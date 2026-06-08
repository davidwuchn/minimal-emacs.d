;;; gptel-auto-workflow-knowledge-reasoning.el --- Formal reasoning for OV5 knowledge layer -*- lexical-binding: t; -*-
;;; λ engage(knowledge_reasoning).
;;;   horn_sat ∧ floyd_warshall ∧ allen_intervals ∧ interval_labelling
;;;   | forward_chain ∧ owl_generation | ∀formal: testable ∧ deterministic

(require 'cl-lib)
(require 'json)

;;; ═══════════════════════════════════════════════════════════════
;;; Horn SAT Consistency Checking
;;; ═══════════════════════════════════════════════════════════════
;;; Linear-time Horn clause satisfiability for ontology integrity.
;;; A Horn clause has at most one positive literal.
;;; Forward chaining: if all negative literals are in the model,
;;; add the positive literal. O(n) per clause, O(n*m) total.

(defun gptel-knowledge--horn-clause-p (clause)
  "Return non-nil if CLAUSE is a valid Horn clause.
A Horn clause is a plist with :head (symbol or nil)
and :body (list of symbols).  NIL head means the clause is a
constraint (all body must not be simultaneously true)."
  (and (plistp clause)
       (plist-member clause :body)
       (cl-every #'symbolp (plist-get clause :body))
       (or (null (plist-get clause :head))
           (symbolp (plist-get clause :head)))))

(defun gptel-knowledge--horn-sat-p (clauses)
  "Check if CLAUSES (list of Horn clauses) are satisfiable.
Each clause is (:head SYM :body (SYM ...)).
Returns (SAT . MODEL) where SAT is t/nil and MODEL is a list of true atoms."
  (let ((model nil)
        (changed t))
    (while changed
      (setq changed nil)
      (dolist (clause clauses)
        (let ((head (plist-get clause :head))
              (body (plist-get clause :body)))
          (when (cl-every (lambda (atom) (memq atom model)) body)
            (cond
             ((null head)
              (setq model nil changed nil)
              (dolist (c clauses)
                (when (and (null (plist-get c :head))
                           (cl-every (lambda (a) (memq a model)) (plist-get c :body)))
                  (setq model :unsat)))
              (when (eq model :unsat)
                (cl-return-from gptel-knowledge--horn-sat-p (cons nil nil))))
             ((not (memq head model))
              (push head model)
              (setq changed t)))))))
    (cons t model)))

(defun gptel-knowledge--check-ontology-consistency (ontology-rules)
  "Check ONTOLOGY-RULES for logical contradictions via Horn SAT.
ONTOLOGY-RULES is a list of (:head SYM :body (SYM ...)) plists.
Returns plist with :consistent (bool), :model (list), :conflicts (list)."
  (let* ((result (gptel-knowledge--horn-sat-p ontology-rules))
         (sat (car result))
         (model (cdr result))
         (conflicts nil))
    (when sat
      (dolist (rule ontology-rules)
        (when (null (plist-get rule :head))
          (when (cl-every (lambda (a) (memq a model)) (plist-get rule :body))
            (push (plist-get rule :body) conflicts)))))
    (list :consistent (and sat (null conflicts))
          :model model
          :conflicts conflicts
          :rule-count (length ontology-rules))))

;;; ═══════════════════════════════════════════════════════════════
;;; Floyd-Warshall Causal Chains
;;; ═══════════════════════════════════════════════════════════════
;;; Multi-experiment sequences → root cause via transitive closure.
;;; Nodes are experiments; edges are causal dependencies.
;;; Returns shortest causal path between any two experiments.

(defun gptel-knowledge--floyd-warshall (nodes edges)
  "Compute transitive closure and shortest paths via Floyd-Warshall.
NODES is a list of node identifiers.
EDGES is a list of (:from NODE :to NODE :weight NUM) plists.
Returns plist with :distances (hash: (from . to) → distance)
                       :predecessors (hash: (from . to) → intermediate node)
                       :causal-chains (list of reachable pairs with paths)."
  (let ((dist (make-hash-table :test 'equal))
        (pred (make-hash-table :test 'equal))
        (inf most-positive-fixnum))
    (dolist (i nodes)
      (dolist (j nodes)
        (puthash (cons i j) (if (eq i j) 0 inf) dist)))
    (dolist (e edges)
      (let ((from (plist-get e :from))
            (to (plist-get e :to))
            (w (or (plist-get e :weight) 1)))
        (puthash (cons from to) w dist)
        (puthash (cons from to) from pred)))
    (dolist (k nodes)
      (dolist (i nodes)
        (dolist (j nodes)
          (let* ((ik (gethash (cons i k) dist inf))
                 (kj (gethash (cons k j) dist inf))
                 (ij (gethash (cons i j) dist inf))
                 (via-k (+ ik kj)))
            (when (and (< via-k ij) (< via-k inf))
              (puthash (cons i j) via-k dist)
              (puthash (cons i j) (gethash (cons k j) pred) pred))))))
    (let ((chains nil))
      (dolist (i nodes)
        (dolist (j nodes)
          (unless (or (eq i j) (= (gethash (cons i j) dist inf) inf))
            (push (list :from i :to j
                        :distance (gethash (cons i j) dist inf)
                        :path (gptel-knowledge--reconstruct-path i j pred))
                  chains))))
      (list :distances dist
            :predecessors pred
            :causal-chains (nreverse chains)))))

(defun gptel-knowledge--reconstruct-path (from to pred)
  "Reconstruct shortest path from FROM to TO using PRED hash table."
  (if (not (gethash (cons from to) pred))
      (list from to)
    (let ((path (list to))
          (current to))
      (while (and (not (eq current from))
                  (gethash (cons from current) pred))
        (setq current (gethash (cons from current) pred))
        (push current path))
      (if (eq (car path) from) path (list from to)))))

(defun gptel-knowledge--experiment-causal-graph (results)
  "Build causal graph from RESULTS (list of experiment result plists).
Edges connect experiments on the same target where a later one
references the earlier one's hypothesis or depends on its outcome."
  (let ((nodes nil)
        (edges nil)
        (by-target (make-hash-table :test 'equal)))
    (dolist (r results)
      (let ((target (plist-get r :target))
            (id (plist-get r :id)))
        (push id nodes)
        (push r (gethash target by-target))))
    (maphash
     (lambda (_target experiments)
       (let ((sorted (sort experiments
                           (lambda (a b) (< (or (plist-get a :id) 0)
                                            (or (plist-get b :id) 0))))))
         (cl-loop for i from 0 below (1- (length sorted))
                  for cur = (nth (1+ i) sorted)
                  for prev = (nth i sorted)
                  do (push (list :from (plist-get prev :id)
                                 :to (plist-get cur :id)
                                 :weight 1
                                 :relation (if (equal (plist-get cur :decision) "kept")
                                               :continued :replaced))
                           edges))))
     by-target)
    (cons (nreverse nodes) (nreverse edges))))

;;; ═══════════════════════════════════════════════════════════════
;;; Allen Interval Algebra (13 Relations)
;;; ═══════════════════════════════════════════════════════════════
;;; Temporal relations between experiment time intervals.
;;; Detects gaps and overlaps between experiment sequences.

(defconst gptel-knowledge--allen-relations
  '((before         . (lambda (a b) (< (plist-get a :end) (plist-get b :start))))
    (after          . (lambda (a b) (< (plist-get b :end) (plist-get a :start))))
    (meets          . (lambda (a b) (= (plist-get a :end) (plist-get b :start))))
    (met-by         . (lambda (a b) (= (plist-get b :end) (plist-get a :start))))
    (overlaps       . (lambda (a b) (and (< (plist-get a :start) (plist-get b :start))
                                         (< (plist-get b :start) (plist-get a :end))
                                         (< (plist-get a :end) (plist-get b :end)))))
    (overlapped-by  . (lambda (a b) (and (< (plist-get b :start) (plist-get a :start))
                                         (< (plist-get a :start) (plist-get b :end))
                                         (< (plist-get b :end) (plist-get a :end)))))
    (starts         . (lambda (a b) (and (= (plist-get a :start) (plist-get b :start))
                                         (< (plist-get a :end) (plist-get b :end)))))
    (started-by     . (lambda (a b) (and (= (plist-get a :start) (plist-get b :start))
                                         (< (plist-get b :end) (plist-get a :end)))))
    (during         . (lambda (a b) (and (> (plist-get a :start) (plist-get b :start))
                                         (< (plist-get a :end) (plist-get b :end)))))
    (contains       . (lambda (a b) (and (> (plist-get b :start) (plist-get a :start))
                                         (< (plist-get b :end) (plist-get a :end)))))
    (finishes       . (lambda (a b) (and (< (plist-get a :start) (plist-get b :start))
                                         (= (plist-get a :end) (plist-get b :end)))))
    (finished-by    . (lambda (a b) (and (< (plist-get b :start) (plist-get a :start))
                                         (= (plist-get b :end) (plist-get a :end)))))
    (equals         . (lambda (a b) (and (= (plist-get a :start) (plist-get b :start))
                                         (= (plist-get a :end) (plist-get b :end))))))
  "Allen interval algebra: 13 temporal relations between two intervals.
Each interval is a plist with :start and :end (numeric timestamps).")

(defun gptel-knowledge--allen-classify (interval-a interval-b)
  "Classify the temporal relation between INTERVAL-A and INTERVAL-B.
Returns the symbol naming the Allen relation."
  (cl-loop for (relation . predicate) in gptel-knowledge--allen-relations
           when (funcall predicate interval-a interval-b)
           return relation))

(defun gptel-knowledge--allen-detect-gaps (intervals)
  "Detect temporal gaps in INTERVALS (list of plists with :start/:end).
Returns list of (:gap-start NUM :gap-end NUM :after-id ID :before-id ID)."
  (let* ((sorted (sort (copy-sequence intervals)
                       (lambda (a b) (< (plist-get a :start) (plist-get b :start)))))
         (gaps nil))
    (cl-loop for i from 0 below (1- (length sorted))
             for cur = (nth i sorted)
             for nxt = (nth (1+ i) sorted)
             when (< (plist-get cur :end) (plist-get nxt :start))
             do (push (list :gap-start (plist-get cur :end)
                            :gap-end (plist-get nxt :start)
                            :gap-duration (- (plist-get nxt :start) (plist-get cur :end))
                            :after-id (plist-get cur :id)
                            :before-id (plist-get nxt :id))
                      gaps))
    (nreverse gaps)))

(defun gptel-knowledge--allen-relation-matrix (intervals)
  "Compute pairwise Allen relations for INTERVALS.
Returns alist of ((id-a . id-b) . relation)."
  (let ((matrix nil))
    (dolist (a intervals)
      (dolist (b intervals)
        (unless (eq (plist-get a :id) (plist-get b :id))
          (push (cons (cons (plist-get a :id) (plist-get b :id))
                      (gptel-knowledge--allen-classify a b))
                matrix))))
    matrix))

;;; ═══════════════════════════════════════════════════════════════
;;; Interval Labelling Schema (O(1) Subsumption)
;;; ═══════════════════════════════════════════════════════════════
;;; Preorder/postorder labelling of pattern hierarchy for O(1)
;;; subsumption checks. A pattern P subsumes Q if P's interval
;;; contains Q's interval: pre(P) ≤ pre(Q) ∧ post(Q) ≤ post(P).

(defun gptel-knowledge--build-interval-labels (hierarchy)
  "Build preorder/postorder interval labels for HIERARCHY.
HIERARCHY is a list of (:id SYM :children ((:id SYM :children ...) ...)).
Returns hash table: id → (:pre NUM :post NUM :depth NUM)."
  (let ((labels (make-hash-table :test 'eq))
        (counter 0))
    (cl-labels
        ((traverse (node depth)
           (let ((pre counter))
             (setq counter (1+ counter))
             (dolist (child (plist-get node :children))
               (traverse child (1+ depth)))
             (puthash (plist-get node :id)
                      (list :pre pre :post counter :depth depth)
                      labels)
             (setq counter (1+ counter)))))
      (dolist (root hierarchy)
        (traverse root 0)))
    labels))

(defun gptel-knowledge--subsumes-p (label-table super-pattern sub-pattern)
  "Return t if SUPER-PATTERN subsumes SUB-PATTERN using interval labels.
O(1) check: pre(super) ≤ pre(sub) ∧ post(sub) ≤ post(super)."
  (let ((super-label (gethash super-pattern label-table))
        (sub-label (gethash sub-pattern label-table)))
    (when (and super-label sub-label)
      (and (<= (plist-get super-label :pre) (plist-get sub-label :pre))
           (<= (plist-get sub-label :post) (plist-get super-label :post))))))

(defun gptel-knowledge--find-subsumers (label-table pattern-id)
  "Find all patterns that subsume PATTERN-ID in LABEL-TABLE.
Returns list of pattern ids."
  (let ((sub-label (gethash pattern-id label-table))
        (subsumers nil))
    (when sub-label
      (let ((sub-pre (plist-get sub-label :pre))
            (sub-post (plist-get sub-label :post)))
        (maphash
         (lambda (id label)
           (unless (eq id pattern-id)
             (when (and (<= (plist-get label :pre) sub-pre)
                        (<= sub-post (plist-get label :post)))
               (push id subsumers))))
         label-table)))
    subsumers))

;;; ═══════════════════════════════════════════════════════════════
;;; Forward Chaining (8 Rules) for Experiment Inference
;;; ═══════════════════════════════════════════════════════════════

(defconst gptel-knowledge--forward-chain-rules
  '((:name saturated-target
     :condition (lambda (facts) (>= (or (plist-get facts :experiment-count) 0) 10))
     :action (lambda (facts) (plist-put facts :skip-target t))
     :description "Target with ≥10 experiments → skip (saturated)")
    (:name repeated-failure
     :condition (lambda (facts) (>= (or (plist-get facts :consecutive-failures) 0) 3))
     :action (lambda (facts) (plist-put facts :freeze-category t))
     :description "3+ consecutive failures → freeze category")
    (:name low-confidence-bypass
     :condition (lambda (facts) (< (or (plist-get facts :ema-confidence) 1.0) 0.3))
     :action (lambda (facts) (plist-put facts :bypass-ontology t))
     :description "EMA < 0.3 → bypass ontology, use LLM")
    (:name high-confidence-accept
     :condition (lambda (facts) (> (or (plist-get facts :ema-confidence) 0.0) 0.6))
     :action (lambda (facts) (plist-put facts :accept-weak-picks t))
     :description "EMA > 0.6 → accept weaker ontology picks")
    (:name backend-unhealthy
     :condition (lambda (facts) (>= (or (plist-get facts :health-strikes) 0) 3))
     :action (lambda (facts) (plist-put facts :probation-backend t))
     :description "3+ health strikes → probation backend")
    (:name budget-exhausted
     :condition (lambda (facts) (>= (or (plist-get facts :experiments-this-run) 0)
                                     (or (plist-get facts :max-experiments) 20)))
     :action (lambda (facts) (plist-put facts :stop-experiments t))
     :description "Budget exhausted → stop experiments")
    (:name category-drift
     :condition (lambda (facts) (> (or (plist-get facts :keep-rate-deviation) 0.0) 0.20))
     :action (lambda (facts) (plist-put facts :flag-drift t))
     :description "Keep-rate deviates >20% from baseline → flag drift")
    (:name champion-unchanged
     :condition (lambda (facts) (>= (or (plist-get facts :cycles-since-promotion) 0) 5))
     :action (lambda (facts) (plist-put facts :explore-wider t))
     :description "5+ cycles without promotion → widen exploration"))
  "8 forward-chaining rules for experiment inference.
Each rule: :condition (predicate on facts) → :action (derive new facts).")

(defun gptel-knowledge--forward-chain (initial-facts &optional rules)
  "Apply forward chaining RULES to INITIAL-FACTS until fixed point.
Returns (FACTS . DERIVATIONS) where DERIVATIONS lists which rules fired."
  (let ((facts (copy-sequence initial-facts))
        (derivations nil)
        (changed t)
        (applicable-rules (or rules gptel-knowledge--forward-chain-rules)))
    (while changed
      (setq changed nil)
      (dolist (rule applicable-rules)
        (let ((condition (plist-get rule :condition))
              (action (plist-get rule :action))
              (name (plist-get rule :name)))
          (when (and (functionp condition) (funcall condition facts))
            (let* ((before-keys (cl-loop for k on facts by #'cddr collect (car k)))
                   (new-facts (funcall action facts))
                   (after-keys (cl-loop for k on new-facts by #'cddr collect (car k)))
                   (derived-keys (cl-set-difference after-keys before-keys)))
              (when derived-keys
                (setq facts new-facts
                      changed t)
                (push (list :rule name
                            :derived-keys derived-keys)
                      derivations)))))))
    (cons facts (nreverse derivations))))

;;; ═══════════════════════════════════════════════════════════════
;;; OWL/SHACL Ontology Generation
;;; ═══════════════════════════════════════════════════════════════

(defun gptel-knowledge--generate-owl (classes properties instances)
  "Generate OWL ontology as Turtle-format string.
CLASSES is a list of (:name SYM :parent SYM :doc STRING).
PROPERTIES is a list of (:name SYM :domain SYM :range SYM :type TYPE).
INSTANCES is a list of (:class SYM :id STRING :properties ALIST)."
  (with-temp-buffer
    (insert "@prefix : <http://ov5.dev/ontology#> .\n")
    (insert "@prefix owl: <http://www.w3.org/2002/07/owl#> .\n")
    (insert "@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#> .\n")
    (insert "@prefix sh: <http://www.w3.org/ns/shacl#> .\n")
    (insert "@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .\n\n")
    (insert "[] a owl:Ontology ;\n rdfs:label \"OV5 Experiment Ontology\" ;\n rdfs:comment
\"Auto-generated from experiment data\" .\n\n")
    (dolist (cls classes)
      (insert (format ":%s a owl:Class" (plist-get cls :name)))
      (when (plist-get cls :parent)
        (insert (format " ;\n   rdfs:subClassOf :%s" (plist-get cls :parent))))
      (when (plist-get cls :doc)
        (insert (format " ;\n   rdfs:comment \"%s\"" (plist-get cls :doc))))
      (insert " .\n\n"))
    (dolist (prop properties)
      (insert (format ":%s a owl:%sProperty ;\n   rdfs:domain :%s ;\n   rdfs:range :%s .\n\n"
                      (plist-get prop :name)
                      (if (eq (plist-get prop :type) :datatype) "Datatype" "Object")
                      (plist-get prop :domain)
                      (plist-get prop :range))))
    (dolist (inst instances)
      (insert (format ":%s a :%s" (plist-get inst :id) (plist-get inst :class)))
      (dolist (p (plist-get inst :properties))
        (insert (format " ;\n   :%s %s" (car p)
                        (if (stringp (cdr p))
                            (format "\"%s\"" (cdr p))
                          (format "%s" (cdr p))))))
      (insert " .\n\n"))
    (buffer-string)))

(defun gptel-knowledge--generate-shacl (classes properties)
  "Generate SHACL shapes as Turtle-format string.
Validates instances against the ontology schema."
  (with-temp-buffer
    (insert "@prefix : <http://ov5.dev/ontology#> .\n")
    (insert "@prefix sh: <http://www.w3.org/ns/shacl#> .\n")
    (insert "@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .\n\n")
    (dolist (cls classes)
      (insert (format ":%sShape a sh:NodeShape ;\n   sh:targetClass :%s ;\n"
                      (plist-get cls :name) (plist-get cls :name)))
      (let ((first-prop t))
        (dolist (prop properties)
          (when (eq (plist-get prop :domain) (plist-get cls :name))
            (unless first-prop (insert " ;\n"))
            (insert (format "   sh:property [\n      sh:path :%s ;\n      sh:class :%s ;\n   ]"
                            (plist-get prop :name) (plist-get prop :range)))
            (setq first-prop nil))))
      (insert " .\n\n"))
    (buffer-string)))

(defun gptel-knowledge--ontology-from-experiments (results)
  "Generate OWL ontology + SHACL shapes from experiment RESULTS.
Returns plist with :owl (Turtle string) :shacl (Turtle string) :stats."
  (let* ((categories (delete-dups (mapcar (lambda (r) (or (plist-get r :category) :uncategorized)) results)))
         (targets (delete-dups (mapcar (lambda (r) (plist-get r :target)) results)))
         (strategies (delete-dups (mapcar (lambda (r) (plist-get r :strategy)) results)))
         (classes (append
                   (list (list :name 'Experiment :parent nil :doc "An automated experiment"))
                   (mapcar (lambda (cat) (list :name cat :parent 'Experiment :doc (format "Category %s" cat))) categories)
                   (list (list :name 'Strategy :parent nil :doc "An experiment strategy"))
                   (list (list :name 'Target :parent nil :doc "An experiment target file"))))
         (properties (list
                      (list :name 'hasTarget :domain 'Experiment :range 'Target :type :object)
                      (list :name 'hasStrategy :domain 'Experiment :range 'Strategy :type :object)
                      (list :name 'hasCategory :domain 'Experiment :range 'Experiment :type :object)
                      (list :name 'hasScore :domain 'Experiment :range 'xsd:float :type :datatype)
                      (list :name 'hasDecision :domain 'Experiment :range 'xsd:string :type :datatype)))
         (instances nil)
         (id-counter 0))
    (dolist (r (seq-take results 50))
      (push (list :class (or (plist-get r :category) 'Experiment)
                  :id (format "exp-%d" (cl-incf id-counter))
                  :properties (list (cons 'hasTarget (format "\"%s\"" (or (plist-get r :target) "unknown")))
                                    (cons 'hasStrategy (format "\"%s\"" (or (plist-get r :strategy) "unknown")))
                                    (cons 'hasScore (or (plist-get r :score-after) 0.0))
                                    (cons 'hasDecision (format "\"%s\"" (or (plist-get r :decision) "unknown")))))
            instances))
    (list :owl (gptel-knowledge--generate-owl classes properties instances)
          :shacl (gptel-knowledge--generate-shacl classes properties)
          :stats (list :classes (length classes)
                       :properties (length properties)
                       :instances (length instances)
                       :categories (length categories)
                       :targets (length targets)
                       :strategies (length strategies)))))

;;; ═══════════════════════════════════════════════════════════════
;;; EDN Plist Format (forge-lambda-fixed-point)
;;; ═══════════════════════════════════════════════════════════════
;;; EDN (Extensible Data Notation) plists for deterministic prompt
;;; construction. Zero LLM calls for rendering.

(defun gptel-knowledge--plist-to-edn (plist)
  "Convert PLIST to EDN-format string.
Keywords become :keyword, strings become \"string\", lists become ().
Deterministic — no LLM calls."
  (cond
   ((null plist) "nil")
   ((stringp plist) (format "\"%s\"" plist))
   ((numberp plist) (format "%s" plist))
   ((symbolp plist) (format ":%s" (substring (symbol-name plist) 1)))
   ((keywordp plist) (format ":%s" (substring (symbol-name plist) 1)))
   ((and (consp plist) (not (listp (cdr plist))))
    (format "{%s %s}"
            (gptel-knowledge--plist-to-edn (car plist))
            (gptel-knowledge--plist-to-edn (cdr plist))))
   ((listp plist)
    (if (and plist (keywordp (car plist)))
        (format "{%s}" (mapconcat #'gptel-knowledge--plist-to-edn plist " "))
      (format "[%s]" (mapconcat #'gptel-knowledge--plist-to-edn plist " "))))
   ((vectorp plist) (format "[%s]" (mapconcat #'gptel-knowledge--plist-to-edn (append plist nil) " ")))
   (t (format "%S" plist))))

(defun gptel-knowledge--forge-lambda-fixed-point (prompt-spec context)
  "Resolve PROMPT-SPEC against CONTEXT until fixed point.
PROMPT-SPEC is an EDN plist with {{variable}} placeholders.
CONTEXT is a plist of variable bindings.
Replaces all {{key}} with the value from context.
Deterministic -- zero LLM calls for rendering."
  (let ((result prompt-spec)
        (changed t))
    (while changed
      (setq changed nil)
      (dolist (key (cl-loop for k on context by #'cddr collect (car k)))
        (let ((placeholder (format "{{%s}}" (substring (symbol-name key) 1)))
              (value (plist-get context key)))
          (when (and (stringp result) (stringp value) (string-match-p placeholder result))
            (setq result (replace-regexp-in-string placeholder value result t t)
                  changed t)))))
    result))

;;; ═══════════════════════════════════════════════════════════════
;;; Playout Cap Randomization (80/15/5)
;;; ═══════════════════════════════════════════════════════════════
;;; AutoGo-inspired depth randomization: prevents over-specialization
;;; by varying the exploration depth each cycle.

(defcustom gptel-knowledge-playout-cap-quick 0.80
  "Probability of quick (shallow) playout in champion league."
  :type 'float
  :group 'gptel-tools-agent)

(defcustom gptel-knowledge-playout-cap-medium 0.15
  "Probability of medium-depth playout in champion league."
  :type 'float
  :group 'gptel-tools-agent)

(defcustom gptel-knowledge-playout-cap-deep 0.05
  "Probability of deep (full) playout in champion league."
  :type 'float
  :group 'gptel-tools-agent)

(defun gptel-knowledge--playout-cap-randomize ()
  "Return playout depth: :quick, :medium, or :deep.
80% quick / 15% medium / 5% deep (AutoGo Playout Cap Randomization)."
  (let ((r (random 100)))
    (cond
     ((< r (* gptel-knowledge-playout-cap-quick 100)) :quick)
     ((< r (* (+ gptel-knowledge-playout-cap-quick gptel-knowledge-playout-cap-medium) 100)) :medium)
     (t :deep))))

(defun gptel-knowledge--playout-sample-limit (depth)
  "Return the maximum sample count for DEPTH (:quick/:medium/:deep).
Quick=3, Medium=7, Deep=all."
  (pcase depth
    (:quick 3)
    (:medium 7)
    (:deep most-positive-fixnum)
    (_ 5)))

;;; ═══════════════════════════════════════════════════════════════
;;; DIALECTIC.md Moderator
;;; ═══════════════════════════════════════════════════════════════
;;; Formalized moderator that triggers forced backend swap after
;;; 3+ consecutive failures. Intervention lenses from DIALECTIC.md.

(defcustom gptel-knowledge-dialectic-failure-threshold 3
  "Number of consecutive failures before forced backend swap."
  :type 'integer
  :group 'gptel-tools-agent)

(defun gptel-knowledge--dialectic-lens (failure-type)
  "Return moderator intervention lens for FAILURE-TYPE.
DIALECTIC.md: consequence_check, evidence_nudge, assumption_probe."
  (pcase failure-type
    (:timeout '(:lens consequence_check
                :prompt "This backend timed out. Is the hypothesis too complex for this model's context window?"
                :action :backend-swap))
    (:rate-limit '(:lens evidence_nudge
                   :prompt "Rate limit suggests overuse. Is there evidence this backend excels at this category?"
                   :action :cool-down))
    (:quality-drop '(:lens assumption_probe
                     :prompt "Quality dropped despite passing tests. Are we optimizing the right metric?"
                     :action :strategy-revise))
    (:consistency '(:lens assumption_probe
                    :prompt "Cross-backend disagreement. Which backend's judgment should we trust?"
                    :action :cross-validate))
    (_ '(:lens consequence_check
         :prompt "Unknown failure pattern. What evidence supports continuing with this backend?"
         :action :investigate))))

(defun gptel-knowledge--dialectic-check (target-history)
  "Check TARGET-HISTORY for failures requiring moderator intervention.
TARGET-HISTORY is a list of (:id N :decision DEC :failure-type SYM).
Returns nil or a plist with :intervention, :lens, :forced-action."
  (let ((consecutive-failures 0)
        (last-failure-type nil))
    (dolist (entry (reverse target-history))
      (if (equal (plist-get entry :decision) "kept")
          (cl-return)
        (cl-incf consecutive-failures)
        (setq last-failure-type (plist-get entry :failure-type))))
    (when (>= consecutive-failures gptel-knowledge-dialectic-failure-threshold)
      (let ((lens (gptel-knowledge--dialectic-lens (or last-failure-type :unknown))))
        (list :intervention t
              :consecutive-failures consecutive-failures
              :lens (plist-get lens :lens)
              :prompt (plist-get lens :prompt)
              :forced-action (plist-get lens :action))))))

;;; ═══════════════════════════════════════════════════════════════
;;; Deterministic-First Target Selection (frontier-select-targets)
;;; ═══════════════════════════════════════════════════════════════

(defun gptel-knowledge--frontier-select-targets (tsv-file &optional max-targets)
  "Select targets from TSV-FILE using Pareto frontier ranking.
Deterministic — reads TSV history, ranks by frontier size, <1s.
No LLM calls. Falls back to category-based ordering when TSV empty."
  (let ((results (gptel-knowledge--parse-tsv-results tsv-file))
        (limit (or max-targets 5)))
    (if (null results)
        (list :targets nil :method :empty :count 0)
      (let* ((by-target (make-hash-table :test 'equal))
             (target-scores nil))
        (dolist (r results)
          (push r (gethash (plist-get r :target) by-target)))
        (maphash
         (lambda (target experiments)
           (let* ((kept (cl-count-if (lambda (e) (equal (plist-get e :decision) "kept")) experiments))
                  (total (length experiments))
                  (keep-rate (if (> total 0) (/ (float kept) total) 0.0))
                  (recent (seq-take (sort experiments (lambda (a b) (> (or (plist-get a :id) 0) (or (plist-get b :id) 0)))) 5))
                  (recent-kept (cl-count-if (lambda (e) (equal (plist-get e :decision) "kept")) recent))
                  (recency (/ (float recent-kept) (max (length recent) 1))))
             (push (list :target target
                         :keep-rate keep-rate
                         :recency recency
                         :total total
                         :frontier-score (+ (* 0.6 recency) (* 0.4 keep-rate)))
                   target-scores)))
         by-target)
        (setq target-scores (sort target-scores
                                  (lambda (a b) (> (plist-get a :frontier-score)
                                                   (plist-get b :frontier-score)))))
        (let ((selected (mapcar (lambda (s) (plist-get s :target))
                                (seq-take target-scores limit))))
          (list :targets selected
                :method :frontier
                :count (length selected)
                :all-scores target-scores))))))

(defun gptel-knowledge--parse-tsv-results (tsv-file)
  "Parse TSV-FILE into list of experiment result plists.
Handles the 30-column TSV format from gptel-auto-experiment-log-tsv."
  (when (file-readable-p tsv-file)
    (let ((results nil))
      (with-temp-buffer
        (insert-file-contents tsv-file)
        (goto-char (point-min))
        (forward-line 1)
        (while (not (eobp))
          (let* ((fields (split-string (buffer-substring (line-beginning-position)
                                                         (line-end-position)) "\t"))
                 (id (nth 0 fields))
                 (target (nth 1 fields))
                 (decision (nth 7 fields)))
            (when (and id target (not (string-empty-p id)))
              (push (list :id (string-to-number id)
                          :target target
                          :decision decision)
                    results))
            (forward-line 1))))
      (nreverse results))))

(provide 'gptel-auto-workflow-knowledge-reasoning)
;;; gptel-auto-workflow-knowledge-reasoning.el ends here
