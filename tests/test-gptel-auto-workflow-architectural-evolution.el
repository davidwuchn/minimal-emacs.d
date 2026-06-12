;;; test-gptel-auto-workflow-architectural-evolution.el --- Tests for architectural-level pattern analysis -*- lexical-binding: t -*-

;; Copyright (C) 2026 OV5 Self-Improving Architecture

;; Author: OV5 System
;; Keywords: tests, architecture, strategy-routing, hypothesis-routing

;;; Commentary:

;; TDD tests for Architectural Evolution module.
;; Tests strategy routing analysis, hypothesis routing analysis,
;; risk classification, proposal generation with legacy keys,
;; and the full run-architectural-analysis entry point.
;; Mocks --parse-all-results (reads TSV files from disk) and
;; --categorize-hypothesis (from evolution module) for test isolation.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-auto-workflow-architectural-evolution)

;; ── Helper Macros ──

(defmacro with-mocked-arch-services (records &rest body)
  "Execute BODY with mocked parse, categorize, score, mementum services.
Returns write-calls list after body completes."
  (declare (indent 1))
  `(let* ((write-calls nil)
          (parsed-records ,records))
     (cl-letf
         (((symbol-function 'gptel-auto-workflow--parse-all-results)
           (lambda (&optional _max-age-days) parsed-records))
          ((symbol-function 'gptel-auto-workflow--categorize-hypothesis)
           (lambda (hypothesis)
             (let ((text (downcase (or hypothesis ""))))
               (cond
                ((string-match-p "safety\\|defensive\\|validate" text) 'safety)
                ((string-match-p "bug\\|fix\\|nil\\|error" text) 'bug-fix)
                ((string-match-p "performance\\|cache\\|optimize" text) 'performance)
                ((string-match-p "refactor\\|extract\\|dedup" text) 'refactoring)
                (t 'other)))))
          ((symbol-function 'gptel-auto-workflow--score-proposal)
           (lambda (proposal)
             (let* ((confidence (or (plist-get proposal :confidence) 0.5))
                    (risk (or (plist-get proposal :risk) "medium"))
                    (impact-score (min 1.0 (* confidence 1.0)))
                    (feasibility-score
                     (cond ((equal risk "low") 0.9)
                           ((equal risk "medium") 0.7)
                           ((equal risk "high") 0.5)
                           (t 0.6))))
               (append proposal
                       (list :impact-score impact-score
                             :feasibility-score feasibility-score)))))
          ((symbol-function 'gptel-auto-workflow--mementum-write-memory)
           (lambda (symbol slug _content)
             (push (list symbol slug) write-calls)
             (format "/tmp/mock-arch-%s-%s.md" symbol slug)))
          ((symbol-function 'gptel-auto-workflow--mementum-slug)
           (lambda (text)
             (let* ((clean (replace-regexp-in-string
                            "[^a-zA-Z0-9]" "-" (or text "")))
                    (collapsed (replace-regexp-in-string "-+" "-" clean))
                    (slug (downcase (string-trim collapsed "-"))))
               (substring slug 0 (min 80 (length slug))))))
          ((symbol-function 'gptel-auto-workflow--worktree-base-root)
           (lambda () "/tmp/mock-base")))
       ,@body
       write-calls)))

;; ── Risk Classification Tests ──

(ert-deftest test-architectural/risk-classify-investigation ()
  "Should classify investigation change-type as low risk."
  (should (equal (gptel-auto-workflow--architectural-risk-classify 'investigation) "low")))

(ert-deftest test-architectural/risk-classify-routing-change ()
  "Should classify routing-change change-type as medium risk."
  (should (equal (gptel-auto-workflow--architectural-risk-classify 'routing-change) "medium")))

(ert-deftest test-architectural/risk-classify-module-remove ()
  "Should classify module-remove change-type as high risk."
  (should (equal (gptel-auto-workflow--architectural-risk-classify 'module-remove) "high")))

(ert-deftest test-architectural/risk-classify-module-add ()
  "Should classify module-add change-type as high risk."
  (should (equal (gptel-auto-workflow--architectural-risk-classify 'module-add) "high")))

(ert-deftest test-architectural/risk-classify-module-split ()
  "Should classify module-split change-type as high risk."
  (should (equal (gptel-auto-workflow--architectural-risk-classify 'module-split) "high")))

(ert-deftest test-architectural/risk-classify-unknown ()
  "Should classify unknown change-type as medium risk (safe default)."
  (should (equal (gptel-auto-workflow--architectural-risk-classify 'unknown) "medium")))

;; ── Risk → Deploy Action Tests ──

(ert-deftest test-architectural/risk-deploy-action-low ()
  "Should map low risk to auto-deploy."
  (should (equal (gptel-auto-workflow--architectural-risk->deploy-action "low") "auto-deploy")))

(ert-deftest test-architectural/risk-deploy-action-medium ()
  "Should map medium risk to notify."
  (should (equal (gptel-auto-workflow--architectural-risk->deploy-action "medium") "notify")))

(ert-deftest test-architectural/risk-deploy-action-high ()
  "Should map high risk to approval-required."
  (should (equal (gptel-auto-workflow--architectural-risk->deploy-action "high") "approval-required")))

;; ── Strategy Routing Analysis Tests ──

(ert-deftest test-architectural/strategy-routing-groups-by-research-strategy ()
  "Should group experiments by :research-strategy and compute kept-rate."
  (let ((records
         (list
          (list :decision "kept" :research-strategy "deep-research"
                :target "lisp/foo.el" :hypothesis "fix bug")
          (list :decision "discarded" :research-strategy "deep-research"
                :target "lisp/foo.el" :hypothesis "optimize cache")
          (list :decision "discarded" :research-strategy "deep-research"
                :target "lisp/foo.el" :hypothesis "add safety check")
          (list :decision "kept" :research-strategy "none"
                :target "lisp/bar.el" :hypothesis "refactor")
          (list :decision "kept" :research-strategy "none"
                :target "lisp/bar.el" :hypothesis "fix nil")
          (list :decision "kept" :research-strategy "none"
                :target "lisp/bar.el" :hypothesis "validate")))
        (patterns nil))
    (with-mocked-arch-services
     records
     (setq patterns (gptel-auto-workflow--analyze-strategy-routing records)))
    ;; deep-research: 1/3 kept (33%), none: 3/3 kept (100%)
    ;; Sorted worst first
    (should (= (length patterns) 2))
    (should (equal (plist-get (nth 0 patterns) :strategy) "deep-research"))
    (should (< (plist-get (nth 0 patterns) :kept-rate) 0.5))
    (should (equal (plist-get (nth 1 patterns) :strategy) "none"))
    (should (= (plist-get (nth 1 patterns) :kept-rate) 1.0))))

(ert-deftest test-architectural/strategy-routing-min-occurrences ()
  "Should not include strategies below min-occurrences threshold."
  (let ((records
         (list
          (list :decision "kept" :research-strategy "rare"
                :target "lisp/foo.el" :hypothesis "fix")
          (list :decision "discarded" :research-strategy "rare"
                :target "lisp/foo.el" :hypothesis "fix")))
        (patterns nil))
    (with-mocked-arch-services
     records
     (let ((gptel-auto-workflow-architectural-min-occurrences 3))
       (setq patterns (gptel-auto-workflow--analyze-strategy-routing records))))
    (should (= (length patterns) 0))))

;; ── Hypothesis Routing Analysis Tests ──

(ert-deftest test-architectural/hypothesis-routing-uses-categorize ()
  "Should use --categorize-hypothesis to classify and group by category+strategy."
  (let ((records
         (list
          (list :decision "kept" :research-strategy "deep-research"
                :target "lisp/foo.el" :hypothesis "add safety check")
          (list :decision "discarded" :research-strategy "deep-research"
                :target "lisp/foo.el" :hypothesis "validate input defensive")
          (list :decision "discarded" :research-strategy "deep-research"
                :target "lisp/foo.el" :hypothesis "defensive programming")
          (list :decision "kept" :research-strategy "none"
                :target "lisp/bar.el" :hypothesis "fix nil error")
          (list :decision "kept" :research-strategy "none"
                :target "lisp/bar.el" :hypothesis "bug fix in handler")
          (list :decision "kept" :research-strategy "none"
                :target "lisp/bar.el" :hypothesis "prevent runtime crash")))
        (groups nil))
    (with-mocked-arch-services
     records
     (setq groups (gptel-auto-workflow--analyze-hypothesis-routing records)))
    ;; safety|deep-research: 1/3 kept (33%) -> routing-change
    ;; bug-fix|none: 3/3 kept (100%) -> filtered out (adequate)
    (should (>= (length groups) 1))
    (let ((first (nth 0 groups)))
      (should (eq (plist-get first :category) 'safety))
      (should (equal (plist-get first :strategy) "deep-research"))
      (should (< (plist-get first :kept-rate) 0.5))
      (should (eq (plist-get first :change-type) 'routing-change)))))

(ert-deftest test-architectural/hypothesis-routing-investigation-type ()
  "Should classify poor performance with none strategy as investigation."
  (let ((records
         (list
          (list :decision "discarded" :research-strategy "none"
                :target "lisp/foo.el" :hypothesis "random change 1")
          (list :decision "discarded" :research-strategy "none"
                :target "lisp/foo.el" :hypothesis "random change 2")
          (list :decision "kept" :research-strategy "none"
                :target "lisp/foo.el" :hypothesis "random change 3")))
        (groups nil))
    (with-mocked-arch-services
     records
     (setq groups (gptel-auto-workflow--analyze-hypothesis-routing records)))
    ;; other|none: 1/3 kept (33%) but strategy is none -> investigation
    (should (>= (length groups) 1))
    (let ((first (nth 0 groups)))
      (should (eq (plist-get first :change-type) 'investigation)))))

;; ── Proposal Generation Tests ──

(ert-deftest test-architectural/generate-proposal-has-legacy-keys ()
  "Should generate proposal with legacy keys (:confidence :risk :component)."
  (let* ((routing-group (list :category 'safety
                              :strategy "deep-research"
                              :total 5
                              :kept 1
                              :kept-rate 0.2
                              :change-type 'routing-change))
         (proposal (gptel-auto-workflow--generate-architectural-proposal routing-group)))
    ;; Legacy keys present for --score-proposal compatibility
    (should (plist-get proposal :confidence))
    (should (plist-get proposal :risk))
    (should (plist-get proposal :component))
    (should (equal (plist-get proposal :confidence) 0.5))
    (should (equal (plist-get proposal :risk) "medium"))
    (should (equal (plist-get proposal :component) "architectural-analysis"))
    ;; Architectural-specific keys also present
    (should (eq (plist-get proposal :change-type) 'routing-change))
    (should (eq (plist-get proposal :category) 'safety))
    (should (equal (plist-get proposal :affected-strategy) "deep-research"))
    (should (= (plist-get proposal :kept-rate) 0.2))))

(ert-deftest test-architectural/generate-proposal-investigation-risk ()
  "Should generate investigation proposal with low risk."
  (let* ((routing-group (list :category 'other
                              :strategy "none"
                              :total 4
                              :kept 1
                              :kept-rate 0.25
                              :change-type 'investigation))
         (proposal (gptel-auto-workflow--generate-architectural-proposal routing-group)))
    (should (equal (plist-get proposal :risk) "low"))
    (should (equal (plist-get proposal :confidence) 0.5))))

(ert-deftest test-architectural/generate-proposal-confidence-by-sample-size ()
  "Should compute confidence from sample size: 3-5=0.5, 6-10=0.6, 11+=0.7."
  (let* ((small-group (list :category 'safety :strategy "strat"
                            :total 4 :kept 1 :kept-rate 0.25
                            :change-type 'routing-change))
         (medium-group (list :category 'safety :strategy "strat"
                            :total 8 :kept 2 :kept-rate 0.25
                            :change-type 'routing-change))
         (large-group (list :category 'safety :strategy "strat"
                           :total 15 :kept 3 :kept-rate 0.2
                           :change-type 'routing-change))
         (small-prop (gptel-auto-workflow--generate-architectural-proposal small-group))
         (medium-prop (gptel-auto-workflow--generate-architectural-proposal medium-group))
         (large-prop (gptel-auto-workflow--generate-architectural-proposal large-group)))
    (should (= (plist-get small-prop :confidence) 0.5))
    (should (= (plist-get medium-prop :confidence) 0.6))
    (should (= (plist-get large-prop :confidence) 0.7))))

;; ── Score Proposal Integration Test ──

(ert-deftest test-architectural/proposal-compatible-with-score-proposal ()
  "Architectural proposal with legacy keys should be processable by --score-proposal."
  (let* ((routing-group (list :category 'safety
                              :strategy "deep-research"
                              :total 5
                              :kept 1
                              :kept-rate 0.2
                              :change-type 'routing-change))
         (proposal (gptel-auto-workflow--generate-architectural-proposal routing-group))
         (scored nil))
    (with-mocked-arch-services
     nil
     (setq scored (gptel-auto-workflow--score-proposal proposal)))
    (should (plist-get scored :impact-score))
    (should (plist-get scored :feasibility-score))
    (should (= (plist-get scored :impact-score) 0.5))
    (should (= (plist-get scored :feasibility-score) 0.7))))

;; ── Full Entry Point Tests ──

(ert-deftest test-architectural/run-analysis-generates-proposals ()
  "Should generate proposals from strategy routing and hypothesis routing analysis."
  (let ((records
         (list
          ;; deep-research strategy: 0/3 kept (very poor)
          (list :decision "discarded" :research-strategy "deep-research"
                :target "lisp/foo.el" :hypothesis "validate defensive safety")
          (list :decision "discarded" :research-strategy "deep-research"
                :target "lisp/foo.el" :hypothesis "add safety check")
          (list :decision "discarded" :research-strategy "deep-research"
                :target "lisp/foo.el" :hypothesis "defensive guard")
          ;; shallow strategy: 3/3 kept (good)
          (list :decision "kept" :research-strategy "shallow"
                :target "lisp/bar.el" :hypothesis "fix nil error")
          (list :decision "kept" :research-strategy "shallow"
                :target "lisp/bar.el" :hypothesis "bug fix crash")
          (list :decision "kept" :research-strategy "shallow"
                :target "lisp/bar.el" :hypothesis "prevent runtime")))
        (result nil))
    (with-mocked-arch-services
     records
     (setq result (gptel-auto-workflow--run-architectural-analysis)))
    (let ((proposals (plist-get result :proposals)))
      (should (>= (length proposals) 1))
      (should (cl-find-if
               (lambda (p) (eq (plist-get p :change-type) 'routing-change))
               proposals)))))

(ert-deftest test-architectural/run-analysis-persists-to-mementum ()
  "Should persist architectural proposals to mementum with insight symbol."
  (let ((records
         (list
          (list :decision "discarded" :research-strategy "deep-research"
                :target "lisp/foo.el" :hypothesis "validate safety")
          (list :decision "discarded" :research-strategy "deep-research"
                :target "lisp/foo.el" :hypothesis "add defensive check")
          (list :decision "discarded" :research-strategy "deep-research"
                :target "lisp/foo.el" :hypothesis "safety guard")))
        (calls nil))
    (setq calls
          (with-mocked-arch-services
           records
           (gptel-auto-workflow--run-architectural-analysis)))
    (should (>= (length calls) 1))
    (should (cl-find-if (lambda (call) (eq (nth 0 call) '💡)) calls))))

(ert-deftest test-architectural/run-analysis-no-records ()
  "Should return empty results when no experiment records exist."
  (let ((result nil))
    (with-mocked-arch-services
     nil
     (setq result (gptel-auto-workflow--run-architectural-analysis)))
    (should (= (length (plist-get result :proposals)) 0))
    (should (= (length (plist-get result :written)) 0))))

;; ── Proposal Formatting Tests ──

(ert-deftest test-architectural/proposal-string-format ()
  "Should format proposal plist into readable string with architectural fields."
  (let* ((proposal (list :description "Strategy routing: deep-research has 20% success"
                         :component "strategy-router"
                         :change-type 'routing-change
                         :affected-strategy "deep-research"
                         :category 'safety
                         :confidence 0.5
                         :risk "medium"
                         :expected-impact "Improve deep-research success from 20% to >50%"
                         :kept-rate 0.2
                         :impact-score 0.5
                         :feasibility-score 0.7))
         (str (gptel-auto-workflow--architectural-proposal->string proposal)))
    (should (string-match-p "Architectural proposal" str))
    (should (string-match-p "Change type" str))
    (should (string-match-p "routing-change" str))
    (should (string-match-p "deep-research" str))
    (should (string-match-p "Component" str))
    (should (string-match-p "Confidence" str))
    (should (string-match-p "Risk" str))
    (should (string-match-p "Impact score" str))
    (should (string-match-p "Feasibility score" str))))

;; ── Uses :research-strategy (not :strategy) ──

(ert-deftest test-architectural/uses-research-strategy-field ()
  "Should use :research-strategy field from parse-all-results, not :strategy."
  (let ((records
         (list
          (list :decision "discarded"
                :research-strategy "deep-research"
                :strategy "default"
                :target "lisp/foo.el"
                :hypothesis "fix bug"
                :prompt-chars 500)))
        (patterns nil))
    (with-mocked-arch-services
     records
     (let ((gptel-auto-workflow-architectural-min-occurrences 1))
       (setq patterns (gptel-auto-workflow--analyze-strategy-routing records))))
    (should (= (length patterns) 1))
    (should (equal (plist-get (nth 0 patterns) :strategy) "deep-research"))))

;; ── Monitoring Cycle Integration Test ──

(ert-deftest test-architectural/monitoring-cycle-integration ()
  "Architectural analysis should be called during monitoring cycle (Phase 4)."
  (let ((records
         (list
          ;; Pattern data for Phase 1-3 (grader failures)
          (list :decision "rejected" :target "lisp/test.el"
                :grader-reason "syntax error" :strategy "default"
                :prompt-chars 500 :research-strategy "none"
                :run-dir "run-1" :hypothesis "fix bug")
          (list :decision "rejected" :target "lisp/test.el"
                :grader-reason "syntax error" :strategy "default"
                :prompt-chars 500 :research-strategy "none"
                :run-dir "run-2" :hypothesis "fix error")
          (list :decision "rejected" :target "lisp/test.el"
                :grader-reason "syntax error" :strategy "default"
                :prompt-chars 500 :research-strategy "none"
                :run-dir "run-3" :hypothesis "fix nil")))
        (calls nil))
    (setq calls
          (with-mocked-arch-services
           records
           (require 'gptel-auto-workflow-monitoring-agent)
           (let ((gptel-auto-workflow-monitoring-enabled t)
                 (gptel-auto-workflow-monitoring-last-cycle-time 0.0)
                 (gptel-auto-workflow-monitoring-cycle-interval 0)
                 (gptel-auto-workflow-monitoring-min-occurrences 3)
                 (gptel-auto-workflow-monitoring-deploy-threshold 0.6))
             (setq gptel-auto-workflow--running t)
             (unwind-protect
                 (gptel-auto-workflow--monitoring-cycle)
                (makunbound 'gptel-auto-workflow--running)))))
    ;; Monitoring cycle should have write calls
    (should (>= (length calls) 1))))

(provide 'test-gptel-auto-workflow-architectural-evolution)
;;; test-gptel-auto-workflow-architectural-evolution.el ends here