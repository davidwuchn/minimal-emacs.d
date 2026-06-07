;;; test-gptel-auto-workflow-monitoring-agent.el --- Tests for failure pattern analysis -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OV5 Self-Improving Architecture

;; Author: OV5 System
;; Keywords: tests, monitoring, failure-patterns

;;; Commentary:

;; TDD tests for Monitoring Agent Phase 1: failure pattern analysis.
;; Tests classification, systemic detection, throttle, and mementum persistence.

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
  "Should persist each pattern to mementum with X symbol."
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
    (dolist (call calls)
      (should (eq (nth 0 call) '❌)))))

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

(provide 'test-gptel-auto-workflow-monitoring-agent)
;;; test-gptel-auto-workflow-monitoring-agent.el ends here