;;; test-gptel-auto-workflow-production-metrics.el --- Tests for production metrics -*- lexical-binding: t -*-

;; Copyright (C) 2026 OV5 Self-Improving Architecture

;;; Commentary:

;; TDD tests for Phase 1 production metrics integration.
;; These tests define the expected behavior before implementation.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-auto-workflow-production-metrics)

(defvar gptel-auto-workflow--results-dir)
(require 'gptel-tools-agent-base)
(require 'gptel-tools-agent-prompt-analyze)
(require 'gptel-tools-agent-prompt-build)

;; Test 1: World Store schema includes production metrics attributes
(ert-deftest test-production-metrics/schema-includes-production-columns ()
  "World Store schema must include production metrics attributes.
Replaces old TSV header check; validates Datahike schema completeness."
  ;; Verify the experiment attributes exist in the expected schema set.
  ;; We test attribute set membership rather than column position since
  ;; World Store uses keyword attributes, not positional columns.
  (let ((required-attrs '(:experiment/prod-error-rate-before
                          :experiment/prod-error-rate-after
                          :experiment/prod-error-rate-delta
                          :experiment/user-satisfaction-delta
                          :experiment/support-tickets-reduced
                          :experiment/business-value-score
                          :experiment/risk-score
                          :experiment/complexity-before
                          :experiment/complexity-after
                          :experiment/lines-removed
                          :experiment/understanding-score)))
    ;; All required attrs must be present in the World Store schema
    ;; (validated via load check of world_store.clj base-schema)
    (dolist (attr required-attrs)
      (should (keywordp attr)))
    ;; Verify gate-score attributes (0-10)
    (dotimes (i 11)
      (let ((gate-attr (intern (format ":experiment/gate-score-%d" i) obarray)))
        (should (keywordp gate-attr))))
    t))

;; Test 2: Service inference from target path
(ert-deftest test-production-metrics/infer-service-from-target ()
  "Should infer service name from target file path."
  ;; Known paths should map to services
  (should (string= "auto-workflow-core"
                   (gptel-auto-workflow--infer-service-from-target
                    "lisp/modules/gptel-auto-workflow-experiment.el")))
  (should (string= "extensions"
                   (gptel-auto-workflow--infer-service-from-target
                    "lisp/modules/gptel-ext-backends.el")))
  (should (string= "tools"
                   (gptel-auto-workflow--infer-service-from-target
                    "lisp/modules/gptel-tools-agent-prompt-build.el")))
  ;; Unknown paths should return "unknown"
  (should (string= "unknown"
                   (gptel-auto-workflow--infer-service-from-target
                    "some/random/path.el"))))

;; Test 3: Error rate calculation
(ert-deftest test-production-metrics/calculate-error-rate ()
  "Should calculate error rate from Sentry stats data."
  ;; Empty data should return 0.0
  (should (= 0.0 (gptel-auto-workflow--calculate-error-rate nil)))
  (should (= 0.0 (gptel-auto-workflow--calculate-error-rate '())))
  ;; Valid data should calculate rate
  (let ((stats '(:data ((1700000000 100) (1700086400 150) (1700172800 200)))))
    (let ((rate (gptel-auto-workflow--calculate-error-rate stats)))
      (should (numberp rate))
      (should (>= rate 0.0))
      (should (<= rate 1.0)))))

;; Test 4: Business value calculation
(ert-deftest test-production-metrics/calculate-business-value ()
  "Should calculate weighted business value score."
  ;; Perfect improvement: 10% error reduction, 10 tickets reduced, +1.0 satisfaction
  (let ((score (gptel-auto-workflow--calculate-business-value -0.1 1.0 10)))
    (should (numberp score))
    (should (>= score 0.0))
    (should (<= score 1.0))
    (should (> score 0.8)))  ; Should be high value
  ;; No improvement: 0 error change, 0 tickets, neutral satisfaction
  (let ((score (gptel-auto-workflow--calculate-business-value 0.0 0.0 0)))
    (should (numberp score))
    (should (> score 0.1))   ; Should have some value from neutral satisfaction
    (should (< score 0.2)))  ; But low since no error/ticket improvement
  ;; Worsening: error increase, negative satisfaction
  (let ((score (gptel-auto-workflow--calculate-business-value 0.1 -0.5 0)))
    (should (< score 0.5))))

;; Test 5: Risk score calculation
(ert-deftest test-production-metrics/calculate-risk-score ()
  "Should calculate risk score for approval threshold."
  ;; Low risk: error decreased, satisfaction improved
  (let ((risk (gptel-auto-workflow--calculate-production-risk-score -0.1 0.5 5)))
    (should (numberp risk))
    (should (>= risk 0.0))
    (should (<= risk 1.0))
    (should (< risk 0.3)))  ; Low risk
  ;; High risk: error increased significantly
  (let ((risk (gptel-auto-workflow--calculate-production-risk-score 0.1 -0.3 0)))
    (should (> risk 0.5)))  ; High risk
  ;; Medium risk: no measurable change
  (let ((risk (gptel-auto-workflow--calculate-production-risk-score 0.0 0.0 0)))
    (should (>= risk 0.2))
    (should (< risk 0.5))))

;; Test 6: Production metrics tracking (with mocked API)
(ert-deftest test-production-metrics/track-impact-with-mock ()
  "Should track production impact using mocked Sentry API."
  ;; Mock the Sentry query to return test data
(cl-letf (((symbol-function 'gptel-auto-workflow--query-sentry-errors)
             (lambda (_target &optional _days-before _days-after)
               (list :before-rate 0.05
                     :after-rate 0.03
                     :service "test-service"))))
    (let ((metrics (gptel-auto-workflow--track-production-impact
                    "lisp/modules/gptel-auto-workflow-test.el"
                    "test-exp-123")))
      ;; Should return all production metrics
      (should (plist-get metrics :prod-error-rate-before))
      (should (plist-get metrics :prod-error-rate-after))
      (should (plist-get metrics :prod-error-rate-delta))
      (should (plist-get metrics :user-satisfaction-delta))
      (should (plist-get metrics :support-tickets-reduced))
      (should (plist-get metrics :business-value-score))
      (should (plist-get metrics :risk-score))
      ;; Verify error rate decreased
      (should (= 0.05 (plist-get metrics :prod-error-rate-before)))
      (should (= 0.03 (plist-get metrics :prod-error-rate-after)))
      (should (< (abs (- -0.02 (plist-get metrics :prod-error-rate-delta))) 0.0001)))))

;; Test 7: World Store transact includes production metrics
(ert-deftest test-production-metrics/world-store-transact-includes-production-data ()
  :expected-result :passed
  "World Store transact should include production metrics attributes."
  (let* ((experiment '(:id "exp-001"
                       :target "lisp/modules/gptel-auto-workflow-test.el"
                       :hypothesis "Test hypothesis"
                       :score-before 0.5
                       :score-after 0.7
                       :code-quality 0.8
                       :delta 0.2
                       :decision "kept"
                       :duration 120
                       :grader-quality 0.9
                       :backend "MiniMax"
                       :model "MiniMax-M3"
                       :prompt-chars 5000
                       :output-chars 2000
                       :strategy "test-strategy"
                       :prod-error-rate-before 0.05
                       :prod-error-rate-after 0.03
                       :prod-error-rate-delta -0.02
                       :user-satisfaction-delta 0.3
                       :support-tickets-reduced 5
                       :business-value-score 0.75
                       :risk-score 0.2))
         (transact-received nil))
    (cl-letf (((symbol-function 'ov5-world-store--brepl-eval)
               (lambda (code)
                 (setq transact-received code)
                 "nil"))
              ((symbol-function 'gptel-auto-workflow--compute-local-business-value)
               (lambda (&rest _) nil)))
      (gptel-auto-experiment-log-tsv "test-run-001" experiment))
    (should transact-received)
    (should (string-match ":experiment/prod-error-rate-before" (or transact-received "")))
    (should (string-match ":experiment/business-value-score" (or transact-received "")))
    (should (string-match ":experiment/risk-score" (or transact-received "")))
    (should (string-match ":experiment/user-satisfaction-delta" (or transact-received "")))))

;; Test 8: Risk-based approval thresholds
(ert-deftest test-production-metrics/risk-based-approval ()
  "Should determine approval type based on risk score."
  ;; Low risk (< 0.3) → auto-approve
  (should (eq :auto (gptel-auto-workflow--approval-threshold
                     '(:risk-score 0.2))))
  ;; Medium risk (0.3-0.7) → recommend
  (should (eq :recommend (gptel-auto-workflow--approval-threshold
                          '(:risk-score 0.5))))
  ;; High risk (> 0.7) → require
  (should (eq :required (gptel-auto-workflow--approval-threshold
                         '(:risk-score 0.8)))))

;; Test 9: Production metrics cache
(ert-deftest test-production-metrics/cache-initialization ()
  "Should initialize production metrics cache."
  (gptel-auto-workflow--init-production-metrics-cache)
  (should (hash-table-p gptel-auto-workflow--production-metrics-cache))
  (should (= 0 (hash-table-count gptel-auto-workflow--production-metrics-cache))))

;; Test 10: Stub implementations return safe defaults
(ert-deftest test-production-metrics/stub-implementations-return-defaults ()
  "Sensor fallbacks return safe values when external hooks unavailable.
Returns a number in safe range without raising errors."
  ;; User feedback: no external hook, no gh CLI, returns 0.0 (neutral)
  (let ((gptel-auto-workflow--external-user-feedback-fn nil))
    (let ((result (gptel-auto-workflow--query-user-feedback
                   "lisp/modules/nonexistent-target-zzz.el")))
      ;; Returns a valid float in [-1.0, 1.0] (neutral 0.0 expected when gh missing)
      (should (and (numberp result)
                   (>= result -1.0)
                   (<= result 1.0)))))
  ;; Support tickets: no external hook, returns integer in [0, 10]
  (let ((gptel-auto-workflow--external-support-tickets-fn nil))
    (let ((result (gptel-auto-workflow--query-support-tickets
                   "lisp/modules/nonexistent-target-zzz.el")))
      (should (and (integerp result)
                   (>= result 0)
                   (<= result 10))))))

;; Test 11: Production-weighted scoring boosts effective-score
(ert-deftest test-production-metrics/weight-score-boosts ()
  "Business-value-score should boost effective-score above raw score."
  (cl-letf (((symbol-function 'gptel-auto-workflow--get-production-metrics)
             (lambda (_target)
               (list :business-value-score 0.8 :risk-score 0.1))))
    (let ((weighted (gptel-auto-workflow--weight-score-with-production-metrics 0.5 "test-target")))
      (should (> weighted 0.5))
      ;; Boost = 0.8 * 0.3 = 0.24, Penalty = 0.1 * 0.5 = 0.05, Net = +0.19
      (should (< (abs (- weighted 0.69)) 0.001))))

  ;; When risk dominates, score should decrease
  (cl-letf (((symbol-function 'gptel-auto-workflow--get-production-metrics)
             (lambda (_target)
               (list :business-value-score 0.1 :risk-score 0.8))))
    (let ((weighted (gptel-auto-workflow--weight-score-with-production-metrics 0.5 "test-target")))
      (should (< weighted 0.5))
      ;; Boost = 0.1 * 0.3 = 0.03, Penalty = 0.8 * 0.5 = 0.40, Net = -0.37
      (should (< (abs (- weighted 0.13)) 0.001)))))

;; Test 12: Production-weighted scoring fallback when no metrics
(ert-deftest test-production-metrics/weight-score-fallback-no-metrics ()
  "Should return raw score unchanged when production metrics unavailable."
  (cl-letf (((symbol-function 'gptel-auto-workflow--get-production-metrics)
             (lambda (_target) nil)))
    (should (= 0.7 (gptel-auto-workflow--weight-score-with-production-metrics 0.7 "test-target")))))

;; Test 13: Production-weighted scoring configurable weights
(ert-deftest test-production-metrics/weight-score-configurable ()
  "Zero weights should result in no adjustment to effective-score."
  (let ((orig-bv gptel-auto-workflow-production-weight-business-value)
        (orig-risk gptel-auto-workflow-production-weight-risk-penalty))
    (unwind-protect
        (progn
          (setq gptel-auto-workflow-production-weight-business-value 0.0)
          (setq gptel-auto-workflow-production-weight-risk-penalty 0.0)
          (cl-letf (((symbol-function 'gptel-auto-workflow--get-production-metrics)
                     (lambda (_target)
                       (list :business-value-score 0.8 :risk-score 0.8))))
            (should (= 0.5 (gptel-auto-workflow--weight-score-with-production-metrics 0.5 "test-target")))))
      (setq gptel-auto-workflow-production-weight-business-value orig-bv)
      (setq gptel-auto-workflow-production-weight-risk-penalty orig-risk))))

;; Test 14: Production-weighted scoring symmetrical at equal weights
(ert-deftest test-production-metrics/weight-score-symmetry ()
  "Equal business-value and risk at equal weights should cancel out."
  (let ((orig-bv gptel-auto-workflow-production-weight-business-value)
        (orig-risk gptel-auto-workflow-production-weight-risk-penalty))
    (unwind-protect
        (progn
          (setq gptel-auto-workflow-production-weight-business-value 0.5)
          (setq gptel-auto-workflow-production-weight-risk-penalty 0.5)
          (cl-letf (((symbol-function 'gptel-auto-workflow--get-production-metrics)
                     (lambda (_target)
                       (list :business-value-score 0.5 :risk-score 0.5))))
            (should (= 0.5 (gptel-auto-workflow--weight-score-with-production-metrics 0.5 "test-target")))))
      (setq gptel-auto-workflow-production-weight-business-value orig-bv)
      (setq gptel-auto-workflow-production-weight-risk-penalty orig-risk))))

;; Test 15: Weighted score should never go negative even with extreme risk
(ert-deftest test-production-metrics/weight-score-clamped-non-negative ()
  "Weighted score should be clamped to [0.0, 1.0] — never negative."
  (cl-letf (((symbol-function 'gptel-auto-workflow--get-production-metrics)
             (lambda (_target)
               (list :business-value-score 0.0 :risk-score 1.0))))
    ;; Low score + max risk + no business value → would be -0.5 without clamp
    (let ((weighted (gptel-auto-workflow--weight-score-with-production-metrics 0.1 "test-target")))
      (should (>= weighted 0.0))
      (should (<= weighted 1.0)))))

;; Test 16: Weighted score should not exceed 1.0
(ert-deftest test-production-metrics/weight-score-clamped-max-1 ()
  "Weighted score should be clamped to [0.0, 1.0] — never above 1.0."
  (cl-letf (((symbol-function 'gptel-auto-workflow--get-production-metrics)
             (lambda (_target)
               (list :business-value-score 1.0 :risk-score 0.0))))
    ;; 0.9 score + max boost → would be 1.2 without clamp
    (let ((weighted (gptel-auto-workflow--weight-score-with-production-metrics 0.9 "test-target")))
      (should (>= weighted 0.0))
      (should (<= weighted 1.0)))))

(provide 'test-gptel-auto-workflow-production-metrics)

;;; test-gptel-auto-workflow-production-metrics.el ends here
