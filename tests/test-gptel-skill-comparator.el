;;; test-gptel-skill-comparator.el --- Tests for GPTel Skill Comparator -*- lexical-binding: t -*-

;;; Commentary:

;; Tests for gptel-skill-comparator.el

;;; Code:

(require 'ert)
(require 'gptel-skill-comparator)

(ert-deftest test-gptel-skill-compare-summaries ()
  "Test comparing two summaries."
  (let ((summary-a '(:overall-score . 75.0))
        (summary-b '(:overall-score . 85.0)))
    (let ((comparison (gptel-skill-compare-summaries summary-a summary-b)))
      (should (equal (plist-get comparison :improvement) 10.0))
      (should (plist-get comparison :better))
      (should-not (plist-get comparison :regression)))))

(ert-deftest test-gptel-skill-compare-summaries-regression ()
  "Test detecting regression."
  (let ((summary-a '(:overall-score . 85.0))
        (summary-b '(:overall-score . 75.0)))
    (let ((comparison (gptel-skill-compare-summaries summary-a summary-b)))
      (should (equal (plist-get comparison :improvement) -10.0))
      (should-not (plist-get comparison :better))
      (should (plist-get comparison :regression)))))

(ert-deftest test-gptel-skill-get-all-versions ()
  "Test getting all versions."
  ;; This test will use the fallback since no benchmark directory exists
  (let ((versions (gptel-skill-get-all-versions "test-skill")))
    (should (member "v1.0" versions))
    (should (member "v1.1" versions))))

(provide 'test-gptel-skill-comparator)

;;; test-gptel-skill-comparator.el ends here
