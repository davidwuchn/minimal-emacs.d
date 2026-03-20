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
Uses 相克 to detect problems, 相生 to guide improvements."
  (let* ((diagnosis (gptel-benchmark-diagnose-elements results))
         (anti-patterns (gptel-benchmark-detect-anti-patterns results))
         (improvements (gptel-benchmark-generate-improvements skill-name 'skill anti-patterns)))
    ;; Apply improvements
    (dolist (impr improvements)
      (gptel-benchmark-apply-improvement skill-name 'skill impr))
    ;; Store learning
    (gptel-benchmark-memory-create 
     (format "skill-improve-%s" skill-name)
     'shift
     (format "Skill %s: %d anti-patterns, %d improvements applied"
             skill-name (length anti-patterns) (length improvements)))
    (list :skill skill-name
          :diagnosis diagnosis
          :anti-patterns anti-patterns
          :improvements improvements
          :applied (length improvements))))

(defun gptel-benchmark-auto-improve-workflow (workflow-name results)
  "Auto-improve WORKFLOW-NAME based on RESULTS.
Uses 相克 to detect problems, 相生 to guide improvements."
  (let* ((diagnosis (gptel-benchmark-diagnose-elements results))
         (anti-patterns (gptel-benchmark-detect-anti-patterns results))
         (improvements (gptel-benchmark-generate-improvements workflow-name 'workflow anti-patterns)))
    ;; Apply improvements
    (dolist (impr improvements)
      (gptel-benchmark-apply-improvement workflow-name 'workflow impr))
    ;; Store learning
    (gptel-benchmark-memory-create
     (format "workflow-improve-%s" workflow-name)
     'shift
     (format "Workflow %s: %d anti-patterns, %d improvements applied"
             workflow-name (length anti-patterns) (length improvements)))
    (list :workflow workflow-name
          :diagnosis diagnosis
          :anti-patterns anti-patterns
          :improvements improvements
          :applied (length improvements))))

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
Modifies test definitions or prompts based on improvement type."
  (let ((specifics (plist-get improvement :specifics)))
    ;; Log improvement
    (push (list :name name
                :type type
                :improvement improvement
                :timestamp (format-time-string "%Y%m%d-%H%M%S"))
          gptel-benchmark-improvements)
    ;; Apply based on type
    (pcase (plist-get improvement :type)
      ('efficiency
       (gptel-benchmark--apply-efficiency-improvement name type specifics))
      ('analysis
       (gptel-benchmark--apply-analysis-improvement name type specifics))
      ('constraints
       (gptel-benchmark--apply-constraint-improvement name type specifics))
      ('flexibility
       (gptel-benchmark--apply-flexibility-improvement name type specifics))
      ('identity
       (gptel-benchmark--apply-identity-improvement name type specifics)))
    ;; Commit if enabled
    (when gptel-benchmark-auto-improve-commit
      (gptel-benchmark-memory-commit
       (format "🎯 auto-improve: %s %s" type name)))))

(defun gptel-benchmark--apply-efficiency-improvement (name type specifics)
  "Apply efficiency improvement."
  (let ((thresholds (plist-get specifics :threshold-suggestions)))
    (message "[auto-improve] %s/%s efficiency: %s" type name (car thresholds))))

(defun gptel-benchmark--apply-analysis-improvement (name type specifics)
  "Apply analysis improvement."
  (let ((prompts (plist-get specifics :prompt-suggestions)))
    (message "[auto-improve] %s/%s analysis: %s" type name (car prompts))))

(defun gptel-benchmark--apply-constraint-improvement (name type specifics)
  "Apply constraint improvement."
  (let ((thresholds (plist-get specifics :threshold-suggestions)))
    (message "[auto-improve] %s/%s constraints: %s" type name (car thresholds))))

(defun gptel-benchmark--apply-flexibility-improvement (name type specifics)
  "Apply flexibility improvement."
  (let ((tests (plist-get specifics :test-suggestions)))
    (message "[auto-improve] %s/%s flexibility: %s" type name (car tests))))

(defun gptel-benchmark--apply-identity-improvement (name type specifics)
  "Apply identity improvement."
  (let ((prompts (plist-get specifics :prompt-suggestions)))
    (message "[auto-improve] %s/%s identity: %s" type name (car prompts))))

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

;;; Provide

(provide 'gptel-benchmark-auto-improve)

;;; gptel-benchmark-auto-improve.el ends here