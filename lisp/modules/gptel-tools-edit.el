;;; gptel-tools-edit.el --- Async Edit tool for gptel -*- lexical-binding: t; -*-

;; Author: David Wu
;; Version: 1.0.0
;;
;; Async Edit tool implementation with patch mode support.

(require 'cl-lib)
(require 'subr-x)
(require 'seq)

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
  (with-temp-buffer
    (insert text)
    (goto-char (point-min))
    (when (looking-at-p "^ *```\\(diff\\|patch\\)?\\s-*$")
      (delete-line))
    (goto-char (point-max))
    (forward-line -1)
    (when (looking-at-p "^ *```\\s-*$")
      (delete-line))
    (string-trim-right (buffer-string))))

;;; Edit Tool Implementation

(defun my/gptel--agent-edit-async (callback path &optional old-str new-str-or-diff diffp)
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
          (unless (file-readable-p path)
            (error "Error: File or directory %s is not readable" path))
          (unless new-str-or-diff
            (error "Required argument `new_str' missing"))
          (let ((patch-mode (and diffp (not (eq diffp :json-false)))))
            (if (not patch-mode)
                (funcall finish
                         (gptel-agent--edit-files path old-str new-str-or-diff diffp))
              (unless (executable-find "patch")
                (error "Error: Command \"patch\" not available, cannot apply diffs"))
              (let* ((out-buf (generate-new-buffer " *gptel-patch*"))
                     (target (expand-file-name path))
                     (default-directory
                      (if (file-directory-p target)
                          (file-name-as-directory target)
                        (file-name-directory target)))
                     (patch-options '("--forward" "--verbose" "--batch"))
                     (patch-text (my/gptel--agent--strip-diff-fences new-str-or-diff))
                     (patch-text (if (string-suffix-p "\n" patch-text)
                                     patch-text
                                   (concat patch-text "\n"))))
                (with-temp-buffer
                  (insert patch-text)
                  (goto-char (point-min))
                  (when (fboundp 'gptel-agent--fix-patch-headers)
                    (gptel-agent--fix-patch-headers))
                  (setq patch-text (buffer-string)))
                (let ((proc
                       (make-process
                        :name "gptel-patch"
                        :buffer out-buf
                        :command (cons "patch" patch-options)
                        :noquery t
                        :connection-type 'pipe
                        :sentinel
                        (lambda (p _event)
                          (when (memq (process-status p) '(exit signal))
                            (let* ((status (process-exit-status p))
                                   (out (with-current-buffer out-buf (buffer-string))))
                              (when (buffer-live-p out-buf) (kill-buffer out-buf))
                              (if (= status 0)
                                  (funcall finish
                                           (format
                                            "Diff successfully applied to %s.\nPatch command options: %s\nPatch STDOUT:\n%s"
                                            target patch-options (string-trim out)))
                                (funcall finish
                                         (format
                                          "Error: Failed to apply diff to %s (exit status %s).\nPatch command options: %s\nPatch STDOUT:\n%s"
                                          target status patch-options (string-trim out))))))))))
                  (process-put proc 'my/gptel-managed t)
                  (process-send-string proc patch-text)
                  (process-send-eof proc)
                  (run-at-time
                   my/gptel-edit-timeout nil
                   (lambda (p buf)
                     (when (process-live-p p)
                       (ignore-errors (set-process-filter p #'ignore))
                       (ignore-errors (set-process-sentinel p #'ignore))
                       (delete-process p))
                     (when (buffer-live-p buf) (kill-buffer buf))
                     (funcall finish "Error: edit/patch timed out."))
                   proc out-buf))))))
      (error
       (funcall finish (format "Error: %s" (error-message-string err)))))))

;;; Tool Registration

(defun gptel-tools-edit-register ()
  "Register the Edit tool with gptel."
  (when (fboundp 'gptel-make-tool)
    (gptel-make-tool
     :name "Edit"
     :description "Replace text or apply a unified diff (async)."
     :function #'my/gptel--agent-edit-async
     :async t
     :args '((:name "path"
              :type string)
            (:name "old_str"
              :type string
              :optional t)
            (:name "new_str"
              :type string)
            (:name "diff"
              :type boolean
              :optional t))
     :category "gptel-agent"
     :confirm t
     :include t)))

;;; Footer

(provide 'gptel-tools-edit)

;;; gptel-tools-edit.el ends here
