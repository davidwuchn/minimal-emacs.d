;;; gptel-tools-edit.el --- Async Edit tool for gptel -*- lexical-binding: t; -*-

;; Author: David Wu
;; Version: 1.0.0
;;
;; Async Edit tool implementation with patch mode support.

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'gptel-tools-preview)

;;; Customization

(defgroup gptel-tools-edit nil
  "Async Edit tool for gptel-agent."
  :group 'gptel)

(defcustom my/gptel-edit-timeout 30
  "Seconds before Edit (patch mode) tool is force-stopped."
  :type 'integer
  :group 'gptel-tools-edit)

;;; Helper Functions

(defun my/gptel--agent--strip-diff-fences (text)
  "Strip leading/trailing fenced code block markers from TEXT, if present."
  (let ((result text))
    ;; Strip opening fence (```diff, ```patch, or ```)
    (when (string-match-p "^\\s-*```\\(diff\\|patch\\)?\\s-*" result)
      (setq result (replace-regexp-in-string "^\\s-*```\\(diff\\|patch\\)?\\s-*\\n?" "" result)))
    ;; Strip closing fence (``` at end of string, with optional whitespace)
    (when (string-match-p "```\\s-*\\'" result)
      (setq result (replace-regexp-in-string "\\n?\\s-*```\\s-*\\'" "" result)))
    (string-trim result)))

;;; Edit Tool Implementation

(defun my/gptel--agent-edit-async (callback file_path &optional old_str new_str diffp)
  "Async replacement for gptel-agent's `Edit' tool.

This is only truly async/interruptible for patch mode (DIFFP true).
For simple string replacements it executes synchronously.

CALLBACK is called exactly once unless the buffer has been aborted."
  (let* ((origin (current-buffer))
         (gen my/gptel--abort-generation)
         (done nil)
         (finish
          (lambda (result)
            (unless done
              (setq done t)
              ;; Always deliver error results so the FSM doesn't hang.
              (when (or (and (stringp result) (string-prefix-p "Error" result))
                         (and (buffer-live-p origin)
                              (with-current-buffer origin
                                (= gen my/gptel--abort-generation))))
                (funcall callback result))))))
    (condition-case err
        (progn
          (unless (file-readable-p file_path)
            (error "File or directory %s is not readable" file_path))
          (unless new_str
            (error "Required argument `new_str' missing"))
          (let ((patch-mode (and diffp (not (eq diffp :json-false)))))
            (if (not patch-mode)
                (funcall finish
                         (gptel-agent--edit-files file_path old_str new_str diffp))
              (unless (executable-find "patch")
                (error "Command \"patch\" not available, cannot apply diffs"))
              (let* ((target (expand-file-name file_path))
                     (patch-text (my/gptel--agent--strip-diff-fences new_str))
                     (patch-text (if (string-suffix-p "\n" patch-text)
                                     patch-text
                                   (concat patch-text "\n"))))
                (with-temp-buffer
                  (insert patch-text)
                  (goto-char (point-min))
                  (when (fboundp 'gptel-agent--fix-patch-headers)
                    (gptel-agent--fix-patch-headers))
                  (setq patch-text (buffer-string)))
                (my/gptel--preview-patch-async
                 patch-text (current-buffer) finish
                 (lambda (cb) (my/gptel--agent-edit-apply-patch cb target patch-text))
                 (lambda (cb) (funcall cb "Error: Preview aborted by user."))
                 "Edit patch preview — n apply    q abort"
                 "Edit")))))
      (error
       (funcall finish (format "Error: %s" (error-message-string err)))))))

(defun my/gptel--agent-edit-apply-patch (callback target patch-text)
  "Apply PATCH-TEXT to TARGET file asynchronously.

CALLBACK is called with the result.
This is the core patch application logic for preview integration."
  (let* ((out-buf (generate-new-buffer " *gptel-patch*"))
         (default-directory (file-name-directory target))
         ;; Use -p1 to strip a/ and b/ prefixes from git diff output
         (patch-options '("-p1" "--forward" "--verbose" "--batch"))
         (cb-called nil)
         (proc
          (make-process
           :name "gptel-patch"
           :buffer out-buf
           :command (cons "patch" patch-options)
           :noquery t
           :connection-type 'pipe
           :sentinel
           (lambda (p _event)
             (when (memq (process-status p) '(exit signal))
               (unless cb-called
                 (setq cb-called t)
                 (let* ((status (process-exit-status p))
                        (out (with-current-buffer out-buf (buffer-string))))
                   (when (buffer-live-p out-buf) (kill-buffer out-buf))
                   (if (= status 0)
                       (funcall callback
                                (format "Diff successfully applied to %s.\nPatch STDOUT:\n%s"
                                        target (string-trim out)))
                     (funcall callback
                              (format "Error: Failed to apply diff to %s (exit %s).\nPatch STDOUT:\n%s"
                                      target status (string-trim out)))))))))))
    (process-put proc 'my/gptel-managed t)
    (process-send-string proc patch-text)
    (process-send-eof proc)
    (run-at-time my/gptel-edit-timeout nil
                 (lambda (p buf)
                   (unless cb-called
                     (when (process-live-p p)
                       (message "gptel-edit: patch timed out, cleaning up process")
                       (ignore-errors (set-process-filter p #'ignore))
                       (ignore-errors (set-process-sentinel p #'ignore))
                       (delete-process p))
                     (when (buffer-live-p buf) (kill-buffer buf))
                     (setq cb-called t)
                     (funcall callback "Error: edit/patch timed out.")))
                 proc out-buf)))

;;; Tool Registration

(defun gptel-tools-edit-register ()
  "Register the Edit tool with gptel."
  (unless (executable-find "patch")
    (when (fboundp 'display-warning)
      (display-warning 'gptel-tools "Executable `patch' not found. Edit tool will only support exact string replacement." :warning)))
  (when (fboundp 'gptel-make-tool)
    (gptel-make-tool
     :name "Edit"
     :description "Replace text or apply a unified diff (async)."
     :function #'my/gptel--agent-edit-async
     :async t
     :args '((:name "file_path"
                    :type string
                    :description "Path to the file to edit")
             (:name "old_str"
                    :type string
                    :optional t
                    :description "Text to replace (omit for patch mode)")
             (:name "new_str"
                    :type string
                    :description "Replacement text or unified diff")
             (:name "diffp"
                    :type boolean
                    :optional t
                    :description "Set true if new_str is a diff"))
     :category "gptel-agent"
     :confirm t
     :include t)))

;;; Footer

(provide 'gptel-tools-edit)

;;; gptel-tools-edit.el ends here
