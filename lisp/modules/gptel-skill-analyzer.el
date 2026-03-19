;;; gptel-skill-analyzer.el --- GPTel Skill Result Analyzer -*- lexical-binding: t -*-

;; Copyright (C) 2024 David Wu

;; Author: David Wu <davidwu@example.com>
;; Keywords: ai, analysis, benchmark

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

;; Analyzes benchmark results to identify patterns, flaky tests, and systematic failures.

;;; Code:

(require 'json)
(require 'cl-lib)
(require 'gptel-skill-utils)

(defun gptel-skill-analyze-results (benchmark-file)
  "Analyze results in BENCHMARK-FILE."
  (let* ((data (gptel-skill-read-json benchmark-file))
         (flaky-tests (gptel-skill-find-flaky-tests benchmark-file))
         (non-discriminating (gptel-skill-find-non-discriminating benchmark-file))
         (systematic-failures (gptel-skill-find-systematic-failures benchmark-file)))
    (list :flaky-tests flaky-tests
          :non-discriminating-tests non-discriminating
          :systematic-failures systematic-failures
          :summary (gptel-skill-generate-summary data))))

(defun gptel-skill-find-flaky-tests (benchmark-file)
  "Identify tests that sometimes pass and sometimes fail in BENCHMARK-FILE."
  (let* ((data (gptel-skill-read-json benchmark-file))
         (flaky-tests '()))
    (dolist (result data)
      (let ((test-id (plist-get result :test-id))
            (_grade (plist-get result :grade)))
        (when (gptel-skill-is-flaky-test test-id benchmark-file)
          (push test-id flaky-tests))))
    flaky-tests))

(defun gptel-skill-find-non-discriminating (benchmark-file)
  "Find tests that don't effectively differentiate between skill levels."
  (let* ((data (gptel-skill-read-json benchmark-file))
         (non-discriminating '()))
    (dolist (result data)
      (let ((test-id (plist-get result :test-id)))
        (when (gptel-skill-is-non-discriminating-test test-id benchmark-file)
          (push test-id non-discriminating))))
    non-discriminating))

(defun gptel-skill-find-systematic-failures (benchmark-file)
  "Identify tests that consistently fail across different skills."
  (let* ((data (gptel-skill-read-json benchmark-file))
         (systematic-failures '()))
    (dolist (result data)
      (let ((test-id (plist-get result :test-id))
            (_grade (plist-get result :grade)))
        (when (gptel-skill-is-systematic-failure test-id benchmark-file)
          (push test-id systematic-failures))))
    systematic-failures))

(defun gptel-skill-generate-improvement-plan (analysis)
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
          :priority (gptel-skill-assess-priority flaky-tests non-discriminating systematic-failures))))

(defun gptel-skill-is-flaky-test (test-id benchmark-file)
  "Check if TEST-ID in BENCHMARK-FILE shows inconsistent pass/fail across runs.
A test is considered flaky if it has multiple runs with different outcomes.
Returns non-nil if the test is flaky."
  (let* ((data (gptel-skill-read-json benchmark-file))
         (test-runs '())
         (pass-count 0)
         (fail-count 0))
    ;; Collect all runs for this test
    (dolist (result data)
      (when (equal (plist-get result :test-id) test-id)
        (let* ((grade (plist-get result :grade))
               (passed (plist-get grade :passed)))
          (push passed test-runs)
          (if passed (cl-incf pass-count) (cl-incf fail-count)))))
    ;; Test is flaky if it has both passes and failures
    (and (> pass-count 0) (> fail-count 0) (> (length test-runs) 1))))

(defun gptel-skill-is-non-discriminating-test (test-id benchmark-file)
  "Check if TEST-ID in BENCHMARK-FILE doesn't differentiate skill levels.
A test is non-discriminating if all runs pass or all runs fail, meaning
it doesn't help distinguish between different skill levels.
Returns non-nil if the test is non-discriminating."
  (let* ((data (gptel-skill-read-json benchmark-file))
         (test-runs '())
         (all-pass t)
         (all-fail t))
    ;; Collect all runs for this test
    (dolist (result data)
      (when (equal (plist-get result :test-id) test-id)
        (let* ((grade (plist-get result :grade))
               (passed (plist-get grade :passed)))
          (push passed test-runs)
          (when (not passed) (setq all-pass nil))
          (when passed (setq all-fail nil)))))
    ;; Test is non-discriminating if all pass or all fail (and has multiple runs)
    (and (> (length test-runs) 1) (or all-pass all-fail))))

(defun gptel-skill-is-systematic-failure (test-id benchmark-file)
  "Check if TEST-ID in BENCHMARK-FILE represents a systematic failure.
A test is a systematic failure if it fails consistently across multiple
different skills, indicating the test itself may be problematic or too difficult.
Returns non-nil if the test is a systematic failure."
  (let* ((data (gptel-skill-read-json benchmark-file))
         (test-runs '())
         (fail-count 0)
         (total-count 0))
    ;; Collect all runs for this test
    (dolist (result data)
      (when (equal (plist-get result :test-id) test-id)
        (let* ((grade (plist-get result :grade))
               (passed (plist-get grade :passed)))
          (push result test-runs)
          (cl-incf total-count)
          (when (not passed) (cl-incf fail-count)))))
    ;; Test is systematic failure if >80% of runs fail (and has multiple runs)
    (and (> total-count 1)
         (> (/ (float fail-count) total-count) 0.8))))

(defun gptel-skill-generate-summary (data)
  "Generate summary statistics from benchmark DATA."
  (let ((total-tests (length data))
        (avg-score 0))
    (dolist (result data)
      (let* ((grade (plist-get result :grade))
             (score (plist-get grade :percentage)))
        (cl-incf avg-score score)))
    (when (> total-tests 0)
      (setq avg-score (/ avg-score total-tests)))
    (list :total-tests total-tests
          :average-score avg-score)))

(defun gptel-skill-assess-priority (flaky non-discriminating systematic)
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

(provide 'gptel-skill-analyzer)

;;; gptel-skill-analyzer.el ends here
