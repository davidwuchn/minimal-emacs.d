;;; test-gptel-skill-trend.el --- Tests for GPTel Skill Trend Tracker -*- lexical-binding: t -*-

;;; Commentary:

;; Tests for gptel-skill-trend.el

;;; Code:

(require 'ert)
(require 'gptel-skill-trend)

(ert-deftest test-gptel-skill-format-trend-data ()
  "Test formatting trend data for display."
  (let ((trend-data '((( :date . "2024-01-01")
                       (:version . "v1.0")
                       (:score . 75.5))
                      (( :date . "2024-01-15")
                       (:version . "v1.1")
                       (:score . 82.3)))))
    (let ((formatted (gptel-skill-format-trend-data trend-data)))
      (should (string-match-p "2024-01-01" formatted))
      (should (string-match-p "v1.0" formatted))
      (should (string-match-p "75.50" formatted))
      (should (string-match-p "v1.1" formatted))
      (should (string-match-p "82.30" formatted)))))

(ert-deftest test-gptel-skill-export-csv ()
  "Test exporting trend data as CSV."
  (let ((trend-data '((( :date . "2024-01-01")
                       (:version . "v1.0")
                       (:score . 75.5))
                      (( :date . "2024-01-15")
                       (:version . "v1.1")
                       (:score . 82.3)))))
    (let ((csv (gptel-skill-export-csv trend-data)))
      (should (string-match-p "Date,Version,Score" csv))
      (should (string-match-p "2024-01-01,v1.0,75.50" csv))
      (should (string-match-p "2024-01-15,v1.1,82.30" csv)))))

(ert-deftest test-gptel-skill-sort-by-date ()
  "Test sorting trend data by date."
  (let ((trend-data '((( :date . "2024-01-15")
                       (:version . "v1.1")
                       (:score . 82.3))
                      (( :date . "2024-01-01")
                       (:version . "v1.0")
                       (:score . 75.5)))))
    (let ((sorted (gptel-skill-sort-by-date trend-data)))
      (should (equal (plist-get (car sorted) :date) "2024-01-01"))
      (should (equal (plist-get (cadr sorted) :date) "2024-01-15")))))

(ert-deftest test-gptel-skill-calculate-slope ()
  "Test calculating trend slope."
  (let ((data '((( :date . "2024-01-01")
                 (:score . 70.0))
                (( :date . "2024-01-15")
                 (:score . 80.0)))))
    (should (equal (gptel-skill-calculate-slope data) 10.0))))

(ert-deftest test-gptel-skill-predict-next-score ()
  "Test predicting next score."
  (let ((data '((( :date . "2024-01-01")
                 (:score . 70.0))
                (( :date . "2024-01-15")
                 (:score . 80.0)))))
    (should (equal (gptel-skill-predict-next-score data 10.0) 90.0))))

(ert-deftest test-gptel-skill-make-prediction-insufficient-data ()
  "Test prediction with insufficient data."
  (let ((prediction (gptel-skill-make-prediction '())))
    (should (equal (plist-get prediction :prediction) "insufficient data"))
    (should (equal (plist-get prediction :confidence) 0))))

(provide 'test-gptel-skill-trend)

;;; test-gptel-skill-trend.el ends here
