;;; strategy-cross-validation-context.el --- Load companion test context -*- lexical-binding: t; -*-
;; Hypothesis: Loading companion test file context alongside the target improves code changes by surfacing potential test-breaking patterns.
;; Axis: B
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-cross-validation-context-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET using cross-validation context strategy."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (test-context (gptel-auto-workflow--load-cross-validation-context target)))
    (if (string-empty-p test-context)
        base-prompt
      (concat base-prompt "\n\n;; Cross-Validation Context\n;; Related test expectations to avoid violating:\n" test-context))))

(defun gptel-auto-workflow--load-cross-validation-context (target)
  "Load companion test file content for TARGET file."
  (when-let* ((file-path (if (listp target) (car target) target))
              ((stringp file-path))
              (file-dir (file-name-directory file-path))
              (file-base (file-name-base file-path))
              (test-paths (list
                           (expand-file-name (concat file-base "-test.el") file-dir)
                           (expand-file-name (concat file-base "_test.el") file-dir)
                           (expand-file-name (concat "test/" file-base "-test.el") file-dir)
                           (expand-file-name (concat "tests/" file-base "-test.el") file-dir)))
              (test-file (seq-find #'file-exists-p test-paths)))
    (with-temp-buffer
      (insert-file-contents test-file)
      (buffer-string))))

(defun strategy-cross-validation-context-get-metadata ()
  (list :name "cross-validation-context"
        :version "1.0"
        :hypothesis "Loading companion test file context alongside the target improves code changes by surfacing potential test-breaking patterns."
        :axis "B"
        :components ["test-context" "cross-validation"]))

(provide 'strategy-cross-validation-context)