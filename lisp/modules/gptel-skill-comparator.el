;;; gptel-skill-comparator.el --- GPTel Skill Version Comparator -*- lexical-binding: t -*-

;; Copyright (C) 2024 David Wu

;; Author: David Wu <davidwu@example.com>
;; Keywords: ai, comparison, benchmark

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

;; Compare different versions of GPTel skills to measure improvement.

;;; Code:

(require 'json)
(require 'cl-lib)
(require 'gptel-skill-benchmark)
(require 'gptel-skill-utils)

(defun gptel-skill-compare-versions (skill version-a version-b)
  "Compare VERSION-A and VERSION-B of SKILL."
  (let* ((benchmark-a (gptel-skill-load-benchmark-result skill version-a))
         (benchmark-b (gptel-skill-load-benchmark-result skill version-b))
         (summary-a (gptel-skill-benchmark-summary benchmark-a))
         (summary-b (gptel-skill-benchmark-summary benchmark-b)))
    (list :version-a version-a
          :version-b version-b
          :summary-a summary-a
          :summary-b summary-b
          :comparison (gptel-skill-compare-summaries summary-a summary-b))))

(defun gptel-skill-baseline-compare (skill)
  "Compare current version of SKILL against baseline."
  (let* ((current-version (gptel-skill-current-version skill))
         (baseline-version (gptel-skill-baseline-version skill))
         (comparison (gptel-skill-compare-versions skill current-version baseline-version)))
    comparison))

(defun gptel-skill-trend (skill &optional versions)
  "Show trend for SKILL across VERSIONS."
  (let ((trend-data '()))
    (if versions
        (dolist (version versions)
          (let* ((benchmark-file (gptel-skill-get-benchmark-file skill version))
                 (summary (gptel-skill-benchmark-summary benchmark-file)))
            (push (list :version version :summary summary) trend-data)))
      ;; If no versions specified, get all available versions
      (let ((all-versions (gptel-skill-get-all-versions skill)))
        (dolist (version all-versions)
          (let* ((benchmark-file (gptel-skill-get-benchmark-file skill version))
                 (summary (gptel-skill-benchmark-summary benchmark-file)))
            (push (list :version version :summary summary) trend-data)))))
    trend-data))

(defun gptel-skill-compare-summaries (summary-a summary-b)
  "Compare two benchmark summaries."
  (let* ((score-a (plist-get summary-a :overall-score))
         (score-b (plist-get summary-b :overall-score))
         (improvement (- score-b score-a)))
    (list :improvement improvement
          :score-a score-a
          :score-b score-b
          :better (> score-b score-a)
          :regression (< score-b score-a))))

(defun gptel-skill-load-benchmark-result (skill version)
  "Load benchmark result for SKILL VERSION."
  (let ((benchmark-file (format "./benchmarks/%s-%s-benchmark.json" skill version)))
    (if (file-exists-p benchmark-file)
        (gptel-skill-read-json benchmark-file)
      '())))

(defun gptel-skill-current-version (skill)
  "Get current version of SKILL.
Attempts to read version from SKILL-VERSION file, falls back to
scanning benchmark files, then to hardcoded default."
  (let ((version-file (format "./assistant/skills/%s/VERSION" skill))
        (version nil))
    ;; Try reading from VERSION file first
    (when (file-exists-p version-file)
      (with-temp-buffer
        (insert-file-contents version-file)
        (goto-char (point-min))
        (when (re-search-forward "^\\([0-9]+\\.[0-9]+\\.[0-9]+\\)" nil t)
          (setq version (match-string 1)))))
    ;; Fallback to scanning benchmark files
    (unless version
      (let ((benchmark-dir "./benchmarks/")
            (found-versions '()))
        (when (file-exists-p benchmark-dir)
          (let ((files (directory-files benchmark-dir nil (format "%s-.*-benchmark\\.json$" skill))))
            (dolist (file files)
              (when (string-match (format "%s-\\(.*\\)-benchmark\\.json$" skill) file)
                (push (match-string 1 file) found-versions))))
          (when found-versions
            (setq version (car (sort found-versions 'string-greaterp)))))))
    ;; Final fallback
    (or version "v1.1")))

(defun gptel-skill-baseline-version (skill)
  "Get baseline version of SKILL for comparison.
Attempts to read from SKILL-BASELINE file, looks for v1.0 or earliest version,
falls back to hardcoded default."
  (let ((baseline-file (format "./assistant/skills/%s/BASELINE" skill))
        (version nil))
    ;; Try reading from BASELINE file first
    (when (file-exists-p baseline-file)
      (with-temp-buffer
        (insert-file-contents baseline-file)
        (goto-char (point-min))
        (when (re-search-forward "^\\([0-9]+\\.[0-9]+\\.[0-9]+\\)" nil t)
          (setq version (match-string 1)))))
    ;; Fallback to finding earliest version
    (unless version
      (let ((benchmark-dir "./benchmarks/")
            (found-versions '()))
        (when (file-exists-p benchmark-dir)
          (let ((files (directory-files benchmark-dir nil (format "%s-.*-benchmark\\.json$" skill))))
            (dolist (file files)
              (when (string-match (format "%s-\\(.*\\)-benchmark\\.json$" skill) file)
                (push (match-string 1 file) found-versions))))
          (when found-versions
            (setq version (car (sort found-versions 'string<)))))))
    ;; Final fallback
    (or version "v1.0")))

(defun gptel-skill-get-benchmark-file (skill version)
  "Get benchmark file path for SKILL VERSION."
  (format "./benchmarks/%s-%s-benchmark.json" skill version))

(defun gptel-skill-get-all-versions (skill)
  "Get all available versions of SKILL by scanning benchmark directory.
Returns a list of version strings found in ./benchmarks/ directory."
  (let ((benchmark-dir "./benchmarks/")
        (versions '()))
    (when (file-exists-p benchmark-dir)
      (let ((files (directory-files benchmark-dir nil (format "%s-.*-benchmark\\.json$" skill))))
        (dolist (file files)
          (when (string-match (format "%s-\\(.*\\)-benchmark\\.json$" skill) file)
            (let ((version (match-string 1 file)))
              (push version versions))))))
    (if versions
        (sort versions 'string<)
      ;; Fallback if no benchmarks found
      (list "v1.0" "v1.1"))))

(provide 'gptel-skill-comparator)

;;; gptel-skill-comparator.el ends here
