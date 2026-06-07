;;; test-gptel-auto-workflow-monitoring-agent.el --- Tests for failure pattern analysis -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OV5 Self-Improving Architecture

;; Author: OV5 System
;; Keywords: tests, monitoring, failure-patterns

;;; Commentary:

;; TDD tests for Monitoring Agent Phase 1: failure pattern analysis.
;; Phase 2: proposal generation, scoring, validation, and persistence.
;; Tests classification, systemic detection, throttle, mementum persistence,
;; and proposal generation pipeline.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-auto-workflow-monitoring-agent)

;; ── Helper Macros ──

(defmacro with-clean-monitoring-state (&rest body)
  "Execute BODY with clean monitoring agent state."
  (declare (indent 0))
  `(let ((gptel-auto-workflow-monitoring-enabled t)
         (gptel-auto-workflow-monitoring-min-occurrences 3)
         (gptel-auto-workflow-monitoring-cycle-interval 900)
         (gptel-auto-workflow-monitoring-last-cycle-time 0.0))
     ,@body))

(defmacro with-mocked-parse-and-mementum (records &rest body)
  "Execute BODY with mocked parse and mementum.  Returns write-calls."
  (declare (indent 1))
  `(let* ((write-calls nil)
          (parsed-records ,records))
     (cl-letf
         (((symbol-function 'gptel-auto-workflow--parse-all-results)
           (lambda (&optional _max-age-days) parsed-records))
          ((symbol-function 'gptel-auto-workflow--mementum-write-memory)
           (lambda (symbol slug content)
             (push (list symbol slug content) write-calls)
             (format "/tmp/mock-%s-%s.md" symbol slug)))
          ((symbol-function 'gptel-auto-workflow--mementum-slug)
           (lambda (text)
             (let* ((clean (replace-regexp-in-string
                            "[^a-zA-Z0-9]" "-" (or text "")))
                    (collapsed (replace-regexp-in-string "-+" "-" clean))
                    (slug (downcase (string-trim collapsed "-"))))
               (substring slug 0 (min 80 (length slug))))))
          ((symbol-function 'gptel-auto-workflow--worktree-base-root)
           (lambda () "/tmp/mock-base")))
       (with-clean-monitoring-state ,@body)
       write-calls)))

(defmacro with-mocked-parse (records &rest body)
  "Execute BODY with mocked parse-all-results returning RECORDS.
Returns the result of the last form in BODY."
  (declare (indent 1))
  `(let ((parsed-records ,records))
     (cl-letf
         (((symbol-function 'gptel-auto-workflow--parse-all-results)
           (lambda (&optional _max-age-days) parsed-records)))
       (with-clean-monitoring-state ,@body))))

;; ── Classification Tests ──

(ert-deftest test-monitoring/classify-grader ()
  "Should classify syntax error in grader_reason as grader failure."
  (let ((experiment (list :decision "rejected"
                          :grader-reason "syntax error in foo function"
                          :prompt-chars 500
                          :strategy "default")))
    (should (eq (gptel-auto-workflow--classify-failure experiment)
                'grader))))

(ert-deftest test-monitoring/classify-grader-type-mismatch ()
  "Should classify type mismatch as grader failure."
  (let ((experiment (list :decision "rejected"
                          :grader-reason "type mismatch: expected string"
                          :prompt-chars 500
                          :strategy "default")))
    (should (eq (gptel-auto-workflow--classify-failure experiment)
                'grader))))

(ert-deftest test-monitoring/classify-compilation ()
  "Should classify compilation failure correctly."
  (let ((experiment (list :decision "rejected"
                          :grader-reason "compile error: missing dependency"
                          :prompt-chars 500
                          :strategy "default")))
    (should (eq (gptel-auto-workflow--classify-failure experiment)
                'compilation))))

(ert-deftest test-monitoring/classify-prompt-long ()
  "Should classify excessive prompt length as prompt failure."
  (let ((experiment (list :decision "rejected"
                          :grader-reason "low quality"
                          :prompt-chars 5000
                          :strategy "default")))
    (should (eq (gptel-auto-workflow--classify-failure experiment)
                'prompt))))

(ert-deftest test-monitoring/classify-prompt-keyword ()
  "Should classify prompt-specific keywords as prompt failure."
  (let ((experiment (list :decision "rejected"
                          :grader-reason "prompt too long for context"
                          :prompt-chars 500
                          :strategy "default")))
    (should (eq (gptel-auto-workflow--classify-failure experiment)
                'prompt))))

(ert-deftest test-monitoring/classify-strategy-none ()
  "Should classify strategy=none as strategy failure."
  (let ((experiment (list :decision "rejected"
                          :grader-reason "low quality"
                          :prompt-chars 500
                          :strategy "none")))
    (should (eq (gptel-auto-workflow--classify-failure experiment)
                'strategy))))

(ert-deftest test-monitoring/classify-unknown ()
  "Should classify unrecognizable patterns as unknown."
  (let ((experiment (list :decision "discarded"
                          :grader-reason "low quality score"
                          :prompt-chars 500
                          :strategy "default")))
    (should (eq (gptel-auto-workflow--classify-failure experiment)
                'unknown))))

;; ── Systemic Failure Analysis Tests ──

(ert-deftest test-monitoring/analyze-grouping ()
  "Should group 4 identical grader failures on same target into one pattern."
  (let* ((records
          (list
           (list :decision "rejected" :target "lisp/foo.el"
                 :grader-reason "syntax error in bar" :strategy "default"
                 :prompt-chars 500 :run-dir "run-1")
           (list :decision "rejected" :target "lisp/foo.el"
                 :grader-reason "syntax error in baz" :strategy "default"
                 :prompt-chars 500 :run-dir "run-2")
           (list :decision "rejected" :target "lisp/foo.el"
                 :grader-reason "syntax error in qux" :strategy "default"
                 :prompt-chars 500 :run-dir "run-3")
           (list :decision "rejected" :target "lisp/foo.el"
                 :grader-reason "syntax error in quuz" :strategy "default"
                 :prompt-chars 500 :run-dir "run-4")))
         (patterns
          (with-mocked-parse
           records
           (gptel-auto-workflow--analyze-systemic-failures))))
    (should (= (length patterns) 1))
    (should (eq (plist-get (car patterns) :type) 'grader))
    (should (equal (plist-get (car patterns) :target) "lisp/foo.el"))
    (should (= (plist-get (car patterns) :count) 4))))

(ert-deftest test-monitoring/analyze-min-occurrences ()
  "Should not flag patterns below min-occurrences threshold."
  (let* ((records
          (list
           (list :decision "rejected" :target "lisp/bar.el"
                 :grader-reason "syntax error" :strategy "default"
                 :prompt-chars 500 :run-dir "run-1")
           (list :decision "rejected" :target "lisp/bar.el"
                 :grader-reason "syntax error" :strategy "default"
                 :prompt-chars 500 :run-dir "run-2")))
         (patterns
          (with-mocked-parse
           records
           (gptel-auto-workflow--analyze-systemic-failures))))
    (should (= (length patterns) 0))))

;; ── Throttle Tests ──

(ert-deftest test-monitoring/throttle-enforces-gap ()
  "Should skip cycle when elapsed time < cycle-interval."
  (with-clean-monitoring-state
   (setq gptel-auto-workflow-monitoring-last-cycle-time
         (- (float-time) 60))
   (let ((result (gptel-auto-workflow--monitoring-cycle)))
     (should (null result)))))

(ert-deftest test-monitoring/throttle-allows-after-interval ()
  "Should allow cycle when elapsed time >= cycle-interval."
  (let* ((records
          (list
           (list :decision "rejected" :target "lisp/test.el"
                 :grader-reason "syntax error" :strategy "default"
                 :prompt-chars 500 :run-dir "run-1")
           (list :decision "rejected" :target "lisp/test.el"
                 :grader-reason "syntax error" :strategy "default"
                 :prompt-chars 500 :run-dir "run-2")
           (list :decision "rejected" :target "lisp/test.el"
                 :grader-reason "syntax error" :strategy "default"
                 :prompt-chars 500 :run-dir "run-3")))
         (calls
          (with-mocked-parse-and-mementum
           records
           (setq gptel-auto-workflow-monitoring-last-cycle-time
                 (- (float-time) 1000))
           (gptel-auto-workflow--monitoring-cycle))))
    (should (>= (length calls) 1))))

;; ── Mementum Persistence Tests ──

(ert-deftest test-monitoring/mementum-persistence ()
  "Should persist patterns to mementum with X symbol."
  (let* ((records
          (list
           (list :decision "rejected" :target "lisp/comp.el"
                 :grader-reason "compile error missing deps" :strategy "default"
                 :prompt-chars 500 :run-dir "run-1")
           (list :decision "rejected" :target "lisp/comp.el"
                 :grader-reason "compile error missing deps" :strategy "default"
                 :prompt-chars 500 :run-dir "run-2")
           (list :decision "rejected" :target "lisp/comp.el"
                 :grader-reason "compile error missing deps" :strategy "default"
                 :prompt-chars 500 :run-dir "run-3")))
          (calls
           (with-mocked-parse-and-mementum
            records
            (setq gptel-auto-workflow-monitoring-last-cycle-time 0.0)
            (gptel-auto-workflow--monitoring-cycle))))
    (should (>= (length calls) 1))
    ;; At least one call must be a pattern (X symbol)
    (let ((has-pattern nil))
      (dolist (call calls)
        (when (eq (nth 0 call) '❌) (setq has-pattern t)))
      (should has-pattern))))

;; ── Pattern Formatting Tests ──

(ert-deftest test-monitoring/pattern-string-format ()
  "Should format pattern plist into readable string with key fields."
  (let* ((pattern (list :type 'grader
                        :target "lisp/modules/foo.el"
                        :count 5
                        :examples
                        (list "syntax error in bar"
                              "type mismatch in baz")
                        :first-seen "run-old"
                        :last-seen "run-new"))
         (str (gptel-auto-workflow--failure-pattern->string pattern)))
    (should (string-match-p "Failure type" str))
    (should (string-match-p "Target" str))
    (should (string-match-p "Occurrences" str))
    (should (string-match-p "syntax error in bar" str))
    (should (string-match-p "run-old" str))
    (should (string-match-p "run-new" str))))

;; ── Phase 2: Proposal Generation Tests ──

(ert-deftest test-monitoring/generate-proposal-from-pattern ()
  "Should generate a proposal with correct component, confidence, risk from a grader pattern."
  (let* ((pattern (list :type 'grader
                        :target "lisp/modules/foo.el"
                        :count 4
                        :examples (list "syntax error in bar" "type mismatch in baz")))
         (proposal (gptel-auto-workflow--generate-improvement-proposal pattern)))
    (should (equal (plist-get proposal :component) "grader"))
    (should (equal (plist-get proposal :confidence) 0.7))
    (should (equal (plist-get proposal :risk) "medium"))
    (should (string-match-p "grader" (plist-get proposal :description)))
    (should (string-match-p "lisp/modules/foo.el" (plist-get proposal :description)))
    (should (equal (plist-get proposal :pattern-type) 'grader))
    (should (equal (plist-get proposal :pattern-target) "lisp/modules/foo.el"))))

(ert-deftest test-monitoring/generate-proposal-compilation-pattern ()
  "Should map compilation failure type to grader component."
  (let* ((pattern (list :type 'compilation
                        :target "lisp/core.el"
                        :count 5
                        :examples (list "compile error missing deps")))
         (proposal (gptel-auto-workflow--generate-improvement-proposal pattern)))
    (should (equal (plist-get proposal :component) "grader"))
    (should (equal (plist-get proposal :confidence) 0.8))
    (should (equal (plist-get proposal :risk) "medium"))))

(ert-deftest test-monitoring/generate-proposal-strategy-pattern ()
  "Should map strategy failure to strategy-harness component with high risk."
  (let* ((pattern (list :type 'strategy
                        :target "lisp/harness.el"
                        :count 3
                        :examples (list "no strategy selected")))
         (proposal (gptel-auto-workflow--generate-improvement-proposal pattern)))
    (should (equal (plist-get proposal :component) "strategy-harness"))
    (should (equal (plist-get proposal :confidence) 0.6))
    (should (equal (plist-get proposal :risk) "high"))))

(ert-deftest test-monitoring/score-proposal-impact-feasibility ()
  "Should compute impact-score and feasibility-score from proposal."
  (let* ((proposal (list :description "Fix grader"
                         :component "grader"
                         :confidence 0.7
                         :risk "medium"
                         :pattern-type 'grader
                         :pattern-target "lisp/foo.el"))
         (scored (gptel-auto-workflow--score-proposal proposal)))
    ;; impact-score = confidence * 1.0 = 0.7
    (should (= (plist-get scored :impact-score) 0.7))
    ;; feasibility-score: medium risk -> 0.7
    (should (= (plist-get scored :feasibility-score) 0.7))))

(ert-deftest test-monitoring/score-proposal-low-risk ()
  "Should give feasibility 0.9 for low-risk proposal."
  (let* ((proposal (list :description "Fix general"
                         :component "general"
                         :confidence 0.6
                         :risk "low"
                         :pattern-type 'unknown
                         :pattern-target "misc"))
         (scored (gptel-auto-workflow--score-proposal proposal)))
    (should (= (plist-get scored :feasibility-score) 0.9))
    (should (= (plist-get scored :impact-score) 0.6))))

(ert-deftest test-monitoring/validate-proposal-high-rate ()
  "Should validate proposal with high match rate as 'validated'."
  (let* ((proposal (list :description "Fix grader failures"
                         :component "grader"
                         :confidence 0.7
                         :risk "medium"
                         :impact-score 0.7
                         :feasibility-score 0.7
                         :pattern-type 'grader
                         :pattern-target "lisp/foo.el"))
         ;; 10 total failures, 8 are grader on lisp/foo.el
         (records
          (append
           (make-list 8 (list :decision "rejected" :target "lisp/foo.el"
                              :grader-reason "syntax error" :strategy "default"
                              :prompt-chars 500))
           (make-list 2 (list :decision "rejected" :target "lisp/other.el"
                              :grader-reason "low quality" :strategy "default"
                              :prompt-chars 500))))
         (validated (gptel-auto-workflow--validate-proposal proposal records)))
    (should (>= (plist-get validated :validation-rate) 0.8))
    (should (equal (plist-get validated :status) "validated"))))

(ert-deftest test-monitoring/validate-proposal-low-rate ()
  "Should mark proposal with low match rate as 'tentative'."
  (let* ((proposal (list :description "Fix grader failures"
                         :component "grader"
                         :confidence 0.7
                         :risk "medium"
                         :impact-score 0.7
                         :feasibility-score 0.7
                         :pattern-type 'grader
                         :pattern-target "lisp/rare.el"))
         ;; 10 total failures, only 2 match
         (records
          (append
           (make-list 2 (list :decision "rejected" :target "lisp/rare.el"
                              :grader-reason "syntax error" :strategy "default"
                              :prompt-chars 500))
           (make-list 8 (list :decision "rejected" :target "lisp/common.el"
                              :grader-reason "low quality" :strategy "default"
                              :prompt-chars 500))))
         (validated (gptel-auto-workflow--validate-proposal proposal records)))
    (should (< (plist-get validated :validation-rate) 0.6))
    (should (equal (plist-get validated :status) "tentative"))))

(ert-deftest test-monitoring/proposal-string-format ()
  "Should format proposal plist into readable string with all key fields."
  (let* ((proposal (list :description "Address recurring grader failures"
                         :component "grader"
                         :expected-impact "Reduce grader failures by ~70%"
                         :confidence 0.7
                         :risk "medium"
                         :validation-rate 0.8
                         :status "validated"))
         (str (gptel-auto-workflow--proposal->string proposal)))
    (should (string-match-p "Proposal" str))
    (should (string-match-p "Component" str))
    (should (string-match-p "grader" str))
    (should (string-match-p "Expected impact" str))
    (should (string-match-p "Confidence" str))
    (should (string-match-p "Risk" str))
    (should (string-match-p "Validation rate" str))
    (should (string-match-p "validated" str))))

(ert-deftest test-monitoring/monitoring-cycle-generates-proposals ()
  "Should persist proposals with insight symbol alongside patterns in monitoring cycle."
  (let* ((records
          (list
           (list :decision "rejected" :target "lisp/test.el"
                 :grader-reason "syntax error" :strategy "default"
                 :prompt-chars 500 :run-dir "run-1")
           (list :decision "rejected" :target "lisp/test.el"
                 :grader-reason "syntax error" :strategy "default"
                 :prompt-chars 500 :run-dir "run-2")
           (list :decision "rejected" :target "lisp/test.el"
                 :grader-reason "syntax error" :strategy "default"
                 :prompt-chars 500 :run-dir "run-3")))
         (calls
          (with-mocked-parse-and-mementum
           records
           (setq gptel-auto-workflow-monitoring-last-cycle-time 0.0)
           (gptel-auto-workflow--monitoring-cycle))))
    ;; Should have at least 2 calls: 1 for pattern (X) + 1 for proposal (insight)
    (should (>= (length calls) 2))
    ;; Check that at least one call uses the insight symbol
    (let ((has-insight nil)
          (has-mistake nil))
      (dolist (call calls)
        (when (eq (nth 0 call) '💡) (setq has-insight t))
        (when (eq (nth 0 call) '❌) (setq has-mistake t)))
      (should has-insight)
      (should has-mistake))))

(provide 'test-gptel-auto-workflow-monitoring-agent)
;;; test-gptel-auto-workflow-monitoring-agent.el ends here