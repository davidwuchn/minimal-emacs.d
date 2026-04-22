;;; gptel-benchmark-subagent.el --- Unified subagent dispatch for benchmarking -*- lexical-binding: t; -*-

;; Copyright (C) 2025 David Wu
;; Author: David Wu
;; Version: 1.0.0
;; Keywords: ai, benchmark, subagent

;;; Commentary:

;; Unified interface for calling subagents (grader, analyzer, executor, reviewer)
;; shared between skill benchmark, workflow benchmark, and continuous learning.
;;
;; Subagent types:
;; - grader: Grade outputs against expected/forbidden behaviors
;; - analyzer: Analyze results and find patterns
;; - executor: Execute changes to files
;; - reviewer: Review code quality
;; - explorer: Explore codebase
;; - researcher: Research and synthesize information
;;
;; Usage:
;;   (gptel-benchmark-grade output expected forbidden callback)
;;   (gptel-benchmark-analyze data callback)
;;   (gptel-benchmark-improve target changes callback)

;;; Code:

(require 'cl-lib)
(require 'json)
(eval-when-compile
  (require 'gptel-benchmark-core nil t))

;; Ensure tools agent is loaded for workflow functions
(require 'gptel-tools-agent nil t)

(declare-function gptel-benchmark-summarize-results "gptel-benchmark-core")
(declare-function gptel-benchmark-load-history "gptel-benchmark-core")
(defvar gptel-benchmark-default-dir)
(defvar my/gptel-agent-task-timeout)

(declare-function gptel-agent--task "gptel-tools-agent")
(declare-function gptel-auto-workflow--read-file-contents "gptel-tools-agent")
(declare-function my/gptel--agent-task-with-timeout "gptel-tools-agent"
                  (callback agent-type description prompt
                            &optional files include-history include-diff))

;;; Customization

(defgroup gptel-benchmark-subagent nil
  "Subagent dispatch for benchmarking."
  :group 'gptel)

(defcustom gptel-benchmark-subagent-timeout 60
  "Default timeout for subagent calls in seconds."
  :type 'integer
  :group 'gptel-benchmark-subagent)

(defcustom gptel-benchmark-use-subagents t
  "Whether to use subagents for evaluation.
When nil, falls back to local evaluation."
  :type 'boolean
  :group 'gptel-benchmark-subagent)

(defvar gptel-benchmark--subagent-files nil
  "Dynamic file context for the next benchmark subagent dispatch.

Callers may bind this to a list of files that should be included in the
subagent context for a single dispatch.")

;;; Subagent Registry

(defconst gptel-benchmark-subagent-types
  '((grader
     :description "Grade outputs against criteria"
     :output-format "JSON with :score, :total, :passed, :details"
     :prompt-template gptel-benchmark--grader-prompt)
    (analyzer
     :description "Analyze results and find patterns"
     :output-format "JSON with :patterns, :issues, :recommendations"
     :prompt-template gptel-benchmark--analyzer-prompt)
    (executor
     :description "Execute changes to files"
     :output-format "Summary of changes made"
     :prompt-template gptel-benchmark--executor-prompt)
    (reviewer
     :description "Review code quality"
     :output-format "Review comments and suggestions"
     :prompt-template gptel-benchmark--reviewer-prompt)
    (explorer
     :description "Explore codebase and gather information"
     :output-format "Findings summary"
     :prompt-template gptel-benchmark--explorer-prompt))
  "Registry of available subagent types with their configurations.")

;;; Core Dispatch

(defun gptel-benchmark-call-subagent (type description prompt callback &optional timeout)
  "Call subagent of TYPE with DESCRIPTION and PROMPT.
Calls CALLBACK with result when complete.
TIMEOUT overrides the default benchmark subagent timeout."
  (if (and gptel-benchmark-use-subagents
           (fboundp 'gptel-agent--task))
      (let ((agent-type (symbol-name type))
            (files gptel-benchmark--subagent-files))
        (if (fboundp 'my/gptel--agent-task-with-timeout)
            (let ((my/gptel-agent-task-timeout
                   (or timeout gptel-benchmark-subagent-timeout)))
              (my/gptel--agent-task-with-timeout
               callback
               agent-type
               description
               prompt
               files))
          (gptel-agent--task
           callback
           agent-type
           description
           prompt)))
    (funcall callback (format "[MOCK] %s: %s"
                              type
                              (truncate-string-to-width prompt 100 nil nil "...")))))

(defun gptel-benchmark-call-subagent-sync (type description prompt &optional timeout)
  "Call subagent synchronously, returning result.
TYPE, DESCRIPTION, PROMPT same as async version.
TIMEOUT overrides default."
  (let ((result nil)
        (done nil))
    (gptel-benchmark-call-subagent
     type description prompt
     (lambda (r)
       (setq result r done t))
     timeout)
    (while (not done)
      (sit-for 0.1))
    result))

;;; Grader Subagent

(defun gptel-benchmark-grade (output expected forbidden callback &optional timeout)
  "Grade OUTPUT against EXPECTED and FORBIDDEN behaviors.
Calls CALLBACK with grade plist: (:score :total :percentage :passed :details).
Optional TIMEOUT overrides default subagent timeout.
Uses grader subagent - no local fallback (fail if subagent unavailable)."
  (let ((grading-prompt (gptel-benchmark--make-grading-prompt output expected forbidden))
        (total (+ (length expected) (length forbidden))))
    (if (and gptel-benchmark-use-subagents
             (fboundp 'gptel-agent--task)
             (> total 0))
        (gptel-benchmark-call-subagent
         'grader
         "Grade output"
         grading-prompt
         (lambda (result)
           (funcall callback (gptel-benchmark--parse-grade-response result expected forbidden)))
         timeout)
      ;; No local fallback - fail the grade
      (funcall callback (list :score 0 
                              :total total
                              :percentage 0.0
                              :passed nil
                              :details "Grader subagent unavailable")))))

(defun gptel-benchmark--make-grading-prompt (output expected forbidden)
  "Create grading prompt for OUTPUT against EXPECTED and FORBIDDEN."
  (format "Grade the following output.

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
          (mapconcat (lambda (b) (concat "- " b)) expected "\n")
          (mapconcat (lambda (b) (concat "- " b)) forbidden "\n")))

(defun gptel-benchmark--parse-grade-response (response expected forbidden)
  "Parse LLM grading RESPONSE into plist.
Handles both SCORE: X/Y format and JSON format.
Passes if score >= 80% of total (not requiring perfect score)."
  (let ((score 0)
        (total (+ (length expected) (length forbidden)))
        (details (if (stringp response) response (format "%S" response))))
    ;; Try SCORE: X/Y format first
    (if (string-match "SCORE:\\s-*\\([0-9]+\\)/\\([0-9]+\\)" details)
        (setq score (string-to-number (match-string 1 details))
              total (string-to-number (match-string 2 details)))
      ;; Count "passed": true in results
      (with-temp-buffer
        (insert details)
        (goto-char (point-min))
        (while (re-search-forward "\"passed\"\\s-*:\\s-*true" nil t)
          (cl-incf score)))
      ;; Try to get total from summary
      (when (string-match "\"total\"\\s-*:\\s-*\\([0-9]+\\)" details)
        (setq total (string-to-number (match-string 1 details)))))
    (let* ((percentage (if (> total 0) (* 100.0 (/ (float score) total)) 0.0))
           ;; Pass if >= 80% (not requiring perfect score)
           (passed (and (> total 0) (>= percentage 80.0))))
      (list :score score
            :total (if (> total 0) total (max score 1))
            :percentage percentage
            :passed passed
            :details details))))

;;; Code Quality Scoring

(defun gptel-benchmark--code-quality-score (code)
  "Score CODE quality based on multiple metrics.
Returns a score from 0.0 to 1.0.

Metrics (weighted):
- Docstring coverage (20%): % of functions with docstrings
- Positive patterns (30%): error handling, naming, predicates
- Function length (25%): shorter functions score higher
- Cyclomatic complexity (25%): fewer conditionals score higher

Perfect score (1.0) = all functions have docstrings, proper error handling,
good naming conventions, all under 20 lines, simple control flow."
  (let* ((func-data (gptel-benchmark--extract-function-data code))
         (func-count (length func-data)))
    (if (= func-count 0)
        0.5
      (let* ((docstring-score (gptel-benchmark--docstring-coverage func-data))
             (positive-score (gptel-benchmark--positive-patterns-score code func-data))
             (length-score (gptel-benchmark--function-length-score func-data))
             (complexity-score (gptel-benchmark--complexity-score code func-count)))
        (+ (* 0.20 docstring-score)
           (* 0.30 positive-score)
           (* 0.25 length-score)
           (* 0.25 complexity-score))))))

(defun gptel-benchmark--extract-function-data (code)
  "Extract function data from CODE.
Returns list of plists: (:name :start :end :has-docstring :length)."
  (with-temp-buffer
    (insert code)
    (goto-char (point-min))
    (let ((results '()))
      (while (re-search-forward "^(defun\\s-+\\(\\S-+\\)\\s-*" nil t)
        (let* ((name (match-string 1))
               (start (match-beginning 0))
               (has-docstring (save-excursion
                                (forward-sexp)  ; skip args
                                (skip-chars-forward " \t\n")
                                (eq (char-after) ?\")))
               (func-end (save-excursion
                           (goto-char start)
                           (forward-list)
                           (point)))
               (length (count-lines start func-end)))
          (push (list :name name
                      :start start
                      :end func-end
                      :has-docstring has-docstring
                      :length length)
                results)))
      (nreverse results))))

(defun gptel-benchmark--docstring-coverage (func-data)
  "Calculate docstring coverage from FUNC-DATA.
Returns 0.0-1.0."
  (if (null func-data)
      1.0
    (let ((with-doc (cl-count-if (lambda (f) (plist-get f :has-docstring)) func-data)))
      (/ (float with-doc) (length func-data)))))

(defun gptel-benchmark--function-length-score (func-data)
  "Score function lengths from FUNC-DATA.
Shorter functions score higher.
- ≤10 lines: 1.0
- ≤20 lines: 0.8
- ≤30 lines: 0.6
- ≤50 lines: 0.4
- >50 lines: 0.2"
  (if (null func-data)
      0.5
    (let ((total-score 0.0))
      (dolist (f func-data)
        (let ((len (plist-get f :length)))
          (cl-incf total-score
                   (cond
                    ((<= len 10) 1.0)
                    ((<= len 20) 0.8)
                    ((<= len 30) 0.6)
                    ((<= len 50) 0.4)
                    (t 0.2)))))
      (/ total-score (length func-data)))))

(defun gptel-benchmark--complexity-score (code func-count)
  "Estimate cyclomatic complexity from CODE.
Counts conditionals (if, cond, when, unless, pcase, etc.).
Returns 0.0-1.0 where 1.0 = simple code (≤2 branches per function avg)."
  (if (= func-count 0)
      0.5
    (let* ((conditionals (with-temp-buffer
                           (insert code)
                           (goto-char (point-min))
                           (let ((count 0))
                             (while (re-search-forward
                                     "(\\(if\\|cond\\|when\\|unless\\|pcase\\|cl-case\\)\\>" nil t)
                               (cl-incf count))
                             count)))
           (avg-complexity (/ (float conditionals) func-count)))
      (cond
       ((<= avg-complexity 1.0) 1.0)
       ((<= avg-complexity 2.0) 0.9)
       ((<= avg-complexity 3.0) 0.7)
       ((<= avg-complexity 5.0) 0.5)
       ((<= avg-complexity 8.0) 0.3)
       (t 0.1)))))

(defun gptel-benchmark--positive-patterns-score (code &optional func-data)
  "Score positive patterns in CODE.
Returns 0.0-1.0 where higher scores indicate better practices.

Positive patterns (weighted):
- Error handling (40%): condition-case, user-error, error, signal
- Naming conventions (30%): -- for internal, no my- prefix, proper predicates
- Standard predicates (30%): null, stringp, listp, etc.

This rewards code that follows Emacs Lisp best practices.
FUNC-DATA may be passed to avoid redundant extraction."
  (let* ((error-handling-terms '("condition-case" "user-error" "error" "signal"
                                 "cl-assert" "cl-check-type" "assert"))
         (bad-naming '("my-" "foo-" "bar-" "baz-"))
         (good-predicates '("null" "stringp" "listp" "numberp" "integerp"
                            "symbolp" "functionp" "boundp" "fboundp" "keywordp"
                            "arrayp" "sequencep" "consp" "atom" "listp"))
         (error-score 0.0)
         (naming-score 1.0)
         (predicate-score 0.0)
         (func-count (max 1 (length (or func-data
                                        (gptel-benchmark--extract-function-data code))))))
    (with-temp-buffer
      (insert code)
      (goto-char (point-min))
      (when (re-search-forward (regexp-opt error-handling-terms) nil t)
        (setq error-score 1.0))
      (goto-char (point-min))
      (while (re-search-forward (regexp-opt bad-naming) nil t)
        (setq naming-score (max 0.0 (- naming-score 0.3))))
      (goto-char (point-min))
      (let ((pred-count 0))
        (while (re-search-forward (regexp-opt good-predicates) nil t)
          (cl-incf pred-count))
        (setq predicate-score (min 1.0 (/ (float pred-count) func-count)))))
    (+ (* 0.40 error-score)
       (* 0.30 naming-score)
       (* 0.30 predicate-score))))

;;; LLM Quality Detection

(defcustom gptel-benchmark-llm-degradation-keywords
  '("I apologize" "I'm sorry" "I understand your concern"
    "As an AI" "I cannot" "I'm unable to"
    "Let me try again" "Let me rephrase" "I apologize for the confusion")
  "Keywords indicating LLM degradation (repetition, apology loops)."
  :type '(repeat string)
  :group 'gptel-benchmark-subagent)

(defun gptel-benchmark--detect-llm-degradation (response expected-keywords)
  "Detect if RESPONSE shows LLM degradation (hallucination, off-topic, lost context).
EXPECTED-KEYWORDS: should be present for on-topic response.
Returns plist: (:degraded-p :reason :score)."
  (let* ((expected-matches 0)
         (forbidden-matches 0)
         (reasons '())
         (forbidden gptel-benchmark-llm-degradation-keywords))
    (dolist (kw expected-keywords)
      (when (string-match-p (regexp-quote kw) response)
        (cl-incf expected-matches)))
    (dolist (kw forbidden)
      (when (string-match-p (regexp-quote kw) response)
        (cl-incf forbidden-matches)
        (push kw reasons)))
    (let* ((expected-score (/ (float expected-matches) (max 1 (length expected-keywords))))
           (degraded-p (or (> forbidden-matches 0)
                           (and expected-keywords (= expected-matches 0))))
           (score (cond
                   ((> forbidden-matches 0)
                    (- 1.0 (/ (float forbidden-matches) (max 1 (length forbidden)))))
                   ((= expected-matches 0) 0.0)
                   (t expected-score))))
      (list :degraded-p degraded-p
            :reason (if (> forbidden-matches 0)
                        (string-join (nreverse reasons) ", ")
                      (if (= expected-matches 0) "no expected keywords" ""))
            :score score))))

;;; Analyzer Subagent

(defun gptel-benchmark-analyze (data description callback)
  "Analyze DATA with optional DESCRIPTION.
Calls CALLBACK with analysis plist: (:patterns :issues :recommendations).
Uses analyzer subagent if available."
  (let ((analysis-prompt (format "Analyze the following benchmark data.

DESCRIPTION: %s

DATA:
%s

Generate analysis with:
1. Patterns detected
2. Issues identified  
3. Recommendations for improvement

Output as JSON:
{
  \"patterns\": [{\"type\": \"...\", \"description\": \"...\"}],
  \"issues\": [{\"type\": \"...\", \"count\": N, \"percentage\": P}],
  \"recommendations\": [\"...\", ...]
}"
                                 (or description "Benchmark results")
                                 (format "%S" data))))
    (gptel-benchmark-call-subagent
     'analyzer
     (format "Analyze: %s" (or description "benchmark data"))
     analysis-prompt
     (lambda (result)
       (funcall callback (gptel-benchmark--parse-analysis-response result))))))

(defun gptel-benchmark--parse-json-response (response &optional fallback)
  "Parse RESPONSE as JSON, returning FALLBACK on error.
RESPONSE can be string or any type (converted to string if needed).
FALLBACK defaults to nil if not provided."
  (condition-case nil
      (json-read-from-string
       (if (stringp response) response (format "%S" response)))
    (error (or fallback nil))))

(defun gptel-benchmark--parse-analysis-response (response)
  "Parse analyzer RESPONSE into plist."
  (let ((parsed (gptel-benchmark--parse-json-response response)))
    (if (and parsed (listp parsed))
        (list :patterns (cdr (assq 'patterns parsed))
              :issues (cdr (assq 'issues parsed))
              :recommendations (cdr (assq 'recommendations parsed)))
      (list :patterns nil
            :issues nil
            :recommendations nil
            :raw response))))

;;; Executor Subagent

(defun gptel-benchmark-execute (target changes callback)
  "Execute CHANGES to TARGET (file or directory).
Calls CALLBACK with result summary.
Uses executor subagent if available."
  (let ((exec-prompt (format "Apply the following changes to: %s

CHANGES:
%s

Execute these changes and report the results."
                             target
                             (format "%S" changes))))
    (gptel-benchmark-call-subagent
     'executor
     (format "Execute changes to %s" target)
     exec-prompt
     callback)))

;;; Reviewer Subagent

(defun gptel-benchmark-review (content callback)
  "Review CONTENT (code or text).
Calls CALLBACK with review results.
Uses reviewer subagent if available."
  (gptel-benchmark-call-subagent
   'reviewer
   "Review content"
   (format "Review the following content and provide feedback:

%s

Focus on: correctness, clarity, best practices, potential issues."
           (if (stringp content) content (format "%S" content)))
   callback))

;;; Explorer Subagent

(defun gptel-benchmark-explore (query scope callback)
  "Explore codebase with QUERY in SCOPE.
Calls CALLBACK with findings.
Uses explorer subagent if available."
  (gptel-benchmark-call-subagent
   'explorer
   (format "Explore: %s" query)
   (format "Explore the codebase to answer: %s

Scope: %s

Return findings with specific file locations and code references."
           query
           (or scope "entire codebase"))
   callback))

;;; Batch Operations

(defun gptel-benchmark-grade-batch (items callback)
  "Grade multiple ITEMS in batch.
ITEMS is list of (output expected forbidden) triples.
Calls CALLBACK with list of grade results."
  (let ((results (make-vector (length items) nil))
        (pending (length items))
        (index 0))
    (dolist (item items)
      (let ((current-index index)
            (output (nth 0 item))
            (expected (nth 1 item))
            (forbidden (nth 2 item)))
        (setq index (1+ index))
        (gptel-benchmark-grade
         output expected forbidden
         (lambda (grade)
           (aset results current-index grade)
           (setq pending (1- pending))
           (when (= pending 0)
             (funcall callback (append results nil)))))))))

;;; Improvement Suggestion Generator

(defun gptel-benchmark-suggest-improvements (analysis callback)
  "Generate improvement suggestions based on ANALYSIS.
Uses analyzer subagent to generate actionable suggestions."
  (let ((prompt (format "Based on the following analysis, generate specific improvement suggestions.

ANALYSIS:
%s

Generate:
1. test_improvements: Specific improvements to test cases
2. threshold_changes: Suggested changes to success criteria thresholds
3. new_tests: New test cases to add
4. prompt_suggestions: Improvements to prompts/instructions

Output as JSON."
                        (format "%S" analysis))))
    (gptel-benchmark-call-subagent
     'analyzer
     "Generate improvement suggestions"
     prompt
     (lambda (result)
       (funcall callback
                (gptel-benchmark--parse-json-response result '(:raw result)))))))

;;; Comparator Subagent (A/B Analysis)

(defun gptel-benchmark-compare (a b description callback)
  "Compare two results A and B with DESCRIPTION.
Calls CALLBACK with comparison plist: (:winner :improvement :analysis).
Uses comparator logic to determine which is better and why."
  (let ((compare-prompt (format "Compare these two benchmark results and determine which is better.

DESCRIPTION: %s

RESULT A:
%s

RESULT B:
%s

Analyze and output JSON:
{
  \"winner\": \"A\" | \"B\" | \"tie\",
  \"improvement\": {\"score\": X, \"percentage\": Y},
  \"analysis\": {
    \"strengths_a\": [...],
    \"strengths_b\": [...],
    \"weaknesses_a\": [...],
    \"weaknesses_b\": [...]
  },
  \"recommendation\": \"...\"
}"
                                (or description "Benchmark comparison")
                                (format "%S" a)
                                (format "%S" b))))
    (gptel-benchmark-call-subagent
     'comparator
     (format "Compare: %s" (or description "A vs B"))
     compare-prompt
     (lambda (result)
       (funcall callback (gptel-benchmark--parse-comparison-response result))))))

(defun gptel-benchmark--parse-comparison-response (response)
  "Parse comparator RESPONSE into plist."
  (let* ((parsed (gptel-benchmark--parse-json-response response)))
    (if (listp parsed)
        (list :winner (cdr (assq 'winner parsed))
              :improvement (cdr (assq 'improvement parsed))
              :analysis (cdr (assq 'analysis parsed))
              :recommendation (cdr (assq 'recommendation parsed)))
      (list :winner nil
            :improvement nil
            :analysis nil
            :recommendation nil))))

(defun gptel-benchmark-ab-test (name-a results-a name-b results-b callback)
  "Run A/B test comparing RESULTS-A (name NAME-A) vs RESULTS-B (name NAME-B).
Calls CALLBACK with comprehensive comparison report."
  (let* ((summary-a (gptel-benchmark-summarize-results results-a))
         (summary-b (gptel-benchmark-summarize-results results-b))
         (score-a (plist-get summary-a :avg-overall))
         (score-b (plist-get summary-b :avg-overall)))
    (gptel-benchmark-compare
     summary-a summary-b
     (format "%s vs %s" name-a name-b)
     (lambda (comparison)
       (let ((report (list :name-a name-a
                           :name-b name-b
                           :score-a score-a
                           :score-b score-b
                           :summary-a summary-a
                           :summary-b summary-b
                           :comparison comparison
                           :statistical (gptel-benchmark--statistical-significance
                                         results-a results-b))))
         (funcall callback report))))))

(defun gptel-benchmark--extract-overall-scores (results)
  "Extract overall scores from RESULTS list.
Handles both plist and cons cell formats.
Filters out nil values to prevent arithmetic errors."
  (delq nil (mapcar (lambda (r)
                      (plist-get (or (cdr r) (plist-get r :scores)) :overall-score))
                    results)))

(defun gptel-benchmark--statistical-significance (results-a results-b)
  "Calculate basic statistical significance between RESULTS-A and RESULTS-B.
Returns plist with :significant and :confidence."
  (let* ((scores-a (gptel-benchmark--extract-overall-scores results-a))
         (scores-b (gptel-benchmark--extract-overall-scores results-b))
         (mean-a (if (and scores-a (> (length scores-a) 0))
                     (/ (apply #'+ scores-a) (length scores-a)) 0))
         (mean-b (if (and scores-b (> (length scores-b) 0))
                     (/ (apply #'+ scores-b) (length scores-b)) 0))
         (diff (abs (- mean-a mean-b))))
    (list :difference diff
          :significant (> diff 0.1)
          :confidence (if (> diff 0.2) "high"
                        (if (> diff 0.1) "medium" "low")))))

(defun gptel-benchmark-compare-versions (name version-a version-b &optional results-dir)
  "Compare VERSION-A and VERSION-B of NAME from RESULTS-DIR.
Uses historical data for comparison."
  (let* ((dir (or results-dir gptel-benchmark-default-dir))
         (history (gptel-benchmark-load-history name dir)))
    (when history
      (let* ((entry-a (cl-find-if (lambda (h)
                                    (string= (plist-get h :run-id) version-a))
                                  history))
             (entry-b (cl-find-if (lambda (h)
                                    (string= (plist-get h :run-id) version-b))
                                  history))
             (summary-a (plist-get entry-a :summary))
             (summary-b (plist-get entry-b :summary)))
        (when (and summary-a summary-b)
          (gptel-benchmark-compare
           summary-a summary-b
           (format "%s: %s vs %s" name version-a version-b)
           #'identity))))))

(defun gptel-benchmark-baseline-compare (name &optional results-dir)
  "Compare current version of NAME against baseline.
Returns improvement/regression analysis."
  (let* ((dir (or results-dir gptel-benchmark-default-dir))
         (history (gptel-benchmark-load-history name dir)))
    (when (and history (> (length history) 1))
      (let* ((current (car history))
             (baseline (car (last history)))
             (summary-current (plist-get current :summary))
             (summary-baseline (plist-get baseline :summary))
             (score-current (plist-get summary-current :avg-overall))
             (score-baseline (plist-get summary-baseline :avg-overall))
             (improvement (- score-current score-baseline)))
        (list :current-run (plist-get current :run-id)
              :baseline-run (plist-get baseline :run-id)
              :current-score score-current
              :baseline-score score-baseline
              :improvement improvement
              :improvement-percentage (* 100 improvement)
              :status (cond
                       ((> improvement 0.1) :significant-improvement)
                       ((> improvement 0) :improvement)
                       ((< improvement -0.1) :significant-regression)
                       ((< improvement 0) :regression)
                       (t :unchanged)))))))

(defun gptel-benchmark-ab-report (report)
  "Display A/B test REPORT in a buffer."
  (with-output-to-temp-buffer "*A/B Test Report*"
    (princ "=== A/B Test Report ===\n\n")
    (princ (format "A: %s (score: %.1f%%)\n"
                   (plist-get report :name-a)
                   (* 100 (or (plist-get report :score-a) 0))))
    (princ (format "B: %s (score: %.1f%%)\n\n"
                   (plist-get report :name-b)
                   (* 100 (or (plist-get report :score-b) 0))))
    (let ((comparison (plist-get report :comparison)))
      (princ (format "Winner: %s\n" (or (plist-get comparison :winner) "undetermined")))
      (when-let ((rec (plist-get comparison :recommendation)))
        (princ (format "\nRecommendation: %s\n" rec)))
      (when-let ((analysis (plist-get comparison :analysis)))
        (princ "\n--- Analysis ---\n")
        (when-let ((sa (alist-get 'strengths_a analysis)))
          (princ (format "A strengths: %s\n" sa)))
        (when-let ((sb (alist-get 'strengths_b analysis)))
          (princ (format "B strengths: %s\n" sb)))))
    (let ((stats (plist-get report :statistical)))
      (princ "\n--- Statistical ---\n")
      (princ (format "Difference: %.1f%%\n" (* 100 (or (plist-get stats :difference) 0))))
      (princ (format "Confidence: %s\n" (or (plist-get stats :confidence) "unknown"))))))

;;; Provide

(provide 'gptel-benchmark-subagent)

;;; gptel-benchmark-subagent.el ends here
