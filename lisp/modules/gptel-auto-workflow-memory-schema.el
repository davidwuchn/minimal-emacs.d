;;; gptel-auto-workflow-memory-schema.el --- Schema extraction and indexing for mementum memories -*- lexical-binding: t -*-

;; Inspired by MemGraphRAG (KDD 2026): three-layer memory with schema
;; extraction, frequency-based promotion, and conflict detection.
;;
;; Architecture:
;;   Memory markdown → heuristic triple extraction → Schema inference → Freq index
;;   Schema promotion: Freq(s) >= tau -> stable (used by ontology router)
;;   Conflict detection: entity overlap scan
;;   Index: mementum/.ov5-memory-index.json
;;
;; Internal data model uses hash tables for JSON-compatible serialization.

(require 'cl-lib)
(require 'json)
(require 'subr-x)

(declare-function gptel-auto-workflow--worktree-base-root "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--log "gptel-auto-workflow-evolution")
(declare-function gptel-auto-workflow--build-digital-twin "gptel-auto-workflow-ontology-router")
(declare-function gptel-auto-workflow--semantic-similarity-edges "gptel-auto-workflow-ontology-router")
(declare-function gptel-auto-workflow--categorize-target "gptel-auto-workflow-ontology-router")
(declare-function skill-graph-node-level "gptel-auto-workflow-skill-graph")
(declare-function skill-graph-edge-weight "gptel-auto-workflow-skill-graph")
(declare-function gptel-auto-workflow-self-audit--root "gptel-auto-workflow-self-audit")
(defvar skill-graph--edges)

;; ─── Configuration ───

(defcustom gptel-auto-workflow-memory-schema-enabled t
  "When non-nil, extract schema triples from mementum memories."
  :type 'boolean
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-memory-schema-threshold 3
  "Minimum observations before a schema pattern is promoted to stable.
Analogous to MemGraphRAG's tau threshold."
  :type 'integer
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-memory-schema-index-file
  "mementum/.ov5-memory-index.json"
  "Path to the schema index file, relative to project root."
  :type 'file
  :group 'gptel-tools-agent)

(defvar gptel-auto-workflow--memory-schema-schemas nil
  "Hash table: SCHEMA-KEY -> frequency count.")

(defvar gptel-auto-workflow--memory-schema-entities nil
  "Hash table: ENTITY-NAME -> (count . (source-file ...)).")

(defvar gptel-auto-workflow--memory-schema-triples nil
  "Hash table: TRIPLE-KEY -> (schema-key . source-file).
Stores individual triples for graph traversal.")

;; ─── Schema Index: Load / Save ───

(defun gptel-auto-workflow--memory-schema-index-path ()
  "Return absolute path to the schema index file."
  (expand-file-name gptel-auto-workflow-memory-schema-index-file
                    (gptel-auto-workflow--worktree-base-root)))

(defun gptel-auto-workflow--memory-schema-make-schemas ()
  "Create a fresh schemas hash table."
  (make-hash-table :test 'equal :size 32))

(defun gptel-auto-workflow--memory-schema-make-entities ()
  "Create a fresh entities hash table."
  (make-hash-table :test 'equal :size 64))

(defun gptel-auto-workflow--memory-schema-make-triples ()
  "Create a fresh triples hash table."
  (make-hash-table :test 'equal :size 64))

(defun gptel-auto-workflow--memory-schema-load-index ()
  "Load the schema index from disk into hash tables."
  (setq gptel-auto-workflow--memory-schema-schemas
        (gptel-auto-workflow--memory-schema-make-schemas))
  (setq gptel-auto-workflow--memory-schema-entities
        (gptel-auto-workflow--memory-schema-make-entities))
  (setq gptel-auto-workflow--memory-schema-triples
        (gptel-auto-workflow--memory-schema-make-triples))
  (let ((file (gptel-auto-workflow--memory-schema-index-path)))
    (when (file-exists-p file)
      (let ((data (with-temp-buffer
                    (insert-file-contents file)
                    (goto-char (point-min))
                    (condition-case nil
                        (let ((json-object-type 'alist)
                              (json-key-type 'string))
                          (json-read-from-string (buffer-string)))
                      (error nil)))))
        (when data
          (let ((schemas-vec (cdr (assoc "schemas" data))))
            (dotimes (i (length schemas-vec))
              (let* ((entry (aref schemas-vec i))
                     (key (cdr (assoc "key" entry)))
                     (freq (cdr (assoc "freq" entry))))
                (when key
                  (puthash key freq
                           gptel-auto-workflow--memory-schema-schemas)))))
          (let ((entities-vec (cdr (assoc "entities" data))))
            (dotimes (i (length entities-vec))
              (let* ((entry (aref entities-vec i))
                     (name (cdr (assoc "name" entry)))
                     (count (cdr (assoc "count" entry)))
                     (sources-vec (cdr (assoc "sources" entry)))
                     (sources (append sources-vec nil)))
                (when name
                  (puthash name (cons count sources)
                           gptel-auto-workflow--memory-schema-entities))))))))))

(defun gptel-auto-workflow--memory-schema-save-index ()
  "Write schema index to disk as JSON."
  (let ((file (gptel-auto-workflow--memory-schema-index-path))
        (json-encoding-pretty-print t)
        (schemas-list nil)
        (entities-list nil))
    (maphash (lambda (key freq)
               (push `(("key" . ,key) ("freq" . ,freq)) schemas-list))
             gptel-auto-workflow--memory-schema-schemas)
    (maphash (lambda (name count-sources)
               (push `(("name" . ,name)
                       ("count" . ,(car count-sources))
                       ("sources" . ,(vconcat (cdr count-sources))))
                     entities-list))
             gptel-auto-workflow--memory-schema-entities)
    (let ((index `(("schemas" . ,(vconcat (nreverse schemas-list)))
                   ("entities" . ,(vconcat (nreverse entities-list))))))
      (make-directory (file-name-directory file) t)
      (with-temp-file file
        (insert (json-encode index))))))

(defun gptel-auto-workflow--memory-schema-ensure-loaded ()
  "Ensure hash tables exist, loading from disk if not yet initialized.
Falls back to empty tables when runtime deps are unavailable."
  (unless gptel-auto-workflow--memory-schema-schemas
    (setq gptel-auto-workflow--memory-schema-schemas
          (gptel-auto-workflow--memory-schema-make-schemas)
          gptel-auto-workflow--memory-schema-entities
          (gptel-auto-workflow--memory-schema-make-entities))
    (when (fboundp 'gptel-auto-workflow--worktree-base-root)
      (condition-case _err
          (gptel-auto-workflow--memory-schema-load-index)
        (error nil)))))

(defvar gptel-auto-workflow--memory-schema-synonymy-cache nil
  "Alist of (ENTITY . ((SYNONYM . SCORE) ...)) from git-embed.
Nil means not yet computed.")

(defvar gptel-auto-workflow--memory-schema-synonymy-cache-time nil
  "Time when synonymy cache was last computed.")

(defvar gptel-auto-workflow--unified-graph nil
  "Unified multigraph: (TYPE . ID) -> ((EDGE-TYPE (TO-TYPE . TO-ID) WEIGHT) ...).
Nil means not yet built.")

(defvar gptel-auto-workflow--unified-graph-time nil
  "Timestamp when unified graph was last built.")

(defun gptel-auto-workflow--memory-schema-reset ()
  "Reset in-memory schema index to empty."
  (setq gptel-auto-workflow--memory-schema-schemas
        (gptel-auto-workflow--memory-schema-make-schemas))
  (setq gptel-auto-workflow--memory-schema-entities
        (gptel-auto-workflow--memory-schema-make-entities))
  (setq gptel-auto-workflow--memory-schema-triples
        (gptel-auto-workflow--memory-schema-make-triples))
  (setq gptel-auto-workflow--memory-schema-synonymy-cache nil
        gptel-auto-workflow--memory-schema-synonymy-cache-time nil
        gptel-auto-workflow--unified-graph nil
        gptel-auto-workflow--unified-graph-time nil))

;; ─── Triple Extraction ───

(defun gptel-auto-workflow--memory-schema--clean-entity (str)
  "Clean STR into a valid entity name, or nil if too noisy.
Filters: max 30 chars, no newlines, must contain a letter if non-empty,
no leading special chars (💡 →, etc).  Returns nil for noisy entities."
  (let ((s (string-trim str)))
    (when (and (<= (length s) 30)
               (not (string-match-p "\n" s))
               (or (= (length s) 0)
                   (and (string-match-p "[a-zA-Z]" s)
                        (not (string-match-p "^[💡→✓✗✅❌🔧⚠⚡📋📐🔄]" s)))))
      s)))

(defun gptel-auto-workflow--memory-schema--valid-entity-p (str)
  "Return non-nil if STR is a non-empty, non-noisy entity name."
  (let ((clean (gptel-auto-workflow--memory-schema--clean-entity str)))
    (and clean (> (length clean) 0))))

(defun gptel-auto-workflow--memory-schema-extract-triples (text)
  "Extract (subject predicate object) triples from TEXT.
Returns list of plists: (:subject S :predicate P :object O
                         :subject-type ST :object-type OT).
Uses heuristic parsing — no LLM call required."
  (let ((triples nil))
    (dolist (line (split-string text "\n"))
      (cond
       ((string-match-p
         (concat "reference to free variable"
                 "\\|assignment to free variable"
                 "\\|the function.*is not known")
         line)
        nil)
       ((string-match
         (concat "\\(?:add\\|remov\\|fix\\|enforc\\|improv"
                 "\\|updat\\|refactor\\|rewrit\\|replac\\|harden\\)"
                 "\\(?:ed\\|es\\|ing\\|s\\)?\\b")
         line)
         (let* ((verb-start (match-beginning 0))
                (verb-end (match-end 0))
                (verb (substring line verb-start verb-end))
                (before-verb (substring line 0 verb-start))
                (after-verb (substring line verb-end))
                (subject (gptel-auto-workflow--memory-schema--clean-entity before-verb)))
           (when (string-match "\\(?:for\\|in\\|on\\|of\\|to\\) +\\(.+\\)"
                               after-verb)
             (let ((object-raw (match-string 1 after-verb)))
               (when (gptel-auto-workflow--memory-schema--valid-entity-p object-raw)
                 (push (list :subject (or subject "")
                            :predicate (string-trim verb)
                            :object (gptel-auto-workflow--memory-schema--clean-entity object-raw)
                            :subject-type nil
                            :object-type nil)
                      triples))))))))
    (delq nil triples)))

(defun gptel-auto-workflow--memory-schema-infer-schema (triple)
  "Infer a schema key from TRIPLE.
A schema is (HEAD-TYPE RELATION TAIL-TYPE).  When types are nil,
use the entity names as proxy types."
  (format "(%s %s %s)"
          (or (plist-get triple :subject-type)
              (plist-get triple :subject)
              "?")
          (or (plist-get triple :predicate) "?")
          (or (plist-get triple :object-type)
              (plist-get triple :object)
              "?")))

;; ─── Index Update ───

(defun gptel-auto-workflow--memory-schema-index-triples (triples source-file)
  "Add TRIPLES from SOURCE-FILE to the schema index.
Updates schema frequencies, entity counts, and triple store.
Returns new schemas count."
  (gptel-auto-workflow--memory-schema-ensure-loaded)
  (let ((new-count 0))
    (dolist (triple triples)
      (let* ((schema-key (gptel-auto-workflow--memory-schema-infer-schema triple))
             (subject (plist-get triple :subject))
             (object (plist-get triple :object))
             (triple-key (format "%s:%s:%s"
                                 (or subject "?")
                                 (or (plist-get triple :predicate) "?")
                                 (or object "?")))
             (existing-freq (gethash schema-key
                                     gptel-auto-workflow--memory-schema-schemas)))
        (if existing-freq
            (puthash schema-key (1+ existing-freq)
                     gptel-auto-workflow--memory-schema-schemas)
          (puthash schema-key 1 gptel-auto-workflow--memory-schema-schemas)
          (cl-incf new-count))
        (puthash triple-key (cons schema-key source-file)
                 gptel-auto-workflow--memory-schema-triples)
        (dolist (entity (delq nil (list subject object)))
          (let ((existing (gethash entity
                                   gptel-auto-workflow--memory-schema-entities)))
            (if existing
                (puthash entity
                         (cons (1+ (car existing))
                               (cons source-file (cdr existing)))
                         gptel-auto-workflow--memory-schema-entities)
              (puthash entity (cons 1 (list source-file))
                        gptel-auto-workflow--memory-schema-entities))))))
     (condition-case nil (gptel-auto-workflow--memory-schema-save-index) (error nil))
     new-count))

;; ─── Schema Stability ───

(defun gptel-auto-workflow--memory-schema-stable-p (schema-key)
  "Return non-nil if SCHEMA-KEY has enough observations to be stable.
Stable means freq >= `gptel-auto-workflow-memory-schema-threshold'."
  (gptel-auto-workflow--memory-schema-ensure-loaded)
  (let ((freq (gethash schema-key
                       gptel-auto-workflow--memory-schema-schemas)))
    (and freq (>= freq gptel-auto-workflow-memory-schema-threshold))))

(defun gptel-auto-workflow--memory-schema-stable-schemas ()
  "Return list of (SCHEMA-KEY . FREQ) for all stable schemas."
  (gptel-auto-workflow--memory-schema-ensure-loaded)
  (let ((result nil))
    (maphash (lambda (key freq)
               (when (>= freq gptel-auto-workflow-memory-schema-threshold)
                 (push (cons key freq) result)))
             gptel-auto-workflow--memory-schema-schemas)
    result))

(defun gptel-auto-workflow--memory-schema-candidate-schemas ()
  "Return list of (SCHEMA-KEY . FREQ) for unstable (candidate) schemas."
  (gptel-auto-workflow--memory-schema-ensure-loaded)
  (let ((result nil))
    (maphash (lambda (key freq)
               (when (< freq gptel-auto-workflow-memory-schema-threshold)
                 (push (cons key freq) result)))
             gptel-auto-workflow--memory-schema-schemas)
    result))

;; ─── Category Lookup via Schema Index ───

(defun gptel-auto-workflow--memory-schema-entity-idf (_name count-sources _total-entities)
  "Compute IDF-inspired score for entity NAME.
COUNT-SOURCES is (count . sources).  TOTAL-ENTITIES is total entity count.
Score = count * 1/log(deg+1) where deg = number of sources.
Penalizes generic entities (high degree); boosts rare ones."
  (let* ((count (car count-sources))
         (deg (length (cdr count-sources)))
         (hub-penalty (/ 1.0 (log (+ deg 1) 10.0))))
    (* count (max hub-penalty 0.1))))

(defun gptel-auto-workflow--memory-schema-rank-entities (entities-hash)
  "Return entities from ENTITIES-HASH sorted by IDF-weighted score.
Each entry is (NAME . WEIGHTED-SCORE)."
  (let ((total (hash-table-count entities-hash))
        (result nil))
    (maphash (lambda (name count-sources)
               (push (cons name
                           (gptel-auto-workflow--memory-schema-entity-idf
                            name count-sources total))
                     result))
             entities-hash)
    (cl-sort result #'> :key #'cdr)))

(defun gptel-auto-workflow--memory-schema-category-for-target (target)
  "Look up category for TARGET using schema index graph.
Returns a keyword (:programming, :tool-calls, :agentic,
:natural-language) or nil if no graph data available.
Uses experiment history (primary), then IDF-weighted entity matching
with schema classification (secondary)."
  (gptel-auto-workflow--memory-schema-ensure-loaded)
  (when target
    (or (gptel-auto-workflow--memory-schema--category-from-history target)
        (gptel-auto-workflow--memory-schema--category-from-schemas target))))

(defun gptel-auto-workflow--memory-schema--category-from-history (target)
  "Look up category for TARGET from experiment history.
Returns keyword or nil.  Requires ≥2 kept experiments for same filename."
  (when (and (fboundp 'gptel-auto-workflow--categorize-target-by-regex)
             (fboundp 'gptel-auto-workflow--parse-all-results)
             (fboundp 'gptel-auto-workflow--worktree-base-root))
    (let ((basename (file-name-nondirectory target))
          (regex-cat (gptel-auto-workflow--categorize-target-by-regex target))
          (kept-counts (make-hash-table :test 'equal :size 4))
          (result nil))
      (when regex-cat
        (condition-case _err
            (dolist (r (gptel-auto-workflow--parse-all-results 30))
              (let ((r-target (plist-get r :target))
                    (r-decision (plist-get r :decision)))
                (when (and r-target
                           (string= (file-name-nondirectory r-target) basename)
                           (equal r-decision "kept"))
                  (let ((r-cat (gptel-auto-workflow--categorize-target-by-regex r-target)))
                    (when r-cat
                      (cl-incf (gethash r-cat kept-counts 0)))))))
          (error nil)))
      (when (> (hash-table-count kept-counts) 0)
        (let ((best nil) (best-n 0))
          (maphash (lambda (cat n)
                     (when (> n best-n) (setq best cat best-n n)))
                   kept-counts)
          (when (and best (>= best-n 2))
            (setq result best))))
      result)))

(defun gptel-auto-workflow--memory-schema--category-from-schemas (target)
  "Look up category for TARGET from schema index.
Uses IDF-weighted entity matching then schema classification.
Returns keyword or nil."
  (let* ((basename (file-name-nondirectory target))
         (slug (file-name-sans-extension basename))
         (total (hash-table-count gptel-auto-workflow--memory-schema-entities))
         (matches nil))
    (maphash (lambda (name count-sources)
               (when (string-match-p (regexp-quote name) basename)
                 (push (cons name
                             (gptel-auto-workflow--memory-schema-entity-idf
                              name count-sources total))
                       matches)))
             gptel-auto-workflow--memory-schema-entities)
    (when (and (not matches)
               (gethash slug gptel-auto-workflow--memory-schema-entities))
      (push (cons slug
                  (gptel-auto-workflow--memory-schema-entity-idf
                   slug (gethash slug gptel-auto-workflow--memory-schema-entities) total))
            matches))
    (when matches
      (let* ((sorted (cl-sort matches #'> :key #'cdr))
             (best-entity (car (car sorted)))
             (cat-scores (list (cons :agentic 0)
                               (cons :programming 0)
                               (cons :tool-calls 0)
                               (cons :natural-language 0))))
        (maphash
         (lambda (_key schema-source)
           (let ((schema-key (car schema-source)))
             (when (and (string-match-p (regexp-quote best-entity) schema-key)
                        (gptel-auto-workflow--memory-schema-stable-p schema-key))
               (dolist (cat-score
                        (gptel-auto-workflow--memory-schema--classify-schema schema-key))
                 (cl-incf (cdr (assq (car cat-score) cat-scores))
                          (cdr cat-score))))))
         gptel-auto-workflow--memory-schema-triples)
        (let ((best-cat (car (cl-sort cat-scores #'> :key #'cdr))))
          (when (> (cdr best-cat) 0)
            (car best-cat)))))))

(defun gptel-auto-workflow--memory-schema--classify-schema (schema-key)
  "Classify SCHEMA-KEY into category scores.
Returns list of (CATEGORY . SCORE) where SCORE reflects how strongly
the schema's predicate/object signals that category."
  (let ((parts (split-string (substring schema-key 1 -1) " "))
        (scores nil))
    (when (>= (length parts) 2)
      (let ((subject (nth 0 parts))
            (predicate (nth 1 parts))
            (object (or (nth 2 parts) "")))
        (let ((agentic-score
               (+ (if (string-match-p
                       "agent\\|workflow\\|evolution\\|strategy\\|dispatch\\|orchestrat"
                       predicate) 2 0)
                  (if (string-match-p
                       "agent\\|workflow\\|evolution\\|strategy\\|subagent\\|persona"
                       object) 1 0)
                  (if (string-match-p
                       "agent\\|workflow\\|evolution\\|strategy"
                       subject) 1 0)))
              (tool-score
               (+ (if (string-match-p
                       "tool\\|bash\\|grep\\|edit\\|sandbox\\|execut\\|invok"
                       predicate) 2 0)
                  (if (string-match-p
                       "tool\\|bash\\|grep\\|edit\\|sandbox\\|command\\|shell"
                       object) 1 0)
                  (if (string-match-p
                       "tool\\|bash\\|grep\\|sandbox"
                       subject) 1 0)))
              (nl-score
               (+ (if (string-match-p
                       "context\\|prompt\\|stream\\|summariz\\|generat\\|render"
                       predicate) 2 0)
                  (if (string-match-p
                       "context\\|prompt\\|stream\\|text\\|language\\|cache"
                       object) 1 0)
                  (if (string-match-p
                       "context\\|prompt\\|stream\\|chat"
                       subject) 1 0)))
              (prog-score
               (+ (if (string-match-p
                       "fix\\|add\\|remov\\|updat\\|refactor\\|rewrit\\|harden\\|enforc\\|compil\\|debug"
                       predicate) 1 0)
                  (if (string-match-p
                       "warning\\|error\\|bug\\|test\\|compil\\|byte\\|type"
                       object) 2 0)
                  (if (string-match-p
                       "compil\\|byte\\|test\\|bench\\|fsm\\|retry"
                       subject) 1 0))))
          (when (> agentic-score 0) (push (cons :agentic agentic-score) scores))
          (when (> tool-score 0) (push (cons :tool-calls tool-score) scores))
          (when (> nl-score 0) (push (cons :natural-language nl-score) scores))
          (when (> prog-score 0) (push (cons :programming prog-score) scores))
          (when (null scores) (push (cons :programming 1) scores)))))
    scores))

;; ─── Conflict Detection ───

(defun gptel-auto-workflow--memory-schema-detect-conflicts ()
  "Scan entity index for potential conflicts.
Returns list of (ENTITY (SOURCE1 . SOURCE2) CONFLICT-TYPE)."
  (gptel-auto-workflow--memory-schema-ensure-loaded)
  (let ((conflicts nil))
    (maphash (lambda (name count-sources)
               (let ((sources (cdr count-sources)))
                 (when (and (>= (length sources) 2)
                            (string-match-p "\\(?:fix\\|remov\\|add\\)" name))
                   (let ((unique-sources (delete-dups sources)))
                     (when (>= (length unique-sources) 2)
                       (push (list name
                                   (cons (nth 0 unique-sources)
                                         (nth 1 unique-sources))
                                   :mutual)
                             conflicts))))))
              gptel-auto-workflow--memory-schema-entities)
     conflicts))

;; ─── Graph Retrieval (PPR-lite) ───

(defun gptel-auto-workflow--memory-schema-entity-neighbors (entity)
   "Return entities connected to ENTITY via shared schemas and git-embed synonymy.
Each neighbor is (ENTITY-NAME . SCORE).
Schema neighbors use shared-schema count; git-embed neighbors use
file-similarity score.  Git-embed edges are included when available."
   (gptel-auto-workflow--memory-schema-ensure-loaded)
   (let ((entity-schemas nil)
         (neighbors (make-hash-table :test 'equal :size 16)))
     (maphash (lambda (_key schema-source)
                (let ((schema-key (car schema-source)))
                  (when (string-match-p (regexp-quote entity) schema-key)
                    (push schema-key entity-schemas))))
              gptel-auto-workflow--memory-schema-triples)
     (dolist (schema entity-schemas)
       (maphash (lambda (_key schema-source)
                  (let ((sk (car schema-source)))
                    (when (equal sk schema)
                      (dolist (part (split-string (substring sk 1 -1) " "))
                        (when (and (not (equal part entity))
                                   (not (equal part "?"))
                                   (not (member part '("fix" "add" "remov" "updat"
                                                       "improv" "replac" "rewrit"
                                                       "refactor" "enforc" "harden"))))
                          (puthash part (1+ (gethash part neighbors 0))
                                   neighbors))))))
                gptel-auto-workflow--memory-schema-triples))
     (let ((embed-synonyms (ignore-errors
                             (gptel-auto-workflow--memory-schema-synonyms-for entity))))
       (dolist (syn embed-synonyms)
         (let ((name (car syn))
               (score (cdr syn)))
           (puthash name (max score (gethash name neighbors 0))
                    neighbors))))
     (let ((result nil))
       (maphash (lambda (name count) (push (cons name count) result))
                neighbors)
       (cl-sort result #'> :key #'cdr))))

(defun gptel-auto-workflow--memory-schema-retrieve (query &optional max-depth)
  "Retrieve related entities for QUERY via graph walk.
MAX-DEPTH defaults to 2.  Returns list of (ENTITY . SCORE) where
SCORE = sum of shared-schema counts at each depth level."
  (gptel-auto-workflow--memory-schema-ensure-loaded)
  (let* ((depth (or max-depth 2))
         (seen (make-hash-table :test 'equal))
         (results nil)
         (frontier (list query)))
    (dotimes (_d depth)
      (let ((next-frontier nil))
        (dolist (entity frontier)
          (dolist (neighbor (gptel-auto-workflow--memory-schema-entity-neighbors entity))
            (let ((name (car neighbor))
                  (score (cdr neighbor)))
              (unless (gethash name seen)
                (puthash name t seen)
                (push (cons name score) results)
                (push name next-frontier)))))
        (setq frontier next-frontier)))
    (cl-sort (delete-dups results) #'> :key #'cdr)))

;; ─── Integration: Extract from Memory File ───

(defun gptel-auto-workflow--memory-schema-extract-from-file (file)
  "Extract triples from a mementum memory FILE and update the index."
  (when gptel-auto-workflow-memory-schema-enabled
    (let* ((content (with-temp-buffer
                      (insert-file-contents file)
                      (buffer-string)))
           (body (if (string-match "^---\n.*?\n---\n" content)
                     (substring content (match-end 0))
                   content))
           (triples (gptel-auto-workflow--memory-schema-extract-triples body)))
      (when triples
        (gptel-auto-workflow--memory-schema-index-triples
         triples (file-name-nondirectory file))))))

(defun gptel-auto-workflow--memory-schema-rebuild-index ()
  "Rebuild the schema index from all memory and knowledge files."
  (interactive)
  (let* ((root (gptel-auto-workflow--worktree-base-root))
         (memories-dir (expand-file-name "mementum/memories" root))
         (knowledge-dir (expand-file-name "mementum/knowledge" root))
         (total 0))
    (gptel-auto-workflow--memory-schema-reset)
    (dolist (dir (list memories-dir knowledge-dir))
      (when (file-directory-p dir)
        (dolist (file (directory-files dir t "\\.md$"))
          (cl-incf total
                   (or (gptel-auto-workflow--memory-schema-extract-from-file file) 0)))))
    (gptel-auto-workflow--memory-schema-save-index)
    (message "[memory-schema] Rebuilt index: %d new schemas, %d stable"
             total
             (length (gptel-auto-workflow--memory-schema-stable-schemas)))))

;; ─── Bidirectional Memory-Code Links ───

(defvar gptel-auto-workflow--memory-schema-code-links nil
  "Hash table: CODE-FILE-REL -> list of referenced memory slugs.
Populated by `gptel-auto-workflow--memory-schema-scan-code-links'.")

(defun gptel-auto-workflow--memory-schema-scan-code-links ()
  "Scan project source files for @memory: references.
Populates `gptel-auto-workflow--memory-schema-code-links'."
  (setq gptel-auto-workflow--memory-schema-code-links
        (make-hash-table :test 'equal :size 128))
  (let* ((root (gptel-auto-workflow--worktree-base-root))
         (lisp-dir (expand-file-name "lisp/modules" root)))
    (when (file-directory-p lisp-dir)
      (dolist (file (directory-files lisp-dir t "\\.el$"))
        (let* ((rel (file-relative-name file root))
               (refs nil))
          (with-temp-buffer
            (insert-file-contents file)
            (goto-char (point-min))
            (while (re-search-forward "@memory:\\([a-zA-Z0-9_-]+\\)" nil t)
              (push (match-string 1) refs)))
          (when refs
            (puthash rel (delete-dups refs)
                     gptel-auto-workflow--memory-schema-code-links)))))))

(defun gptel-auto-workflow--memory-schema-memories-for-file (code-file)
  "Return list of memory slugs referenced by CODE-FILE.
CODE-FILE can be absolute or relative to project root."
  (unless gptel-auto-workflow--memory-schema-code-links
    (gptel-auto-workflow--memory-schema-scan-code-links))
  (let* ((root (gptel-auto-workflow--worktree-base-root))
         (rel (file-relative-name code-file root)))
    (gethash rel gptel-auto-workflow--memory-schema-code-links)))

(defun gptel-auto-workflow--memory-schema-files-for-memory (slug)
  "Return list of code files that reference memory with SLUG."
  (unless gptel-auto-workflow--memory-schema-code-links
    (gptel-auto-workflow--memory-schema-scan-code-links))
  (let ((files nil))
    (maphash (lambda (code-file slugs)
               (when (member slug slugs)
                 (push code-file files)))
             gptel-auto-workflow--memory-schema-code-links)
    files))

;; ─── Experiment-Scoped Memory Injection ───

(defun gptel-auto-workflow--memory-schema-experiment-context (target &optional max-chars)
  "Build experiment-scoped memory context for TARGET.
Returns a string with relevant memories and graph-retrieved entities,
suitable for injection into subagent prompts.  MAX-CHARS defaults to 1500."
  (gptel-auto-workflow--memory-schema-ensure-loaded)
  (let* ((max-len (or max-chars 1500))
         (basename (file-name-nondirectory target))
         (slug (file-name-sans-extension basename))
         (parts nil))
    (when (fboundp 'gptel-auto-workflow--mementum-read-valid-memories)
      (let ((memories (gptel-auto-workflow--mementum-read-valid-memories 30))
            (relevant nil))
        (dolist (mem memories)
          (let ((_file (car mem))
                (content (cdr mem)))
            (when (string-match-p (regexp-quote basename) content)
              (push content relevant))))
        (when relevant
          (push (concat "## Relevant Memories\n\n"
                        (mapconcat (lambda (s)
                                     (let ((trimmed (string-trim s)))
                                       (if (> (length trimmed) 300)
                                           (concat (substring trimmed 0 297) "...")
                                         trimmed)))
                                   (seq-take (nreverse relevant) 5)
                                   "\n\n"))
                parts))))
    (let ((related nil)
          (basename-slug (file-name-sans-extension basename)))
      (dolist (entity-name (cons basename-slug
                                  (delq nil
                                        (mapcar (lambda (e)
                                                  (when (string-match-p (regexp-quote (car e)) basename)
                                                    (car e)))
                                                (let ((all nil))
                                                  (maphash (lambda (k v) (push (cons k v) all))
                                                           gptel-auto-workflow--memory-schema-entities)
                                                  all)))))
        (dolist (r (gptel-auto-workflow--memory-schema-retrieve entity-name 1))
          (push r related)))
      (setq related (delete-dups related))
      (when related
        (push (concat "## Related Entities\n\n"
                      (mapconcat (lambda (e) (format "- %s (%d)" (car e) (cdr e)))
                                 (seq-take (cl-sort related #'> :key #'cdr) 10)
                                 "\n"))
              parts)))
    (when (fboundp 'gptel-auto-workflow--memory-schema-files-for-memory)
      (ignore-errors
       (let ((code-links (gptel-auto-workflow--memory-schema-files-for-memory slug)))
         (when code-links
           (push (concat "## Code References\n\n"
                         (mapconcat (lambda (s) (format "- @memory:%s" s))
                                    (seq-take code-links 5) "\n"))
                 parts)))))
    (condition-case nil
        (when (fboundp 'gptel-auto-workflow--unified-graph-walk)
          (let ((walk (gptel-auto-workflow--unified-graph-walk :file slug 1 '(:similar :schema-neighbor :synonymy))))
            (when walk
              (push (concat "## Graph Neighbors\n\n"
                            (mapconcat (lambda (n)
                                         (format "- %s %s (%.2f)"
                                                 (symbol-name (caar n)) (cdar n) (cdr n)))
                                       (seq-take walk 8) "\n"))
                    parts))))
      (error nil))
    (when parts
      (let ((result (mapconcat #'identity (nreverse parts) "\n\n")))
        (if (> (length result) max-len)
            (concat (substring result 0 (- max-len 3)) "...")
          result)))))

;; ─── Entity Synonymy via git-embed ───

(defun gptel-auto-workflow--memory-schema-git-embed-bin ()
  "Return path to git-embed binary, or nil if unavailable."
  (or (executable-find "git-embed")
      (let ((bin (expand-file-name "bin/git-embed"
                                   (gptel-auto-workflow--worktree-base-root))))
        (when (file-executable-p bin) bin))))

(defun gptel-auto-workflow--memory-schema-synonymy-edges (&optional threshold)
  "Compute entity synonymy edges using git-embed file similarity.
Strategy: for each entity's source files, find similar files via
git-embed, then extract entities from those similar files.  Entities
co-occurring in similar file neighborhoods are synonymy candidates.
Returns alist of (ENTITY . ((SYNONYM . SCORE) ...)) with SCORE >= THRESHOLD
\(default 0.70).  Cached for 1 hour."
  (let ((threshold (or threshold 0.70))
        (now (float-time)))
    (if (and gptel-auto-workflow--memory-schema-synonymy-cache-time
             (< (- now gptel-auto-workflow--memory-schema-synonymy-cache-time) 3600))
        (cl-remove-if (lambda (entry)
                        (< (cdr entry) threshold))
                      (mapcar (lambda (group)
                                (cons (car group)
                                      (cl-remove-if (lambda (p) (< (cdr p) threshold))
                                                    (cdr group))))
                              gptel-auto-workflow--memory-schema-synonymy-cache))
      (let ((git-embed (gptel-auto-workflow--memory-schema-git-embed-bin))
            (root (gptel-auto-workflow--worktree-base-root))
            (result nil))
        (if (not git-embed)
            (progn
              (setq gptel-auto-workflow--memory-schema-synonymy-cache nil
                    gptel-auto-workflow--memory-schema-synonymy-cache-time now)
              nil)
          (gptel-auto-workflow--memory-schema-ensure-loaded)
          (let ((entity-files (make-hash-table :test 'equal :size 64)))
            (maphash (lambda (entity _count)
                       (let ((files (ignore-errors
                                      (gptel-auto-workflow--memory-schema-files-for-memory entity))))
                         (when files
                           (puthash entity files entity-files))))
                     gptel-auto-workflow--memory-schema-entities)
            (let ((file-entities (make-hash-table :test 'equal :size 64)))
              (maphash (lambda (entity files)
                         (dolist (f files)
                           (puthash f (cons entity (gethash f file-entities nil))
                                    file-entities)))
                       entity-files)
              (maphash
               (lambda (entity files)
                 (let ((synonyms (make-hash-table :test 'equal :size 16))
                       (max-score 0.0))
                   (dolist (rel-file files)
                     (let ((abs (expand-file-name rel-file root)))
                       (when (file-exists-p abs)
                         (let ((output (shell-command-to-string
                                        (mapconcat #'shell-quote-argument
                                                   (list git-embed "similar" abs "-n" "5")
                                                   " "))))
                           (dolist (line (split-string output "\n" t))
                             (when (string-match
                                    "^\\([0-9.]+\\)\\s-+\\(.+\\)$" line)
                               (let ((score (string-to-number (match-string 1 line)))
                                     (sim-file (match-string 2 line)))
                                 (when (>= score threshold)
                                   (setq max-score (max max-score score))
                                   (dolist (e (gethash sim-file file-entities nil))
                                     (unless (equal e entity)
                                       (puthash e (max score (gethash e synonyms 0.0))
                                                synonyms)))))))))))
                   (when (> (hash-table-count synonyms) 0)
                     (let ((pairs nil))
                       (maphash (lambda (name score) (push (cons name score) pairs))
                                synonyms)
                       (push (cons entity (cl-sort pairs #'> :key #'cdr))
                             result)))))
               entity-files))
            (setq gptel-auto-workflow--memory-schema-synonymy-cache result
                  gptel-auto-workflow--memory-schema-synonymy-cache-time now)
            result))))))

(defun gptel-auto-workflow--memory-schema-synonyms-for (entity)
  "Return synonymy edges for ENTITY from git-embed, or nil."
  (let ((edges (gptel-auto-workflow--memory-schema-synonymy-edges)))
    (cdr (assoc entity edges))))

;; ─── Ontology → Memory Feedback ───

(defun gptel-auto-workflow--memory-schema-record-ontology-event (event-type data)
  "Record an ontology EVENT-TYPE with DATA into the schema index.
EVENT-TYPE is one of :saturation, :strategy-change, :drift, :backend-change.
DATA is a plist with event-specific fields.
Creates entity and triple entries so future graph walks surface these
learnings."
  (gptel-auto-workflow--memory-schema-ensure-loaded)
  (let* ((category (plist-get data :category))
         (cat-str (and category
                       (let ((s (symbol-name category)))
                         (if (string-prefix-p ":" s) (substring s 1) s))))
         (entity-name (cond
                       ((eq event-type :saturation)
                        (format "%s-saturation" cat-str))
                       ((eq event-type :strategy-change)
                        (format "%s-strategy" cat-str))
                       ((eq event-type :drift)
                        (format "%s-drift" (plist-get data :target)))
                       ((eq event-type :backend-change)
                        (format "%s-backend" cat-str))
                       (t nil))))
    (when entity-name
      (let ((triple (pcase event-type
                      (:saturation
                       (list :subject entity-name
                             :predicate "saturated"
                             :object (format "%d-experiments-0-keeps"
                                             (or (plist-get data :total) 0))
                             :subject-type cat-str
                             :object-type "diagnostic"))
                      (:strategy-change
                       (list :subject entity-name
                             :predicate "switched"
                             :object (format "%s-to-%s"
                                             (or (plist-get data :from) "default")
                                             (or (plist-get data :to) "unknown"))
                             :subject-type cat-str
                             :object-type "strategy"))
                      (:drift
                       (list :subject entity-name
                             :predicate "drifted"
                             :object (format "from-%s-delta-%+.0f%%"
                                             (or (plist-get data :from-cat) "unknown")
                                             (* 100 (or (plist-get data :delta) 0)))
                             :subject-type cat-str
                             :object-type "diagnostic"))
                      (:backend-change
                       (list :subject entity-name
                             :predicate "preferred"
                             :object (or (plist-get data :backend) "unknown")
                             :subject-type cat-str
                             :object-type "backend"))
                      (_ nil))))
        (when triple
          (gptel-auto-workflow--memory-schema-index-triples
           (list triple) (format "ontology-%s" entity-name)))))))

(defun gptel-auto-workflow--memory-schema-record-evolution (evolve-result)
  "Record all ontology events from EVOLVE-RESULT into the schema index.
EVOLVE-RESULT is the plist returned by `evolve-ontology':
  (:changes N :backend-changes N :saturated N :total-strategies N).
Reads the global state to extract individual events."
  (when (and evolve-result (> (+ (or (plist-get evolve-result :changes) 0)
                                  (or (plist-get evolve-result :saturated) 0)) 0))
    (gptel-auto-workflow--memory-schema-ensure-loaded)
    (when (boundp 'gptel-auto-workflow--category-strategy-preferences)
      (dolist (pref gptel-auto-workflow--category-strategy-preferences)
        (gptel-auto-workflow--memory-schema-record-ontology-event
         :strategy-change
         (list :category (car pref)
               :to (cdr pref)))))
    (when (boundp 'gptel-auto-workflow--category-saturation)
      (dolist (sat gptel-auto-workflow--category-saturation)
        (when (cdr sat)
          (gptel-auto-workflow--memory-schema-record-ontology-event
           :saturation
           (list :category (car sat))))))
    (gptel-auto-workflow--memory-schema-persist)))

;; ─── Persistence ───

(defun gptel-auto-workflow--memory-schema-persist ()
  "Save current schema index to disk."
  (when gptel-auto-workflow--memory-schema-schemas
    (gptel-auto-workflow--memory-schema-save-index)))

;; ─── Unified Entity-Ontology Graph ───

(defun gptel-auto-workflow--unified-graph-build ()
  "Build the unified entity-ontology graph from all data sources.
Merges edges from: digital twin (requires), git-embed (similar),
schema triples (schema-neighbor), synonymy, skill graph,
category routing, and backend preferences.
Returns the graph hash table."
  (let ((graph (make-hash-table :test 'equal :size 256)))
    (cl-labels ((edge-confidence (edge-type weight)
                  (cond ((eq edge-type :requires) (cons 'EXTRACTED 1.0))
                        ((eq edge-type :similar) (cons 'INFERRED (min 1.0 weight)))
                        ((eq edge-type :schema-neighbor) (cons 'INFERRED 0.8))
                        ((eq edge-type :skill-graph) (cons 'INFERRED (min 1.0 weight)))
                        ((eq edge-type :co-occurrence) (cons 'AMBIGUOUS 0.3))
                        (t (cons 'INFERRED 0.5))))
                (ensure-node (type id)
                  (let ((key (cons type id)))
                    (unless (gethash key graph)
                      (puthash key nil graph))
                    key))
                (add-edge (from-type from-id to-type to-id edge-type weight)
                  (when (and from-id to-id (> weight 0))
                    (let* ((from-key (ensure-node from-type from-id))
                           (to-key (cons to-type to-id))
                           (existing (gethash from-key graph))
                           (conf (edge-confidence edge-type weight)))
                      (puthash from-key
                               (cons (list edge-type to-key weight
                                           (car conf) (cdr conf))
                                     existing)
                               graph)))))
      (gptel-auto-workflow--memory-schema-ensure-loaded)
      (let ((root (condition-case nil (gptel-auto-workflow--worktree-base-root) (error nil))))
        (when root
          (condition-case nil
              (let ((twin (or (and (fboundp 'gptel-auto-workflow--build-digital-twin)
                                   (condition-case nil
                                       (gptel-auto-workflow--build-digital-twin)
                                     (error nil)))
                              (and (fboundp 'gptel-auto-workflow--load-target-state)
                                   (condition-case nil
                                       (progn (gptel-auto-workflow--load-target-state) nil)
                                     (error nil))))))
                (when (and twin (hash-table-p twin))
                  (maphash
                   (lambda (file-key entry)
                     (let ((basename (file-name-nondirectory file-key)))
                       (dolist (req (plist-get entry :requires))
                         (add-edge :file basename :file req :requires 1.0))))
                   twin)))
            (error nil)))
        (condition-case nil
            (when (fboundp 'gptel-auto-workflow--semantic-similarity-edges)
              (dolist (edge (gptel-auto-workflow--semantic-similarity-edges 0.50))
                (let ((src (file-name-nondirectory (plist-get edge :source)))
                      (tgt (plist-get edge :target))
                      (score (plist-get edge :score)))
                  (when (and src tgt score)
                    (add-edge :file src :file tgt :similar score)))))
          (error nil))
        (maphash
         (lambda (_key schema-source)
           (let ((schema-key (car schema-source))
                 (source (cdr schema-source)))
             (let ((parts (split-string (substring schema-key 1 -1) " ")))
               (when (>= (length parts) 2)
                 (let ((subject (nth 0 parts))
                       (object (or (nth 2 parts) "")))
                   (dolist (entity (delq nil (list subject object)))
                     (add-edge :entity entity :entity subject :schema-neighbor 1.0))
                   (when (and source (not (string= source "")))
                     (add-edge :entity subject :file source :category-of 1.0)))))))
         gptel-auto-workflow--memory-schema-triples)
        (condition-case nil
            (when (fboundp 'gptel-auto-workflow--memory-schema-synonymy-edges)
              (dolist (group (gptel-auto-workflow--memory-schema-synonymy-edges 0.60))
                (let ((entity (car group)))
                  (dolist (syn (cdr group))
                    (add-edge :entity entity :entity (car syn) :synonymy (cdr syn))))))
          (error nil))
        (when (and (boundp 'gptel-auto-workflow--category-strategy-preferences)
                   gptel-auto-workflow--category-strategy-preferences)
          (dolist (pref gptel-auto-workflow--category-strategy-preferences)
            (let ((cat-str (substring (symbol-name (car pref)) 1)))
              (add-edge :category cat-str :strategy (cdr pref) :strategy-pref 1.0))))
        (when (and (boundp 'gptel-auto-workflow--category-backend-overrides)
                   gptel-auto-workflow--category-backend-overrides)
          (dolist (override gptel-auto-workflow--category-backend-overrides)
            (let ((cat-str (substring (symbol-name (car override)) 1)))
              (add-edge :category cat-str :backend (cdr override) :best-backend 1.0))))
        (condition-case nil
            (when (and (boundp 'skill-graph--nodes) (hash-table-p skill-graph--nodes))
              (maphash
               (lambda (id node)
                 (add-edge :skill (symbol-name id)
                           :category (substring (symbol-name (skill-graph-node-level node)) 1)
                           :category-of 1.0))
               skill-graph--nodes)
              (maphash
               (lambda (key edge)
                 (add-edge :skill (symbol-name (car key))
                           :skill (symbol-name (cdr key))
                           :skill-cooccur (skill-graph-edge-weight edge)))
               skill-graph--edges))
          (error nil))))
    (setq gptel-auto-workflow--unified-graph graph
          gptel-auto-workflow--unified-graph-time (float-time))
    graph))

(defun gptel-auto-workflow--unified-graph-ensure ()
  "Ensure the unified graph is built, rebuilding if stale (1 hour)."
  (let ((now (float-time)))
    (when (or (not gptel-auto-workflow--unified-graph)
              (not gptel-auto-workflow--unified-graph-time)
              (> (- now gptel-auto-workflow--unified-graph-time) 3600))
      (gptel-auto-workflow--unified-graph-build)))
  gptel-auto-workflow--unified-graph)

(defun gptel-auto-workflow--unified-graph-neighbors (type id &optional edge-types)
  "Return neighbors of node (TYPE . ID) in the unified graph.
EDGE-TYPES is an optional list of edge types to filter by.
Returns list of (EDGE-TYPE (TO-TYPE . TO-ID) WEIGHT)."
  (let ((graph (gptel-auto-workflow--unified-graph-ensure))
        (key (cons type id)))
    (let ((edges (gethash key graph)))
      (if edge-types
          (cl-remove-if-not (lambda (e) (memq (car e) edge-types)) edges)
        edges))))

(defun gptel-auto-workflow--unified-graph-walk (type id &optional max-depth edge-types)
  "Walk the unified graph from node (TYPE . ID) up to MAX-DEPTH (default 2).
Returns list of ((TO-TYPE . TO-ID) . CUMULATIVE-SCORE) sorted by score.
EDGE-TYPES optionally filters which edge types to traverse."
  (let ((graph (gptel-auto-workflow--unified-graph-ensure))
        (depth (or max-depth 2))
        (seen (make-hash-table :test 'equal :size 64))
        (results nil)
        (frontier (list (cons (cons type id) 1.0))))
    (dotimes (_d depth)
      (let ((next-frontier nil))
        (dolist (entry frontier)
          (let* ((node-key (car entry))
                 (cum-score (cdr entry)))
            (dolist (edge (gethash node-key graph))
              (let* ((edge-type (car edge))
                     (to-key (cadr edge))
                     (weight (nth 2 edge)))
                (when (and (or (null edge-types) (memq edge-type edge-types))
                           (not (gethash to-key seen)))
                  (puthash to-key t seen)
                  (let ((score (* cum-score weight)))
                    (push (cons to-key score) results)
                    (push (cons to-key score) next-frontier)))))))
        (setq frontier next-frontier)))
    (cl-sort (delete-dups results) #'> :key #'cdr)))

(defun gptel-auto-workflow--unified-graph-best-backend-for (target)
  "Find the best backend for TARGET using unified graph walk.
Walks: target -> category -> best-backend, and target -> file ->
similar files -> their categories -> their backends.
Returns list of (BACKEND . SCORE)."
  (let* ((basename (file-name-nondirectory target))
         (slug (file-name-sans-extension basename))
         (category (when (fboundp 'gptel-auto-workflow--categorize-target)
                     (gptel-auto-workflow--categorize-target target)))
         (cat-str (and category (substring (symbol-name category) 1)))
         (backends (make-hash-table :test 'equal :size 8)))
    (when cat-str
      (dolist (edge (gptel-auto-workflow--unified-graph-neighbors :category cat-str
                                                                    '(:best-backend)))
        (let ((backend (cdr (cadr edge)))
              (weight (nth 2 edge))
              (conf-score (or (nth 4 edge) 0.5)))
          (puthash backend (max (* weight conf-score)
                               (gethash backend backends 0.0)) backends))))
    (dolist (edge (gptel-auto-workflow--unified-graph-neighbors :file slug '(:similar)))
      (let ((sim-file (cdr (cadr edge)))
            (sim-score (nth 2 edge))
            (conf-score (or (nth 4 edge) 0.5)))
        (let ((sim-cat (when (fboundp 'gptel-auto-workflow--categorize-target)
                         (gptel-auto-workflow--categorize-target sim-file))))
          (when sim-cat
            (dolist (be (gptel-auto-workflow--unified-graph-neighbors
                         :category (substring (symbol-name sim-cat) 1) '(:best-backend)))
               (let ((backend (cdr (cadr be)))
                     (weight (* sim-score (nth 2 be) conf-score)))
                (puthash backend (max weight (gethash backend backends 0.0)) backends)))))))
    (let ((result nil))
      (maphash (lambda (backend score) (push (cons backend score) result)) backends)
      (cl-sort result #'> :key #'cdr))))

(defun gptel-auto-workflow--graph-same-community-p (target-a target-b)
  "Return t if TARGET-A and TARGET-B share the same graph community."
  (let* ((comms (gptel-auto-workflow--unified-graph-communities))
         (sa (file-name-sans-extension (file-name-nondirectory target-a)))
         (sb (file-name-sans-extension (file-name-nondirectory target-b))))
    (when comms (let ((ca (gethash (cons :file sa) comms)) (cb (gethash (cons :file sb) comms))) (and ca cb (= ca cb))))))

(defun gptel-auto-workflow--graph-community-for-target (target)
  "Return community ID for TARGET, or nil."
  (let* ((comms (gptel-auto-workflow--unified-graph-communities))
         (slug (file-name-sans-extension (file-name-nondirectory target))))
    (when comms (gethash (cons :file slug) comms))))

;;; Graph topology analysis (community detection + centrality — graphify-inspired)

(defun gptel-auto-workflow--unified-graph-god-nodes (&optional top-n)
  "Return the most-connected nodes in the unified graph by degree centrality.
Excludes file-level hub nodes and isolates. Returns list of (node-key .
degree).
TOP-N defaults to 10."
  (let ((graph (gptel-auto-workflow--unified-graph-ensure))
        (degrees (make-hash-table :test 'equal :size 64)))
    (when graph
      ;; Count outgoing degree for each node
      (maphash (lambda (from-key edges)
                 (when edges
                   (puthash from-key
                            (+ (length edges)
                               (gethash from-key degrees 0))
                            degrees)
                   (dolist (edge edges)
                     (let ((to-key (cadr edge)))
                       (puthash to-key
                                (1+ (gethash to-key degrees 0))
                                degrees)))))
               graph)
      ;; Sort by degree descending, filter file hubs and isolates
      (let ((ranked '()))
        (maphash (lambda (key deg)
                   (let ((type (car key)))
                     ;; Skip file hubs (all files connect to many things)
                     (unless (and (eq type :file) (> deg 10))
                       (push (cons key deg) ranked))))
                 degrees)
        (seq-take (cl-sort ranked #'> :key #'cdr)
                  (or top-n 10))))))

(defun gptel-auto-workflow--unified-graph-communities (&optional max-iterations)
  "Detect communities in the unified graph using label propagation.
Returns hash table: node-key -> community-id (integer).
MAX-ITERATIONS defaults to 20."
  (let* ((graph (gptel-auto-workflow--unified-graph-ensure))
         (communities (make-hash-table :test 'equal :size 64))
         (nodes '())
         (community-id 0))
    (when graph
      ;; Initialize: each node in its own community
      (maphash (lambda (key _edges)
                 (puthash key community-id communities)
                 (push key nodes)
                 (setq community-id (1+ community-id)))
               graph)
      ;; Label propagation
      (cl-loop for iteration from 0 below (or max-iterations 20)
               for changed = nil
               do (dolist (node nodes)
            (let* ((edges (gethash node graph))
                   (neighbor-votes (make-hash-table :test 'equal :size 16)))
              ;; Count neighbor community votes
              (dolist (edge (or edges '()))
                (let* ((to-key (cadr edge))
                       (neighbor-community (gethash to-key communities)))
                  (when neighbor-community
                    (puthash neighbor-community
                             (1+ (gethash neighbor-community neighbor-votes 0))
                             neighbor-votes))))
              ;; Also count reverse edges (nodes that point TO this node)
              (dolist (other-node nodes)
                (unless (equal other-node node)
                  (dolist (edge (gethash other-node graph))
                    (when (equal (cadr edge) node)
                      (let ((nc (gethash other-node communities)))
                        (when nc
                          (puthash nc
                                   (1+ (gethash nc neighbor-votes 0))
                                   neighbor-votes)))))))
              ;; Choose majority community
              (let ((best-community nil) (best-count 0))
                (maphash (lambda (comm count)
                           (when (> count best-count)
                             (setq best-community comm best-count count)))
                         neighbor-votes)
                (when (and best-community
                           (not (= best-community (gethash node communities))))
                  (puthash node best-community communities)
                   (setq changed t)))))
          (unless changed
            (message "[memory-schema] Label propagation converged after %d iterations"
                     iteration)
            (cl-return communities)))
      communities)))

(defun gptel-auto-workflow--unified-graph-community-cohesion (communities)
  "Compute cohesion scores for each community in COMMUNITIES.
Returns hash table: community-id -> cohesion (0.0-1.0).
Cohesion = fraction of edges that stay within the community.
High cohesion (>0.7) = well-connected cluster. Low (<0.3) = fragmented."
  (let* ((graph (gptel-auto-workflow--unified-graph-ensure))
         (scores (make-hash-table :test 'equal)))
    (when (and graph communities)
      (maphash (lambda (key _edges)
                 (let ((comm (gethash key communities)))
                   (when comm
                     (let* ((total 0) (internal 0)
                            (edges (gethash key graph)))
                       (dolist (edge (or edges ()))
                         (setq total (1+ total))
                         (let ((to-comm (gethash (cadr edge) communities)))
                           (when (equal comm to-comm)
                             (setq internal (1+ internal)))))
                       (when (> total 0)
                         (puthash comm
                                  (cons (+ (car (gethash comm scores '(0 . 0))) total)
                                        (+ (cdr (gethash comm scores '(0 . 0))) internal))
                                  scores))))))
               graph)
      (maphash (lambda (comm pair)
                 (puthash comm (/ (float (cdr pair)) (max 1 (car pair))) scores))
               scores))
    scores))

(defun gptel-auto-workflow--unified-graph-surprising-connections (&optional top-n)
  "Find surprising cross-community connections in the unified graph.
Returns list of (source-id target-id edge-type score).
Surprising = cross-community edges with low-confidence edge types.
TOP-N defaults to 10."
  (let* ((graph (gptel-auto-workflow--unified-graph-ensure))
         (communities (gptel-auto-workflow--unified-graph-communities))
         (surprises '()))
    (when (and graph communities)
      (maphash (lambda (from-key edges)
                 (let ((from-comm (gethash from-key communities)))
                   (dolist (edge (or edges '()))
                     (let* ((to-key (cadr edge))
                            (to-comm (gethash to-key communities))
                            (edge-type (car edge))
                            (weight (nth 2 edge)))
                       ;; Surprising: cross-community AND (low weight OR inferred edge)
                       (when (and from-comm to-comm
                                  (not (= from-comm to-comm))
                                  (or (< weight 0.5)
                                      (member edge-type '(:similar :schema-neighbor))))
                         (push (list (cdr from-key) (cdr to-key)
                                     edge-type weight
                                     (abs (- from-comm to-comm)))
                               surprises))))))
               graph)
      (seq-take (cl-sort surprises #'> :key (lambda (s) (nth 4 s)))
                (or top-n 10)))))

(defun gptel-auto-workflow--unified-graph-stats-for-prompt ()
  "Return a compact summary of graph topology for prompt injection.
Includes: node count, edge count, top god nodes, community count,
surprising connections. Uses graphify-inspired format."
  (let* ((graph (gptel-auto-workflow--unified-graph-ensure)))
    (when (and graph (> (hash-table-count graph) 0))
      (let* ((node-count (hash-table-count graph))
             (edge-count 0) (extracted 0) (inferred 0) (ambiguous 0)
             (god-nodes (gptel-auto-workflow--unified-graph-god-nodes 5))
             (communities (gptel-auto-workflow--unified-graph-communities))
             (comm-set (make-hash-table :test 'equal))
             (surprises (gptel-auto-workflow--unified-graph-surprising-connections 5)))
        (maphash (lambda (_k edges)
                   (dolist (edge (or edges ()))
                     (setq edge-count (1+ edge-count))
                     (pcase (nth 3 edge)
                       ('EXTRACTED (setq extracted (1+ extracted)))
                       ('INFERRED (setq inferred (1+ inferred)))
                       ('AMBIGUOUS (setq ambiguous (1+ ambiguous))))))
                 graph)
        (when communities
          (maphash (lambda (_k comm) (puthash comm t comm-set)) communities))
        (let* ((cohesion (gptel-auto-workflow--unified-graph-community-cohesion communities))
               (cohesion-str
                (when cohesion
                  (let ((vals '()))
                    (maphash (lambda (_k v) (push v vals)) cohesion)
                    (let ((avg (if vals (/ (apply '+ vals) (length vals)) 0))
                          (low (seq-count (lambda (v) (< v 0.3)) vals)))
                      (format "- Cohesion: %.0f%% avg, %d fragmented communities (<30%%)\n"
                              (* 100 avg) low))))))
        (concat
         "## Knowledge Graph Topology\n"
         (format "- %d nodes, %d edges, %d communities\n"
                 node-count edge-count (hash-table-count comm-set))
         (when cohesion-str cohesion-str)
         (when (> edge-count 0)
           (format "- Confidence: %d EXTRACTED (%.0f%%) %d INFERRED (%.0f%%) %d AMBIGUOUS (%.0f%%)\n"
                   extracted (* 100.0 (/ (float extracted) edge-count))
                   inferred (* 100.0 (/ (float inferred) edge-count))
                   ambiguous (* 100.0 (/ (float ambiguous) edge-count))))
         (when god-nodes
           (concat "- **God nodes** (most-connected):\n"
                   (mapconcat (lambda (n)
                                (format "  - %s:%s (degree=%d)"
                                        (car (car n)) (cdr (car n)) (cdr n)))
                              god-nodes "\n")
                   "\n"))
         (when surprises
           (concat "- **Surprising connections** (cross-community):\n"
                   (mapconcat (lambda (s)
                                (format "  - %s ⟷ %s [%s, weight=%.2f]"
                                        (nth 0 s) (nth 1 s) (nth 2 s) (nth 3 s)))
                              surprises "\n")
                   "\n"))
         "\n"))))))

;;; Graph export (JSON for external tools, visualization)

(defun gptel-auto-workflow--unified-graph-export-json (output-file)
  "Export unified graph as node-link JSON to OUTPUT-FILE.
Format compatible with NetworkX and vis.js."
  (let ((graph (gptel-auto-workflow--unified-graph-ensure)))
    (when (and graph (> (hash-table-count graph) 0))
      (let ((nodes nil) (links nil) (seen (make-hash-table :test 'equal)))
        (maphash (lambda (key edges)
                   (let ((nid (format "%s:%s" (car key) (cdr key))))
                     (unless (gethash nid seen)
                       (puthash nid t seen)
                       (push (format "{\"id\":\"%s\",\"label\":\"%s\",\"type\":\"%s\"}"
                                     nid (cdr key) (car key)) nodes))
                     (dolist (edge (or edges ()))
                       (push (format "{\"source\":\"%s\",\"target\":\"%s\",\"type\":\"%s\",\"weight\":%.2f,\"confidence\":\"%s\"}"
                                     nid (format "%s:%s" (car (cadr edge)) (cdr (cadr edge)))
                                     (car edge) (nth 2 edge) (nth 3 edge))
                             links))))
                 graph)
        (with-temp-file output-file
          (insert "{\n")
          (insert "  \"nodes\": [" (mapconcat #'identity (nreverse nodes) ",\n             ") "],\n")
          (insert "  \"links\": [" (mapconcat #'identity (nreverse links) ",\n             ") "]\n")
          (insert "}\n"))
        (message "[memory-schema] Exported graph to %s (%d nodes, %d edges)"
                 output-file (length nodes) (length links))
        t))))

(defun gptel-auto-workflow--unified-graph-export-html (json-file html-file)
  "Generate an interactive HTML visualization from JSON-FILE.
Writes standalone HTML to HTML-FILE using vis.js from CDN.
The graph is interactive: click nodes, search, zoom, drag."
  (let ((template
         "<!DOCTYPE html>
<html><head><meta charset=\"utf-8\">
<title>OV5 Knowledge Graph</title>
<script
src=\"https://cdnjs.cloudflare.com/ajax/libs/vis/4.21.0/vis.min.js\"></script>
<link href=\"https://cdnjs.cloudflare.com/ajax/libs/vis/4.21.0/vis.min.css\"
rel=\"stylesheet\">
<style>body{margin:0}#graph{width:100vw;height:100vh;background:#1a1a2e}
.vis-node{font-size:12px}.vis-edge{stroke:#555}</style></head>
<body><div id=\"graph\"></div>
<script>
fetch('%s').then(r=>r.json()).then(data=>{
  var nodes=new vis.DataSet(data.nodes.map(n=>({id:n.id,label:n.label,
    group:n.type===\='file\='?1:n.type===\='skill\='?2:3})));
  var edges=new vis.DataSet(data.links.map(l=>({from:l.source,to:l.target,
label:l.type,title:l.confidence+'

















w='+l.weight,color:{color:l.confidence===\='EXTRACTED\='?'#4fc3f7':l.confidence===\='INFERRED\='?'#ffb74d':'#ef5350'}})));
  var container=document.getElementById(\='graph\=');
  new vis.Network(container,{nodes:nodes,edges:edges},{


















groups:{1:{color:{background:'#1565c0'}},2:{color:{background:'#2e7d32'}},3:{color:{background:'#6a1b9a'}}},


















physics:{stabilization:{iterations:100}},edges:{arrows:\='to\=',smooth:{type:\='curvedCW\='}}});
}).catch(e=>document.body.innerHTML='<p style=color:red>Error: '+e+'</p>');
</script></body></html>"))
    (with-temp-file html-file
      (insert (format template
                      (file-relative-name json-file
                                          (file-name-directory html-file)))))
    (message "[memory-schema] Exported HTML visualization to %s" html-file)
    t))

(defun gptel-auto-workflow--mcp-handle-request (method &optional params)
  "Handle an MCP-style query and return a JSON response string.
Supports: graph-stats, god-nodes, communities, node-neighbors,
surprising-edges.
Callable via emacsclient: (gptel-auto-workflow--mcp-handle-request \"method\"
\"params\")"
  (condition-case err
      (let ((result nil))
        (cond
         ((equal method "graph-stats")
          (let* ((g (gptel-auto-workflow--unified-graph-ensure))
                 (nc (if g (hash-table-count g) 0))
                 (ec 0))
            (when g (maphash (lambda (_k e) (setq ec (+ ec (length (or e ()))))) g))
            (setq result (format "{\"nodes\":%d,\"edges\":%d}" nc ec))))
         ((equal method "god-nodes")
          (let ((gn (gptel-auto-workflow--unified-graph-god-nodes (or (and params (read params)) 5))))
            (setq result (format "[%s]" (mapconcat (lambda (n) (format "[\"%s:%s\",%d]" (caar n) (cdar n) (cdr n))) gn ",")))))
         ((equal method "communities")
          (let ((comms (gptel-auto-workflow--unified-graph-communities))
                (counts (make-hash-table :test 'equal)))
            (when comms
              (maphash (lambda (_k v) (puthash v (1+ (gethash v counts 0)) counts)) comms)
              (setq result (format "{\"community_count\":%d}" (hash-table-count counts))))))
         ((equal method "surprising-edges")
          (let ((surp (gptel-auto-workflow--unified-graph-surprising-connections 5)))
            (setq result (format "[%s]" (mapconcat (lambda (s) (format "[\"%s\",\"%s\",\"%s\",%.2f]" (nth 0 s) (nth 1 s) (nth 2 s) (nth 3 s))) surp ",")))))
         (t (setq result "{\"error\":\"unknown method\"}")))
        result)
    (error (format "{\"error\":\"%s\"}" (error-message-string err)))))

;;; AST extraction (deterministic Elisp parsing — graphify's extract() layer)

(defun gptel-auto-workflow--extract-elisp-ast (file-path)
  "Extract structural data from FILE-PATH using Elisp reader.
Returns plist with (:defuns :defvars :requires :provides).
Deterministic — no LLM needed. Uses Emacs' built-in read.
On malformed forms: a bad form may swallow the rest of the file
(Emacs' read maintains paren-depth state across calls). We detect
this by checking that the read form contains one of our known
top-level symbols, and abort the parse if it doesn't."
  (let ((defuns nil) (defvars nil) (requires nil) (provides nil))
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents file-path)
          (goto-char (point-min))
          (while (not (eobp))
            (let* ((form (condition-case nil (read (current-buffer)) (error nil)))
                   (head (and (listp form) (symbolp (car form)) (car form))))
              (cond
               ((null head) (goto-char (point-max)))
               ((memq head '(defun defvar defcustom defconst require provide))
                (pcase head
                  ('defun (push (cadr form) defuns))
                  ((or 'defvar 'defcustom 'defconst) (push (cadr form) defvars))
                  ('require (push (cadr form) requires))
                  ('provide (push (cadr form) provides))))
               (t nil)))))
      (error nil))
    (list :defuns (nreverse defuns) :defvars (nreverse defvars)
          :requires (nreverse requires) :provides (nreverse provides))))

(defun gptel-auto-workflow--ingest-elisp-asts (target-dir)
  "Extract AST from all .el files in TARGET-DIR and add to unified graph.
Adds :defines edges (file -> function), :requires edges (file -> file),
and :provides edges (file -> feature).
Returns number of edges added."
  (let* ((graph (gptel-auto-workflow--unified-graph-ensure))
         (edge-count 0))
    (when (and graph (file-directory-p target-dir))
      (dolist (f (directory-files target-dir t "\\.el$"))
        (let* ((ast (gptel-auto-workflow--extract-elisp-ast f))
               (basename (file-name-nondirectory f))
               (slug (file-name-sans-extension basename)))
          ;; Add :defines edges (file defines function)
          (dolist (fn (plist-get ast :defuns))
            (when (gethash (cons :file slug) graph)
              (let ((existing (gethash (cons :file slug) graph)))
                (puthash (cons :file slug)
                         (cons (list :defines (cons :function (symbol-name fn))
                                     1.0 'EXTRACTED 1.0)
                               existing)
                         graph)
                (setq edge-count (1+ edge-count)))))
          ;; Add :requires edges
          (dolist (req (plist-get ast :requires))
            (let* ((req-name (if (stringp req) req (symbol-name req)))
                   (req-slug (if (string-match "^\\(.+\\)\\.el$" req-name)
                                 (match-string 1 req-name)
                               req-name)))
              (when (gethash (cons :file slug) graph)
                (let ((existing (gethash (cons :file slug) graph)))
                  (puthash (cons :file slug)
                           (cons (list :requires (cons :file req-slug)
                                       1.0 'EXTRACTED 1.0)
                                 existing)
                           graph)
                  (setq edge-count (1+ edge-count))))))))
      (message "[memory-schema] Ingested AST from %s: %d edges added"
               target-dir edge-count))
    edge-count))

;;; Nice-to-have enhancements (graphify-inspired optimizations)

(defun gptel-auto-workflow--graph-token-benchmark ()
  "Estimate token savings from using the graph vs raw corpus.
Compares graph stats token count (~50 tokens per node/edge summary)
against estimated raw file token count (~4 tokens per line).
Returns plist: (:graph-tokens :raw-tokens :savings-pct :ratio)."
  (let* ((graph (gptel-auto-workflow--unified-graph-ensure))
         (nc (if graph (hash-table-count graph) 0))
         (ec 0))
    (when graph (maphash (lambda (_k e) (setq ec (+ ec (length (or e ()))))) graph))
    (let* ((graph-tokens (+ (* nc 10) (* ec 15) 100))  ; ~10 tok/node, ~15 tok/edge
           (root (gptel-auto-workflow-self-audit--root))
           (raw-lines 0))
      (when root
        (dolist (f (directory-files (expand-file-name "lisp/modules" root) t "\\.el$"))
          (with-temp-buffer (insert-file-contents f) (setq raw-lines (+ raw-lines (count-lines (point-min) (point-max)))))))
      (let* ((raw-tokens (* raw-lines 4))  ; ~4 tokens per line of Elisp
            (savings (if (> raw-tokens 0) (- 1 (/ (float graph-tokens) raw-tokens)) 0)))
        (list :graph-tokens graph-tokens :raw-tokens raw-tokens
              :savings-pct (* 100 savings) :ratio (if (> raw-tokens 0) (/ (float raw-tokens) (max 1 graph-tokens)) 0))))))

(defun gptel-auto-workflow--graph-suggest-questions ()
  "Generate investigation questions from graph topology gaps.
Returns list of question strings."
  (let* ((graph (gptel-auto-workflow--unified-graph-ensure))
         (questions nil))
    (when graph
      ;; Isolated nodes (degree 0) — need documentation or investigation
      (let ((isolated 0))
        (maphash (lambda (k e) (when (null e) (setq isolated (1+ isolated)) (when (<= isolated 3) (push (format "Why is %s:%s isolated with no connections?" (car k) (cdr k)) questions)))) graph))
      ;; AMBIGUOUS edges — need verification
      (let ((amb-count 0))
         (maphash (lambda (_k edges) (dolist (e (or edges ())) (when (eq (nth 3 e) 'AMBIGUOUS) (setq amb-count (1+ amb-count)))) (when (>= amb-count 3) (unless (member "Verify AMBIGUOUS graph edges — some connections may be wrong" questions) (push "Verify AMBIGUOUS graph edges — some connections may be wrong" questions))))) graph)
      ;; God nodes with many INFERRED edges
      (let ((gn (gptel-auto-workflow--unified-graph-god-nodes 3)))
        (dolist (g gn) (push (format "What is the role of %s:%s (degree=%d) in the architecture?" (caar g) (cdar g) (cdr g)) questions))))
    (nreverse questions)))

(defun gptel-auto-workflow--graph-snapshot (output-file)
  "Save a snapshot of the current graph for later diff comparison.
Writes timestamps + node/edge counts to OUTPUT-FILE."
  (let ((graph (gptel-auto-workflow--unified-graph-ensure)))
    (when graph
      (let ((nc (hash-table-count graph)) (ec 0))
        (maphash (lambda (_k e) (setq ec (+ ec (length (or e ()))))) graph)
        (with-temp-file output-file
          (insert (format ";; graph snapshot — %s\n" (format-time-string "%Y-%m-%dT%H:%M:%S")))
          (insert (format "(nodes . %d)\n" nc))
          (insert (format "(edges . %d)\n" ec)))
        (message "[memory-schema] Graph snapshot saved to %s" output-file)
        t))))

(defun gptel-auto-workflow--graph-diff (snapshot-file)
  "Compare current graph with SNAPSHOT-FILE. Returns diff plist."
  (when (file-exists-p snapshot-file)
    (let* ((graph (gptel-auto-workflow--unified-graph-ensure))
           (nc (if graph (hash-table-count graph) 0))
           (ec 0) (prev-nc 0) (prev-ec 0))
      (when graph (maphash (lambda (_k e) (setq ec (+ ec (length (or e ()))))) graph))
      (with-temp-buffer
        (insert-file-contents snapshot-file)
        (goto-char (point-min))
        (when (re-search-forward "(nodes \\. \\([0-9]+\\))" nil t) (setq prev-nc (string-to-number (match-string 1))))
        (goto-char (point-min))
        (when (re-search-forward "(edges \\. \\([0-9]+\\))" nil t) (setq prev-ec (string-to-number (match-string 1)))))
      (list :nodes-before prev-nc :nodes-after nc :nodes-delta (- nc prev-nc)
            :edges-before prev-ec :edges-after ec :edges-delta (- ec prev-ec)
            :drift-pct (if (> prev-nc 0) (* 100 (/ (float (abs (- nc prev-nc))) prev-nc)) 0)))))

(defun gptel-auto-workflow--graph-query-feedback (query result)
  "Save a graph query and its result as a mementum memory for future synthesis.
The feedback loop: what the system asks about gets incorporated into
knowledge."
  (let* ((root (gptel-auto-workflow-self-audit--root))
         (mem-file (expand-file-name
                    (format "mementum/memories/graph-query-%s.md"
                            (format-time-string "%Y%m%dT%H%M%S"))
                    root)))
    (with-temp-file mem-file
      (insert "---\ntitle: Graph Query Feedback\ncategory: graph-query\n---\n\n")
      (insert (format "**Query:** %s\n\n**Result:** %s\n" query result)))
    (message "[memory-schema] Query feedback saved to %s" mem-file)))

(provide 'gptel-auto-workflow-memory-schema)
