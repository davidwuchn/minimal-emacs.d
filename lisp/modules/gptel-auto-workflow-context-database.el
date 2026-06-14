;;; gptel-auto-workflow-context-database.el --- Causal/business context database for experiments -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OV5 Self-Improving Architecture

;; Author: OV5 System
;; Keywords: context, database, business-context, causal-chain, sidecar

;;; Commentary:

;; Phase 3: Software as Consumable - Context Database
;; Preserves business context (why decisions were made, what was learned)
;; as per-experiment sidecar files, enabling code regeneration with better models.
;;
;; Architecture: each experiment gets a sidecar file var/context/<id>.edn
;; containing narrative fields (business-rationale, hypothesis, causal-chain,
;; learned, decision-rationale) alongside score/model/duration metrics.
;; This captures "why" not just "what" for each experiment.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'parseedn)
;; gptel-auto-workflow--project-root is called unconditionally in multiple
;; functions (--file-path, --ensure-dir, capture, --derive-dependencies).
;; Require it so the function is actually defined at runtime, not just
;; declared for the byte-compiler.
(require 'gptel-tools-agent-benchmark nil t)
;; Reuse shared EDN helpers.
(require 'gptel-tools-agent-experiment-loop)

(declare-function gptel-auto-workflow--plist-get "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--project-root "gptel-tools-agent-benchmark")

;; ============================================================================
;; Configuration
;; ============================================================================

(defcustom gptel-auto-workflow-context-db-dir "var/context"
  "Directory for per-experiment context sidecar files.
Relative to project root.  Each experiment gets <id>.edn."
  :type 'string
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-context-db-auto-capture t
  "When non-nil, automatically capture context when experiments are logged."
  :type 'boolean
  :group 'gptel-tools-agent)

;; ============================================================================
;; Internal Helpers — File-System Layer
;; ============================================================================

(defun gptel-auto-workflow-context-db--file-path (experiment-id)
  "Return absolute path to sidecar file for EXPERIMENT-ID."
  (let ((root (gptel-auto-workflow--project-root)))
    (expand-file-name (format "%s.edn" experiment-id)
                      (expand-file-name gptel-auto-workflow-context-db-dir root))))

(defun gptel-auto-workflow-context-db--ensure-dir ()
  "Ensure the context sidecar directory exists."
  (let ((dir (expand-file-name gptel-auto-workflow-context-db-dir
                               (gptel-auto-workflow--project-root))))
    (unless (file-directory-p dir)
      (make-directory dir t))
    dir))

(defun gptel-auto-workflow-context-db--write (context)
  "Write CONTEXT plist to its sidecar file as EDN.
Returns CONTEXT on success, nil on failure."
  (condition-case err
      (let ((file (gptel-auto-workflow-context-db--file-path
                   (plist-get context :id))))
        (gptel-auto-workflow-context-db--ensure-dir)
        (gptel-auto-workflow--write-edn file context)
        context)
    (error
     (message "[context-db] Write error: %s" err)
     nil)))

(defun gptel-auto-workflow-context-db--all-files ()
  "Return list of all .edn sidecar files in the context directory."
  (let ((dir (expand-file-name gptel-auto-workflow-context-db-dir
                               (gptel-auto-workflow--project-root))))
    (when (file-directory-p dir)
      (directory-files dir t "\\.edn$"))))

;; ============================================================================
;; Internal Helpers — Derivation Layer
;; ============================================================================

(defun gptel-auto-workflow-context-db--derive-business-rationale (experiment-result)
  "Derive business rationale string from EXPERIMENT-RESULT.
Priority: hypothesis patterns > strategy mapping > category mapping."
  (let ((hypothesis (or (plist-get experiment-result :hypothesis) ""))
        (strategy (or (plist-get experiment-result :strategy) ""))
        (category (plist-get experiment-result :category)))
    (cond
     ;; Hypothesis pattern matching
     ((string-match-p "nil guard\\|ignore-errors\\|condition-case\\|error handling\\|wrong-type-argument" hypothesis)
      "Reduce runtime failures by hardening error paths.")
     ((string-match-p "refactor\\|simplify\\|clean up\\|restructure\\|deduplicate" hypothesis)
      "Lower maintenance cost by reducing code complexity.")
     ((string-match-p "test\\|coverage\\|regression\\|verify\\|assert" hypothesis)
      "Prevent regressions by adding test coverage.")
     ((string-match-p "performance\\|speed\\|latency\\|optimize\\|slow\\|timeout" hypothesis)
      "Reduce latency by optimizing critical paths.")
     ((string-match-p "memory\\|cleanup\\|garbage\\|leak\\|daemon" hypothesis)
      "Improve daemon stability by fixing resource lifecycle issues.")
     ;; Strategy mapping
     ((string-match-p "nil-guard" strategy) "Reduce runtime failures by adding nil guards.")
     ((string-match-p "refactor" strategy) "Lower maintenance cost through structural simplification.")
     ((string-match-p "test" strategy) "Prevent regressions with additional test coverage.")
     ((string-match-p "performance" strategy) "Reduce latency through targeted optimization.")
     ;; Category mapping
     ((eq category :agentic) "Improve autonomous workflow reliability.")
     ((eq category :programming) "Strengthen code correctness and maintainability.")
     ((eq category :tool-calls) "Enhance tool integration robustness.")
     ((eq category :natural-language) "Improve communication clarity and accuracy.")
     ;; Fallback
     (t (format "Improve quality of %s." (or (plist-get experiment-result :target) "unknown target"))))))

(defun gptel-auto-workflow-context-db--derive-causal-chain (experiment-result)
  "Derive causal chain (list of (cause . effect) pairs) from EXPERIMENT-RESULT."
  (let* ((hypothesis (or (plist-get experiment-result :hypothesis) ""))
        (decision (or (plist-get experiment-result :decision) ""))
        (score-after (or (plist-get experiment-result :score-after) 0.0))
        (score-before (or (plist-get experiment-result :score-before) 0.0))
        (cause (cond
                ((string-match-p "nil guard\\|ignore-errors" hypothesis) "missing nil guard")
                ((string-match-p "refactor\\|simplify" hypothesis) "structural complexity")
                ((string-match-p "test\\|coverage" hypothesis) "untested edge case")
                ((string-match-p "performance\\|optimize" hypothesis) "inefficient algorithm")
                ((string-match-p "memory\\|cleanup\\|leak" hypothesis) "resource leak")
                (t (if (> (length hypothesis) 0)
                       (substring hypothesis 0 (min 40 (length hypothesis)))
                     "unknown defect"))))
        (effect (cond
                 ((equal decision "kept")
                  (if (> score-after score-before)
                      "quality improvement confirmed"
                    "minimal impact observed"))
                 (t "rejected — insufficient improvement"))))
    (list (cons cause effect))))

(defun gptel-auto-workflow-context-db--derive-dependencies (target)
  "Derive list of dependency paths from TARGET file by parsing require
statements."
  (let* ((root (gptel-auto-workflow--project-root))
         (target-full (expand-file-name target root))
         (deps nil))
    (when (file-exists-p target-full)
      (with-temp-buffer
        (insert-file-contents target-full)
        (goto-char (point-min))
        (while (re-search-forward "(require\\s+'\\([^)]+\\)" nil t)
          (let ((req-name (match-string 1)))
            (when (and req-name (stringp req-name))
              ;; Convert feature name to relative path
              (let ((dep-path (format "lisp/modules/%s.el" req-name)))
                (when (file-exists-p (expand-file-name dep-path root))
                  (push dep-path deps))))))))
    (nreverse deps)))

(defun gptel-auto-workflow-context-db--derive-learned (experiment-result)
  "Derive learned insight string from EXPERIMENT-RESULT.
Uses score delta and grader/comparator reason."
  (let* ((score-before (or (plist-get experiment-result :score-before) 0.0))
         (score-after (or (plist-get experiment-result :score-after) 0.0))
         (delta (- score-after score-before))
         (grader-reason (or (plist-get experiment-result :grader-reason) ""))
         (comparator-reason (or (plist-get experiment-result :comparator-reason) "")))
    (cond
     ((> delta 0.1)
      (format "Hypothesis confirmed; %s."
              (if (> (length grader-reason) 3)
                  (substring grader-reason 0 (min 80 (length grader-reason)))
                "quality improvement achieved")))
     ((> delta 0.0)
      (format "Marginal improvement; %s."
              (if (> (length comparator-reason) 3)
                  (substring comparator-reason 0 (min 80 (length comparator-reason)))
                "positive delta but below threshold")))
     ((<= delta 0.0)
      (format "Hypothesis disproved; %s."
              (if (> (length comparator-reason) 3)
                  (substring comparator-reason 0 (min 80 (length comparator-reason)))
                "no quality improvement"))))))

(defun gptel-auto-workflow-context-db--decision-rationale (experiment-result)
  "Derive decision rationale string from EXPERIMENT-RESULT."
  (let ((decision (or (plist-get experiment-result :decision) "unknown"))
        (comparator-reason (or (plist-get experiment-result :comparator-reason) "")))
    (cond
     ((equal decision "kept")
      (format "Approved because %s."
              (if (> (length comparator-reason) 3)
                  comparator-reason
                "expected user-facing quality gain")))
     ((equal decision "recommend")
      (format "Recommended for review: %s."
              (if (> (length comparator-reason) 3)
                  comparator-reason
                "needs human validation")))
     ((equal decision "rejected")
      (format "Rejected: %s."
              (if (> (length comparator-reason) 3)
                  comparator-reason
                "insufficient improvement")))
     (t (format "Decision: %s; %s." decision comparator-reason)))))

;; ============================================================================
;; Public Functions (8)
;; ============================================================================

(defun gptel-auto-workflow-context-db-capture (experiment-result &optional metadata)
  "Capture causal/business context from EXPERIMENT-RESULT.
Write a sidecar .edn file with derived narrative fields.
Optional METADATA plist is merged into the context.
Returns the captured context plist."
  (let* ((id (or (plist-get experiment-result :id) 0))
         (target (or (plist-get experiment-result :target) ""))
         (context (list :id id
                       :target target
                       :created-at (float-time)
                       :business-rationale (gptel-auto-workflow-context-db--derive-business-rationale
                                            experiment-result)
                       :hypothesis (or (plist-get experiment-result :hypothesis) "")
                       :causal-chain (gptel-auto-workflow-context-db--derive-causal-chain
                                      experiment-result)
                       :dependencies (gptel-auto-workflow-context-db--derive-dependencies target)
                       :alternatives nil
                       :decision (or (plist-get experiment-result :decision) "unknown")
                       :decision-rationale (gptel-auto-workflow-context-db--decision-rationale
                                           experiment-result)
                       :learned (gptel-auto-workflow-context-db--derive-learned experiment-result)
                       :expected-impact (gptel-auto-workflow-context-db--derive-business-rationale
                                         experiment-result)
                       :observed-impact nil
                       :business-value-score (or (plist-get experiment-result :business-value-score) 0.0)
                       :risk-score (or (plist-get experiment-result :risk-score) 0.0)
                       :score-before (or (plist-get experiment-result :score-before) 0.0)
                       :score-after (or (plist-get experiment-result :score-after) 0.0)
                       :strategy (or (plist-get experiment-result :strategy) "template-default")
                       :model (or (plist-get experiment-result :model) "unknown")
                       :duration (or (plist-get experiment-result :duration) 0))))
    ;; Merge optional metadata
    (when metadata
      (dolist (key (number-sequence 0 (- (length metadata) 2) 2))
        (setq context (plist-put context (nth key metadata) (nth (1+ key) metadata)))))
    (gptel-auto-workflow-context-db--write context)))

(defun gptel-auto-workflow-context-db-read (experiment-id)
  "Read context plist for EXPERIMENT-ID from its sidecar file.
Returns the plist, or nil if no sidecar exists."
  (let ((file (gptel-auto-workflow-context-db--file-path experiment-id)))
    (when (and file (file-exists-p file))
      (condition-case err
          (gptel-auto-workflow--read-edn file)
        (error
         (message "[context-db] Read error for id %s: %s" experiment-id err)
         nil)))))

(cl-defun gptel-auto-workflow-context-db-query (&key target strategy since before after decision)
  "Query context sidecars by keyword filters.
Returns list of matching context plists.
&key TARGET — filter by target string match.
&key STRATEGY — filter by strategy string match.
&key SINCE — filter by created-at >= SINCE (float-time).
&key BEFORE — filter by created-at < BEFORE (float-time).
&key AFTER — filter by created-at > AFTER (float-time).
&key DECISION — filter by decision string match."
  (let ((files (gptel-auto-workflow-context-db--all-files))
        (results nil))
    (dolist (file files)
      (condition-case _err
          (let ((ctx (gptel-auto-workflow--read-edn file)))
            (when ctx
              (let ((match t))
                (when target
                  (setq match (and match
                                   (string= (or (plist-get ctx :target) "") target))))
                (when strategy
                  (setq match (and match
                                   (string= (or (plist-get ctx :strategy) "") strategy))))
                (when since
                  (setq match (and match
                                   (>= (or (plist-get ctx :created-at) 0.0) since))))
                (when before
                  (setq match (and match
                                   (< (or (plist-get ctx :created-at) 0.0) before))))
                (when after
                  (setq match (and match
                                   (> (or (plist-get ctx :created-at) 0.0) after))))
                (when decision
                  (setq match (and match
                                   (string= (or (plist-get ctx :decision) "") decision))))
                (when match
                  (push ctx results)))))
        (error nil)))
    (nreverse results)))

(defun gptel-auto-workflow-context-db-update-observed-impact (experiment-id observed-impact)
  "Update the :observed-impact field for EXPERIMENT-ID's sidecar.
Reads context, adds :observed-impact OBSERVED-IMPACT, rewrites file.
Returns updated context plist, or nil if not found."
  (let ((ctx (gptel-auto-workflow-context-db-read experiment-id)))
    (when ctx
      (setq ctx (plist-put ctx :observed-impact observed-impact))
      (gptel-auto-workflow-context-db--write ctx))))

(defun gptel-auto-workflow-context-db-dependencies (target)
  "Return list of experiment IDs whose :dependencies reference TARGET.
Scans all sidecars, finds those listing target in their dependency list."
  (let ((files (gptel-auto-workflow-context-db--all-files))
        (ids nil))
(dolist (file files)
      (condition-case _err
          (let* ((ctx (gptel-auto-workflow--read-edn file))
                 (deps (plist-get ctx :dependencies)))
            (when (and ctx deps (member target deps))
              (push (plist-get ctx :id) ids)))
        (error nil)))
    (nreverse ids)))

(defun gptel-auto-workflow-context-db-summary-for-target (target)
  "Return aggregated summary plist for all contexts targeting TARGET.
Includes :total-experiments, :kept-count, :rejected-count,
:avg-score-before, :avg-score-after, :avg-business-value-score,
:common-patterns, :contexts."
  (let ((contexts (gptel-auto-workflow-context-db-query :target target))
        (total 0)
        (kept 0)
        (rejected 0)
        (sum-before 0.0)
        (sum-after 0.0)
        (sum-bvs 0.0)
        (hypotheses nil))
    (dolist (ctx contexts)
      (setq total (1+ total))
      (let ((decision (or (plist-get ctx :decision) "")))
        (cond ((equal decision "kept") (setq kept (1+ kept)))
              ((equal decision "rejected") (setq rejected (1+ rejected)))))
      (setq sum-before (+ sum-before (or (plist-get ctx :score-before) 0.0)))
      (setq sum-after (+ sum-after (or (plist-get ctx :score-after) 0.0)))
      (setq sum-bvs (+ sum-bvs (or (plist-get ctx :business-value-score) 0.0)))
      (push (or (plist-get ctx :hypothesis) "") hypotheses))
    (let ((common-patterns
           (let ((short-hyps (mapcar (lambda (h) (substring h 0 (min 30 (length h)))) hypotheses))
                 (freq (make-hash-table :test 'equal)))
             (dolist (h short-hyps)
               (puthash h (1+ (or (gethash h freq) 0)) freq))
             (let ((sorted (sort (hash-table-keys freq)
                                 (lambda (a b) (> (gethash a freq) (gethash b freq))))))
               (seq-take sorted 3)))))
      (list :total-experiments total
            :kept-count kept
            :rejected-count rejected
            :avg-score-before (if (> total 0) (/ sum-before total) 0.0)
            :avg-score-after (if (> total 0) (/ sum-after total) 0.0)
            :avg-business-value-score (if (> total 0) (/ sum-bvs total) 0.0)
            :common-patterns common-patterns
            :contexts contexts))))

(defun gptel-auto-workflow-context-db-search (query-string)
  "Full-text search over narrative fields in all context sidecars.
Searches :business-rationale, :hypothesis, :learned,
:decision-rationale, :expected-impact, :observed-impact.
Returns list of matching context plists."
  (let ((files (gptel-auto-workflow-context-db--all-files))
        (results nil)
        (narrative-fields '(:business-rationale :hypothesis :learned
                            :decision-rationale :expected-impact :observed-impact)))
    (dolist (file files)
      (condition-case _err
          (let ((ctx (gptel-auto-workflow--read-edn file))
                (found nil))
            (when ctx
              (dolist (field narrative-fields)
                (let ((val (plist-get ctx field)))
                  (when (and val (stringp val)
                             (string-match-p query-string val))
                    (setq found t))))
              (when found
                (push ctx results))))
        (error nil)))
    (nreverse results)))

(defun gptel-auto-workflow-context-db-all-ids ()
  "Return sorted list of all experiment IDs that have context sidecars."
  (let ((files (gptel-auto-workflow-context-db--all-files))
        (ids nil))
    (dolist (file files)
      (let ((basename (file-name-nondirectory file)))
        (when (string-match "\\([0-9]+\\)\\.edn" basename)
          (push (string-to-number (match-string 1 basename)) ids))))
    (sort ids #'<)))

;; ============================================================================
;; Backward-Compatibility Aliases
;; ============================================================================
;; These preserve callers that use fboundp guards in other modules:
;;   - production.el calls --capture-experiment-context, --context-db-load, --context-db-persist
;;   - main.el calls --context-db-load
;;   - ontology-predict.el, token-economics.el call --get-context
;;   - human-interface.el calls --get-context-summary

(defalias 'gptel-auto-workflow--capture-experiment-context
  'gptel-auto-workflow-context-db-capture
  "Backward-compat alias for `gptel-auto-workflow-context-db-capture'.
Called by gptel-auto-workflow-production.el via fboundp guard.")

(defalias 'gptel-auto-workflow--capture-context
  'gptel-auto-workflow-context-db-capture
  "Backward-compat alias for `gptel-auto-workflow-context-db-capture'.
Called by gptel-auto-workflow-production.el via fboundp guard.")

(defalias 'gptel-auto-workflow--get-context
  'gptel-auto-workflow-context-db-read
  "Backward-compat alias for `gptel-auto-workflow-context-db-read'.
Called by ontology-predict.el and token-economics.el via fboundp guard.")

(defun gptel-auto-workflow--context-db-init (_config)
  "Backward-compat: no-op init.  Sidecar architecture is always ready.
Returns t.  CONFIG argument is ignored."
  t)

(defun gptel-auto-workflow--context-db-configured-p ()
  "Backward-compat: always configured with sidecar architecture."
  t)

(defun gptel-auto-workflow--context-db-load ()
  "Backward-compat: no-op load.  Sidecars are lazy-loaded per-read.
Returns t."
  t)

(defun gptel-auto-workflow--context-db-persist ()
  "Backward-compat: no-op persist.  Sidecars are written per-capture.
Returns t."
  t)

(defun gptel-auto-workflow--get-context-summary ()
  "Backward-compat: return aggregated summary plist of all contexts.
Called by gptel-auto-workflow-human-interface.el via fboundp guard."
  (let ((contexts (gptel-auto-workflow-context-db-query)))
    (let ((modules-count 0)
          (experiments-count (length contexts))
          (targets (make-hash-table :test 'equal)))
      (dolist (ctx contexts)
        (let ((target (or (plist-get ctx :target) "")))
          (unless (gethash target targets)
            (puthash target t targets)
            (setq modules-count (1+ modules-count))))
        ;; Collect recent decisions (last 5)
        )
      (let ((recent-decisions
             (mapcar (lambda (ctx)
                       (list :id (plist-get ctx :id)
                             :target (plist-get ctx :target)
                             :rationale (plist-get ctx :decision-rationale)))
                     (seq-take contexts 5))))
        (list :modules-count modules-count
              :experiments-count experiments-count
              :recent-decisions recent-decisions)))))

;; Remaining backward-compat aliases for regeneration/disposable features
;; These were in the old module and may be referenced by other test files.

(defvar gptel-auto-workflow--context-db-config nil
  "Backward-compat: config variable.  Unused in sidecar architecture.")

(defvar gptel-auto-workflow--context-store (make-hash-table :test 'equal)
  "Backward-compat: in-memory store.  Unused in sidecar architecture.")

(defvar gptel-auto-workflow--module-context-store (make-hash-table :test 'equal)
  "Backward-compat: in-memory module store.  Unused in sidecar architecture.")

(defvar gptel-auto-workflow--regeneration-history (make-hash-table :test 'equal)
  "Backward-compat: regeneration history.  Unused in sidecar architecture.")

(defvar gptel-auto-workflow--scheduled-regenerations nil
  "Backward-compat: scheduled regenerations.  Unused in sidecar architecture.")

(defvar gptel-auto-workflow--disposable-modules (make-hash-table :test 'equal)
  "Backward-compat: disposable modules set.  Unused in sidecar architecture.")

(defvar gptel-auto-workflow--preserved-contexts (make-hash-table :test 'equal)
  "Backward-compat: preserved contexts.  Unused in sidecar architecture.")

(defun gptel-auto-workflow--context-db-execute (_query params)
  "Backward-compat: delegate to context-db-query via PARAMS plist.
QUERY is ignored; PARAMS :query-type determines behavior."
  (let ((query-type (plist-get params :query-type)))
    (cond
     ((eq query-type :module)
      (gptel-auto-workflow-context-db-query :target (plist-get params :module)))
     ((eq query-type :time-range)
      (gptel-auto-workflow-context-db-query
       :since (plist-get params :start-time)
       :before (plist-get params :end-time)))
     (t (gptel-auto-workflow-context-db-query)))))

(defun gptel-auto-workflow--hash-table-to-alist (hash-table)
  "Backward-compat: convert HASH-TABLE to alist."
  (let ((result nil))
    (maphash (lambda (key value) (push (cons key value) result)) hash-table)
    result))

(defun gptel-auto-workflow--alist-to-hash-table (alist)
  "Backward-compat: convert ALIST to hash table."
  (let ((hash-table (make-hash-table :test 'equal)))
    (dolist (pair alist) (puthash (car pair) (cdr pair) hash-table))
    hash-table))

;; Regeneration/disposable backward-compat stubs
(defun gptel-auto-workflow--capture-module-context (module-context)
  "Backward-compat: store MODULE-CONTEXT in in-memory hash."
  (let ((module (plist-get module-context :module)))
    (puthash module module-context gptel-auto-workflow--module-context-store)
    t))

(defun gptel-auto-workflow--get-module-context (module)
  "Backward-compat: get context for MODULE from in-memory hash."
  (gethash module gptel-auto-workflow--module-context-store))

(defun gptel-auto-workflow--update-module-context (module-context)
  "Backward-compat: merge MODULE-CONTEXT into in-memory hash."
  (let* ((module (plist-get module-context :module))
         (existing (gethash module gptel-auto-workflow--module-context-store)))
    (when existing
      (puthash module (append module-context existing)
               gptel-auto-workflow--module-context-store))))

(defun gptel-auto-workflow--query-context-by-module (module)
  "Backward-compat: query contexts by module (target)."
  (gptel-auto-workflow-context-db-query :target module))

(defun gptel-auto-workflow--query-context-by-time-range (start-time end-time)
  "Backward-compat: query contexts by time range."
  (gptel-auto-workflow-context-db-query :since start-time :before end-time))

(defun gptel-auto-workflow--update-context (update)
  "Backward-compat: update context by reading sidecar and rewriting."
  (let ((id (plist-get update :id)))
    (when id
      (let ((ctx (gptel-auto-workflow-context-db-read id)))
        (when ctx
          (let ((merged (append update ctx)))
            (gptel-auto-workflow-context-db--write merged)))))))

(defun gptel-auto-workflow--delete-context (experiment-id)
  "Backward-compat: delete sidecar file for EXPERIMENT-ID."
  (let ((file (gptel-auto-workflow-context-db--file-path experiment-id)))
    (when (and file (file-exists-p file))
      (delete-file file)
      t)))

;; Disposable code backward-compat stubs
(defun gptel-auto-workflow--mark-as-disposable (module)
  "Backward-compat: mark MODULE as disposable."
  (puthash module t gptel-auto-workflow--disposable-modules)
  t)

(defun gptel-auto-workflow--get-disposable-status (module)
  "Backward-compat: get disposable status of MODULE."
  (if (gethash module gptel-auto-workflow--disposable-modules) :disposable :persistent))

(defun gptel-auto-workflow--preserve-context-before-disposal (module)
  "Backward-compat: preserve context for MODULE."
  (let ((context (gethash module gptel-auto-workflow--module-context-store)))
    (when context
      (puthash module context gptel-auto-workflow--preserved-contexts)
      t)))

(defun gptel-auto-workflow--get-preserved-context (module)
  "Backward-compat: get preserved context for MODULE."
  (gethash module gptel-auto-workflow--preserved-contexts))

;; Regeneration backward-compat stubs
(defun gptel-auto-workflow--track-regeneration (regeneration)
  "Backward-compat: track regeneration event."
  (let* ((module (plist-get regeneration :module))
         (history (gethash module gptel-auto-workflow--regeneration-history nil)))
    (push regeneration history)
    (puthash module history gptel-auto-workflow--regeneration-history)
    t))

(defun gptel-auto-workflow--get-regeneration-history (module)
  "Backward-compat: get regeneration history for MODULE."
  (gethash module gptel-auto-workflow--regeneration-history))

;; Forward declarations for code-regeneration module (defalias targets)
(declare-function gptel-auto-workflow-code-regeneration--prepare-context
  "gptel-auto-workflow-code-regeneration" (module model-version))
(declare-function gptel-auto-workflow-code-regeneration--generate-prompt
  "gptel-auto-workflow-code-regeneration" (regen-context))
(declare-function gptel-auto-workflow-code-regeneration--identify-candidates
  "gptel-auto-workflow-code-regeneration" (&optional _args))
(declare-function gptel-auto-workflow-code-regeneration--full-workflow
  "gptel-auto-workflow-code-regeneration" (module _current-model target-model))

;; Regeneration functions now live in gptel-auto-workflow-code-regeneration.el
;; These defaliases preserve the old names for backward compatibility.
;; The defalias optional docstring preserves the original documentation.

(defalias 'gptel-auto-workflow--prepare-regeneration-context
  'gptel-auto-workflow-code-regeneration--prepare-context
  "Prepare regeneration context plist for MODULE targeting MODEL-VERSION.
Reads sidecar context data, derives business rationale, key decisions,
and historical learnings.  Now delegates to code-regeneration module.")

(defalias 'gptel-auto-workflow--generate-regeneration-prompt
  'gptel-auto-workflow-code-regeneration--generate-prompt
  "Generate a regeneration prompt string from REGEN-CONTEXT plist.
Incorporates business rationale, decisions, learnings, and model stats.
Now delegates to code-regeneration module.")

(defalias 'gptel-auto-workflow--identify-regeneration-candidates
  'gptel-auto-workflow-code-regeneration--identify-candidates
  "Identify modules that would benefit from regeneration with a better model.
Scans context-database sidecar data for targets with sufficient history
and below-threshold improvement.  Returns nil if context-database is
not available.  Now delegates to code-regeneration module.")

(defalias 'gptel-auto-workflow--full-regeneration-workflow
  'gptel-auto-workflow-code-regeneration--full-workflow
  "Execute full regeneration workflow for MODULE to TARGET-MODEL.
Prepares context, generates prompt, sets experiment-prompt-override.
Now delegates to code-regeneration module.")

(defun gptel-auto-workflow--compare-regeneration-versions (version1 version2)
  "Backward-compat: compare two regeneration versions."
  (let* ((metrics1 (plist-get version1 :metrics))
         (metrics2 (plist-get version2 :metrics))
         (perf1 (plist-get metrics1 :performance))
         (perf2 (plist-get metrics2 :performance))
         (read1 (plist-get metrics1 :readability))
         (read2 (plist-get metrics2 :readability)))
    (list :performance-improvement (> perf2 perf1)
          :readability-improvement (> read2 read1)
          :recommended (if (or (> perf2 perf1) (> read2 read1)) :version2 :version1))))

(defun gptel-auto-workflow--schedule-regeneration (module &rest args)
  "Backward-compat: schedule regeneration for MODULE."
  (let ((scheduled (list :module module
                         :priority (plist-get args :priority)
                         :scheduled-time (plist-get args :scheduled-time))))
    (push scheduled gptel-auto-workflow--scheduled-regenerations)
    t))

(defun gptel-auto-workflow--get-scheduled-regenerations ()
  "Backward-compat: get scheduled regenerations."
  gptel-auto-workflow--scheduled-regenerations)

;; (identify-regeneration-candidates now a defalias above)

(defun gptel-auto-workflow--estimate-regeneration-value (_module current-metrics expected-improvements)
  "Backward-compat: estimate regeneration value."
  (let* ((perf-current (plist-get current-metrics :performance))
         (perf-mult (plist-get expected-improvements :performance))
         (perf-gain (* perf-current (- perf-mult 1.0)))
         (maint-current (plist-get current-metrics :maintainability))
         (maint-mult (plist-get expected-improvements :maintainability))
         (maint-gain (* maint-current (- maint-mult 1.0))))
    (list :performance-gain perf-gain
          :maintainability-gain maint-gain
          :overall-value-score (/ (+ perf-gain maint-gain) 2.0))))

;; (full-regeneration-workflow now a defalias above)

(defun gptel-auto-workflow--get-all-modules ()
  "Backward-compat stub: returns nil."
  nil)

(defun gptel-auto-workflow--module-age (_module)
  "Backward-compat stub: returns 0."
  0)

(defun gptel-auto-workflow--latest-model-available ()
  "Backward-compat stub: returns default model string."
  "gpt-4")

(defun gptel-auto-workflow--module-model-version (_module)
  "Backward-compat stub: returns default model string."
  "gpt-4")

(provide 'gptel-auto-workflow-context-database)

;;; gptel-auto-workflow-context-database.el ends here
