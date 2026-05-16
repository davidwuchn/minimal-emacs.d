;;; test-gptel-tools-agent-base.el --- Tests for base agent utilities -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-tools-agent-base.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-tools-agent-base.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-tools-agent-base)

;;; Validation tests

(ert-deftest test-base/validate-string-accepts-valid ()
  "Validation should accept non-empty strings."
  (should (gptel-auto-workflow--validate-non-empty-string "valid" "test")))

(ert-deftest test-base/validate-string-rejects-nil ()
  "Validation should reject nil."
  (should-error (gptel-auto-workflow--validate-non-empty-string nil "test")
                :type 'error))

(ert-deftest test-base/validate-string-rejects-empty ()
  "Validation should reject empty strings."
  (should-error (gptel-auto-workflow--validate-non-empty-string "" "test")
                :type 'error))

(ert-deftest test-base/validate-string-rejects-whitespace ()
  "Validation should reject whitespace-only strings."
  (should-error (gptel-auto-workflow--validate-non-empty-string "   " "test")
                :type 'error))

(ert-deftest test-base/validate-string-rejects-non-string ()
  "Validation should reject non-string values."
  (should-error (gptel-auto-workflow--validate-non-empty-string 123 "test")
                :type 'error))

;;; Shell timeout tests

(ert-deftest test-base/shell-timeout-default ()
  "Default shell timeout should be 30 seconds."
  (should (= gptel-auto-workflow-shell-timeout 30)))

(provide 'test-gptel-tools-agent-base)
;;; test-gptel-tools-agent-base.el ends here