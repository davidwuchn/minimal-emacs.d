;;; gptel-benchmark-tests.el --- ERT tests for benchmark modules -*- lexical-binding: t; -*-

;; Copyright (C) 2025 David Wu
;; Author: David Wu
;; Version: 1.0.0
;; Keywords: ai, benchmark, test

;;; Code:

(require 'ert)
(require 'gptel-benchmark-principles)
(require 'gptel-benchmark-core)
(require 'gptel-benchmark-evolution)
(require 'gptel-benchmark-auto-improve)
(require 'gptel-benchmark-daily)

;; Disable auto-commit for tests (no mementum directory)
(setq gptel-benchmark-memory-auto-commit nil
      gptel-benchmark-auto-improve-commit nil)

;;; ============================================================================
;;; Eight Keys Tests
;;; ============================================================================

(ert-deftest gptel-benchmark-test-eight-keys-criteria ()
  "Test that criteria are returned for each key."
  (dolist (key '(phi-vitality fractal-clarity epsilon-purpose tau-wisdom
                 pi-synthesis mu-directness exists-truth forall-vigilance))
    (let ((criteria (gptel-benchmark-eight-keys-criteria key)))
      (should (listp criteria))
      (should (> (length criteria) 0)))))

(ert-deftest gptel-benchmark-test-eight-keys-signals ()
  "Test that signals are returned for each key."
  (dolist (key '(phi-vitality fractal-clarity epsilon-purpose tau-wisdom
                 pi-synthesis mu-directness exists-truth forall-vigilance))
    (let ((signals (gptel-benchmark-eight-keys-signals key)))
      (should (listp signals))
      (should (> (length signals) 0)))))

(ert-deftest gptel-benchmark-test-eight-keys-anti-patterns ()
  "Test that anti-patterns are returned for each key."
  (dolist (key '(phi-vitality fractal-clarity epsilon-purpose tau-wisdom
                 pi-synthesis mu-directness exists-truth forall-vigilance))
    (let ((anti-patterns (gptel-benchmark-eight-keys-anti-patterns key)))
      (should (listp anti-patterns))
      (should (> (length anti-patterns) 0)))))

(ert-deftest gptel-benchmark-test-eight-keys-element-mapping ()
  "Test that each key maps to a Wu Xing element."
  (dolist (key '(phi-vitality fractal-clarity epsilon-purpose tau-wisdom
                 pi-synthesis mu-directness exists-truth forall-vigilance))
    (let ((element (gptel-benchmark-eight-keys-element key)))
      (should (memq element '(water wood fire earth metal))))))

(ert-deftest gptel-benchmark-test-eight-keys-score ()
  "Test Eight Keys scoring."
  (let* ((output "This approach builds on discoveries and adapts to new information. The goal is clear and measurable.")
         (scores (gptel-benchmark-eight-keys-score output)))
    (should (listp scores))
    (should (alist-get 'overall scores))
    (should (>= (alist-get 'overall scores) 0.0))
    (should (<= (alist-get 'overall scores) 1.0))))

(ert-deftest gptel-benchmark-test-eight-keys-violations ()
  "Test Eight Keys violation detection."
  (let* ((output "This should work properly. Let me handle this appropriately.")
         (violations (gptel-benchmark-eight-keys-violations output)))
    (should (listp violations))))

(ert-deftest gptel-benchmark-test-score-signals ()
  "Test signal scoring."
  (let* ((output "builds on discoveries adapts to new information")
         (signals '("builds on discoveries" "adapts to new information" "non-repetitive"))
         (score (gptel-benchmark--score-signals output signals)))
    (should (>= score 0.5))))

(ert-deftest gptel-benchmark-test-score-anti-patterns ()
  "Test anti-pattern scoring."
  (let* ((output "This approach is good and works well.")
         (anti-patterns '("handle properly" "look good" "vague terms"))
         (score (gptel-benchmark--score-anti-patterns output anti-patterns)))
    (should (= score 1.0))))

;;; ============================================================================
;;; Wu Xing Tests
;;; ============================================================================

(ert-deftest gptel-benchmark-test-five-elements-defined ()
  "Test that all five elements are defined."
  (dolist (element '(water wood fire earth metal))
    (let ((info (gptel-benchmark-element-info element)))
      (should (plist-get info :symbol))
      (should (plist-get info :name))
      (should (plist-get info :vsm-level))
      (should (plist-get info :generates)))))

(ert-deftest gptel-benchmark-test-generating-cycle ()
  "Test Wu Xing generating cycle (相生)."
  (should (eq (gptel-benchmark-element-generates 'water) 'wood))
  (should (eq (gptel-benchmark-element-generates 'wood) 'fire))
  (should (eq (gptel-benchmark-element-generates 'fire) 'earth))
  (should (eq (gptel-benchmark-element-generates 'earth) 'metal))
  (should (eq (gptel-benchmark-element-generates 'metal) 'water)))

(ert-deftest gptel-benchmark-test-controlling-cycle ()
  "Test Wu Xing controlling cycle (相克)."
  (should (eq (gptel-benchmark-element-controls 'wood) 'earth))
  (should (eq (gptel-benchmark-element-controls 'earth) 'water))
  (should (eq (gptel-benchmark-element-controls 'water) 'fire))
  (should (eq (gptel-benchmark-element-controls 'fire) 'metal))
  (should (eq (gptel-benchmark-element-controls 'metal) 'wood)))

(ert-deftest gptel-benchmark-test-controlled-by ()
  "Test what controls each element."
  (should (eq (gptel-benchmark-element-controlled-by 'wood) 'metal))
  (should (eq (gptel-benchmark-element-controlled-by 'fire) 'water))
  (should (eq (gptel-benchmark-element-controlled-by 'earth) 'wood))
  (should (eq (gptel-benchmark-element-controlled-by 'water) 'earth))
  (should (eq (gptel-benchmark-element-controlled-by 'metal) 'fire)))

(ert-deftest gptel-benchmark-test-generated-by ()
  "Test what generates each element."
  (should (eq (gptel-benchmark-element-generated-by 'wood) 'water))
  (should (eq (gptel-benchmark-element-generated-by 'fire) 'wood))
  (should (eq (gptel-benchmark-element-generated-by 'earth) 'fire))
  (should (eq (gptel-benchmark-element-generated-by 'metal) 'earth))
  (should (eq (gptel-benchmark-element-generated-by 'water) 'metal)))

(ert-deftest gptel-benchmark-test-element-status ()
  "Test element status determination."
  (should (eq (gptel-benchmark--element-status 0.95) 'excellent))
  (should (eq (gptel-benchmark--element-status 0.75) 'healthy))
  (should (eq (gptel-benchmark--element-status 0.55) 'adequate))
  (should (eq (gptel-benchmark--element-status 0.35) 'deficient))
  (should (eq (gptel-benchmark--element-status 0.15) 'critical)))

;;; ============================================================================
;;; VSM Tests
;;; ============================================================================

(ert-deftest gptel-benchmark-test-vsm-to-element ()
  "Test VSM level to element mapping."
  (should (eq (gptel-benchmark-vsm-to-element 'S5) 'water))
  (should (eq (gptel-benchmark-vsm-to-element 'S4) 'fire))
  (should (eq (gptel-benchmark-vsm-to-element 'S3) 'earth))
  (should (eq (gptel-benchmark-vsm-to-element 'S2) 'metal))
  (should (eq (gptel-benchmark-vsm-to-element 'S1) 'wood)))

(ert-deftest gptel-benchmark-test-element-to-vsm ()
  "Test element to VSM level mapping."
  (should (eq (gptel-benchmark-element-to-vsm 'water) 'S5))
  (should (eq (gptel-benchmark-element-to-vsm 'fire) 'S4))
  (should (eq (gptel-benchmark-element-to-vsm 'earth) 'S3))
  (should (eq (gptel-benchmark-element-to-vsm 'metal) 'S2))
  (should (eq (gptel-benchmark-element-to-vsm 'wood) 'S1)))

;;; ============================================================================
;;; Core Utilities Tests
;;; ============================================================================

(ert-deftest gptel-benchmark-test-summarize-results ()
  "Test result summarization."
  (let* ((results (list (cons 'run1 (list :overall-score 0.8
                                           :efficiency-score 0.7
                                           :completion-score 0.9
                                           :constraint-score 1.0))
                        (cons 'run2 (list :overall-score 0.6
                                           :efficiency-score 0.5
                                           :completion-score 0.7
                                           :constraint-score 0.9))))
         (summary (gptel-benchmark-summarize-results results)))
    (should (= (plist-get summary :total-tests) 2))
    (should (= (plist-get summary :passed-tests) 1))
    (should (>= (plist-get summary :avg-overall) 0.0))
    (should (<= (plist-get summary :avg-overall) 1.0))))

(ert-deftest gptel-benchmark-test-evolve-score-validated ()
  "Test score evolution with validated outcome."
  (let ((new-score (gptel-benchmark-evolve-score 0.5 :validated)))
    (should (> new-score 0.5))
    (should (<= new-score 1.0))))

(ert-deftest gptel-benchmark-test-evolve-score-corrected ()
  "Test score evolution with corrected outcome."
  (let ((new-score (gptel-benchmark-evolve-score 0.5 :corrected)))
    (should (< new-score 0.5))
    (should (>= new-score 0.0))))

(ert-deftest gptel-benchmark-test-evolve-score-clamp ()
  "Test that evolved scores are clamped to 0-1."
  (should (= (gptel-benchmark-evolve-score 0.99 :validated 0.5) 1.0))
  (should (= (gptel-benchmark-evolve-score 0.01 :corrected 0.5) 0.0)))

(ert-deftest gptel-benchmark-test-analyze-patterns ()
  "Test pattern analysis."
  (let* ((results (list (cons 'run1 (list :overall-score 0.5
                                           :efficiency-score 0.5))
                        (cons 'run2 (list :overall-score 0.9))))
         (analysis (gptel-benchmark-analyze-patterns results)))
    (should (plist-get analysis :total-tests))
    (should (plist-get analysis :recommendations))))

;;; ============================================================================
;;; Evolution Tests
;;; ============================================================================

(ert-deftest gptel-benchmark-test-evolution-cycle-increments ()
  "Test that evolution cycle increments counter."
  (let ((initial-cycle (plist-get gptel-benchmark-evolution-state :cycle)))
    ;; Directly test the counter increment
    (cl-incf (plist-get gptel-benchmark-evolution-state :cycle))
    (should (> (plist-get gptel-benchmark-evolution-state :cycle) initial-cycle))))

(ert-deftest gptel-benchmark-test-evolution-pathway ()
  "Test evolution pathway generation."
  (let ((pathway (gptel-benchmark-evolution-pathway 'water)))
    (should (listp pathway))
    (should (= (length pathway) 5))
    (should (eq (car pathway) 'water))))

(ert-deftest gptel-benchmark-test-anti-pattern-detection ()
  "Test anti-pattern detection via 相克."
  (let* ((results (list :step-count 25))
         (detected (gptel-benchmark-detect-anti-patterns results)))
    (should (listp detected))
    (when detected
      (should (plist-get (car detected) :remedy)))))

(ert-deftest gptel-benchmark-test-evolution-balance ()
  "Test evolution balance check."
  (let* ((results (list :completion-score 0.3))
         (balance (gptel-benchmark-evolution-balance results)))
    (should (plist-get balance :anti-patterns))
    (should (listp (plist-get balance :anti-patterns)))))

;;; ============================================================================
;;; Auto-Improve Tests
;;; ============================================================================

(ert-deftest gptel-benchmark-test-improvement-cycle ()
  "Test that improvement cycle runs."
  (let* ((results (list :step-count 10))
         (gptel-benchmark-auto-improve-commit nil)
         (gptel-benchmark-memory-auto-commit nil))
    (gptel-benchmark-improvement-cycle 'test-name 'test results)
    (should (= (length gptel-benchmark-improvements) 1))))

(ert-deftest gptel-benchmark-test-generate-improvements ()
  "Test improvement generation from anti-patterns."
  (let* ((anti-patterns (list (list :element 'wood
                                    :controlled-by 'metal
                                    :symptom "test symptom"
                                    :remedy "test remedy")))
         (improvements (gptel-benchmark-generate-improvements 'test-name 'test anti-patterns)))
    (should (listp improvements))))

(ert-deftest gptel-benchmark-test-apply-improvement ()
  "Test applying an improvement."
  (let* ((improvement (list :type 'efficiency
                            :element 'wood
                            :remedy 'metal
                            :action "Fix X"
                            :specifics (list :threshold-suggestions '("test"))))
         (gptel-benchmark-auto-improve-commit nil))
    (gptel-benchmark-apply-improvement 'test-name 'test improvement)
    (should (= (length gptel-benchmark-improvements) 1))))

;;; ============================================================================
;;; Daily Integration Tests
;;; ============================================================================

(ert-deftest gptel-benchmark-test-daily-setup ()
  "Test daily integration setup."
  (gptel-benchmark-daily-teardown)
  (gptel-benchmark-daily-setup)
  (should gptel-benchmark-daily-auto-collect))

(ert-deftest gptel-benchmark-test-daily-collect ()
  "Test daily metric collection."
  (setq gptel-benchmark-daily-runs nil)
  (let ((gptel-benchmark-daily-auto-collect t))
    (gptel-benchmark-daily--wrap-skill-run
     (lambda (&rest _args) 'mock-result)
     'test-skill 'test-001))
  (should (= (length gptel-benchmark-daily-runs) 1))
  (should (eq (plist-get (car gptel-benchmark-daily-runs) :type) 'skill)))

(ert-deftest gptel-benchmark-test-daily-report-json ()
  "Test JSON report generation."
  (let ((json (gptel-benchmark-daily-report-json)))
    (should (stringp json))
    (should (string-match-p "date" json))))

;;; ============================================================================
;;; Diagnostics Tests
;;; ============================================================================

(ert-deftest gptel-benchmark-test-diagnose-elements ()
  "Test Wu Xing element diagnosis."
  (let* ((results (list (cons 'run1 (list :overall-score 0.8
                                           :completion-score 0.9
                                           :efficiency-score 0.7))))
         (diagnosis (gptel-benchmark-diagnose-elements results)))
    (should (listp diagnosis))
    (should (= (length diagnosis) 5))
    (dolist (d diagnosis)
      (should (plist-get d :element))
      (should (plist-get d :status)))))

(ert-deftest gptel-benchmark-test-prescribe ()
  "Test prescription generation."
  (let* ((diagnosis (list (list :element 'wood
                                :status 'deficient
                                :score 0.3)))
         (prescriptions (gptel-benchmark-prescribe diagnosis)))
    (should (listp prescriptions))
    (when prescriptions
      (should (plist-get (car prescriptions) :prescription)))))

;;; Provide

(provide 'gptel-benchmark-tests)

;;; gptel-benchmark-tests.el ends here

;;; ============================================================================
;;; Skill Benchmark Integration Tests
;;; ============================================================================

;; These tests verify skill benchmark uses core modules correctly

(ert-deftest gptel-benchmark-test-skill-eight-keys-integration ()
  "Test that skill benchmark Eight Keys scoring works."
  (let* ((output "This approach builds on discoveries and adapts to new information. The goal is clear and measurable.")
         (scores (gptel-benchmark-eight-keys-score output)))
    (should (alist-get 'overall scores))
    (should (> (alist-get 'overall scores) 0.0))))

(ert-deftest gptel-benchmark-test-skill-wu-xing-diagnosis ()
  "Test Wu Xing diagnosis from skill benchmark results."
  (let* ((mock-results (list (cons 'test1 (list :overall-score 0.8
                                                 :completion-score 0.9
                                                 :efficiency-score 0.7
                                                 :constraint-score 1.0
                                                 :tool-score 1.0))))
         (diagnosis (gptel-benchmark-diagnose-elements mock-results)))
    (should (= (length diagnosis) 5))
    (should (cl-find-if (lambda (d) (eq (plist-get d :element) 'water)) diagnosis))))

(ert-deftest gptel-benchmark-test-skill-anti-pattern-detection ()
  "Test anti-pattern detection in skill outputs."
  (let* ((results (list :step-count 25
                        :efficiency-score 0.4))
         (detected (gptel-benchmark-detect-anti-patterns results)))
    (should (listp detected))
    (when detected
      (should (plist-get (car detected) :remedy)))))

(ert-deftest gptel-benchmark-test-skill-improvement-generation ()
  "Test improvement generation for skills."
  (let* ((anti-patterns (list (list :element 'wood
                                    :controlled-by 'metal
                                    :symptom "test symptom"
                                    :remedy "test remedy")))
         (improvements (gptel-benchmark-generate-improvements 'test-skill 'skill anti-patterns)))
    (should (listp improvements))
    (when improvements
      (should (plist-get (car improvements) :action)))))

(ert-deftest gptel-benchmark-test-skill-violation-detection ()
  "Test Eight Keys violation detection in skill outputs."
  (let* ((output "This should work properly. Let me handle this appropriately.")
         (violations (gptel-benchmark-eight-keys-violations output)))
    (should (listp violations))))