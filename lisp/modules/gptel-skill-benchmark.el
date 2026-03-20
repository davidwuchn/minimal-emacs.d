;;; gptel-skill-benchmark.el --- GPTel Skill Benchmarking Engine -*- lexical-binding: t -*-

;; Copyright (C) 2024 David Wu

;; Author: David Wu <davidwu@example.com>
;; Keywords: ai, benchmark, testing

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

;; Core engine for benchmarking GPTel skills.
;; Uses existing agents (grader, analyzer, comparator) via gptel-agent--task.
;; All operations are async with callbacks.

;;; Code:

(require 'json)
(require 'cl-lib)
(require 'gptel-skill-utils)

(declare-function gptel-agent--task "gptel-agent-tools")

;;; Customization

(defgroup gptel-skill-benchmark nil
  "Benchmarking for GPTel skills."
  :group 'gptel)

(defcustom gptel-skill-benchmark-dir "./benchmarks/"
  "Directory where benchmark results are stored."
  :type 'directory
  :group 'gptel-skill-benchmark)

(defcustom gptel-skill-tests-dir "./assistant/evals/skill-tests/"
  "Directory where test definitions are stored."
  :type 'directory
  :group 'gptel-skill-benchmark)

(defcustom gptel-skill-skills-dir "./assistant/skills/"
  "Directory where skill definitions are stored."
  :type 'directory
  :group 'gptel-skill-benchmark)

;;; Cancel Support

(defvar gptel-skill-benchmark--cancelled nil
  "Flag to cancel running benchmark.")

;;; Test Loading

(defun gptel-skill-load-tests (skill-name)
  "Load test definitions for SKILL-NAME.
Returns list of test plists with :id, :name, :prompt, :expected_behaviors, :forbidden_behaviors."
  (let ((test-file (expand-file-name (format "%s.json" skill-name) gptel-skill-tests-dir)))
    (if (file-exists-p test-file)
        (let* ((data (gptel-skill-read-json test-file))
               (test-cases (cdr (assq 'test_cases data))))
          (mapcar #'gptel-skill--normalize-test test-cases))
      '())))

(defun gptel-skill--normalize-test (test)
  "Normalize TEST alist to plist format."
  (list :id (cdr (assq 'id test))
        :name (cdr (assq 'name test))
        :prompt (cdr (assq 'prompt test))
        :expected_behaviors (cdr (assq 'expected_behaviors test))
        :forbidden_behaviors (cdr (assq 'forbidden_behaviors test))))

;;; Async Skill Execution

(defun gptel-skill-execute-test (skill test-id prompt callback)
  "Execute TEST-ID for SKILL with PROMPT using gptel-agent--task.
Calls CALLBACK with result string asynchronously."
  (gptel-skill-feedback-log 'execute (format "Executing test %s for skill %s" test-id skill))
  (condition-case err
      (if (fboundp 'gptel-agent--task)
          (gptel-agent--task
           callback
           skill
           (format "Benchmark test: %s" test-id)
           prompt)
        (funcall callback (format "[MOCK] Skill %s: %s"
                                  skill (truncate-string-to-width prompt 100 nil nil "..."))))
    (error
     (funcall callback (format "ERROR: %s" (error-message-string err))))))

;;; Async Grading

(defun gptel-skill-grade-with-agent (test-id output expected forbidden callback)
  "Grade test TEST-ID using grader agent asynchronously.
OUTPUT is the skill output. EXPECTED and FORBIDDEN are behavior lists.
Calls CALLBACK with grade plist."
  (let* ((grading-prompt (gptel-skill--make-grading-prompt output expected forbidden))
         (total (+ (length expected) (length forbidden))))
    (condition-case err
        (if (and (fboundp 'gptel-agent--task) (> total 0))
            (gptel-agent--task
             (lambda (result)
               (condition-case nil
                   (funcall callback (gptel-skill--parse-grade-response result))
                 (error
                  (funcall callback (list :score 0 :total total :percentage 0.0
                                          :passed nil :details (format "Parse error: %s" result))))))
             "grader"
             (format "Grade test: %s" test-id)
             grading-prompt)
          (funcall callback (list :score 0 :total total :percentage 0.0
                                  :passed nil :details "No grader or no behaviors")))
      (error
       (funcall callback (list :score 0 :total total :percentage 0.0
                               :passed nil :details (format "Error: %s" (error-message-string err))))))))

(defun gptel-skill--make-grading-prompt (output expected forbidden)
  "Create grading prompt for OUTPUT against EXPECTED and FORBIDDEN behaviors."
  (format "Grade the following skill output.

OUTPUT:
%s

EXPECTED BEHAVIORS (should be present):
%s

FORBIDDEN BEHAVIORS (should NOT be present):
%s

For each behavior, respond with PASS or FAIL and a brief reason.
End with a summary line: SCORE: X/Y where X is passed behaviors, Y is total behaviors.

Format your response as:
EXPECTED:
1. [behavior]: PASS/FAIL - [reason]
...
FORBIDDEN:
1. [behavior]: PASS/FAIL - [reason]
...
SUMMARY: SCORE: X/Y"
          output
          (mapconcat (lambda (b) (format "- %s" b)) expected "\n")
          (mapconcat (lambda (b) (format "- %s" b)) forbidden "\n")))

(defun gptel-skill--parse-grade-response (response)
  "Parse LLM grading RESPONSE into plist."
  (let ((score 0)
        (total 0)
        (details (if (stringp response) response (format "%S" response))))
    (when (string-match "SCORE:\\s-*\\([0-9]+\\)/\\([0-9]+\\)" details)
      (setq score (string-to-number (match-string 1 details))
            total (string-to-number (match-string 2 details))))
    (list :score score
          :total (if (> total 0) total (max score 1))
          :percentage (if (> total 0) (* 100.0 (/ (float score) total)) 0.0)
          :passed (and (> total 0) (= score total))
          :details details)))

;;; Main Async Benchmark

(defun gptel-skill-benchmark-run-async (skill-name callback)
  "Run benchmark for SKILL-NAME asynchronously.
Calls CALLBACK with results list when complete."
  (let* ((run-id (format-time-string "%Y%m%d-%H%M%S"))
         (benchmark-file (expand-file-name (format "%s-benchmark.json" skill-name)
                                           gptel-skill-benchmark-dir))
         (tests (gptel-skill-load-tests skill-name))
         (results (make-vector (length tests) nil))
         (pending (length tests))
         (index 0))
    (setq gptel-skill-benchmark--cancelled nil)
    (if (null tests)
        (funcall callback nil)
      (gptel-skill-feedback-log 'benchmark-start
                                (format "Starting benchmark for %s with %d tests"
                                        skill-name (length tests)))
      (dolist (test tests)
        (let ((current-index index)
              (test-id (plist-get test :id))
              (prompt (plist-get test :prompt))
              (expected (plist-get test :expected_behaviors))
              (forbidden (plist-get test :forbidden_behaviors)))
          (setq index (1+ index))
          (gptel-skill-execute-test
           skill-name test-id prompt
           (lambda (output)
             (when gptel-skill-benchmark--cancelled
               (message "[Benchmark] Cancelled"))
             (if gptel-skill-benchmark--cancelled
                 (progn
                   (setq pending 0)
                   (funcall callback nil))
               (gptel-skill-grade-with-agent
                test-id output expected forbidden
                (lambda (grade)
                  (gptel-skill-feedback-log 'test-complete
                                            (format "Test %s: score=%.1f%%"
                                                    test-id (plist-get grade :percentage)))
                  (aset results current-index
                        (list :test-id test-id
                              :run-id run-id
                              :output (truncate-string-to-width output 500 nil nil "...")
                              :grade grade
                              :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S")))
                  (setq pending (1- pending))
                  (when (= pending 0)
                    (let ((final-results (append results nil)))
                      (gptel-skill-save-results benchmark-file final-results)
                      (gptel-skill-benchmark-save-historical skill-name final-results)
                      (gptel-skill-feedback-log 'benchmark-complete
                                                (format "Benchmark complete: %d tests" (length final-results)))
                      (funcall callback final-results)))))))))))))

;;; Cancel

(defun gptel-skill-benchmark-cancel ()
  "Cancel running benchmark."
  (interactive)
  (setq gptel-skill-benchmark--cancelled t)
  (message "Benchmark cancellation requested..."))

;;; Interactive Wrapper (with cancellation support)

(defun gptel-skill-benchmark-run (skill-name)
  "Run benchmark for SKILL-NAME.
Type C-g to cancel."
  (interactive
   (list (completing-read "Skill to benchmark (C-g to cancel): "
                          (directory-files gptel-skill-tests-dir nil "\\.json$"))))
  (setq skill-name (replace-regexp-in-string "\\.json$" "" skill-name))
  (let ((result nil)
        (done nil))
    (gptel-skill-benchmark-run-async
     skill-name
     (lambda (results)
       (setq result results done t)))
    (message "Running benchmark for %s... (C-g to cancel)" skill-name)
    (while (and (not done) (not gptel-skill-benchmark--cancelled))
      (when (input-pending-p)
        (let ((event (read-event nil nil 0.1)))
          (when (and event (eq event ?\C-g))
            (gptel-skill-benchmark-cancel)
            (keyboard-quit)))))
    (when (called-interactively-p 'interactive)
      (cond
       (gptel-skill-benchmark--cancelled
        (message "Benchmark cancelled"))
       (result
        (message "Benchmark complete: %d tests, avg: %.1f%%"
                 (length result)
                 (gptel-skill--average-score result)))
       (t
        (message "No tests found for %s" skill-name))))
    result))

;;; Historical Data

(defun gptel-skill-benchmark-save-historical (skill-name results)
  "Save RESULTS to historical file for SKILL-NAME."
  (let* ((history-file (expand-file-name (format "%s-history.json" skill-name)
                                         gptel-skill-benchmark-dir))
         (existing (when (file-exists-p history-file)
                     (gptel-skill-read-json history-file)))
         (run-id (format-time-string "%Y%m%d-%H%M%S"))
         (entry (list :run-id run-id
                      :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S")
                      :summary (gptel-skill--summarize-results results)
                      :total-tests (length results))))
    (let ((history (if (vectorp existing) (append existing nil) existing)))
      (gptel-skill-write-json (cons entry history) history-file)
      entry)))

(defun gptel-skill--summarize-results (results)
  "Create summary of RESULTS."
  (let ((total 0) (passed 0) (score-sum 0) (max-sum 0))
    (dolist (r results)
      (let* ((grade (gptel-skill--get-field r :grade))
             (s (or (gptel-skill--get-field grade :score) 0))
             (m (or (gptel-skill--get-field grade :total) 1)))
        (cl-incf total 1)
        (cl-incf score-sum s)
        (cl-incf max-sum m)
        (when (= s m) (cl-incf passed))))
    (list :total-tests total
          :passed-tests passed
          :average-score (if (> max-sum 0) (* 100 (/ (float score-sum) max-sum)) 0))))

(defun gptel-skill-benchmark-load-history (skill-name)
  "Load historical benchmark data for SKILL-NAME."
  (let ((history-file (expand-file-name (format "%s-history.json" skill-name)
                                        gptel-skill-benchmark-dir)))
    (when (file-exists-p history-file)
      (let ((data (gptel-skill-read-json history-file)))
        (if (vectorp data) (append data nil) data)))))

;;; Summary and Display

(defun gptel-skill--average-score (results)
  "Calculate average score percentage from RESULTS."
  (let ((total 0) (count 0))
    (dolist (r results)
      (let ((pct (plist-get (plist-get r :grade) :percentage)))
        (when (numberp pct)
          (cl-incf total pct)
          (cl-incf count))))
    (if (> count 0) (/ total count) 0.0)))

(defun gptel-skill-benchmark-summary (benchmark-file)
  "Generate summary from BENCHMARK-FILE."
  (when (file-exists-p benchmark-file)
    (let* ((data (gptel-skill-read-json benchmark-file))
           (data-list (if (vectorp data) (append data nil) data))
           (total-tests (length data-list))
           (passed-tests 0)
           (total-score 0)
           (max-possible-score 0))
      (dolist (result data-list)
        (let* ((grade (gptel-skill--get-field result :grade))
               (score (or (gptel-skill--get-field grade :score) 0))
               (total (or (gptel-skill--get-field grade :total) 1)))
          (cl-incf total-score score)
          (cl-incf max-possible-score total)
          (when (= score total)
            (cl-incf passed-tests))))
      (list :total-tests total-tests
            :passed-tests passed-tests
            :overall-score (if (> max-possible-score 0)
                               (* 100 (/ (float total-score) max-possible-score))
                             0)))))

(defun gptel-skill-benchmark-show-results (skill-name)
  "Show benchmark results for SKILL-NAME."
  (interactive
   (list (completing-read "Skill: "
                          (directory-files gptel-skill-tests-dir nil "\\.json$"))))
  (setq skill-name (replace-regexp-in-string "\\.json$" "" skill-name))
  (let* ((benchmark-file (expand-file-name (format "%s-benchmark.json" skill-name)
                                           gptel-skill-benchmark-dir))
         (results (when (file-exists-p benchmark-file)
                    (gptel-skill-read-json benchmark-file)))
         (summary (when results (gptel-skill-benchmark-summary benchmark-file))))
    (with-output-to-temp-buffer (format "*Benchmark: %s*" skill-name)
      (princ (format "=== Benchmark Results: %s ===\n\n" skill-name))
      (when summary
        (princ (format "Total Tests: %d\n" (plist-get summary :total-tests)))
        (princ (format "Passed: %d\n" (plist-get summary :passed-tests)))
        (princ (format "Overall Score: %.1f%%\n\n" (plist-get summary :overall-score))))
      (princ "--- Test Details ---\n\n")
      (dolist (result (if (vectorp results) (append results nil) results))
        (let* ((test-id (gptel-skill--get-field result :test-id))
               (grade (gptel-skill--get-field result :grade))
               (score (or (gptel-skill--get-field grade :score) 0))
               (total (or (gptel-skill--get-field grade :total) 1)))
          (princ (format "%s: %d/%d (%.0f%%)\n"
                         test-id score total
                         (if (> total 0) (* 100 (/ (float score) total)) 0))))))))

(defun gptel-skill-benchmark-trend (skill-name)
  "Show trend of benchmark scores over time for SKILL-NAME."
  (interactive
   (list (completing-read "Skill: "
                          (directory-files gptel-skill-tests-dir nil "\\.json$"))))
  (setq skill-name (replace-regexp-in-string "\\.json$" "" skill-name))
  (let* ((history (gptel-skill-benchmark-load-history skill-name)))
    (if (not history)
        (message "No historical data for %s" skill-name)
      (with-output-to-temp-buffer (format "*Benchmark Trend: %s*" skill-name)
        (princ (format "=== Benchmark Trend: %s ===\n\n" skill-name))
        (dolist (entry (nreverse history))
          (let* ((summary (gptel-skill--get-field entry :summary))
                 (timestamp (or (gptel-skill--get-field entry :timestamp) "unknown"))
                 (avg-score (or (gptel-skill--get-field summary :average-score) 0)))
            (princ (format "%s: %.1f%% (%d tests)\n"
                           timestamp
                           avg-score
                           (or (gptel-skill--get-field summary :total-tests) 0)))))))))

;;; Feedback Logging

(defun gptel-skill-feedback-log (stage feedback)
  "Log FEEDBACK for STAGE of benchmarking process."
  (let ((log-dir (file-name-as-directory gptel-skill-benchmark-dir)))
    (unless (file-exists-p log-dir)
      (make-directory log-dir t))
    (let ((log-entry (format "[%s] %s: %s\n"
                             (format-time-string "%Y-%m-%d %H:%M:%S")
                             stage
                             feedback)))
      (with-temp-buffer
        (insert log-entry)
        (write-region (point-min) (point-max) (concat log-dir "feedback.log") t)))))

;;; Save Results

(defun gptel-skill-save-results (benchmark-file results)
  "Save RESULTS to BENCHMARK-FILE."
  (let ((dir (file-name-directory benchmark-file)))
    (unless (file-exists-p dir)
      (make-directory dir t)))
  (with-temp-file benchmark-file
    (insert (json-encode (gptel-skill--to-json-format results)))))

;;; Legacy Compatibility

(defun gptel-skill-check-assertion (output assertion)
  "Check if OUTPUT satisfies ASSERTION using simple pattern matching.
DEPRECATED: Use grader agent instead."
  (string-match-p assertion output))

(provide 'gptel-skill-benchmark)

;;; gptel-skill-benchmark.el ends here