;;; test-gptel-auto-workflow-external-sensors.el --- Tests for external sensors -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OV5 Self-Improving Architecture

;; Author: OV5 System
;; Keywords: tests, sensors, production-monitoring

;;; Commentary:

;; TDD tests for Phase 1: External Sensors
;; This module collects production metrics, user feedback, and business value data
;; to close the loop between code quality improvements and real-world impact.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-auto-workflow-external-sensors)

;; ============================================================================
;; Task 1.1: Production Metrics Collection
;; ============================================================================

(ert-deftest test-external-sensors/initialize-sentry-client ()
  "Should initialize Sentry client with configuration."
  (let ((config '(:dsn "https://key@sentry.io/123"
                       :environment "production")))
    (should (gptel-auto-workflow--sentry-init config))
    (should (gptel-auto-workflow--sentry-configured-p))))

(ert-deftest test-external-sensors/query-error-rate ()
  "Should query error rate for a time window."
  (cl-letf (((symbol-function 'gptel-auto-workflow--sentry-api-call)
             (lambda (endpoint params)
               '((:error-count 150 :request-count 10000)))))
    (let ((result (gptel-auto-workflow--query-error-rate
                   :start-time (- (time-to-seconds) 3600)
                   :end-time (time-to-seconds))))
      (should (= 0.015 (plist-get result :error-rate)))
      (should (= 150 (plist-get result :error-count)))
      (should (= 10000 (plist-get result :request-count))))))

(ert-deftest test-external-sensors/query-error-rate-by-module ()
  "Should query error rate filtered by module."
  (cl-letf (((symbol-function 'gptel-auto-workflow--sentry-api-call)
             (lambda (endpoint params)
               (when (string-match "gptel-auto-workflow" (plist-get params :filter))
                 '((:error-count 25 :request-count 5000))))))
    (let ((result (gptel-auto-workflow--query-error-rate
                   :module "gptel-auto-workflow-evolution.el"
                   :start-time (- (time-to-seconds) 3600)
                   :end-time (time-to-seconds))))
      (should (= 0.005 (plist-get result :error-rate))))))

(ert-deftest test-external-sensors/query-performance-metrics ()
  "Should query performance metrics (latency, throughput)."
  (cl-letf (((symbol-function 'gptel-auto-workflow--sentry-api-call)
             (lambda (endpoint params)
               '((:p50-latency 120 :p95-latency 450 :p99-latency 1200
                  :throughput 850)))))
    (let ((result (gptel-auto-workflow--query-performance-metrics
                   :module "gptel-auto-workflow-experiment.el"
                   :start-time (- (time-to-seconds) 3600)
                   :end-time (time-to-seconds))))
      (should (= 120 (plist-get result :p50-latency)))
      (should (= 450 (plist-get result :p95-latency)))
      (should (= 850 (plist-get result :throughput))))))

(ert-deftest test-external-sensors/collect-baseline-metrics ()
  "Should collect baseline metrics before experiment."
  (cl-letf (((symbol-function 'gptel-auto-workflow--query-error-rate)
             (lambda (&rest args)
               '((:error-rate 0.02 :error-count 200 :request-count 10000))))
            ((symbol-function 'gptel-auto-workflow--query-performance-metrics)
             (lambda (&rest args)
               '((:p50-latency 150 :p95-latency 500 :throughput 800)))))
    (let ((baseline (gptel-auto-workflow--collect-baseline-metrics
                     "gptel-auto-workflow-evolution.el")))
      (should (= 0.02 (plist-get baseline :error-rate-before)))
      (should (= 150 (plist-get baseline :p50-latency-before)))
      (should (= 800 (plist-get baseline :throughput-before))))))

;; ============================================================================
;; Task 1.2: Error Rate Tracking Before/After Experiments
;; ============================================================================

(ert-deftest test-external-sensors/collect-post-experiment-metrics ()
  "Should collect metrics after experiment deployment."
  (cl-letf (((symbol-function 'gptel-auto-workflow--query-error-rate)
             (lambda (&rest args)
               '((:error-rate 0.015 :error-count 150 :request-count 10000))))
            ((symbol-function 'gptel-auto-workflow--query-performance-metrics)
             (lambda (&rest args)
               '((:p50-latency 120 :p95-latency 450 :throughput 850)))))
    (let ((post-metrics (gptel-auto-workflow--collect-post-experiment-metrics
                         "gptel-auto-workflow-evolution.el"
                         :wait-hours 24)))
      (should (= 0.015 (plist-get post-metrics :error-rate-after)))
      (should (= 120 (plist-get post-metrics :p50-latency-after)))
      (should (= 850 (plist-get post-metrics :throughput-after))))))

(ert-deftest test-external-sensors/calculate-error-rate-impact ()
  "Should calculate error rate improvement percentage."
  (let ((before '((:error-rate 0.02 :error-count 200 :request-count 10000)))
        (after '((:error-rate 0.015 :error-count 150 :request-count 10000))))
    (let ((impact (gptel-auto-workflow--calculate-error-rate-impact before after)))
      ;; Use approximate comparison for floating point
      (should (< (abs (- 0.25 (plist-get impact :error-rate-improvement-pct))) 0.0001))
      (should (= 50 (plist-get impact :errors-reduced)))
      (should (eq :improved (plist-get impact :direction))))))

(ert-deftest test-external-sensors/calculate-error-rate-impact-regression ()
  "Should detect error rate regression."
  (let ((before '((:error-rate 0.02 :error-count 200 :request-count 10000)))
        (after '((:error-rate 0.025 :error-count 250 :request-count 10000))))
    (let ((impact (gptel-auto-workflow--calculate-error-rate-impact before after)))
      ;; Use approximate comparison for floating point
      (should (< (abs (- -0.25 (plist-get impact :error-rate-improvement-pct))) 0.0001))
      (should (eq :regressed (plist-get impact :direction))))))

(ert-deftest test-external-sensors/calculate-performance-impact ()
  "Should calculate performance improvement."
  (let ((before '((:p50-latency 150 :p95-latency 500 :throughput 800)))
        (after '((:p50-latency 120 :p95-latency 450 :throughput 850))))
    (let ((impact (gptel-auto-workflow--calculate-performance-impact before after)))
      ;; Use approximate comparison for floating point
      (should (< (abs (- 0.20 (plist-get impact :latency-improvement-pct))) 0.0001))
      (should (< (abs (- 0.0625 (plist-get impact :throughput-improvement-pct))) 0.0001))
      (should (eq :improved (plist-get impact :direction))))))

(ert-deftest test-external-sensors/schedule-post-experiment-collection ()
  "Should schedule metrics collection after experiment deployment."
  (let ((timer-created nil))
    (cl-letf (((symbol-function 'run-with-timer)
               (lambda (delay repeat function &rest args)
                 (setq timer-created t)
                 (should (= delay (* 24 3600)))  ;; 24 hours
                 (should (null repeat))
                 (should (functionp function))
                 'mock-timer)))
      (let ((timer (gptel-auto-workflow--schedule-post-experiment-collection
                    "gptel-auto-workflow-evolution.el"
                    "exp-123")))
        (should timer-created)
        (should (eq 'mock-timer timer))))))

;; ============================================================================
;; Task 1.3: User Feedback Collection
;; ============================================================================

(ert-deftest test-external-sensors/initialize-feedback-collector ()
  "Should initialize user feedback collection system."
  (let ((config '(:webhook-endpoint "https://feedback.example.com/webhook"
                   :storage-backend 'sqlite
                   :retention-days 90)))
    (should (gptel-auto-workflow--feedback-init config))
    (should (gptel-auto-workflow--feedback-configured-p))))

(ert-deftest test-external-sensors/collect-user-feedback ()
  "Should collect user feedback for a module."
  (cl-letf (((symbol-function 'gptel-auto-workflow--feedback-query)
             (lambda (module start-time end-time)
               '((:positive 15 :negative 3 :neutral 20
                  :sample-complaints ("Function too slow" "Confusing API"))))))
    (let ((feedback (gptel-auto-workflow--collect-user-feedback
                     "gptel-auto-workflow-evolution.el"
                     :start-time (- (time-to-seconds) (* 7 24 3600))
                     :end-time (time-to-seconds))))
      (should (= 15 (plist-get feedback :positive)))
      (should (= 3 (plist-get feedback :negative)))
      (should (= 20 (plist-get feedback :neutral)))
      ;; Use approximate comparison for floating point
      (should (< (abs (- 0.3947 (plist-get feedback :satisfaction-rate))) 0.001)))))

(ert-deftest test-external-sensors/calculate-feedback-impact ()
  "Should calculate user satisfaction improvement."
  (let ((before '((:positive 10 :negative 5 :neutral 20 :satisfaction-rate 0.29)))
        (after '((:positive 15 :negative 3 :neutral 20 :satisfaction-rate 0.39))))
    (let ((impact (gptel-auto-workflow--calculate-feedback-impact before after)))
      ;; Use approximate comparison for floating point
      (should (< (abs (- 0.3448 (plist-get impact :satisfaction-improvement-pct))) 0.001))
      (should (= 2 (plist-get impact :complaints-reduced)))
      (should (eq :improved (plist-get impact :direction))))))

(ert-deftest test-external-sensors/parse-feedback-webhook ()
  "Should parse incoming feedback webhook."
  (let ((webhook-data '((:module "gptel-auto-workflow-evolution.el"
                          :feedback-type "complaint"
                          :message "Function takes too long to run"
                          :severity "medium"
                          :timestamp "2026-06-05T10:30:00Z"))))
    (let ((parsed (gptel-auto-workflow--parse-feedback-webhook webhook-data)))
      (should (string= "gptel-auto-workflow-evolution.el"
                       (plist-get parsed :module)))
      (should (eq :negative (plist-get parsed :sentiment)))
      (should (eq :medium (plist-get parsed :severity))))))

(ert-deftest test-external-sensors/aggregate-feedback-sentiment ()
  "Should aggregate sentiment from multiple feedback items."
  (let ((feedback-items '((:sentiment :positive)
                          (:sentiment :positive)
                          (:sentiment :negative)
                          (:sentiment :neutral)
                          (:sentiment :positive))))
    (let ((aggregated (gptel-auto-workflow--aggregate-feedback-sentiment
                       feedback-items)))
      (should (= 3 (plist-get aggregated :positive)))
      (should (= 1 (plist-get aggregated :negative)))
      (should (= 1 (plist-get aggregated :neutral)))
      (should (= 0.60 (plist-get aggregated :satisfaction-rate))))))

;; ============================================================================
;; Task 1.4: Business Value Metrics Integration
;; ============================================================================

(ert-deftest test-external-sensors/define-business-value-metrics ()
  "Should define business value metrics for experiments."
  (let ((experiment '(:id "exp-123"
                      :target "gptel-auto-workflow-evolution.el"
                      :error-rate-improvement 0.25
                      :complaints-reduced 2
                      :performance-improvement 0.20
                      :development-time-saved-hours 5)))
    (let ((bv (gptel-auto-workflow--define-business-value-metrics experiment)))
      (should (numberp (plist-get bv :business-value-score)))
      (should (>= (plist-get bv :business-value-score) 0.0))
      (should (<= (plist-get bv :business-value-score) 1.0)))))

(ert-deftest test-external-sensors/calculate-business-value-score ()
  "Should calculate weighted business value score."
  (let ((weights '(:error-rate-weight 0.4
                   :user-satisfaction-weight 0.3
                   :performance-weight 0.2
                   :development-efficiency-weight 0.1)))
    (let ((metrics '(:error-rate-improvement 0.25
                     :satisfaction-improvement 0.34
                     :performance-improvement 0.20
                     :development-time-saved 5.0)))
      (let ((score (gptel-auto-workflow--calculate-business-value-score
                    metrics weights)))
        (should (numberp score))
        (should (> score 0.0))
        (should (<= score 1.0))))))

(ert-deftest test-external-sensors/calculate-business-value-roi ()
  "Should calculate business value ROI."
  (let ((experiment '(:id "exp-123"
                      :cost-usd 2.50
                      :business-value-score 0.75
                      :errors-reduced 50
                      :support-tickets-reduced 2
                      :development-hours-saved 5)))
    (let ((roi (gptel-auto-workflow--calculate-business-value-roi experiment)))
      (should (numberp (plist-get roi :roi-percentage)))
      (should (numberp (plist-get roi :value-per-dollar)))
      (should (> (plist-get roi :value-per-dollar) 0.0)))))

(ert-deftest test-external-sensors/integrate-business-value-into-scoring ()
  "Should integrate business value into experiment scoring."
  (let ((experiment '(:id "exp-123"
                      :code-quality-score 0.85
                      :business-value-score 0.75)))
    (let ((integrated (gptel-auto-workflow--integrate-business-value-into-scoring
                       experiment
                       :business-value-weight 0.6
                       :code-quality-weight 0.4)))
      (should (= 0.79 (plist-get integrated :combined-score)))
      (should (= 0.75 (plist-get integrated :business-value-score)))
      (should (= 0.85 (plist-get integrated :code-quality-score))))))

(ert-deftest test-external-sensors/prioritize-experiments-by-business-value ()
  "Should prioritize experiments by business value."
  (let ((experiments '((:id "exp-1" :business-value-score 0.85 :code-quality-score 0.70)
                       (:id "exp-2" :business-value-score 0.60 :code-quality-score 0.90)
                       (:id "exp-3" :business-value-score 0.75 :code-quality-score 0.80))))
    (let ((prioritized (gptel-auto-workflow--prioritize-experiments-by-business-value
                        experiments
                        :business-value-weight 0.6)))
      (should (string= "exp-1" (plist-get (car prioritized) :id)))
      (should (string= "exp-3" (plist-get (cadr prioritized) :id)))
      (should (string= "exp-2" (plist-get (caddr prioritized) :id))))))

(ert-deftest test-external-sensors/generate-business-impact-report ()
  "Should generate business impact report."
  (let ((experiments '((:id "exp-1"
                            :target "module-a.el"
                            :business-value-score 0.85
                            :errors-reduced 50
                            :complaints-reduced 2
                            :cost-usd 2.50)
                       (:id "exp-2"
                            :target "module-b.el"
                            :business-value-score 0.60
                            :errors-reduced 20
                            :complaints-reduced 0
                            :cost-usd 1.80))))
    (let ((report (gptel-auto-workflow--generate-business-impact-report experiments)))
      (should (plist-get report :total-business-value))
      (should (plist-get report :total-cost))
      (should (plist-get report :overall-roi))
      (should (plist-get report :top-performing-experiments))
      (should (= 2 (length (plist-get report :top-performing-experiments)))))))

;; ============================================================================
;; Integration Tests
;; ============================================================================

(ert-deftest test-external-sensors/full-sensor-pipeline ()
  "Should run full external sensor pipeline for an experiment."
  (cl-letf (((symbol-function 'gptel-auto-workflow--collect-baseline-metrics)
             (lambda (module)
               '((:error-rate-before 0.02
                  :p50-latency-before 150
                  :throughput-before 800))))
            ((symbol-function 'gptel-auto-workflow--collect-post-experiment-metrics)
             (lambda (module &rest args)
               '((:error-rate-after 0.015
                  :p50-latency-after 120
                  :throughput-after 850))))
            ((symbol-function 'gptel-auto-workflow--collect-user-feedback)
             (lambda (module &rest args)
               '((:positive 15 :negative 3 :neutral 20
                  :satisfaction-rate 0.39))))
            ((symbol-function 'gptel-auto-workflow--calculate-business-value-score)
             (lambda (metrics weights)
               0.75)))
    (let ((result (gptel-auto-workflow--full-sensor-pipeline
                   "gptel-auto-workflow-evolution.el"
                   "exp-123")))
      (should (plist-get result :baseline-metrics))
      (should (plist-get result :post-metrics))
      (should (plist-get result :user-feedback))
      (should (plist-get result :business-value-score))
      (should (plist-get result :error-rate-impact))
      (should (plist-get result :performance-impact))
      (should (plist-get result :feedback-impact)))))

(ert-deftest test-external-sensors/handle-missing-metrics ()
  "Should handle missing production metrics gracefully."
  (cl-letf (((symbol-function 'gptel-auto-workflow--collect-baseline-metrics)
             (lambda (module) nil))
            ((symbol-function 'gptel-auto-workflow--collect-post-experiment-metrics)
             (lambda (module &rest args) nil)))
    (let ((result (gptel-auto-workflow--full-sensor-pipeline
                   "gptel-auto-workflow-evolution.el"
                   "exp-123")))
      (should (null (plist-get result :baseline-metrics)))
      (should (null (plist-get result :post-metrics)))
      (should (null (plist-get result :error-rate-impact)))
      (should (= 0.0 (plist-get result :business-value-score))))))

(ert-deftest test-external-sensors/persist-sensor-data ()
  "Should persist sensor data to storage."
  (let ((sensor-data '(:experiment-id "exp-123"
                       :module "gptel-auto-workflow-evolution.el"
                       :timestamp "2026-06-05T12:00:00Z"
                       :error-rate-before 0.02
                       :error-rate-after 0.015
                       :business-value-score 0.75))
        (temp-file (make-temp-file "sensor-data-")))
    (unwind-protect
        (progn
          (gptel-auto-workflow--persist-sensor-data sensor-data temp-file)
          (should (file-exists-p temp-file))
          (let ((loaded (gptel-auto-workflow--load-sensor-data temp-file)))
            (should (string= "exp-123" (plist-get loaded :experiment-id)))
            (should (= 0.75 (plist-get loaded :business-value-score)))))
      (delete-file temp-file))))

;; ============================================================================
;; Edge Cases
;; ============================================================================

(ert-deftest test-external-sensors/handle-api-failures ()
  "Should handle API failures gracefully."
  (cl-letf (((symbol-function 'gptel-auto-workflow--sentry-api-call)
             (lambda (endpoint params)
               (error "API timeout"))))
    (let ((result (gptel-auto-workflow--query-error-rate
                   :start-time (- (time-to-seconds) 3600)
                   :end-time (time-to-seconds))))
      (should (null result)))))

(ert-deftest test-external-sensors/handle-empty-data ()
  "Should handle empty metrics data."
  (cl-letf (((symbol-function 'gptel-auto-workflow--sentry-api-call)
             (lambda (endpoint params)
               '((:error-count 0 :request-count 0)))))
    (let ((result (gptel-auto-workflow--query-error-rate
                   :start-time (- (time-to-seconds) 3600)
                   :end-time (time-to-seconds))))
      (should (= 0.0 (plist-get result :error-rate))))))

(ert-deftest test-external-sensors/handle-timezone-differences ()
  "Should handle timezone differences in timestamps."
  (let ((utc-timestamp "2026-06-05T12:00:00Z")
        (local-timestamp "2026-06-05T14:00:00+02:00"))
    (let ((utc-seconds (gptel-auto-workflow--parse-iso-timestamp utc-timestamp))
          (local-seconds (gptel-auto-workflow--parse-iso-timestamp local-timestamp)))
      (should (= utc-seconds local-seconds)))))

(provide 'test-gptel-auto-workflow-external-sensors)

;;; test-gptel-auto-workflow-external-sensors.el ends here
