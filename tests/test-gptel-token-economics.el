;;; test-gptel-token-economics.el --- Tests for token economics tracking -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OV5 Project

;; Author: OV5 AI System
;; Keywords: tests, economics, tokens

;;; Commentary:

;; TDD tests for Phase 3: Token Economics
;; This module tracks ROI per token spent and optimizes budget allocation.

;;; Code:

(require 'ert)
(require 'gptel-token-economics)

;; Helper for floating point comparison with tolerance
(defun test-token-economics--approximately-equal (a b &optional tolerance)
  "Check if A and B are approximately equal within TOLERANCE.
Default tolerance is 0.0001."
  (let ((tol (or tolerance 0.0001)))
    (< (abs (- a b)) tol)))

;; Setup/teardown to reset state before each test
(defmacro test-token-economics--with-clean-state (&rest body)
  "Execute BODY with clean token economics state."
  `(let ((gptel-token-economics--records nil))
     ,@body))

;; ============================================================================
;; Task 3.1: Token Cost Tracking Tests
;; ============================================================================

(ert-deftest test-token-economics/calculate-token-cost ()
  "Should calculate cost from input and output tokens."
  (let ((pricing '(:input-price 0.00003 :output-price 0.00006)))
    ;; 1000 input tokens + 500 output tokens
    (should (test-token-economics--approximately-equal
             0.06
             (gptel-token-economics--calculate-cost 1000 500 pricing)))
    ;; 2000 input tokens + 1000 output tokens
    (should (test-token-economics--approximately-equal
             0.12
             (gptel-token-economics--calculate-cost 2000 1000 pricing)))))

(ert-deftest test-token-economics/track-experiment-tokens ()
  "Should track tokens spent on an experiment."
  (test-token-economics--with-clean-state
   (let ((experiment '(:id "exp-001"
                       :target "lisp/foo.el"
                       :category :programming
                       :input-tokens 1500
                       :output-tokens 800
                       :decision "kept")))
     (should (gptel-token-economics--track-experiment experiment))
     ;; Should record the experiment
     (let ((records (gptel-token-economics--get-records)))
       (should (= 1 (length records)))
       (should (equal "exp-001" (plist-get (car records) :id)))))))

(ert-deftest test-token-economics/track-multiple-experiments ()
  "Should track multiple experiments across different categories."
  (test-token-economics--with-clean-state
   (let ((experiments '((:id "exp-001" :category :programming :input-tokens 1000 :output-tokens 500 :decision "kept")
                        (:id "exp-002" :category :research :input-tokens 2000 :output-tokens 1000 :decision "discarded")
                        (:id "exp-003" :category :programming :input-tokens 1500 :output-tokens 800 :decision "kept"))))
     (dolist (exp experiments)
       (gptel-token-economics--track-experiment exp))
     (let ((records (gptel-token-economics--get-records)))
       (should (= 3 (length records)))))))

;; ============================================================================
;; Task 3.2: ROI Calculation Tests
;; ============================================================================

(ert-deftest test-token-economics/calculate-roi-for-experiment ()
  "Should calculate ROI as value gained divided by cost."
  (let ((experiment '(:id "exp-001"
                      :input-tokens 1000
                      :output-tokens 500
                      :score-before 0.40
                      :score-after 0.65
                      :decision "kept")))
    ;; Cost = (1000 * 0.00003) + (500 * 0.00006) = 0.06
    ;; Value = score improvement = 0.25
    ;; ROI = 0.25 / 0.06 = 4.17
    (let ((roi (gptel-token-economics--calculate-roi experiment)))
      (should (> roi 4.0))
      (should (< roi 5.0)))))

(ert-deftest test-token-economics/roi-zero-for-discarded ()
  "Should return zero ROI for discarded experiments."
  (let ((experiment '(:id "exp-001"
                      :input-tokens 1000
                      :output-tokens 500
                      :score-before 0.40
                      :score-after 0.35
                      :decision "discarded")))
    (should (= 0.0 (gptel-token-economics--calculate-roi experiment)))))

(ert-deftest test-token-economics/calculate-category-roi ()
  "Should calculate average ROI for a category."
  (let ((experiments '((:id "exp-001" :category :programming :input-tokens 1000 :output-tokens 500
                            :score-before 0.40 :score-after 0.65 :decision "kept")
                       (:id "exp-002" :category :programming :input-tokens 1500 :output-tokens 800
                            :score-before 0.50 :score-after 0.70 :decision "kept")
                       (:id "exp-003" :category :research :input-tokens 2000 :output-tokens 1000
                            :score-before 0.60 :score-after 0.55 :decision "discarded"))))
    (dolist (exp experiments)
      (gptel-token-economics--track-experiment exp))
    ;; Programming category should have positive ROI
    (let ((prog-roi (gptel-token-economics--category-roi :programming)))
      (should (> prog-roi 0.0)))
    ;; Research category should have zero ROI (discarded)
    (let ((research-roi (gptel-token-economics--category-roi :research)))
      (should (= 0.0 research-roi)))))

(ert-deftest test-token-economics/rank-categories-by-roi ()
  "Should rank categories by ROI (highest first)."
  (let ((experiments '((:id "exp-001" :category :programming :input-tokens 1000 :output-tokens 500
                            :score-before 0.40 :score-after 0.65 :decision "kept")
                       (:id "exp-002" :category :documentation :input-tokens 800 :output-tokens 400
                            :score-before 0.50 :score-after 0.80 :decision "kept")
                       (:id "exp-003" :category :research :input-tokens 2000 :output-tokens 1000
                            :score-before 0.60 :score-after 0.55 :decision "discarded"))))
    (dolist (exp experiments)
      (gptel-token-economics--track-experiment exp))
    (let ((ranking (gptel-token-economics--rank-categories-by-roi)))
      ;; Documentation should be first (highest ROI)
      (should (equal :documentation (car (car ranking))))
      ;; Research should be last (zero ROI)
      (should (equal :research (car (car (last ranking))))))))

;; ============================================================================
;; Task 3.3: Budget Allocation Tests
;; ============================================================================

(ert-deftest test-token-economics/calculate-budget-allocation ()
  "Should allocate budget proportionally to ROI."
  (let ((category-rois '((:documentation . 5.0)
                         (:programming . 3.0)
                         (:research . 0.0)))
        (total-budget 100.0))
    (let ((allocation (gptel-token-economics--allocate-budget category-rois total-budget)))
      ;; Documentation should get most budget (5/8 of total)
      (should (> (plist-get allocation :documentation) 60.0))
      ;; Programming should get some budget (3/8 of total)
      (should (> (plist-get allocation :programming) 35.0))
      (should (< (plist-get allocation :programming) 40.0))
      ;; Research should get zero budget (zero ROI)
      (should (= 0.0 (plist-get allocation :research))))))

(ert-deftest test-token-economics/minimum-budget-guarantee ()
  "Should guarantee minimum budget for all categories."
  (let ((category-rois '((:documentation . 5.0)
                         (:programming . 3.0)
                         (:research . 0.0)))
        (total-budget 100.0)
        (min-budget 5.0))
    (let ((allocation (gptel-token-economics--allocate-budget category-rois total-budget min-budget)))
      ;; Even research should get minimum budget
      (should (>= (plist-get allocation :research) min-budget)))))

(ert-deftest test-token-economics/optimize-token-allocation ()
  "Should optimize allocation based on historical ROI."
  (let ((experiments '((:id "exp-001" :category :programming :input-tokens 1000 :output-tokens 500
                            :score-before 0.40 :score-after 0.65 :decision "kept")
                       (:id "exp-002" :category :documentation :input-tokens 800 :output-tokens 400
                            :score-before 0.50 :score-after 0.80 :decision "kept")
                       (:id "exp-003" :category :research :input-tokens 2000 :output-tokens 1000
                            :score-before 0.60 :score-after 0.55 :decision "discarded")
                       (:id "exp-004" :category :programming :input-tokens 1200 :output-tokens 600
                            :score-before 0.45 :score-after 0.70 :decision "kept"))))
    (dolist (exp experiments)
      (gptel-token-economics--track-experiment exp))
    (let* ((allocation (gptel-token-economics--optimize-allocation 100.0))
           (doc-budget (plist-get allocation :documentation))
           (prog-budget (plist-get allocation :programming))
           (research-budget (plist-get allocation :research)))
      ;; Documentation should get more budget than programming (higher ROI)
      (should (> doc-budget prog-budget))
      ;; Programming should get more than research
      (should (> prog-budget research-budget)))))

;; ============================================================================
;; Integration Tests
;; ============================================================================

(ert-deftest test-token-economics/track-cost-per-kept-experiment ()
  "Should track cost per kept experiment."
  (let ((experiments '((:id "exp-001" :category :programming :input-tokens 1000 :output-tokens 500
                            :score-before 0.40 :score-after 0.65 :decision "kept")
                       (:id "exp-002" :category :programming :input-tokens 1500 :output-tokens 800
                            :score-before 0.50 :score-after 0.45 :decision "discarded")
                       (:id "exp-003" :category :programming :input-tokens 1200 :output-tokens 600
                            :score-before 0.55 :score-after 0.75 :decision "kept"))))
    (dolist (exp experiments)
      (gptel-token-economics--track-experiment exp))
    (let ((cost-per-kept (gptel-token-economics--cost-per-kept-experiment :programming)))
      ;; Should average cost of 2 kept experiments
      (should (> cost-per-kept 0.0))
      (should (< cost-per-kept 0.20)))))

(ert-deftest test-token-economics/generate-economics-report ()
  "Should generate comprehensive economics report."
  (let ((experiments '((:id "exp-001" :category :programming :input-tokens 1000 :output-tokens 500
                            :score-before 0.40 :score-after 0.65 :decision "kept")
                       (:id "exp-002" :category :documentation :input-tokens 800 :output-tokens 400
                            :score-before 0.50 :score-after 0.80 :decision "kept")
                       (:id "exp-003" :category :research :input-tokens 2000 :output-tokens 1000
                            :score-before 0.60 :score-after 0.55 :decision "discarded"))))
    (dolist (exp experiments)
      (gptel-token-economics--track-experiment exp))
    (let ((report (gptel-token-economics--generate-report)))
      (should (plist-get report :total-cost))
      (should (plist-get report :total-roi))
      (should (plist-get report :category-breakdown))
      (should (plist-get report :optimization-recommendations)))))

(ert-deftest test-token-economics/persist-economics-data ()
  "Should persist economics data to file."
  (let ((experiments '((:id "exp-001" :category :programming :input-tokens 1000 :output-tokens 500
                             :score-before 0.40 :score-after 0.65 :decision "kept")))
        (temp-file (make-temp-file "token-economics-")))
    (unwind-protect
        (progn
          (dolist (exp experiments)
            (gptel-token-economics--track-experiment exp))
          (gptel-token-economics--persist-data temp-file)
          (should (file-exists-p temp-file))
          (should (> (file-attribute-size (file-attributes temp-file)) 0)))
      (delete-file temp-file))))

(ert-deftest test-token-economics/persist-and-load-round-trip ()
  "Should round-trip data through persist + load without data loss."
  (let ((experiments '((:id "exp-001" :category :programming :input-tokens 1000 :output-tokens 500
                             :score-before 0.40 :score-after 0.65 :decision "kept")
                       (:id "exp-002" :category :research :input-tokens 2000 :output-tokens 1000
                             :score-before 0.60 :score-after 0.55 :decision "discarded")))
        (temp-file (make-temp-file "token-economics-roundtrip-")))
    (unwind-protect
        (progn
          ;; Reset global state
          (setq gptel-token-economics--records nil)
          (dolist (exp experiments)
            (gptel-token-economics--track-experiment exp))
          (gptel-token-economics--persist-data temp-file)
          ;; Clear and reload
          (setq gptel-token-economics--records nil)
          (should (= 0 (length (gptel-token-economics--get-records))))
          (gptel-token-economics--load-data temp-file)
          ;; Verify data survived round-trip
          (let ((records (gptel-token-economics--get-records)))
            (should (= 2 (length records)))
            ;; First record should have correct fields
            (let ((exp1 (cl-find-if (lambda (r) (equal "exp-001" (plist-get r :id))) records)))
              (should exp1)
              (should (equal :programming (plist-get exp1 :category)))
              (should (equal "kept" (plist-get exp1 :decision)))
              (should (= 1000 (plist-get exp1 :input-tokens)))
              (should (= 0.65 (plist-get exp1 :score-after))))
            ;; Second record
            (let ((exp2 (cl-find-if (lambda (r) (equal "exp-002" (plist-get r :id))) records)))
              (should exp2)
              (should (equal :research (plist-get exp2 :category)))
              (should (equal "discarded" (plist-get exp2 :decision))))))
      (delete-file temp-file))))

;; ============================================================================
;; Edge Cases
;; ============================================================================

(ert-deftest test-token-economics/handle-zero-tokens ()
  "Should handle experiments with zero tokens gracefully."
  (let ((experiment '(:id "exp-001"
                      :input-tokens 0
                      :output-tokens 0
                      :score-before 0.40
                      :score-after 0.65
                      :decision "kept")))
    ;; Should not cause division by zero
    (should (= 0.0 (gptel-token-economics--calculate-roi experiment)))))

(ert-deftest test-token-economics/handle-missing-category ()
  "Should handle experiments without category."
  (let ((experiment '(:id "exp-001"
                      :input-tokens 1000
                      :output-tokens 500
                      :score-before 0.40
                      :score-after 0.65
                      :decision "kept")))
    ;; Should assign to :unknown category
    (gptel-token-economics--track-experiment experiment)
    (let ((records (gptel-token-economics--get-records)))
      (should (equal :unknown (plist-get (car records) :category))))))

(ert-deftest test-token-economics/handle-negative-score-improvement ()
  "Should handle experiments where score decreased."
  (let ((experiment '(:id "exp-001"
                      :input-tokens 1000
                      :output-tokens 500
                      :score-before 0.65
                      :score-after 0.40
                      :decision "discarded")))
    ;; ROI should be negative or zero
    (let ((roi (gptel-token-economics--calculate-roi experiment)))
      (should (<= roi 0.0)))))

;; ============================================================================
;; ROI Pre-Flight Prediction Tests
;; ============================================================================

(ert-deftest test-token-economics/predict-roi-from-category-history ()
  "Should predict ROI from historical category-roi."
  (test-token-economics--with-clean-state
   (let ((experiments '((:id "exp-001" :category :programming :input-tokens 1000 :output-tokens 500
                         :score-before 0.40 :score-after 0.65 :decision "kept")
                        (:id "exp-002" :category :programming :input-tokens 1500 :output-tokens 800
                         :score-before 0.50 :score-after 0.70 :decision "kept"))))
     (dolist (exp experiments)
       (gptel-token-economics--track-experiment exp))
     (let ((predicted (gptel-token-economics--predict-roi :programming))
           (historical (gptel-token-economics--category-roi :programming)))
       ;; Predicted ROI should equal historical category-roi
       (should (test-token-economics--approximately-equal predicted historical))))))

(ert-deftest test-token-economics/predict-roi-unknown-category ()
  "Should return 1.0 (break-even) for unknown or nil categories.
This allows experiments to run and collect data for future predictions."
  (test-token-economics--with-clean-state
   ;; No history for :unknown category → 1.0 (break-even default)
   (should (= 1.0 (gptel-token-economics--predict-roi :unknown)))
   (should (= 1.0 (gptel-token-economics--predict-roi nil)))))

(ert-deftest test-token-economics/pre-flight-rejects-below-threshold ()
  "Pre-flight should reject when predicted ROI is below threshold.
With Pi5's cold-start fix, zero-ROI categories return 1.0 (break-even),
so they pass the default threshold of 1.0.  Only high thresholds reject."
  (test-token-economics--with-clean-state
   (let ((experiments '((:id "exp-001" :category :research :input-tokens 2000 :output-tokens 1000
                         :score-before 0.60 :score-after 0.55 :decision "discarded"))))
     (dolist (exp experiments)
       (gptel-token-economics--track-experiment exp))
     ;; :research has 0.0 ROI (all discarded) → cold-start returns 1.0
     (let ((predicted (gptel-token-economics--predict-roi :research)))
       (should (= 1.0 predicted))
       ;; With threshold 5.0, should be rejected (1.0 < 5.0)
       (let ((gptel-token-economics-roi-threshold 5.0))
         (should (< predicted gptel-token-economics-roi-threshold)))
       ;; With default threshold 1.0, passes (1.0 is NOT < 1.0)
       (should (not (< predicted gptel-token-economics-roi-threshold)))))))

(ert-deftest test-token-economics/predict-roi-new-category-allows-through ()
  "Pre-flight should allow new categories with no historical data.
Pi5's cold-start fix returns 1.0 (break-even) for unknown categories,
which passes the default threshold of 1.0 (1.0 is NOT < 1.0)."
  (test-token-economics--with-clean-state
   ;; No experiments tracked → cold-start returns 1.0
   (should (= 1.0 (gptel-token-economics--predict-roi :brand-new-category)))
   ;; 1.0 passes default threshold 1.0 (not less than)
   (let ((gptel-token-economics-roi-threshold 1.0))
     (should (not (< (gptel-token-economics--predict-roi :brand-new-category)
                     gptel-token-economics-roi-threshold))))))

(ert-deftest test-token-economics/pre-flight-passes-above-threshold ()
  "Pre-flight should pass when predicted ROI exceeds threshold."
  (test-token-economics--with-clean-state
   (let ((experiments '((:id "exp-001" :category :programming :input-tokens 1000 :output-tokens 500
                         :score-before 0.40 :score-after 0.65 :decision "kept")
                        (:id "exp-002" :category :programming :input-tokens 800 :output-tokens 400
                         :score-before 0.50 :score-after 0.80 :decision "kept"))))
     (dolist (exp experiments)
       (gptel-token-economics--track-experiment exp))
     (let ((predicted (gptel-token-economics--predict-roi :programming)))
       ;; With default threshold 1.0, programming ROI > 1.0
       (should (> predicted 1.0))
       (should (>= predicted gptel-token-economics-roi-threshold))))))

(provide 'test-gptel-token-economics)

;;; test-gptel-token-economics.el ends here
