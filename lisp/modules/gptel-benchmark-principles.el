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

(defconst gptel-benchmark-eight-keys-subsystem-profiles
  `((:autotts t
              ;; AutoTTS research controller: foresight + evidence.
              ;; Wisdom (τ): planning before execution, error prevention.
              ;; Truth (∃): evidence-based parameter selection, honest confidence.
              :weights ((phi-vitality     . 0.7)
                        (fractal-clarity  . 0.5)
                        (epsilon-purpose  . 0.8)
                        (tau-wisdom       . 1.5)
                        (pi-synthesis     . 0.6)
                        (mu-directness    . 0.5)
                        (exists-truth     . 1.3)
                        (forall-vigilance . 0.8))
              :description "AutoTTS controller — optimizes research strategy parameters")
    (:autogo t
             ;; AutoGo champion league: organic improvement + defensive.
             ;; Vitality (φ): builds on discoveries, non-repetitive evolution.
             ;; Vigilance (∀): never repeat failures, defensive against regression.
             :weights ((phi-vitality     . 1.5)
                       (fractal-clarity  . 0.8)
                       (epsilon-purpose  . 0.7)
                       (tau-wisdom       . 0.5)
                       (pi-synthesis     . 0.5)
                       (mu-directness    . 0.6)
                       (exists-truth     . 0.8)
                       (forall-vigilance . 1.3))
             :description "AutoGo champion league — gates new strategies, prevents regression")
    (:self-evolve t
                  ;; Self-evolution cycle: holistic integration + actionable outcomes.
                  ;; Synthesis (π): connects findings, integrates knowledge across cycles.
                  ;; Purpose (ε): clear goals, measurable outcomes, purposeful steps.
                  :weights ((phi-vitality     . 0.8)
                            (fractal-clarity  . 0.7)
                            (epsilon-purpose  . 1.5)
                            (tau-wisdom       . 0.8)
                            (pi-synthesis     . 1.3)
                            (mu-directness    . 0.5)
                            (exists-truth     . 0.7)
                            (forall-vigilance . 0.9))
                  :description "Self-evolution cycle — synthesizes knowledge across experiment runs")
    (:meta-harness t
                   ;; Meta-harness strategy proposer: explicit + efficient.
                   ;; Clarity (fractal): explicit assumptions, testable definitions, clear structure.
                   ;; Directness (μ): efficient, no wasted effort, cuts through noise.
                   :weights ((phi-vitality     . 0.6)
                             (fractal-clarity  . 1.5)
                             (epsilon-purpose  . 0.8)
                             (tau-wisdom       . 0.6)
                             (pi-synthesis     . 0.7)
                             (mu-directness    . 1.3)
                             (exists-truth     . 0.6)
                             (forall-vigilance . 0.7))
                   :description "Meta-harness proposer — generates new strategy candidates")
    (:ontology t
               ;; Ontology router: actionable routing + evidence-based selection.
               ;; Purpose (ε): actionable function, measurable backend outcomes.
               ;; Truth (∃): evidence-based, data-driven backend selection.
               :weights ((phi-vitality     . 0.5)
                         (fractal-clarity  . 0.7)
                         (epsilon-purpose  . 1.5)
                         (tau-wisdom       . 0.6)
                         (pi-synthesis     . 0.5)
                         (mu-directness    . 0.8)
                         (exists-truth     . 1.3)
                         (forall-vigilance . 0.6))
               :description "Ontology router — data-driven backend selection per target category"))
  "Per-subsystem Eight Keys weight profiles.
Each element is a plist (tag t :weights ALIST :description STRING).
Weights >1.0 amplify the key; weights <1.0 de-emphasize it.
The default profile uses all 1.0 (equal weighting).")

(defvar gptel-benchmark--active-subsystem nil
  "Dynamically-bound subsystem keyword for Eight Keys weight selection.
When non-nil, `gptel-benchmark-eight-keys-score' uses the profile-specific
weights instead of the default equal weights.
Bind with `let' around the subsystem's scoring context.")

(defun gptel-benchmark-get-subsystem-weights (subsystem)
  "Return the Eight Keys weight alist for SUBSYSTEM.
SUBSYSTEM is a keyword: :autotts, :autogo, :self-evolve, :meta-harness, :ontology.
Returns default weights if SUBSYSTEM not recognized."
  (or (plist-get
       (cl-find subsystem gptel-benchmark-eight-keys-subsystem-profiles
                :key (lambda (p) (car p)))
       :weights)
      gptel-benchmark-eight-keys-weights))

;;; ============================================================================
;;; Eight Keys - see mementum/knowledge/nucleus-patterns.md for documentation
;;; ============================================================================

(defun gptel-benchmark--load-keys-from-skill ()
  "Load Eight Keys definitions from eight-keys-grader skill.
Returns list of key definitions or nil if skill not available.
Currently returns nil to use hardcoded fallback until skill
parsing is implemented."
  ;; TODO: Parse eight-keys-grader SKILL.md into proper list structure
  ;; The skill content is markdown text, not an Elisp data structure
  nil)

(defconst gptel-benchmark-eight-keys-definitions
  (or (gptel-benchmark--load-keys-from-skill)
      '((phi-vitality
         :symbol "φ"
         :name "Vitality"
         :element water
         :signals ("builds on discoveries" "adapts to new information" "progressive improvement"
                   "non-repetitive" "evolves approach" "learns from feedback")
         :anti-patterns ("mechanical rephrasing" "circular logic" "repeated failed approaches"
                         "retrying same way" "static approach" "ignores feedback"))
        (fractal-clarity
         :symbol "fractal"
         :name "Clarity"
         :element metal
         :signals ("explicit assumptions" "testable definitions" "clear structure"
                   "measurable criteria" "well-defined phases" "explicit success criteria")
         :anti-patterns ("vague terms" "handle properly" "look good" "ambiguous instructions"
                         "undefined terms" "implicit assumptions"))
        (epsilon-purpose
         :symbol "ε"
         :name "Purpose"
         :element wood
         :signals ("clear goals" "measurable outcomes" "actionable function"
                   "specific objectives" "defined deliverables" "purposeful steps")
         :anti-patterns ("abstract descriptions" "no action" "unclear goals"
                         "meandering" "no measurable outcome" "purposeless"))
        (tau-wisdom
         :symbol "τ"
         :name "Wisdom"
         :element fire
         :signals ("planning before execution" "error prevention" "foresight"
                   "plan file created" "risks identified" "proactive measures")
         :anti-patterns ("premature optimization" "reactive fixes" "no planning"
                         "jump to execution" "ignores risks" "short-sighted"))
        (pi-synthesis
         :symbol "π"
         :name "Synthesis"
         :element earth
         :signals ("connects findings" "integrates knowledge" "holistic view"
                   "findings integrated" "connections noted" "synthesizes information")
         :anti-patterns ("fragmented thinking" "isolated facts" "disconnected"
                         "siloed information" "no integration" "missing connections"))
        (mu-directness
         :symbol "μ"
         :name "Directness"
         :element metal
         :signals ("direct communication" "no pleasantries" "efficient"
                   "errors logged directly" "clear pass/fail" "concise")
         :anti-patterns ("polite evasion" "euphemisms" "softening language"
                         "vague language" "unnecessary words" "beating around bush"))
        (exists-truth
         :symbol "∃"
         :name "Truth"
         :element water
         :signals ("actual data" "evidence-based" "acknowledges uncertainty"
                   "actual errors logged" "verification based on evidence" "honest assessment")
         :anti-patterns ("surface agreement" "wishful thinking" "assumptions over data"
                         "should work" "ignores evidence" "false confidence"))
        (forall-vigilance
         :symbol "∀"
         :name "Vigilance"
         :element earth
         :signals ("proactive error handling" "never repeat failures" "defensive"
                   "3-strike protocol" "failed attempts tracked" "approach mutates")
         :anti-patterns ("accepting failures" "repeating mistakes" "no error handling"
                         "ignores edge cases" "gives up easily" "static after failure")))
      "Eight Keys definitions.
See mementum/knowledge/nucleus-patterns.md for documentation.")
  )

(defun gptel-benchmark-eight-keys-criteria (key)
  "Return criteria list for KEY."
  (list (format "Check %s alignment" key)))

(defvar gptel-benchmark--key-property-cache (make-hash-table :test 'equal)
  "Cache for eight-keys property lookups.
Maps (key . property) cons cells to cached values.")

(defun gptel-benchmark--get-key-property (key property)
  "Get PROPERTY for KEY from Eight Keys definitions.
Uses memoization cache to avoid redundant lookups.
Helper to reduce duplication in accessor functions."
  (unless (symbolp key)
    (error "Expected symbol for key, got: %s" (type-of key)))
  (let ((cache-key (cons key property)))
    (or (gethash cache-key gptel-benchmark--key-property-cache)
        (let* ((def (alist-get key gptel-benchmark-eight-keys-definitions))
               (value (if def (plist-get def property)
                        (error "Unknown key: %s" key))))
          (puthash cache-key value gptel-benchmark--key-property-cache)
          value))))

(defun gptel-benchmark-eight-keys-signals (key)
  "Return positive signal patterns for KEY."
  (gptel-benchmark--get-key-property key :signals))

(defun gptel-benchmark-eight-keys-anti-patterns (key)
  "Return anti-pattern list for KEY."
  (gptel-benchmark--get-key-property key :anti-patterns))

(defun gptel-benchmark-eight-keys-element (key)
  "Return Wu Xing element for KEY."
  (gptel-benchmark--get-key-property key :element))

(defconst gptel-benchmark--task-type-key-mapping
  '((refactoring
     (fractal-clarity epsilon-purpose mu-directness exists-truth)
     "Code refactoring: clarity, purpose, directness, truth")
    (bug-fix
     (forall-vigilance exists-truth fractal-clarity epsilon-purpose)
     "Bug fix: vigilance, truth, clarity, purpose")
    (performance
     (phi-vitality exists-truth fractal-clarity epsilon-purpose)
     "Performance optimization: vitality, truth, clarity, purpose")
    (feature
     (tau-wisdom phi-vitality pi-synthesis fractal-clarity epsilon-purpose exists-truth forall-vigilance mu-directness)
     "Feature development: all keys")
    (validation
     (forall-vigilance exists-truth fractal-clarity)
     "Validation/safety: vigilance, truth, clarity")
    (default
     (phi-vitality fractal-clarity epsilon-purpose tau-wisdom pi-synthesis mu-directness exists-truth forall-vigilance)
     "Default: all keys"))
  "Mapping from task types to relevant Eight Keys.
Each entry: (task-type (keys...) description).")

(defun gptel-benchmark--detect-task-type (hypothesis)
  "Detect task type from HYPOTHESIS using keyword matching.
Returns a symbol: refactoring, bug-fix, performance, feature,
validation, or default."
  (when (stringp hypothesis)
    (let ((h (downcase hypothesis)))
      (cond
       ((or (string-match-p "\\bvalidation\\|\\bguard\\|\\bdefensive\\|\\bnil-check\\|\\bsafety\\|\\bempty string\\|\\bnull check\\|\\bnil-coalesc" h))
        'validation)
       ((or (string-match-p "\\bfix\\|\\bbug\\|\\berror\\|\\bprevent\\|\\bcrash\\|\\bruntime error\\|\\bhandle\\|\\bcorrect" h))
        'bug-fix)
       ((or (string-match-p "\\bperformance\\|\\boptimize\\|\\bcache\\|\\bspeed\\|\\bfast\\|\\bmemory\\|\\bleak\\|\\befficiency\\|\\btoken usage" h))
        'performance)
       ((or (string-match-p "\\brefactor\\|\\bextract\\|\\bsimplify\\|\\bduplicate\\|\\bclarity\\|\\brename\\|\\bhelper\\|\\bDRY\\|\\bredundant\\|\\bremove duplication" h))
        'refactoring)
       ((or (string-match-p "\\badd\\|\\bnew\\|\\bfeature\\|\\bsupport\\|\\bimplement\\|\\bcreate\\|\\bintroduce" h))
        'feature)
       (t 'default)))))

(defun gptel-benchmark-eight-keys-score (output &optional hypothesis)
  "Score OUTPUT against relevant Eight Keys using local pattern matching.
If HYPOTHESIS is provided, detect task type and only score relevant keys.
Returns alist: ((key . score) ...) plus overall score.
Weights are drawn from `gptel-benchmark--active-subsystem' if bound,
otherwise the default `gptel-benchmark-eight-keys-weights'."
  (gptel-benchmark--eight-keys-score-with-weights
   output hypothesis
   (if (and (boundp 'gptel-benchmark--active-subsystem)
            gptel-benchmark--active-subsystem)
       (gptel-benchmark-get-subsystem-weights gptel-benchmark--active-subsystem)
     gptel-benchmark-eight-keys-weights)))

(defun gptel-benchmark-eight-keys-score-for (output subsystem &optional hypothesis)
  "Score OUTPUT using subsystem-specific Eight Keys weights.
SUBSYSTEM is a keyword: :autotts, :autogo, :self-evolve, :meta-harness, :ontology.
Uses `gptel-benchmark-get-subsystem-weights' to look up the profile.
Returns alist: ((key . score) ...) plus overall score."
  (gptel-benchmark--eight-keys-score-with-weights
   output hypothesis
   (gptel-benchmark-get-subsystem-weights subsystem)))

(defun gptel-benchmark--eight-keys-score-with-weights (output hypothesis weights)
  "Core scoring engine.  Uses WEIGHTS instead of the global default.
Internal helper shared by score and score-for."
  (let* ((task-type (gptel-benchmark--detect-task-type hypothesis))
         (relevant-keys (or (cadr (assoc task-type gptel-benchmark--task-type-key-mapping))
                            (cadr (assoc 'default gptel-benchmark--task-type-key-mapping))))
         (scores '())
         (total 0.0)
         (count 0))
    (dolist (key-def gptel-benchmark-eight-keys-definitions)
      (let* ((key (car key-def))
             (def-plist (cdr key-def))
             (weight (or (alist-get key weights) 1.0))
             (signals (plist-get def-plist :signals))
             (anti-patterns (plist-get def-plist :anti-patterns)))
        (if (memq key relevant-keys)
            (let* ((signal-score (gptel-benchmark--score-signals output signals))
                   (anti-score (gptel-benchmark--score-anti-patterns output anti-patterns))
                   (score (+ (* 0.6 signal-score) (* 0.4 anti-score))))
              (push (cons key score) scores)
              (cl-incf total (* score weight))
              (cl-incf count weight))
          (push (cons key 'not-applicable) scores))))
    (push (cons 'overall (if (> count 0) (/ total count) 0.0)) scores)
    (nreverse scores)))

(defun gptel-benchmark-eight-keys-summary (scores)
  "Generate human-readable summary of Eight Keys SCORES.
SCORES is the alist returned by gptel-benchmark-eight-keys-score."
  (let ((parts '()))
    (dolist (key-def gptel-benchmark-eight-keys-definitions)
      (let* ((key (car key-def))
             (def-plist (cdr key-def))
             (symbol (plist-get def-plist :symbol))
             (name (plist-get def-plist :name))
             (score (alist-get key scores)))
        (push (format "%s %s: %.0f%%" symbol name (* 100 (or score 0))) parts)))
    (let ((overall (alist-get 'overall scores)))
      (push (format "Overall: %.0f%%" (* 100 (or overall 0))) parts))
    (mapconcat #'identity (nreverse parts) "\n")))

(defun gptel-benchmark-eight-keys-weakest (scores &optional n)
  "Return N weakest keys from SCORES alist.
Excludes `overall' from results.
Returns list of (key . score) pairs sorted ascending by score."
  (let* ((key-scores (cl-remove-if (lambda (x) (eq (car x) 'overall)) scores))
         (count (length key-scores))
         (take (min (or n 2) count)))
    (cl-subseq (sort key-scores (lambda (a b) (< (cdr a) (cdr b)))) 0 take)))

(defun gptel-benchmark-eight-keys-weakest-with-signals (scores &optional n)
  "Return N weakest keys with their positive signals.
For hypothesis generation targeting weak areas."
  (let* ((weakest (gptel-benchmark-eight-keys-weakest scores n))
         (result '()))
    (dolist (item weakest)
      (let* ((key (car item))
             (score (cdr item))
             (signals-raw (gptel-benchmark-eight-keys-signals key))
             (signals (if (and (listp signals-raw) (eq (car signals-raw) 'quote))
                          (cadr signals-raw)
                        signals-raw)))
        (push (list :key key :score score :signals (seq-take signals 3)) result)))
    (nreverse result)))

(defun gptel-benchmark--score-signals (output signals)
  "Score OUTPUT based on presence of SIGNALS.
Returns 0.5 if OUTPUT or SIGNALS is nil/empty."
  (if (or (null signals) (not (listp signals)) (not (stringp output)))
      0.5
    (let ((matches 0)
          (total (length signals)))
      (dolist (signal signals)
        (when (string-match-p (regexp-quote signal) output)
          (cl-incf matches)))
      (if (zerop total) 0.5 (/ (float matches) (float total))))))

(defun gptel-benchmark--score-anti-patterns (output anti-patterns)
  "Score OUTPUT based on absence of ANTI-PATTERNS.
Returns 0.5 if OUTPUT or ANTI-PATTERNS is nil/empty."
  (if (or (null anti-patterns) (not (listp anti-patterns)) (not (stringp output)))
      0.5
    (let ((violations 0)
          (total (length anti-patterns)))
      (dolist (pattern anti-patterns)
        (when (string-match-p (regexp-quote pattern) output)
          (cl-incf violations)))
      (if (zerop total) 0.5
        (max 0.0 (- 1.0 (/ (float violations) (float total))))))))

(defun gptel-benchmark-eight-keys-violations (output)
  "Detect all Eight Keys violations in OUTPUT."
  (let ((all-violations '()))
    (dolist (key-def gptel-benchmark-eight-keys-definitions)
      (let* ((key (car key-def))
             (def-plist (cdr key-def))
             (anti-patterns (plist-get def-plist :anti-patterns))
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
  (unless (symbolp element)
    (error "Expected symbol for element, got: %s" (type-of element)))
  (alist-get element gptel-benchmark-five-elements))

(defun gptel-benchmark-element-generates (element)
  "Get what ELEMENT generates."
  (cdr (assoc element gptel-benchmark-generating-cycle)))

(defun gptel-benchmark-element-controls (element)
  "Get what ELEMENT controls."
  (cdr (assoc element gptel-benchmark-controlling-cycle)))

(defun gptel-benchmark-element-controlled-by (element)
  "Get what controls ELEMENT.
Returns ELEMENT as fallback if not found in controlling cycle."
  (or (car (rassoc element gptel-benchmark-controlling-cycle)) element))

(defun gptel-benchmark-element-generated-by (element)
  "Get what generates ELEMENT.
Returns ELEMENT as fallback if not found in generating cycle."
  (or (car (rassoc element gptel-benchmark-generating-cycle)) element))

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
  "Convert Wu Xing ELEMENT to VSM level.
Returns nil if ELEMENT is not a valid element symbol."
  (when (symbolp element)
    (car (cl-find-if (lambda (x) (eq (plist-get (cdr x) :element) element))
                     gptel-benchmark-vsm-levels))))

;;; ============================================================================
;;; Wu Xing Diagnostics
;;; ============================================================================

(defun gptel-benchmark-diagnose-elements (results)
  "Diagnose RESULTS using Wu Xing framework."
  (let ((diagnosis '()))
    (dolist (element '(water wood fire earth metal))
      (let ((score 0.5))
        (when results
          (let ((key (format "%s-score" element)))
            (dolist (r results)
              (let ((scores (if (consp r) (cdr r) r)))
                (let ((score-value (and (listp scores) (alist-get (intern key) scores))))
                  (when (numberp score-value)
                    (setq score score-value)))))))
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
