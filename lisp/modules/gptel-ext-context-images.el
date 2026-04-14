;;; gptel-ext-context-images.el --- Image context management for gptel -*- no-byte-compile: t; lexical-binding: t; -*-

;; Author: David Wu
;; Version: 1.0.0
;;
;; Image handling for gptel context:
;; - Auto-convert images to WebP at insertion time
;; - Token estimation for images
;; - Smart image trimming based on relevance

;;; Code:

(require 'cl-lib)
(require 'gptel)

(declare-function gptel-context--add-binary-file "gptel-context")
(defvar gptel-context)

;;; Customization

(defgroup my/gptel-context-images nil
  "Image management for gptel context."
  :group 'gptel)

(defcustom my/gptel-auto-convert-images t
  "When non-nil, automatically convert images to WebP before adding to context.
WebP provides better compression (25-35% smaller) reducing API payload size."
  :type 'boolean
  :group 'my/gptel-context-images)

(defcustom my/gptel-max-context-images 10
  "Maximum number of images to keep in context.
Older/least-used images are trimmed first when exceeded.
Set to nil for unlimited."
  :type '(choice (const :tag "Unlimited" nil) integer)
  :group 'my/gptel-context-images)

(defcustom my/gptel-image-token-estimate 1000
  "Estimated tokens per image for context window calculations.
This is a simple heuristic. Actual tokens vary by model:
- OpenAI: ~85 tokens per 512x512 tile
- Anthropic: based on dimensions
- Gemini: based on dimensions

Default 1000 is conservative for typical images."
  :type 'integer
  :group 'my/gptel-context-images)

(defcustom my/gptel-image-convert-quality 85
  "WebP quality for image conversion (0-100).
Higher = better quality, larger files.
85 is a good balance for screenshots and photos."
  :type 'integer
  :group 'my/gptel-context-images)

(defcustom my/gptel-image-max-dimensions 1024
  "Maximum image dimensions (width or height) in pixels.
Larger images are resized to fit within this limit.
This reduces token count and API payload.
Set to nil to disable resizing."
  :type '(choice (const :tag "No resize" nil) integer)
  :group 'my/gptel-context-images)

(defcustom my/gptel-image-temp-dir
  (expand-file-name "gptel-images/" temporary-file-directory)
  "Directory for converted images."
  :type 'directory
  :group 'my/gptel-context-images)

;;; Image Conversion

(defun my/gptel--image-convertible-p (path)
  "Return non-nil if PATH is an image that can be converted."
  (let ((ext (downcase (or (file-name-extension path) ""))))
    (member ext '("png" "jpg" "jpeg" "gif" "bmp" "tiff" "tif" "heic" "heif" "webp"))))

(defun my/gptel--convert-image (path)
  "Convert image at PATH to WebP using ImageMagick.
Returns the path to the converted file, or the original PATH on failure."
  (unless (file-exists-p path)
    (error "Image file not found: %s" path))
  (let* ((base-name (file-name-base path))
         (converted-path (expand-file-name
                          (concat base-name ".webp")
                          my/gptel-image-temp-dir)))
    (make-directory my/gptel-image-temp-dir t)
    (let* ((resize-arg (when my/gptel-image-max-dimensions
                         (format "%dx%d>" my/gptel-image-max-dimensions my/gptel-image-max-dimensions)))
           (args (delq nil
                       (list path
                             "-quality" (number-to-string my/gptel-image-convert-quality)
                             (and resize-arg "-resize")
                             resize-arg
                             converted-path)))
           (result (apply #'call-process "magick" nil nil nil args)))
      (if (and (numberp result) (= result 0) (file-exists-p converted-path))
          converted-path
        (message "[gptel-images] Conversion failed for %s, using original" path)
        path))))

(defun my/gptel--get-image-dimensions (path)
  "Get image dimensions (width . height) for PATH using ImageMagick identify.
Returns nil if unable to determine."
  (when (file-exists-p path)
    (with-temp-buffer
      (when (= 0 (call-process "magick" nil t nil "identify" "-format" "%w %h" path))
        (goto-char (point-min))
        (when (looking-at "\\([0-9]+\\) \\([0-9]+\\)")
          (cons (string-to-number (match-string 1))
                (string-to-number (match-string 2))))))))

(defun my/gptel--estimate-image-tokens (path)
  "Estimate token count for image at PATH.
Uses simple heuristic unless dimensions are available."
  (let ((dims (my/gptel--get-image-dimensions path)))
    (if dims
        (let* ((width (car dims))
               (height (cdr dims))
               (max-dim (max width height))
               (tiles (ceiling (/ (float max-dim) 512.0)))
               (tokens-per-tile 85))
          (* tiles tiles tokens-per-tile))
      my/gptel-image-token-estimate)))

;;; Token Counting

(defun my/gptel--count-context-image-tokens ()
  "Count total image tokens in current `gptel-context'.
Iterates media entries, estimates per-image token cost."
  (cl-loop for entry in gptel-context
           for (path . props) = (if (consp entry) entry (list entry))
           when (and (stringp path) (plist-get props :mime))
           sum (or (plist-get props :tokens)
                   my/gptel-image-token-estimate)))

(defun my/gptel--context-image-count ()
  "Return the number of images in current `gptel-context'."
  (cl-loop for entry in gptel-context
           for (path . props) = (if (consp entry) entry (list entry))
           when (and (stringp path) (plist-get props :mime))
           count t))

;;; Metadata Tracking

(defun my/gptel--enhance-image-metadata (path props)
  "Add metadata to image context entry.
PROPS is the existing plist. Returns enhanced plist."
  (let* ((tokens (my/gptel--estimate-image-tokens path))
         (dims (my/gptel--get-image-dimensions path))
         (enhanced (copy-sequence props)))
    (plist-put enhanced :added-time (current-time))
    (plist-put enhanced :usage-count 0)
    (plist-put enhanced :tokens tokens)
    (when dims
      (plist-put enhanced :width (car dims))
      (plist-put enhanced :height (cdr dims)))
    enhanced))

(defun my/gptel--convert-image-on-add (orig-fn path)
  "Advice around `gptel-context--add-binary-file' to convert images.
Adds metadata for image context entries."
  (let* ((is-image (my/gptel--image-convertible-p path))
         (converted-path (if (and is-image my/gptel-auto-convert-images)
                             (my/gptel--convert-image path)
                           path))
         (mime-type (or (mailcap-file-name-to-mime-type converted-path)
                        "application/octet-stream"))
         (is-media (string-prefix-p "image/" mime-type)))
    (if is-media
        (let* ((existing-entry (cl-find-if (lambda (e)
                                             (equal (if (consp e) (car e) e) converted-path))
                                           gptel-context))
               (existing-props (and existing-entry (consp existing-entry) (cdr existing-entry)))
               (enhanced-props (my/gptel--enhance-image-metadata converted-path
                                          (or existing-props `(:mime ,mime-type)))))
          (cl-pushnew (cons converted-path enhanced-props) gptel-context :test #'equal))
      (funcall orig-fn path))))

(advice-add 'gptel-context--add-binary-file :around #'my/gptel--convert-image-on-add)

;;; Image Trimming

(defun my/gptel--sort-images-by-relevance ()
  "Sort gptel-context images by relevance (most recent first).
Returns list of (path . props) for images only."
  (let ((images (cl-loop for entry in gptel-context
                         for (path . props) = (if (consp entry) entry (list entry))
                         when (and (stringp path) (plist-get props :mime))
                         collect (cons path props))))
    (sort images
          (lambda (a b)
            (let* ((time-a (or (plist-get (cdr a) :added-time) 0))
                   (time-b (or (plist-get (cdr b) :added-time) 0))
                   (usage-a (or (plist-get (cdr a) :usage-count) 0))
                   (usage-b (or (plist-get (cdr b) :usage-count) 0)))
              (if (= usage-a usage-b)
                  (time-less-p time-b time-a)
                (> usage-a usage-b)))))))

(defun my/gptel--trim-context-images (&optional keep-count)
  "Trim images from `gptel-context' to KEEP-COUNT.
Prefers keeping most recently used images.
Returns number of images removed."
  (let* ((keep (or keep-count my/gptel-max-context-images 999))
         (images (my/gptel--sort-images-by-relevance))
         (total (length images))
         (removed 0))
    (when (and my/gptel-max-context-images (> total keep))
      (let ((to-remove (nthcdr keep images)))
        (dolist (img to-remove)
          (setq gptel-context
                (cl-remove-if (lambda (e)
                                (equal (if (consp e) (car e) e) (car img)))
                              gptel-context))
          (cl-incf removed))
        (when (> removed 0)
          (message "[gptel-images] Trimmed %d image(s), keeping %d" removed keep))))
    removed))

(defun my/gptel--trim-oldest-images (bytes-to-save)
  "Trim oldest images to save approximately BYTES-TO-SAVE bytes.
Returns actual bytes saved."
  (if (not (and (numberp bytes-to-save) (> bytes-to-save 0)))
      0
    (let* ((images (my/gptel--sort-images-by-relevance))
           (bytes-saved 0)
           (trimmed 0))
      (dolist (img images)
        (when (and (< bytes-saved bytes-to-save)
                   (file-exists-p (car img)))
          (let* ((path (car img))
                 (size (file-attribute-size (file-attributes path))))
            (setq gptel-context
                  (cl-remove-if (lambda (e)
                                   (equal (if (consp e) (car e) e) path))
                                 gptel-context))
            (cl-incf bytes-saved (or size 0))
            (cl-incf trimmed))))
      (when (> trimmed 0)
        (message "[gptel-images] Trimmed %d image(s) (~%dKB)" trimmed (/ bytes-saved 1024)))
      bytes-saved)))

;;; Context Image Info

(defun my/gptel-show-context-images ()
  "Show info about images in current gptel context."
  (interactive)
  (let* ((images (my/gptel--sort-images-by-relevance))
         (total-tokens (my/gptel--count-context-image-tokens))
         (total-count (length images)))
    (if (= total-count 0)
        (message "No images in context")
      (let ((buf (get-buffer-create "*gptel-images*")))
        (with-current-buffer buf
          (erase-buffer)
          (insert (format "Images in context: %d (est. %d tokens)\n\n" total-count total-tokens))
          (dolist (img images)
            (let* ((path (car img))
                   (props (cdr img))
                   (tokens (or (plist-get props :tokens) my/gptel-image-token-estimate))
                   (width (plist-get props :width))
                   (height (plist-get props :height))
                   (added (plist-get props :added-time)))
              (insert (format "  %s\n" (file-name-nondirectory path)))
              (when (and width height)
                (insert (format "    Dimensions: %dx%d\n" width height)))
              (insert (format "    Tokens: ~%d\n" tokens))
              (when added
                (insert (format "    Added: %s\n" (format-time-string "%Y-%m-%d %H:%M" added))))
              (insert "\n")))
          (goto-char (point-min)))
        (display-buffer buf)))))

(provide 'gptel-ext-context-images)
;;; gptel-ext-context-images.el ends here