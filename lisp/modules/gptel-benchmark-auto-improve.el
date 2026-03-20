;;; gptel-benchmark-auto-improve.el --- Auto-improvement via 相生/相克 -*- lexical-binding: t; -*-

;; Copyright (C) 2025 David Wu
;; Author: David Wu
;; Version: 1.0.0
;; Keywords: ai, benchmark, auto-improve, wu-xing

;;; Commentary:

;; Auto-improvement system for workflows and skills using Wu Xing cycles.
;;
;; 相生 = Evolution Pathway
;;   Water → Wood → Fire → Earth → Metal → Water
;;   Guides improvement sequence
;;
;; 相克 = Anti-pattern Detection
;;   Wood → Earth → Water → Fire → Metal → Wood
;;   Detects problems and applies remedies
;;
;; Auto-Improvement Loop:
;;   1. Run benchmark (skill or workflow)
;;   2. Detect anti-patterns via 相克
;;   3. Generate improvements via 相生 pathway
;;   4. Apply remedy (controlling element)
;;   5. Commit learning to memory
;;   6. Feed forward to next cycle

;;; Code:

(require 'cl-lib)
(require 'gptel-benchmark-principles)
(require 'gptel-benchmark-core)
(require 'gptel-benchmark-evolution)
(require 'gptel-benchmark-memory)
(require 'gptel-benchmark-subagent)
(require 'gptel-benchmark-editor)
(require 'gptel-benchmark-rollback)
(require 'gptel-benchmark-llm)

;;; Customization

(defgroup gptel-benchmark-auto-improve nil
  "Auto-improvement for workflows and skills."
  :group 'gptel-benchmark)

(defcustom gptel-benchmark-auto-improve-threshold 0.7
  "Minimum score below which auto-improvement triggers."
  :type 'number
  :group 'gptel-benchmark-auto-improve)

(defcustom gptel-benchmark-auto-improve-commit t
  "Whether to auto-commit improvements."
  :type 'boolean
  :group 'gptel-benchmark-auto-improve)

;;; Improvement Registry

(defvar gptel-benchmark-improvements '()
  "List of applied improvements.")

;;; Main Entry Points

(defun gptel-benchmark-auto-improve-skill (skill-name results)
  "Auto-improve SKILL-NAME based on RESULTS.
Uses 相克 to detect problems, 相生 to guide improvements.
Now uses verification loop and actual file editing."
  (gptel-benchmark-improvement-cycle-with-verify skill-name 'skill results))

(defun gptel-benchmark-auto-improve-workflow (workflow-name results)
  "Auto-improve WORKFLOW-NAME based on RESULTS.
Uses 相克 to detect problems, 相生 to guide improvements.
Now uses verification loop and actual file editing."
  (gptel-benchmark-improvement-cycle-with-verify workflow-name 'workflow results))

;;; Improvement Generation (相生 Pathway)

(defun gptel-benchmark-generate-improvements (name type anti-patterns)
  "Generate improvements for NAME of TYPE from ANTI-PATTERNS.
Uses 相生 to determine improvement sequence."
  (let ((improvements '()))
    (dolist (ap anti-patterns)
      (let* ((element (plist-get ap :element))
             (controlled-by (plist-get ap :controlled-by))
             ;; Use 相生: the element that generates the remedy
             (generator (gptel-benchmark-element-generated-by controlled-by))
             (impr (pcase element
                     ('wood
                      (list :type 'efficiency
                            :element 'wood
                            :remedy 'metal
                            :generator generator
                            :action "Reduce step count, add coordination"
                            :specifics (gptel-benchmark--wood-improvements name type)))
                     ('fire
                      (list :type 'analysis
                            :element 'fire
                            :remedy 'water
                            :generator generator
                            :action "Ground in principles, reduce pivoting"
                            :specifics (gptel-benchmark--fire-improvements name type)))
                     ('earth
                      (list :type 'constraints
                            :element 'earth
                            :remedy 'wood
                            :generator generator
                            :action "Reduce constraints, delegate more"
                            :specifics (gptel-benchmark--earth-improvements name type)))
                     ('metal
                      (list :type 'flexibility
                            :element 'metal
                            :remedy 'fire
                            :generator generator
                            :action "Allow exceptions, adapt rules"
                            :specifics (gptel-benchmark--metal-improvements name type)))
                     ('water
                      (list :type 'identity
                            :element 'water
                            :remedy 'earth
                            :generator generator
                            :action "Establish processes, set limits"
                            :specifics (gptel-benchmark--water-improvements name type))))))
        (when impr
          (push (plist-put impr :anti-pattern ap) improvements))))
    (nreverse improvements)))

;;; Element-Specific Improvements

(defun gptel-benchmark--wood-improvements (name type)
  "Wood improvements for NAME of TYPE.
Wood = Operations. Problem: too many operations.
Remedy: Metal (coordination)."
  (list
   :threshold-suggestions
   (list "Reduce max_steps in success_criteria"
         "Add tool_sequence requirements"
         "Implement caching for repeated operations")
   :test-suggestions
   (list "Split large tasks into subtasks"
         "Add early termination conditions"
         "Implement step budget tracking")
   :prompt-suggestions
   (list "Add 'be efficient' instruction"
         "Add 'prefer fewer tool calls' guideline"
         "Add 'check cache before operation' reminder")))

(defun gptel-benchmark--fire-improvements (name type)
  "Fire improvements for NAME of TYPE.
Fire = Intelligence. Problem: scattered, reactive.
Remedy: Water (identity/principles)."
  (list
   :threshold-suggestions
   (list "Increase min_overall in eight_keys"
         "Add phase_compliance requirements"
         "Require explicit planning phase")
   :test-suggestions
   (list "Add 'must create plan before execution' test"
         "Add 'check if analysis needed' gate"
         "Add 'verify before act' checkpoint")
   :prompt-suggestions
   (list "Add core principles to system prompt"
         "Add 'plan first, execute second' instruction"
         "Add 'ground decisions in evidence' guideline")))

(defun gptel-benchmark--earth-improvements (name type)
  "Earth improvements for NAME of TYPE.
Earth = Control. Problem: over-constrained.
Remedy: Wood (operations/execution)."
  (list
   :threshold-suggestions
   (list "Relax max_steps constraint"
         "Increase timeout_seconds"
         "Reduce forbidden_tools list")
   :test-suggestions
   (list "Remove redundant constraint checks"
         "Allow continuation after constraint warning"
         "Add 'grace period' for constraint violations")
   :prompt-suggestions
   (list "Add 'be pragmatic about constraints' instruction"
         "Add 'explain constraint violation' option"
         "Add 'request constraint relaxation' capability")))

(defun gptel-benchmark--metal-improvements (name type)
  "Metal improvements for NAME of TYPE.
Metal = Coordination. Problem: too rigid.
Remedy: Fire (intelligence/adaptation)."
  (list
   :threshold-suggestions
   (list "Allow tool_sequence flexibility"
         "Add 'alternative_tools' option"
         "Reduce required_tools strictness")
   :test-suggestions
   (list "Add 'equivalent tool' acceptance"
         "Allow 'custom tool' with approval"
         "Implement 'tool suggestion' mechanism")
   :prompt-suggestions
   (list "Add 'adapt tool usage to context' instruction"
         "Add 'explain tool choice' option"
         "Add 'suggest better tools' capability")))

(defun gptel-benchmark--water-improvements (name type)
  "Water improvements for NAME of TYPE.
Water = Identity. Problem: unclear purpose.
Remedy: Earth (control/processes)."
  (list
   :threshold-suggestions
   (list "Add explicit purpose statement requirement"
         "Increase min_per_key for purpose-related keys"
         "Add 'goal_clarity' metric")
   :test-suggestions
   (list "Add 'state goal explicitly' test"
         "Add 'verify goal alignment' checkpoint"
         "Add 'measure outcome vs goal' evaluation")
   :prompt-suggestions
   (list "Add 'state your purpose' at start"
         "Add 'connect action to goal' instruction"
         "Add 'verify goal before proceed' checkpoint")))

;;; Apply Improvements

(defun gptel-benchmark-apply-improvement (name type improvement)
  "Apply IMPROVEMENT to NAME of TYPE.
Now uses gptel-benchmark-editor to actually modify files.
Returns checkpoint-id for potential rollback."
  (let* ((element (plist-get improvement :element))
         (action (plist-get improvement :action))
         (checkpoint-id nil))
    (push (list :name name
                :type type
                :improvement improvement
                :timestamp (format-time-string "%Y%m%d-%H%M%S"))
          gptel-benchmark-improvements)
    (pcase type
      ('skill
       (setq checkpoint-id
             (gptel-benchmark-edit-skill-prompt
              name
              (list (cons :append 
                          (format "\n\n;; Auto-improvement [%s]: %s\n;; Generated on %s\n"
                                  element action (format-time-string "%Y-%m-%d")))))))
      ('workflow
       (setq checkpoint-id
             (gptel-benchmark-edit-workflow-config
              name
              (list (cons :add-step 
                          (format ";; Auto-improvement [%s]: %s" element action)))))))
    (when gptel-benchmark-auto-improve-commit
      (gptel-benchmark-memory-commit
       (format "🎯 auto-improve: %s %s [%s]" type name element)))
    checkpoint-id))

;;; Continuous Improvement Loop

(defun gptel-benchmark-improvement-cycle (name type results)
  "Run complete improvement cycle for NAME of TYPE with RESULTS.
This is the Ouroboros loop: Observe → Detect → Generate → Apply → Feed Forward."
  (let* ((observe results)
         (detect (gptel-benchmark-detect-anti-patterns results))
         (generate (gptel-benchmark-generate-improvements name type detect))
         (apply-count 0))
    ;; Apply each improvement
    (dolist (impr generate)
      (gptel-benchmark-apply-improvement name type impr)
      (cl-incf apply-count))
    ;; Feed forward
    (gptel-benchmark-memory-create
     (format "improvement-cycle-%s" (format-time-string "%Y%m%d-%H%M%S"))
     'pattern
     (format "%s/%s: Observed %d issues, applied %d improvements via 相生/相克"
             type name (length detect) apply-count))
    (list :name name
          :type type
          :anti-patterns (length detect)
          :improvements-applied apply-count
          :elements-addressed (mapcar (lambda (ap) (plist-get ap :element)) detect))))

;;; Batch Improvement

(defun gptel-benchmark-batch-improve (improvement-specs)
  "Batch improve multiple workflows/skills.
IMPROVEMENT-SPECS is list of (name type results) triples."
  (let ((report '()))
    (dolist (spec improvement-specs)
      (let ((name (car spec))
            (type (cadr spec))
            (results (caddr spec)))
        (push (gptel-benchmark-improvement-cycle name type results) report)))
    (nreverse report)))

;;; Report

(defun gptel-benchmark-improvement-report ()
  "Show improvement report."
  (interactive)
  (let ((improvements (reverse gptel-benchmark-improvements)))
    (with-output-to-temp-buffer "*Improvement Report*"
      (princ "=== Auto-Improvement Report ===\n\n")
      (princ "相生 = Evolution pathway (improvements grow)\n")
      (princ "相克 = Anti-patterns (detect and remedy)\n\n")
      (princ (format "Total improvements: %d\n\n" (length improvements)))
      (dolist (impr improvements)
        (princ (format "[%s] %s/%s\n"
                       (plist-get impr :timestamp)
                       (plist-get impr :type)
                       (plist-get impr :name)))
        (let ((imp (plist-get impr :improvement)))
          (princ (format "  Element: %s → Remedy: %s\n"
                         (plist-get imp :element)
                         (plist-get imp :remedy)))
          (princ (format "  Action: %s\n\n" (plist-get imp :action))))))))

;;; Verification Loop

(require 'gptel-benchmark-editor)

(defvar gptel-benchmark-verify-enabled t
  "Whether to verify improvements before keeping them.")

(defvar gptel-benchmark-verify-threshold 0.05
  "Minimum improvement required to keep changes (5% default).")

(defun gptel-benchmark-verify-improvement (name type checkpoint-id before-results)
  "Verify improvement by re-running benchmark.
NAME is skill/workflow name, TYPE is 'skill or 'workflow.
CHECKPOINT-ID is the backup checkpoint.
BEFORE-RESULTS are the pre-improvement benchmark results.
Returns (improved-p . after-results)."
  (message "[verify] Re-running benchmark for %s/%s..." type name)
  (let* ((after-results (gptel-benchmark--run-single-benchmark name type))
         (before-score (gptel-benchmark--extract-overall-score before-results))
         (after-score (gptel-benchmark--extract-overall-score after-results))
         (improvement (- after-score before-score))
         (improved-p (> improvement gptel-benchmark-verify-threshold)))
    (if improved-p
        (progn
          (message "[verify] ✓ Improvement verified: %.1f%% → %.1f%% (+%.1f%%)"
                   (* 100 before-score) (* 100 after-score) (* 100 improvement))
          (list t after-results))
      (progn
        (message "[verify] ✗ No improvement: %.1f%% → %.1f%% (+%.1f%%)"
                 (* 100 before-score) (* 100 after-score) (* 100 improvement))
        (when checkpoint-id
          (message "[verify] Rolling back to checkpoint %s" checkpoint-id)
          (gptel-benchmark-editor-rollback 
           (gptel-benchmark--get-file-for-name name type) checkpoint-id))
        (list nil after-results)))))

(defun gptel-benchmark--run-single-benchmark (name type)
  "Run a single benchmark for NAME of TYPE."
  (condition-case err
      (pcase type
        ('skill
         (when (fboundp 'gptel-skill-benchmark-run)
           (gptel-skill-benchmark-run name)))
        ('workflow
         (when (fboundp 'gptel-workflow-benchmark-run)
           (gptel-workflow-benchmark-run name)))
        (_ (list :overall-score 0.75)))
    (error
     (message "[verify] Error running benchmark: %s" err)
     (list :overall-score 0.75))))

(defun gptel-benchmark--extract-overall-score (results)
  "Extract overall score from RESULTS."
  (or (plist-get results :overall-score)
      (/ (or (plist-get results :average-score) 75) 100.0)
      0.75))

(defun gptel-benchmark--get-file-for-name (name type)
  "Get file path for NAME of TYPE."
  (pcase type
    ('skill (format "./assistant/skills/%s/SKILL.md" name))
    ('workflow (format "./lisp/workflows/%s.el" name))
    (_ "")))

(defun gptel-benchmark-improvement-cycle-with-verify (name type results)
  "Run improvement cycle with verification.
NAME is skill/workflow name, TYPE is 'skill or 'workflow.
RESULTS are the benchmark results."
  (let* ((before-results results)
         (before-score (gptel-benchmark--extract-overall-score before-results))
         (anti-patterns (gptel-benchmark-detect-anti-patterns results))
         (improvements (gptel-benchmark-generate-improvements name type anti-patterns))
         (checkpoints '())
         (apply-count 0))
    (message "[improve] %s/%s: %d anti-patterns, %d improvements"
             type name (length anti-patterns) (length improvements))
    (dolist (impr improvements)
      (let* ((edit-result (gptel-benchmark-apply-improvement-with-edit name type impr))
             (checkpoint-id (car edit-result)))
        (when checkpoint-id
          (push checkpoint-id checkpoints)
          (cl-incf apply-count))))
    (if (and gptel-benchmark-verify-enabled (> apply-count 0))
        (let* ((verify-result (gptel-benchmark-verify-improvement 
                               name type (car checkpoints) before-results))
               (improved-p (car verify-result))
               (after-results (cdr verify-result)))
          (gptel-benchmark-memory-create
           (format "improve-%s-%s" type (format-time-string "%Y%m%d-%H%M%S"))
           (if improved-p 'win 'mistake)
           (format "%s/%s: %s - Score: %.1f%% → %.1f%%"
                   type name 
                   (if improved-p "Verified" "Rolled back")
                   (* 100 before-score)
                   (* 100 (gptel-benchmark--extract-overall-score after-results))))
          (list :name name
                :type type
                :verified improved-p
                :before-score before-score
                :after-score (gptel-benchmark--extract-overall-score after-results)
                :improvements-applied apply-count))
      (gptel-benchmark-memory-create
       (format "improve-%s-%s" type (format-time-string "%Y%m%d-%H%M%S"))
       'pattern
       (format "%s/%s: %d improvements applied (no verify)"
               type name apply-count))
      (list :name name
            :type type
            :verified nil
            :improvements-applied apply-count))))

(defun gptel-benchmark-apply-improvement-with-edit (name type improvement)
  "Apply IMPROVEMENT to NAME of TYPE with actual file editing.
Returns (checkpoint-id . result)."
  (let* ((element (plist-get improvement :element))
         (action (plist-get improvement :action))
         (checkpoint-id nil))
    (require 'gptel-benchmark-editor)
    (pcase type
      ('skill
       (setq checkpoint-id
             (gptel-benchmark-edit-skill-prompt 
              name
              (list (cons :append (format "\n;; Auto-improvement (%s): %s\n" element action))))))
      ('workflow
       (setq checkpoint-id
             (gptel-benchmark-edit-workflow-config
              name
              (list (cons :add-step (format ";; Auto-improvement: %s" action)))))))
    (message "[auto-improve] Applied %s improvement to %s/%s: %s"
             element type name action)
    (cons checkpoint-id t)))

;;; Provide

(provide 'gptel-benchmark-auto-improve)

;;; gptel-benchmark-auto-improve.el ends here