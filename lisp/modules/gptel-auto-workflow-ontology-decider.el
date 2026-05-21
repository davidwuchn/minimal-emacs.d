;;; gptel-auto-workflow-ontology-decider.el --- Formal ontology vs LLM decision framework -*- lexical-binding: t -*-

;; Copyright (C) 2024-2026  Self-Evolving Emacs Project

;; Author: Self-Evolving System
;; Keywords: ontology, llm, decision-tree, cost-optimization

;;; Commentary:

;; Decision framework: when to use ontology (fast, cheap, structured)
;; vs when to use LLM (slow, expensive, reasoning).
;;
;; Rule of thumb:
;; - If answer fits in a hash table → ontology
;; - If answer requires reading 500 lines of code → LLM
;; - If decision time < 1ms critical → ontology
;; - If reasoning required → LLM
;;
;; This module provides a formal decider function and guards to
;; prevent expensive LLM calls when ontology can answer.

;;; Code:

(defcustom gptel-auto-workflow--ontology-decision-log t
  "Log ontology vs LLM decisions for analysis."
  :type 'boolean
  :group 'gptel-auto-workflow)

(defcustom gptel-auto-workflow--ontology-cost-threshold 0.01
  "Max cost (in dollars) for ontology-based decisions.
Above this, prefer ontology even if less accurate."
  :type 'float
  :group 'gptel-auto-workflow)

(defcustom gptel-auto-workflow--llm-cost-threshold 0.05
  "Min cost (in dollars) for LLM-based decisions.
Below this, LLM is acceptable even for simple queries."
  :type 'float
  :group 'gptel-auto-workflow)

;; ─── Decision Types ───

(defconst gptel-auto-workflow--decision-types
  '((:name "pre-flight"
     :description "Should we run this experiment?"
     :ontology-rules ("anti-pattern (3+ failures)" "target saturation (≥10)" "prediction < 0.15")
     :llm-when ("novel strategy" "no historical data" "target never seen")
     :default :ontology)

    (:name "strategy-selection"
     :description "Which strategy to use?"
     :ontology-rules ("effective status (+1.0)" "promising status (+0.5)" "keep-rate > 0.5")
     :llm-when ("no strategy history" "all strategies underperforming" "new target type")
     :default :ontology)

    (:name "target-prioritization"
     :description "Which target to optimize next?"
     :ontology-rules ("high-value first" "moderate second" "low-value last" "unknown = moderate")
     :llm-when ("target has no code" "target is new module" "dependencies unknown")
     :default :ontology)

    (:name "outcome-prediction"
     :description "Will this experiment succeed?"
     :ontology-rules ("weighted: pair(3x) + strategy(2x) + target(1x) + trend(1x)")
     :llm-when ("insufficient data (< 3 experiments)" "recent paradigm shift" "external factors")
     :default :ontology)

    (:name "code-generation"
     :description "What code changes to make?"
     :ontology-rules nil
     :llm-when ("always" "code is unstructured" "semantic understanding required")
     :default :llm)

    (:name "quality-grading"
     :description "Is this code improvement good?"
     :ontology-rules ("automated metrics" "style checks" "test pass/fail")
     :llm-when ("subjective quality" "architecture decisions" "trade-off analysis")
     :default :llm)

    (:name "knowledge-synthesis"
     :description "What did we learn?"
     :ontology-rules ("pattern extraction" "statistical summaries" "trend detection")
     :llm-when ("insight generation" "causal reasoning" "analogy formation")
     :default :hybrid)

    (:name "competency-questions"
     :description "Can our ontology answer this?"
     :ontology-rules ("keyword matching" "class/property lookup" "threshold comparison")
     :llm-when ("question is novel" "requires inference" "cross-domain reasoning")
     :default :ontology))
  "Decision type catalog with ontology vs LLM guidance.")

;; ─── Formal Decider ───

(defun gptel-auto-workflow--decide-ontology-or-llm (decision-type data-availability complexity)
  "Decide whether to use ontology or LLM for DECISION-TYPE.
DATA-AVAILABILITY: :abundant :sparse :none
COMPLEXITY: :simple :moderate :complex
Returns :ontology, :llm, or :hybrid."
  (let* ((type-info (cl-find-if (lambda (d) (string= (plist-get d :name) decision-type))
                                gptel-auto-workflow--decision-types))
         (default (or (plist-get type-info :default) :llm))
         (result default))
    
    ;; Override based on data availability
    (when (eq data-availability :none)
      (setq result :llm))
    
    ;; Override based on complexity
    (when (eq complexity :complex)
      (setq result :llm))
    
    ;; Override: if ontology has explicit rules and data is sufficient
    (when (and (eq data-availability :abundant)
               (eq complexity :simple)
               (plist-get type-info :ontology-rules))
      (setq result :ontology))
    
    ;; Log decision
    (when gptel-auto-workflow--ontology-decision-log
      (message "[decider] %s: %s (data=%s complexity=%s default=%s)"
               decision-type result data-availability complexity default))
    
    result))

;; ─── Cost-Based Guard ───

(defun gptel-auto-workflow--guard-llm-with-ontology (decision-type fn &rest args)
  "Guard FN (an LLM call) with ontology pre-check.
If ontology can answer, skip LLM and return ontology result.
Otherwise, call FN with ARGS."
  (let ((decision (gptel-auto-workflow--decide-ontology-or-llm
                   decision-type :abundant :simple)))
    (if (eq decision 'ontology)
        (progn
          (message "[guard] %s → ontology (skipped LLM)" decision-type)
          (apply #'gptel-auto-workflow--ontology-answer decision-type args))
      (apply fn args))))

(defun gptel-auto-workflow--ontology-answer (decision-type &rest args)
  "Generate ontology-based answer for DECISION-TYPE.
ARGS are decision-specific parameters."
  (pcase decision-type
    ("pre-flight"
     (let ((strategy (car args))
           (target (cadr args)))
       (gptel-auto-workflow--experiment-preflight strategy target)))
    
    ("strategy-selection"
     (let ((strategies (car args))
           (target (cadr args)))
       (gptel-auto-workflow--select-best-strategy-with-ontology strategies target)))
    
    ("target-prioritization"
     (let ((targets (car args)))
       (gptel-auto-workflow--ontology-filter-targets targets)))
    
    ("outcome-prediction"
     (let ((strategy (car args))
           (target (cadr args)))
       (gptel-auto-workflow--predict-outcome strategy target)))
    
    (_ (error "Unknown decision type: %s" decision-type))))

;; ─── Decision Statistics ───

(defvar gptel-auto-workflow--decision-stats
  (make-hash-table :test 'equal)
  "Track ontology vs LLM decisions for analysis.")

(defun gptel-auto-workflow--record-decision (decision-type result &optional reason)
  "Record decision for analysis."
  (let* ((current (gethash decision-type gptel-auto-workflow--decision-stats
                            (list :ontology 0 :llm 0 :hybrid 0 :total 0)))
         (total (or (plist-get current :total) 0))
         (count (or (plist-get current result) 0)))
    (setq current (plist-put current :total (1+ total)))
    (setq current (plist-put current result (1+ count)))
    (puthash decision-type current gptel-auto-workflow--decision-stats)))

(defun gptel-auto-workflow--decision-stats-report ()
  "Generate report of ontology vs LLM usage."
  (let ((report nil))
    (maphash (lambda (type stats)
               (push (format "%s: %d total (%d ontology, %d llm, %d hybrid)"
                             type
                             (plist-get stats :total)
                             (plist-get stats :ontology)
                             (plist-get stats :llm)
                             (plist-get stats :hybrid))
                     report))
             gptel-auto-workflow--decision-stats)
    (sort report #'string<)))

;; ─── Advice Integration ───

(defun gptel-auto-workflow--install-ontology-guards ()
  "Install ontology guards on key decision points."
  ;; Guard experiment pre-flight
  (unless (advice-member-p #'gptel-auto-workflow--experiment-preflight-advice
                           #'gptel-auto-experiment-run)
    (advice-add 'gptel-auto-experiment-run
                :around #'gptel-auto-workflow--experiment-preflight-advice))
  
  ;; Guard strategy selection
  (when (fboundp 'gptel-auto-workflow--select-best-strategy)
    (unless (advice-member-p #'gptel-auto-workflow--ontology-enhance-strategy-selection
                             #'gptel-auto-workflow--select-best-strategy)
      (advice-add 'gptel-auto-workflow--select-best-strategy
                  :around #'gptel-auto-workflow--ontology-enhance-strategy-selection)))
  
  (message "[decider] Ontology guards installed"))

(defun gptel-auto-workflow--ontology-enhance-strategy-selection (orig-fun &rest args)
  "Advice to enhance strategy selection with ontology data."
  (let ((target (car args)))
    (if (and (fboundp 'gptel-auto-workflow--generate-experiment-ontology)
             (> (hash-table-count (plist-get (gptel-auto-workflow--generate-experiment-ontology)
                                             :classes)) 0))
        (let ((ontology-choice (gptel-auto-workflow--select-best-strategy-with-ontology
                                nil target)))
          (if ontology-choice
              (progn
                (gptel-auto-workflow--record-decision "strategy-selection" 'ontology)
                ontology-choice)
            (progn
              (gptel-auto-workflow--record-decision "strategy-selection" 'llm)
              (apply orig-fun args))))
      (apply orig-fun args))))

(provide 'gptel-auto-workflow-ontology-decider)
;;; gptel-auto-workflow-ontology-decider.el ends here
