;;; gptel-auto-workflow-skill-graph.el --- Skill graph data structures for OV5 -*- lexical-binding: t; -*-

;; Copyright (C) 2024-2026  Self-Evolving Emacs Project

;; Author: Self-Evolving System
;; Keywords: skill, graph, ontology, workflow

;;; Commentary:

;; Three-layer skill graph for OV5:
;;   Atoms     — Single focused capabilities (~99% reliability)
;;   Molecules — Hardcoded atom sequences ≤10 atoms (~90% reliability)
;;   Compounds — Human-driven workflows ≤10 molecules (~70% reliability)
;;
;; Design-time compilation: graph traversal suggests molecules,
;; runtime uses hardcoded molecules (no traversal, no depth fragility).

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'seq)

;; ─── Data Structures ───

(cl-defstruct (skill-graph-node (:constructor skill-graph-node-create)
                            (:copier nil))
  "Skill graph node representing a single skill."
  id           ; symbol: skill name (e.g., 'hashline-edit)
  level        ; atom | molecule | compound
  path         ; file path to SKILL.md
  metadata     ; alist from frontmatter
  stats        ; plist: :usage-count :success-rate :last-used
  )

(cl-defstruct (skill-graph-edge (:constructor skill-graph-edge-create)
                            (:copier nil))
  "Skill graph edge representing co-occurrence or sequence."
  from         ; node id
  to           ; node id
  weight       ; float: co-occurrence strength (0.0–1.0)
  type         ; sequence | co-occurrence | dependency
  stats        ; plist: :success-count :total-count :last-used
  )

;; ─── Global State ───

(defvar skill-graph--nodes (make-hash-table :test 'eq)
  "Hash table: skill-id → skill-graph-node.
Nodes are loaded from assistant/skills/*/SKILL.md frontmatter.
Keys are symbols (e.g., 'hashline-edit).")

(defvar skill-graph--edges (make-hash-table :test 'equal)
  "Hash table: (from-id . to-id) → skill-graph-edge.
Edges are discovered from AutoTTS traces (skill co-occurrence).")

(defvar skill-graph--molecules nil
  "List of known molecules: each is a list of node ids in sequence.
Molecules are compiled at design time, not traversed at runtime.
Example: ('elisp-discover 'elisp-expert 'elisp-validator).")

;; ─── Skill Loading ───

(defun skill-graph--parse-frontmatter (content)
  "Parse YAML frontmatter from SKILL.md CONTENT.
Returns alist of key-value pairs.
Handles list values like: atoms: [elisp-expert, elisp-validator]"
  (let ((result nil))
    (dolist (line (split-string content "\n"))
      (cond
       ((string-match "^\\([a-z-]+\\):\\s-*\\[\\(.*\\)\\]\\s-*$" line)
        (let ((key (intern (match-string 1 line)))
              (vals-str (match-string 2 line))
              (vals nil))
          (dolist (v (split-string vals-str ",\\s-*"))
            (push (intern (string-trim v)) vals))
          (push (cons key (nreverse vals)) result)))
       ((string-match "^\\([a-z-]+\\):\\s-*\\(.+\\)$" line)
        (let ((key (intern (match-string 1 line)))
              (val (string-trim (match-string 2 line))))
          (when (and (>= (length val) 2)
                     (or (and (eq (aref val 0) ?\")
                              (eq (aref val (1- (length val))) ?\"))
                         (and (eq (aref val 0) ?')
                              (eq (aref val (1- (length val))) ?'))))
            (setq val (substring val 1 -1)))
          (push (cons key val) result)))))
    result))

(defun skill-graph--load-skill (skill-dir)
  "Load a single skill from SKILL-DIR into the graph.
Returns the node id (symbol) or nil if invalid."
  (let ((skill-file (expand-file-name "SKILL.md" skill-dir)))
    (when (file-exists-p skill-file)
      (let* ((content (with-temp-buffer
                        (insert-file-contents skill-file)
                        (buffer-string)))
             (frontmatter (skill-graph--parse-frontmatter content))
             (name (cdr (assoc 'name frontmatter)))
             (level (cdr (assoc 'level frontmatter)))
             (atoms (cdr (assoc 'atoms frontmatter)))
             (molecules (cdr (assoc 'molecules frontmatter)))
             (id (and name (intern name))))
        (when id
          (let* ((node (skill-graph-node-create
                       :id id
                       :level (or (and level (intern level)) 'unknown)
                       :path skill-file
                       :metadata frontmatter
                       :stats (list :usage-count 0
                                    :success-rate 0.0
                                    :last-used nil))))
            (puthash id node skill-graph--nodes)
            (dolist (atom-id atoms)
              (unless (gethash (cons atom-id id) skill-graph--edges)
                (skill-graph--update-edge atom-id id 'dependency nil)))
            (dolist (mol-id molecules)
              (unless (gethash (cons mol-id id) skill-graph--edges)
                (skill-graph--update-edge mol-id id 'dependency nil)))
            (when (and atoms
                       (eq (skill-graph-node-level node) 'molecule))
              (push atoms skill-graph--molecules))
            id))))))

(defun skill-graph-load-all-skills (&optional skills-dir)
  "Load all skills from SKILLS-DIR (default: assistant/skills/).
Returns list of loaded node ids."
  (let* ((root (or (and (boundp 'gptel-auto-workflow--project-root)
                        (fboundp 'gptel-auto-workflow--project-root)
                        (gptel-auto-workflow--project-root))
                   user-emacs-directory))
         (dir (or skills-dir
                  (expand-file-name "assistant/skills" root)))
         (loaded nil))
    (clrhash skill-graph--nodes)
    (dolist (subdir (directory-files dir t "^[^.]"))
      (when (file-directory-p subdir)
        (let ((id (skill-graph--load-skill subdir)))
          (when id
            (push id loaded)))))
    (message "[skill-graph] Loaded %d skills from %s"
             (length loaded) dir)
    loaded))

;; ─── Graph Traversal (Design-Time Only) ───

(defun skill-graph-neighbors (node-id &optional edge-type)
  "Return list of neighbor node ids connected to NODE-ID.
If EDGE-TYPE is specified, only return edges of that type.
Design-time only — runtime uses hardcoded molecules."
  (let ((neighbors nil))
    (maphash (lambda (key edge)
               (when (and (eq (car key) node-id)
                          (or (null edge-type)
                              (eq (skill-graph-edge-type edge) edge-type)))
                 (push (skill-graph-edge-to edge) neighbors)))
             skill-graph--edges)
    (delete-dups neighbors)))

(defun skill-graph--edge-weight (from-id to-id)
  "Return weight of edge FROM-ID → TO-ID, or 0.0 if no edge."
  (let ((edge (gethash (cons from-id to-id) skill-graph--edges)))
    (if edge (skill-graph-edge-weight edge) 0.0)))

;; ─── Edge Management ───

(defun skill-graph--update-edge (from-id to-id type success)
  "Update edge FROM-ID → TO-ID with new outcome.
SUCCESS is t if the skill combination succeeded, nil otherwise.
Weights reinforce on success (+0.05), decay on failure (*0.99)."
  (let* ((key (cons from-id to-id))
         (edge (gethash key skill-graph--edges))
         (stats (and edge (skill-graph-edge-stats edge))))
    (if edge
        ;; Update existing edge
        (let* ((success-count (or (plist-get stats :success-count) 0))
               (total-count (or (plist-get stats :total-count) 0))
               (weight (skill-graph-edge-weight edge))
               (new-total (1+ total-count))
               (new-success (if success (1+ success-count) success-count))
               (new-weight (if success
                              (min 1.0 (+ weight 0.05))
                            (* weight 0.99))))
          (setf (skill-graph-edge-weight edge) new-weight)
          (setf (skill-graph-edge-stats edge)
                (list :success-count new-success
                      :total-count new-total
                      :last-used (float-time))))
      ;; Create new edge
      (puthash key
               (skill-graph-edge-create
                :from from-id
                :to to-id
                :weight (if success 0.5 0.1)
                :type type
                :stats (list :success-count (if success 1 0)
                            :total-count 1
                            :last-used (float-time)))
               skill-graph--edges))))

;; ─── Molecule Compilation (Design-Time) ───

(defun skill-graph--compile-molecule (goal &optional max-atoms)
  "Compile a molecule for GOAL using greedy graph traversal.
Returns list of atom node ids, or nil if no path found.
MAX-ATOMS: maximum atoms in molecule (default: 10).
Design-time only — runtime uses hardcoded molecules.

Algorithm:
1. Find best starting atom (highest success rate matching GOAL)
2. Greedily follow highest-weight edge to next unvisited atom
3. Stop when MAX-ATOMS reached or no edges > 0.1"
  (let* ((max-len (or max-atoms 10))
         (visited (make-hash-table :test 'eq))
         (path nil)
         ;; Find starting atom: highest success rate among atoms
         (start (let ((best nil)
                      (best-score 0.0))
                  (maphash (lambda (id node)
                             (when (eq (skill-graph-node-level node) 'atom)
                               (let* ((stats (skill-graph-node-stats node))
                                      (rate (or (plist-get stats :success-rate) 0.0))
                                      (name (symbol-name id))
                                      ;; Boost if name matches goal keywords
                                      (match-boost (if (and goal
                                                            (string-match-p
                                                             (regexp-quote (downcase name))
                                                             (downcase goal)))
                                                       0.3
                                                     0.0))
                                      (score (+ rate match-boost)))
                                 (when (> score best-score)
                                   (setq best id
                                         best-score score)))))
                           skill-graph--nodes)
                  best)))
    (when start
      (setq path (list start))
      (puthash start t visited)
      ;; Greedily extend path, preferring dependency edges
      (cl-loop repeat (1- max-len)
               do (let* ((current (car path))
                         (best-next nil)
                         (best-score 0.0))
                    (maphash (lambda (key edge)
                               (when (and (eq (car key) current)
                                          (not (gethash (cdr key) visited))
                                          (eq (skill-graph-node-level
                                               (gethash (cdr key) skill-graph--nodes))
                                              'atom))
                                 (let* ((w (skill-graph-edge-weight edge))
                                        ;; Boost dependency edges (explicit frontmatter)
                                        (dep-boost (if (eq (skill-graph-edge-type edge) 'dependency)
                                                       0.5 0.0))
                                        (score (+ w dep-boost)))
                                   (when (> score best-score)
                                     (setq best-next (cdr key)
                                           best-score score)))))
                             skill-graph--edges)
                    (if (and best-next (> best-score 0.1))
                        (progn
                          (push best-next path)
                          (puthash best-next t visited))
                      (cl-return))))
      ;; Return path in forward order
      (nreverse path))))

;; ─── Molecule Validation ───

(defun skill-graph--validate-molecule (molecule)
  "Validate a MOLECULE (list of atom ids) against constraints.
Returns plist: :valid t|nil, :errors (list of strings)."
  (let ((errors nil))
    ;; Constraint 1: max 10 atoms per molecule
    (when (> (length molecule) 10)
      (push (format "Too many atoms: %d > 10" (length molecule)) errors))
    ;; Constraint 2: all must be known atoms
    (dolist (id molecule)
      (let ((node (gethash id skill-graph--nodes)))
        (unless node
          (push (format "Unknown skill: %s" id) errors))
        (when (and node (not (eq (skill-graph-node-level node) 'atom)))
          (push (format "Not an atom: %s (level=%s)" id (skill-graph-node-level node)) errors))))
    ;; Constraint 3: no duplicates
    (let ((seen (make-hash-table :test 'eq)))
      (dolist (id molecule)
        (when (gethash id seen)
          (push (format "Duplicate atom: %s" id) errors))
        (puthash id t seen)))
    ;; Constraint 4: consecutive edges should exist
    (when (>= (length molecule) 2)
      (cl-loop for (a b) on molecule by #'cdr
               while b
               do (let ((w (skill-graph--edge-weight a b)))
                    (when (< w 0.05)
                      (push (format "Weak edge %s→%s (weight=%.3f)" a b w) errors)))))
    (list :valid (null errors)
          :errors (nreverse errors)
          :length (length molecule))))

;; ─── Molecule Execution ───

(defun skill-graph--execute-molecule (molecule fn &optional context)
  "Execute a MOLECULE (list of atom ids) by calling FN for each atom.
FN is called with (atom-id node context) and should return modified context.
Returns plist: :success t|nil, :results list, :context final value."
  (let* ((validation (skill-graph--validate-molecule molecule))
         (results nil)
         (ctx context))
    (if (not (plist-get validation :valid))
        (list :success nil
              :results results
              :context ctx
              :errors (plist-get validation :errors))
      (progn
        (dolist (id molecule)
          (let* ((node (gethash id skill-graph--nodes))
                 (result (condition-case err
                             (funcall fn id node ctx)
                           (error (list :error (error-message-string err))))))
            (push (cons id result) results)
            (when (and (listp result) (not (plist-get result :error)))
              (setq ctx result))
            (let* ((stats (skill-graph-node-stats node))
                   (usage (or (plist-get stats :usage-count) 0)))
              (setf (skill-graph-node-stats node)
                    (plist-put (plist-put stats :usage-count (1+ usage))
                              :last-used (float-time))))))
        (list :success t
              :results (nreverse results)
              :context ctx
              :validation validation)))))

;; ─── AutoTTS Integration ───

(defun skill-graph--record-experiment-skills (skills outcome)
  "Record skill combination from an experiment.
SKILLS is list of skill ids used in sequence.
OUTCOME is t for kept, nil for discarded.
Updates edge weights between consecutive skills.
Preserves dependency edge type (explicit frontmatter) on updates."
  (when (>= (length skills) 2)
    (let ((prev (car skills))
          (rest (cdr skills)))
      (dolist (next rest)
        ;; Check if a dependency edge already exists for this pair
        (let* ((key (cons prev next))
               (existing (gethash key skill-graph--edges))
               (existing-type (and existing (skill-graph-edge-type existing))))
          ;; Use dependency if it exists, otherwise sequence
          (skill-graph--update-edge prev next
                               (if (eq existing-type 'dependency)
                                   'dependency 'sequence)
                               outcome))
        (setq prev next))))
  ;; Update individual node stats
  (dolist (skill-id skills)
    (let ((node (gethash skill-id skill-graph--nodes)))
      (when node
        (let* ((stats (skill-graph-node-stats node))
               (usage (or (plist-get stats :usage-count) 0))
               (success (or (plist-get stats :success-rate) 0.0))
               (total (or (plist-get stats :total-count) 0))
               (new-total (1+ total))
               (new-success (if outcome
                               (/ (+ (* success total) 1.0) new-total)
                             (/ (* success total) new-total))))
          (setf (skill-graph-node-stats node)
                (list :usage-count (1+ usage)
                      :success-rate new-success
                      :total-count new-total
                      :last-used (float-time))))))))

;; ─── Molecule Recommendation ───

(defvar skill-graph--standard-workflows
  '((:name "elisp-workflow"
     :atoms (elisp-discover elisp-expert elisp-validator)
     :category :programming
     :patterns ("\\.el\\'")
     :description "Read→Understand→Write→Validate workflow for Elisp editing")
    (:name "clojure-workflow"
     :atoms (clojure-expert)
     :category :programming
     :patterns ("\\.clj\\'" "\\.cljs\\'" "\\.cljc\\'")
     :description "REPL-first workflow for Clojure editing")
    (:name "debug-workflow"
     :atoms (elisp-debug elisp-validator)
     :category :agentic
     :patterns ()
     :description "Debug→Validate workflow for fixing errors"))
  "Pre-compiled workflow molecules.
Each is a plist with :name, :atoms, :category (matching ontology), :description.
Used as fallback when graph edges are cold (no experiment data).")

(defun skill-graph--recommend-molecule (target &optional category)
  "Recommend a molecule for TARGET based on skill graph and ontology CATEGORY.
Returns list of atom ids, or nil if no recommendation.
PRIORITY: 1) compiled from graph edges, 2) standard workflow match, 3) nil."
  (unless category
    (setq category (and target
                        (fboundp 'gptel-auto-workflow--categorize-target)
                        (gptel-auto-workflow--categorize-target target))))
  (or
   ;; 1) Match standard workflow by category (fast, deterministic)
   (let ((best nil) (best-score 0))
     (dolist (wf skill-graph--standard-workflows)
       (let* ((cat-match (if (and category
                                  (eq (plist-get wf :category) category))
                             1.0 0.0))
              (ext-match (if (and target
                                  (cl-some (lambda (pat)
                                             (string-match-p pat target))
                                           (plist-get wf :patterns)))
                             1.0 0.0))
              (score (+ cat-match ext-match)))
         (when (> score best-score)
           (setq best (plist-get wf :atoms)
                 best-score score))))
     (and best (> best-score 0) best))
   ;; 2) Compile from graph edges (slower, experiment-learned weights)
   (condition-case nil
       (let ((mol (skill-graph--compile-molecule target)))
         (and mol (> (length mol) 0) mol))
     (error nil))))

;; ─── Persistence ───

(defun skill-graph--persist-path ()
  "Return path to skill graph persistence file."
  (let ((root (or (and (boundp 'gptel-auto-workflow--project-root)
                       (fboundp 'gptel-auto-workflow--project-root)
                       (gptel-auto-workflow--project-root))
                  user-emacs-directory)))
    (expand-file-name "var/tmp/skill-graph.eld" root)))

(defun skill-graph--serialize ()
  "Serialize skill graph to a Lisp-readable form.
Returns a single expression that can be read back with `read'."
  (let ((nodes nil)
        (edges nil))
    (maphash (lambda (id node)
               (push (list id
                           (skill-graph-node-level node)
                           (skill-graph-node-path node)
                           (skill-graph-node-stats node))
                     nodes))
             skill-graph--nodes)
    (maphash (lambda (key edge)
               (push (list (car key)
                           (cdr key)
                           (skill-graph-edge-weight edge)
                           (skill-graph-edge-type edge)
                           (skill-graph-edge-stats edge))
                     edges))
             skill-graph--edges)
    (list 'skill-graph--restore
          nodes
          edges
          skill-graph--molecules)))

(defun skill-graph--restore (nodes edges molecules)
  "Restore skill graph from serialized data."
  (clrhash skill-graph--nodes)
  (clrhash skill-graph--edges)
  (setq skill-graph--molecules nil)
  (dolist (n nodes)
    (let ((id (car n))
          (level (cadr n))
          (path (caddr n))
          (stats (cadddr n)))
      (puthash id
               (skill-graph-node-create
                :id id
                :level level
                :path path
                :stats stats)
               skill-graph--nodes)))
  (dolist (e edges)
    (let ((from (car e))
          (to (cadr e))
          (weight (caddr e))
          (type (cadddr e))
          (stats (nth 4 e)))
      (puthash (cons from to)
               (skill-graph-edge-create
                :from from
                :to to
                :weight weight
                :type type
                :stats stats)
               skill-graph--edges)))
  (setq skill-graph--molecules molecules))

(defun skill-graph-save ()
  "Save skill graph to file."
  (let ((file (skill-graph--persist-path)))
    (with-temp-file file
      (let ((print-level nil)
            (print-length nil))
        (prin1 (skill-graph--serialize) (current-buffer))))
    (message "[skill-graph] Saved %d nodes, %d edges to %s"
             (hash-table-count skill-graph--nodes)
             (hash-table-count skill-graph--edges)
             file)))

(defun skill-graph-load ()
  "Load skill graph from file."
  (let ((file (skill-graph--persist-path)))
    (when (file-exists-p file)
      (condition-case err
          (let ((data (with-temp-buffer
                        (insert-file-contents file)
                        (read (current-buffer)))))
            (when (and (listp data)
                       (eq (car data) 'skill-graph--restore))
              (apply #'skill-graph--restore (cdr data))
              (message "[skill-graph] Loaded %d nodes, %d edges from %s"
                       (hash-table-count skill-graph--nodes)
                       (hash-table-count skill-graph--edges)
                       file)))
        (error (message "[skill-graph] Load error: %S" err))))))

;; ─── Evolution ───

(defun skill-graph-evolve-from-experiments ()
  "Update skill graph edges from recent experiment outcomes.
Reads experiment results and updates edge weights based on
skill co-occurrence and success/failure."
  (message "[skill-graph] Starting evolution from experiments...")
  (let ((updated 0))
    (when (fboundp 'gptel-auto-workflow--parse-all-results)
      (let ((results (gptel-auto-workflow--parse-all-results)))
        (dolist (r results)
          (let* ((decision (plist-get r :decision))
                 (kept (equal decision "kept"))
                 (skills-str (plist-get r :skills))
                 (skills
                  (when (and skills-str (not (string-empty-p skills-str)))
                    ;; Parse space-separated skill names or hashtags
                    (let ((candidates
                           (mapcar (lambda (s)
                                     (intern (replace-regexp-in-string
                                              "^#" "" (string-trim s))))
                                   (split-string skills-str))))
                      ;; Filter to only known skill nodes
                      (seq-filter (lambda (s) (gethash s skill-graph--nodes))
                                  candidates)))))
            (when (and skills (>= (length skills) 2))
              (skill-graph--record-experiment-skills skills kept)
              (setq updated (1+ updated)))))))
    (message "[skill-graph] Updated %d experiment skill sequences" updated)
    ;; Save updated graph
    (skill-graph-save)))

;; ─── Initialization ───

(defun skill-graph-init ()
  "Initialize skill graph from filesystem.
Loads skills and persisted graph state."
  (skill-graph-load-all-skills)
  (skill-graph-load)
  (message "[skill-graph] Initialized with %d nodes, %d edges"
           (hash-table-count skill-graph--nodes)
           (hash-table-count skill-graph--edges)))

;; Deferred init — called by evolution cycle or live-reload.
;; Not auto-initialized at load time because project-root may not be available yet.
;; Use (skill-graph-init) to explicitly initialize when context is ready.

(provide 'gptel-auto-workflow-skill-graph)
;;; gptel-auto-workflow-skill-graph.el ends here
