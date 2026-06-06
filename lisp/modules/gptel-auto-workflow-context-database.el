;;; gptel-auto-workflow-context-database.el --- Context database for business context preservation -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OV5 Self-Improving Architecture

;; Author: OV5 System
;; Keywords: context, database, business-context, regeneration

;;; Commentary:

;; Phase 3: Software as Consumable - Context Database
;; Preserves business context (why decisions were made, what was learned)
;; separate from code implementation, enabling code regeneration with better models.

;;; Code:

(require 'cl-lib)

;; ============================================================================
;; Configuration and State
;; ============================================================================

(defvar gptel-auto-workflow--context-db-config nil
  "Context database configuration.")

(defvar gptel-auto-workflow--context-store (make-hash-table :test 'equal)
  "In-memory store for experiment contexts.")

(defvar gptel-auto-workflow--module-context-store (make-hash-table :test 'equal)
  "In-memory store for module contexts.")

(defvar gptel-auto-workflow--regeneration-history (make-hash-table :test 'equal)
  "In-memory store for regeneration history.")

(defvar gptel-auto-workflow--scheduled-regenerations nil
  "List of scheduled regenerations.")

(defvar gptel-auto-workflow--disposable-modules (make-hash-table :test 'equal)
  "Set of modules marked as disposable.")

(defvar gptel-auto-workflow--preserved-contexts (make-hash-table :test 'equal)
  "Store for preserved contexts before disposal.")

;; ============================================================================
;; Task 3.1: Business Context Preservation System
;; ============================================================================

(defun gptel-auto-workflow--context-db-init (config)
  "Initialize context database with CONFIG."
  (setq gptel-auto-workflow--context-db-config config)
  t)

(defun gptel-auto-workflow--context-db-configured-p ()
  "Return t if context database is configured."
  (not (null gptel-auto-workflow--context-db-config)))

(defun gptel-auto-workflow--capture-context (experiment)
  "Capture business context for EXPERIMENT."
  (condition-case err
      (let ((id (plist-get experiment :id)))
        (puthash id experiment gptel-auto-workflow--context-store)
        t)
    (error
     (message "[context-db] Failed to capture context: %s" err)
     nil)))

(defun gptel-auto-workflow--get-context (experiment-id)
  "Get context for EXPERIMENT-ID."
  (gethash experiment-id gptel-auto-workflow--context-store))

(defun gptel-auto-workflow--capture-module-context (module-context)
  "Capture context for module in MODULE-CONTEXT."
  (condition-case err
      (let ((module (plist-get module-context :module)))
        (puthash module module-context gptel-auto-workflow--module-context-store)
        t)
    (error
     (message "[context-db] Failed to capture module context: %s" err)
     nil)))

(defun gptel-auto-workflow--get-module-context (module)
  "Get context for MODULE."
  (gethash module gptel-auto-workflow--module-context-store))

(defun gptel-auto-workflow--update-module-context (module-context)
  "Update context for module in MODULE-CONTEXT."
  (let* ((module (plist-get module-context :module))
         (existing (gptel-auto-workflow--get-module-context module)))
    (when existing
      ;; Merge new context with existing
      (let ((merged (append module-context existing)))
        (puthash module merged gptel-auto-workflow--module-context-store)))))

(defun gptel-auto-workflow--context-db-query (query params)
  "Execute database QUERY with PARAMS.
This is a stub for testing - would execute actual SQL in production."
  nil)

(defun gptel-auto-workflow--query-context-by-module (module)
  "Query all contexts for MODULE."
  (let ((results nil))
    (maphash (lambda (id ctx)
               (when (string= (plist-get ctx :target) module)
                 (push ctx results)))
             gptel-auto-workflow--context-store)
    results))

(defun gptel-auto-workflow--query-context-by-time-range (start-time end-time)
  "Query contexts between START-TIME and END-TIME."
  (let ((results nil))
    (maphash (lambda (id ctx)
               (let ((timestamp (plist-get ctx :timestamp)))
                 (when (and timestamp
                            (not (string< timestamp start-time))
                            (not (string< end-time timestamp)))
                   (push ctx results))))
             gptel-auto-workflow--context-store)
    results))

(defun gptel-auto-workflow--update-context (update)
  "Update existing context with UPDATE."
  (condition-case err
      (let* ((id (plist-get update :id))
             (existing (gptel-auto-workflow--get-context id)))
        (when existing
          (let ((merged (append update existing)))
            (puthash id merged gptel-auto-workflow--context-store)
            t)))
    (error
     (message "[context-db] Failed to update context: %s" err)
     nil)))

(defun gptel-auto-workflow--delete-context (experiment-id)
  "Delete context for EXPERIMENT-ID."
  (remhash experiment-id gptel-auto-workflow--context-store)
  t)

;; ============================================================================
;; Task 3.2: Code Regeneration Infrastructure
;; ============================================================================

(defun gptel-auto-workflow--prepare-regeneration-context (module model-version)
  "Prepare context for regenerating MODULE with MODEL-VERSION."
  (let* ((module-context (gptel-auto-workflow--get-module-context module))
         (historical-contexts (gptel-auto-workflow--query-context-by-module module))
         (historical-learnings (mapcar (lambda (ctx)
                                         (plist-get ctx :learnings))
                                       historical-contexts)))
    (list :module module
          :target-model model-version
          :purpose (plist-get module-context :purpose)
          :key-decisions (plist-get module-context :key-decisions)
          :historical-learnings historical-learnings
          :constraints (plist-get module-context :constraints))))

(defun gptel-auto-workflow--generate-regeneration-prompt (regen-context)
  "Generate prompt for code regeneration from REGEN-CONTEXT."
  (let ((module (plist-get regen-context :module))
        (model (plist-get regen-context :target-model))
        (purpose (plist-get regen-context :purpose))
        (decisions (plist-get regen-context :key-decisions))
        (learnings (plist-get regen-context :historical-learnings))
        (constraints (plist-get regen-context :constraints)))
    (format "Regenerate module: %s\nTarget model: %s\n\nPurpose:\n%s\n\nKey Decisions:\n%s\n\nHistorical Learnings:\n%s\n\nConstraints:\n%s"
            module
            model
            (or purpose "No purpose specified")
            (or (mapconcat #'identity decisions "\n") "No decisions recorded")
            (or (mapconcat #'identity learnings "\n") "No learnings recorded")
            (or (mapconcat #'identity constraints "\n") "No constraints recorded"))))

(defun gptel-auto-workflow--track-regeneration (regeneration)
  "Track code REGENERATION event."
  (let* ((module (plist-get regeneration :module))
         (history (gethash module gptel-auto-workflow--regeneration-history nil)))
    (push regeneration history)
    (puthash module history gptel-auto-workflow--regeneration-history)
    t))

(defun gptel-auto-workflow--get-regeneration-history (module)
  "Get regeneration history for MODULE."
  (gethash module gptel-auto-workflow--regeneration-history))

(defun gptel-auto-workflow--compare-regeneration-versions (version1 version2)
  "Compare two regeneration VERSION1 and VERSION2."
  (let* ((metrics1 (plist-get version1 :metrics))
         (metrics2 (plist-get version2 :metrics))
         (perf1 (plist-get metrics1 :performance))
         (perf2 (plist-get metrics2 :performance))
         (read1 (plist-get metrics1 :readability))
         (read2 (plist-get metrics2 :readability))
         (perf-improvement (> perf2 perf1))
         (read-improvement (> read2 read1))
         (recommended (if (and perf-improvement read-improvement)
                          :version2
                        (if (or perf-improvement read-improvement)
                            :version2
                          :version1))))
    (list :performance-improvement perf-improvement
          :readability-improvement read-improvement
          :recommended recommended)))

;; ============================================================================
;; Task 3.3: Disposable Code Practices
;; ============================================================================

(defun gptel-auto-workflow--get-all-modules ()
  "Get list of all modules.
This is a stub - would scan actual codebase in production."
  nil)

(defun gptel-auto-workflow--module-age (module)
  "Get age of MODULE in days.
This is a stub - would check git history in production."
  0)

(defun gptel-auto-workflow--latest-model-available ()
  "Get latest available model version.
This is a stub - would query model registry in production."
  "gpt-4")

(defun gptel-auto-workflow--module-model-version (module)
  "Get model version used to generate MODULE.
This is a stub - would check metadata in production."
  "gpt-4")

(defun gptel-auto-workflow--identify-regeneration-candidates (&rest args)
  "Identify modules ready for regeneration.
ARGS may include :max-age-days and :require-newer-model."
  (let ((max-age (plist-get args :max-age-days))
        (require-newer (plist-get args :require-newer-model))
        (candidates nil)
        (latest-model (gptel-auto-workflow--latest-model-available)))
    (dolist (module (gptel-auto-workflow--get-all-modules))
      (let ((age (gptel-auto-workflow--module-age module))
            (current-model (gptel-auto-workflow--module-model-version module)))
        (when (or (and max-age (> age max-age))
                  (and require-newer
                       (not (string= current-model latest-model))))
          (push module candidates))))
    candidates))

(defun gptel-auto-workflow--estimate-regeneration-value (module current-metrics expected-improvements)
  "Estimate value of regenerating MODULE.
CURRENT-METRICS and EXPECTED-IMPROVEMENTS are plists."
  (let* ((perf-current (plist-get current-metrics :performance))
         (perf-mult (plist-get expected-improvements :performance))
         (perf-gain (* perf-current (- perf-mult 1.0)))
         (maint-current (plist-get current-metrics :maintainability))
         (maint-mult (plist-get expected-improvements :maintainability))
         (maint-gain (* maint-current (- maint-mult 1.0)))
         (overall-score (/ (+ perf-gain maint-gain) 2.0)))
    (list :performance-gain perf-gain
          :maintainability-gain maint-gain
          :overall-value-score overall-score)))

(defun gptel-auto-workflow--schedule-regeneration (module &rest args)
  "Schedule regeneration for MODULE.
ARGS may include :priority and :scheduled-time."
  (let ((scheduled (list :module module
                         :priority (plist-get args :priority)
                         :scheduled-time (plist-get args :scheduled-time))))
    (push scheduled gptel-auto-workflow--scheduled-regenerations)
    t))

(defun gptel-auto-workflow--get-scheduled-regenerations ()
  "Get list of scheduled regenerations."
  gptel-auto-workflow--scheduled-regenerations)

(defun gptel-auto-workflow--mark-as-disposable (module)
  "Mark MODULE as disposable."
  (puthash module t gptel-auto-workflow--disposable-modules)
  t)

(defun gptel-auto-workflow--get-disposable-status (module)
  "Get disposable status of MODULE."
  (if (gethash module gptel-auto-workflow--disposable-modules)
      :disposable
    :persistent))

(defun gptel-auto-workflow--preserve-context-before-disposal (module)
  "Preserve context for MODULE before disposal."
  (let ((context (gptel-auto-workflow--get-module-context module)))
    (when context
      (puthash module context gptel-auto-workflow--preserved-contexts)
      t)))

(defun gptel-auto-workflow--get-preserved-context (module)
  "Get preserved context for MODULE."
  (gethash module gptel-auto-workflow--preserved-contexts))

;; ============================================================================
;; Integration Functions
;; ============================================================================

(defun gptel-auto-workflow--full-regeneration-workflow (module current-model target-model)
  "Run full regeneration workflow for MODULE.
CURRENT-MODEL is the current model, TARGET-MODEL is the target."
  (condition-case err
      (let* ((regen-context (gptel-auto-workflow--prepare-regeneration-context
                             module target-model))
             (prompt (gptel-auto-workflow--generate-regeneration-prompt regen-context))
             ;; In production, would actually regenerate code here
             (regeneration (list :module module
                                 :from-model current-model
                                 :to-model target-model
                                 :timestamp (format-time-string "%Y-%m-%dT%H:%M:%SZ")
                                 :context-preserved t)))
        (gptel-auto-workflow--track-regeneration regeneration)
        (list :success t
              :module module
              :new-model target-model
              :prompt prompt))
    (error
     (message "[context-db] Regeneration workflow failed: %s" err)
     (list :success nil
           :error (error-message-string err)))))

(defun gptel-auto-workflow--context-db-execute (query params)
  "Execute database QUERY with PARAMS.
This is a stub for testing."
  nil)

(provide 'gptel-auto-workflow-context-database)

;;; gptel-auto-workflow-context-database.el ends here
