;;; strategy-failure-weighted-guidance.el --- Weight guidance by historical failure patterns -*- lexical-binding: t; -*-
;; Hypothesis: Emphasizing guidance sections based on historical failure frequencies produces more targeted improvements
;; Axis: D
;;
(require 'gptel-tools-agent-prompt-build)
(require 'cl-lib)

(defun strategy-failure-weighted-guidance-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with guidance weighted by failure pattern history."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         ;; Compute failure weights from historical data
         (failure-analysis (analyze-failure-patterns previous-results))
         ;; Extract top failure categories
         (top-failures (cl-subseq (cl-sort failure-analysis #'> :key #'cdr) 0 (min 3 (length failure-analysis))))
         ;; Generate weighted guidance text
         (weighted-guidance (generate-weighted-guidance-text top-failures)))
    (if weighted-guidance
        (concat base-prompt "\n\n;; Failure-Weighted Guidance\n" weighted-guidance)
      base-prompt)))

(defun analyze-failure-patterns (previous-results)
  "Analyze PREVIOUS-RESULTS to compute failure frequency per category."
  (let ((category-counts (list (cons "syntax" 0)
                               (cons "logic" 0)
                               (cons "style" 0)
                               (cons "performance" 0)
                               (cons "api-usage" 0)
                               (cons "edge-cases" 0))))
    (dolist (result previous-results)
      (let ((failures (plist-get result :failures)))
        (when failures
          (dolist (failure failures)
            (let ((category (or (plist-get failure :category) "other")))
              (when (assoc category category-counts)
                (cl-incf (cdr (assoc category category-counts)))))))))
    category-counts))

(defun generate-weighted-guidance-text (top-failures)
  "Generate guidance text emphasizing TOP-FAILURES categories."
  (when top-failures
    (let ((total (apply #'+ (mapcar #'cdr top-failures))))
      (when (> total 0)
        (concat "Based on failure analysis:\n"
                (mapconcat (lambda (p)
                            (let ((weight (/ (float (cdr p)) total)))
                              (format "- %s issues (weight: %.0f%%) - %s"
                                     (car p)
                                     (* weight 100)
                                     (get-category-guidance (car p) weight))))
                          top-failures "\n"))))))

(defun get-category-guidance (category weight)
  "Return guidance text for CATEGORY based on its WEIGHT."
  (cond
   ((string= category "syntax")
    (if (> weight 0.3) "CRITICAL: Double-check parentheses, quoting, and special forms" "Review syntax carefully"))
   ((string= category "logic")
    (if (> weight 0.3) "CRITICAL: Verify conditional logic and control flow" "Pay attention to logical correctness"))
   ((string= category "style")
    (if (> weight 0.3) "CRITICAL: Ensure consistent coding style" "Follow established conventions"))
   ((string= category "performance")
    (if (> weight 0.3) "CRITICAL: Optimize algorithmic complexity" "Consider performance implications"))
   ((string= category "api-usage")
    (if (> weight 0.3) "CRITICAL: Verify API function signatures and return values" "Check API usage carefully"))
   ((string= category "edge-cases")
    (if (> weight 0.3) "CRITICAL: Add guards for nil, empty, and boundary conditions" "Handle edge cases explicitly"))
   (t "Review this category thoroughly")))

(defun strategy-failure-weighted-guidance-get-metadata ()
  "Return metadata for this strategy."
  (list :name "failure-weighted-guidance"
        :version "1.0"
        :hypothesis "Emphasizing guidance sections based on historical failure frequencies produces more targeted improvements"
        :axis "D"
        :components ["failure-analysis" "category-weighting" "adaptive-guidance"]))

(provide 'strategy-failure-weighted-guidance)