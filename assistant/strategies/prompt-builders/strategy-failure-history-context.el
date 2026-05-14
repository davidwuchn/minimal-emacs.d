;;; strategy-failure-history-context.el --- Context retrieval guided by failure history -*- lexical-binding: t; -*-
;; Hypothesis: Retrieving context from modules involved in past failures produces more targeted guidance
;; Axis: B

(require 'gptel-tools-agent-prompt-build)

(defun strategy-failure-history-context-build-prompt
    (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with context retrieval guided by failure history."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (failure-modules (strategy-failure-history-context--get-failing-modules previous-results))
         (related-context (strategy-failure-history-context--load-related-context failure-modules))
         (prior-solutions (strategy-failure-history-context--get-prior-solutions previous-results)))
    (concat base-prompt
            "\n\n;; Failure-Guided Context Retrieval"
            "\n# Past Failure Analysis"
            (format "\nPreviously failing modules: %s" failure-modules)
            "\n\n# Related Module Context"
            related-context
            "\n\n# Prior Successful Solutions"
            prior-solutions)))

(defun strategy-failure-history-context--get-failing-modules (previous-results)
  "Extract module names from failing experiments."
  (cl-loop for result in previous-results
           when (eq (plist-get result :outcome) 'failure)
           nconc (cl-loop for file in (plist-get result :affected-files)
                          collect file)))

(defun strategy-failure-history-context--load-related-context (modules)
  "Load context from MODULES that have caused failures."
  (if (null modules)
      "\nNo prior failure context available."
    (let ((unique-modules (delete-dups modules))
          (context ""))
      (dolist (mod unique-modules)
        (when (file-readable-p mod)
          (with-temp-buffer
            (insert-file-contents mod)
            (let ((lines (cl-loop for i from 1 to 30
                                   when (nthcdr i (split-string (buffer-string) "\n"))
                                   collect it)))
              (setq context (concat context "\n\nFrom " mod ":\n"
                                    (mapconcat #'identity lines "\n")))))))
      context)))

(defun strategy-failure-history-context--get-prior-solutions (previous-results)
  "Extract successful solutions from past experiments."
  (let ((solutions '()))
    (dolist (result previous-results)
      (when (eq (plist-get result :outcome) 'success)
        (when-let ((guidance (plist-get result :solution-guidance)))
          (push guidance solutions))))
    (if solutions
        (mapconcat #'identity (nreverse solutions) "\n---\n")
      "\nNo prior successful solutions available.")))

(defun strategy-failure-history-context-get-metadata ()
  "Return metadata for failure-history-guided context strategy."
  (list :name "failure-history-context"
        :version "1.0"
        :hypothesis "Retrieving context from modules involved in past failures produces more targeted guidance"
        :axis "B"
        :components ["failure-analysis" "context-retrieval"]))

(provide 'strategy-failure-history-context)