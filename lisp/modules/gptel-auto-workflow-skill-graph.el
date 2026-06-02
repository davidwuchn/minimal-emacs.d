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

(cl-defstruct (ov5-sg-node (:constructor ov5-sg-node-create)
                            (:copier nil))
  "Skill graph node representing a single skill."
  id           ; symbol: skill name (e.g., 'hashline-edit)
  level        ; atom | molecule | compound
  path         ; file path to SKILL.md
  metadata     ; alist from frontmatter
  stats        ; plist: :usage-count :success-rate :last-used
  )

(cl-defstruct (ov5-sg-edge (:constructor ov5-sg-edge-create)
                            (:copier nil))
  "Skill graph edge representing co-occurrence or sequence."
  from         ; node id
  to           ; node id
  weight       ; float: co-occurrence strength (0.0–1.0)
  type         ; sequence | co-occurrence | dependency
  stats        ; plist: :success-count :total-count :last-used
  )

;; ─── Global State ───

(defvar ov5-sg--nodes (make-hash-table :test 'eq)
  "Hash table: skill-id → ov5-sg-node.
Nodes are loaded from assistant/skills/*/SKILL.md frontmatter.
Keys are symbols (e.g., 'hashline-edit).")

(defvar ov5-sg--edges (make-hash-table :test 'equal)
  "Hash table: (from-id . to-id) → ov5-sg-edge.
Edges are discovered from AutoTTS traces (skill co-occurrence).")

(defvar ov5-sg--molecules nil
  "List of known molecules: each is a list of node ids in sequence.
Molecules are compiled at design time, not traversed at runtime.
Example: ('elisp-discover 'elisp-expert 'elisp-validator).")

;; ─── Skill Loading ───

(defun ov5-sg--parse-frontmatter (content)
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

(defun ov5-sg--load-skill (skill-dir)
  "Load a single skill from SKILL-DIR into the graph.
Returns the node id (symbol) or nil if invalid."
  (let ((skill-file (expand-file-name "SKILL.md" skill-dir)))
    (when (file-exists-p skill-file)
      (let* ((content (with-temp-buffer
                        (insert-file-contents skill-file)
                        (buffer-string)))
             (frontmatter (ov5-sg--parse-frontmatter content))
             (name (cdr (assoc 'name frontmatter)))
             (level (cdr (assoc 'level frontmatter)))
             (atoms (cdr (assoc 'atoms frontmatter)))
             (molecules (cdr (assoc 'molecules frontmatter)))
             (id (and name (intern name))))
        (when id
          (let* ((node (ov5-sg-node-create
                       :id id
                       :level (or (and level (intern level)) 'unknown)
                       :path skill-file
                       :metadata frontmatter
                       :stats (list :usage-count 0
                                    :success-rate 0.0
                                    :last-used nil))))
            (puthash id node ov5-sg--nodes)
            (dolist (atom-id atoms)
              (unless (gethash (cons atom-id id) ov5-sg--edges)
                (ov5-sg--update-edge atom-id id 'dependency nil)))
            (dolist (mol-id molecules)
              (unless (gethash (cons mol-id id) ov5-sg--edges)
                (ov5-sg--update-edge mol-id id 'dependency nil)))
            (when (and atoms
                       (eq (ov5-sg-node-level node) 'molecule))
              (push atoms ov5-sg--molecules))
            id))))))

(defun ov5-sg-load-all-skills (&optional skills-dir)
  "Load all skills from SKILLS-DIR (default: assistant/skills/).
Returns list of loaded node ids."
  (let* ((root (or (and (boundp 'gptel-auto-workflow--project-root)
                        (fboundp 'gptel-auto-workflow--project-root)
                        (gptel-auto-workflow--project-root))
                   user-emacs-directory))
         (dir (or skills-dir
                  (expand-file-name "assistant/skills" root)))
         (loaded nil))
    (clrhash ov5-sg--nodes)
    (dolist (subdir (directory-files dir t "^[^.]"))
      (when (file-directory-p subdir)
        (let ((id (ov5-sg--load-skill subdir)))
          (when id
            (push id loaded)))))
    (message "[skill-graph] Loaded %d skills from %s"
             (length loaded) dir)
    loaded))

;; ─── Graph Traversal (Design-Time Only) ───

(defun ov5-sg-neighbors (node-id &optional edge-type)
  "Return list of neighbor node ids connected to NODE-ID.
If EDGE-TYPE is specified, only return edges of that type.
Design-time only — runtime uses hardcoded molecules."
  (let ((neighbors nil))
    (maphash (lambda (key edge)
               (when (and (eq (car key) node-id)
                          (or (null edge-type)
                              (eq (ov5-sg-edge-type edge) edge-type)))
                 (push (ov5-sg-edge-to edge) neighbors)))
             ov5-sg--edges)
    (delete-dups neighbors)))

(defun ov5-sg--edge-weight (from-id to-id)
  "Return weight of edge FROM-ID → TO-ID, or 0.0 if no edge."
  (let ((edge (gethash (cons from-id to-id) ov5-sg--edges)))
    (if edge (ov5-sg-edge-weight edge) 0.0)))

;; ─── Edge Management ───

(defun ov5-sg--update-edge (from-id to-id type success)
  "Update edge FROM-ID → TO-ID with new outcome.
SUCCESS is t if the skill combination succeeded, nil otherwise.
Weights reinforce on success (+0.05), decay on failure (*0.99)."
  (let* ((key (cons from-id to-id))
         (edge (gethash key ov5-sg--edges))
         (stats (and edge (ov5-sg-edge-stats edge))))
    (if edge
        ;; Update existing edge
        (let* ((success-count (or (plist-get stats :success-count) 0))
               (total-count (or (plist-get stats :total-count) 0))
               (weight (ov5-sg-edge-weight edge))
               (new-total (1+ total-count))
               (new-success (if success (1+ success-count) success-count))
               (new-weight (if success
                              (min 1.0 (+ weight 0.05))
                            (* weight 0.99))))
          (setf (ov5-sg-edge-weight edge) new-weight)
          (setf (ov5-sg-edge-stats edge)
                (list :success-count new-success
                      :total-count new-total
                      :last-used (float-time))))
      ;; Create new edge
      (puthash key
               (ov5-sg-edge-create
                :from from-id
                :to to-id
                :weight (if success 0.5 0.1)
                :type type
                :stats (list :success-count (if success 1 0)
                            :total-count 1
                            :last-used (float-time)))
               ov5-sg--edges))))

;; ─── Molecule Compilation (Design-Time) ───

(defun ov5-sg--compile-molecule (goal &optional max-atoms)
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
                             (when (eq (ov5-sg-node-level node) 'atom)
                               (let* ((stats (ov5-sg-node-stats node))
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
                           ov5-sg--nodes)
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
                                          (eq (ov5-sg-node-level
                                               (gethash (cdr key) ov5-sg--nodes))
                                              'atom))
                                 (let* ((w (ov5-sg-edge-weight edge))
                                        ;; Boost dependency edges (explicit frontmatter)
                                        (dep-boost (if (eq (ov5-sg-edge-type edge) 'dependency)
                                                       0.5 0.0))
                                        (score (+ w dep-boost)))
                                   (when (> score best-score)
                                     (setq best-next (cdr key)
                                           best-score score)))))
                             ov5-sg--edges)
                    (if (and best-next (> best-score 0.1))
                        (progn
                          (push best-next path)
                          (puthash best-next t visited))
                      (cl-return))))
      ;; Return path in forward order
      (nreverse path))))

;; ─── Molecule Validation ───

(defun ov5-sg--validate-molecule (molecule)
  "Validate a MOLECULE (list of atom ids) against constraints.
Returns plist: :valid t|nil, :errors (list of strings)."
  (let ((errors nil))
    ;; Constraint 1: max 10 atoms per molecule
    (when (> (length molecule) 10)
      (push (format "Too many atoms: %d > 10" (length molecule)) errors))
    ;; Constraint 2: all must be known atoms
    (dolist (id molecule)
      (let ((node (gethash id ov5-sg--nodes)))
        (unless node
          (push (format "Unknown skill: %s" id) errors))
        (when (and node (not (eq (ov5-sg-node-level node) 'atom)))
          (push (format "Not an atom: %s (level=%s)" id (ov5-sg-node-level node)) errors))))
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
               do (let ((w (ov5-sg--edge-weight a b)))
                    (when (< w 0.05)
                      (push (format "Weak edge %s→%s (weight=%.3f)" a b w) errors)))))
    (list :valid (null errors)
          :errors (nreverse errors)
          :length (length molecule))))

;; ─── Molecule Execution ───

(defun ov5-sg--execute-molecule (molecule fn &optional context)
  "Execute a MOLECULE (list of atom ids) by calling FN for each atom.
FN is called with (atom-id node context) and should return modified context.
Returns plist: :success t|nil, :results list, :context final value."
  (let* ((validation (ov5-sg--validate-molecule molecule))
         (results nil)
         (ctx context))
    (if (not (plist-get validation :valid))
        (list :success nil
              :results results
              :context ctx
              :errors (plist-get validation :errors))
      (progn
        (dolist (id molecule)
          (let* ((node (gethash id ov5-sg--nodes))
                 (result (condition-case err
                             (funcall fn id node ctx)
                           (error (list :error (error-message-string err))))))
            (push (cons id result) results)
            (when (and (listp result) (not (plist-get result :error)))
              (setq ctx result))
            (let* ((stats (ov5-sg-node-stats node))
                   (usage (or (plist-get stats :usage-count) 0)))
              (setf (ov5-sg-node-stats node)
                    (plist-put (plist-put stats :usage-count (1+ usage))
                              :last-used (float-time))))))
        (list :success t
              :results (nreverse results)
              :context ctx
              :validation validation)))))

;; ─── AutoTTS Integration ───

(defun ov5-sg--record-experiment-skills (skills outcome)
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
               (existing (gethash key ov5-sg--edges))
               (existing-type (and existing (ov5-sg-edge-type existing))))
          ;; Use dependency if it exists, otherwise sequence
          (ov5-sg--update-edge prev next
                               (if (eq existing-type 'dependency)
                                   'dependency 'sequence)
                               outcome))
        (setq prev next))))
  ;; Update individual node stats
  (dolist (skill-id skills)
    (let ((node (gethash skill-id ov5-sg--nodes)))
      (when node
        (let* ((stats (ov5-sg-node-stats node))
               (usage (or (plist-get stats :usage-count) 0))
               (success (or (plist-get stats :success-rate) 0.0))
               (total (or (plist-get stats :total-count) 0))
               (new-total (1+ total))
               (new-success (if outcome
                               (/ (+ (* success total) 1.0) new-total)
                             (/ (* success total) new-total))))
          (setf (ov5-sg-node-stats node)
                (list :usage-count (1+ usage)
                      :success-rate new-success
                      :total-count new-total
                      :last-used (float-time))))))))

;; ─── Persistence ───

(defun ov5-sg--persist-path ()
  "Return path to skill graph persistence file."
  (let ((root (or (and (boundp 'gptel-auto-workflow--project-root)
                       (fboundp 'gptel-auto-workflow--project-root)
                       (gptel-auto-workflow--project-root))
                  user-emacs-directory)))
    (expand-file-name "var/tmp/skill-graph.eld" root)))

(defun ov5-sg--serialize ()
  "Serialize skill graph to a Lisp-readable form.
Returns a single expression that can be read back with `read'."
  (let ((nodes nil)
        (edges nil))
    (maphash (lambda (id node)
               (push (list id
                           (ov5-sg-node-level node)
                           (ov5-sg-node-path node)
                           (ov5-sg-node-stats node))
                     nodes))
             ov5-sg--nodes)
    (maphash (lambda (key edge)
               (push (list (car key)
                           (cdr key)
                           (ov5-sg-edge-weight edge)
                           (ov5-sg-edge-type edge)
                           (ov5-sg-edge-stats edge))
                     edges))
             ov5-sg--edges)
    (list 'ov5-sg--restore
          nodes
          edges
          ov5-sg--molecules)))

(defun ov5-sg--restore (nodes edges molecules)
  "Restore skill graph from serialized data."
  (clrhash ov5-sg--nodes)
  (clrhash ov5-sg--edges)
  (setq ov5-sg--molecules nil)
  (dolist (n nodes)
    (let ((id (car n))
          (level (cadr n))
          (path (caddr n))
          (stats (cadddr n)))
      (puthash id
               (ov5-sg-node-create
                :id id
                :level level
                :path path
                :stats stats)
               ov5-sg--nodes)))
  (dolist (e edges)
    (let ((from (car e))
          (to (cadr e))
          (weight (caddr e))
          (type (cadddr e))
          (stats (nth 4 e)))
      (puthash (cons from to)
               (ov5-sg-edge-create
                :from from
                :to to
                :weight weight
                :type type
                :stats stats)
               ov5-sg--edges)))
  (setq ov5-sg--molecules molecules))

(defun ov5-sg-save ()
  "Save skill graph to file."
  (let ((file (ov5-sg--persist-path)))
    (with-temp-file file
      (let ((print-level nil)
            (print-length nil))
        (prin1 (ov5-sg--serialize) (current-buffer))))
    (message "[skill-graph] Saved %d nodes, %d edges to %s"
             (hash-table-count ov5-sg--nodes)
             (hash-table-count ov5-sg--edges)
             file)))

(defun ov5-sg-load ()
  "Load skill graph from file."
  (let ((file (ov5-sg--persist-path)))
    (when (file-exists-p file)
      (condition-case err
          (let ((data (with-temp-buffer
                        (insert-file-contents file)
                        (read (current-buffer)))))
            (when (and (listp data)
                       (eq (car data) 'ov5-sg--restore))
              (apply #'ov5-sg--restore (cdr data))
              (message "[skill-graph] Loaded %d nodes, %d edges from %s"
                       (hash-table-count ov5-sg--nodes)
                       (hash-table-count ov5-sg--edges)
                       file)))
        (error (message "[skill-graph] Load error: %S" err))))))

;; ─── Evolution ───

(defun ov5-sg-evolve-from-experiments ()
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
                      (seq-filter (lambda (s) (gethash s ov5-sg--nodes))
                                  candidates)))))
            (when (and skills (>= (length skills) 2))
              (ov5-sg--record-experiment-skills skills kept)
              (setq updated (1+ updated)))))))
    (message "[skill-graph] Updated %d experiment skill sequences" updated)
    ;; Save updated graph
    (ov5-sg-save)))

;; ─── Initialization ───

(defun ov5-sg-init ()
  "Initialize skill graph from filesystem.
Loads skills and persisted graph state."
  (ov5-sg-load-all-skills)
  (ov5-sg-load)
  (message "[skill-graph] Initialized with %d nodes, %d edges"
           (hash-table-count ov5-sg--nodes)
           (hash-table-count ov5-sg--edges)))

;; Auto-initialize when loaded (safe for daemon — checks directory existence)
(condition-case err
    (let ((root (or (and (boundp 'gptel-auto-workflow--project-root)
                         (fboundp 'gptel-auto-workflow--project-root)
                         (gptel-auto-workflow--project-root))
                    user-emacs-directory)))
      (when (file-directory-p (expand-file-name "assistant/skills" root))
        (ov5-sg-init)))
  (error (message "[skill-graph] Init deferred: %s" (error-message-string err))))

(provide 'gptel-auto-workflow-skill-graph)
;;; gptel-auto-workflow-skill-graph.el ends here
