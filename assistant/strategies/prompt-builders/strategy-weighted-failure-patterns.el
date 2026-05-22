;;; strategy-weighted-failure-patterns.el --- Weighted pattern prioritization -*- lexical-binding: t; -*-
;; Hypothesis: Weighting failure patterns by cross-target frequency and recency produces more actionable guidance.
;; Axis: D
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-weighted-failure-patterns-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET using weighted failure pattern analysis."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         ;; NEW MECHANISM: Compute importance weights for patterns
         (weighted-patterns (strategy-weighted-failure-patterns--compute-weights analysis previous-results))
         (pattern-section (format "\n\n;; Weighted Failure Patterns (higher weight = more critical)\n%s"
                                  weighted-patterns)))
    (concat base-prompt pattern-section)))

(defun strategy-weighted-failure-patterns--compute-weights (analysis previous-results)
  "Compute importance weights for patterns based on frequency and recency."
  (let ((pattern-weights nil))
    (dolist (result previous-results)
      (when (plist-get result :patterns)
        (let ((exp-time (or (plist-get result :timestamp) 0))
              (age-factor (/ 1.0 (+ 1.0 (- (float-time) exp-time)))))
          (dolist (pattern (plist-get result :patterns))
            (let ((current-weight (cdr (assoc pattern pattern-weights))))
              (push (cons pattern (+ (or current-weight 0) age-factor))
                    pattern-weights))))))
    ;; Sort by weight descending
    (setq pattern-weights (sort pattern-weights (lambda (a b) (> (cdr a) (cdr b)))))
    (mapconcat (lambda (w) (format "%s (weight: %.2f)" (car w) (cdr w)))
               pattern-weights "\n")))

(defun strategy-weighted-failure-patterns-get-metadata ()
  (list :name "weighted-failure-patterns"
        :version "1.0"
        :hypothesis "Weighting failure patterns by cross-target frequency and recency produces more actionable guidance."
        :axis "D"
        :components ["pattern-weighting" "recency-scoring"]))

(provide 'strategy-weighted-failure-patterns)