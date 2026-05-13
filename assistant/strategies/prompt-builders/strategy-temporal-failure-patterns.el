;;; strategy-temporal-failure-patterns-patterns.el --- Time-based failure pattern weighting -*- lexical-binding: t; -*-
;; Hypothesis: Analyzing where in file structure failures occur enables targeted guidance weighting
;; Axis: D/C

(require 'gptel-tools-agent-prompt-build)

(defun strategy-temporal-failure-patterns--analyze-patterns (previous-results)
  "Analyze failure patterns from PREVIOUS-RESULTS to find temporal clustering."
  (when (listp previous-results)
    (let* ((failure-positions nil)
           (error-types nil))
      (dolist (result previous-results)
        (when (and (plistp result)
                   (plist-get result :error-location))
          (push (plist-get result :error-location) failure-positions))
        (when (and (plistp result)
                   (plist-get result :error-type))
          (push (plist-get result :error-type) error-types)))
      (list :positions failure-positions
            :types error-types
            :early-failures (cl-count-if (lambda (p) (< p 100)) failure-positions)
            :late-failures (cl-count-if (lambda (p) (>= p 100)) failure-positions)))))

(defun strategy-temporal-failure-patterns--compute-guidance-weight (analysis)
  "Compute guidance weighting based on temporal failure analysis."
  (let* ((early (plist-get analysis :early-failures))
         (late (plist-get analysis :late-failures))
         (total (+ early late)))
    (when (> total 0)
      (cond
       ((> (/ (float early) total) 0.6)
        "early-structure")
       ((> (/ (float late) total) 0.6)
        "late-optimization")
       (t "balanced")))))

(defun strategy-temporal-failure-patterns--generate-weighted-guidance (weight-type)
  "Generate guidance text based on WEIGHT-TYPE."
  (pcase weight-type
    ("early-structure"
     "\n\n;; Temporal Failure Pattern: Focus on structural integrity\nPay special attention to file header organization, package declarations, and early definitions. Issues tend to cluster in setup and initialization code.")
    ("late-optimization"
     "\n\n;; Temporal Failure Pattern: Focus on optimization areas\nConcentrate on later sections where complexity accumulates. Review function implementations and optimization opportunities.")
    (_
     "\n\n;; Temporal Failure Pattern: Balanced attention\nDistribute focus evenly across the file structure.")))

(defun strategy-temporal-failure-patterns-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt using temporal failure pattern weighting."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (temporal-analysis (strategy-temporal-failure-patterns--analyze-patterns previous-results))
         (weight-type (strategy-temporal-failure-patterns--compute-guidance-weight temporal-analysis))
         (weighted-guidance (strategy-temporal-failure-patterns--generate-weighted-guidance weight-type)))
    (concat base-prompt weighted-guidance)))

(defun strategy-temporal-failure-patterns-get-metadata ()
  (list :name "temporal-failure-patterns-patterns"
        :version "1.0"
        :hypothesis "Analyzing where in file structure failures occur enables targeted guidance weighting"
        :axis "D/C"
        :components ["temporal-analysis" "failure-position-tracking" "weighted-guidance"]))

(provide 'strategy-temporal-failure-patterns)