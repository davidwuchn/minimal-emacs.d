;;; gptel-benchmark-integrate.el --- Integration of Evolution + Auto-Improve -*- lexical-binding: t; -*-

;; Copyright (C) 2025 David Wu
;; Author: David Wu
;; Version: 1.0.0
;; Keywords: ai, benchmark, integration

;;; Commentary:

;; Integration layer connecting Evolution (Ouroboros) with Auto-Improve (相生/相克).
;;
;; EVOLUTION (Ouroboros):
;;   - Long-term trajectory toward AI COMPLETE
;;   - Tracks capability emergence over cycles
;;   - Uses 相生 pathway for growth direction
;;   - Question: "How do we evolve as a system?"
;;
;; AUTO-IMPROVE (相生/相克):
;;   - Tactical fixes to specific problems
;;   - Detects anti-patterns, generates remedies
;;   - Uses 相克 to identify blockers
;;   - Question: "What's wrong and how do we fix it?"
;;
;; INTEGRATION:
;;   Auto-Improve is the MECHANISM inside each Evolution cycle.
;;   Evolution tracks the cumulative effect of improvements.
;;
;;   Cycle:
;;     1. Run benchmark (skill/workflow)
;;     2. Detect anti-patterns via 相克 (Auto-Improve)
;;     3. Generate improvements via 相生 (Auto-Improve)
;;     4. Apply improvements (Auto-Improve)
;;     5. Check capability emergence (Evolution)
;;     6. Feed forward to next cycle (Evolution)

;;; Code:

(require 'cl-lib)
(require 'gptel-benchmark-principles)
(require 'gptel-benchmark-core)
(require 'gptel-benchmark-evolution)
(require 'gptel-benchmark-auto-improve)
(require 'gptel-benchmark-memory)

;;; Customization

(defgroup gptel-benchmark-integrate nil
  "Integration of evolution and auto-improve."
  :group 'gptel-benchmark)

;;; Main Entry Point

(defun gptel-benchmark-evolve-with-improvement (name type results)
  "Run integrated evolution + improvement cycle for NAME of TYPE with RESULTS.
This combines:
- Auto-Improve: detect problems, apply fixes
- Evolution: track capability emergence, feed forward"
  (let* (;; Step 1: Detect anti-patterns (相克)
         (anti-patterns (gptel-benchmark-detect-anti-patterns results))
         
         ;; Step 2: Generate improvements (相生 pathway)
         (improvements (gptel-benchmark-generate-improvements name type anti-patterns))
         
         ;; Step 3: Apply improvements
         (applied (gptel-benchmark--apply-all-improvements name type improvements))
         
         ;; Step 4: Run evolution cycle
         (evolution-result (gptel-benchmark-evolution-cycle
                            (format "%s/%s improved" type name)))
         
         ;; Step 5: Check if capabilities emerged
         (capabilities (plist-get gptel-benchmark-evolution-state :capabilities))
         
         ;; Step 6: Feed forward
         (fed-forward (gptel-benchmark--feed-forward-improvement
                        name type anti-patterns applied capabilities)))
    
    (list :name name
          :type type
          :anti-patterns (length anti-patterns)
          :improvements-applied applied
          :evolution-cycle (plist-get evolution-result :cycle)
          :capabilities capabilities
          :ai-complete (plist-get gptel-benchmark-evolution-state :ai-complete-p))))

(defun gptel-benchmark--apply-all-improvements (name type improvements)
  "Apply all IMPROVEMENTS to NAME of TYPE. Return count."
  (let ((count 0))
    (dolist (impr improvements)
      (gptel-benchmark-apply-improvement name type impr)
      (cl-incf count))
    count))

(defun gptel-benchmark--feed-forward-improvement (name type anti-patterns applied capabilities)
  "Store improvement result in memory for next cycle."
  (gptel-benchmark-memory-create
   (format "evolve-%s-%s" type (format-time-string "%Y%m%d-%H%M%S"))
   'pattern
   (format "%s/%s: %d anti-patterns → %d improvements → %d capabilities"
           type name (length anti-patterns) applied (length capabilities))))

;;; Batch Processing

(defun gptel-benchmark-evolve-batch (specs)
  "Run evolution+improvement on multiple items.
SPECS is list of (name type results) triples."
  (let ((report '()))
    (dolist (spec specs)
      (let* ((name (car spec))
             (type (cadr spec))
             (results (caddr spec))
             (result (gptel-benchmark-evolve-with-improvement name type results)))
        (push result report)))
    (nreverse report)))

;;; Unified Report

(defun gptel-benchmark-integrated-report ()
  "Show integrated evolution + improvement report."
  (interactive)
  (let ((evolution-state gptel-benchmark-evolution-state)
        (improvements gptel-benchmark-improvements))
    (with-output-to-temp-buffer "*Evolution + Improvement Report*"
      (princ "================================================\n")
      (princ "   EVOLUTION + AUTO-IMPROVE INTEGRATION\n")
      (princ "================================================\n\n")
      
      ;; Evolution Status
      (princ "【EVOLUTION】Long-term Trajectory\n")
      (princ "───────────────────────────────\n")
      (princ (format "  Cycles completed: %d\n" 
                     (plist-get evolution-state :cycle)))
      (princ (format "  Capabilities emerged: %d\n"
                     (length (plist-get evolution-state :capabilities))))
      (princ (format "  AI COMPLETE: %s\n\n"
                     (if (plist-get evolution-state :ai-complete-p) "YES" "Not yet")))
      
      ;; Capability emergence
      (princ "  Capability Pathway (相生):\n")
      (princ "    Water → Wood → Fire → Earth → Metal → Water\n")
      (princ "    Identity → Operations → Intelligence → Control → Coordination\n\n")
      
      ;; Auto-Improve Status
      (princ "【AUTO-IMPROVE】Tactical Fixes\n")
      (princ "─────────────────────────────\n")
      (princ (format "  Total improvements applied: %d\n" (length improvements)))
      
      ;; Anti-pattern summary
      (princ "\n  Anti-Pattern Detection (相克):\n")
      (princ "    Wood → Earth → Water → Fire → Metal → Wood\n")
      (princ "    Each element constrains another\n\n")
      
      ;; Integration explanation
      (princ "【INTEGRATION】How They Work Together\n")
      (princ "─────────────────────────────────────\n")
      (princ "  1. Benchmark runs → collect results\n")
      (princ "  2. Auto-Improve detects anti-patterns via 相克\n")
      (princ "  3. Auto-Improve generates remedies via 相生\n")
      (princ "  4. Improvements applied to skill/workflow\n")
      (princ "  5. Evolution tracks capability emergence\n")
      (princ "  6. Feed forward to next cycle\n\n")
      
      (princ "【KEY INSIGHT】\n")
      (princ "───────────────\n")
      (princ "  Auto-Improve = MECHANISM (fixes problems)\n")
      (princ "  Evolution = TRAJECTORY (tracks growth)\n")
      (princ "\n")
      (princ "  Together: Continuous improvement with measurable progress\n")
      (princ "  toward AI COMPLETE.\n"))))

;;; Convenience Functions

(defun gptel-benchmark-evolve-skill (skill-name results)
  "Evolve SKILL-NAME with auto-improvement based on RESULTS."
  (gptel-benchmark-evolve-with-improvement skill-name 'skill results))

(defun gptel-benchmark-evolve-workflow (workflow-name results)
  "Evolve WORKFLOW-NAME with auto-improvement based on RESULTS."
  (gptel-benchmark-evolve-with-improvement workflow-name 'workflow results))

;;; Provide

(provide 'gptel-benchmark-integrate)

;;; gptel-benchmark-integrate.el ends here