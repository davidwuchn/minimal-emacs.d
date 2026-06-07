;;; gptel-auto-workflow-external-sensors.el --- External sensors for production monitoring -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OV5 Self-Improving Architecture

;; Author: OV5 System
;; Keywords: sensors, production-monitoring, feedback, business-value

;;; Commentary:

;; Phase 1: External Sensors
;; This module collects production metrics, user feedback, and business value data
;; to close the loop between code quality improvements and real-world impact.
;;
;; Features:
;; - Production metrics collection (Sentry/DataDog integration)
;; - Error rate tracking before/after experiments
;; - User feedback collection mechanism
;; - Business value metrics integration

;;; Code:

(require 'cl-lib)
(require 'json)

;; ============================================================================
;; Configuration
;; ============================================================================

(defvar gptel-auto-workflow--sentry-config nil
  "Sentry client configuration.")

(defvar gptel-auto-workflow--feedback-config nil
  "User feedback collection configuration.")

(defvar gptel-auto-workflow--sensor-data-cache nil
  "Cache for sensor data to avoid redundant API calls.")

;; ============================================================================
;; Task 1.1: Production Metrics Collection
;; ============================================================================

(defun gptel-auto-workflow--sentry-init (config)
  "Initialize Sentry client with CONFIG.
CONFIG is a plist with :dsn and :environment."
  (setq gptel-auto-workflow--sentry-config config)
  t)

(defun gptel-auto-workflow--sentry-configured-p ()
  "Return t if Sentry is configured."
  (and gptel-auto-workflow--sentry-config
       (plist-get gptel-auto-workflow--sentry-config :dsn)))

(defun gptel-auto-workflow--sentry-api-call (endpoint params)
  "Make API call to Sentry ENDPOINT with PARAMS.
Uses curl via call-process. Returns parsed JSON plist or nil on failure.
Requires OV5_SENTRY_API_KEY env var or `gptel-auto-workflow--sentry-api-key'."
  (let ((api-key (or (getenv "OV5_SENTRY_API_KEY")
                     (bound-and-true-p gptel-auto-workflow--sentry-api-key)))
        (base-url (or (and gptel-auto-workflow--sentry-config
                           (plist-get gptel-auto-workflow--sentry-config :base-url))
                      "https://sentry.io/api/0"))
        (org-slug (or (and gptel-auto-workflow--sentry-config
                           (plist-get gptel-auto-workflow--sentry-config :org))
                      (getenv "OV5_SENTRY_ORG")))
        (project-slug (or (and gptel-auto-workflow--sentry-config
                                (plist-get gptel-auto-workflow--sentry-config :project))
                          (getenv "OV5_SENTRY_PROJECT"))))
    (when (and api-key (not (string-empty-p api-key)))
      (let* ((url (cond
                   ;; Full URL already
                   ((string-prefix-p "http" endpoint) endpoint)
                   ;; Project-scoped endpoint
                   ((and org-slug project-slug)
                    (format "%s/projects/%s/%s%s" base-url org-slug project-slug endpoint))
                   ;; Org-scoped endpoint
                   (org-slug
                    (format "%s/organizations/%s%s" base-url org-slug endpoint))
                   ;; Bare endpoint (no org/project)
                   (t (format "%s%s" base-url endpoint))))
             (query-string
              (when params
                (let ((parts nil))
                  (when (plist-get params :start)
                    (push (format "since=%d" (plist-get params :start)) parts))
                  (when (plist-get params :end)
                    (push (format "until=%d" (plist-get params :end)) parts))
                  (when (plist-get params :filter)
                    (push (format "query=%s" (plist-get params :filter)) parts))
                  (when (plist-get params :stat)
                    (push (format "stat=%s" (plist-get params :stat)) parts))
                  (when parts
                    (concat "?" (string-join (nreverse parts) "&"))))))
             (full-url (if query-string (concat url query-string) url)))
        (condition-case err
            (with-temp-buffer
              (let ((exit-code
                     (call-process "curl" nil t nil
                                   "-s" "-f" "-H" (format "Authorization: Bearer %s" api-key)
                                   full-url)))
                (if (and exit-code (zerop exit-code))
                    (progn
                      (goto-char (point-min))
                      (json-parse-buffer :object-type 'plist :array-type 'list))
                  (message "[external-sensors] Sentry API call failed (exit %d): %s %s"
                           (or exit-code -1) endpoint (or query-string ""))
                  nil)))
          (error
           (message "[external-sensors] Sentry API error: %s" (error-message-string err))
           nil))))))

(defun gptel-auto-workflow--query-error-rate (&rest args)
  "Query error rate for time window or module.
ARGS is a plist with :start-time, :end-time, and optional :module."
  (condition-case err
      (let* ((start-time (plist-get args :start-time))
             (end-time (plist-get args :end-time))
             (module (plist-get args :module))
             (params (list :start start-time
                           :end end-time
                           :filter (or module "")))
             (result (gptel-auto-workflow--sentry-api-call "/api/0/issues/" params)))
        (when result
          (let* ((error-count (or (plist-get (car result) :error-count) 0))
                 (request-count (or (plist-get (car result) :request-count) 1)))
            (list :error-rate (if (> request-count 0)
                                  (/ (float error-count) request-count)
                                0.0)
                  :error-count error-count
                  :request-count request-count))))
    (error
     (message "[external-sensors] API error: %s" (error-message-string err))
     nil)))

(defun gptel-auto-workflow--query-performance-metrics (&rest args)
  "Query performance metrics for module.
ARGS is a plist with :module, :start-time, :end-time."
  (let* ((module (plist-get args :module))
         (params (list :module module
                       :start (plist-get args :start-time)
                       :end (plist-get args :end-time)))
         (result (gptel-auto-workflow--sentry-api-call "/api/0/performance/" params)))
    (when result
      (car result))))

(defun gptel-auto-workflow--collect-baseline-metrics (module)
  "Collect baseline metrics for MODULE before experiment.
Returns plist with :error-rate-before, :p50-latency-before, etc."
  (let* ((now (time-to-seconds))
         (one-hour-ago (- now 3600))
         (error-rate-result (gptel-auto-workflow--query-error-rate
                             :module module
                             :start-time one-hour-ago
                             :end-time now))
         (error-rate (if (listp error-rate-result)
                         (car error-rate-result)
                       error-rate-result))
         (performance-result (gptel-auto-workflow--query-performance-metrics
                              :module module
                              :start-time one-hour-ago
                              :end-time now))
         (performance (if (listp performance-result)
                          (car performance-result)
                        performance-result)))
    (list :error-rate-before (or (plist-get error-rate :error-rate) 0.0)
          :error-count-before (or (plist-get error-rate :error-count) 0)
          :request-count-before (or (plist-get error-rate :request-count) 0)
          :p50-latency-before (or (plist-get performance :p50-latency) 0)
          :p95-latency-before (or (plist-get performance :p95-latency) 0)
          :throughput-before (or (plist-get performance :throughput) 0))))

;; ============================================================================
;; Task 1.2: Error Rate Tracking Before/After Experiments
;; ============================================================================

(defun gptel-auto-workflow--collect-post-experiment-metrics (module &rest _args)
  "Collect metrics after experiment for MODULE.
ARGS may include :wait-hours to wait before collecting."
  (let* ((now (time-to-seconds))
         (one-hour-ago (- now 3600))
         (error-rate-result (gptel-auto-workflow--query-error-rate
                             :module module
                             :start-time one-hour-ago
                             :end-time now))
         (error-rate (if (listp error-rate-result)
                         (car error-rate-result)
                       error-rate-result))
         (performance-result (gptel-auto-workflow--query-performance-metrics
                              :module module
                              :start-time one-hour-ago
                              :end-time now))
         (performance (if (listp performance-result)
                          (car performance-result)
                        performance-result)))
    (list :error-rate-after (or (plist-get error-rate :error-rate) 0.0)
          :error-count-after (or (plist-get error-rate :error-count) 0)
          :request-count-after (or (plist-get error-rate :request-count) 0)
          :p50-latency-after (or (plist-get performance :p50-latency) 0)
          :p95-latency-after (or (plist-get performance :p95-latency) 0)
          :throughput-after (or (plist-get performance :throughput) 0))))

(defun gptel-auto-workflow--calculate-error-rate-impact (before after)
  "Calculate error rate impact between BEFORE and AFTER metrics.
BEFORE and AFTER are plists with :error-rate, :error-count, :request-count.
Returns plist with :error-rate-improvement-pct, :errors-reduced, :direction."
  (let* ((before-metrics (if (listp (car before)) (car before) before))
         (after-metrics (if (listp (car after)) (car after) after))
         (before-rate (or (plist-get before-metrics :error-rate) 0.0))
         (after-rate (or (plist-get after-metrics :error-rate) 0.0))
         (before-count (or (plist-get before-metrics :error-count) 0))
         (after-count (or (plist-get after-metrics :error-count) 0))
         (improvement-pct (if (> before-rate 0.0)
                              (/ (float (- before-rate after-rate)) before-rate)
                            0.0))
         (errors-reduced (- before-count after-count))
         (direction (cond
                     ((> improvement-pct 0.0) :improved)
                     ((< improvement-pct 0.0) :regressed)
                     (t :unchanged))))
    (list :error-rate-improvement-pct improvement-pct
          :errors-reduced errors-reduced
          :direction direction)))

(defun gptel-auto-workflow--calculate-performance-impact (before after)
  "Calculate performance impact between BEFORE and AFTER metrics.
BEFORE and AFTER are plists with :p50-latency, :p95-latency,
:throughput.  Returns plist with :latency-improvement-pct,
:throughput-improvement-pct, :direction."
  (let* ((before-metrics (if (listp (car before)) (car before) before))
         (after-metrics (if (listp (car after)) (car after) after))
         (before-latency (or (plist-get before-metrics :p50-latency) 0))
         (after-latency (or (plist-get after-metrics :p50-latency) 0))
         (before-throughput (or (plist-get before-metrics :throughput) 0))
         (after-throughput (or (plist-get after-metrics :throughput) 0))
         (latency-improvement-pct (if (> before-latency 0)
                                      (/ (float (- before-latency after-latency)) before-latency)
                                    0.0))
         (throughput-improvement-pct (if (> before-throughput 0)
                                         (/ (float (- after-throughput before-throughput)) before-throughput)
                                       0.0))
         (direction (cond
                     ((or (> latency-improvement-pct 0.0) (> throughput-improvement-pct 0.0)) :improved)
                     ((or (< latency-improvement-pct 0.0) (< throughput-improvement-pct 0.0)) :regressed)
                     (t :unchanged))))
    (list :latency-improvement-pct latency-improvement-pct
          :throughput-improvement-pct throughput-improvement-pct
          :direction direction)))

(defun gptel-auto-workflow--schedule-post-experiment-collection (module _experiment-id)
  "Schedule metrics collection 24 hours after experiment deployment.
Returns timer object."
  (run-with-timer (* 24 3600) nil
                  (lambda ()
                    (gptel-auto-workflow--collect-post-experiment-metrics module))))

;; ============================================================================
;; Task 1.3: User Feedback Collection
;; ============================================================================

(defun gptel-auto-workflow--feedback-init (config)
  "Initialize user feedback collection with CONFIG.
CONFIG is a plist with :webhook-endpoint, :storage-backend, :retention-days."
  (setq gptel-auto-workflow--feedback-config config)
  t)

(defun gptel-auto-workflow--feedback-configured-p ()
  "Return t if feedback collection is configured."
  (and gptel-auto-workflow--feedback-config
       (plist-get gptel-auto-workflow--feedback-config :webhook-endpoint)))

(defun gptel-auto-workflow--feedback-query (module start-time end-time)
  "Query feedback for MODULE between START-TIME and END-TIME.
Uses configured webhook endpoint if available, otherwise returns nil.
Webhook endpoint is set via OV5_FEEDBACK_ENDPOINT env var or feedback config."
  (let ((endpoint (or (and gptel-auto-workflow--feedback-config
                           (plist-get gptel-auto-workflow--feedback-config :webhook-endpoint))
                      (getenv "OV5_FEEDBACK_ENDPOINT"))))
    (when (and endpoint (not (string-empty-p endpoint)))
      (let* ((req-url (format "%s?module=%s&start=%d&end=%d"
                              endpoint
                              (shell-quote-argument (or module ""))
                              (round start-time)
                              (round end-time)))
             (result (condition-case err
                         (with-temp-buffer
                           (let ((exit-code (call-process "curl" nil t nil "-s" "-f" req-url)))
                             (if (and exit-code (zerop exit-code))
                                 (progn
                                   (goto-char (point-min))
                                   (json-parse-buffer :object-type 'plist :array-type 'list))
                               nil)))
                       (error
                        (message "[external-sensors] Feedback query error: %s" (error-message-string err))
                        nil))))
        result))))

(defun gptel-auto-workflow--collect-user-feedback (module &rest args)
  "Collect user feedback for MODULE.
ARGS may include :start-time and :end-time."
  (let* ((start-time (or (plist-get args :start-time)
                         (- (time-to-seconds) (* 7 24 3600))))
         (end-time (or (plist-get args :end-time) (time-to-seconds)))
         (feedback (gptel-auto-workflow--feedback-query module start-time end-time)))
    (when feedback
      (let* ((positive (or (plist-get (car feedback) :positive) 0))
             (negative (or (plist-get (car feedback) :negative) 0))
             (neutral (or (plist-get (car feedback) :neutral) 0))
             (total (+ positive negative neutral))
             (satisfaction-rate (if (> total 0)
                                    (/ (float positive) total)
                                  0.0)))
        (list :positive positive
              :negative negative
              :neutral neutral
              :satisfaction-rate satisfaction-rate
              :sample-complaints (plist-get (car feedback) :sample-complaints))))))

(defun gptel-auto-workflow--calculate-feedback-impact (before after)
  "Calculate user satisfaction improvement from BEFORE to AFTER.
BEFORE and AFTER are plists with :satisfaction-rate, :negative, etc.
Returns plist with :satisfaction-improvement-pct,
:complaints-reduced, :direction."
  (let* ((before-metrics (if (listp (car before)) (car before) before))
         (after-metrics (if (listp (car after)) (car after) after))
         (satisfaction-before (or (plist-get before-metrics :satisfaction-rate) 0.0))
         (satisfaction-after (or (plist-get after-metrics :satisfaction-rate) 0.0))
         (negative-before (or (plist-get before-metrics :negative) 0))
         (negative-after (or (plist-get after-metrics :negative) 0))
         (improvement-pct (if (> satisfaction-before 0)
                              (/ (- satisfaction-after satisfaction-before)
                                 satisfaction-before)
                            0.0))
         (complaints-reduced (- negative-before negative-after))
         (direction (cond
                     ((> improvement-pct 0.01) :improved)
                     ((< improvement-pct -0.01) :regressed)
                     (t :unchanged))))
    (list :satisfaction-improvement-pct improvement-pct
          :complaints-reduced complaints-reduced
          :direction direction)))

(defun gptel-auto-workflow--parse-feedback-webhook (webhook-data)
  "Parse incoming feedback WEBHOOK-DATA.
WEBHOOK-DATA can be a plist or a list containing a plist.
Returns normalized feedback entry."
  (let* ((data (if (listp (car webhook-data)) (car webhook-data) webhook-data))
         (feedback-type (plist-get data :feedback-type))
         (sentiment (cond
                     ((string= feedback-type "complaint") :negative)
                     ((string= feedback-type "praise") :positive)
                     (t :neutral)))
         (severity-str (or (plist-get data :severity) "low"))
         (severity (intern (concat ":" severity-str))))
    (list :module (plist-get data :module)
          :message (plist-get data :message)
          :sentiment sentiment
          :severity severity
          :timestamp (plist-get data :timestamp))))

(defun gptel-auto-workflow--aggregate-feedback-sentiment (feedback-items)
  "Aggregate sentiment from multiple FEEDBACK-ITEMS.
Returns plist with :positive, :negative, :neutral counts and :satisfaction-rate."
  (let ((positive 0)
        (negative 0)
        (neutral 0))
    (dolist (item feedback-items)
      (let ((sentiment (plist-get item :sentiment)))
        (cond
         ((eq sentiment :positive) (setq positive (1+ positive)))
         ((eq sentiment :negative) (setq negative (1+ negative)))
         (t (setq neutral (1+ neutral))))))
    (let* ((total (+ positive negative neutral))
           (satisfaction-rate (if (> total 0)
                                  (/ (float positive) total)
                                0.0)))
      (list :positive positive
            :negative negative
            :neutral neutral
            :satisfaction-rate satisfaction-rate))))

;; ============================================================================
;; Task 1.4: Business Value Metrics Integration
;; ============================================================================

(defun gptel-auto-workflow--define-business-value-metrics (experiment)
  "Define business value metrics for EXPERIMENT.
Returns plist with :business-value-score."
  (let ((error-rate-improvement (or (plist-get experiment :error-rate-improvement) 0.0))
        (complaints-reduced (or (plist-get experiment :complaints-reduced) 0))
        (performance-improvement (or (plist-get experiment :performance-improvement) 0.0))
        (development-time-saved (or (plist-get experiment :development-time-saved-hours) 0)))
    ;; Normalize to 0-1 range and weight
    (let* ((error-score (min 1.0 (max 0.0 error-rate-improvement)))
           (complaint-score (min 1.0 (/ (float complaints-reduced) 10.0)))
           (performance-score (min 1.0 (max 0.0 performance-improvement)))
           (time-score (min 1.0 (/ development-time-saved 20.0)))
           (weighted-score (+ (* 0.4 error-score)
                              (* 0.3 complaint-score)
                              (* 0.2 performance-score)
                              (* 0.1 time-score))))
      (list :business-value-score weighted-score
            :error-score error-score
            :complaint-score complaint-score
            :performance-score performance-score
            :time-score time-score))))

(defun gptel-auto-workflow--calculate-business-value-score (metrics weights)
  "Calculate weighted business value score from METRICS and WEIGHTS.
METRICS is a plist with :error-rate-improvement, :satisfaction-improvement, etc.
WEIGHTS is a plist with :error-rate-weight, :user-satisfaction-weight, etc.
Returns weighted score 0.0-1.0."
  (let* ((error-rate-improvement (or (plist-get metrics :error-rate-improvement) 0.0))
         (satisfaction-improvement (or (plist-get metrics :satisfaction-improvement) 0.0))
         (performance-improvement (or (plist-get metrics :performance-improvement) 0.0))
         (development-time-saved (or (plist-get metrics :development-time-saved) 0.0))
         (error-weight (or (plist-get weights :error-rate-weight) 0.4))
         (satisfaction-weight (or (plist-get weights :user-satisfaction-weight) 0.3))
         (performance-weight (or (plist-get weights :performance-weight) 0.2))
         (time-weight (or (plist-get weights :development-efficiency-weight) 0.1))
         ;; Normalize to 0-1 range
         (error-score (min 1.0 (max 0.0 error-rate-improvement)))
         (satisfaction-score (min 1.0 (max 0.0 satisfaction-improvement)))
         (performance-score (min 1.0 (max 0.0 performance-improvement)))
         (time-score (min 1.0 (/ development-time-saved 20.0)))
         ;; Calculate weighted score
         (weighted-score (+ (* error-weight error-score)
                            (* satisfaction-weight satisfaction-score)
                            (* performance-weight performance-score)
                            (* time-weight time-score))))
    (min 1.0 (max 0.0 weighted-score))))

(defun gptel-auto-workflow--calculate-business-value-roi (experiment)
  "Calculate business value ROI for EXPERIMENT.
Returns plist with :roi-percentage and :value-per-dollar."
  (let* ((cost-usd (or (plist-get experiment :cost-usd) 0.0))
          (_business-value-score (or (plist-get experiment :business-value-score) 0.0))
         (errors-reduced (or (plist-get experiment :errors-reduced) 0))
         (support-tickets-reduced (or (plist-get experiment :support-tickets-reduced) 0))
         (development-hours-saved (or (plist-get experiment :development-hours-saved) 0))
         ;; Estimate business value in dollars
         (error-value (* errors-reduced 50.0))  ;; $50 per error prevented
         (ticket-value (* support-tickets-reduced 100.0))  ;; $100 per ticket
         (time-value (* development-hours-saved 150.0))  ;; $150 per hour
         (total-value (+ error-value ticket-value time-value))
         (value-per-dollar (if (> cost-usd 0)
                               (/ total-value cost-usd)
                             0.0))
         (roi-percentage (* (- value-per-dollar 1.0) 100.0)))
    (list :roi-percentage roi-percentage
          :value-per-dollar value-per-dollar
          :total-value total-value
          :cost-usd cost-usd)))

(defun gptel-auto-workflow--integrate-business-value-into-scoring (experiment
                                                                    &rest args)
  "Integrate business value into experiment scoring.
EXPERIMENT is a plist with :code-quality-score and :business-value-score.
ARGS may include :business-value-weight and :code-quality-weight.
Returns experiment with :combined-score."
  (let* ((business-value-score (or (plist-get experiment :business-value-score) 0.0))
         (code-quality-score (or (plist-get experiment :code-quality-score) 0.0))
         (business-value-weight (or (plist-get args :business-value-weight) 0.6))
         (code-quality-weight (or (plist-get args :code-quality-weight) 0.4))
         (combined-score (+ (* business-value-weight business-value-score)
                            (* code-quality-weight code-quality-score))))
    (append experiment
            (list :combined-score combined-score
                  :business-value-score business-value-score
                  :code-quality-score code-quality-score))))

(defun gptel-auto-workflow--prioritize-experiments-by-business-value (experiments
                                                                       &rest args)
  "Prioritize EXPERIMENTS by business value.
ARGS may include :business-value-weight.
Returns sorted list of experiments."
  (let ((business-value-weight (or (plist-get args :business-value-weight) 0.6)))
    (sort (copy-sequence experiments)
          (lambda (a b)
            (let* ((a-bv (or (plist-get a :business-value-score) 0.0))
                   (a-cq (or (plist-get a :code-quality-score) 0.0))
                   (a-combined (+ (* business-value-weight a-bv)
                                  (* (- 1.0 business-value-weight) a-cq)))
                   (b-bv (or (plist-get b :business-value-score) 0.0))
                   (b-cq (or (plist-get b :code-quality-score) 0.0))
                   (b-combined (+ (* business-value-weight b-bv)
                                  (* (- 1.0 business-value-weight) b-cq))))
              (> a-combined b-combined))))))

(defun gptel-auto-workflow--generate-business-impact-report (experiments)
  "Generate business impact report for EXPERIMENTS.
Returns plist with :total-business-value, :total-cost,
:overall-roi, :top-performing-experiments."
  (let ((total-business-value 0.0)
        (total-cost 0.0)
        (sorted-experiments (sort (copy-sequence experiments)
                                  (lambda (a b)
                                    (> (or (plist-get a :business-value-score) 0.0)
                                       (or (plist-get b :business-value-score) 0.0))))))
    (dolist (exp experiments)
      (setq total-business-value (+ total-business-value
                                    (or (plist-get exp :business-value-score) 0.0)))
      (setq total-cost (+ total-cost (or (plist-get exp :cost-usd) 0.0))))
    (let ((overall-roi (if (> total-cost 0)
                           (/ total-business-value total-cost)
                         0.0)))
      (list :total-business-value total-business-value
            :total-cost total-cost
            :overall-roi overall-roi
            :top-performing-experiments (seq-take sorted-experiments 5)))))

;; ============================================================================
;; Integration
;; ============================================================================

(defun gptel-auto-workflow--full-sensor-pipeline (module experiment-id)
  "Run full external sensor pipeline for MODULE and EXPERIMENT-ID.
Returns plist with all sensor data."
  (let* ((baseline (gptel-auto-workflow--collect-baseline-metrics module))
         (post-metrics (when baseline
                         (gptel-auto-workflow--collect-post-experiment-metrics module)))
         (user-feedback (gptel-auto-workflow--collect-user-feedback module))
         (error-rate-impact (when (and baseline post-metrics)
                              (gptel-auto-workflow--calculate-error-rate-impact
                               baseline post-metrics)))
         (performance-impact (when (and baseline post-metrics)
                               (gptel-auto-workflow--calculate-performance-impact
                                baseline post-metrics)))
         (feedback-impact user-feedback)  ;; Simplified for now
         (business-value-metrics (list :error-rate-improvement
                                       (or (plist-get error-rate-impact :error-rate-improvement-pct) 0.0)
                                       :performance-improvement
                                       (or (plist-get performance-impact :latency-improvement-pct) 0.0)
                                       :complaints-reduced
                                       (or (plist-get feedback-impact :negative) 0)))
         (business-value-score (gptel-auto-workflow--calculate-business-value-score
                                business-value-metrics
                                '(:error-rate-weight 0.4
                                  :user-satisfaction-weight 0.3
                                  :performance-weight 0.2
                                  :development-efficiency-weight 0.1))))
    (list :experiment-id experiment-id
          :module module
          :baseline-metrics baseline
          :post-metrics post-metrics
          :user-feedback user-feedback
          :error-rate-impact error-rate-impact
          :performance-impact performance-impact
          :feedback-impact feedback-impact
          :business-value-score (or business-value-score 0.0))))

;; ============================================================================
;; Persistence
;; ============================================================================

(defun gptel-auto-workflow--persist-sensor-data (data file)
  "Persist sensor DATA to FILE as JSON."
  (with-temp-file file
    (insert (json-encode data))))

(defun gptel-auto-workflow--load-sensor-data (file)
  "Load sensor data from FILE.
Returns plist or nil if file doesn't exist."
  (when (file-exists-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (let ((json-object-type 'plist)
            (json-array-type 'list))
        (json-read-from-string (buffer-string))))))

;; ============================================================================
;; Task 1.3: GitHub Issues Sensor (external user feedback)
;; ============================================================================

(defcustom gptel-auto-workflow-github-repo nil
  "GitHub repo for issue sensing in OWNER/REPO format.
When nil, attempts auto-detection from git remote.
Set to a string like \"davidwu/minimal-emacs.d\" to override."
  :type '(choice (const nil) string)
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-github-issues-days 7
  "Number of days to look back for GitHub issues."
  :type 'integer
  :group 'gptel-tools-agent)

(defun gptel-auto-workflow--github-detect-repo ()
  "Auto-detect GitHub repo from git remote.
Returns OWNER/REPO string or nil."
  (let ((remote-url (condition-case nil
                        (with-temp-buffer
                          (call-process "git" nil t nil
                                        "remote" "get-url" "origin")
                          (goto-char (point-min))
                          (buffer-substring (point-min) (line-end-position)))
                      (error nil))))
    (when (stringp remote-url)
      (cond
       ;; SSH: git@github.com:OWNER/REPO.git
       ((string-match "github\\.com:\\(.+?\\)\\(\\.git\\)?$" remote-url)
        (match-string 1 remote-url))
       ;; HTTPS: https://github.com/OWNER/REPO.git
       ((string-match "github\\.com/\\(.+?\\)\\(\\.git\\)?$" remote-url)
        (match-string 1 remote-url))
       (t nil)))))

(defun gptel-auto-workflow--github-repo ()
  "Return the GitHub repo to query, or nil if unavailable."
  (or gptel-auto-workflow-github-repo
      (gptel-auto-workflow--github-detect-repo)))

(defun gptel-auto-workflow--github-fetch-issues (repo &optional days)
  "Fetch recent GitHub issues for REPO via gh CLI.
DAYS is the lookback window (default: `github-issues-days').
Returns a plist with :open-issues, :closed-issues, :labels,
:top-issues (list of plists), :error-count, :bug-count,
:enhancement-count, :fetched-at, or nil on failure."
  (let* ((days (or days gptel-auto-workflow-github-issues-days))
         (since (format-time-string "%Y-%m-%dT%H:%M:%SZ"
                                    (time-subtract
                                     (current-time)
                                     (days-to-time days))))
         (output (condition-case nil
                     (with-temp-buffer
                       (let ((rc (call-process
                                  "gh" nil t nil
                                  "issue" "list"
                                  "--repo" repo
                                  "--state" "all"
                                  "--limit" "50"
                                  "--json"
                                  "number,title,labels,state,createdAt,closedAt,comments"
                                  "--search" (format "updated:>=%s" since))))
                         (when (and (numberp rc) (= rc 0))
                           (goto-char (point-min))
                           (buffer-string))))
                   (error nil))))
    (when (and output (> (length output) 10))
      (condition-case nil
          (let* ((json-object-type 'plist)
                 (json-array-type 'list)
                 (issues (json-read-from-string output))
                 (open-issues 0)
                 (closed-issues 0)
                 (bug-count 0)
                 (enhancement-count 0)
                 (label-counts (make-hash-table :test 'equal))
                 (top-issues nil))
            (dolist (issue issues)
              (if (equal (plist-get issue :state) "OPEN")
                  (setq open-issues (1+ open-issues))
                (setq closed-issues (1+ closed-issues)))
              (dolist (label (plist-get issue :labels))
                (let ((name (downcase (or (plist-get label :name) ""))))
                  (puthash name (1+ (gethash name label-counts 0))
                           label-counts)
                  (cond ((member name '("bug" "error" "crash" "regression"))
                         (setq bug-count (1+ bug-count)))
                        ((member name '("enhancement" "feature" "improvement"))
                         (setq enhancement-count (1+ enhancement-count))))))
              (when (< (length top-issues) 10)
                (push (list :number (plist-get issue :number)
                            :title (plist-get issue :title)
                            :state (plist-get issue :state)
                            :labels (mapcar (lambda (l) (plist-get l :name))
                                            (plist-get issue :labels))
                            :comments (length (plist-get issue :comments)))
                      top-issues)))
            (list :open-issues open-issues
                  :closed-issues closed-issues
                  :total (length issues)
                  :bug-count bug-count
                  :enhancement-count enhancement-count
                  :label-distribution
                  (let ((r nil))
                    (maphash (lambda (k v) (push (cons k v) r)) label-counts)
                    (sort r (lambda (a b) (> (cdr a) (cdr b)))))
                  :top-issues (nreverse top-issues)
                  :repo repo
                  :window-days days
                  :fetched-at (format-time-string "%Y-%m-%dT%H:%M:%S")))
        (error nil)))))

(defun gptel-auto-workflow--github-sensor-collect ()
  "Collect GitHub Issues sensor data for the evolution cycle.
Returns the issues plist from --github-fetch-issues, or nil.
Auto-detects repo from git remote."
  (let ((repo (gptel-auto-workflow--github-repo)))
    (when repo
      (message "[github-sensor] Fetching issues for %s (last %d days)"
               repo gptel-auto-workflow-github-issues-days)
      (let ((data (gptel-auto-workflow--github-fetch-issues
                   repo gptel-auto-workflow-github-issues-days)))
        (when data
          (message "[github-sensor] %d open, %d closed, %d bugs, %d enhancements"
                   (plist-get data :open-issues)
                   (plist-get data :closed-issues)
                   (plist-get data :bug-count)
                   (plist-get data :enhancement-count))
          data)))))

(defun gptel-auto-workflow--github-sensor-summary ()
  "Return a concise summary string for the metrics dashboard."
  (let ((data (gptel-auto-workflow--github-sensor-collect)))
    (if data
        (format "GitHub Issues [%s]: %d open, %d closed, %d bugs, %d enhancements (last %dd)"
                (plist-get data :repo)
                (plist-get data :open-issues)
                (plist-get data :closed-issues)
                (plist-get data :bug-count)
                (plist-get data :enhancement-count)
                (plist-get data :window-days))
      "GitHub Issues: not configured (no gh CLI or repo detected)")))

;; ============================================================================
;; Edge Cases
;; ============================================================================

(defun gptel-auto-workflow--parse-iso-timestamp (timestamp)
  "Parse ISO 8601 TIMESTAMP to seconds since epoch.
Handles both UTC (Z suffix) and timezone offsets (+HH:MM)."
  (let ((time (parse-time-string timestamp)))
    (time-to-seconds (encode-time time))))

(provide 'gptel-auto-workflow-external-sensors)

;;; gptel-auto-workflow-external-sensors.el ends here
