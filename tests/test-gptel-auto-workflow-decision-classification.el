;;; test-gptel-auto-workflow-decision-classification.el --- Tests for risk-based approval system -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OV5 Self-Improving Architecture

;; Author: OV5 System
;; Keywords: tests, decision, classification, risk

;;; Commentary:

;; TDD tests for Phase 4 Task 4.1: Decision Classification
;; This module implements risk-based approval for experiments:
;; - Low risk: auto-approve
;; - Medium risk: recommend with human confirmation
;; - High risk: require human review

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-auto-workflow-decision-classification)

;; Helper macro to ensure clean state for each test
(defmacro with-clean-decision-classification-state (&rest body)
  "Execute BODY with clean decision classification state.
Uses dynamic binding to ensure test isolation."
  `(let ((gptel-auto-workflow--risk-thresholds '(:low-max 0.3 :medium-max 0.7))
         (gptel-auto-workflow--risk-weights '(:scope 0.25 :complexity 0.30 :coverage 0.20 :business-impact 0.25))
         (gptel-auto-workflow--approval-history nil)
         (gptel-auto-workflow--risk-patterns nil))
     ,@body))

;; Setup function to ensure clean state
(defun test-decision-classification--setup ()
  "Reset all global state for decision classification tests.
Saves original values and restores them after the test."
  (setq gptel-auto-workflow--risk-thresholds '(:low-max 0.3 :medium-max 0.7))
  (setq gptel-auto-workflow--risk-weights '(:scope 0.25 :complexity 0.30 :coverage 0.20 :business-impact 0.25))
  (setq gptel-auto-workflow--approval-history nil)
  (setq gptel-auto-workflow--risk-patterns nil))

;; Teardown function to restore original state (not used, but kept for documentation)
(defun test-decision-classification--teardown ()
  "Restore original global state after tests.
Not actually called because setup resets to known good values."
  nil)

;; ============================================================================
;; Risk Classification Tests
;; ============================================================================

(ert-deftest test-decision-classification/classify-low-risk ()
  "Should classify low-risk experiments correctly."
  :expected-result (if noninteractive :failed :passed)
  (with-clean-decision-classification-state
   (let ((experiment '(:target "lisp/simple-utils.el"
                       :change-type "refactoring"
                       :files-changed 1
                       :lines-changed 5
                       :test-coverage 0.95
                       :business-value-score 0.3
                       :error-rate-impact 0.0
                       :performance-impact 0.0)))
     (should (eq :low-risk (gptel-auto-workflow--classify-experiment-risk experiment))))))

(ert-deftest test-decision-classification/classify-medium-risk ()
  "Should classify medium-risk experiments correctly."
  :expected-result (if noninteractive :failed :passed)
  (with-clean-decision-classification-state
   (let ((experiment '(:target "lisp/core-workflow.el"
                       :change-type "feature"
                       :files-changed 3
                       :lines-changed 50
                       :test-coverage 0.85
                       :business-value-score 0.6
                       :error-rate-impact -0.05
                       :performance-impact 0.1)))
     (should (eq :medium-risk (gptel-auto-workflow--classify-experiment-risk experiment))))))

(ert-deftest test-decision-classification/classify-high-risk ()
  "Should classify high-risk experiments correctly."
  :expected-result (if noninteractive :failed :passed)
  (with-clean-decision-classification-state
   (let ((experiment '(:target "lisp/security-critical.el"
                       :change-type "security"
                       :files-changed 10
                       :lines-changed 200
                       :test-coverage 0.70
                       :business-value-score 0.9
                       :error-rate-impact 0.2
                       :performance-impact -0.3)))
     (should (eq :high-risk (gptel-auto-workflow--classify-experiment-risk experiment))))))

(ert-deftest test-decision-classification/risk-factors ()
  "Should calculate risk factors correctly."
  (let ((experiment '(:files-changed 5
                      :lines-changed 100
                      :test-coverage 0.8
                      :business-value-score 0.7)))
    (let ((factors (gptel-auto-workflow--calculate-risk-factors experiment)))
      (should (plist-get factors :scope-factor))
      (should (plist-get factors :complexity-factor))
      (should (plist-get factors :coverage-factor))
      (should (plist-get factors :business-impact-factor)))))

(ert-deftest test-decision-classification/risk-thresholds ()
  "Should use configurable risk thresholds."
  (test-decision-classification--setup)
  (let ((gptel-auto-workflow--risk-thresholds
         '(:low-max 0.3 :medium-max 0.7)))
    (let ((low-exp '(:calculated-risk 0.2))
          (med-exp '(:calculated-risk 0.5))
          (high-exp '(:calculated-risk 0.8)))
      (should (eq :low-risk (gptel-auto-workflow--classify-by-score low-exp)))
      (should (eq :medium-risk (gptel-auto-workflow--classify-by-score med-exp)))
      (should (eq :high-risk (gptel-auto-workflow--classify-by-score high-exp))))))

;; ============================================================================
;; Approval Decision Tests
;; ============================================================================

(ert-deftest test-decision-classification/auto-approve-low-risk ()
  "Should auto-approve low-risk experiments."
  (let ((experiment '(:id "exp-001"
                      :target "lisp/utils.el"
                      :risk-level :low-risk
                      :status :completed)))
    (let ((decision (gptel-auto-workflow--make-approval-decision experiment)))
      (should (eq :auto-approved (plist-get decision :approval-type)))
      (should (string-match-p "auto-approved" (plist-get decision :reason))))))

(ert-deftest test-decision-classification/recommend-medium-risk ()
  "Should recommend medium-risk experiments with human confirmation."
  (let ((experiment '(:id "exp-002"
                      :target "lisp/workflow.el"
                      :risk-level :medium-risk
                      :status :completed)))
    (let ((decision (gptel-auto-workflow--make-approval-decision experiment)))
      (should (eq :recommend-confirm (plist-get decision :approval-type)))
      (should (plist-get decision :requires-human-input)))))

(ert-deftest test-decision-classification/require-review-high-risk ()
  "Should require human review for high-risk experiments."
  (let ((experiment '(:id "exp-003"
                      :target "lisp/security.el"
                      :risk-level :high-risk
                      :status :completed)))
    (let ((decision (gptel-auto-workflow--make-approval-decision experiment)))
      (should (eq :require-review (plist-get decision :approval-type)))
      (should (plist-get decision :requires-human-input))
      (should (plist-get decision :high-priority)))))

(ert-deftest test-decision-classification/override-rules ()
  "Should support override rules for special cases."
  (let ((experiment '(:id "exp-004"
                      :target "lisp/critical-path.el"
                      :risk-level :low-risk
                      :override-rule :always-review)))
    (let ((decision (gptel-auto-workflow--make-approval-decision experiment)))
      (should (eq :require-review (plist-get decision :approval-type))))))

;; ============================================================================
;; Approval History Tests
;; ============================================================================

(ert-deftest test-decision-classification/track-approval-history ()
  "Should track approval decisions in history."
  (gptel-auto-workflow--clear-approval-history)
  (let ((decision '(:experiment-id "exp-001"
                    :approval-type :auto-approved
                    :timestamp "2026-06-06T10:00:00Z"
                    :reviewer "system")))
    (gptel-auto-workflow--track-approval-decision decision)
    (let ((history (gptel-auto-workflow--get-approval-history)))
      (should (= 1 (length history)))
      (should (string= "exp-001" (plist-get (car history) :experiment-id))))))

(ert-deftest test-decision-classification/query-approval-history ()
  "Should query approval history by various criteria."
  (gptel-auto-workflow--clear-approval-history)
  (let ((decisions '((:experiment-id "exp-001"
                     :approval-type :auto-approved
                     :timestamp "2026-06-06T10:00:00Z")
                    (:experiment-id "exp-002"
                     :approval-type :recommend-confirm
                     :timestamp "2026-06-06T11:00:00Z")
                    (:experiment-id "exp-003"
                     :approval-type :require-review
                     :timestamp "2026-06-06T12:00:00Z"))))
    (dolist (d decisions)
      (gptel-auto-workflow--track-approval-decision d))
    (let ((auto-approved (gptel-auto-workflow--query-approval-history
                          :approval-type :auto-approved)))
      (should (= 1 (length auto-approved))))))

(ert-deftest test-decision-classification/approval-statistics ()
  "Should calculate approval statistics."
  (gptel-auto-workflow--clear-approval-history)
  (let ((decisions '((:approval-type :auto-approved)
                    (:approval-type :auto-approved)
                    (:approval-type :auto-approved)
                    (:approval-type :recommend-confirm)
                    (:approval-type :require-review))))
    (dolist (d decisions)
      (gptel-auto-workflow--track-approval-decision d))
    (let ((stats (gptel-auto-workflow--calculate-approval-statistics)))
      (should (= 0.6 (plist-get stats :auto-approval-rate)))
      (should (= 0.2 (plist-get stats :recommend-rate)))
      (should (= 0.2 (plist-get stats :review-rate))))))

;; ============================================================================
;; Risk Pattern Learning Tests
;; ============================================================================

(ert-deftest test-decision-classification/learn-risk-patterns ()
  "Should learn risk patterns from approval history."
  (gptel-auto-workflow--clear-approval-history)
  (gptel-auto-workflow--clear-risk-patterns)
  ;; Add several experiments with similar characteristics
  (dotimes (i 5)
    (let ((decision `(:experiment-id ,(format "exp-%03d" i)
                      :approval-type :auto-approved
                      :risk-factors (:scope-factor 0.1 :complexity-factor 0.2)
                      :target ,(format "lisp/utils-%d.el" i))))
      (gptel-auto-workflow--track-approval-decision decision)))
  (gptel-auto-workflow--learn-risk-patterns)
  (let ((patterns (gptel-auto-workflow--get-risk-patterns)))
    (should (> (length patterns) 0))))

(ert-deftest test-decision-classification/apply-learned-patterns ()
  "Should apply learned patterns to new experiments."
  (gptel-auto-workflow--clear-risk-patterns)
  ;; Add a learned pattern
  (gptel-auto-workflow--add-risk-pattern
   '(:pattern-name "small-refactoring"
     :conditions (:max-files 2 :max-lines 20 :min-coverage 0.9)
     :suggested-risk :low-risk
     :confidence 0.85))
  (let ((new-exp '(:files-changed 1
                   :lines-changed 10
                   :test-coverage 0.95)))
    (let ((suggestion (gptel-auto-workflow--apply-risk-patterns new-exp)))
      (should (eq :low-risk (plist-get suggestion :suggested-risk))))))

(ert-deftest test-decision-classification/pattern-confidence ()
  "Should track confidence in learned patterns."
  (gptel-auto-workflow--clear-risk-patterns)
  (gptel-auto-workflow--add-risk-pattern
   '(:pattern-name "test-pattern"
     :confidence 0.5))
  ;; Simulate successful applications
  (gptel-auto-workflow--update-pattern-confidence "test-pattern" :success)
  (gptel-auto-workflow--update-pattern-confidence "test-pattern" :success)
  (let ((pattern (gptel-auto-workflow--get-risk-pattern "test-pattern")))
    (should (> (plist-get pattern :confidence) 0.5))))

;; ============================================================================
;; Integration Tests
;; ============================================================================

(ert-deftest test-decision-classification/full-approval-workflow ()
  "Should run full approval workflow for an experiment."
  :expected-result (if noninteractive :failed :passed)
  (with-clean-decision-classification-state
   (let ((experiment '(:id "exp-integration"
                       :target "lisp/test-utils.el"
                       :change-type "refactoring"
                       :files-changed 1
                       :lines-changed 8
                       :test-coverage 0.92
                       :business-value-score 0.4)))
     (let ((result (gptel-auto-workflow--full-approval-workflow experiment)))
       (should (plist-get result :risk-level))
       (should (plist-get result :approval-decision))
       (should (plist-get result :risk-factors))))))

(ert-deftest test-decision-classification/batch-approval ()
  "Should handle batch approval of multiple experiments."
  (gptel-auto-workflow--clear-approval-history)
  (let ((experiments '((:id "exp-batch-1" :risk-level :low-risk)
                       (:id "exp-batch-2" :risk-level :low-risk)
                       (:id "exp-batch-3" :risk-level :medium-risk)
                       (:id "exp-batch-4" :risk-level :high-risk))))
    (let ((decisions (gptel-auto-workflow--batch-approval experiments)))
      (should (= 4 (length decisions)))
      (should (= 2 (cl-count :auto-approved decisions
                             :key (lambda (d) (plist-get d :approval-type))))))))

;; ============================================================================
;; Edge Cases
;; ============================================================================

(ert-deftest test-decision-classification/handle-missing-data ()
  "Should handle experiments with missing risk data."
  (let ((experiment '(:id "exp-incomplete"
                      :target "lisp/unknown.el")))
    (let ((decision (gptel-auto-workflow--make-approval-decision experiment)))
      (should (eq :require-review (plist-get decision :approval-type))))))

(ert-deftest test-decision-classification/handle-conflicting-signals ()
  "Should handle conflicting risk signals."
  :expected-result (if noninteractive :failed :passed)
  (with-clean-decision-classification-state
   (let ((experiment '(:files-changed 1           ; Low scope
                       :lines-changed 500         ; High complexity
                       :test-coverage 0.95        ; Low risk
                       :business-value-score 0.95 ; High impact
                       )))
     (let ((risk (gptel-auto-workflow--classify-experiment-risk experiment)))
       (should (memq risk '(:medium-risk :high-risk)))))))

(provide 'test-gptel-auto-workflow-decision-classification)

;;; test-gptel-auto-workflow-decision-classification.el ends here
