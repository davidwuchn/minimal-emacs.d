;;; gptel-tools-grep.el --- Async Grep tool for gptel -*- no-byte-compile: t; lexical-binding: t; -*-

;; Author: David Wu
;; Version: 1.0.0
;;
;; Async Grep tool implementation with timeout and abort support.

(require 'cl-lib)
(require 'subr-x)
(require 'seq)

;;; Customization

(defgroup gptel-tools-grep nil
  "Async Grep tool for gptel-agent."
  :group 'gptel)

(defcustom my/gptel-grep-timeout 20
  "Seconds before Grep tool is force-stopped."
  :type 'integer
  :group 'gptel-tools-grep)

(defcustom my/gptel-grep-max-count 1000
  "Maximum number of matching lines returned by the Grep tool.
Passed as --max-count to rg/grep."
  :type 'integer
  :group 'gptel-tools-grep)

;;; Grep Tool Implementation

(defun gptel-tools-grep--normalize-context-lines (value)
  "Normalize Grep VALUE into a capped context line count.
Accept integer-like strings, clamp negatives to 0, and cap values at 30.
Return invalid non-numeric values unchanged so contract validation can reject
them."
  (cond
   ((integerp value)
    (max 0 (min 30 value)))
   ((and (stringp value)
         (string-match-p "\\`[[:space:]]*[+-]?[0-9]+[[:space:]]*\\'" value))
    (max 0 (min 30 (string-to-number (string-trim value)))))
   (t value)))

(defun my/gptel--agent-grep-async (callback regex path &optional glob context-lines)
  "Async replacement for gptel-agent's `Grep' tool.

Searches for REGEX in PATH using ripgrep (preferred) or grep.
GLOB pattern and CONTEXT-LINES are optional.

CALLBACK is called exactly once with the result. Even if aborted, callback
receives an error message to prevent callers from hanging."
  (let* ((origin (current-buffer))
         (gen my/gptel--abort-generation))
    (condition-case err
        (progn
          (unless (and (stringp regex) (not (string-empty-p (string-trim regex))))
            (error "regex is empty"))
          (unless (and (stringp path) (file-readable-p path))
            (error "File or directory %s is not readable" path))
          (let* ((grepper (or (executable-find "rg") (executable-find "grep")))
                 (_ (unless grepper (error "ripgrep/grep not available")))
                 (cmd (file-name-sans-extension (file-name-nondirectory grepper)))
                 (raw-context-lines
                  (gptel-tools-grep--normalize-context-lines context-lines))
                 (context-lines (if (natnump raw-context-lines) raw-context-lines 0))
                 (expanded-path (expand-file-name (substitute-in-file-name path)))
                 (args
                  (cond
                   ((string= "rg" cmd)
                     (delq nil (list "--sort=modified"
                                     (format "--context=%d" context-lines)
                                     (and glob (format "--glob=%s" glob))
                                     (format "--max-count=%d" my/gptel-grep-max-count)
                                     "--heading" "--line-number"
                                     "-e" regex
                                     expanded-path)))
                    ((string= "grep" cmd)
                     (delq nil (list "--recursive"
                                     (format "--context=%d" context-lines)
                                     (and glob (format "--include=%s" glob))
                                     (format "--max-count=%d" my/gptel-grep-max-count)
                                    "--line-number" "--regexp" regex
                                    expanded-path)))
                   (t (error "failed to identify grepper"))))
                 (buf (generate-new-buffer " *gptel-grep*"))
                 (done nil)
                 (finish
                  (lambda (result)
                    (unless done
                      (setq done t)
                      (when (buffer-live-p buf) (kill-buffer buf))
                      (cond
                       ((and (buffer-live-p origin)
                             (with-current-buffer origin
                               (= gen my/gptel--abort-generation)))
                        (funcall callback result))
                       ((not (buffer-live-p origin))
                        (funcall callback result))
                       (t
                        (funcall callback (format "Error: Request aborted\n%s"
                                                  (if (string-prefix-p "Error:" result) result
                                                    (concat "Partial output:\n" result))))))))))
            (let ((proc
                   (make-process
                    :name "gptel-grep"
                    :buffer buf
                    :command (cons grepper args)
                    :noquery t
                    :connection-type 'pipe
                    :sentinel
                    (lambda (p _event)
                      (when (memq (process-status p) '(exit signal))
                        (let* ((status (process-exit-status p))
                               (out (with-current-buffer buf (buffer-string))))
                          (funcall finish
                                   (if (= status 0)
                                       (string-trim out)
                                     (string-trim
                                      (format "Error: search failed with exit-code %d. Tool output:\n\n%s"
                                              status out))))))))))
              (process-put proc 'my/gptel-managed t)
              (run-at-time
               my/gptel-grep-timeout nil
               (lambda (p)
                 (when (process-live-p p)
                   (ignore-errors (set-process-filter p #'ignore))
                   (ignore-errors (set-process-sentinel p #'ignore))
                   (delete-process p))
                 (funcall finish "Error: search timed out."))
               proc))))
      (error
       (funcall callback (format "Error: %s" (error-message-string err)))))))

;;; Tool Registration

(defun gptel-tools-grep-register ()
  "Register the Grep tool with gptel."
  (if (not (or (executable-find "rg") (executable-find "grep")))
      (when (fboundp 'display-warning)
        (display-warning 'gptel-tools "Executables `rg' and `grep' not found. Grep tool will not be registered." :warning))
    (when (fboundp 'gptel-make-tool)
      (gptel-make-tool
       :name "Grep"
       :description "Search file contents under a path (async)."
       :function #'my/gptel--agent-grep-async
       :async t
       :args '((:name "regex"
                :type string)
              (:name "path"
                :type string)
              (:name "glob"
                :type string
                :optional t)
              (:name "context_lines"
                 :optional t
                 :normalize gptel-tools-grep--normalize-context-lines
                 :type integer
                 :maximum 30))
       :category "gptel-agent"
       :include t))))

;;; Footer

(provide 'gptel-tools-grep)

;;; gptel-tools-grep.el ends here
