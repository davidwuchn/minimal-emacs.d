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
;; Uses existing agents (grader, analyzer, comparator) via RunAgent.

;;; Code:

(require 'json)
(require 'cl-lib)
(require 'gptel-skill-utils)

(defvar gptel-skill-benchmark-dir "./benchmarks/"
  "Directory where benchmark results are stored.")

(defvar gptel-skill-temp-dir nil
  "Temp directory for benchmark run.")

;;; Test Loading

(defun gptel-skill-load-tests (skill-name)
  "Load test definitions for SKILL-NAME.
Returns list of test plists with :id, :name, :prompt, :expected_behaviors, :forbidden_behaviors."
  (let ((test-file (format "./assistant/evals/skill-tests/%s.json" skill-name)))
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

;;; Skill Execution via RunAgent

(defun gptel-skill-execute-test (skill test-id prompt work-dir)
  "Execute TEST-ID for SKILL with PROMPT using RunAgent.
WORK-DIR is the temp directory for outputs.
Returns the skill's output string."
  (gptel-skill-feedback-log 'execute (format "Executing test %s for skill %s" test-id skill))
  (let ((output-file (expand-file-name "outputs/output.txt" work-dir)))
    (make-directory (file-name-directory output-file) t)
    (if (fboundp 'gptel-agent--run-agent)
        (let* ((result (condition-case err
                           (gptel-agent--run-agent
                            skill
                            (format "Benchmark test: %s" test-id)
                            prompt
                            nil nil nil)
                         (error (format "Error executing skill: %s" (error-message-string err))))))
          (let ((output (if (stringp result) result (format "%S" result))))
            (with-temp-file output-file
              (insert output))
            output))
      (let ((output (format "[MOCK] Skill %s executed with prompt: %s"
                            skill (truncate-string-to-width prompt 100 nil nil "..."))))
        (with-temp-file output-file
          (insert output))
        output))))

;;; Grading via RunAgent (uses grader agent)

(defun gptel-skill-grade-with-agent (test-id work-dir expected forbidden)
  "Grade test TEST-ID using grader agent.
WORK-DIR contains outputs/ directory.
EXPECTED and FORBIDDEN are behavior lists.
Returns plist with :score, :total, :percentage, :passed, :details."
  (let* ((eval-file (expand-file-name "eval_metadata.json" work-dir))
         (grading-file (expand-file-name "grading.json" work-dir)))
    (gptel-skill--write-eval-metadata eval-file test-id expected forbidden)
    (if (fboundp 'gptel-agent--run-agent)
        (let ((result (condition-case err
                          (gptel-agent--run-agent
                           "grader"
                           (format "Grade test: %s" test-id)
                           (format "Grade the output in %s against eval_metadata.json"
                                   work-dir)
                           (list eval-file (expand-file-name "outputs/" work-dir))
                           nil nil)
                        (error (format "Grading error: %s" (error-message-string err))))))
          (gptel-skill--parse-grading-result grading-file result))
      (gptel-skill--simple-grade expected forbidden))))

(defun gptel-skill--write-eval-metadata (file test-id expected forbidden)
  "Write eval metadata to FILE for TEST-ID with EXPECTED and FORBIDDEN behaviors."
  (let ((assertions (append
                     (mapcar (lambda (b) `((name . ,b) (type . "llm") (criteria . "should be present")))
                             expected)
                     (mapcar (lambda (b) `((name . ,b) (type . "llm") (criteria . "should NOT be present")))
                             forbidden))))
    (with-temp-file file
      (insert (json-encode `((eval_id . ,test-id)
                             (assertions . ,assertions)))))))

(defun gptel-skill--parse-grading-result (grading-file fallback)
  "Parse grading result from GRADING-FILE or use FALLBACK string."
  (if (file-exists-p grading-file)
      (let* ((data (gptel-skill-read-json grading-file))
             (summary (cdr (assq 'summary data)))
             (passed (cdr (assq 'passed summary)))
             (total (cdr (assq 'total summary))))
        (list :score passed
              :total total
              :percentage (if (> total 0) (* 100.0 (/ (float passed) total)) 0.0)
              :passed (= passed total)
              :details (format "Graded from %s" grading-file)))
    (gptel-skill--parse-grade-response fallback)))

(defun gptel-skill--simple-grade (expected forbidden)
  "Simple fallback grader when RunAgent unavailable.
Returns approximate grade plist."
  (list :score 0
        :total (+ (length expected) (length forbidden))
        :percentage 0.0
        :passed nil
        :details "RunAgent not available"))

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

;;; Main Benchmark Run

(defun gptel-skill-benchmark-run (skill-name &optional _args)
  "Run benchmark for SKILL-NAME with optional ARGS.
Uses RunAgent to execute skill and grade outputs.
When called interactively, prompts for SKILL-NAME."
  (interactive
   (list (completing-read "Skill to benchmark: "
                          (directory-files "./assistant/evals/skill-tests/" nil "\\.json$"))))
  (setq skill-name (replace-regexp-in-string "\\.json$" "" skill-name))
  (let* ((run-id (format-time-string "%Y%m%d-%H%M%S"))
         (work-root (make-temp-file "gptel-skill-benchmark" t))
         (benchmark-file (format "%s%s-benchmark.json" gptel-skill-benchmark-dir skill-name))
         (tests (gptel-skill-load-tests skill-name))
         (results '()))
    (gptel-skill-feedback-log 'benchmark-start
                              (format "Starting benchmark for %s with %d tests"
                                      skill-name (length tests)))
    (unwind-protect
        (progn
          (dolist (test tests)
            (let* ((test-id (plist-get test :id))
                   (prompt (plist-get test :prompt))
                   (expected (plist-get test :expected_behaviors))
                   (forbidden (plist-get test :forbidden_behaviors))
                   (work-dir (expand-file-name test-id work-root)))
              (make-directory work-dir t)
              (let* ((output (gptel-skill-execute-test skill-name test-id prompt work-dir))
                     (grade (gptel-skill-grade-with-agent test-id work-dir expected forbidden)))
                (gptel-skill-feedback-log 'test-complete
                                          (format "Test %s: score=%.1f%%"
                                                  test-id (plist-get grade :percentage)))
                (push (list :test-id test-id
                            :run-id run-id
                            :output (truncate-string-to-width output 500 nil nil "...")
                            :grade grade
                            :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S"))
                      results))))
          (let ((final-results (nreverse results)))
            (gptel-skill-save-results benchmark-file final-results)
            (gptel-skill-benchmark-save-historical skill-name final-results)
            (gptel-skill-feedback-log 'benchmark-complete
                                      (format "Benchmark complete: %d tests, avg: %.1f%%"
                                              (length final-results)
                                              (gptel-skill--average-score final-results)))
            (when (called-interactively-p 'interactive)
              (message "Benchmark complete: %d tests, avg score: %.1f%%"
                       (length final-results)
                       (gptel-skill--average-score final-results)))
            final-results))
      (delete-directory work-root t))))

(defun gptel-skill--average-score (results)
  "Calculate average score percentage from RESULTS."
  (let ((total 0) (count 0))
    (dolist (r results)
      (let ((pct (plist-get (plist-get r :grade) :percentage)))
        (when (numberp pct)
          (cl-incf total pct)
          (cl-incf count))))
    (if (> count 0) (/ total count) 0.0)))

;;; Analysis via RunAgent (uses analyzer agent)

(defun gptel-skill-analyze-with-agent (skill-name)
  "Analyze benchmark results for SKILL-NAME using analyzer agent.
Returns analysis plist with findings and recommendations."
  (interactive
   (list (completing-read "Skill to analyze: "
                          (directory-files "./assistant/evals/skill-tests/" nil "\\.json$"))))
  (setq skill-name (replace-regexp-in-string "\\.json$" "" skill-name))
  (let* ((benchmark-file (format "%s%s-benchmark.json" gptel-skill-benchmark-dir skill-name)))
    (if (not (file-exists-p benchmark-file))
        (error "No benchmark file found for %s" skill-name)
      (if (fboundp 'gptel-agent--run-agent)
          (let* ((result (gptel-agent--run-agent
                          "analyzer"
                          (format "Analyze benchmark: %s" skill-name)
                          (format "Analyze the benchmark results in %s" benchmark-file)
                          (list benchmark-file)
                          nil nil)))
            (when (called-interactively-p 'interactive)
              (message "Analysis complete for %s" skill-name))
            result)
        (gptel-skill-analyze-results benchmark-file)))))

;;; Summary and Display

(defun gptel-skill-benchmark-summary (benchmark-file)
  "Generate summary from BENCHMARK-FILE.
Handles both plist and alist formats from JSON parsing."
  (when (file-exists-p benchmark-file)
    (let* ((data (gptel-skill-read-json benchmark-file))
           (data-list (if (vectorp data) (append data nil) data))
           (total-tests (length data-list))
           (passed-tests 0)
           (total-score 0)
           (max-possible-score 0))
      (dolist (result data-list)
        (let* ((grade (gptel-skill--get-field result :grade))
               (score (or (gptel-skill--get-field grade :score)
                          (cdr (assq 'score grade)) 0))
               (total (or (gptel-skill--get-field grade :total)
                          (cdr (assq 'total grade)) 1)))
          (cl-incf total-score score)
          (cl-incf max-possible-score total)
          (when (= score total)
            (cl-incf passed-tests))))
      (list :total-tests total-tests
            :passed-tests passed-tests
            :overall-score (if (> max-possible-score 0)
                               (* 100 (/ (float total-score) max-possible-score))
                             0)))))

(defun gptel-skill--get-field (obj field)
  "Get FIELD from OBJ, handling both plist and alist formats."
  (or (plist-get obj field)
      (cdr (assq (intern (substring (symbol-name field) 1)) obj))))

(defun gptel-skill-benchmark-show-results (skill-name)
  "Show benchmark results for SKILL-NAME."
  (interactive
   (list (completing-read "Skill: "
                          (directory-files "./assistant/evals/skill-tests/" nil "\\.json$"))))
  (setq skill-name (replace-regexp-in-string "\\.json$" "" skill-name))
  (let* ((benchmark-file (format "%s%s-benchmark.json" gptel-skill-benchmark-dir skill-name))
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
      (dolist (result results)
        (let* ((test-id (plist-get result :test-id))
               (grade (plist-get result :grade))
               (score (or (plist-get grade :score) 0))
               (total (or (plist-get grade :total) 1)))
          (princ (format "%s: %d/%d (%.0f%%)\n"
                         test-id score total
                         (if (> total 0) (* 100 (/ (float score) total)) 0))))))))

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

;;; Historical Data Storage

(defun gptel-skill-benchmark-save-historical (skill-name results)
  "Save RESULTS to historical file for SKILL-NAME.
Enables trend analysis across multiple benchmark runs."
  (let* ((history-file (format "%s%s-history.json" gptel-skill-benchmark-dir skill-name))
         (existing (when (file-exists-p history-file)
                     (gptel-skill-read-json history-file)))
         (run-id (format-time-string "%Y%m%d-%H%M%S"))
         (entry (list :run-id run-id
                      :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S")
                      :summary (gptel-skill--summarize-results results)
                      :total-tests (length results))))
    (let ((history (if (vectorp existing)
                       (append existing nil)
                     existing)))
      (gptel-skill-write-json (cons entry history) history-file)
      entry)))

(defun gptel-skill--summarize-results (results)
  "Create summary of RESULTS for historical storage."
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
  (let ((history-file (format "%s%s-history.json" gptel-skill-benchmark-dir skill-name)))
    (when (file-exists-p history-file)
      (let ((data (gptel-skill-read-json history-file)))
        (if (vectorp data) (append data nil) data)))))

(defun gptel-skill-benchmark-trend (skill-name)
  "Show trend of benchmark scores over time for SKILL-NAME."
  (interactive
   (list (completing-read "Skill: "
                          (directory-files "./assistant/evals/skill-tests/" nil "\\.json$"))))
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
DEPRECATED: Use grader agent via RunAgent instead."
  (string-match-p assertion output))

(provide 'gptel-skill-benchmark)

;;; gptel-skill-benchmark.el ends here