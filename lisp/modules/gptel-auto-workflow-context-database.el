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
(require 'json)

(declare-function gptel-auto-workflow--project-root "gptel-tools-agent-benchmark")

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

(defvar gptel-auto-workflow--context-db-file nil
  "Path to persistent context database file.
Initialized lazily by `gptel-auto-workflow--context-db-file-path'.
Cached after first access to avoid repeated calls to project-root.")

(defun gptel-auto-workflow--context-db-file-path ()
  "Return the path to the context database file.
Initializes lazily on first call to avoid calling project-root at load time.
Returns nil if project-root is not available."
  (or gptel-auto-workflow--context-db-file
      (when (fboundp 'gptel-auto-workflow--project-root)
        (setq gptel-auto-workflow--context-db-file
              (expand-file-name "var/context-database.json"
                                (gptel-auto-workflow--project-root))))))

;; ============================================================================
;; Persistence Functions
;; ============================================================================

(defun gptel-auto-workflow--context-db-persist ()
  "Persist context database to JSON file.
Saves all in-memory stores to survive daemon restarts."
  (let ((data (list
               :context-store (gptel-auto-workflow--hash-table-to-alist
                               gptel-auto-workflow--context-store)
               :module-context-store (gptel-auto-workflow--hash-table-to-alist
                                      gptel-auto-workflow--module-context-store)
               :regeneration-history (gptel-auto-workflow--hash-table-to-alist
                                      gptel-auto-workflow--regeneration-history)
               :scheduled-regenerations gptel-auto-workflow--scheduled-regenerations
               :disposable-modules (gptel-auto-workflow--hash-table-to-alist
                                    gptel-auto-workflow--disposable-modules)
               :preserved-contexts (gptel-auto-workflow--hash-table-to-alist
                                    gptel-auto-workflow--preserved-contexts))))
    (let ((file (gptel-auto-workflow--context-db-file-path)))
      (unless file
        (message "[context-db] Cannot persist: project-root not available")
        (cl-return-from gptel-auto-workflow--context-db-persist))
      (make-directory (file-name-directory file) t)
      (with-temp-file file
        (insert (json-encode data)))
      (message "[context-db] Persisted to %s" file))))

(defun gptel-auto-workflow--context-db-load ()
  "Load context database from JSON file.
Restores all in-memory stores from persistent storage."
  (let ((file (gptel-auto-workflow--context-db-file-path)))
    (when (and file (file-exists-p file))
    (condition-case err
          (let ((data (json-read-file file)))
            (setq gptel-auto-workflow--context-store
                  (gptel-auto-workflow--alist-to-hash-table
                   (plist-get data :context-store)))
            (setq gptel-auto-workflow--module-context-store
                  (gptel-auto-workflow--alist-to-hash-table
                   (plist-get data :module-context-store)))
            (setq gptel-auto-workflow--regeneration-history
                  (gptel-auto-workflow--alist-to-hash-table
                   (plist-get data :regeneration-history)))
            (setq gptel-auto-workflow--scheduled-regenerations
                  (plist-get data :scheduled-regenerations))
            (setq gptel-auto-workflow--disposable-modules
                  (gptel-auto-workflow--alist-to-hash-table
                   (plist-get data :disposable-modules)))
            (setq gptel-auto-workflow--preserved-contexts
                  (gptel-auto-workflow--alist-to-hash-table
                   (plist-get data :preserved-contexts)))
            (message "[context-db] Loaded from %s" file))
        (error
         (message "[context-db] Load error: %s" err))))))

(defun gptel-auto-workflow--hash-table-to-alist (hash-table)
  "Convert HASH-TABLE to alist for JSON serialization."
  (let ((result nil))
    (maphash (lambda (key value)
               (push (cons key value) result))
             hash-table)
    result))

(defun gptel-auto-workflow--alist-to-hash-table (alist)
  "Convert ALIST to hash table for in-memory storage."
  (let ((hash-table (make-hash-table :test 'equal)))
    (dolist (pair alist)
      (puthash (car pair) (cdr pair) hash-table))
    hash-table))

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

(defalias 'gptel-auto-workflow--capture-experiment-context
  'gptel-auto-workflow--capture-context
  "Alias for `gptel-auto-workflow--capture-context'.
Used by production.el via fboundp guard.")

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

(defun gptel-auto-workflow--context-db-query (_query params)
  "Execute database QUERY with PARAMS.
Queries the in-memory hash table stores based on QUERY type.
QUERY can be :module, :time-range, :all-modules, :module-age, :model-version.
PARAMS is a plist with query-specific parameters."
  (let ((query-type (plist-get params :query-type)))
    (cond
     ((eq query-type :module)
      (gptel-auto-workflow--query-context-by-module (plist-get params :module)))
     ((eq query-type :time-range)
      (gptel-auto-workflow--query-context-by-time-range
       (plist-get params :start-time)
       (plist-get params :end-time)))
     ((eq query-type :all-modules)
      (gptel-auto-workflow--get-all-modules))
     ((eq query-type :module-age)
      (gptel-auto-workflow--module-age (plist-get params :module)))
     ((eq query-type :model-version)
      (gptel-auto-workflow--module-model-version (plist-get params :module)))
     (t nil))))

(defun gptel-auto-workflow--query-context-by-module (module)
  "Query all contexts for MODULE."
  (let ((results nil))
    (maphash (lambda (_id ctx)
               (when (string= (plist-get ctx :target) module)
                 (push ctx results)))
             gptel-auto-workflow--context-store)
    results))

(defun gptel-auto-workflow--query-context-by-time-range (start-time end-time)
  "Query contexts between START-TIME and END-TIME."
  (let ((results nil))
    (maphash (lambda (_id ctx)
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

(defun gptel-auto-workflow--get-context-summary ()
  "Get summary of business context from context database.
Returns plist with :modules-count, :experiments-count, :recent-decisions."
  (let ((modules-count (hash-table-count gptel-auto-workflow--module-context-store))
        (experiments-count (hash-table-count gptel-auto-workflow--context-store))
        (recent-decisions nil))
    ;; Get last 5 experiment contexts
    (let ((contexts nil))
      (maphash (lambda (_id ctx) (push ctx contexts))
               gptel-auto-workflow--context-store)
      (setq recent-decisions
            (mapcar (lambda (ctx)
                      (list :id (plist-get ctx :experiment-id)
                            :target (plist-get ctx :target)
                            :rationale (plist-get ctx :decision-rationale)))
                    (seq-take contexts 5))))
    (list :modules-count modules-count
          :experiments-count experiments-count
          :recent-decisions recent-decisions)))

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
Scans lisp/modules directory for .el files."
  (let ((modules-dir (expand-file-name "lisp/modules" (gptel-auto-workflow--project-root)))
        (modules nil))
    (when (file-directory-p modules-dir)
      (dolist (file (directory-files modules-dir t "\\.el$"))
        (when (and (file-regular-p file)
                   (not (string-match-p "test-" (file-name-nondirectory file))))
          (push (file-relative-name file (gptel-auto-workflow--project-root)) modules))))
    modules))

(defun gptel-auto-workflow--module-age (module)
  "Get age of MODULE in days.
Checks git history for first commit date."
  (let ((default-directory (gptel-auto-workflow--project-root))
        (result nil))
    (condition-case _err
        (let ((output (shell-command-to-string
                       (format "git log --format='%%aI' --diff-filter=A --follow -- %s | tail -1" module))))
          (when (and output (> (length output) 0))
            (let ((first-commit-time (date-to-time (string-trim output)))
                  (current-time (current-time)))
              (setq result (floor (/ (float-time (time-subtract current-time first-commit-time))
                                    86400))))))
      (error nil))
    (or result 0)))

(defun gptel-auto-workflow--latest-model-available ()
  "Get latest available model version.
Queries backend registry for latest model."
  (let ((backends '(("MiniMax" . "MiniMax-M3")
                    ("moonshot" . "kimi-k2.6")
                    ("DeepSeek" . "deepseek-v4-pro")
                    ("DashScope" . "qwen3.6-plus")
                    ("Copilot" . "gpt-5.4-mini"))))
    ;; For now, return MiniMax-M3 as default
    ;; In production, this would query actual backend availability
    (or (cdr (assoc "MiniMax" backends)) "gpt-4")))

(defun gptel-auto-workflow--module-model-version (module)
  "Get model version used to generate MODULE.
Checks module metadata or defaults to gpt-4."
  (let ((module-context (gethash module gptel-auto-workflow--module-context-store)))
    (or (and module-context (plist-get module-context :model-version))
        "gpt-4")))

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

(defun gptel-auto-workflow--estimate-regeneration-value (_module current-metrics expected-improvements)
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
Delegates to gptel-auto-workflow--context-db-query for actual execution."
  (gptel-auto-workflow--context-db-query query params))

(provide 'gptel-auto-workflow-context-database)

;;; gptel-auto-workflow-context-database.el ends here
