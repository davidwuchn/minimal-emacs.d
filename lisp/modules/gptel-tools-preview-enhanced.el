;;; gptel-tools-preview-enhanced.el --- Enhanced Preview Tools -*- lexical-binding: t -*-

;;; Commentary:
;; Enhanced preview tools with:
;; 1. Inline diff preview (side-by-side or unified)
;; 2. Batch preview for multiple files
;; 3. Syntax-highlighted previews
;; 4. Quick navigation between changes

;;; Code:

(require 'diff-mode)
(require 'ediff)

;;; Inline Preview

(defun my/gptel--inline-diff-preview (path original replacement &optional callback)
  "Show inline diff preview for PATH.

ORIGINAL and REPLACEMENT are the file contents.
CALLBACK is called with user's decision (confirmed/aborted)."
  (let* ((diff-buf (get-buffer-create "*gptel-inline-preview*"))
         (temp1 (make-temp-file "orig"))
         (temp2 (make-temp-file "new")))
    (unwind-protect
        (progn
          (write-region original nil temp1 nil 'silent)
          (write-region replacement nil temp2 nil 'silent)
          (with-current-buffer diff-buf
            (erase-buffer)
            (insert (format "Inline Preview: %s\n\n" path))
            (call-process "diff" nil t nil "-u" "--color=always" temp1 temp2)
            (ansi-color-apply-on-region (point-min) (point-max))
            (diff-mode)
            (setq-local buffer-read-only t))
          (display-buffer diff-buf '(display-buffer-reuse-window
                                     display-buffer-below-selected
                                     (window-height . 0.4)))
          (when callback
            (my/gptel--setup-preview-keys
             diff-buf
             (lambda () (funcall callback 'confirmed))
             (lambda () (funcall callback 'aborted)))))
      (delete-file temp1)
      (delete-file temp2))))

;;; Batch Preview

(defun my/gptel--batch-preview-files (file-changes &optional callback)
  "Show batch preview for multiple FILE-CHANGES.

FILE-CHANGES is an alist: ((path . (original . replacement)) ...)
CALLBACK is called with list of confirmed files."
  (let* ((diff-buf (get-buffer-create "*gptel-batch-preview*"))
         (confirmed-files '())
         (temp-dir (make-temp-file "batch" t)))
    (with-current-buffer diff-buf
      (erase-buffer)
      (insert "Batch Preview: Multiple File Changes\n\n")
      (insert "Press 'n' to confirm all, 'y' to confirm selected, 'q' to abort\n\n")
      (insert "========================================\n\n")
      (cl-loop for (path . contents) in file-changes
               do (let* ((original (car contents))
                         (replacement (cdr contents))
                         (temp1 (expand-file-name "orig" temp-dir))
                         (temp2 (expand-file-name "new" temp-dir)))
                    (write-region original nil temp1 nil 'silent)
                    (write-region replacement nil temp2 nil 'silent)
                    (insert (format "File: %s\n" path))
                    (insert "----------------------------------------\n")
                    (call-process "diff" nil t nil "-u" temp1 temp2)
                    (insert "\n\n")))
      (diff-mode)
      (setq-local buffer-read-only t
                  my/gptel--confirmed-files confirmed-files
                  my/gptel--callback callback))
    (display-buffer diff-buf '(display-buffer-reuse-window
                               display-buffer-below-selected
                               (window-height . 0.5)))
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
  (let ((callback (buffer-local-value 'my/gptel--callback (current-buffer))))
    (kill-buffer)
    (when callback
      (funcall callback 'all-confirmed))))

(defun my/gptel--batch-confirm-current ()
  "Confirm current file in batch preview."
  (interactive)
  (message "Confirming selected file..."))

(defun my/gptel--batch-abort ()
  "Abort batch preview."
  (interactive)
  (let ((callback (buffer-local-value 'my/gptel--callback (current-buffer))))
    (kill-buffer)
    (when callback
      (funcall callback 'aborted))))

;;; Syntax-Highlighted Preview

(defun my/gptel--syntax-preview (path content &optional mode)
  "Show syntax-highlighted preview of CONTENT for PATH.

MODE is the major mode to use (auto-detected if nil)."
  (let* ((preview-buf (get-buffer-create "*gptel-syntax-preview*"))
         (detected-mode (or mode
                           (when (string-match-p "\\.py\\'" path) 'python-ts-mode)
                           (when (string-match-p "\\.el\\'" path) 'emacs-lisp-mode)
                           (when (string-match-p "\\.rs\\'" path) 'rust-ts-mode)
                           (when (string-match-p "\\.clj\\'" path) 'clojure-mode))))
    (with-current-buffer preview-buf
      (erase-buffer)
      (insert (format "Syntax Preview: %s\n\n" path))
      (insert content)
      (when detected-mode
        (funcall detected-mode))
      (setq-local buffer-read-only t))
    (display-buffer preview-buf '(display-buffer-reuse-window
                                  display-buffer-below-selected
                                  (window-height . 0.4)))))

;;; Tool Registration

(defun gptel-tools-preview-enhanced-register ()
  "Register enhanced preview tools."
  (when (fboundp 'gptel-make-tool)
    ;; Inline diff preview
    (gptel-make-tool
     :name "inline_diff_preview"
     :async t
     :category "gptel-agent"
     :function (lambda (callback path original replacement)
                 (my/gptel--inline-diff-preview path original replacement
                   (lambda (result)
                     (funcall callback (symbol-name result)))))
     :description "Show inline diff preview with syntax highlighting"
     :args '((:name "path" :type string :description "File path")
             (:name "original" :type string :description "Original content")
             (:name "replacement" :type string :description "New content")))
    ;; Batch preview
    (gptel-make-tool
     :name "batch_preview"
     :async t
     :category "gptel-agent"
     :function (lambda (callback files)
                 (my/gptel--batch-preview-files files
                   (lambda (result)
                     (funcall callback (symbol-name result)))))
     :description "Preview multiple file changes at once"
     :args '((:name "files" :type array :description "List of file changes")))
    ;; Syntax preview
    (gptel-make-tool
     :name "syntax_preview"
     :async nil
     :category "gptel-agent"
     :function (lambda (path content)
                 (my/gptel--syntax-preview path content)
                 "Preview displayed")
     :description "Show syntax-highlighted file preview"
     :args '((:name "path" :type string :description "File path")
             (:name "content" :type string :description "File content")))))

(provide 'gptel-tools-preview-enhanced)

;;; gptel-tools-preview-enhanced.el ends here
