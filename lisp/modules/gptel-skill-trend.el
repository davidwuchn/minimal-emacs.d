;;; gptel-skill-trend.el --- GPTel Skill Historical Trend Tracker -*- lexical-binding: t -*-

;; Copyright (C) 2024 David Wu

;; Author: David Wu <davidwu@example.com>
;; Keywords: ai, trends, history

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Track historical performance trends of GPTel skills over time.

;;; Code:

(require 'json)
(require 'cl-lib)
(require 'gptel-skill-utils)

(defun gptel-skill-trend-load (skill)
  "Load trend data for SKILL."
  (let ((trend-file (format "./benchmarks/%s-trend.json" skill)))
    (if (file-exists-p trend-file)
        (gptel-skill-read-json trend-file)
      '())))

(defun gptel-skill-trend-display (skill)
  "Display trend information for SKILL."
  (let* ((trend-data (gptel-skill-trend-load skill))
         (formatted-data (gptel-skill-format-trend-data trend-data)))
    (with-output-to-temp-buffer "*Skill Trend*"
      (princ formatted-data))))

(defun gptel-skill-trend-export (skill &optional format)
  "Export trend data for SKILL in FORMAT."
  (let* ((trend-data (gptel-skill-trend-load skill))
         (export-format (or format "json")))
    (cond
     ((string= export-format "json")
      (json-encode trend-data))
     ((string= export-format "csv")
      (gptel-skill-export-csv trend-data))
     (t
      (json-encode trend-data)))))

(defun gptel-skill-trend-predict (skill)
  "Predict future performance for SKILL based on trend."
  (let* ((trend-data (gptel-skill-trend-load skill))
         (prediction (gptel-skill-make-prediction trend-data)))
    prediction))

(defun gptel-skill-format-trend-data (trend-data)
  "Format TREND-DATA for display."
  (let ((output ""))
    (dolist (entry trend-data)
      (let* ((date (plist-get entry :date))
             (version (plist-get entry :version))
             (score (plist-get entry :score))
             (line (format "Date: %s | Version: %s | Score: %.2f%%\n" date version score)))
        (setq output (concat output line))))
    output))

(defun gptel-skill-export-csv (trend-data)
  "Export TREND-DATA as CSV."
  (let ((csv "Date,Version,Score\n"))
    (dolist (entry trend-data)
      (let* ((date (plist-get entry :date))
             (version (plist-get entry :version))
             (score (plist-get entry :score))
             (line (format "%s,%s,%.2f\n" date version score)))
        (setq csv (concat csv line))))
    csv))

(defun gptel-skill-make-prediction (trend-data)
  "Make performance prediction based on TREND-DATA."
  (if (null trend-data)
      (list :prediction "insufficient data" :confidence 0)
    (let* ((sorted-data (gptel-skill-sort-by-date trend-data))
           (recent-data (gptel-skill-get-recent-data sorted-data))
           (slope (gptel-skill-calculate-slope recent-data))
           (next-score (gptel-skill-predict-next-score recent-data slope)))
      (list :predicted-score next-score
            :trend (if (> slope 0) "improving" (if (< slope 0) "declining" "stable"))
            :confidence (gptel-skill-calculate-confidence recent-data)))))

(defun gptel-skill-sort-by-date (trend-data)
  "Sort TREND-DATA by date."
  (cl-sort (copy-sequence trend-data) 
           (lambda (a b) 
             (string< (plist-get a :date) (plist-get b :date)))))

(defun gptel-skill-get-recent-data (sorted-data)
  "Get most recent entries from SORTED-DATA."
  (let ((count (min 5 (length sorted-data))))
    (cl-subseq sorted-data (- (length sorted-data) count))))

(defun gptel-skill-calculate-slope (data)
  "Calculate trend slope from DATA."
  (if (< (length data) 2)
      0
    (let* ((first-score (plist-get (car data) :score))
           (last-score (plist-get (car (last data)) :score))
           (slope (- last-score first-score)))
      slope)))

(defun gptel-skill-predict-next-score (data slope)
  "Predict next score based on DATA and SLOPE."
  (if (null data)
      0
    (let ((last-score (plist-get (car (last data)) :score)))
      (+ last-score slope))))

(defun gptel-skill-calculate-confidence (data)
  "Calculate confidence in prediction based on DATA."
  (if (null data)
      0
    (/ (length data) 5.0)))  ; Max confidence with 5+ data points

(provide 'gptel-skill-trend)

;;; gptel-skill-trend.el ends here
