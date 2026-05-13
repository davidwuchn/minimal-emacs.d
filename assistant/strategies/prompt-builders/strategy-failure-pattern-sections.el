;;; strategy-failure-pattern-sections.el --- Reorder sections based on failure patterns -*- lexical-binding: t; -*-
;; Hypothesis: Prompt sections addressing historical failure patterns should appear earlier
;; Axis: C
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-failure-pattern-sections-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with failure-pattern-driven section ordering for TARGET."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (template (gptel-auto-workflow--load-prompt-template))
         (failure-sections (strategy--extract-failure-sections analysis previous-results)))
    (if failure-sections
        (gptel-auto-workflow--substitute-template
         template (list (cons "FAILURE_PATTERN_GUIDANCE" failure-sections)))
      base-prompt)))

(defun strategy--extract-failure-sections (analysis previous-results)
  "Extract guidance from past failures and format for prompt inclusion."
  (when previous-results
    (let (patterns)
      (dolist (result previous-results)
        (when (and (plist-get result :failed)
                   (plist-get result :reason))
          (push (format "- %s" (plist-get result :reason)) patterns)))
      (when patterns
        (concat ";; Prioritize addressing these historical failure patterns:\n"
                (mapconcat 'identity (reverse patterns) "\n"))))))

(defun strategy-failure-pattern-sections-get-metadata ()
  (list :name "failure-pattern-sections"
        :version "1.0"
        :hypothesis "Placing failure pattern guidance earlier in prompt improves pattern avoidance"
        :axis "C"
        :components ["failure-extraction" "section-reordering"]))

(provide 'strategy-failure-pattern-sections)