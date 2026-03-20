;;; gptel-benchmark-principles.el --- Core principles: Eight Keys + Wu Xing (Five Elements) -*- lexical-binding: t; -*-

;; Copyright (C) 2025 David Wu
;; Author: David Wu
;; Version: 2.0.0
;; Keywords: ai, benchmark, principles, eight-keys, wu-xing

;;; Commentary:

;; Core principles module for benchmarking.
;; 
;; Principles are defined here but documented in mementum/knowledge/nucleus-patterns.md
;; which serves as the human-readable source of truth.
;;
;; This module provides:
;; - Eight Keys scoring functions
;; - Wu Xing diagnostic functions
;; - VSM mapping

;;; Code:

(require 'cl-lib)

;;; ============================================================================
;;; Customization
;;; ============================================================================

(defgroup gptel-benchmark-principles nil
  "Core principles for benchmarking."
  :group 'tools)

(defcustom gptel-benchmark-eight-keys-weights
  '((phi-vitality     . 1.0)
    (fractal-clarity  . 1.0)
    (epsilon-purpose  . 1.0)
    (tau-wisdom       . 1.0)
    (pi-synthesis     . 1.0)
    (mu-directness    . 1.0)
    (exists-truth     . 1.0)
    (forall-vigilance . 1.0))
  "Weights for each of the Eight Keys in scoring."
  :type '(alist :key-type symbol :value-type number)
  :group 'gptel-benchmark-principles)

;;; ============================================================================
;;; Eight Keys - see mementum/knowledge/nucleus-patterns.md for documentation
;;; ============================================================================

(defconst gptel-benchmark-eight-keys-definitions
  '((phi-vitality
     :symbol "φ"
     :name "Vitality"
     :element water
     :signals '("builds on discoveries" "adapts to new information" "progressive improvement"
                "non-repetitive" "evolves approach" "learns from feedback")
     :anti-patterns '("mechanical rephrasing" "circular logic" "repeated failed approaches"
                      "retrying same way" "static approach" "ignores feedback"))
    (fractal-clarity
     :symbol "fractal"
     :name "Clarity"
     :element metal
     :signals '("explicit assumptions" "testable definitions" "clear structure"
                "measurable criteria" "well-defined phases" "explicit success criteria")
     :anti-patterns '("vague terms" "handle properly" "look good" "ambiguous instructions"
                      "undefined terms" "implicit assumptions"))
    (epsilon-purpose
     :symbol "ε"
     :name "Purpose"
     :element wood
     :signals '("clear goals" "measurable outcomes" "actionable function"
                "specific objectives" "defined deliverables" "purposeful steps")
     :anti-patterns '("abstract descriptions" "no action" "unclear goals"
                      "meandering" "no measurable outcome" "purposeless"))
    (tau-wisdom
     :symbol "τ"
     :name "Wisdom"
     :element fire
     :signals '("planning before execution" "error prevention" "foresight"
                "plan file created" "risks identified" "proactive measures")
     :anti-patterns '("premature optimization" "reactive fixes" "no planning"
                      "jump to execution" "ignores risks" "short-sighted"))
    (pi-synthesis
     :symbol "π"
     :name "Synthesis"
     :element earth
     :signals '("connects findings" "integrates knowledge" "holistic view"
                "findings integrated" "connections noted" "synthesizes information")
     :anti-patterns '("fragmented thinking" "isolated facts" "disconnected"
                      "siloed information" "no integration" "missing connections"))
    (mu-directness
     :symbol "μ"
     :name "Directness"
     :element metal
     :signals '("direct communication" "no pleasantries" "efficient"
                "errors logged directly" "clear pass/fail" "concise")
     :anti-patterns '("polite evasion" "euphemisms" "softening language"
                      "vague language" "unnecessary words" "beating around bush"))
    (exists-truth
     :symbol "∃"
     :name "Truth"
     :element water
     :signals '("actual data" "evidence-based" "acknowledges uncertainty"
                "actual errors logged" "verification based on evidence" "honest assessment")
     :anti-patterns '("surface agreement" "wishful thinking" "assumptions over data"
                      "should work" "ignores evidence" "false confidence"))
    (forall-vigilance
     :symbol "∀"
     :name "Vigilance"
     :element earth
     :signals '("proactive error handling" "never repeat failures" "defensive"
                "3-strike protocol" "failed attempts tracked" "approach mutates")
     :anti-patterns '("accepting failures" "repeating mistakes" "no error handling"
                      "ignores edge cases" "gives up easily" "static after failure")))
  "Eight Keys definitions. See mementum/knowledge/nucleus-patterns.md for documentation.")

(defun gptel-benchmark-eight-keys-criteria (key)
  "Return criteria list for KEY."
  (list (format "Check %s alignment" key)))

(defun gptel-benchmark-eight-keys-signals (key)
  "Return positive signal patterns for KEY."
  (let ((def (alist-get key gptel-benchmark-eight-keys-definitions)))
    (if def (plist-get def :signals)
      (error "Unknown key: %s" key))))

(defun gptel-benchmark-eight-keys-anti-patterns (key)
  "Return anti-pattern list for KEY."
  (let ((def (alist-get key gptel-benchmark-eight-keys-definitions)))
    (if def (plist-get def :anti-patterns)
      (error "Unknown key: %s" key))))

(defun gptel-benchmark-eight-keys-element (key)
  "Return Wu Xing element for KEY."
  (let ((def (alist-get key gptel-benchmark-eight-keys-definitions)))
    (if def (plist-get def :element)
      (error "Unknown key: %s" key))))

(defun gptel-benchmark-eight-keys-score (output)
  "Score OUTPUT against all Eight Keys using local pattern matching.
Returns alist: ((key . score) ...) plus overall score."
  (let ((scores '())
        (total 0.0)
        (count 0))
    (dolist (key-def gptel-benchmark-eight-keys-definitions)
      (let* ((key (car key-def))
             (weight (or (alist-get key gptel-benchmark-eight-keys-weights) 1.0))
             (signals (plist-get key-def :signals))
             (anti-patterns (plist-get key-def :anti-patterns))
             (signal-score (gptel-benchmark--score-signals output signals))
             (anti-score (gptel-benchmark--score-anti-patterns output anti-patterns))
             (score (+ (* 0.6 signal-score) (* 0.4 anti-score))))
        (push (cons key score) scores)
        (cl-incf total (* score weight))
        (cl-incf count weight)))
    (push (cons 'overall (/ total count)) scores)
    (nreverse scores)))

(defun gptel-benchmark--score-signals (output signals)
  "Score OUTPUT based on presence of SIGNALS."
  (let ((matches 0)
        (total (length signals)))
    (dolist (signal signals)
      (when (string-match-p (regexp-quote signal) output)
        (cl-incf matches)))
    (if (zerop total) 0.5 (/ (float matches) (float total)))))

(defun gptel-benchmark--score-anti-patterns (output anti-patterns)
  "Score OUTPUT based on absence of ANTI-PATTERNS."
  (let ((violations 0)
        (total (length anti-patterns)))
    (dolist (pattern anti-patterns)
      (when (string-match-p (regexp-quote pattern) output)
        (cl-incf violations)))
    (if (zerop total) 0.5
      (max 0.0 (- 1.0 (/ (float violations) (float total)))))))

(defun gptel-benchmark-eight-keys-violations (output)
  "Detect all Eight Keys violations in OUTPUT."
  (let ((all-violations '()))
    (dolist (key-def gptel-benchmark-eight-keys-definitions)
      (let ((key (car key-def))
            (anti-patterns (plist-get key-def :anti-patterns))
            (violations '()))
        (dolist (pattern anti-patterns)
          (when (string-match-p (regexp-quote pattern) output)
            (push pattern violations)))
        (when violations
          (push (cons key (nreverse violations)) all-violations))))
    (nreverse all-violations)))

;;; ============================================================================
;;; Wu Xing - Five Elements - see mementum/knowledge/nucleus-patterns.md
;;; ============================================================================

(defconst gptel-benchmark-five-elements
  '((water
     :symbol "水"
     :name "Water"
     :vsm-level S5
     :generates wood
     :controls fire
     :controlled-by earth
     :generated-by metal)
    (wood
     :symbol "木"
     :name "Wood"
     :vsm-level S1
     :generates fire
     :controls earth
     :controlled-by metal
     :generated-by water)
    (fire
     :symbol "火"
     :name "Fire"
     :vsm-level S4
     :generates earth
     :controls metal
     :controlled-by water
     :generated-by wood)
    (earth
     :symbol "土"
     :name "Earth"
     :vsm-level S3
     :generates metal
     :controls water
     :controlled-by wood
     :generated-by fire)
    (metal
     :symbol "金"
     :name "Metal"
     :vsm-level S2
     :generates water
     :controls wood
     :controlled-by fire
     :generated-by earth))
  "Five Elements. See mementum/knowledge/nucleus-patterns.md for documentation.")

(defconst gptel-benchmark-generating-cycle
  '((water . wood) (wood . fire) (fire . earth) (earth . metal) (metal . water))
  "Generating cycle (相生). See mementum/knowledge/nucleus-patterns.md")

(defconst gptel-benchmark-controlling-cycle
  '((wood . earth) (earth . water) (water . fire) (fire . metal) (metal . wood))
  "Controlling cycle (相克). See mementum/knowledge/nucleus-patterns.md")

(defun gptel-benchmark-element-info (element)
  "Get info plist for ELEMENT."
  (alist-get element gptel-benchmark-five-elements))

(defun gptel-benchmark-element-generates (element)
  "Get what ELEMENT generates."
  (cdr (assoc element gptel-benchmark-generating-cycle)))

(defun gptel-benchmark-element-controls (element)
  "Get what ELEMENT controls."
  (cdr (assoc element gptel-benchmark-controlling-cycle)))

(defun gptel-benchmark-element-controlled-by (element)
  "Get what controls ELEMENT."
  (car (rassoc element gptel-benchmark-controlling-cycle)))

(defun gptel-benchmark-element-generated-by (element)
  "Get what generates ELEMENT."
  (car (rassoc element gptel-benchmark-generating-cycle)))

;;; ============================================================================
;;; VSM - Viable System Model - see mementum/knowledge/nucleus-patterns.md
;;; ============================================================================

(defconst gptel-benchmark-vsm-levels
  '((S5 :element water :name "Identity" :eight-keys (phi-vitality exists-truth))
    (S4 :element fire :name "Intelligence" :eight-keys (tau-wisdom))
    (S3 :element earth :name "Control" :eight-keys (pi-synthesis forall-vigilance))
    (S2 :element metal :name "Coordination" :eight-keys (fractal-clarity mu-directness))
    (S1 :element wood :name "Operations" :eight-keys (epsilon-purpose)))
  "VSM levels. See mementum/knowledge/nucleus-patterns.md for documentation.")

(defun gptel-benchmark-vsm-to-element (level)
  "Convert VSM LEVEL to Wu Xing element."
  (plist-get (alist-get level gptel-benchmark-vsm-levels) :element))

(defun gptel-benchmark-element-to-vsm (element)
  "Convert Wu Xing ELEMENT to VSM level."
  (car (cl-find-if (lambda (x) (eq (plist-get (cdr x) :element) element))
                   gptel-benchmark-vsm-levels)))

;;; ============================================================================
;;; Wu Xing Diagnostics
;;; ============================================================================

(defun gptel-benchmark-diagnose-elements (results)
  "Diagnose RESULTS using Wu Xing framework."
  (let ((diagnosis '()))
    (dolist (element '(water wood fire earth metal))
      (let ((score 0.5))
        (when results
          (let ((key (intern (format "%s-score" element))))
            (dolist (r results)
              (let ((scores (if (consp r) (cdr r) r)))
                (when (plist-get scores key)
                  (setq score (plist-get scores key)))))))
        (push (list :element element
                    :vsm (gptel-benchmark-element-to-vsm element)
                    :score score
                    :status (gptel-benchmark--element-status score))
              diagnosis)))
    (nreverse diagnosis)))

(defun gptel-benchmark--element-status (score)
  "Determine element status from SCORE."
  (cond ((>= score 0.9) 'excellent)
        ((>= score 0.7) 'healthy)
        ((>= score 0.5) 'adequate)
        ((>= score 0.3) 'deficient)
        (t 'critical)))

(defun gptel-benchmark-prescribe (diagnosis)
  "Generate Wu Xing-based prescriptions from DIAGNOSIS."
  (let ((prescriptions '()))
    (dolist (d diagnosis)
      (let* ((element (plist-get d :element))
             (status (plist-get d :status))
             (score (plist-get d :score)))
        (when (memq status '(deficient critical))
          (let ((prescription
                 (format "Strengthen %s by enhancing %s (generates). Avoid excess %s (controls)."
                         element
                         (gptel-benchmark-element-generated-by element)
                         (gptel-benchmark-element-controlled-by element))))
            (push (list :element element
                        :status status
                        :score score
                        :prescription prescription)
                  prescriptions)))))
    (nreverse prescriptions)))

(defun gptel-benchmark-wu-xing-report (results)
  "Generate Wu Xing diagnostic report for RESULTS."
  (interactive)
  (let* ((diagnosis (gptel-benchmark-diagnose-elements results))
         (prescriptions (gptel-benchmark-prescribe diagnosis)))
    (with-output-to-temp-buffer "*Wu Xing Report*"
      (princ "=== Wu Xing (Five Elements) Diagnostic Report ===\n\n")
      (princ "Element  | VSM | Status     | Score\n")
      (princ "---------|-----|------------|-------\n")
      (dolist (d diagnosis)
        (let* ((element (plist-get d :element))
               (info (gptel-benchmark-element-info element))
               (symbol (plist-get info :symbol))
               (vsm (plist-get d :vsm))
               (status (plist-get d :status))
               (score (* 100 (plist-get d :score))))
          (princ (format "%-8s | S%d  | %-10s | %3.0f%%\n"
                         (format "%s %s" symbol element)
                         (cl-position vsm '(S1 S2 S3 S4 S5))
                         status score))))
      (princ "\n--- Generating Cycle (相生) ---\n")
      (princ "Water→Wood→Fire→Earth→Metal→Water\n\n")
      (princ "--- Controlling Cycle (相克) ---\n")
      (princ "Wood→Earth→Water→Fire→Metal→Wood\n")
      (when prescriptions
        (princ "\n--- Prescriptions ---\n")
        (dolist (p prescriptions)
          (princ (format "\n%s: %s\n  → %s\n"
                         (plist-get p :element)
                         (plist-get p :status)
                         (plist-get p :prescription))))))))

;;; Provide

(provide 'gptel-benchmark-principles)

;;; gptel-benchmark-principles.el ends here