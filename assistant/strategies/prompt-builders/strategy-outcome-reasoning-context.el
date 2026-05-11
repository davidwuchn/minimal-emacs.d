;;; strategy-outcome-reasoning-context.el --- Context retrieval by outcome similarity -*- lexical-binding: t; -*-
;; Hypothesis: Retrieving context based on similar outcomes (improvements/regressions) is more effective than file similarity
;; Axis: B (Context Retrieval)
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-outcome-reasoning-context-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with outcome-reasoned context retrieval instead of file-similarity."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         ;; Extract patterns and analyze their outcomes
         (patterns (plist-get analysis :patterns))
         (improvement-patterns nil)
         (regression-patterns nil)
         ;; Categorize by outcome
         (improvement-patterns (seq-filter
                                (lambda (p) (> (or (plist-get p :improvement-score) 0) 0))
                                patterns))
         (regression-patterns (seq-filter
                               (lambda (p) (< (or (plist-get p :improvement-score) 0) 0))
                               patterns))
         ;; Build outcome reasoning context
         (outcome-context
          (concat ";; OUTCOME-REASONED CONTEXT\n"
                  ";; Patterns leading to IMPROVEMENT (apply these patterns):\n"
                  (if improvement-patterns
                      (string-join (mapcar #'format improvement-patterns) "\n")
                    ";; No positive patterns yet recorded\n")
                  "\n\n;; Patterns leading to REGRESSION (avoid these patterns):\n"
                  (if regression-patterns
                      (string-join (mapcar #'format regression-patterns) "\n")
                    ";; No negative patterns yet recorded\n")
                  "\n\n;; REASONING: Apply improvement patterns to similar code structures, avoid regression patterns.")))
    (concat base-prompt "\n\n" outcome-context)))

(defun strategy-outcome-reasoning-context-get-metadata ()
  (list :name "outcome-reasoning-context"
        :version "1.0"
        :hypothesis "Retrieving context based on similar outcomes (improvements/regressions) is more effective than file similarity"
        :axis "B"
        :components ["outcome-categorization" "backward-reasoning" "improvement-patterns"]))

(provide 'strategy-outcome-reasoning-context)