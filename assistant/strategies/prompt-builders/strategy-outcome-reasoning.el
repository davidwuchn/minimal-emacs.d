;;; strategy-outcome-reasoning.el --- Derive failure reasoning chains -*- lexical-binding: t; -*-
;; Hypothesis: Computing causal reasoning from failure outcomes produces more actionable guidance than pattern listing alone.
;; Axis: D (Variable computation)
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-outcome-reasoning-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET using outcome reasoning mechanism.
Derives causal chains from past failures instead of just listing patterns."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (failure-reasoning (compute-failure-reasoning-chains previous-results))
         (derived-insights (extract-derived-insights failure-reasoning))
         (actionable-guidance (format-reasoned-guidance derived-insights)))
    (concat base-prompt "\n\n;; Derived Failure Reasoning\n" actionable-guidance)))

(defun compute-failure-reasoning-chains (previous-results)
  "Compute causal reasoning chains from experiment outcomes.
Returns a list of (attempted-fix . inferred-failure-cause) pairs."
  (when previous-results
    (let ((chains nil))
      (dolist (result previous-results)
        (when (and (plist-get result :outcome) (plist-get result :attempted-fix))
          (let ((outcome (plist-get result :outcome))
                (fix (plist-get result :attempted-fix))
                (context (plist-get result :context)))
            (push (reason-about-outcome fix outcome context) chains))))
      chains)))

(defun reason-about-outcome (fix outcome context)
  "Derive causal relationship between fix attempt and outcome."
  (cond
   ((and (eq outcome 'regression) (string-match-p "over-correction" fix))
    '("Over-correction detected" . "Fix was too aggressive; seek gentler approach"))
   ((and (eq outcome 'no-improvement) (string-match-p "partial" fix))
    '("Partial fix insufficient" . "Problem spans multiple concerns; consider systemic approach"))
   ((eq outcome 'regression)
    '("Regression introduced" . "New code introduced side effects; isolate changes"))
   ((eq outcome 'no-improvement)
    '("No measurable improvement" . "Root cause may differ from symptoms addressed"))
   (t '("Unknown outcome" . "Insufficient data for reasoning"))))

(defun extract-derived-insights (chains)
  "Extract high-level insights from reasoning chains."
  (let ((insights nil))
    (dolist (chain chains)
      (push (format "- %s: %s" (car chain) (cdr chain)) insights))
    (nreverse insights)))

(defun format-reasoned-guidance (insights)
  "Format reasoned guidance from derived insights."
  (if insights
      (concat "Based on reasoning from past outcomes:\n"
              (mapconcat #'identity insights "\n"))
    "Insufficient outcome data for reasoning derivation."))

(defun strategy-outcome-reasoning-get-metadata ()
  (list :name "outcome-reasoning"
        :version "1.0"
        :hypothesis "Computing causal reasoning chains from failure outcomes produces more actionable guidance than pattern listing alone."
        :axis "D"
        :components ["failure-reasoning" "derived-insights" "causal-chains"]))

(provide 'strategy-outcome-reasoning)