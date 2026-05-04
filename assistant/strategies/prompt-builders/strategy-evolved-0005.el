;;; strategy-evolved-0005.el --- Counterfactual reasoning for unexplored alternatives -*- lexical-binding: t; -*-
;; Hypothesis: Explicit counterfactual reasoning about untried approaches provides better exploration signal
;; Axis: A (Prompt template architecture)

(require 'gptel-tools-agent-prompt-build)
(require 'cl-lib)

(defun strategy-evolved-0005--extract-patterns (previous-results)
  "Extract both successful and failed approaches."
  (let (successes failures)
    (dolist (result previous-results)
      (when (listp result)
        (if (plist-get result :success)
            (push (plist-get result :pattern) successes)
          (push (plist-get result :pattern) failures))))
    (cons successes failures)))

(defun strategy-evolved-0005--generate-counterfactuals (successes failures)
  "Generate explicit counterfactual reasoning about untried approaches."
  (let ((success-set (or successes '()))
        (failure-set (or failures '()))
        (success-count (length (or successes '())))
        (failure-count (length (or failures '()))))
    (format "=== Contrastive Counterfactual Analysis ===

OBSERVED SUCCESSES (%d patterns):
%s

OBSERVED FAILURES (%d patterns):
%s

COUNTERFACTUAL EXPLORATION:
Rather than repeating known patterns, consider these ALTERNATIVE approaches
that have NOT been tried in prior experiments:

1. INVERSE OF SUCCESS: What if we invert the key characteristics of %s?
   - Successful approaches suggest 'do X' → consider 'do NOT X' for edge cases

2. HYBRID OF FAILURES: Combine elements from %s
   - Multiple failures may indicate partial solutions that, combined differently, could work

3. ANALOGICAL EXTENSION: Apply the underlying PRINCIPLE, not just the pattern
   - '%s' succeeded → what is the general principle it demonstrates?

GUIDANCE: Avoid pattern repetition. Use counterfactuals to explore the solution space."
            success-count
            (if success-set (string-join success-set "\n") "No explicit successes yet")
            failure-count
            (if failure-set (string-join failure-set "\n") "No explicit failures yet")
            (if success-set (car success-set) "known success")
            (if failure-set (mapconcat #'identity (cl-subseq failure-set 0 (min 2 (length failure-set))) " + ") "known failures")
            (if success-set (car success-set) "successful pattern"))))

(defun strategy-evolved-0005-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with contrastive counterfactual reasoning."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt target experiment-id max-experiments analysis baseline previous-results))
         (patterns (strategy-evolved-0005--extract-patterns previous-results))
         (counterfactuals (strategy-evolved-0005--generate-counterfactuals (car patterns) (cdr patterns))))
    (concat base-prompt "\n\n" counterfactuals)))

(defun strategy-evolved-0005-get-metadata ()
  "Return metadata for this strategy."
  (list :name "evolved-0005"
        :version "1.0"
        :hypothesis "Explicit counterfactual reasoning about untried approaches provides better exploration signal"
        :axis "A"
        :created "2024"
        :parent-strategies '("evolved-0004-reasoning")
        :components ["counterfactual-reasoning" "inverse-analysis" "hybrid-exploration" "analogical-extension"]))

(provide 'strategy-evolved-0005)