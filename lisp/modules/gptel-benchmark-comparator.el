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
(declare-function cl-last "cl-lib")

;;; Memoization Cache for Performance

(defvar gptel-benchmark-result-cache (make-hash-table :test 'equal)
  "Cache for loaded benchmark results to avoid repeated file I/O.")

(defun gptel-benchmark--cache-get (key)
  "Get cached value for KEY from result cache."
  (gethash key gptel-benchmark-result-cache))

(defun gptel-benchmark--require-valid-string (value type-name)
  "Signal error if VALUE is not a valid non-empty string.
TYPE-NAME is a symbol describing the expected type for error messages.
Returns VALUE if valid.
Internal helper to centralize string validation logic."
  (unless (and value (stringp value) (not (string-empty-p value)))
    (signal 'wrong-type-argument (list type-name value)))
  value)

(defun gptel-benchmark--require-valid-name (name)
  "Signal error if NAME is not a valid non-empty string.
Returns NAME if valid."
  (gptel-benchmark--require-valid-string name 'benchmark-name))

(defun gptel-benchmark--require-valid-version (version)
  "Signal error if VERSION is not a valid non-empty string.
Returns VERSION if valid."
  (gptel-benchmark--require-valid-string version 'version))

(defun gptel-benchmark--cache-put (key value)
  "Store KEY-VALUE pair in result cache.
KEY and VALUE must be non-nil."
  (unless key
    (signal 'wrong-type-argument (list 'non-nil key)))
  (unless value
    (signal 'wrong-type-argument (list 'non-nil value)))
  (puthash key value gptel-benchmark-result-cache))

(defun gptel-benchmark--clear-result-cache ()
  "Clear the benchmark result cache.
Call this when benchmark files are updated."
  (clrhash gptel-benchmark-result-cache))

;;; Version Comparison

(defun gptel-benchmark-compare-file-versions (name version-a version-b)
  "Compare VERSION-A and VERSION-B of benchmark NAME using file-based approach."
  (gptel-benchmark--require-valid-name name)
  (let* ((benchmark-a (gptel-benchmark-load-result name version-a))
         (benchmark-b (gptel-benchmark-load-result name version-b)))
    (when (null benchmark-a)
      (signal 'user-error (format "Benchmark file not found for %s version %s" name version-a)))
    (when (null benchmark-b)
      (signal 'user-error (format "Benchmark file not found for %s version %s" name version-b)))
    (let* ((summary-a (gptel-benchmark-summarize-results benchmark-a))
           (summary-b (gptel-benchmark-summarize-results benchmark-b)))
      (list :version-a version-a
            :version-b version-b
            :summary-a summary-a
            :summary-b summary-b
            :comparison (gptel-benchmark-compare-summaries summary-a summary-b)))))

(defun gptel-benchmark-baseline-file-compare (name)
  "Compare current version of NAME against baseline using file-based approach."
  (gptel-benchmark--require-valid-name name)
  (let* ((current-version (gptel-benchmark-current-version name))
         (baseline-version (gptel-benchmark-baseline-version name))
         ;; ASSUMPTION: compare-summaries treats version-a as baseline and
         ;; version-b as candidate (improvement = score-b - score-a).
         ;; Pass baseline as version-a and current as version-b so
         ;; improvement reflects current relative to baseline.
         (comparison (gptel-benchmark-compare-file-versions name baseline-version current-version)))
    comparison))

(defun gptel-benchmark--get-trend-summary (name version)
  "Get benchmark summary for NAME VERSION, or nil if file doesn't exist.
Internal helper to centralize trend data extraction logic."
  (let ((benchmark-data (gptel-benchmark-load-result name version)))
    (when (and benchmark-data (proper-list-p benchmark-data))
      (gptel-benchmark-summarize-results benchmark-data))))

(defun gptel-benchmark-version-trend (name &optional versions)
  "Show trend for NAME across VERSIONS.
If VERSIONS is a proper list, use it directly; otherwise scan for all available versions."
  (gptel-benchmark--require-valid-name name)
  (let ((trend-data '())
        (versions-to-process (if (and (proper-list-p versions) (not (null versions)))
                                 versions
                               (gptel-benchmark-get-all-versions name))))
    (dolist (version versions-to-process)
      (let ((summary (gptel-benchmark--get-trend-summary name version)))
        (when summary
          (push (list :version version :summary summary) trend-data))))
    (nreverse trend-data)))

;;; Summary Comparison

(defun gptel-benchmark-compare-summaries (summary-a summary-b)
  "Compare two benchmark summaries."
  (unless (proper-list-p summary-a)
    (signal 'wrong-type-argument (list "proper-list-p" summary-a)))
  (unless (proper-list-p summary-b)
    (signal 'wrong-type-argument (list "proper-list-p" summary-b)))
  (let* ((score-a (plist-get summary-a :avg-overall))
         (score-b (plist-get summary-b :avg-overall)))
    (unless (plist-member summary-a :avg-overall)
      (signal 'wrong-type-argument (list "expected :avg-overall key in plist" summary-a)))
    (unless (plist-member summary-b :avg-overall)
      (signal 'wrong-type-argument (list "expected :avg-overall key in plist" summary-b)))
    (unless (numberp score-a)
      (signal 'wrong-type-argument (list "numberp" score-a)))
    (unless (numberp score-b)
      (signal 'wrong-type-argument (list "numberp" score-b)))
    (let* ((improvement (- score-b score-a)))
      (list :improvement improvement
            :score-a score-a
            :score-b score-b
            :better (> score-b score-a)
            :regression (< score-b score-a)))))

;;; File/Version Helpers

(defun gptel-benchmark-load-result (name version)
  "Load benchmark result for NAME VERSION.
Results are cached to avoid repeated file I/O for the same benchmark.
Returns nil if the benchmark file does not exist."
  (gptel-benchmark--require-valid-name name)
  (gptel-benchmark--require-valid-version version)
  (let* ((cache-key (cons name version))
         (cached (gptel-benchmark--cache-get cache-key)))
    (if cached
        cached
      (let ((benchmark-file (gptel-benchmark-get-file name version)))
        (when (file-exists-p benchmark-file)
          (let ((result (gptel-benchmark-read-json benchmark-file)))
            (when result
              (gptel-benchmark--cache-put cache-key result))
            result))))))

(defun gptel-benchmark--read-version-file (name file-type fallback-fn default)
  "Read version from NAME's FILE-TYPE file.
FILE-TYPE is \"VERSION\" or \"BASELINE\".
FALLBACK-FN is a function to call on found-versions if file read fails.
DEFAULT is the fallback value if nothing found.
Internal helper to centralize version file reading logic."
  (let ((version-file (format "./assistant/skills/%s/%s" name file-type))
        (version nil))
    (when (file-exists-p version-file)
      (with-temp-buffer
        (insert-file-contents version-file)
        (goto-char (point-min))
        (when (re-search-forward "^\\([0-9]+\\.[0-9]+\\.[0-9]+\\)" nil t)
          (setq version (match-string 1)))))
    (unless version
      (let ((found-versions (gptel-benchmark--scan-versions-from-dir name)))
        (when (and (proper-list-p found-versions) found-versions (functionp fallback-fn))
          (let ((fallback-result (funcall fallback-fn found-versions)))
            (when (stringp fallback-result)
              (setq version fallback-result))))))
    (or version default)))

(defun gptel-benchmark-current-version (name)
  "Get current version of NAME.
Attempts to read version from VERSION file, falls back to
scanning benchmark files, then to hardcoded default."
  (gptel-benchmark--require-valid-name name)
  (gptel-benchmark--read-version-file name "VERSION" #'car "v1.1"))

(defun gptel-benchmark-baseline-version (name)
  "Get baseline version of NAME for comparison.
Attempts to read from BASELINE file, looks for v1.0 or earliest version,
falls back to hardcoded default."
  (gptel-benchmark--require-valid-name name)
  (gptel-benchmark--read-version-file name "BASELINE" #'cl-last "v1.0"))

(defun gptel-benchmark-get-file (name version)
  "Get benchmark file path for NAME VERSION."
  (gptel-benchmark--require-valid-name name)
  (gptel-benchmark--require-valid-version version)
  (format "./benchmarks/%s-%s-benchmark.json" name version))

(defun gptel-benchmark--scan-versions-from-dir (name)
  "Scan benchmarks directory for NAME and return sorted version strings.
Internal helper to avoid code duplication."
  (unless (and name (stringp name) (not (string-empty-p name)))
    (signal 'wrong-type-argument (list "stringp" name)))
  (let ((benchmark-dir "./benchmarks/")
        (versions '()))
    (when (file-exists-p benchmark-dir)
      (let ((files (directory-files benchmark-dir nil (format "%s-.*-benchmark\\.json$" (regexp-quote name)))))
        (dolist (file files)
          (when (string-match (format "%s-\\(.*\\)-benchmark\\.json$" (regexp-quote name)) file)
            (push (match-string 1 file) versions)))))
    (if versions
        (sort versions 'string<)
      '())))

(defun gptel-benchmark-get-all-versions (name)
  "Get all available versions of NAME by scanning benchmark directory.
Returns a list of version strings found in ./benchmarks/ directory."
  (gptel-benchmark--require-valid-name name)
  (or (gptel-benchmark--scan-versions-from-dir name)
      (list "v1.0" "v1.1")))

;;; Provide

(provide 'gptel-benchmark-comparator)

;;; gptel-benchmark-comparator.el ends here
