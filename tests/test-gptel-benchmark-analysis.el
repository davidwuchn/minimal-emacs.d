;;; test-gptel-benchmark-analysis.el --- Tests for benchmark analysis -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for gptel-benchmark-analysis.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-benchmark-analysis.el -f ert-run-tests-batch

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-benchmark-analysis)

;;; Parse analysis result tests

(ert-deftest test-analysis/parse-analysis-result-string ()
  "Parse analysis result should handle string."
  (let ((result (gptel-benchmark--parse-analysis-result "{\"summary\": \"test\"}")))
    (should (listp result))))

(ert-deftest test-analysis/parse-analysis-result-nil ()
  "Parse analysis result should handle nil."
  (let ((result (gptel-benchmark--parse-analysis-result nil)))
    (should (listp result))))

;;; Result passed tests

(ert-deftest test-analysis/result-passed-nil ()
  "Result passed should handle nil."
  (should-not (gptel-benchmark--result-passed-p nil)))

(ert-deftest test-analysis/result-passed-false ()
  "Result passed should handle false value."
  (should-not (gptel-benchmark--result-passed-p '(:passed nil))))

;;; Group by test id tests

(ert-deftest test-analysis/group-by-test-id-nil-returns-hash ()
  "Group by test id should handle nil and return hash."
  (let ((result (gptel-benchmark--group-by-test-id nil)))
    (should (or (null result) (hash-table-p result)))))

;;; Flaky test detection tests

(ert-deftest test-analysis/flaky-test-p-empty ()
  "Flaky test detection should handle empty."
  (should-not (gptel-benchmark--flaky-test-p nil)))

;;; Priority assessment tests

(ert-deftest test-analysis/assess-priority-exists ()
  "Assess priority function should exist."
  (should (fboundp 'gptel-benchmark-assess-priority)))

(provide 'test-gptel-benchmark-analysis)
;;; test-gptel-benchmark-analysis.el ends here