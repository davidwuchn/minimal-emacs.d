;;; gptel-tools-preview.el --- Preview tools for gptel -*- lexical-binding: t; -*-

;; Author: David Wu
;; Version: 1.0.0
;;
;; Preview tools for file changes and patches.

(require 'cl-lib)
(require 'subr-x)

;;; Customization

(defgroup gptel-tools-preview nil
  "Preview tools for gptel-agent."
  :group 'gptel)

;;; Preview Functions

(defun my/gptel--setup-preview-keys (buffer on-confirm on-abort)
  "Set up local keys in preview BUFFER for confirmation.

ON-CONFIRM and ON-ABORT are called with no arguments when the user
presses n/y or q respectively."
  (with-current-buffer buffer
    (let ((map (make-sparse-keymap)))
      (set-keymap-parent map (current-local-map))
      (define-key map (kbd "n") (lambda () (interactive) (kill-buffer buffer) (funcall on-confirm)))
      (define-key map (kbd "y") (lambda () (interactive) (kill-buffer buffer) (funcall on-confirm)))
      (define-key map (kbd "q") (lambda () (interactive) (kill-buffer buffer) (funcall on-abort)))
      (use-local-map map))))

(defun my/gptel--preview-enqueue (buffer path original replacement callback)
  "Enqueue a file preview for BUFFER.

Shows the diff between ORIGINAL and REPLACEMENT for PATH.
CALLBACK is called when user confirms or aborts."
  (let* ((parent-fsm (buffer-local-value 'gptel--fsm-last buffer))
         (wrapped-cb
          (lambda (result)
            (when (buffer-live-p buffer)
              (with-current-buffer buffer
                (setq-local gptel--fsm-last parent-fsm)))
            (setq-local gptel--fsm-last parent-fsm)
            (funcall callback result)))
         (diff-buf (get-buffer-create "*gptel-preview*"))
         (temp1 (make-temp-file "orig"))
         (temp2 (make-temp-file "new"))
         (diff-output
          (progn
            (write-region original nil temp1 nil 'silent)
            (write-region replacement nil temp2 nil 'silent)
            (with-temp-buffer
              (call-process "diff" nil t nil "-u" temp1 temp2)
              (buffer-string)))))
    (unwind-protect
        (progn
          (with-current-buffer diff-buf
            (erase-buffer)
            (insert (format "Preview: %s\n\n" path))
            (insert diff-output)
            (diff-mode))
          (display-buffer diff-buf)
          (my/gptel--setup-preview-keys
           diff-buf
           (lambda () (funcall wrapped-cb "Preview confirmed."))
           (lambda () (funcall wrapped-cb "Preview aborted."))))
      (delete-file temp1)
      (delete-file temp2))))

(defun my/gptel--preview-patch-async (patch buffer callback on-confirm on-abort header)
  "Show patch preview asynchronously.

PATCH is the unified diff content.
BUFFER is the originating buffer.
CALLBACK is called with the result.
ON-CONFIRM and ON-ABORT are called based on user action.
HEADER is the prompt to show."
  (let* ((parent-fsm (buffer-local-value 'gptel--fsm-last buffer))
         (wrapped-cb
          (lambda (result)
            (when (buffer-live-p buffer)
              (with-current-buffer buffer
                (setq-local gptel--fsm-last parent-fsm)))
            (setq-local gptel--fsm-last parent-fsm)
            (funcall callback result)))
         (diff-buf (get-buffer-create "*gptel-patch-preview*")))
    (with-current-buffer diff-buf
      (erase-buffer)
      (insert header "\n\n")
      (insert patch)
      (diff-mode))
    (display-buffer diff-buf)
    (my/gptel--setup-preview-keys
     diff-buf
     (lambda () (funcall on-confirm wrapped-cb))
     (lambda () (funcall on-abort wrapped-cb)))))

;;; Tool Registration

(defun gptel-tools-preview-register ()
  "Register preview tools with gptel."
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
                     (my/gptel--preview-enqueue
                      (current-buffer) path orig new callback))))
     :description "Preview file changes step-by-step using magit (or diff-mode fallback)."
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
                 (my/gptel--preview-patch-async
                  patch
                  (current-buffer)
                  callback
                  ;; on-confirm
                  (lambda (cb) (funcall cb "Patch reviewed. Not applied."))
                  ;; on-abort
                  (lambda (cb) (funcall cb "Patch preview aborted."))
                  ;; header
                  "Patch preview — n reviewed    q abort"))
     :description "Preview a unified diff for review without applying it."
     :args '((:name "patch"
              :type string
              :description "Unified diff content"))
     :confirm t)))

;;; Footer

(provide 'gptel-tools-preview)

;;; gptel-tools-preview.el ends here
