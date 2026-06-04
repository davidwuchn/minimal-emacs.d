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
  "Ensure hash tables exist, loading from disk if not yet initialized."
  (unless gptel-auto-workflow--memory-schema-schemas
    (gptel-auto-workflow--memory-schema-load-index)))

(defun gptel-auto-workflow--memory-schema-reset ()
  "Reset in-memory schema index to empty."
  (setq gptel-auto-workflow--memory-schema-schemas
        (gptel-auto-workflow--memory-schema-make-schemas))
  (setq gptel-auto-workflow--memory-schema-entities
        (gptel-auto-workflow--memory-schema-make-entities))
  (setq gptel-auto-workflow--memory-schema-triples
        (gptel-auto-workflow--memory-schema-make-triples)))

;; ─── Triple Extraction ───

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
               (after-verb (substring line verb-end)))
          (when (string-match "\\(?:for\\|in\\|on\\|of\\|to\\) +\\(.+\\)"
                              after-verb)
            (push (list :subject (string-trim before-verb)
                        :predicate (string-trim verb)
                        :object (string-trim (match-string 1 after-verb))
                        :subject-type nil
                        :object-type nil)
                  triples))))))
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
    (gptel-auto-workflow--memory-schema-save-index)
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
  "Look up category for TARGET using schema index.
Returns a keyword (:programming, :tool-calls, :agentic,
:natural-language) or nil if no entity matches.
Uses IDF-weighted ranking to penalize generic entities."
  (gptel-auto-workflow--memory-schema-ensure-loaded)
  (let* ((basename (file-name-nondirectory target))
         (total (hash-table-count gptel-auto-workflow--memory-schema-entities))
         (matches nil))
    (maphash (lambda (name count-sources)
               (when (string-match-p (regexp-quote name) basename)
                 (push (cons name
                             (gptel-auto-workflow--memory-schema-entity-idf
                              name count-sources total))
                       matches)))
             gptel-auto-workflow--memory-schema-entities)
    (when matches
      (let* ((sorted (cl-sort matches #'> :key #'cdr))
             (entity (car (car sorted))))
        (cond
         ((string-match-p "\\(?:agent\\|workflow\\|evolution\\|strategy\\)" entity) :agentic)
         ((string-match-p "\\(?:tool\\|bash\\|grep\\|edit\\)" entity) :tool-calls)
         ((string-match-p "\\(?:context\\|prompt\\|stream\\)" entity) :natural-language)
         (t :programming))))))

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
  "Return entities connected to ENTITY via shared schemas.
Each neighbor is (ENTITY-NAME . SHARED-SCHEMA-COUNT).
Walks the triple store to find entities in the same schemas."
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
    (let ((slug (file-name-sans-extension basename)))
      (when (fboundp 'gptel-auto-workflow--memory-schema-files-for-memory)
        (ignore-errors
          (let ((code-links (gptel-auto-workflow--memory-schema-files-for-memory slug)))
            (when code-links
              (push (concat "## Code References\n\n"
                            (mapconcat (lambda (s) (format "- @memory:%s" s))
                                       (seq-take code-links 5) "\n"))
                     parts))))))
    (when parts
      (let ((result (mapconcat #'identity (nreverse parts) "\n\n")))
        (if (> (length result) max-len)
            (concat (substring result 0 (- max-len 3)) "...")
          result)))))

;; ─── Persistence ───

(defun gptel-auto-workflow--memory-schema-persist ()
  "Save current schema index to disk."
  (when gptel-auto-workflow--memory-schema-schemas
    (gptel-auto-workflow--memory-schema-save-index)))

(provide 'gptel-auto-workflow-memory-schema)
