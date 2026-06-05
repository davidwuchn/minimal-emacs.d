;;; test-gptel-monitoring-agent.el --- Tests for monitoring agent -*- lexical-binding: t -*-

;; Copyright (C) 2026 OV5 Self-Improving Architecture

;;; Commentary:

;; TDD tests for Phase 2: Monitoring Agent
;; This agent analyzes failures and rewrites the pipeline itself.
;; The "holy shit moment" from YC vision.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-monitoring-agent)

;; ============================================================================
;; Task 2.1: Failure Pattern Analysis
;; ============================================================================

(ert-deftest test-monitoring-agent/parse-results ()
  "Should parse last N runs from TSV files."
  (let* ((mock-results '((:id "exp-001" :decision "kept" :backend "MiniMax" :category :programming :target "file1.el")
                         (:id "exp-002" :decision "discarded" :backend "MiniMax" :category :programming :target "file1.el")
                         (:id "exp-003" :decision "grader-failed" :backend "DeepSeek" :category :tool-calls :target "file2.el")))
         (parsed (gptel-monitoring-agent--parse-results mock-results)))
    (should (= 3 (length parsed)))
    (should (equal "exp-001" (plist-get (car parsed) :id)))))

(ert-deftest test-monitoring-agent/detect-grader-failures ()
  "Should detect when grader fails 3+ times on similar code."
  (let* ((results '((:id "1" :decision "grader-failed" :target "file1.el" :category :programming)
                    (:id "2" :decision "grader-failed" :target "file2.el" :category :programming)
                    (:id "3" :decision "grader-failed" :target "file3.el" :category :programming)
                    (:id "4" :decision "kept" :target "file4.el" :category :tool-calls)))
         (patterns (gptel-monitoring-agent--analyze-failure-patterns results)))
    (should (> (length patterns) 0))
    (should (cl-find "grader-systematic-failure" patterns
                     :key (lambda (p) (plist-get p :pattern))
                     :test #'string=))))

(ert-deftest test-monitoring-agent/detect-backend-category-failure ()
  "Should detect when backend has <5% keep-rate on category with 20+ experiments."
  (let* ((results (cl-loop for i from 1 to 25
                           collect (list :id (format "exp-%d" i)
                                        :decision (if (< i 2) "kept" "discarded")
                                        :backend "DeepSeek"
                                        :category :agentic
                                        :target (format "file%d.el" i))))
         (patterns (gptel-monitoring-agent--analyze-failure-patterns results)))
    (should (> (length patterns) 0))
    (should (cl-find "backend-category-failure" patterns
                     :key (lambda (p) (plist-get p :pattern))
                     :test #'string=))))

(ert-deftest test-monitoring-agent/detect-effort-waste ()
  "Should detect when high effort wastes tokens without improvement."
  (let* ((results (cl-loop for i from 1 to 10
                           collect (list :id (format "exp-%d" i)
                                        :decision "discarded"
                                        :effort-level "high"
                                        :prompt-chars 50000
                                        :target (format "file%d.el" i))))
         (patterns (gptel-monitoring-agent--analyze-failure-patterns results)))
    (should (> (length patterns) 0))
    (should (cl-find "effort-waste" patterns
                     :key (lambda (p) (plist-get p :pattern))
                     :test #'string=))))

(ert-deftest test-monitoring-agent/detect-target-failure-loop ()
  "Should detect when same target fails 5+ times."
  (let* ((results (cl-loop for i from 1 to 6
                           collect (list :id (format "exp-%d" i)
                                        :decision "discarded"
                                        :target "problematic-file.el"
                                        :category :programming)))
         (patterns (gptel-monitoring-agent--analyze-failure-patterns results)))
    (should (> (length patterns) 0))
    (should (cl-find "target-failure-loop" patterns
                     :key (lambda (p) (plist-get p :pattern))
                     :test #'string=))))

(ert-deftest test-monitoring-agent/no-patterns-when-healthy ()
  "Should return empty list when no systemic failures."
  (let* ((results '((:id "1" :decision "kept" :backend "MiniMax" :category :programming)
                    (:id "2" :decision "kept" :backend "MiniMax" :category :tool-calls)
                    (:id "3" :decision "discarded" :backend "DeepSeek" :category :agentic)))
         (patterns (gptel-monitoring-agent--analyze-failure-patterns results)))
    (should (= 0 (length patterns)))))

;; ============================================================================
;; Task 2.2: Self-Improvement Proposals
;; ============================================================================

(ert-deftest test-monitoring-agent/generate-grader-proposal ()
  "Should generate concrete proposal for grader systematic failure."
  (let* ((pattern '(:pattern "grader-systematic-failure"
                    :target "grader"
                    :evidence ((:id "1" :decision "grader-failed")
                               (:id "2" :decision "grader-failed")
                               (:id "3" :decision "grader-failed"))))
         (proposal (gptel-monitoring-agent--generate-proposal pattern)))
    (should (plist-get proposal :target))
    (should (plist-get proposal :changes))
    (should (plist-get proposal :test-plan))
    (should (plist-get proposal :expected-improvement))
    (should (string-match-p "grader" (plist-get proposal :target)))))

(ert-deftest test-monitoring-agent/generate-backend-proposal ()
  "Should generate proposal to swap backend for failing category."
  (let* ((pattern '(:pattern "backend-category-failure"
                    :backend "DeepSeek"
                    :category :agentic
                    :keep-rate 0.04
                    :evidence ((:id "1" :decision "discarded"))))
         (proposal (gptel-monitoring-agent--generate-proposal pattern)))
    (should (plist-get proposal :target))
    (should (string-match-p "DeepSeek" (plist-get proposal :changes)))
    (should (string-match-p "agentic" (plist-get proposal :changes)))))

(ert-deftest test-monitoring-agent/generate-effort-proposal ()
  "Should generate proposal to downgrade effort level."
  (let* ((pattern '(:pattern "effort-waste"
                    :effort-level "high"
                    :wasted-tokens 500000
                    :evidence ((:id "1" :decision "discarded" :effort-level "high"))))
         (proposal (gptel-monitoring-agent--generate-proposal pattern)))
    (should (plist-get proposal :target))
    (should (string-match-p "effort" (plist-get proposal :changes)))
    (should (string-match-p "downgrade" (plist-get proposal :changes)))))

(ert-deftest test-monitoring-agent/generate-target-proposal ()
  "Should generate proposal to skip failing target."
  (let* ((pattern '(:pattern "target-failure-loop"
                    :target "problematic-file.el"
                    :failure-count 6
                    :evidence ((:id "1" :decision "discarded" :target "problematic-file.el"))))
         (proposal (gptel-monitoring-agent--generate-proposal pattern)))
    (should (plist-get proposal :target))
    (should (string-match-p "skip" (plist-get proposal :changes)))
    (should (string-match-p "problematic-file.el" (plist-get proposal :changes)))))

(ert-deftest test-monitoring-agent/proposal-includes-test-plan ()
  "All proposals should include test plan and expected improvement."
  (let* ((patterns '((:pattern "grader-systematic-failure" :target "grader")
                     (:pattern "backend-category-failure" :backend "DeepSeek" :category :agentic :keep-rate 0.04)
                     (:pattern "effort-waste" :effort-level "high")
                     (:pattern "target-failure-loop" :target "file.el")))
         (proposals (mapcar #'gptel-monitoring-agent--generate-proposal patterns)))
    (dolist (proposal proposals)
      (should (plist-get proposal :test-plan))
      (should (plist-get proposal :expected-improvement))
      (should (> (length (plist-get proposal :test-plan)) 10)))))

;; ============================================================================
;; Task 2.3: Automated Testing & Deployment
;; ============================================================================

(ert-deftest test-monitoring-agent/test-proposal-baseline ()
  "Should calculate baseline keep-rate before applying changes."
  (let* ((proposal '(:target "gptel-tools-agent-grader.el"
                     :changes "Fix grader logic"
                     :test-plan "Test against 5 failed experiments"
                     :expected-improvement "Grader pass rate: 60% → 85%"))
         (mock-results '((:id "1" :decision "grader-failed" :target "file1.el")
                         (:id "2" :decision "grader-failed" :target "file2.el")
                         (:id "3" :decision "kept" :target "file3.el")))
         (baseline (gptel-monitoring-agent--calculate-baseline mock-results proposal)))
    (should (numberp baseline))
    (should (>= baseline 0.0))
    (should (<= baseline 1.0))))

(ert-deftest test-monitoring-agent/test-proposal-improvement ()
  "Should calculate improvement delta after applying changes."
  (let* ((proposal '(:target "gptel-tools-agent-grader.el"
                     :changes "Fix grader logic"
                     :test-plan "Test against 5 failed experiments"))
         (before-keep-rate 0.33)
         (after-keep-rate 0.67)
         (improvement (gptel-monitoring-agent--calculate-improvement
                       before-keep-rate after-keep-rate)))
    (should (numberp improvement))
    (should (> improvement 0.0))
    (should (= improvement (- after-keep-rate before-keep-rate)))))

(ert-deftest test-monitoring-agent/deploy-if-better ()
  "Should deploy proposal only if keep-rate improves."
  (let* ((proposal '(:target "gptel-tools-agent-grader.el"
                     :changes "Fix grader logic"))
         (test-result '(:pass-rate 0.67
                        :improvement 0.34
                        :decision "deploy")))
    (should (equal "deploy" (plist-get test-result :decision)))
    (should (> (plist-get test-result :improvement) 0.0))))

(ert-deftest test-monitoring-agent/reject-if-worse ()
  "Should reject proposal if keep-rate decreases."
  (let* ((proposal '(:target "gptel-tools-agent-grader.el"
                     :changes "Broken change"))
         (test-result '(:pass-rate 0.20
                        :improvement -0.13
                        :decision "reject")))
    (should (equal "reject" (plist-get test-result :decision)))
    (should (< (plist-get test-result :improvement) 0.0))))

(ert-deftest test-monitoring-agent/log-deployment-decision ()
  "Should log deployment decisions to file."
  (let* ((proposal '(:target "gptel-tools-agent-grader.el"
                     :changes "Fix grader"
                     :expected-improvement "60% → 85%"))
         (test-result '(:pass-rate 0.85
                        :improvement 0.25
                        :decision "deploy"))
         (log-file "/tmp/test-deployment-log.json"))
    ;; Mock the logging function
    (cl-letf (((symbol-function 'gptel-monitoring-agent--log-deployment)
               (lambda (proposal result file)
                 (with-temp-file file
                   (insert (json-encode (list :proposal proposal
                                             :result result
                                             :timestamp (current-time))))))))
      (gptel-monitoring-agent--log-deployment proposal test-result log-file)
      (should (file-exists-p log-file))
      (delete-file log-file))))

;; ============================================================================
;; Integration Tests
;; ============================================================================

(ert-deftest test-monitoring-agent/full-cycle ()
  "Should run full cycle: analyze → propose → test → deploy."
  (let* ((results (cl-loop for i from 1 to 30
                           collect (list :id (format "exp-%d" i)
                                        :decision (if (< i 5) "kept" "grader-failed")
                                        :target (format "file%d.el" i)
                                        :category :programming)))
         (patterns (gptel-monitoring-agent--analyze-failure-patterns results))
         (proposals (mapcar #'gptel-monitoring-agent--generate-proposal patterns)))
    (should (> (length patterns) 0))
    (should (> (length proposals) 0))
    (should (plist-get (car proposals) :target))
    (should (plist-get (car proposals) :changes))))

(ert-deftest test-monitoring-agent/no-deployment-when-no-patterns ()
  "Should not generate proposals when no systemic failures."
  (let* ((results '((:id "1" :decision "kept" :backend "MiniMax")
                    (:id "2" :decision "kept" :backend "MiniMax")
                    (:id "3" :decision "discarded" :backend "DeepSeek")))
         (patterns (gptel-monitoring-agent--analyze-failure-patterns results))
         (proposals (mapcar #'gptel-monitoring-agent--generate-proposal patterns)))
    (should (= 0 (length patterns)))
    (should (= 0 (length proposals)))))

;; ============================================================================
;; Helper Function Tests
;; ============================================================================

(ert-deftest test-monitoring-agent/filter-by-decision ()
  "Should filter results by decision type."
  (let* ((results '((:id "1" :decision "kept")
                    (:id "2" :decision "grader-failed")
                    (:id "3" :decision "grader-failed")
                    (:id "4" :decision "discarded")))
         (filtered (gptel-monitoring-agent--filter-by-decision results "grader-failed")))
    (should (= 2 (length filtered)))
    (should (cl-every (lambda (r) (equal "grader-failed" (plist-get r :decision)))
                      filtered))))

(ert-deftest test-monitoring-agent/group-by-backend-category ()
  "Should group results by backend and category, calculating keep-rates."
  (let* ((results '((:id "1" :backend "MiniMax" :category :programming :decision "kept")
                    (:id "2" :backend "MiniMax" :category :programming :decision "discarded")
                    (:id "3" :backend "DeepSeek" :category :agentic :decision "discarded")
                    (:id "4" :backend "DeepSeek" :category :agentic :decision "discarded")))
         (grouped (gptel-monitoring-agent--group-by-backend-category results)))
    (should (> (length grouped) 0))
    ;; Should have entries for (MiniMax, :programming) and (DeepSeek, :agentic)
    (should (cl-find-if (lambda (entry)
                          (and (equal "MiniMax" (car entry))
                               (equal :programming (cadr entry))))
                        grouped))))

(ert-deftest test-monitoring-agent/count-target-failures ()
  "Should count failures per target."
  (let* ((results '((:id "1" :target "file1.el" :decision "discarded")
                    (:id "2" :target "file1.el" :decision "discarded")
                    (:id "3" :target "file1.el" :decision "discarded")
                    (:id "4" :target "file2.el" :decision "discarded")
                    (:id "5" :target "file1.el" :decision "kept")))
         (counts (gptel-monitoring-agent--count-target-failures results)))
    (should (assoc "file1.el" counts))
    (should (= 3 (cdr (assoc "file1.el" counts))))
    (should (= 1 (cdr (assoc "file2.el" counts))))))

(provide 'test-gptel-monitoring-agent)

;;; test-gptel-monitoring-agent.el ends here
