;;; gptel-auto-workflow-production-metrics.el --- Production impact tracking -*- lexical-binding: t -*-

;; Copyright (C) 2026 OV5 Self-Improving Architecture

;; Author: OV5 System
;; Keywords: automation, benchmarking, production-metrics

;;; Commentary:

;; Production metrics integration for Phase 1 of the YC Vision roadmap.
;; Tracks real-world impact of code improvements by querying external
;; monitoring systems (Sentry, DataDog, custom logs).
;;
;; This module extends the benchmark TSV with columns 33-39:
;; - prod_error_rate_before: Error rate before experiment (0.0-1.0)
;; - prod_error_rate_after: Error rate after experiment (0.0-1.0)
;; - prod_error_rate_delta: Change in error rate (-1.0-1.0, negative = improvement)
;; - user_satisfaction_delta: Change in user satisfaction (-1.0-1.0)
;; - support_tickets_reduced: Number of support tickets reduced (integer)
;; - business_value_score: Weighted business value (0.0-1.0)
;; - risk_score: Risk assessment for approval (0.0-1.0)

;;; Code:

(require 'cl-lib)

(declare-function gptel-auto-workflow--expand-workspace-path "gptel-tools-agent-base")

;;; Customization
(defgroup gptel-auto-workflow-production-metrics nil
  "Production metrics weighting for experiment scoring."
  :group 'gptel-auto-workflow)

(defcustom gptel-auto-workflow-production-weight-business-value 0.3
  "Weight multiplier for business-value-score boost on effective-score.
Higher values give more weight to experiments with demonstrated business value.
Range 0.0–1.0. Set to 0.0 to disable business-value boosting."
  :type 'float
  :group 'gptel-auto-workflow-production-metrics)

(defcustom gptel-auto-workflow-production-weight-risk-penalty 0.5
  "Weight multiplier for risk-score penalty on effective-score.
Higher values penalize risky experiments more aggressively.
Range 0.0–1.0. Set to 0.0 to disable risk-based penalty."
  :type 'float
  :group 'gptel-auto-workflow-production-metrics)

;; API configuration
(defvar gptel-auto-workflow--sentry-api-key nil
  "Sentry API key for production metrics.
Set via environment variable OV5_SENTRY_API_KEY or configuration.")

(defvar gptel-auto-workflow--sentry-org "default"
  "Sentry organization slug.")

(defvar gptel-auto-workflow--sentry-project nil
  "Sentry project slug. If nil, inferred from target file.")

(defvar gptel-auto-workflow--production-metrics-cache nil
  "Cache for production metrics queries.
Format: (hash-table target -> (before-rate . after-rate)).")

;; Target-to-service mapping
(defvar gptel-auto-workflow--target-service-map
  '(("lisp/modules/gptel-auto-workflow" . "auto-workflow-core")
    ("lisp/modules/gptel-ext" . "extensions")
    ("lisp/modules/gptel-tools" . "tools")
    ("lisp/modules/gptel-benchmark" . "benchmark")
    ("lisp/modules/gptel-knowledge" . "knowledge"))
  "Mapping from target file paths to service names.
Used to query production metrics for the right service.")

(defun gptel-auto-workflow--get-sentry-key ()
  "Get Sentry API key from environment or configuration."
  (or gptel-auto-workflow--sentry-api-key
      (getenv "OV5_SENTRY_API_KEY")
      (let ((key-file (expand-file-name "~/.ov5/sentry-key")))
        (when (file-exists-p key-file)
          (ignore-errors
            (with-temp-buffer
              (insert-file-contents key-file)
              (string-trim (buffer-string))))))))

(defun gptel-auto-workflow--infer-service-from-target (target)
  "Infer service name from TARGET file path.
Returns service name string or \\='unknown if not mappable."
  (or (cl-loop for (path . service) in gptel-auto-workflow--target-service-map
               when (string-prefix-p path target)
               return service)
      "unknown"))

(defun gptel-auto-workflow--query-sentry-errors (target &optional days-before days-after)
  "Query Sentry for error rates around TARGET experiment.
DAYS-BEFORE: days before experiment to measure baseline (default 7).
DAYS-AFTER: days after experiment to measure impact (default 7).
Returns plist with :before-rate and :after-rate, or nil on failure."
  (let* ((api-key (gptel-auto-workflow--get-sentry-key))
         (service (gptel-auto-workflow--infer-service-from-target target))
         (days-before (or days-before 7))
         (days-after (or days-after 7)))
    (when (and api-key (not (string= service "unknown")))
      (condition-case err
          (let* ((before-end (current-time))
                 (before-start (time-subtract before-end (days-to-time days-before)))
                 (after-start before-end)
                 (after-end (time-add after-start (days-to-time days-after)))
                 ;; Query Sentry API for error rates
                 (before-url (format "https://sentry.io/api/0/projects/%s/%s/stats/?stat=received&since=%d&until=%d"
                                     gptel-auto-workflow--sentry-org
                                     service
                                     (truncate (float-time before-start))
                                     (truncate (float-time before-end))))
                 (after-url (format "https://sentry.io/api/0/projects/%s/%s/stats/?stat=received&since=%d&until=%d"
                                    gptel-auto-workflow--sentry-org
                                    service
                                    (truncate (float-time after-start))
                                    (truncate (float-time after-end))))
                 (before-data (gptel-auto-workflow--http-get-json before-url api-key))
                 (after-data (gptel-auto-workflow--http-get-json after-url api-key)))
            (when (and before-data after-data)
              (let ((before-rate (gptel-auto-workflow--calculate-error-rate before-data))
                    (after-rate (gptel-auto-workflow--calculate-error-rate after-data)))
                (list :before-rate before-rate
                      :after-rate after-rate
                      :service service))))
        (error
         (message "[production-metrics] Sentry query failed for %s: %s"
                  target (error-message-string err))
         nil)))))

(defun gptel-auto-workflow--http-get-json (url api-key)
  "Make HTTP GET request to URL with API-KEY.
Returns parsed JSON or nil on failure."
  (condition-case err
      (with-temp-buffer
        (let ((exit-code
               (call-process "curl" nil t nil
                             "-s" "-H" (format "Authorization: Bearer %s" api-key)
                             url)))
          (when (and exit-code (zerop exit-code))
            (goto-char (point-min))
            (json-parse-buffer :object-type 'plist :array-type 'list))))
    (error
     (message "[production-metrics] HTTP GET failed: %s" (error-message-string err))
     nil)))

(defun gptel-auto-workflow--calculate-error-rate (stats-data)
  "Calculate error rate from Sentry STATS-DATA.
Returns float 0.0-1.0 representing error rate."
  (if (and stats-data (listp stats-data))
      (let* ((raw-events (or (plist-get stats-data :data) '()))
             ;; EDGE CASE: parsed JSON items may not be lists; filter to prevent cadr crash
             (events (delq nil (mapcar (lambda (e) (when (listp e) e)) raw-events)))
             (total-events (apply #'+ (mapcar #'cadr events)))
             (time-span (length events))
             ;; Normalize to rate per day
             (rate (if (> time-span 0)
                       (/ (float total-events) time-span)
                     0.0)))
        ;; Cap at 1.0 for safety
        (min 1.0 (/ rate 1000.0)))
    0.0))

(defun gptel-auto-workflow--query-user-feedback (_target)
  "Query user feedback system for TARGET.
Returns satisfaction delta: -1.0 (worse) to +1.0 (better).
Stub implementation - returns 0.0 until feedback system is integrated."
  ;; TODO: Integrate with Slack, GitHub issues, or custom feedback API
  ;; For now, return neutral delta
  0.0)

(defun gptel-auto-workflow--query-support-tickets (_target)
  "Query support ticket system for TARGET.
Returns number of tickets reduced (integer, 0-N).
Stub implementation - returns 0 until ticket system is integrated."
  ;; TODO: Integrate with Zendesk, Freshdesk, or custom ticket API
  ;; For now, return 0 tickets reduced
  0)

(defun gptel-auto-workflow--track-production-impact (target _experiment-id)
  "Track production impact for TARGET experiment.
EXPERIMENT-ID: unique identifier for this experiment.
Returns plist with production metrics for TSV columns 33-39.
Uses external APIs when available, falls back to local signals."
  (let* ((metrics (or (gptel-auto-workflow--query-sentry-errors target) '()))
         (error-before (or (plist-get metrics :before-rate) 0.0))
         (error-after (or (plist-get metrics :after-rate) 0.0))
         (error-delta (if (plist-get metrics :before-rate)
                          (- error-after error-before)
                        0.0))
         (satisfaction-delta (gptel-auto-workflow--query-user-feedback target))
         (tickets-reduced (gptel-auto-workflow--query-support-tickets target))
         ;; When no external metrics available, compute from local signals
         (local-metrics (when (and (= error-delta 0.0)
                                   (= satisfaction-delta 0.0)
                                   (= tickets-reduced 0))
                          (gptel-auto-workflow--compute-local-business-value target)))
         (business-value (or (and local-metrics (plist-get local-metrics :business-value-score))
                             (gptel-auto-workflow--calculate-business-value
                              error-delta satisfaction-delta tickets-reduced)))
         (risk-score (or (and local-metrics (plist-get local-metrics :risk-score))
                         (gptel-auto-workflow--calculate-production-risk-score
                          error-delta satisfaction-delta tickets-reduced))))
    (list :prod-error-rate-before error-before
          :prod-error-rate-after error-after
          :prod-error-rate-delta error-delta
          :user-satisfaction-delta (or (and local-metrics (plist-get local-metrics :user-satisfaction-delta))
                                       satisfaction-delta)
          :support-tickets-reduced (or (and local-metrics (plist-get local-metrics :support-tickets-reduced))
                                       tickets-reduced)
          :business-value-score business-value
          :risk-score risk-score)))

(defun gptel-auto-workflow--compute-local-business-value (target)
  "Compute business value from LOCAL signals when external APIs are unavailable.
Analyzes Emacs error logs, byte-compile warnings, and test results for TARGET.
Returns plist with :business-value-score, :risk-score, :user-satisfaction-delta, :support-tickets-reduced.

Business value heuristics:
  +0.3  Fix for a function that appears in recent error logs
  +0.2  Target has byte-compile warnings (improving it reduces noise)
  +0.2  Target has no ERT tests (adding tests is high value)
  +0.1  Target is >500 lines (complexity reduction valuable)
  -0.3  Target has no known issues (change is low value)
  -0.2  Change is a trivial nil guard on already-safe code"
  (when (and target (stringp target) (file-exists-p target))
    (let* ((target-basename (file-name-nondirectory target))
           (value 0.0)
           (risk 0.2)  ; baseline: no measurable improvement

           ;; Signal 1: Does this target appear in recent Emacs error logs?
            (error-log-dir (expand-file-name "var/log/" (gptel-auto-workflow--expand-workspace-path "")))
            (recent-logs (when (file-directory-p error-log-dir)
                           (sort (directory-files error-log-dir t "\\.log\\'")
                                 (lambda (a b)
                                   (time-less-p (nth 5 (file-attributes b))
                                                (nth 5 (file-attributes a)))))))
           (target-in-errors
            (cl-block check-logs
              (dolist (log (seq-take (or recent-logs '()) 20))  ; Check 20 most recent logs
                (ignore-errors
                  (with-temp-buffer
                    (insert-file-contents log nil 0 50000)  ; First 50KB
                    (goto-char (point-min))
                    (when (re-search-forward (regexp-quote target-basename) nil t)
                      (cl-return t)))))
              nil))

           ;; Signal 2: Does the target have byte-compile warnings?
           (bytecompile-output (ignore-errors
                                 (with-temp-buffer
                                   (call-process (expand-file-name invocation-name
                                                                     invocation-directory)
                                                 nil t nil
                                                 "-Q" "--batch" "-f" "batch-byte-compile" target)
                                   (buffer-string))))
           (has-warnings (and bytecompile-output
                              (string-match-p "Warning\\|warning" bytecompile-output)))

           ;; Signal 3: Does the target have ERT tests?
           (test-dir (expand-file-name "tests/" (gptel-auto-workflow--expand-workspace-path "")))
           (has-tests (when (file-directory-p test-dir)
                        (cl-block find-test
                          (dolist (f (directory-files test-dir t "\\.el\\'"))
                            (ignore-errors
                              (with-temp-buffer
                                (insert-file-contents f)
                                (when (string-match-p (regexp-quote
                                                       (file-name-sans-extension target-basename))
                                                      (buffer-string))
                                  (cl-return t)))))
                          nil)))

           ;; Signal 4: Target file size (complexity proxy)
           (target-size (or (ignore-errors (file-attribute-size (file-attributes target))) 0))
           (is-complex (> target-size 20000)))  ; >20KB

      ;; Accumulate business value
      (when target-in-errors (setq value (+ value 0.3)))
      (when has-warnings (setq value (+ value 0.2)))
      (when (not has-tests) (setq value (+ value 0.2)))
      (when is-complex (setq value (+ value 0.1)))

      ;; If no positive signals found, the change is likely low value
      (when (and (not target-in-errors) (not has-warnings) (not is-complex))
        (setq value (- value 0.3)))

      ;; Cap at 0.0-1.0
      (setq value (max 0.0 (min 1.0 value)))
      (setq risk (max 0.0 (min 1.0 risk)))

      (list :business-value-score value
            :risk-score risk
            :user-satisfaction-delta 0.0
            :support-tickets-reduced (if target-in-errors 1 0)))))

(defun gptel-auto-workflow--calculate-business-value (error-delta satisfaction-delta tickets-reduced)
  "Calculate business value score from production impact metrics.
ERROR-DELTA: change in error rate (negative = improvement).
SATISFACTION-DELTA: change in user satisfaction (-1.0 to 1.0).
TICKETS-REDUCED: number of support tickets reduced (integer).
Returns weighted score 0.0-1.0.
Weights: error-reduction (40%), support-tickets (30%), satisfaction (30%)."
  (let* ((error-score (min 1.0 (/ (abs (min 0 error-delta)) 0.1)))  ; 10% reduction = 1.0
         (ticket-score (min 1.0 (/ tickets-reduced 10.0)))          ; 10 tickets = 1.0
         (satisfaction-score (/ (+ satisfaction-delta 1.0) 2.0)))   ; -1..1 → 0..1
    (+ (* 0.4 error-score)
       (* 0.3 ticket-score)
       (* 0.3 satisfaction-score))))

(defun gptel-auto-workflow--calculate-production-risk-score (error-delta satisfaction-delta tickets-reduced)
  "Calculate risk score for approval threshold.
ERROR-DELTA: change in error rate.
SATISFACTION-DELTA: change in user satisfaction.
TICKETS-REDUCED: number of support tickets reduced.
Returns risk score 0.0 (low risk) to 1.0 (high risk).

Risk factors:
- Large error rate increase (> 5%) → +0.3
- Satisfaction decrease (> 0.2) → +0.3
- No measurable improvement → +0.2
- High cost experiment → +0.2 (added later in TSV logging)"
  (let ((risk 0.0))
    ;; Risk factor 1: Error rate increased significantly
    (when (> error-delta 0.05)
      (setq risk (+ risk 0.3)))
    ;; Risk factor 2: User satisfaction decreased
    (when (< satisfaction-delta -0.2)
      (setq risk (+ risk 0.3)))
    ;; Risk factor 3: No measurable improvement
    (when (and (>= error-delta 0)
               (<= satisfaction-delta 0)
               (<= tickets-reduced 0))
      (setq risk (+ risk 0.2)))
    ;; Cap at 1.0
    (min 1.0 risk)))

(defun gptel-auto-workflow--get-production-metrics (target)
  "Get production metrics for TARGET, using cache if available.
Returns plist with production metrics or default values if unavailable."
  (when target
    (or (when (hash-table-p gptel-auto-workflow--production-metrics-cache)
          (ignore-errors (gethash target gptel-auto-workflow--production-metrics-cache)))
        (let ((metrics (ignore-errors (gptel-auto-workflow--track-production-impact target nil))))
          (when (and (hash-table-p gptel-auto-workflow--production-metrics-cache) metrics)
            (puthash target metrics gptel-auto-workflow--production-metrics-cache))
          metrics))))

(defun gptel-auto-workflow--init-production-metrics-cache ()
  "Initialize production metrics cache."
  (setq gptel-auto-workflow--production-metrics-cache
        (make-hash-table :test 'equal)))

(defun gptel-auto-workflow--approval-threshold (experiment)
  "Determine approval type based on EXPERIMENT risk score.
Returns :auto (risk < 0.3), :recommend (0.3-0.7), or :required (> 0.7)."
  (let ((risk (or (and experiment (ignore-errors (plist-get experiment :risk-score))) 0.0)))
    (cond
     ((< risk 0.3) :auto)
     ((< risk 0.7) :recommend)
     (t :required))))

(defun gptel-auto-workflow--weight-score-with-production-metrics (score target)
  "Weight SCORE with production metrics for TARGET.
Business-value-score boosts effective-score; risk-score penalizes it.
Formula: effective = score + (business-value * weight) - (risk * weight)
Returns weighted score, or original SCORE if production metrics unavailable."
  (if-let* ((metrics (gptel-auto-workflow--get-production-metrics target))
            (bv (plist-get metrics :business-value-score))
            (risk (plist-get metrics :risk-score)))
      (let ((boost (* bv gptel-auto-workflow-production-weight-business-value))
            (penalty (* risk gptel-auto-workflow-production-weight-risk-penalty)))
        (max 0.0 (min 1.0 (+ score boost (- penalty)))))
    score))

(provide 'gptel-auto-workflow-production-metrics)

;;; gptel-auto-workflow-production-metrics.el ends here
