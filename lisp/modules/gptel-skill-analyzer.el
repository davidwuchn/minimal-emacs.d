;;; gptel-skill-analyzer.el --- Pattern analysis for benchmark results -*- lexical-binding: t; -*-

;; Copyright (C) 2024

;; Author: David Wu
;; Keywords: ai, benchmark, analysis

;;; Commentary:

;; Analyze benchmark results to find patterns, insights, and recommendations.

;;; Code:

(require 'json)
(require 'cl-lib)

(defconst gptel-skill-analyzer-version "1.0.0"
  "Version of the analyzer system.")

(defun gptel-skill-analyze-results (benchmark-data)
  "Analyze BENCHMARK-DATA and return insights.
BENCHMARK-DATA is a plist from gptel-skill-benchmark-run."
  (let* ((results (plist-get benchmark-data :results))
         (pass-rate (plist-get benchmark-data :pass-rate))
         (total (plist-get benchmark-data :total-tests))
         (passed (plist-get benchmark-data :passed-tests))
         (findings '()))
    
    (push (list :category 'summary
                :severity 'info
                :description (format "Pass rate: %.1f%% (%d/%d)" pass-rate passed total)
                :evidence (list :pass-rate pass-rate :passed passed :total total))
          findings)
    
    (let ((failed-tests (cl-remove-if (lambda (r) (eq (plist-get r :status) 'pass)) results)))
      (when failed-tests
        (push (list :category 'failures
                    :severity 'high
                    :description (format "%d tests failed" (length failed-tests))
                    :evidence (mapcar (lambda (x) (plist-get x :test-id)) failed-tests))
              findings)))
    
    (let ((error-tests (cl-remove-if (lambda (r) (not (eq (plist-get r :status) 'error))) results)))
      (when error-tests
        (push (list :category 'errors
                    :severity 'critical
                    :description (format "%d tests had errors" (length error-tests))
                    :evidence (mapcar (lambda (x) (plist-get x :test-id)) error-tests))
              findings)))
    
    (let ((slow-tests (cl-remove-if (lambda (r) 
                                       (< (float-time (plist-get r :duration)) 5.0))
                                     results)))
      (when slow-tests
        (push (list :category 'performance
                    :severity 'medium
                    :description (format "%d tests took >5s" (length slow-tests))
                    :evidence (mapcar (lambda (x) 
                                        (list :test-id (plist-get x :test-id)
                                              :duration (float-time (plist-get x :duration))))
                                      slow-tests))
              findings)))
    
    (list :findings (reverse findings)
          :recommendations (gptel-skill-analyzer-recommendations findings)
          :summary (format "Analyzed %d tests: %.1f%% pass rate" total pass-rate))))

(defun gptel-skill-analyzer-recommendations (findings)
  "Generate recommendations based on FINDINGS."
  (let ((recs '()))
    (dolist (f findings)
      (let ((cat (plist-get f :category))
            (sev (plist-get f :severity)))
        (cond
         ((and (eq cat 'failures) (eq sev 'high))
          (push "Review failed test cases and improve skill prompts" recs))
         ((and (eq cat 'errors) (eq sev 'critical))
          (push "Fix errors before running additional benchmarks" recs))
         ((and (eq cat 'performance) (eq sev 'medium))
          (push "Consider optimizing slow operations" recs)))))
    (delete-dups (reverse recs))))

(defun gptel-skill-analyze-trends (history)
  "Analyze HISTORY of benchmark runs for trends.
HISTORY is a list of benchmark reports."
  (when (< (length history) 2)
    (error "Need at least 2 benchmark runs for trend analysis"))
  (let* ((recent (car history))
         (previous (cadr history))
         (recent-rate (plist-get recent :pass-rate))
         (previous-rate (plist-get previous :pass-rate))
         (delta (- recent-rate previous-rate)))
    (list :trend (cond ((> delta 5) 'improving)
                       ((< delta -5) 'degrading)
                       (t 'stable))
          :delta delta
          :recent-rate recent-rate
          :previous-rate previous-rate
          :summary (format "Pass rate %s by %.1f%% (%.1f%% → %.1f%%)"
                           (if (> delta 0) "improved" "declined")
                           (abs delta)
                           previous-rate
                           recent-rate))))

(defun gptel-skill-analyze-assertions (results)
  "Analyze assertion patterns across RESULTS."
  (let ((assertion-stats (make-hash-table :test 'equal)))
    (dolist (result results)
      (let ((test-id (plist-get result :test-id))
            (assertion-results (plist-get result :assertion-results)))
        (dolist (ar assertion-results)
          (let* ((assertion (plist-get ar :assertion))
                 (type (plist-get assertion :type))
                 (passed (plist-get ar :result)))
            (puthash type 
                     (cons (list :test-id test-id :passed passed)
                           (gethash type assertion-stats '()))
                     assertion-stats)))))
    (let ((summary '()))
      (maphash (lambda (type results)
                 (let* ((total (length results))
                        (passed (cl-count-if (lambda (r) (plist-get r :passed)) results)))
                   (push (list :type type
                              :total total
                              :passed passed
                              :pass-rate (* 100.0 (/ passed (max total 1))))
                         summary)))
               assertion-stats)
      (sort summary (lambda (a b) (> (plist-get a :pass-rate) (plist-get b :pass-rate)))))))

(provide 'gptel-skill-analyzer)

;;; gptel-skill-analyzer.el ends here