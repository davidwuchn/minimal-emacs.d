;;; gptel-benchmark-comparator.el --- Benchmark version comparison -*- lexical-binding: t -*-

;; Copyright (C) 2025 David Wu
;; Author: David Wu
;; Version: 1.0.0
;; Keywords: ai, benchmark, comparison

;;; Commentary:

;; Compare different versions of benchmarks to measure improvement.
;; Consolidated from gptel-skill-comparator.el.

;;; Code:

(require 'json)
(require 'cl-lib)
(require 'gptel-benchmark-core)

;;; Version Comparison

(defun gptel-benchmark-compare-versions (name version-a version-b)
  "Compare VERSION-A and VERSION-B of benchmark NAME."
  (let* ((benchmark-a (gptel-benchmark-load-result name version-a))
         (benchmark-b (gptel-benchmark-load-result name version-b))
         (summary-a (gptel-benchmark-summarize-results benchmark-a))
         (summary-b (gptel-benchmark-summarize-results benchmark-b)))
    (list :version-a version-a
          :version-b version-b
          :summary-a summary-a
          :summary-b summary-b
          :comparison (gptel-benchmark-compare-summaries summary-a summary-b))))

(defun gptel-benchmark-baseline-compare (name)
  "Compare current version of NAME against baseline."
  (let* ((current-version (gptel-benchmark-current-version name))
         (baseline-version (gptel-benchmark-baseline-version name))
         (comparison (gptel-benchmark-compare-versions name current-version baseline-version)))
    comparison))

(defun gptel-benchmark-version-trend (name &optional versions)
  "Show trend for NAME across VERSIONS."
  (let ((trend-data '()))
    (if versions
        (dolist (version versions)
          (let* ((benchmark-file (gptel-benchmark-get-file name version))
                 (summary (gptel-benchmark-summarize-results
                           (gptel-benchmark-read-json benchmark-file))))
            (push (list :version version :summary summary) trend-data)))
      (let ((all-versions (gptel-benchmark-get-all-versions name)))
        (dolist (version all-versions)
          (let* ((benchmark-file (gptel-benchmark-get-file name version))
                 (summary (when (file-exists-p benchmark-file)
                            (gptel-benchmark-summarize-results
                             (gptel-benchmark-read-json benchmark-file)))))
            (when summary
              (push (list :version version :summary summary) trend-data))))))
    (nreverse trend-data)))

;;; Summary Comparison

(defun gptel-benchmark-compare-summaries (summary-a summary-b)
  "Compare two benchmark summaries."
  (let* ((score-a (plist-get summary-a :avg-overall))
         (score-b (plist-get summary-b :avg-overall))
         (improvement (- (or score-b 0) (or score-a 0))))
    (list :improvement improvement
          :score-a score-a
          :score-b score-b
          :better (> (or score-b 0) (or score-a 0))
          :regression (< (or score-b 0) (or score-a 0)))))

;;; File/Version Helpers

(defun gptel-benchmark-load-result (name version)
  "Load benchmark result for NAME VERSION."
  (let ((benchmark-file (format "./benchmarks/%s-%s-benchmark.json" name version)))
    (if (file-exists-p benchmark-file)
        (gptel-benchmark-read-json benchmark-file)
      '())))

(defun gptel-benchmark-current-version (name)
  "Get current version of NAME.
Attempts to read version from VERSION file, falls back to
scanning benchmark files, then to hardcoded default."
  (let ((version-file (format "./assistant/skills/%s/VERSION" name))
        (version nil))
    (when (file-exists-p version-file)
      (with-temp-buffer
        (insert-file-contents version-file)
        (goto-char (point-min))
        (when (re-search-forward "^\\([0-9]+\\.[0-9]+\\.[0-9]+\\)" nil t)
          (setq version (match-string 1)))))
    (unless version
      (let ((benchmark-dir "./benchmarks/")
            (found-versions '()))
        (when (file-exists-p benchmark-dir)
          (let ((files (directory-files benchmark-dir nil (format "%s-.*-benchmark\\.json$" name))))
            (dolist (file files)
              (when (string-match (format "%s-\\(.*\\)-benchmark\\.json$" name) file)
                (push (match-string 1 file) found-versions))))
          (when found-versions
            (setq version (car (sort found-versions 'string-greaterp)))))))
    (or version "v1.1")))

(defun gptel-benchmark-baseline-version (name)
  "Get baseline version of NAME for comparison.
Attempts to read from BASELINE file, looks for v1.0 or earliest version,
falls back to hardcoded default."
  (let ((baseline-file (format "./assistant/skills/%s/BASELINE" name))
        (version nil))
    (when (file-exists-p baseline-file)
      (with-temp-buffer
        (insert-file-contents baseline-file)
        (goto-char (point-min))
        (when (re-search-forward "^\\([0-9]+\\.[0-9]+\\.[0-9]+\\)" nil t)
          (setq version (match-string 1)))))
    (unless version
      (let ((benchmark-dir "./benchmarks/")
            (found-versions '()))
        (when (file-exists-p benchmark-dir)
          (let ((files (directory-files benchmark-dir nil (format "%s-.*-benchmark\\.json$" name))))
            (dolist (file files)
              (when (string-match (format "%s-\\(.*\\)-benchmark\\.json$" name) file)
                (push (match-string 1 file) found-versions))))
          (when found-versions
            (setq version (car (sort found-versions 'string<)))))))
    (or version "v1.0")))

(defun gptel-benchmark-get-file (name version)
  "Get benchmark file path for NAME VERSION."
  (format "./benchmarks/%s-%s-benchmark.json" name version))

(defun gptel-benchmark-get-all-versions (name)
  "Get all available versions of NAME by scanning benchmark directory.
Returns a list of version strings found in ./benchmarks/ directory."
  (let ((benchmark-dir "./benchmarks/")
        (versions '()))
    (when (file-exists-p benchmark-dir)
      (let ((files (directory-files benchmark-dir nil (format "%s-.*-benchmark\\.json$" name))))
        (dolist (file files)
          (when (string-match (format "%s-\\(.*\\)-benchmark\\.json$" name) file)
            (let ((version (match-string 1 file)))
              (push version versions))))))
    (if versions
        (sort versions 'string<)
      (list "v1.0" "v1.1"))))

;;; Provide

(provide 'gptel-benchmark-comparator)

;;; gptel-benchmark-comparator.el ends here