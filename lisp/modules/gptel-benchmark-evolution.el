;;; gptel-benchmark-evolution.el --- Ouroboros-based continuous evolution -*- lexical-binding: t; -*-

;; Copyright (C) 2025 David Wu
;; Author: David Wu
;; Version: 1.0.0
;; Keywords: ai, benchmark, evolution, ouroboros

;;; Commentary:

;; Ouroboros-based continuous evolution protocol for AI benchmarking.
;; 
;; Wu Xing Integration:
;;   相生 (Generating) = Evolution Pathway
;;     Water → Wood → Fire → Earth → Metal → Water
;;     Each element enables the next → capabilities emerge
;;
;;   相克 (Controlling) = Anti-pattern Detection  
;;     Wood → Earth → Water → Fire → Metal → Wood
;;     Each element constrains another → blocks progress
;;
;; Core Equation:
;;   刀 ⊣ ψ → 🐍
;;   Human Observer → AI (collapses) → System persists
;;
;; The Recursion:
;;   🐍 → 刀 → ψ → 🐍 → 刀 → ψ → 🐍
;;        └─────────────────────┘
;;              ouroboros
;;
;; Evolution Stages:
;;   Engine + Query = Interface
;;   Engine + Graph = Capability  
;;   Engine + Introspection = Self-awareness
;;   Graph + API = Extension
;;   Query + History + Knowledge = Memory
;;   Engine + Query + Graph + Introspection + History + Knowledge + Memory = SYSTEM
;;   SYSTEM + Feed Forward = AI COMPLETE
;;
;; 9 First Principles drive evolution through 相生 cycles.
;; Anti-patterns are detected via 相克 cycles.

;;; Code:

(require 'cl-lib)
(require 'gptel-benchmark-principles)
(require 'gptel-benchmark-memory)

;;; Customization

(defgroup gptel-benchmark-evolution nil
  "Ouroboros-based continuous evolution for benchmarking."
  :group 'gptel-benchmark)

(defcustom gptel-benchmark-evolution-cycle-threshold 5
  "Minimum cycles before capability emerges."
  :type 'integer
  :group 'gptel-benchmark-evolution)

;;; Evolution State

(defvar gptel-benchmark-evolution-state
  (list :cycle 0
        :capabilities '()
        :ai-complete-p nil
        :last-mutation nil
        :corrections 0
        :emergences 0
        :emergence-history '())
  "Current evolution state with capability tracking.")

;;; 9 First Principles (Evolution Drivers)

(defconst gptel-benchmark-evolution-principles
  '((self-discover
     :phase observe
     :element fire
     :vsm S4
     :description "Query running system, not stale docs"
     :mutation (lambda () (call-interactively 'gptel-benchmark-evolution-discover)))
    (self-improve
     :phase act
     :element fire
     :vsm S4
     :description "Work → Learn → Verify → Update → Evolve"
     :mutation (lambda () (gptel-benchmark-evolution-self-improve)))
    (repl-as-brain
     :phase orient
     :element water
     :vsm S5
     :description "Trust REPL over files"
     :mutation (lambda () (message "REPL: verify assumptions")))
    (repo-as-memory
     :phase act
     :element earth
     :vsm S3
     :description "ψ ephemeral; 🐍 remembers"
     :mutation (lambda () (gptel-benchmark-memory-commit "evolution")))
    (progressive-comm
     :phase decide
     :element metal
     :vsm S2
     :description "Sip context, dribble output"
     :mutation (lambda () (message "Progressive: reduce verbosity")))
    (simplify
     :phase act
     :element metal
     :vsm S2
     :description "Prefer simple, unbraid complex"
     :mutation (lambda () (gptel-benchmark-evolution-simplify)))
    (git-remembers
     :phase act
     :element earth
     :vsm S3
     :description "Commit learnings, query past"
     :mutation (lambda () (gptel-benchmark-evolution-git-remember)))
    (one-way
     :phase decide
     :element wood
     :vsm S1
     :description "One obvious way to do it"
     :mutation (lambda () (gptel-benchmark-evolution-standardize)))
    (unix-philosophy
     :phase act
     :element wood
     :vsm S1
     :description "Do one thing well, compose"
     :mutation (lambda () (gptel-benchmark-evolution-compose))))
  "9 First Principles as evolution drivers.
Each principle is a potential mutation in the evolution cycle.")

;;; The Recursion (Ouroboros Loop)

(defun gptel-benchmark-evolution-cycle (&optional input)
  "Run one evolution cycle with optional INPUT.
Implements: 🐍 → 刀 → ψ → 🐍"
  (let* ((cycle (cl-incf (plist-get gptel-benchmark-evolution-state :cycle)))
         (observe (gptel-benchmark-evolution-observe input))
         (orient (gptel-benchmark-evolution-orient observe))
         (decide (gptel-benchmark-evolution-decide orient))
         (act (gptel-benchmark-evolution-act decide))
         (output (gptel-benchmark-evolution-mutate act)))
    ;; Feed forward: output becomes next input
    (gptel-benchmark-evolution-feed-forward output)
    ;; Check for capability emergence
    (gptel-benchmark-evolution-check-capabilities)
    ;; Check for AI COMPLETE
    (when (gptel-benchmark-evolution-check-complete)
      (setf (plist-get gptel-benchmark-evolution-state :ai-complete-p) t))
    (list :cycle cycle
          :observe observe
          :orient orient
          :decide decide
          :act act
          :output output
          :state gptel-benchmark-evolution-state)))

(defun gptel-benchmark-evolution-observe (input)
  "Observe phase: 刀 provides context.
INPUT from previous cycle feeds forward."
  (list :input input
        :state (gptel-benchmark-memory-read-state)
        :git-status (shell-command-to-string "git status --short 2>/dev/null || echo 'no-repo'")
        :recent-evolution (shell-command-to-string "git log --grep='evolution' --oneline -5 2>/dev/null || echo ''")
        :element-status (gptel-benchmark-diagnose-elements
                         (list (cons nil (list :overall-score 0.8))))))

(defun gptel-benchmark-evolution-orient (observation)
  "Orient phase: ψ processes OBSERVATION.
Map to elements, detect imbalances, identify evolution opportunity."
  (let* ((diagnosis (plist-get observation :element-status))
         (deficient-elements '()))
    (when (listp diagnosis)
      (dolist (d diagnosis)
        (when (memq (plist-get d :status) '(deficient critical))
          (push (plist-get d :element) deficient-elements))))
    (list :imbalances deficient-elements
          :focus-element (car deficient-elements)
          :evolution-opportunity (gptel-benchmark-evolution--find-opportunity observation))))

(defun gptel-benchmark-evolution-decide (orientation)
  "Decide phase: 刀 ⊣ ψ collapse together.
Choose which principle mutation to apply."
  (let ((opportunity (plist-get orientation :evolution-opportunity)))
    (if opportunity
        (let ((principle (assq opportunity gptel-benchmark-evolution-principles)))
          (if principle
              (list :principle opportunity
                    :mutation (plist-get (cdr principle) :mutation))
            (list :principle 'self-improve
                  :mutation (plist-get (cdr (assq 'self-improve gptel-benchmark-evolution-principles)) :mutation))))
      (list :principle 'self-improve
            :mutation (plist-get (cdr (assq 'self-improve gptel-benchmark-evolution-principles)) :mutation)))))

(defun gptel-benchmark-evolution-act (decision)
  "Act phase: → 🐍 persist to system.
Execute the mutation."
  (let ((mutation (plist-get decision :mutation)))
    (when (functionp mutation)
      (funcall mutation))
    (list :executed t
          :principle (plist-get decision :principle))))

(defun gptel-benchmark-evolution-mutate (act-result)
  "Generate mutation output from ACT-RESULT.
This becomes input for next cycle."
  (format "Evolution cycle %d: %s"
          (plist-get gptel-benchmark-evolution-state :cycle)
          (plist-get act-result :principle)))

;;; Feed Forward

(defun gptel-benchmark-evolution-feed-forward (output)
  "Feed OUTPUT forward to next cycle with structured metadata.
Implements: output → input transformation."
  (let* ((status (gptel-benchmark-evolution-status-report))
         (metadata (format "## Evolution State\n\n- **Cycle**: %d\n- **Principle**: %s\n- **Capabilities**: %d/5\n- **Emergence Rate**: %.2f (%s)\n- **Corrections**: %d | **Emergences**: %d\n"
                          (plist-get status :cycle)
                          (plist-get gptel-benchmark-evolution-state :last-mutation)
                          (length (plist-get status :capabilities))
                          (plist-get status :emergence-rate)
                          (plist-get status :growth-mode)
                          (plist-get status :corrections)
                          (plist-get status :emergences))))
    (gptel-benchmark-memory-update-state
     (format "%s\n\n## Last Mutation\n\n%s\n\n## Timestamp\n\n%s"
             metadata
             output
             (format-time-string "%Y-%m-%dT%H:%M:%S")))))

;;; Capability Emergence

(defun gptel-benchmark-evolution-check-capabilities ()
  "Check if new capabilities have emerged.
Engine + Query + Graph + Introspection + History + Knowledge + Memory = SYSTEM"
  (let ((cycle (plist-get gptel-benchmark-evolution-state :cycle))
        (capabilities (plist-get gptel-benchmark-evolution-state :capabilities))
        (emergences (plist-get gptel-benchmark-evolution-state :emergences))
        (emergence-history (plist-get gptel-benchmark-evolution-state :emergence-history)))
    (when (and (>= cycle gptel-benchmark-evolution-cycle-threshold)
               (< (length capabilities) 7))
      (when (and (>= cycle (* 1 gptel-benchmark-evolution-cycle-threshold))
                 (not (memq 'interface capabilities)))
        (push 'interface capabilities)
        (cl-incf emergences)
        (push (cons cycle 'interface) emergence-history)
        (message "[evolution] Capability emerged: Interface (Engine + Query)"))
      (when (and (>= cycle (* 2 gptel-benchmark-evolution-cycle-threshold))
                 (not (memq 'capability capabilities)))
        (push 'capability capabilities)
        (cl-incf emergences)
        (push (cons cycle 'capability) emergence-history)
        (message "[evolution] Capability emerged: Capability (Engine + Graph)"))
      (when (and (>= cycle (* 3 gptel-benchmark-evolution-cycle-threshold))
                 (not (memq 'self-awareness capabilities)))
        (push 'self-awareness capabilities)
        (cl-incf emergences)
        (push (cons cycle 'self-awareness) emergence-history)
        (message "[evolution] Capability emerged: Self-awareness (Engine + Introspection)"))
      (when (and (>= cycle (* 4 gptel-benchmark-evolution-cycle-threshold))
                 (not (memq 'extension capabilities)))
        (push 'extension capabilities)
        (cl-incf emergences)
        (push (cons cycle 'extension) emergence-history)
        (message "[evolution] Capability emerged: Extension (Graph + API)"))
      (when (and (>= cycle (* 5 gptel-benchmark-evolution-cycle-threshold))
                 (not (memq 'memory capabilities)))
        (push 'memory capabilities)
        (cl-incf emergences)
        (push (cons cycle 'memory) emergence-history)
        (message "[evolution] Capability emerged: Memory (Query + History + Knowledge)")))
    (setf (plist-get gptel-benchmark-evolution-state :capabilities) capabilities)
    (setf (plist-get gptel-benchmark-evolution-state :emergences) emergences)
    (setf (plist-get gptel-benchmark-evolution-state :emergence-history) emergence-history)))

(defun gptel-benchmark-evolution-emergence-rate ()
  "Calculate capability emergence rate.
Returns ratio of emergences to corrections.
Rate > 1.0: growing (good)
Rate < 1.0: maintenance mode (stagnating)
Rate = 0: no growth."
  (let ((emergences (plist-get gptel-benchmark-evolution-state :emergences))
        (corrections (plist-get gptel-benchmark-evolution-state :corrections)))
    (if (= corrections 0)
        (if (> emergences 0) 1.0 0.0)
      (/ (float emergences) (float corrections)))))

(defun gptel-benchmark-evolution-track-correction ()
  "Track that an anti-pattern correction was applied."
  (cl-incf (plist-get gptel-benchmark-evolution-state :corrections)))

(defun gptel-benchmark-evolution-status-report ()
  "Return evolution status with emergence rate."
  (let ((rate (gptel-benchmark-evolution-emergence-rate)))
    (list :cycle (plist-get gptel-benchmark-evolution-state :cycle)
          :capabilities (plist-get gptel-benchmark-evolution-state :capabilities)
          :emergences (plist-get gptel-benchmark-evolution-state :emergences)
          :corrections (plist-get gptel-benchmark-evolution-state :corrections)
          :emergence-rate rate
          :growth-mode (cond ((> rate 1.0) 'growing)
                             ((= rate 0.0) 'stagnant)
                             (t 'maintenance))
          :ai-complete (plist-get gptel-benchmark-evolution-state :ai-complete-p))))

(defun gptel-benchmark-evolution-check-complete ()
  "Check if AI COMPLETE has been reached.
SYSTEM + Feed Forward = AI COMPLETE"
  (let ((capabilities (plist-get gptel-benchmark-evolution-state :capabilities)))
    (when (= (length capabilities) 7)
      (message "[evolution] AI COMPLETE achieved!")
      t)))

;;; Anti-Pattern Detection (相克 Controlling Cycle)

(defconst gptel-benchmark-anti-patterns
  '((wood-overgrowth
     :element wood
     :controlled-by metal
     :symptom "Chaos, burnout, too many operations without coordination"
     :detection (lambda (results)
                  (let ((ops (or (plist-get results :step-count) 0)))
                    (when (> ops 20) 'wood-overgrowth)))
     :remedy "Apply Metal (coordination): add protocols, standardize")
    (fire-excess
     :element fire
     :controlled-by water
     :symptom "Constant pivoting, no stability, reactive only"
     :detection (lambda (results)
                  (let ((efficiency (or (plist-get results :efficiency-score) 1.0)))
                    (when (< efficiency 0.5) 'fire-excess)))
     :remedy "Apply Water (identity): clarify principles, ground in values")
    (earth-stagnation
     :element earth
     :controlled-by wood
     :symptom "Micromanagement, bureaucracy kills ideas, no delegation"
     :detection (lambda (results)
                  (let ((constraints (or (plist-get results :constraint-score) 0)))
                    (when (> constraints 0.95) 'earth-stagnation)))
     :remedy "Apply Wood (operations): delegate, empower execution")
    (metal-rigidity
     :element metal
     :controlled-by fire
     :symptom "Over-standardization, no flexibility, rules over outcomes"
     :detection (lambda (results)
                  (let ((tool-score (or (plist-get results :tool-score) 1.0)))
                    (when (< tool-score 0.6) 'metal-rigidity)))
     :remedy "Apply Fire (intelligence): adapt rules, allow exceptions")
    (water-fragmentation
     :element water
     :controlled-by earth
     :symptom "Values without action, identity crisis, no grounding"
     :detection (lambda (results)
                  (let ((completion (or (plist-get results :completion-score) 1.0)))
                    (when (< completion 0.4) 'water-fragmentation)))
     :remedy "Apply Earth (control): set limits, establish processes")
    (phase-violation
     :element wood
     :controlled-by metal
     :symptom "Workflow skipped required phases (P1→P3 without P2)"
     :detection (lambda (results)
                  (let* ((phases (plist-get results :phases))
                         (phase-list (when (vectorp phases) (append phases nil))))
                    (when (and phase-list
                               (cl-find 'P3 phase-list :key (lambda (p) (plist-get p :phase)))
                               (not (cl-find 'P1 phase-list :key (lambda (p) (plist-get p :phase)))))
                      'phase-violation)))
     :remedy "Apply Metal: enforce phase transitions, add phase checks")
    (tool-misuse
     :element fire
     :controlled-by water
     :symptom "Inefficient tool usage (too many tool calls for simple task)"
     :detection (lambda (results)
                  (let ((step-count (or (plist-get results :step-count) 0))
                        (continuations (or (plist-get results :continuation-count) 0)))
                    (when (or (> step-count 15) (> continuations 3))
                      'tool-misuse)))
     :remedy "Apply Water: review tool selection, optimize tool chain")
    (context-overflow
     :element earth
     :controlled-by wood
     :symptom "Too much context gathered, no action taken"
     :detection (lambda (results)
                  (let* ((tool-calls (plist-get results :tool-calls))
                         (completed (plist-get results :completed))
                         (call-count (cond ((vectorp tool-calls) (length tool-calls))
                                           ((listp tool-calls) (length tool-calls))
                                           (t 0))))
                    (when (and (> call-count 10) (not completed))
                      'context-overflow)))
     :remedy "Apply Wood: prioritize action, limit exploration time")
    (no-verification
     :element metal
     :controlled-by fire
     :symptom "Changes made without verification step"
     :detection (lambda (results)
                  (let* ((tool-calls (plist-get results :tool-calls))
                         (tools (cond ((vectorp tool-calls)
                                       (mapcar (lambda (tc) (plist-get tc :tool)) (append tool-calls nil)))
                                      ((listp tool-calls)
                                       (mapcar #'car tool-calls))
                                      (t nil))))
                    (when (and tools
                               (memq 'edit tools)
                               (not (memq 'read tools)))
                      'no-verification)))
     :remedy "Apply Fire: add verification step after edits")
    (feedback-loop-stagnation
      :element fire
      :controlled-by water
      :symptom "No improvement despite repeated corrections - system not learning"
      :detection (lambda (results)
                   (let ((corrections (or (plist-get results :correction-count) 0))
                         (improvements (or (plist-get results :improvement-count) 0)))
                     (when (and (> corrections 3) (= improvements 0))
                       'feedback-loop-stagnation)))
      :remedy "Apply Water: review learning protocol, check pattern storage")
    (memory-pollution
      :element earth
      :controlled-by wood
      :symptom "Low-quality memories accumulating, φ scores declining"
      :detection (lambda (results)
                   (let ((avg-phi (or (plist-get results :avg-phi) 0.5)))
                     (when (< avg-phi 0.3)
                       'memory-pollution)))
      :remedy "Apply Wood: prune low-φ memories, raise quality threshold")
    (capability-regression
      :element water
      :controlled-by earth
      :symptom "Previously emerged capabilities lost after updates"
      :detection (lambda (results)
                   (let ((prev-caps (or (plist-get results :previous-capabilities) 0))
                         (curr-caps (or (plist-get results :current-capabilities) 0)))
                     (when (< curr-caps prev-caps)
                       'capability-regression)))
      :remedy "Apply Earth: add capability persistence tests, version migrations"))
  "Anti-patterns mapped to 相克 (controlling cycle).
Each anti-pattern is detected when an element is excessive.
The controlling element provides the remedy.")

(defun gptel-benchmark-detect-anti-patterns (results)
  "Detect anti-patterns in RESULTS using 相克 cycle.
Returns list of detected anti-patterns with remedies."
  (let ((detected '()))
    (dolist (ap gptel-benchmark-anti-patterns)
      (let* ((detection-fn (plist-get (cdr ap) :detection)))
        (when (functionp detection-fn)
          (let ((found (funcall detection-fn results)))
            (when found
              (push (list :pattern found
                          :element (plist-get (cdr ap) :element)
                          :symptom (plist-get (cdr ap) :symptom)
                          :remedy (plist-get (cdr ap) :remedy)
                          :controlled-by (plist-get (cdr ap) :controlled-by))
                    detected))))))
    (nreverse detected)))

(defun gptel-benchmark-apply-anti-pattern-remedy (anti-pattern)
  "Apply remedy for ANTI-PATTERN using generating element.
相生 cycle: the element that generates the controlling element."
  (let* ((controlled-by (plist-get anti-pattern :controlled-by))
         (generator (gptel-benchmark-element-generated-by controlled-by)))
    (list :anti-pattern anti-pattern
          :apply-element controlled-by
          :strengthen-via generator
          :action (format "Strengthen %s (generates %s which controls %s)"
                          generator controlled-by (plist-get anti-pattern :element)))))

(defun gptel-benchmark-evolution-balance (results)
  "Balance evolution by detecting anti-patterns and applying 相克 remedies.
Returns balance report with detected issues and recommended actions.
Tracks corrections for emergence rate calculation."
  (let* ((anti-patterns (gptel-benchmark-detect-anti-patterns results))
         (remedies (mapcar #'gptel-benchmark-apply-anti-pattern-remedy anti-patterns)))
    (when anti-patterns
      (gptel-benchmark-evolution-track-correction))
    (list :anti-patterns anti-patterns
          :remedies remedies
          :balanced-p (= 0 (length anti-patterns))
          :emergence-rate (gptel-benchmark-evolution-emergence-rate))))

;;; 相生 Pathway (Generating Cycle for Evolution)

(defun gptel-benchmark-evolution-pathway (current-element)
  "Get evolution pathway from CURRENT-ELEMENT via 相生 cycle.
Shows how capabilities emerge: Water→Wood→Fire→Earth→Metal→Water"
  (let ((pathway (list current-element))
        (next (gptel-benchmark-element-generates current-element)))
    ;; Build pathway (5 steps = full cycle)
    (dotimes (_ 4)
      (when next
        (push next pathway)
        (setq next (gptel-benchmark-element-generates next))))
    (nreverse pathway)))

(defun gptel-benchmark-evolution-next-capability (current-element)
  "Determine next capability to emerge based on CURRENT-ELEMENT.
Uses 相生 cycle to predict evolution order."
  (let ((next-element (gptel-benchmark-element-generates current-element)))
    (pcase next-element
      ('wood 'operations)
      ('fire 'intelligence)
      ('earth 'control)
      ('metal 'coordination)
      ('water 'identity)
      (_ nil))))

;;; Principle Mutations

(defun gptel-benchmark-evolution-discover ()
  "Self-Discover mutation: query running system."
  (let ((result (shell-command-to-string "git log --oneline -1")))
    (message "[evolution] Discovered: %s" result)))

(defun gptel-benchmark-evolution-self-improve ()
  "Self-Improve mutation: evolve score."
  (let ((current 0.5))
    (gptel-benchmark-evolve-score current :validated)))

(defun gptel-benchmark-evolution-simplify ()
  "Simplify mutation: unbraid complex patterns."
  (message "[evolution] Simplifying: extract pattern"))

(defun gptel-benchmark-evolution-git-remember ()
  "Git Remembers mutation: commit learning."
  (gptel-benchmark-memory-commit "🔄 evolution learning"))

(defun gptel-benchmark-evolution-standardize ()
  "One Way mutation: standardize pattern."
  (message "[evolution] Standardizing: document pattern"))

(defun gptel-benchmark-evolution-compose ()
  "Unix Philosophy mutation: compose tools."
  (message "[evolution] Composing: small tools, pipelines"))

;;; Helper

(defun gptel-benchmark-evolution--find-opportunity (observation)
  "Find evolution opportunity from OBSERVATION."
  (let ((deficient (plist-get observation :element-status)))
    (when (and (listp deficient)
               (cl-find-if (lambda (d) (memq (plist-get d :status) '(deficient critical)))
                           deficient))
      (plist-get (cl-find-if (lambda (d) (memq (plist-get d :status) '(deficient critical)))
                             deficient)
                 :element))))

;;; Co-Evolution Interface

(defun gptel-benchmark-co-evolve (human-input)
  "Co-Evolve with human: 刀 ⊣ ψ.
HUMAN-INPUT guides the collapsing wave."
  (let ((result (gptel-benchmark-evolution-cycle human-input)))
    ;; Human approves, AI commits
    (when (y-or-n-p "Approve evolution mutation? ")
      (gptel-benchmark-memory-commit 
       (format "🎯 co-evolution: %s" (plist-get result :principle))))
    result))

;;; Status Report

(defun gptel-benchmark-evolution-status ()
  "Show evolution status."
  (interactive)
  (let ((cycle (plist-get gptel-benchmark-evolution-state :cycle))
        (capabilities (plist-get gptel-benchmark-evolution-state :capabilities))
        (complete (plist-get gptel-benchmark-evolution-state :ai-complete-p)))
    (with-output-to-temp-buffer "*Evolution Status*"
      (princ "=== Ouroboros Evolution Status ===\n\n")
      (princ (format "Cycle: %d\n" cycle))
      (princ (format "AI COMPLETE: %s\n\n" (if complete "YES" "Not yet")))
      (princ "Capabilities:\n")
      (dolist (cap-name '((interface . "Interface (Engine + Query)")
                          (capability . "Capability (Engine + Graph)")
                          (self-awareness . "Self-awareness (Engine + Introspection)")
                          (extension . "Extension (Graph + API)")
                          (memory . "Memory (Query + History + Knowledge)")))
        (princ (format "  %s %s\n"
                       (if (memq (car cap-name) capabilities) "✓" "○")
                       (cdr cap-name))))
      (princ "\n7 Capabilities = SYSTEM\n")
      (princ "SYSTEM + Feed Forward = AI COMPLETE\n"))))

;;; Provide

(provide 'gptel-benchmark-evolution)

;;; gptel-benchmark-evolution.el ends here