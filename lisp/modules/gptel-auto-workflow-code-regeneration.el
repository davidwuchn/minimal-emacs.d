;;; gptel-auto-workflow-code-regeneration.el --- Code regeneration with context-aware prompts -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OV5 Self-Improving Architecture

;; Author: OV5 System
;; Keywords: regeneration, context, disposable-code, model-upgrade

;;; Commentary:

;; Phase 3 ext: Software as Consumable - Code Regeneration
;; Enables regeneration of modules when better models become available,
;; using context-database sidecar data to build richer prompts.
;;
;; Cross-module dependencies use declare-function + fboundp guards:
;;   - evolution.el: gptel-auto-workflow--evolution-model-stats (optional)
;;   - context-database.el: gptel-auto-workflow-context-db-* (primary data source)
;;   - experiment-core.el: gptel-auto-workflow--experiment-prompt-override (hook point)

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'gptel-auto-workflow-context-database nil t)

;; Forward declarations - never require at load time
(declare-function gptel-auto-workflow--evolution-model-stats
  "gptel-auto-workflow-evolution")
(declare-function gptel-auto-workflow-context-db-query
  "gptel-auto-workflow-context-database"
  (&key target strategy since before after decision))
(declare-function gptel-auto-workflow-context-db-read
  "gptel-auto-workflow-context-database"
  (experiment-id))
(declare-function gptel-auto-workflow-context-db-summary-for-target
  "gptel-auto-workflow-context-database"
  (target))
(declare-function gptel-auto-workflow--project-root
  "gptel-tools-agent-benchmark")

;; ============================================================================
;; Configuration
;; ============================================================================

(defcustom gptel-auto-workflow-regeneration-min-score-delta 0.05
  "Minimum score improvement delta to consider a regeneration candidate."
  :type 'float
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-regeneration-min-history-count 3
  "Minimum historical experiments to identify a regeneration candidate."
  :type 'integer
  :group 'gptel-tools-agent)

;; ============================================================================
;; Prompt Override Variable
;; ============================================================================

(defvar gptel-auto-workflow--experiment-prompt-override nil
  "When non-nil, overrides the experiment prompt entirely.
Set by regeneration workflow, cleared after each experiment run.")

;; ============================================================================
;; Core: prepare-context
;; ============================================================================

(defun gptel-auto-workflow-code-regeneration--prepare-context (module model-version)
  "Prepare regeneration context plist for MODULE targeting MODEL-VERSION.
Returns plist with :module :target-model :purpose :key-decisions
:historical-learnings :constraints :model-stats."
  (let* ((summary
          (when (fboundp 'gptel-auto-workflow-context-db-summary-for-target)
            (gptel-auto-workflow-context-db-summary-for-target module)))
         (contexts
          (when (fboundp 'gptel-auto-workflow-context-db-query)
            (gptel-auto-workflow-context-db-query :target module)))
         (model-stats
          (when (fboundp 'gptel-auto-workflow--evolution-model-stats)
            (gptel-auto-workflow--evolution-model-stats)))
         (learnings
          (delq nil
                (mapcar (lambda (ctx)
                          (plist-get ctx :learned))
                        (or contexts '()))))
         (decisions
          (delq nil
                (mapcar (lambda (ctx)
                          (plist-get ctx :decision-rationale))
                        (or contexts '()))))
         (purpose
          (when summary
            (let ((patterns (plist-get summary :common-patterns)))
              (if patterns
                  (mapconcat #'identity patterns "; ")
                "Improve code quality"))))
         (constraints
          (when contexts
            (delq nil
                  (mapcar (lambda (ctx)
                            (plist-get ctx :business-rationale))
                          contexts)))))
    (list :module module
          :target-model model-version
          :purpose (or purpose "Improve code quality")
          :key-decisions (or decisions '("No decisions recorded"))
          :historical-learnings (or learnings '("No learnings recorded"))
          :constraints (or constraints '("No constraints recorded"))
          :model-stats model-stats)))

;; ============================================================================
;; Core: generate-prompt
;; ============================================================================

(defun gptel-auto-workflow-code-regeneration--generate-prompt (regen-context)
  "Generate regeneration prompt from REGEN-CONTEXT plist.
Preserves institutional knowledge during model-upgrade regeneration."
  (let* ((module (plist-get regen-context :module))
         (model (plist-get regen-context :target-model))
         (purpose (plist-get regen-context :purpose))
         (decisions (plist-get regen-context :key-decisions))
         (learnings (plist-get regen-context :historical-learnings))
         (constraints (plist-get regen-context :constraints))
         (model-stats (plist-get regen-context :model-stats))
         (stats-line
          (if model-stats
              (mapconcat
               (lambda (entry)
                 (format "  %s: keep-rate %.2f"
                         (car entry)
                         (cdr entry)))
               (seq-take model-stats 5)
               "\n")
            "Model stats unavailable; evolution module not loaded")))
    (format "Regenerate module: %s\nTarget model: %s\n\nPurpose:\n%s\n\nKey Decisions:\n%s\n\nHistorical Learnings:\n%s\n\nConstraints:\n%s\n\nModel Performance Context:\n%s"
            module model
            (or purpose "No purpose specified")
            (or (mapconcat #'identity decisions "\n")
                "No decisions recorded")
            (or (mapconcat #'identity learnings "\n")
                "No learnings recorded")
            (or (mapconcat #'identity constraints "\n")
                "No constraints recorded")
            stats-line)))

;; ============================================================================
;; Core: identify-candidates
;; ============================================================================

(defun gptel-auto-workflow-code-regeneration--identify-candidates (&optional _args)
  "Identify modules that would benefit from regeneration with a better model.
Scans context-database sidecars for targets with sufficient history
and below-threshold improvement.  Returns nil if context-db unavailable."
  (when (fboundp 'gptel-auto-workflow-context-db-query)
    (let* ((all-contexts (gptel-auto-workflow-context-db-query))
           (by-target (make-hash-table :test 'equal))
           (candidates nil))
      ;; Phase 1: group contexts by target
      (dolist (ctx all-contexts)
        (let ((target (or (plist-get ctx :target) "")))
          (when (and target (not (string-empty-p target)))
            (let ((existing (gethash target by-target)))
              (puthash target
                       (if existing (cons ctx existing) (list ctx))
                       by-target))))))
      ;; Phase 2: analyze each target's history
      (maphash
       (lambda (target contexts)
         (when (>= (length contexts)
                   gptel-auto-workflow-regeneration-min-history-count)
           (let ((best-delta 0.0)
                 (best-model "unknown"))
(dolist (ctx2 contexts)
              (let* ((before (or (plist-get ctx2 :score-before) 0.0))
                     (after (or (plist-get ctx2 :score-after) 0.0))
                     (delta (- after before))
                     (model (or (plist-get ctx2 :model) "unknown")))
                 (when (> delta best-delta)
                   (setq best-delta delta)
                   (setq best-model model))))
             (when (< best-delta gptel-auto-workflow-regeneration-min-score-delta)
               (push (list :module target
                           :history-count (length contexts)
                           :best-delta best-delta
                           :current-best-model best-model)
                     candidates))))
       by-target)
      (nreverse candidates))))

;; ============================================================================
;; Core: full-workflow
;; ============================================================================

(defun gptel-auto-workflow-code-regeneration--full-workflow (module _current-model target-model)
  "Execute full regeneration workflow for MODULE to TARGET-MODEL.
Prepares context, generates prompt, sets experiment-prompt-override."
  (let* ((regen-context
          (gptel-auto-workflow-code-regeneration--prepare-context
           module target-model))
         (prompt
          (gptel-auto-workflow-code-regeneration--generate-prompt
           regen-context)))
    (setq gptel-auto-workflow--experiment-prompt-override prompt)
    (list :success t
          :module module
          :new-model target-model
          :prompt prompt
          :regen-context regen-context)))

(provide 'gptel-auto-workflow-code-regeneration)

;;; gptel-auto-workflow-code-regeneration.el ends here
