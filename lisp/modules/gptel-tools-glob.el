;;; gptel-tools-glob.el --- Async Glob tool for gptel -*- lexical-binding: t; -*-

;; Author: David Wu
;; Version: 1.0.0
;;
;; Async Glob tool implementation with timeout and result truncation.

(require 'cl-lib)
(require 'subr-x)
(require 'seq)

;;; Customization

(defgroup gptel-tools-glob nil
  "Async Glob tool for gptel-agent."
  :group 'gptel)

(defcustom my/gptel-glob-timeout 20
  "Seconds before Glob tool is force-stopped."
  :type 'integer
  :group 'gptel-tools-glob)

(defcustom my/gptel-glob-result-limit 20000
  "Max characters to return inline from Glob output.
Results longer than this are saved to a temp file and only the
first 50 lines are returned with a reference to the full content."
  :type 'integer
  :group 'gptel-tools-glob)

;;; Helper Functions

(defun my/gptel--agent-glob--maybe-truncate (text)
  "Return TEXT, truncating and persisting to a temp file if needed.

If TEXT exceeds `my/gptel-glob-result-limit' bytes, it's saved to a temp file and only
the first 50 lines are returned with a reference to the full content."
  (if (<= (length text) my/gptel-glob-result-limit)
      text
    (let ((temp-file (my/gptel-make-temp-file "glob-" nil ".txt")))
      (with-temp-file temp-file (insert text))
      (with-temp-buffer
        (insert text)
        (let ((orig-size (buffer-size))
              (orig-lines (line-number-at-pos (point-max)))
              (max-lines 50))
          (goto-char (point-min))
          (insert (format "Glob results too large (%d chars, %d lines) for context window.\nStored in: %s\n\nFirst %d lines:\n\n"
                          orig-size orig-lines temp-file max-lines))
          (forward-line max-lines)
          (delete-region (point) (point-max))
          (goto-char (point-max))
          (insert (format "\n\n[Use Read tool with file_path=\"%s\" to view full results]"
                          temp-file))
          (buffer-string))))))

;;; Glob Tool Implementation

(defun my/gptel--agent-glob-async (callback pattern &optional path depth)
  "Async replacement for gptel-agent's `Glob' tool.

Finds files matching PATTERN using the `tree' command.
PATH defaults to current directory. DEPTH limits recursion.

CALLBACK is called exactly once unless the buffer has been aborted."
  (let* ((origin (current-buffer))
         (gen my/gptel--abort-generation)
         (buf nil)
         (done nil))
    (cl-labels
        ((finish (result)
           (unless done
             (setq done t)
             (when (buffer-live-p buf) (kill-buffer buf))
             (when (and (buffer-live-p origin)
                        (with-current-buffer origin
                          (= gen my/gptel--abort-generation)))
               (funcall callback result)))))
      (condition-case err
          (progn
            (when (string-empty-p pattern)
              (error "pattern must not be empty"))
            (if path
                (unless (and (file-readable-p path) (file-directory-p path))
                  (error "path %s is not readable" path))
              (setq path "."))
            (unless (executable-find "tree")
              (error "Executable `tree' not found. This tool cannot be used"))
            (let* ((full-path (expand-file-name path))
                   (args (list "-l" "-f" "-i" "-I" ".git"
                               "--sort=mtime" "--ignore-case"
                               "--prune" "-P" pattern full-path))
                   (args (if (natnump depth)
                             (nconc args (list "-L" (number-to-string depth)))
                           args)))
              (setq buf (generate-new-buffer " *gptel-glob*"))
              (let ((proc
                     (make-process
                      :name "gptel-glob"
                      :buffer buf
                      :command (cons "tree" args)
                      :noquery t
                      :connection-type 'pipe
                      :sentinel
                      (lambda (p _event)
                        (when (memq (process-status p) '(exit signal))
                          (let* ((status (process-exit-status p))
                                 (out (with-current-buffer buf (buffer-string))))
                            (setq out
                                  (if (= status 0)
                                      out
                                    (concat
                                     (format "Glob failed with exit code %d\n.STDOUT:\n\n" status)
                                     out)))
                            (finish (my/gptel--agent-glob--maybe-truncate out))))))))
                (process-put proc 'my/gptel-managed t)
                (run-at-time
                 my/gptel-glob-timeout nil
                 (lambda (p)
                   (when (process-live-p p)
                     (ignore-errors (set-process-filter p #'ignore))
                     (ignore-errors (set-process-sentinel p #'ignore))
                     (delete-process p))
                   (finish "Error: glob timed out."))
                 proc))))
        (error
         (finish (format "Error: %s" (error-message-string err))))))))

;;; Tool Registration

(defun gptel-tools-glob-register ()
  "Register the Glob tool with gptel."
  (if (not (executable-find "tree"))
      (when (fboundp 'display-warning)
        (display-warning 'gptel-tools "Executable `tree' not found. Glob tool will not be registered." :warning))
    (when (fboundp 'gptel-make-tool)
      (gptel-make-tool
       :name "Glob"
       :description "Find files by glob pattern (async)."
       :function #'my/gptel--agent-glob-async
       :async t
       :args '((:name "pattern"
                :type string
                :description "Glob pattern.")
              (:name "path"
                :type string
                :optional t)
              (:name "depth"
                :type integer
                :optional t))
       :category "gptel-agent"
       :include t))))

;;; Footer

(provide 'gptel-tools-glob)

;;; gptel-tools-glob.el ends here
