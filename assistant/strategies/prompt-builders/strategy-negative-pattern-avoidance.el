;;; strategy-negative-pattern-avoidance.el --- Learn from failed attempts -*- lexical-binding: t; -*-
;; Hypothesis: Explicitly avoiding patterns that failed in previous attempts improves outcomes.
;; Axis: D
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-negative-pattern-avoidance-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with explicit avoidance guidance from failed experiments."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (negative-patterns (seq-reduce
                            (lambda (acc result)
                              (if (eq (plist-get result :outcome) 'failure)
                                  (let ((pattern (plist-get result :pattern)))
                                    (if pattern (cons pattern acc) acc))
                                acc))
                            previous-results
                            nil))
         (avoidance-guidance (when negative-patterns
                               (format "\n\n;; Patterns to Avoid\n;; These approaches have failed in previous experiments; avoid them:\n- %s"
                                       (string-join (delete-dups negative-patterns) "\n- ")))))
    (concat base-prompt (or avoidance-guidance ""))))

(defun strategy-negative-pattern-avoidance-get-metadata ()
  (list :name "negative-pattern-avoidance"
        :version "1.0"
        :hypothesis "Explicitly avoiding patterns that failed in previous attempts improves outcomes."
        :axis "D"
        :components ["negative-learning" "failure-patterns"]))

(provide 'strategy-negative-pattern-avoidance)