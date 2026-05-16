;;; test-gptel-benchmark-subagent.el --- Tests for subagent dispatch -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-benchmark-subagent.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-benchmark-subagent.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-benchmark-subagent)

;;; Customization tests

(ert-deftest test-subagent/timeout-default ()
  "Subagent timeout should default to 120 seconds."
  (should (= gptel-benchmark-subagent-timeout 120)))

(ert-deftest test-subagent/slow-fallback-timeout-default ()
  "Slow fallback timeout should default to 360 seconds."
  (should (= gptel-benchmark-subagent-slow-fallback-timeout 360)))

(ert-deftest test-subagent/use-subagents-default ()
  "Use subagents should default to t."
  (should gptel-benchmark-use-subagents))

;;; Slow fallback tests

(ert-deftest test-subagent/slow-fallback-preset-p-returns-bool ()
  "Slow fallback preset check should return boolean."
  (should (or (null (gptel-benchmark--slow-fallback-preset-p nil))
              (eq (gptel-benchmark--slow-fallback-preset-p nil) t))))

;;; Subagent timeout tests

(ert-deftest test-subagent/subagent-timeout-returns-number ()
  "Subagent timeout should return a number."
  (should (numberp (gptel-benchmark--subagent-timeout 60 nil))))

;;; Code quality tests

(ert-deftest test-subagent/code-quality-score-empty ()
  "Code quality score for empty code should be reasonable."
  (let ((score (gptel-benchmark--code-quality-score "")))
    (should (>= score 0))))

;;; Function length tests

(ert-deftest test-subagent/function-length-score-nil ()
  "Function length score for nil should handle gracefully."
  (let ((score (gptel-benchmark--function-length-score nil)))
    (should (>= score 0))))

(provide 'test-gptel-benchmark-subagent)
;;; test-gptel-benchmark-subagent.el ends here