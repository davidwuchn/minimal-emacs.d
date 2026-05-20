;;; test-gptel-benchmark-comparator.el --- Tests for benchmark comparator -*- lexical-binding: t; -*-

;; Tests for gptel-benchmark-comparator.el functions.
;; Run with:
;;   emacs --batch -L tests -l test-gptel-benchmark-comparator.el -f ert-run-tests-batch

(require 'ert)
(require 'cl-lib)
(require 'gptel-benchmark-comparator)

(ert-deftest test-comparator/get-trend-summary-nil-data ()
  "Should return nil when benchmark data is nil."
  (let ((result (gptel-benchmark--get-trend-summary "nonexistent" "1.0")))
    (should (null result))))

(ert-deftest test-comparator/get-trend-summary-non-list-data ()
  "Should return nil when benchmark data is not a proper list."
  (let ((result (gptel-benchmark--get-trend-summary "some-file" "1.0")))
    (should (null result))))

(ert-deftest test-comparator/version-trend-valid-name ()
  "Should return list for valid name."
  (let ((result (gptel-benchmark-version-trend "nonexistent-module")))
    (should (listp result))))

(ert-deftest test-comparator/version-trend-empty-name ()
  "Should signal error on empty string."
  (should-error (gptel-benchmark-version-trend "") :type 'wrong-type-argument))

(ert-deftest test-comparator/version-trend-nil-name ()
  "Should signal error on nil name."
  (should-error (gptel-benchmark-version-trend nil) :type 'wrong-type-argument))

(ert-deftest test-comparator/version-trend-non-list-versions ()
  "Should handle non-list versions gracefully."
  (let ((result (gptel-benchmark-version-trend "nonexistent-module" "not-a-list")))
    (should (listp result))))

(ert-deftest test-comparator/compare-summaries-both-nil ()
  "Should signal error when both summaries are nil."
  (should-error (gptel-benchmark-compare-summaries nil nil)
                :type 'wrong-type-argument))

(ert-deftest test-comparator/compare-summaries-first-nil ()
  "Should signal error when first summary is nil."
  (should-error (gptel-benchmark-compare-summaries nil '(:avg-overall 0.5))
                :type 'wrong-type-argument))

(ert-deftest test-comparator/compare-summaries-second-nil ()
  "Should signal error when second summary is nil."
  (should-error (gptel-benchmark-compare-summaries '(:avg-overall 0.4) nil)
                :type 'wrong-type-argument))

(ert-deftest test-comparator/compare-summaries-valid ()
  "Should return improvement plist."
  (let ((result (gptel-benchmark-compare-summaries
                 '(:avg-overall 0.4) '(:avg-overall 0.43))))
    (should (listp result))
    (should (plist-get result :improvement))
    (should (plist-get result :better))
    (should (plist-get result :score-a))
    (should (plist-get result :score-b))))

(provide 'test-gptel-benchmark-comparator)
;;; test-gptel-benchmark-comparator.el ends here
