;;; test-gptel-skill-planning-v1.el --- Tests for GPTel Planning Skill v1.1 -*- lexical-binding: t -*-

;;; Commentary:

;; Tests for gptel-skill-planning-v1.el

;;; Code:

(require 'ert)
(require 'gptel-skill-planning-v1)

(ert-deftest test-gptel-skill-plan-nil-guard-nil ()
  "Test nil guard with nil input."
  (should-error (gptel-skill-plan-nil-guard nil)
                :type 'error))

(ert-deftest test-gptel-skill-plan-nil-guard-empty ()
  "Test nil guard with empty string."
  (should-error (gptel-skill-plan-nil-guard "")
                :type 'error))

(ert-deftest test-gptel-skill-plan-nil-guard-whitespace ()
  "Test nil guard with whitespace only."
  (should-error (gptel-skill-plan-nil-guard "   ")
                :type 'error))

(ert-deftest test-gptel-skill-plan-nil-guard-valid ()
  "Test nil guard with valid input."
  (should-not (gptel-skill-plan-nil-guard "Valid task description")))

(ert-deftest test-gptel-skill-plan-single-action-p ()
  "Test single action detection."
  (should (gptel-skill-plan-single-action-p "rename file.txt"))
  (should (gptel-skill-plan-single-action-p "move file to dir"))
  (should (gptel-skill-plan-single-action-p "delete temp files"))
  (should-not (gptel-skill-plan-single-action-p "refactor entire module")))

(ert-deftest test-gptel-skill-plan-no-dependencies-p ()
  "Test dependency detection."
  (should-not (gptel-skill-plan-no-dependencies-p "do this after that"))
  (should-not (gptel-skill-plan-no-dependencies-p "run before build"))
  (should (gptel-skill-plan-no-dependencies-p "simple task")))

(ert-deftest test-gptel-skill-plan-no-risk-p ()
  "Test risk detection."
  (should-not (gptel-skill-plan-no-risk-p "delete production database"))
  (should-not (gptel-skill-plan-no-risk-p "remove old files"))
  (should-not (gptel-skill-plan-no-risk-p "overwrite config"))
  (should (gptel-skill-plan-no-risk-p "read configuration")))

(ert-deftest test-gptel-skill-plan-should-skip-p ()
  "Test skip planning decision."
  ;; Single action tasks should skip
  (should (gptel-skill-plan-should-skip-p "rename file.txt"))
  ;; No dependencies should skip
  (should (gptel-skill-plan-should-skip-p "show current time")))

(ert-deftest test-gptel-skill-plan-3-strike-retry-strike1 ()
  "Test 3-strike retry on first failure."
  (let ((result (gptel-skill-plan-3-strike-retry 'test-action 1)))
    (should (equal (plist-get result :status) 'retry))
    (should (equal (plist-get result :strike) 1))))

(ert-deftest test-gptel-skill-plan-3-strike-retry-strike2 ()
  "Test 3-strike retry on second failure."
  (let ((result (gptel-skill-plan-3-strike-retry 'test-action 2)))
    (should (equal (plist-get result :status) 'retry-mutated))
    (should (equal (plist-get result :strike) 2))))

(ert-deftest test-gptel-skill-plan-3-strike-retry-strike3 ()
  "Test 3-strike retry on third failure."
  (let ((result (gptel-skill-plan-3-strike-retry 'test-action 3)))
    (should (equal (plist-get result :status) 'escalated))
    (should (equal (plist-get result :failures) 3))))

(ert-deftest test-gptel-skill-plan-detect-conflict ()
  "Test conflict detection (no conflicts case)."
  ;; This test verifies the function runs without error
  ;; Actual conflict detection requires multiple plan files
  (should-not (gptel-skill-plan-detect-conflict)))

(provide 'test-gptel-skill-planning-v1)

;;; test-gptel-skill-planning-v1.el ends here
