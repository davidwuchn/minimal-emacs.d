;;; strategy-outcome-reasoning-reasoning.el --- evolved-0004 reasoning injection in prompt architecture -*- lexical-binding: t; -*-
;; Hypothesis: Injecting explicit evolved-0004 reasoning between success/failure patterns improves learning
;; Axis: A (Prompt template architecture)

(require 'gptel-tools-agent-prompt-build)
(require 'cl-lib)

(defun strategy-outcome-reasoning--extract-success-patterns (previous-results)
  "Extract patterns from successful experiments."
  (when previous-results
    (cl-loop for result in previous-results
             when (and (listp result) (plist-get result :success))
             collect (plist-get result :pattern))))

(defun strategy-outcome-reasoning--extract-failure-patterns (analysis)
  "Extract patterns from failures."
  (gptel-auto-experiment--format-failure-patterns analysis))

(defun strategy-outcome-reasoning--generate-evolved-0004-analysis (successes failures)
  "Generate explicit evolved-0004 reasoning between successes and failures."
  (let ((success-count (length successes))
        (failure-text (or failures "No explicit failures detected")))
    (format "=== evolved-0004 Analysis ===

SUCCESS CONTEXT (%d patterns detected):
%s

FAILURE CONTEXT:
%s

evolved-0004 REASONING:
When the following conditions are TRUE, the approach tends to succeed:
- Code follows established patterns from %d prior successes
- Changes are incremental and localized

When the following conditions are TRUE, the approach tends to fail:
- Deviations from established patterns without justification
- Changes that introduce interaction effects with existing code

GUIDANCE: Apply the success patterns while explicitly avoiding the failure patterns."
            success-count
            (if successes (string-join successes "\n") "No clear success patterns yet")
            failure-text
            success-count)))

(defun strategy-outcome-reasoning--extract-axis-guidance (analysis)
  "Extract axis-specific guidance for evolved-0004 framing."
  (gptel-auto-experiment--format-axis-guidance analysis))

(defun strategy-outcome-reasoning-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt using evolved-0004 reasoning injection architecture."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt target experiment-id max-experiments analysis baseline previous-results))
         (success-patterns (strategy-outcome-reasoning--extract-success-patterns previous-results))
         (failure-patterns (strategy-outcome-reasoning--extract-failure-patterns analysis))
         (evolved-0004-analysis (strategy-outcome-reasoning--generate-evolved-0004-analysis success-patterns failure-patterns))
         (axis-guidance (strategy-outcome-reasoning--extract-axis-guidance analysis)))
    (if (or success-patterns failure-patterns)
        (concat base-prompt "\n\n" evolved-0004-analysis "\n\n" axis-guidance)
      (concat base-prompt "\n\n" axis-guidance))))

(defun strategy-outcome-reasoning-get-metadata ()
  "Return metadata for this strategy."
  (list :name "evolved-0004-reasoning"
        :version "1.0"
        :hypothesis "Explicit evolved-0004 reasoning between success and failure patterns improves learning signal"
        :axis "A"
        :components ["evolved-0004-analysis" "success-extraction" "failure-context" "reasoning-injection"]))

(provide 'strategy-outcome-reasoning)