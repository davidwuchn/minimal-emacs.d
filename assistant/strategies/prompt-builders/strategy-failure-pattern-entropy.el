;;; strategy-failure-pattern-entropy.el --- Weight guidance by failure pattern entropy -*- lexical-binding: t; -*-
;; Hypothesis: Patterns with high entropy (distributed across many types) require different guidance than low-entropy (concentrated) patterns.
;; Axis: D
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-failure-pattern-entropy-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET using failure pattern entropy analysis.
Patterns with high entropy receive concentrated fix guidance; low entropy receives systematic approach guidance."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (entropy-metrics (strategy-failure-pattern-entropy--compute analysis previous-results))
         (entropy-guidance (strategy-failure-pattern-entropy--generate-guidance entropy-metrics)))
    (if entropy-guidance
        (concat base-prompt "\n\n;; Entropy-Based Guidance\n" entropy-guidance)
      base-prompt)))

(defun strategy-failure-pattern-entropy--compute (analysis previous-results)
  "Compute entropy metrics for failure patterns across experiments.
Returns plist with :pattern-entropy :recurrence-rate :spread-factor."
  (let ((pattern-counts (make-hash-table :test 'equal))
        (total-occurrences 0))
    (dolist (result previous-results)
      (when (plist-get result :patterns)
        (dolist (pattern (plist-get result :patterns))
          (let ((type (plist-get pattern :type)))
            (when type
              (puthash type (1+ (gethash type pattern-counts 0)) pattern-counts)
              (setq total-occurrences (1+ total-occurrences)))))))
    (when (and (> total-occurrences 0) (> (hash-table-size pattern-counts) 0))
      (let* ((unique-patterns (hash-table-size pattern-counts))
             (entropy (strategy-failure-pattern-entropy--shannon-entropy pattern-counts total-occurrences))
             (max-entropy (log (float unique-patterns) 2))
             (normalized-entropy (if (> max-entropy 0) (/ entropy max-entropy) 0))
             (recurrence (if previous-results
                             (/ (float (cl-count-if (lambda (r) (plist-get r :patterns)) previous-results))
                                (float (length previous-results)))
                           0)))
        (list :pattern-entropy entropy
              :normalized-entropy normalized-entropy
              :recurrence-rate recurrence
              :unique-patterns unique-patterns
              :spread-factor (if (> recurrence 0) (/ normalized-entropy recurrence) 0))))))

(defun strategy-failure-pattern-entropy--shannon-entropy (counts total)
  "Compute Shannon entropy for pattern COUNTS with TOTAL occurrences."
  (let ((entropy 0.0))
    (maphash (lambda (_ count)
               (let ((p (/ (float count) (float total))))
                 (when (> p 0)
                   (setq entropy (- entropy (* p (log p 2)))))))
             counts)
    entropy))

(defun strategy-failure-pattern-entropy--generate-guidance (metrics)
  "Generate guidance based on entropy METRICS."
  (when metrics
    (let ((norm-ent (plist-get metrics :normalized-entropy))
          (recurrence (plist-get metrics :recurrence-rate))
          (unique (plist-get metrics :unique-patterns)))
      (cond
       ((> norm-ent 0.7)
        (format "HIGH ENTROPY DETECTED (%.2f): Diverse failure types suggest systemic issues. Apply broad fixes before narrow ones. Unique patterns: %d"
                norm-ent unique))
       ((> norm-ent 0.4)
        (format "MODERATE ENTROPY (%.2f): Mixed failure distribution. Balance systematic review with targeted fixes. Recurrence rate: %.2f"
                norm-ent recurrence))
       (t
        (format "LOW ENTROPY (%.2f): Concentrated failures suggest localized issues. Deep-dive into repeated pattern. Recurrence rate: %.2f"
                norm-ent recurrence))))))

(defun strategy-failure-pattern-entropy-get-metadata ()
  (list :name "failure-pattern-entropy"
        :version "1.0"
        :hypothesis "High-entropy failure patterns require different guidance than concentrated patterns"
        :axis "D"
        :components ["entropy-computation" "adaptive-guidance"]))

(provide 'strategy-failure-pattern-entropy)