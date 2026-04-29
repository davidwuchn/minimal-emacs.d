;;; gptel-benchmark-analysis.el --- Benchmark result analysis -*- lexical-binding: t -*-

;; Copyright (C) 2025 David Wu
;; Author: David Wu
;; Version: 1.0.0
;; Keywords: ai, benchmark, analysis

;;; Commentary:

;; Analyzes benchmark results to identify patterns, flaky tests, and systematic failures.
;; Consolidated from gptel-skill-analyzer.el.

;;; Code:

(require 'json)
(require 'cl-lib)
(require 'gptel-benchmark-core)

(declare-function gptel-agent--task "gptel-agent-tools")

;;; Main Analysis

(defun gptel-benchmark-analyze-results (benchmark-file)
  "Analyze results in BENCHMARK-FILE.
Returns plist with flaky tests, non-discriminating tests, and systematic failures."
  (if (fboundp 'gptel-agent--task)
      (let ((result nil) (done nil))
        (gptel-agent--task
         (lambda (r)
           (setq result r done t))
         "analyzer"
         (format "Analyze: %s" (file-name-base benchmark-file))
         (format "Analyze benchmark results in %s. Output JSON with findings and recommendations."
                 benchmark-file))
        (while (not done) (sit-for 0.1))
        (gptel-benchmark--parse-analysis-result result))
    (let* ((data (gptel-benchmark-read-json benchmark-file))
           (flaky-tests (gptel-benchmark-find-flaky-tests benchmark-file))
           (non-discriminating (gptel-benchmark-find-non-discriminating benchmark-file))
           (systematic-failures (gptel-benchmark-find-systematic-failures benchmark-file)))
      (list :flaky-tests flaky-tests
            :non-discriminating-tests non-discriminating
            :systematic-failures systematic-failures
            :summary (gptel-benchmark-generate-summary data)))))

(defun gptel-benchmark--parse-analysis-result (result)
  "Parse analyzer RESULT into plist."
  (if (stringp result)
      (condition-case nil
          (let ((parsed (json-read-from-string result)))
            (list :summary (cdr (assq 'summary parsed))
                  :findings (cdr (assq 'findings parsed))
                  :recommendations (cdr (assq 'recommendations parsed))))
        (error (list :raw result)))
    (list :raw (format "%S" result))))

;;; Flaky Test Detection

(defun gptel-benchmark--group-by-test-id (data)
  "Group benchmark DATA by test-id.
Returns a hash table mapping test-id to list of results."
  (let ((table (make-hash-table :test 'equal)))
    (dolist (result data)
      (let ((test-id (plist-get result :test-id)))
        (puthash test-id (cons result (gethash test-id table '())) table)))
    table))

(defun gptel-benchmark--result-passed-p (result)
  "Extract pass/fail status from RESULT.
Returns t if the result passed, nil otherwise.
Returns nil for missing or malformed grade data."
  (let ((grade (plist-get result :grade)))
    (and (listp grade) (plist-get grade :passed))))

(defun gptel-benchmark--flaky-test-p (results)
  "Check if RESULTS show inconsistent pass/fail across runs.
RESULTS is a list of benchmark results for a single test-id."
  (let ((pass-count 0) (fail-count 0))
    (dolist (result results)
      (if (gptel-benchmark--result-passed-p result)
          (cl-incf pass-count)
        (cl-incf fail-count)))
    (and (> pass-count 0) (> fail-count 0))))

(defun gptel-benchmark-find-flaky-tests (benchmark-file)
  "Identify tests that sometimes pass and sometimes fail in BENCHMARK-FILE."
  (let* ((data (gptel-benchmark-read-json benchmark-file))
         (test-results (gptel-benchmark--group-by-test-id data))
         (flaky-tests '()))
    (maphash (lambda (test-id results)
               (when (gptel-benchmark--flaky-test-p results)
                 (push test-id flaky-tests)))
             test-results)
    flaky-tests))

;;; Non-Discriminating Test Detection

(defun gptel-benchmark--non-discriminating-p (results)
  "Check if RESULTS don't differentiate skill levels.
RESULTS is a list of benchmark results for a single test-id."
  (let ((all-pass t) (all-fail t) (run-count 0))
    (dolist (result results)
      (cl-incf run-count)
      (if (gptel-benchmark--result-passed-p result)
          (setq all-fail nil)
        (setq all-pass nil)))
    (and (> run-count 1) (or all-pass all-fail))))

(defun gptel-benchmark-find-non-discriminating (benchmark-file)
  "Find tests that don't effectively differentiate between skill levels."
  (let* ((data (gptel-benchmark-read-json benchmark-file))
         (test-results (gptel-benchmark--group-by-test-id data))
         (non-discriminating '()))
    (maphash (lambda (test-id results)
               (when (gptel-benchmark--non-discriminating-p results)
                 (push test-id non-discriminating)))
             test-results)
    non-discriminating))

;;; Systematic Failure Detection

(defun gptel-benchmark--systematic-failure-p (results)
  "Check if RESULTS represent a systematic failure.
RESULTS is a list of benchmark results for a single test-id."
  (let ((fail-count 0) (total-count 0))
    (dolist (result results)
      (cl-incf total-count)
      (unless (gptel-benchmark--result-passed-p result)
        (cl-incf fail-count)))
    (and (> total-count 1)
         (> (/ (float fail-count) total-count) 0.8))))

(defun gptel-benchmark-find-systematic-failures (benchmark-file)
  "Identify tests that consistently fail across different skills."
  (let* ((data (gptel-benchmark-read-json benchmark-file))
         (test-results (gptel-benchmark--group-by-test-id data))
         (systematic-failures '()))
    (maphash (lambda (test-id results)
               (when (gptel-benchmark--systematic-failure-p results)
                 (push test-id systematic-failures)))
             test-results)
    systematic-failures))

;;; Summary Generation

(defun gptel-benchmark-generate-summary (data)
  "Generate summary statistics from benchmark DATA.
Skips entries with missing :grade or :percentage fields."
  (let ((total-tests (length data))
        (avg-score 0)
        (scored-count 0))
    (dolist (result data)
      (let* ((grade (plist-get result :grade))
             (pct (and (listp grade) (plist-get grade :percentage))))
        (when (numberp pct)
          (cl-incf avg-score pct)
          (cl-incf scored-count))))
    (when (> scored-count 0)
      (setq avg-score (/ avg-score scored-count)))
    (list :total-tests total-tests
          :average-score avg-score
          :scored-count scored-count)))

(defun gptel-benchmark-generate-improvement-plan (analysis)
  "Generate improvement plan based on ANALYSIS."
  (let* ((flaky-tests (plist-get analysis :flaky-tests))
         (non-discriminating (plist-get analysis :non-discriminating-tests))
         (systematic-failures (plist-get analysis :systematic-failures))
         (recommendations '()))
    (when flaky-tests
      (push "Investigate and stabilize flaky tests" recommendations))
    (when non-discriminating
      (push "Revise non-discriminating tests to better differentiate skill levels" recommendations))
    (when systematic-failures
      (push "Review systematically failing tests for appropriate difficulty level" recommendations))
    (list :recommendations recommendations
          :priority (gptel-benchmark-assess-priority flaky-tests non-discriminating systematic-failures))))

(defun gptel-benchmark-assess-priority (flaky non-discriminating systematic)
  "Assess priority of issues.
FLAKY, NON-DISCRIMINATING, and SYSTEMATIC are lists of test IDs."
  (let ((high-priority 0)
        (medium-priority 0)
        (low-priority 0))
    (when flaky
      (cl-incf high-priority (length flaky)))
    (when systematic
      (cl-incf medium-priority (length systematic)))
    (when non-discriminating
      (cl-incf low-priority (length non-discriminating)))
    (list :high high-priority
          :medium medium-priority
          :low low-priority)))

;;; Provide

(provide 'gptel-benchmark-analysis)

;;; gptel-benchmark-analysis.el ends here
