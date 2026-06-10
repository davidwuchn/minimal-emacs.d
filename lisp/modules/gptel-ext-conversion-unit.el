;;; gptel-ext-conversion-unit.el --- Sibyl-style auditable conversion units -*- lexical-binding: t; -*-

;; Part of the Ouroboros V5 self-evolving pipeline.
;; Inspired by Sibyl-AutoResearch (2605.22343) trial-to-behavior conversion.
;;
;; Core principle: Every ontology update is an auditable conversion unit
;; linking a specific trial to a specific ontology change.

;;; Commentary:
;; This module tracks how experiment outcomes translate into ontology updates.
;; Each conversion unit records:
;;   - trial-id: source experiment or trial
;;   - conversion-type: behavior | harness-behavior | drift | repair
;;   - before-state: ontology state before conversion
;;   - after-state: ontology state after conversion
;;   - timestamp: when conversion occurred
;;   - validation-status: pending | validated | rejected | orphaned
;;   - source-file: file or module that initiated the conversion
;;
;; Conversion units persist to JSONL for auditability and rotation.

;;; Code:

(require 'cl-lib)
(require 'json)

;; ─── Customization ───

(defcustom gptel-conversion-unit-enabled t
  "When non-nil, track ontology updates as auditable conversion units.
Disabling skips conversion tracking (legacy behavior)."
  :type 'boolean
  :group 'gptel-tools-agent)

(defcustom gptel-conversion-unit-persist-dir
  (expand-file-name "var/tmp/conversion-units/"
                    (or (and (fboundp 'gptel-auto-workflow--project-root)
                             (gptel-auto-workflow--project-root))
                        default-directory))
  "Directory for persisting conversion unit JSONL files.
Files are named YYYY-MM.jsonl."
  :type 'directory
  :group 'gptel-tools-agent)

(defcustom gptel-conversion-unit-max-age-days 90
  "Maximum age in days for conversion unit JSONL files.
Older files are deleted during rotation."
  :type 'integer
  :group 'gptel-tools-agent)

;; ─── Data Structure ───

(cl-defstruct (gptel-conversion-unit
               (:constructor gptel-conversion-unit--create)
               (:copier nil))
  "Auditable record of an ontology update.
Fields:
  id — Unique identifier (timestamp-based)
  trial-id — Source experiment or trial identifier
  conversion-type — Symbol: behavior, harness-behavior, drift, repair, evolution
  before-state — Plist describing state before change
  after-state — Plist describing state after change
  timestamp — Unix timestamp of conversion
  validation-status — Symbol: pending, validated, rejected, orphaned
  source-file — Module or file initiating the conversion
  context — Optional additional context (plist)"
  id trial-id conversion-type before-state after-state
  timestamp validation-status source-file context)

;; ─── Registry ───

(defvar gptel-conversion-unit--registry (make-hash-table :test 'equal)
  "Hash table mapping conversion unit IDs to `gptel-conversion-unit' structs.
In-memory registry.  Persisted to JSONL periodically.")

(defvar gptel-conversion-unit--last-persist-time nil
  "Timestamp of last persistence operation.
Used to throttle frequent saves.")

(defvar gptel-conversion-unit--persist-interval 300
  "Minimum seconds between automatic persistence.
Prevents excessive disk writes.")

;; ─── Core Operations ───

(defun gptel-conversion-unit-add (trial-id conversion-type before-state after-state
                                        &optional source-file context)
  "Create and register a new conversion unit.
TRIAL-ID identifies the source experiment.
CONVERSION-TYPE is a symbol: \='behavior, \='harness-behavior,
\='drift, \='repair, or \='evolution.
BEFORE-STATE and AFTER-STATE are plists describing ontology state.
Optional SOURCE-FILE and CONTEXT provide additional traceability.
Returns the created conversion unit struct."
  (when gptel-conversion-unit-enabled
    (let* ((id (format "%s-%s-%s"
                       (format-time-string "%Y%m%d%H%M%S")
                       conversion-type
                       (or trial-id "unknown")))
           (unit (gptel-conversion-unit--create
                  :id id
                  :trial-id trial-id
                  :conversion-type conversion-type
                  :before-state before-state
                  :after-state after-state
                  :timestamp (float-time)
                  :validation-status 'pending
                  :source-file (or source-file "unknown")
                  :context (or context nil))))
      (puthash id unit gptel-conversion-unit--registry)
      (message "[conversion-unit] Added %s (%s → %s)"
               id conversion-type
               (or (plist-get after-state :category)
                   (or (plist-get after-state :change)
                       "unknown")))
      ;; Auto-persist if enough time elapsed
      (gptel-conversion-unit--maybe-persist)
      unit)))

(defun gptel-conversion-unit-get (id)
  "Retrieve conversion unit by ID.
Returns the struct or nil if not found."
  (gethash id gptel-conversion-unit--registry))

(defun gptel-conversion-unit-list (&optional filter-fn)
  "Return all conversion units as a list.
If FILTER-FN is provided, only return units where (FILTER-FN unit) is non-nil.
Sorted by timestamp descending (newest first)."
  (let ((result nil))
    (maphash (lambda (_id unit)
               (when (or (null filter-fn)
                         (funcall filter-fn unit))
                 (push unit result)))
             gptel-conversion-unit--registry)
    (sort result (lambda (a b)
                   (> (gptel-conversion-unit-timestamp a)
                       (gptel-conversion-unit-timestamp b))))))

(defun gptel-conversion-unit-count ()
  "Return total number of conversion units in registry."
  (hash-table-count gptel-conversion-unit--registry))

(defun gptel-conversion-unit-clear ()
  "Clear the in-memory registry.
Does not affect persisted JSONL files."
  (clrhash gptel-conversion-unit--registry)
  (message "[conversion-unit] Registry cleared"))

;; ─── Filtering ───

(defun gptel-conversion-unit-filter-by-trial (trial-id)
  "Return all conversion units for TRIAL-ID."
  (gptel-conversion-unit-list
   (lambda (unit)
     (equal (gptel-conversion-unit-trial-id unit) trial-id))))

(defun gptel-conversion-unit-filter-by-type (conversion-type)
  "Return all conversion units of CONVERSION-TYPE."
  (gptel-conversion-unit-list
   (lambda (unit)
     (eq (gptel-conversion-unit-conversion-type unit) conversion-type))))

(defun gptel-conversion-unit-filter-by-validation (status)
  "Return all conversion units with VALIDATION-STATUS."
  (gptel-conversion-unit-list
   (lambda (unit)
     (eq (gptel-conversion-unit-validation-status unit) status))))

;; ─── Validation ───

(defun gptel-conversion-unit-validate (id &optional status)
  "Mark conversion unit ID as validated.
Optional STATUS defaults to `\='validated'.
Can also be `\='rejected'."
  (let ((unit (gptel-conversion-unit-get id)))
    (when unit
      (setf (gptel-conversion-unit-validation-status unit)
            (or status 'validated))
      (message "[conversion-unit] %s → %s" id (or status 'validated))
      t)))

(defun gptel-conversion-unit-mark-orphaned (id)
  "Mark conversion unit ID as orphaned (no matching trial evidence)."
  (gptel-conversion-unit-validate id 'orphaned))

;; ─── Serialization ───

(defun gptel-conversion-unit--to-plist (unit)
  "Convert UNIT struct to plist for JSON serialization."
  (list :id (gptel-conversion-unit-id unit)
        :trial-id (gptel-conversion-unit-trial-id unit)
        :conversion-type (symbol-name (gptel-conversion-unit-conversion-type unit))
        :before-state (gptel-conversion-unit-before-state unit)
        :after-state (gptel-conversion-unit-after-state unit)
        :timestamp (gptel-conversion-unit-timestamp unit)
        :validation-status (symbol-name (gptel-conversion-unit-validation-status unit))
        :source-file (gptel-conversion-unit-source-file unit)
        :context (gptel-conversion-unit-context unit)))

(defun gptel-conversion-unit--from-plist (plist)
  "Create unit struct from PLIST (from JSON deserialization)."
  (gptel-conversion-unit--create
   :id (plist-get plist :id)
   :trial-id (plist-get plist :trial-id)
   :conversion-type (intern (or (plist-get plist :conversion-type) "unknown"))
   :before-state (plist-get plist :before-state)
   :after-state (plist-get plist :after-state)
   :timestamp (plist-get plist :timestamp)
   :validation-status (intern (or (plist-get plist :validation-status) "pending"))
   :source-file (or (plist-get plist :source-file) "unknown")
   :context (plist-get plist :context)))

;; ─── Persistence ───

(defun gptel-conversion-unit--current-file ()
  "Return path to current month's JSONL file."
  (expand-file-name (format "%s.jsonl" (format-time-string "%Y-%m"))
                    gptel-conversion-unit-persist-dir))

(defun gptel-conversion-unit-persist ()
  "Save all conversion units to JSONL.
Appends to current month's file.  Creates directory if needed."
  (when (> (hash-table-count gptel-conversion-unit--registry) 0)
    (let ((file (gptel-conversion-unit--current-file)))
      (make-directory (file-name-directory file) t)
      (with-temp-file file
        (maphash (lambda (_id unit)
                   (insert (json-serialize (gptel-conversion-unit--to-plist unit)))
                   (insert "\n"))
                 gptel-conversion-unit--registry))
      (setq gptel-conversion-unit--last-persist-time (float-time))
      (message "[conversion-unit] Persisted %d units to %s"
               (hash-table-count gptel-conversion-unit--registry)
               (file-name-nondirectory file)))))

(defun gptel-conversion-unit--maybe-persist ()
  "Auto-persist if enough time has elapsed since last save."
  (when (or (null gptel-conversion-unit--last-persist-time)
            (> (- (float-time) gptel-conversion-unit--last-persist-time)
               gptel-conversion-unit--persist-interval))
    (gptel-conversion-unit-persist)))

(defun gptel-conversion-unit-load ()
  "Load conversion units from current month's JSONL file.
Merges with existing registry (units with same ID are overwritten)."
  (let ((file (gptel-conversion-unit--current-file)))
    (when (file-exists-p file)
      (let ((count 0))
        (with-temp-buffer
          (insert-file-contents file)
          (goto-char (point-min))
          (while (not (eobp))
            (let* ((line (buffer-substring-no-properties
                          (line-beginning-position)
                          (line-end-position)))
                   (plist (condition-case nil
                              (json-parse-string line
                                                 :object-type 'plist
                                                 :null-object nil)
                            (error nil))))
              (when plist
                (let ((unit (gptel-conversion-unit--from-plist plist)))
                  (puthash (gptel-conversion-unit-id unit) unit
                           gptel-conversion-unit--registry)
                  (cl-incf count))))
            (forward-line)))
        (message "[conversion-unit] Loaded %d units from %s"
                 count (file-name-nondirectory file))))))

(defun gptel-conversion-unit-rotate ()
  "Delete JSONL files older than `gptel-conversion-unit-max-age-days'."
  (when (file-directory-p gptel-conversion-unit-persist-dir)
    (let* ((cutoff (- (float-time)
                      (* gptel-conversion-unit-max-age-days 24 60 60)))
           (deleted 0))
      (dolist (file (directory-files gptel-conversion-unit-persist-dir t
                                     "\.jsonl$"))
        (when (> cutoff (float-time (nth 5 (file-attributes file))))
          (delete-file file)
          (cl-incf deleted)))
      (when (> deleted 0)
        (message "[conversion-unit] Rotated %d old JSONL files" deleted)))))

;; ─── Stats ───

(defun gptel-conversion-unit-stats ()
  "Return human-readable statistics about conversion units."
  (let ((total (gptel-conversion-unit-count))
        (pending 0) (validated 0) (rejected 0) (orphaned 0))
    (maphash (lambda (_id unit)
               (pcase (gptel-conversion-unit-validation-status unit)
                 ('pending (cl-incf pending))
                 ('validated (cl-incf validated))
                 ('rejected (cl-incf rejected))
                 ('orphaned (cl-incf orphaned))))
             gptel-conversion-unit--registry)
    (format "[conversion-unit] Total: %d | Pending: %d | Validated: %d | Rejected: %d | Orphaned: %d"
            total pending validated rejected orphaned)))

;; ─── Audit ───

(defun gptel-conversion-unit-audit ()
  "Validate conversion units against available trial evidence.
Marks units as orphaned if their trial-id cannot be found in
experiment results (TSV files).
Returns count of orphaned units found."
  (let ((orphaned-count 0)
        (trial-ids (gptel-conversion-unit--collect-trial-ids)))
    (maphash
     (lambda (id unit)
       (when (and (eq (gptel-conversion-unit-validation-status unit) 'pending)
                  (not (member (gptel-conversion-unit-trial-id unit) trial-ids)))
         (setf (gptel-conversion-unit-validation-status unit) 'orphaned)
         (cl-incf orphaned-count)
         (message "[conversion-unit] Orphaned: %s (trial %s not found)"
                  id (gptel-conversion-unit-trial-id unit))))
     gptel-conversion-unit--registry)
    (message "[conversion-unit] Audit complete: %d orphaned" orphaned-count)
    orphaned-count))

(defun gptel-conversion-unit--collect-trial-ids ()
  "Collect all trial IDs from experiment TSV files.
Returns list of strings.  Expensive — call sparingly."
  (let ((ids nil)
        (root (or (and (fboundp 'gptel-auto-workflow--project-root)
                       (gptel-auto-workflow--project-root))
                  default-directory)))
    (dolist (tsv-file (directory-files-recursively
                        (expand-file-name "var/tmp/experiments" root)
                        "results\\.tsv$"))
      (with-temp-buffer
        (insert-file-contents tsv-file)
        (goto-char (point-min))
        ;; Skip header
        (forward-line)
        (while (not (eobp))
          (let* ((line (buffer-substring-no-properties
                        (line-beginning-position)
                        (line-end-position)))
                 (cols (split-string line "\t")))
            (when (> (length cols) 1)
              (push (string-trim (car cols)) ids)))
          (forward-line))))
    (delete-dups ids)))

;; ─── Export ───

(defun gptel-conversion-unit-export-to-tsv (&optional file)
  "Export all conversion units to TSV.
Optional FILE defaults to var/tmp/conversion-units-export.tsv.
Returns path to exported file."
  (let* ((root (or (and (fboundp 'gptel-auto-workflow--project-root)
                        (gptel-auto-workflow--project-root))
                   default-directory))
         (outfile (or file
                      (expand-file-name "var/tmp/conversion-units-export.tsv" root))))
    (make-directory (file-name-directory outfile) t)
    (with-temp-file outfile
      (insert "id\ttrial-id\tconversion-type\ttimestamp\tvalidation-status\tsource-file\tbefore-state\tafter-state\n")
      (dolist (unit (gptel-conversion-unit-list))
        (insert (format "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n"
                        (gptel-conversion-unit-id unit)
                        (gptel-conversion-unit-trial-id unit)
                        (symbol-name (gptel-conversion-unit-conversion-type unit))
                        (format-time-string "%Y-%m-%d %H:%M:%S"
                                            (seconds-to-time
                                             (gptel-conversion-unit-timestamp unit)))
                        (symbol-name (gptel-conversion-unit-validation-status unit))
                        (gptel-conversion-unit-source-file unit)
                        (prin1-to-string (gptel-conversion-unit-before-state unit))
                        (prin1-to-string (gptel-conversion-unit-after-state unit))))))
    (message "[conversion-unit] Exported %d units to %s"
             (gptel-conversion-unit-count) outfile)
    outfile))

;; ─── Integration Helpers ───

(defun gptel-conversion-unit-record-repair (target current-cat suggested-cat delta)
  "Record an ontology repair as a conversion unit.
Called by `gptel-auto-workflow--repair-ontology' for each
recategorization suggestion."
  (gptel-conversion-unit-add
   (format "repair-%s" target)
   'repair
   (list :target target :category current-cat)
   (list :target target :category suggested-cat :delta delta)
   "gptel-auto-workflow-ontology-router.el"
   (list :delta delta)))

(defun gptel-conversion-unit-record-drift (target category delta)
  "Record a category drift detection as a conversion unit.
Called by `gptel-auto-workflow--detect-category-drift' for each drift."
  (gptel-conversion-unit-add
   (format "drift-%s" target)
   'drift
   (list :target target :category category)
   (list :target target :category category :delta delta)
   "gptel-auto-workflow-ontology-router.el"
   (list :delta delta)))

(defun gptel-conversion-unit-record-evolution (changes-plist)
  "Record an ontology evolution result as a conversion unit.
Called by `gptel-auto-workflow--memory-schema-record-evolution'."
  (gptel-conversion-unit-add
   "evolution-cycle"
   'evolution
   nil
   changes-plist
   "gptel-auto-workflow-ontology-router.el"
   nil))

;; ─── Provide ───

(provide 'gptel-ext-conversion-unit)

;;; gptel-ext-conversion-unit.el ends here
