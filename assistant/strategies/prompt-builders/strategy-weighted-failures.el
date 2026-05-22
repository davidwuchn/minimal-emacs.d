;;; strategy-weighted-failures.el --- Weight failure patterns by recency and frequency -*- lexical-binding: t; -*-
;; Hypothesis: Prioritizing recent and frequent failure patterns yields more actionable insights than treating all patterns equally.
;; Axis: D (Variable computation)
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-weighted-failures-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET with weighted failure patterns.
Weights patterns by recency and frequency before presentation."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (patterns (plist-get analysis :patterns))
         (weighted-patterns nil))
    (when patterns
      (let ((total-experiments (length previous-results)))
        (dolist (pattern patterns)
          (let* ((pattern-experiment (or (plist-get pattern :experiment) 1))
                 (pattern-count (or (plist-get pattern :count) 1))
                 (recency-weight (- total-experiments pattern-experiment))
                 (total-weight (+ pattern-count recency-weight))
                 (weighted-pattern (plist-put pattern :weight total-weight)))
            (push weighted-pattern weighted-patterns)))
        (setq weighted-patterns (sort weighted-patterns
                                     (lambda (a b)
                                       (> (or (plist-get a :weight) 0)
                                          (or (plist-get b :weight) 0)))))))
    (concat base-prompt
            (when weighted-patterns
              (format "\n\n;; Weighted Failure Patterns\n;; Patterns weighted by recency (recent) and frequency (common):\n%s"
                      (mapconcat (lambda (p)
                                   (format "- %s (weight: %d)"
                                           (or (plist-get p :description) "Unknown pattern")
                                           (or (plist-get p :weight) 0)))
                                 weighted-patterns
                                 "\n"))))))

(defun strategy-weighted-failures-get-metadata ()
  (list :name "weighted-failures"
        :version "1.0"
        :hypothesis "Prioritizing recent and frequent failure patterns yields more actionable insights than treating all patterns equally."
        :axis "D"
        :components ["weighted-patterns" "recency-filtering"]))

(provide 'strategy-weighted-failures)