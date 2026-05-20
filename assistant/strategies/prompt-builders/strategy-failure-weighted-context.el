;;; strategy-failure-weighted-context.el --- Weight context by failure correlation -*- lexical-binding: t; -*-
;; Hypothesis: Weighting context sections by their correlation with past failures will improve focus on problematic areas.
;; Axis: D
;;
;; Mechanism: Analyzes previous results to compute failure correlation weights for different
;; context types, then restructures the prompt to emphasize high-correlation areas.

(require 'gptel-tools-agent-prompt-build)

(defun strategy-failure-weighted-context-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with failure-weighted context emphasis."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (failure-patterns (plist-get analysis :patterns))
         (weights (strategy-failure-weighted-context--compute-weights previous-results failure-patterns))
         (high-weight-sections (strategy-failure-weighted-context--extract-high-weight base-prompt weights))
         (formatted-failures (when failure-patterns
                               (gptel-auto-experiment--format-failure-patterns failure-patterns))))
    ;; Restructure: high-weight sections first, then base prompt, then failure guidance
    (concat ";; PRIORITY CONTEXT (failure-correlated)\n"
            high-weight-sections
            "\n\n;; STANDARD CONTEXT\n"
            base-prompt
            (when formatted-failures
              (concat "\n\n;; FAILURE PATTERN FOCUS\n"
                      formatted-failures
                      "\n;; Prioritize addressing patterns that correlate with past failures."))
            (format "\n\n;; Failure correlation weights: %s"
                    (mapconcat (lambda (w) (format "%s=%.2f" (car w) (cdr w)))
                               weights " ")))))

(defun strategy-failure-weighted-context--compute-weights (previous-results failure-patterns)
  "Compute correlation weights from PREVIOUS-RESULTS and FAILURE-PATTERNS."
  (let ((weights '((:performance . 0.0) (:correctness . 0.0) (:maintainability . 0.0))))
    (dolist (result previous-results weights)
      (let* ((score (plist-get result :score))
             (success (plist-get result :success))
             (categories (plist-get result :categories)))
        (when (and score (< score 0.5))
          (dolist (cat categories)
            (let ((entry (assq cat weights)))
              (when entry
                (setcdr entry (+ (cdr entry) (- 1.0 score)))))))))
    ;; Normalize weights
    (let ((max-weight (apply #'max (mapcar #'cdr weights))))
      (when (> max-weight 0)
        (setq weights (mapcar (lambda (w) (cons (car w) (/ (cdr w) max-weight))) weights)))
      weights)))

(defun strategy-failure-weighted-context--extract-high-weight (prompt weights)
  "Extract sections from PROMPT that match high WEIGHTS."
  (let ((sections "")
        (threshold 0.5))
    (dolist (w weights)
      (when (> (cdr w) threshold)
        (let ((pattern (format ";;.*%s" (symbol-name (car w)))))
          (when (string-match pattern prompt)
            (setq sections (concat sections (match-string 0 prompt) "\n"))))))
    sections))

(defun strategy-failure-weighted-context-get-metadata ()
  (list :name "failure-weighted-context"
        :version "1.0"
        :hypothesis "Weighting context by failure correlation improves focus on problematic areas"
        :axis "D"
        :components ["failure-analysis" "context-weighting" "priority-reordering"]))

(provide 'strategy-failure-weighted-context)