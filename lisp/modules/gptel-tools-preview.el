;;; gptel-tools-preview.el --- Preview tools for gptel -*- lexical-binding: t; -*-

;; Author: David Wu
;; Version: 2.0.0
;;
;; Unified preview tools for file changes, patches, batch operations,
;; and syntax-highlighted previews.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'diff-mode)
(require 'ediff)
(require 'ansi-color)

;;; Customization

(defgroup gptel-tools-preview nil
  "Preview tools for gptel-agent."
  :group 'gptel)

(defcustom gptel-tools-preview-window-height 0.4
  "Height of preview windows as fraction of frame."
  :type 'float
  :group 'gptel-tools-preview)

(defcustom gptel-tools-preview-use-syntax-highlighting t
  "Whether to enable syntax highlighting in previews."
  :type 'boolean
  :group 'gptel-tools-preview)

;;; Core Preview Functions

(defun my/gptel--setup-preview-keys (buffer on-confirm on-abort)
  "Set up local keys in preview BUFFER for confirmation.

ON-CONFIRM and ON-ABORT are called with no arguments when the user
presses n/y or q respectively."
  (with-current-buffer buffer
    (let ((map (make-sparse-keymap)))
      (set-keymap-parent map (current-local-map))
      (define-key map (kbd "n") (lambda () (interactive) (funcall on-confirm) (kill-buffer buffer)))
      (define-key map (kbd "y") (lambda () (interactive) (funcall on-confirm) (kill-buffer buffer)))
      (define-key map (kbd "q") (lambda () (interactive) (funcall on-abort) (kill-buffer buffer)))
      (use-local-map map))))

(defun my/gptel--create-diff-buffer (name header &optional content mode)
  "Create a diff buffer named NAME with HEADER and CONTENT.

MODE is the major mode to activate (defaults to diff-mode).
Returns the buffer."
  (let ((buf (get-buffer-create name)))
    (with-current-buffer buf
      (erase-buffer)
      (insert header "\n\n")
      (when content
        (insert content))
      (when mode
        (funcall mode))
      (setq-local buffer-read-only t))
    buf))

(defun my/gptel--display-preview-buffer (buffer &optional height)
  "Display BUFFER with HEIGHT as fraction of frame.

Returns the window displaying the buffer."
  (display-buffer buffer
                  `(display-buffer-reuse-window
                    display-buffer-below-selected
                    (window-height . ,(or height gptel-tools-preview-window-height)))))

(defun my/gptel--run-diff (temp1 temp2 &optional color)
  "Run diff between TEMP1 and TEMP2 files.

If COLOR is non-nil, adds --color=always.
Returns the diff output string."
  (with-temp-buffer
    (let ((args '("-u")))
      (when color
        (setq args (append args '("--color=always"))))
      (apply #'call-process "diff" nil t nil (append args (list temp1 temp2))))
    (buffer-string)))

;;; File Change Preview

(defun my/gptel--preview-file-change (buffer path original replacement callback)
  "Preview file change for BUFFER.

Shows diff between ORIGINAL and REPLACEMENT for PATH.
CALLBACK is called when user confirms or aborts."
  (let* ((parent-fsm (buffer-local-value 'gptel--fsm-last buffer))
         (cb-called nil)
         (wrapped-cb
          (lambda (result)
            (unless cb-called
              (setq cb-called t)
              (when (buffer-live-p buffer)
                (with-current-buffer buffer
                  (setq-local gptel--fsm-last parent-fsm)))
              (setq-local gptel--fsm-last parent-fsm)
              (funcall callback result))))
         (temp1 (make-temp-file "orig"))
         (temp2 (make-temp-file "new"))
         (diff-output
          (progn
            (write-region original nil temp1 nil 'silent)
            (write-region replacement nil temp2 nil 'silent)
            (my/gptel--run-diff temp1 temp2))))
    (unwind-protect
        (let ((diff-buf (my/gptel--create-diff-buffer
                         "*gptel-preview*"
                         (format "Preview: %s" path)
                         diff-output
                         #'diff-mode)))
          (add-hook 'kill-buffer-hook
                    (lambda () (funcall wrapped-cb "Preview aborted."))
                    nil t)
          (my/gptel--display-preview-buffer diff-buf)
          (my/gptel--setup-preview-keys
           diff-buf
           (lambda () (funcall wrapped-cb "Preview confirmed."))
           (lambda () (funcall wrapped-cb "Preview aborted."))))
      (delete-file temp1)
      (delete-file temp2))))

;;; Patch Preview

(defun my/gptel--preview-patch (patch buffer callback header)
  "Show patch preview.

PATCH is the unified diff content.
BUFFER is the originating buffer.
CALLBACK is called with the result.
HEADER is the prompt to show."
  (let* ((parent-fsm (buffer-local-value 'gptel--fsm-last buffer))
         (cb-called nil)
         (wrapped-cb
          (lambda (result)
            (unless cb-called
              (setq cb-called t)
              (when (buffer-live-p buffer)
                (with-current-buffer buffer
                  (setq-local gptel--fsm-last parent-fsm)))
              (setq-local gptel--fsm-last parent-fsm)
              (funcall callback result))))
         (diff-buf (my/gptel--create-diff-buffer
                    "*gptel-patch-preview*"
                    header
                    patch
                    #'diff-mode)))
    (add-hook 'kill-buffer-hook
              (lambda () (funcall callback "Preview aborted."))
              nil t)
    (my/gptel--display-preview-buffer diff-buf)
    (my/gptel--setup-preview-keys
     diff-buf
     (lambda () (funcall wrapped-cb "Patch reviewed. Not applied."))
     (lambda () (funcall wrapped-cb "Patch preview aborted.")))))

(defun my/gptel--preview-patch-async (patch buffer callback on-confirm on-abort header)
  "Show patch preview asynchronously for ApplyPatch tool.

PATCH is the unified diff content.
BUFFER is the originating buffer.
CALLBACK is called with the result.
ON-CONFIRM is called with wrapped callback when user confirms.
ON-ABORT is called with wrapped callback when user aborts.
HEADER is the prompt to show."
  (let* ((parent-fsm (buffer-local-value 'gptel--fsm-last buffer))
         (cb-called nil)
         (wrapped-cb
          (lambda (result)
            (unless cb-called
              (setq cb-called t)
              (when (buffer-live-p buffer)
                (with-current-buffer buffer
                  (setq-local gptel--fsm-last parent-fsm)))
              (setq-local gptel--fsm-last parent-fsm)
              (funcall callback result))))
         (diff-buf (my/gptel--create-diff-buffer
                    "*gptel-patch-preview*"
                    header
                    patch
                    #'diff-mode)))
    (with-current-buffer diff-buf
      (add-hook 'kill-buffer-hook
                (lambda () (funcall on-abort wrapped-cb))
                nil t))
    (my/gptel--display-preview-buffer diff-buf)
    (my/gptel--setup-preview-keys
     diff-buf
     (lambda () (funcall on-confirm wrapped-cb))
     (lambda () (funcall on-abort wrapped-cb)))))

;;; Inline Diff Preview

(defun my/gptel--inline-diff-preview (path original replacement callback)
  "Show inline diff preview for PATH.

ORIGINAL and REPLACEMENT are the file contents.
CALLBACK is called with user's decision (confirmed/aborted)."
  (let* ((temp1 (make-temp-file "orig"))
         (temp2 (make-temp-file "new"))
         (diff-output
          (progn
            (write-region original nil temp1 nil 'silent)
            (write-region replacement nil temp2 nil 'silent)
            (my/gptel--run-diff temp1 temp2 t)))
         (diff-buf (my/gptel--create-diff-buffer
                    "*gptel-inline-preview*"
                    (format "Inline Preview: %s" path)
                    nil
                    #'diff-mode)))
    (unwind-protect
        (progn
          (with-current-buffer diff-buf
            (insert diff-output)
            (when gptel-tools-preview-use-syntax-highlighting
              (ansi-color-apply-on-region (point-min) (point-max))))
          (my/gptel--display-preview-buffer diff-buf)
          (my/gptel--setup-preview-keys
           diff-buf
           (lambda () (funcall callback "Preview confirmed"))
           (lambda () (funcall callback "Preview aborted"))))
      (delete-file temp1)
      (delete-file temp2))))

;;; Batch Preview

(defvar-local my/gptel--batch-confirmed-files nil
  "List of confirmed files in batch preview.")

(defvar-local my/gptel--batch-callback nil
  "Callback for batch preview.")

(defvar-local my/gptel--batch-file-list nil
  "List of file paths in batch preview.")

(defun my/gptel--batch-preview-files (file-changes callback)
  "Show batch preview for multiple FILE-CHANGES.

FILE-CHANGES is an alist: ((path . (original . replacement)) ...)
CALLBACK is called with list of confirmed files."
  (let* ((temp-dir (make-temp-file "batch" t))
         (file-list (mapcar #'car file-changes))
         (diff-buf (my/gptel--create-diff-buffer
                    "*gptel-batch-preview*"
                    (concat "Batch Preview: Multiple File Changes\n\n"
                            "Press 'n' to confirm all, 'y' to confirm current file, 'q' to abort\n\n"
                            "========================================\n\n"))))
    (with-current-buffer diff-buf
      (setq-local my/gptel--batch-confirmed-files '()
                  my/gptel--batch-callback callback
                  my/gptel--batch-file-list file-list)
      (cl-loop for (path . contents) in file-changes
               do (let* ((original (car contents))
                         (replacement (cdr contents))
                         (temp1 (expand-file-name "orig" temp-dir))
                         (temp2 (expand-file-name "new" temp-dir)))
                    (write-region original nil temp1 nil 'silent)
                    (write-region replacement nil temp2 nil 'silent)
                    (insert (format "File: %s\n" path))
                    (insert "----------------------------------------\n")
                    (insert (my/gptel--run-diff temp1 temp2))
                    (insert "\n\n")))
      (diff-mode)
      (goto-char (point-min)))
    (my/gptel--display-preview-buffer diff-buf 0.5)
    (my/gptel--setup-batch-preview-keys diff-buf)))

(defun my/gptel--setup-batch-preview-keys (buffer)
  "Set up batch preview keys in BUFFER."
  (with-current-buffer buffer
    (let ((map (make-sparse-keymap)))
      (set-keymap-parent map (current-local-map))
      (define-key map (kbd "n") 'my/gptel--batch-confirm-all)
      (define-key map (kbd "y") 'my/gptel--batch-confirm-current)
      (define-key map (kbd "q") 'my/gptel--batch-abort)
      (use-local-map map))))

(defun my/gptel--batch-confirm-all ()
  "Confirm all files in batch preview."
  (interactive)
  (let ((callback my/gptel--batch-callback))
    (kill-buffer)
    (when callback
      (funcall callback "All files confirmed"))))

(defun my/gptel--batch-confirm-current ()
  "Confirm current file in batch preview."
  (interactive)
  (let ((callback my/gptel--batch-callback)
        (file-list my/gptel--batch-file-list))
    (save-excursion
      (beginning-of-line)
      (if (re-search-backward "^File: \\(.+\\)$" nil t)
          (let* ((current-file (match-string 1))
                 (confirmed my/gptel--batch-confirmed-files))
            (unless (member current-file confirmed)
              (setq my/gptel--batch-confirmed-files
                    (cons current-file confirmed)))
            (message "Confirmed: %s (%d/%d)" current-file
                     (length my/gptel--batch-confirmed-files)
                     (length file-list)))
        (message "No file header found")))))

(defun my/gptel--batch-abort ()
  "Abort batch preview."
  (interactive)
  (let ((callback my/gptel--batch-callback))
    (kill-buffer)
    (when callback
      (funcall callback "Preview aborted"))))

;;; Syntax-Highlighted Preview

(defun my/gptel--detect-major-mode (path)
  "Detect major mode for PATH."
  (cond
   ((string-match-p "\\.py\\'" path) 'python-ts-mode)
   ((string-match-p "\\.el\\'" path) 'emacs-lisp-mode)
   ((string-match-p "\\.rs\\'" path) 'rust-ts-mode)
   ((string-match-p "\\.clj\\'" path) 'clojure-mode)
   ((string-match-p "\\.js\\'" path) 'js-mode)
   ((string-match-p "\\.ts\\'" path) 'typescript-mode)
   ((string-match-p "\\.rb\\'" path) 'ruby-mode)
   ((string-match-p "\\.go\\'" path) 'go-mode)
   ((string-match-p "\\.java\\'" path) 'java-mode)
   ((string-match-p "\\.c\\'" path) 'c-mode)
   ((string-match-p "\\.cpp\\'" path) 'c++-mode)
   ((string-match-p "\\.h\\'" path) 'c-mode)
   ((string-match-p "\\.css\\'" path) 'css-mode)
   ((string-match-p "\\.html?\\'" path) 'html-mode)
   ((string-match-p "\\.json\\'" path) 'json-mode)
   ((string-match-p "\\.yaml\\'" path) 'yaml-mode)
   ((string-match-p "\\.toml\\'" path) 'toml-mode)
   ((string-match-p "\\.md\\'" path) 'markdown-mode)
   ((string-match-p "\\.org\\'" path) 'org-mode)
   (t nil)))

(defun my/gptel--syntax-preview (path content &optional mode)
  "Show syntax-highlighted preview of CONTENT for PATH.

MODE is the major mode to use (auto-detected if nil)."
  (let* ((detected-mode (or mode (my/gptel--detect-major-mode path)))
         (preview-buf (my/gptel--create-diff-buffer
                       "*gptel-syntax-preview*"
                       (format "Syntax Preview: %s" path)
                       content
                       detected-mode)))
    (my/gptel--display-preview-buffer preview-buf)
    (with-current-buffer preview-buf
      (goto-char (point-min)))))

;;; Tool Registration

(defun gptel-tools-preview-register ()
  "Register all preview tools with gptel."
  (when (fboundp 'gptel-make-tool)
    ;; preview_file_change
    (gptel-make-tool
     :name "preview_file_change"
     :async t
     :category "gptel-agent"
     :function (lambda (callback path &optional original replacement)
                 (let* ((full-path (expand-file-name path))
                        (orig (or original
                                  (when (file-readable-p full-path)
                                    (with-temp-buffer
                                      (insert-file-contents full-path)
                                      (buffer-string)))))
                        (new (or replacement "")))
                   (if (not orig)
                       (funcall callback
                                (format "Error: Cannot read original content for %s"
                                        path))
                     (my/gptel--preview-file-change
                      (current-buffer) path orig new callback))))
     :description "Preview file changes with diff view."
     :args '((:name "path"
              :type string
              :description "Target file path")
            (:name "original"
              :type string
              :description "Original content (optional)"
              :optional t)
            (:name "replacement"
              :type string
              :description "Replacement content"))
     :confirm t)

    ;; preview_patch
    (gptel-make-tool
     :name "preview_patch"
     :async t
     :category "gptel-agent"
     :function (lambda (callback patch)
                 (my/gptel--preview-patch
                  patch
                  (current-buffer)
                  callback
                  "Patch preview — n reviewed    q abort"))
     :description "Preview a unified diff for review without applying it."
     :args '((:name "patch"
              :type string
              :description "Unified diff content"))
     :confirm t)

    ;; preview_inline
    (gptel-make-tool
     :name "preview_inline"
     :async t
     :category "gptel-agent"
     :function (lambda (callback path original replacement)
                 (my/gptel--inline-diff-preview path original replacement callback))
     :description "Show inline diff preview with syntax highlighting and color."
     :args '((:name "path" :type string :description "File path")
             (:name "original" :type string :description "Original content")
             (:name "replacement" :type string :description "New content")))

    ;; preview_batch
    (gptel-make-tool
     :name "preview_batch"
     :async t
     :category "gptel-agent"
     :function (lambda (callback files)
                 (my/gptel--batch-preview-files files callback))
     :description "Preview multiple file changes at once with batch confirmation."
     :args '((:name "files"
              :type array
              :description "List of file changes: [{path, original, replacement}]")))

    ;; preview_syntax
    (gptel-make-tool
     :name "preview_syntax"
     :async nil
     :category "gptel-agent"
     :function (lambda (path content)
                 (my/gptel--syntax-preview path content)
                 "Preview displayed")
     :description "Show syntax-highlighted file preview with auto-detected mode."
     :args '((:name "path" :type string :description "File path")
             (:name "content" :type string :description "File content")))))

;;; Footer

(provide 'gptel-tools-preview)

;;; gptel-tools-preview.el ends here
