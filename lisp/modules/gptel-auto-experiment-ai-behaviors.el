;;; gptel-auto-experiment-ai-behaviors.el --- ai-behaviors hashtag resolver for OV5

;; Resolves #hashtags from the ai-behaviors submodule at
;; packages/ai-behaviors/behaviors/<name>/{compose,prompt.md}.
;; Maps ontology categories to hashtag combinations and injects
;; the resolved content into executor prompts.

(defconst gptel-ai-behaviors-root
  (expand-file-name "packages/ai-behaviors/behaviors"
                    (or (bound-and-true-p minimal-emacs-user-directory)
                        user-emacs-directory))
  "Path to the ai-behaviors behaviors directory.")

(defvar gptel-ai-behaviors--expand-cache (make-hash-table :test 'equal)
  "Cache of hashtag → resolved content. Cleared on repo update.")

(defun gptel-ai-behaviors--repo-available-p ()
  "Return non-nil when the ai-behaviors submodule is present."
  (let ((avail (file-directory-p gptel-ai-behaviors-root)))
    (unless avail
      (message "[ai-behaviors] Submodule not found at %s — using hardcoded defaults"
               gptel-ai-behaviors-root))
    avail))

(defun gptel-ai-behaviors--resolve-dir (name)
  "Resolve behavior directory for NAME, checking all overrides.
Resolution order: project-local (.ai-behaviors/) → user-local
(~/.config/ai-behaviors/) → repo (packages/ai-behaviors/behaviors/).
Returns directory path or nil."
  (or (let* ((proj-root (and (bound-and-true-p gptel-auto-workflow--current-project)
                             (expand-file-name gptel-auto-workflow--current-project)))
             (local-dir (and proj-root (expand-file-name (concat ".ai-behaviors/" name) proj-root))))
        (when (and local-dir (file-directory-p local-dir))
          local-dir))
      (let ((user-dir (expand-file-name (concat "~/.config/ai-behaviors/behaviors/" name))))
        (when (file-directory-p user-dir)
          user-dir))
      (let ((repo-dir (expand-file-name name gptel-ai-behaviors-root)))
        (when (file-directory-p repo-dir)
          repo-dir))))

(defun gptel-ai-behaviors--expand (hashtags &optional depth seen)
  "Expand HASHTAGS (space-separated, with # prefix) to leaf behaviors.
Resolves composites recursively (max depth 8). Returns (CONTENT . MODE-TAGS)
where CONTENT is the concatenated prompt.md text and MODE-TAGS is the
active operating mode tag (or nil)."
  (let ((content "")
        (mode-tag nil)
        (current-depth (or depth 0))
        (current-seen (or seen "")))
    (dolist (tag (split-string hashtags))
      (let ((name (substring tag 1)))  ; strip #
        (when-let ((dir (gptel-ai-behaviors--resolve-dir name)))
          (cond
           ;; Composite: has compose file — expand recursively
           ((file-exists-p (expand-file-name "compose" dir))
            (when (not (string-match-p (regexp-quote name) current-seen))
              (when (< current-depth 8)
                (let ((composed (with-temp-buffer
                                  (insert-file-contents (expand-file-name "compose" dir))
                                  (string-trim (buffer-string)))))
                  (when-let ((result (gptel-ai-behaviors--expand
                                      composed (1+ current-depth)
                                      (concat current-seen " " name))))
                    (setq content (concat content (car result)))
                    (when (and (cdr result) (not mode-tag))
                      (setq mode-tag (cdr result))))))))
           ;; Leaf behavior: has prompt.md — read content
           ((file-exists-p (expand-file-name "prompt.md" dir))
            (let ((md-content (with-temp-buffer
                                (insert-file-contents (expand-file-name "prompt.md" dir))
                                (string-trim (buffer-string)))))
              (setq content (concat content "\n" md-content "\n"))
              (when (string-prefix-p "#=" tag)
                (setq mode-tag tag))))))))
    (cons (string-trim content) mode-tag)))

(defvar gptel-ai-behaviors--current-hashtags nil
  "Dynamic variable. Set by prompt builder to the hashtags injected.
Read by experiment logging to record which behaviors were active.")

(defvar gptel-ai-behaviors--current-strategy nil
  "Dynamic variable. Set by prompt builder to the strategy name used.
Read by experiment logging for three-way (category × strategy × hashtags) tracking.")

(defvar gptel-ai-behaviors--category-performance (make-hash-table :test 'equal)
  "Hash table: (category . hashtag) → (kept . total).
Learned from experiment outcomes. Evolved each cycle.")

(defvar gptel-ai-behaviors--category-defaults nil
  "Alist: (category . hashtag-string) learned from kept experiments.
Falls back to hardcoded defaults when no data exists.")

(defun gptel-ai-behaviors--record-experiment (category hashtags kept &optional strategy backend)
  "Record HASHTAGS for CATEGORY as kept or not.
When STRATEGY is provided, tracks three-way (category × strategy × hashtags).
When BACKEND is provided, tracks (category × backend × hashtag) for backend-aware behavior selection."
  (when category
    (dolist (tag (split-string hashtags))
      ;; Two-way: (category × hashtags)
      (let* ((key (cons category tag))
             (entry (gethash key gptel-ai-behaviors--category-performance (cons 0 0))))
        (setf (car entry) (+ (car entry) (if kept 1 0)))
        (setf (cdr entry) (1+ (cdr entry)))
        (puthash key entry gptel-ai-behaviors--category-performance))
      ;; Three-way: (category × strategy × hashtags)
      (when strategy
        (let* ((key3 (list category strategy tag))
               (entry3 (gethash key3 gptel-ai-behaviors--category-performance (cons 0 0))))
          (setf (car entry3) (+ (car entry3) (if kept 1 0)))
          (setf (cdr entry3) (1+ (cdr entry3)))
          (puthash key3 entry3 gptel-ai-behaviors--category-performance)))
      ;; Backend-aware: (category × backend × hashtags) — Gap 1 closure
      (when backend
        (let* ((keyb (list category (intern backend) tag))
               (entryb (gethash keyb gptel-ai-behaviors--category-performance (cons 0 0))))
          (setf (car entryb) (+ (car entryb) (if kept 1 0)))
          (setf (cdr entryb) (1+ (cdr entryb)))
          (puthash keyb entryb gptel-ai-behaviors--category-performance))))))

(defvar gptel-ai-behaviors--combo-defaults nil
  "Alist: (category . (strategy . hashtags)) learned from three-way data.")

(defun gptel-ai-behaviors--evolve-hashtags ()
  "Evolve category→hashtags mapping from experiment outcomes.
Learns both two-way (category × hashtag) and three-way
(category × strategy × hashtag) optimal combinations."
  (let ((cat-best (make-hash-table :test 'equal))
        (combo-best (make-hash-table :test 'equal)))
    ;; Two-way: category × hashtag
    (maphash
     (lambda (key entry)
       (when (and (consp key) (not (listp (cdr key))))  ; simple (cat . tag) keys
         (let* ((category (car key))
                (hashtag (cdr key))
                (kept (car entry))
                (total (cdr entry))
                (rate (if (> total 0) (/ (float kept) total) 0))
                (current (gethash category cat-best nil)))
           (when (and (>= total 3) (> rate 0)
                      (or (null current) (> rate (cdr current))))
             (puthash category (cons hashtag rate) cat-best)))))
     gptel-ai-behaviors--category-performance)
    (setq gptel-ai-behaviors--category-defaults nil)
    (maphash
     (lambda (category best)
       (push (cons category (car best))
             gptel-ai-behaviors--category-defaults)
       (message "[ai-behaviors-evolve] %s: best hashtag %s (keep-rate %.0f%%)"
                category (car best) (* 100 (cdr best))))
     cat-best)
    ;; Three-way: category × strategy × hashtag
    (maphash
     (lambda (key entry)
       (when (and (listp key) (= (length key) 3))  ; three-way keys
         (let* ((category (nth 0 key))
                (strategy (nth 1 key))
                (hashtag (nth 2 key))
                (kept (car entry))
                (total (cdr entry))
                (rate (if (> total 0) (/ (float kept) total) 0))
                (combo-key (cons category strategy))
                (current (gethash combo-key combo-best nil)))
           (when (and (>= total 2) (> rate 0)
                      (or (null current) (> rate (cdr current))))
             (puthash combo-key (cons hashtag rate) combo-best)))))
     gptel-ai-behaviors--category-performance)
    (setq gptel-ai-behaviors--combo-defaults nil)
    (maphash
     (lambda (combo-key best)
       (let* ((category (car combo-key))
              (strategy (cdr combo-key))
              (hashtag (car best))
              (rate (cdr best)))
         (push (list category strategy hashtag)
               gptel-ai-behaviors--combo-defaults)
         (message "[ai-behaviors-evolve] %s/%s: best hashtag %s (keep-rate %.0f%%)"
                  category strategy hashtag (* 100 rate))))
     combo-best)))

(defun gptel-ai-behaviors--best-hashtag-for (category &optional strategy)
  "Return the best hashtag for CATEGORY, optionally with STRATEGY.
Prefers three-way (category × strategy) match over two-way (category only)."
  (when category
    (or (and strategy
             (let ((entry (assoc (list category strategy)
                                 (mapcar (lambda (x) (cons (list (nth 0 x) (nth 1 x)) (nth 2 x)))
                                         gptel-ai-behaviors--combo-defaults))))
               (when entry (cdr entry))))
        (cdr (assq category gptel-ai-behaviors--category-defaults)))))

(defun gptel-ai-behaviors--category-hashtags (category)
  "Return the hashtag string for CATEGORY (ai-behaviors format).
Uses learned defaults when available, falls back to hardcoded.
All hashtags reference real behavior directories in packages/ai-behaviors/."
  (or (cdr (assq category gptel-ai-behaviors--category-defaults))
      (pcase category
        (:agentic "#=code #contract #checklist #stop #legible #concise #=act")
        (:programming "#=tdd #decompose #bisect #concrete #legible #=act")
        (:tool-calls "#=code #simulate #boundary #temporal #legible #=act")
        (:natural-language "#=code #user-lens #coherence #concrete #legible #=act")
        (_ "#=code #legible #concise #=act"))))

(defvar gptel-ai-behaviors--impact-tracking (make-hash-table :test 'equal)
  "Hash table: (category . hashtag) → (kept-with . total-with) for behavior impact analysis.")

(defun gptel-ai-behaviors--record-behavior-impact (category hashtags kept)
  "Record which behaviors were active for KEPT or DISCARDED experiment."
  (when category
    (dolist (tag (split-string hashtags))
      (let* ((key (cons category tag))
             (entry (gethash key gptel-ai-behaviors--impact-tracking (cons 0 0))))
        (setf (car entry) (+ (car entry) (if kept 1 0)))
        (setf (cdr entry) (1+ (cdr entry)))
        (puthash key entry gptel-ai-behaviors--impact-tracking)))))

(defun gptel-ai-behaviors--low-impact-behaviors (category)
  "Return list of hashtags for CATEGORY that never affect outcomes (skip threshold > 5 experiments)."
  (let ((result nil))
    (maphash
     (lambda (key entry)
       (when (and (eq (car key) category)
                  (>= (cdr entry) 5)  ; enough data
                  (let* ((kept-with (car entry))
                         (total-with (cdr entry))
                         (kept-without (- total-with kept-with)))
                    ;; If keep-rate WITH behavior ≈ keep-rate WITHOUT, it's low-impact
                    (< (abs (- (if (> kept-with 0) (/ (float kept-with) total-with) 0)
                                (if (> kept-without 0) (/ (float (- total-with kept-with)) total-with) 0)))
                       0.1))))
       (push (cdr key) result))
     gptel-ai-behaviors--impact-tracking)
    result))

(defun gptel-ai-behaviors--inject (category)
  "Resolve hashtags for CATEGORY and return formatted context.
Skips behaviors that have been identified as low-impact for this category."
  (when (and category (gptel-ai-behaviors--repo-available-p))
    (let* ((all-hashtags (gptel-ai-behaviors--category-hashtags category))
           (low-impact (gptel-ai-behaviors--low-impact-behaviors category))
           (filtered (if low-impact
                        (mapconcat #'identity
                                   (cl-remove-if (lambda (tagn)
                                                   (member tagn low-impact))
                                                 (split-string all-hashtags))
                                   " ")
                      all-hashtags)))
      (when (string-empty-p (string-trim filtered))
        (setq filtered all-hashtags))  ; never inject empty — revert to all
      (let* ((resolved (gptel-ai-behaviors--expand filtered))
             (content (car resolved))
             (mode-tag (cdr resolved)))
        (when (> (length content) 0)
          (when (> (length low-impact) 0)
            (message "[ai-behaviors] Skipped %d low-impact behaviors for %s: %s"
                     (length low-impact) category (mapconcat #'identity low-impact " ")))
          (concat (if mode-tag
                      (format "<operating-mode name=\"%s\">\n%s\n</operating-mode>\n"
                              mode-tag content)
                    (format "<behavior-modifiers>\n%s\n</behavior-modifiers>\n"
                            content))
                  "<framework>
HARD CONSTRAINTs define what the current mode IS — they are not overridable.
When a behavior modifier causes you to make a point you would not otherwise make,
mark it: (#name) after the sentence.
</framework>\n"))))))

(defun gptel-ai-behaviors--inject-for-target (target)
  "Resolve ai-behaviors for TARGET's ontology category."
  (when (and target (fboundp 'gptel-auto-workflow--categorize-target))
    (gptel-ai-behaviors--inject
     (gptel-auto-workflow--categorize-target target))))

;; ─── Pipeline Mode Map ───
;; Each OV5 subagent type maps to an ai-behaviors operating mode.
;; The mode defines WHAT the subagent IS (its identity) and what it WILL NOT do.

(defconst gptel-ai-behaviors--pipeline-modes
  '((analyzer
     :mode "#=research"
     :description "Investigate. Report facts. Do NOT recommend or implement."
     :hard-constraints ("research ∩ {Opinions, Recommendations, Code, Implementation} = ∅"
                        "Report findings and unknowns — not solutions")
     :transition "when investigation is exhausted ⊣ {#Code}")
    (executor
      :mode "#=tdd"
      :description "Test-first development. Verify, then implement. Do NOT skip verification."
      :hard-constraints ("tdd ∩ {UntestedCode, UnverifiedChanges, SkippedVerify} = ∅"
                         "Write VERIFY section (outside <think>) with MANDATORY commands:"
                         "  emacs -batch -f batch-byte-compile <file>  → must PASS"
                         "  emacs -batch -l <file>                     → must LOAD without error"
                         "  Run tests if test file exists              → must PASS"
                         "Change ONLY what the hypothesis specifies"
                         "VERIFY output missing = automatic grader FAIL")
      :transition "when ALL verification passes ⊣ {#Review}")
    (grader
     :mode "#=review"
     :description "Evaluate code. Find issues. Do NOT fix them."
     :hard-constraints ("review ∩ {Fixes, Refactoring, WrittenCode} = ∅"
                        "Judge against expected behaviors — not personal preference")
     :transition "when all findings are delivered ⊣ {#Code, #Spec}")
    (comparator
     :mode "#=spec"
     :description "Compare before/after. Decide keep or discard. Do NOT re-implement."
     :hard-constraints ("spec ∩ {Code, Implementation} = ∅"
                        "Base decision on evidence — grader score + tests + eight-keys")
     :transition "when decision is made — pipeline continues"))
  "Maps each OV5 subagent type to an ai-behaviors operating mode.
Each mode has HARD CONSTRAINTS (what the subagent IS) and a ⊣ transition
(what should run next).")

(defun gptel-ai-behaviors--mode-for-subagent (agent-type)
  "Return the operating mode plist for AGENT-TYPE (analyzer/executor/grader/comparator)."
  (cdr (assq agent-type gptel-ai-behaviors--pipeline-modes)))

(defun gptel-ai-behaviors--mode-hashtags (agent-type)
  "Return the mode hashtag string for AGENT-TYPE, e.g. \"#=research\"."
  (plist-get (gptel-ai-behaviors--mode-for-subagent agent-type) :mode))

(defun gptel-ai-behaviors--mode-hard-constraints (agent-type)
  "Return the HARD CONSTRAINT strings for AGENT-TYPE."
  (plist-get (gptel-ai-behaviors--mode-for-subagent agent-type) :hard-constraints))

(defun gptel-ai-behaviors--mode-transition (agent-type)
  "Return the ⊣ transition string for AGENT-TYPE."
  (plist-get (gptel-ai-behaviors--mode-for-subagent agent-type) :transition))

(defun gptel-ai-behaviors--format-pipeline-context (agent-type)
  "Format the pipeline mode context for AGENT-TYPE as a prompt string.
Injects into executor/analyzer/grader/comparator prompts."
  (when-let ((mode (gptel-ai-behaviors--mode-for-subagent agent-type)))
    (format
     (concat "<operating-mode name=\"%s\">\n"
             "%s\n"
             "HARD CONSTRAINTS:\n"
             "%s\n"
             "When done: %s\n"
             "</operating-mode>\n")
     (plist-get mode :mode)
     (plist-get mode :description)
     (mapconcat (lambda (c) (format "  ∩ %s" c))
                (plist-get mode :hard-constraints) "\n")
     (plist-get mode :transition))))

;; ─── Mode Enforcement ───
;; The controller checks whether a subagent output stays within its mode's
;; HARD CONSTRAINTS. Out-of-mode signals (e.g., executor making a research
;; recommendation) are flagged but not blocked — the system observes and
;; records the violation for self-evolution.

;; ─── Reasoning-to-Behavior Mapping ───
;; Extracts reasoning patterns from <think> blocks and maps them to
;; ai-behaviors hashtags. The ontology tracks which patterns are
;; effective per category and recommends behaviors for future experiments.

(defconst gptel-ai-behaviors--reasoning-patterns
  '(("trace\\|step.by.step\\|simulat\\|let me trace" . "#simulate")
    ("check\\|edge case\\|boundar\\|zero\\|empty\\|nil" . "#boundary")
    ("decompos\\|break down\\|subproblem\\|split" . "#decompose")
    ("alternatives\\|option\\|compare\\|tradeoff" . "#evaluate")
    ("what if\\|reverse\\|backward\\|from the end" . "#backward")
    ("first principle\\|axiom\\|fundamental\\|from scratch" . "#first-principles")
    ("analog\\|similar\\|like\\|compare to" . "#analogy")
    ("deep\\|why\\|root cause\\|underlying" . "#deep")
    ("dimension\\|axis\\|factor\\|independ" . "#factor")
    ("precondition\\|postcondition\\|invariant\\|contract" . "#contract")
    ("provenance\\|origin\\|source\\|where.*came" . "#provenance"))
  "Alist of (reasoning-regex . ai-behaviors-hashtag).
Maps reasoning patterns found in <think> blocks to behavior tags.")

(defvar gptel-ai-behaviors--reasoning-hits (make-hash-table :test 'equal)
  "Hash table: (category . hashtag) → count of reasoning matches.
Cleared each evolution cycle. Used by prompt builder to recommend behaviors.")

(defun gptel-ai-behaviors--parse-reasoning (output category)
  "Parse OUTPUT for reasoning patterns, update hit counts for CATEGORY."
  (when (and output category)
    (let ((think-blocks (gptel-auto-experiment--extract-think-blocks output)))
      (dolist (block think-blocks)
        (dolist (pattern gptel-ai-behaviors--reasoning-patterns)
          (when (string-match-p (car pattern) block)
            (let ((key (cons category (cdr pattern))))
              (puthash key (1+ (gethash key gptel-ai-behaviors--reasoning-hits 0))
                       gptel-ai-behaviors--reasoning-hits))))))))

(defun gptel-ai-behaviors--extract-think-blocks (text)
  "Extract all <think>...</think> blocks from TEXT as list of strings."
  (let ((blocks nil)
        (start 0))
    (while (string-match "<think>\\(.*?\\)</think>" text start)
      (push (match-string-no-properties 1 text) blocks)
      (setq start (match-end 0)))
    blocks))

(defun gptel-ai-behaviors--recommend-behaviors (category &optional n)
  "Return the N most frequently hit hashtags for CATEGORY (min 3 hits).
Returns string of space-separated hashtags, or empty string."
  (when category
    (let ((hits (make-hash-table :test 'equal)))
      (maphash (lambda (key count)
                 (when (and (eq (car key) category) (>= count 3))
                   (puthash (cdr key) (+ (gethash (cdr key) hits 0) count) hits)))
               gptel-ai-behaviors--reasoning-hits)
      (let ((sorted (sort (let (result)
                            (maphash (lambda (k v) (push (cons k v) result)) hits)
                            result)
                          (lambda (a b) (> (cdr a) (cdr b))))))
        (when sorted
          (mapconcat #'car (seq-take sorted (or n 3)) " "))))))

(defun gptel-ai-behaviors--clear-reasoning-hits ()
  "Clear reasoning hit counts at the start of each evolution cycle."
  (clrhash gptel-ai-behaviors--reasoning-hits))

(defun gptel-ai-behaviors--check-mode-violation (agent-type output)
  "Check if OUTPUT contains out-of-mode signals for AGENT-TYPE.
Returns violation string or nil. Detects transitions and mode-crossing
language ('I recommend', 'we should research', etc.)."
  (when (and (stringp output) (assq agent-type gptel-ai-behaviors--pipeline-modes))
    (let ((violations nil)
          (mode-name (plist-get (gptel-ai-behaviors--mode-for-subagent agent-type) :mode)))
      (pcase agent-type
        ((or 'analyzer 'comparator)
         (when (string-match-p "\\`I recommend\\|we should implement\\|let me code\\|I'll write"
                               output)
           (push (format "%s crossed mode boundary: recommended/implemented when in %s"
                         agent-type mode-name) violations)))
        ('executor
         (when (string-match-p "\\`I recommend\\|further research needed\\|we should investigate"
                               output)
           (push (format "%s crossed mode boundary: recommended/analyzed when in %s"
                         agent-type mode-name) violations)))
        ('grader
         (when (string-match-p "\\`I'll fix\\|let me correct\\|I will change"
                               output)
           (push (format "%s crossed mode boundary: attempted fixes when in %s"
                         agent-type mode-name) violations))))
      (when violations
        (let ((msg (mapconcat #'identity violations "; ")))
          (gptel-ai-behaviors--record-violation msg)
          msg)))))

(defvar gptel-ai-behaviors--recent-violations nil
  "List of mode violation strings from the most recent experiment cycle.
Reset each cycle. Read by prompt builder for failure feedback.")

(defun gptel-ai-behaviors--record-violation (violation)
  "Record a mode VIOLATION for prompt feedback."
  (push violation gptel-ai-behaviors--recent-violations))

(defun gptel-ai-behaviors--clear-violations ()
  "Clear recorded violations at cycle start."
  (setq gptel-ai-behaviors--recent-violations nil))

(defun gptel-ai-behaviors--violations-for-prompt ()
  "Format recent violations as prompt guidance, or empty string."
  (when gptel-ai-behaviors--recent-violations
    (concat "## Mode Violations (AVOID THESE)\n"
            "Previous experiments crossed mode boundaries:\n"
            (mapconcat (lambda (v) (format "  - %s" v))
                       (delete-dups gptel-ai-behaviors--recent-violations) "\n")
            "\n\nStay within your assigned operating mode.\n")))

(defun gptel-ai-behaviors--recommend-for-prompt (target)
  "Return formatted recommended behaviors string for TARGET, or empty.
Uses reasoning→behavior mappings from previous experiments.
Includes three-way combo (category × strategy × hashtags) recommendation
when available from empirical data."
  (when (and target (fboundp 'gptel-auto-workflow--categorize-target))
    (let* ((category (gptel-auto-workflow--categorize-target target))
           (recs (gptel-ai-behaviors--recommend-behaviors category 3))
           (strategy (when (boundp 'gptel-auto-workflow--current-strategy-name)
                       gptel-auto-workflow--current-strategy-name))
           (best-hashtag (when (fboundp 'gptel-ai-behaviors--best-hashtag-for)
                           (gptel-ai-behaviors--best-hashtag-for category strategy)))
           (parts nil))
      (when best-hashtag
        (push (format "  └ %s for %s with strategy %s (learned from experiment data)"
                      best-hashtag category strategy) parts))
      (when (> (length recs) 0)
        (push (format "  └ %s (from reasoning patterns)" recs) parts))
      (when parts
        (concat "## Optimal Behavior Combos (learned)\n"
                (mapconcat #'identity parts "\n") "\n")))))

;; ─── Universal Subsystem Behavior Map ───
;; Every OV5 subsystem can query its optimal behavior hashtags.
;; Defaults are learned from experiment data per (subsystem × category).

(defconst gptel-ai-behaviors--subsystem-map
  '((researcher
     :mode "#=research"
     :description "Investigate. Report findings. Surface unknowns."
     :modifiers "#epistemic #provenance #concise"
     :used-by "gptel-auto-workflow--load-research-findings")
    (autotts
     :mode "#=design"
     :description "Explore strategy candidates. Evaluate before committing."
     :modifiers "#evaluate #provenance #decompose"
     :used-by "gptel-auto-workflow--select-best-strategy")
    (autogo
     :mode "#=spec"
     :description "Allocate budget. Reason from desired outcomes."
     :modifiers "#backward #obligations #concise"
     :used-by "gptel-auto-workflow--compute-frontier")
    (controller
     :mode "#=review"
     :description "Orchestrate pipeline. Check every step."
     :modifiers "#checklist #stop #triage #concise"
     :used-by "gptel-auto-workflow--consume-vsm-actions")
    (champion
     :mode "#=evaluate"
     :description "Benchmark strategies. Every candidate × every dimension."
     :modifiers "#evaluate #provenance #legible"
     :used-by "gptel-auto-workflow--run-research-champion-league"))
  "Maps each OV5 subsystem to ai-behaviors mode + modifiers.
Each entry: (subsystem-symbol :mode :description :modifiers :used-by)")

(defun gptel-ai-behaviors--subsystem-context (subsystem)
  "Return formatted ai-behaviors context for SUBSYSTEM, or empty.
Injects operating mode + behavior modifiers into subsystem prompts."
  (when-let ((entry (assq subsystem gptel-ai-behaviors--subsystem-map)))
    (let ((mode (plist-get (cdr entry) :mode))
          (desc (plist-get (cdr entry) :description))
          (modifiers (plist-get (cdr entry) :modifiers)))
      (concat
       (format "<operating-mode name=\"%s\">\n%s\n</operating-mode>\n" mode desc)
       (when (> (length modifiers) 0)
         (format "<behavior-modifiers>\n%s\n</behavior-modifiers>\n"
                 (gptel-ai-behaviors--resolve-subagent-category subsystem modifiers)))
       "<framework>
HARD CONSTRAINTs define what the current mode IS — they are not overridable.
</framework>\n"))))

(defun gptel-ai-behaviors--resolve-subagent-category (subsystem default-modifiers)
  "Resolve modifiers for SUBSYSTEM. Uses learned defaults if available."
  (when (and (fboundp 'gptel-auto-workflow--categorize-target)
             (bound-and-true-p gptel-auto-workflow--current-target))
    (let* ((target gptel-auto-workflow--current-target)
           (category (gptel-auto-workflow--categorize-target target))
           (best (when category
                   (gptel-ai-behaviors--best-hashtag-for category nil))))
      (or best default-modifiers))))

;; ─── Convergence Invariant Tracking ───
;; Monitors that refine scores are monotonically improving.

(defvar gptel-ai-behaviors--convergence-history (make-hash-table :test 'equal)
  "Hash table: target → list of (timestamp . score) for successive refines.")

(defvar gptel-ai-behaviors--convergence-violations (make-hash-table :test 'equal)
  "Hash table: target → count of consecutive convergence violations.")

(defun gptel-ai-behaviors--record-refine-score (target score)
  "Record SCORE for TARGET refine iteration. Checks monotonic improvement."
  (when target
    (let* ((history (gethash target gptel-ai-behaviors--convergence-history nil))
           (prev-score (car (car history)))
           (violations (gethash target gptel-ai-behaviors--convergence-violations 0)))
      (push (cons (float-time) score) history)
      (puthash target history gptel-ai-behaviors--convergence-history)
      ;; Check monotonic improvement
      (when (and prev-score (< score prev-score))
        (let ((new-violations (1+ violations)))
          (puthash target new-violations gptel-ai-behaviors--convergence-violations)
          (message "[convergence] ⚠ %s: score dropped %.3f → %.3f (%d violations)"
                   target prev-score score new-violations)
          (when (>= new-violations 3)
            (message "[convergence] 🚫 %s: 3 consecutive regressions — suggest terminating refine cycle"
                     target)))))))

(defun gptel-ai-behaviors--clear-convergence ()
  "Clear convergence tracking at cycle start."
  (clrhash gptel-ai-behaviors--convergence-history)
  (clrhash gptel-ai-behaviors--convergence-violations))

;; ─── Subagent Precondition Enforcement ───
;; Blocks subagent dispatch if HARD CONSTRAINTS are violated.

(defun gptel-ai-behaviors--check-subagent-preconditions (agent-type prompt)
  "Check if PROMPT violates AGENT-TYPE's mode HARD CONSTRAINTS.
Returns nil if ok, or error string if blocked."
  (when-let ((mode (gptel-ai-behaviors--mode-for-subagent agent-type)))
    (let ((constraints (plist-get mode :hard-constraints))
          (violations nil))
      (dolist (constraint constraints)
        (cond
         ;; "review ∩ {Fixes, Refactoring, WrittenCode} = ∅" → prompt should not ask to fix
         ((and (string-match-p "∩ {Fixes" constraint)
               (string-match-p "fix\\|correct\\|rewrite\\|refactor" prompt))
          (push (format "HARD CONSTRAINT: %s (prompt asks to fix in %s mode)" constraint agent-type)
                violations))
         ;; "research ∩ {Code, Implementation} = ∅" → prompt should not ask to implement
         ((and (string-match-p "∩ {Code, Implementation" constraint)
               (string-match-p "implement\\|write code\\|create file" prompt))
          (push (format "HARD CONSTRAINT: %s (prompt asks to implement in %s mode)" constraint agent-type)
                violations))
         ;; "spec ∩ {Code, Implementation} = ∅" → similar
         ((and (string-match-p "∩ {Code, Implementation, Mutation" constraint)
               (string-match-p "implement\\|write code\\|modify" prompt))
          (push (format "HARD CONSTRAINT: %s (prompt asks to implement in %s mode)" constraint agent-type)
                violations))))
      (when violations
        (mapconcat #'identity violations "; ")))))

;; ─── Subsystem Advice Registration ───
;; Wire ai-behaviors context into each subsystem at its entry point.

(defun gptel-ai-behaviors--advice-inject (subsystem &optional no-prompt)
  "Return an :around advice function that injects SUBSYSTEM behavior context.
When NO-PROMPT is non-nil, just logs the context (for non-LLM subsystems)."
  (lambda (orig-fn &rest args)
    (let ((ctx (gptel-ai-behaviors--subsystem-context subsystem)))
      (when (> (length ctx) 0)
        (if no-prompt
            (message "[ai-behaviors] %s context:\n%s" subsystem ctx)
          (message "[ai-behaviors] Injected %s behaviors" subsystem)))
      (apply orig-fn args))))

;; ─── Allium Validation of Research Findings ───

(defun gptel-ai-behaviors--validate-research (findings)
  "Validate research FINDINGS with Allium BDD. Returns validation result."
  (when (and (stringp findings) (> (length findings) 50)
             (fboundp 'gptel-auto-workflow--allium-bdd-assert))
    (let ((checks
           (list
            (gptel-auto-workflow--allium-bdd-assert
             (format "Research findings have actionable recommendations: %s"
                     (if (string-match-p "apply\\|recommend\\|use\\|try\\|switch" findings) "YES" "NO")))
            (gptel-auto-workflow--allium-bdd-assert
             (format "Research findings reference experiment data: %s"
                     (if (string-match-p "kept\\|keep.rate\\|experiment\\|\\d+%" findings) "YES" "NO")))
            (gptel-auto-workflow--allium-bdd-assert
             (format "Research findings are category-aware: %s"
                     (if (string-match-p ":agentic\\|:programming\\|:tool.calls\\|:natural.language\\|programming\\|agentic"
                                         findings) "YES" "NO"))))))
      (let ((passed (cl-count-if #'identity checks))
            (total (length checks)))
        (message "[researcher-allium] Validated findings: %d/%d checks passed" passed total)
        (list :passed passed :total total :pct (if (> total 0) (/ (float passed) total) 0))))))

;; Wrap load-research-findings with Allium validation
(defun gptel-ai-behaviors--wrap-research-with-validation (orig-fn &rest args)
  "Wrap research findings loading with Allium validation."
  (let ((findings (apply orig-fn args)))
    (when (and (stringp findings) (> (length findings) 0)
               (fboundp 'gptel-ai-behaviors--validate-research))
      (let ((validation (gptel-ai-behaviors--validate-research findings)))
        (when (and validation (< (plist-get validation :pct) 0.67))
          (message "[researcher-allium] ⚠ Findings validation weak (%d/%d) — consider refining research approach"
                   (plist-get validation :passed) (plist-get validation :total)))))
    findings))

;; Register advice for each subsystem
(dolist (entry gptel-ai-behaviors--subsystem-map)
  (let* ((subsystem (car entry))
         (used-by (plist-get (cdr entry) :used-by))
         (no-prompt (memq subsystem '(autogo champion))))
    (when (and used-by (fboundp (intern used-by)))
      (condition-case nil
          (progn
            (advice-add (intern used-by) :around
                        (gptel-ai-behaviors--advice-inject subsystem no-prompt))
            (when (eq subsystem 'researcher)
              (advice-add (intern used-by) :around
                          #'gptel-ai-behaviors--wrap-research-with-validation)))
        (error nil)))))

;; ─── Concrete Task-Type Tracking for Ontology Evolution ───

(defvar gptel-ai-behaviors--concrete-task-performance (make-hash-table :test 'equal)
  "Hash table: (category . task-type) → (total . kept).")

(defvar gptel-ai-behaviors--concrete-trigger-counts (make-hash-table :test 'equal)
  "Hash table: category → (triggered . total). How often concrete task fallback activates.")

(defun gptel-ai-behaviors--record-concrete-task (category task-type)
  "Record that TASK-TYPE was dispatched for CATEGORY."
  (let* ((key (cons category task-type))
         (entry (gethash key gptel-ai-behaviors--concrete-task-performance (cons 0 0))))
    (setf (car entry) (1+ (car entry)))
    (puthash key entry gptel-ai-behaviors--concrete-task-performance)))

(defun gptel-ai-behaviors--record-concrete-task-outcome (category task-type kept)
  "Record KEPT/DISCARDED for TASK-TYPE on CATEGORY."
  (let* ((key (cons category task-type))
         (entry (gethash key gptel-ai-behaviors--concrete-task-performance (cons 0 0))))
    (when kept
      (setf (cdr entry) (1+ (cdr entry))))
    (puthash key entry gptel-ai-behaviors--concrete-task-performance)))

(defun gptel-ai-behaviors--evolve-concrete-tasks ()
  "Log best task-type per category and diagnose category health.
Compares concrete task keep-rate vs overall experiment keep-rate.
If concrete tasks succeed but regular experiments fail, the category
may need simpler experiments (concrete-task-default mode)."
  (let ((best-per-cat (make-hash-table :test 'equal))
        (results (condition-case nil (gptel-auto-workflow--parse-all-results) (error nil))))
    (maphash
     (lambda (key entry)
       (let* ((category (car key))
              (task-type (cdr key))
              (total (car entry))
              (kept (cdr entry))
              (rate (if (> total 0) (/ (float kept) total) 0)))
         (when (>= total 3)
           (message "[concrete-task] %s/%s: %d/%d kept (%.0f%%)"
                    category task-type kept total (* 100 rate))
           (let ((current (gethash category best-per-cat)))
             (when (or (null current) (> rate (cdr current)))
               (puthash category (cons task-type rate) best-per-cat))))))
     gptel-ai-behaviors--concrete-task-performance)
    ;; Diagnose category health: concrete task vs overall keep-rate
    (when results
      (let ((cat-totals (make-hash-table :test 'equal)))
        (dolist (r results)
          (let* ((r-target (plist-get r :target))
                 (r-decision (plist-get r :decision))
                 (r-kept (equal r-decision "kept"))
                 (cat (and r-target (fboundp 'gptel-auto-workflow--categorize-target)
                          (gptel-auto-workflow--categorize-target r-target))))
            (when cat
              (let ((e (gethash cat cat-totals (cons 0 0))))
                (setf (car e) (+ (car e) (if r-kept 1 0)))
                (setf (cdr e) (1+ (cdr e)))
                (puthash cat e cat-totals)))))
        (maphash
         (lambda (cat total-entry)
           (let* ((overall-kept (car total-entry))
                  (overall-total (cdr total-entry))
                  (overall-rate (if (> overall-total 0) (/ (float overall-kept) overall-total) 0))
                  (best-task-entry (gethash cat best-per-cat))
                  (concrete-rate (if best-task-entry (cdr best-task-entry) 0)))
             (when (and (>= overall-total 5) (> concrete-rate 0))
               (let ((gap (- concrete-rate overall-rate)))
                 (cond
                  ((> gap 0.5)
                   (message "[category-health] ⚠ %s: concrete tasks %.0f%% vs overall %.0f%% (gap %+.0f%%) — prefer simple tasks"
                            cat (* 100 concrete-rate) (* 100 overall-rate) (* 100 gap)))
                  ((< gap -0.3)
                   (message "[category-health] ✓ %s: concrete tasks %.0f%% ≈ overall %.0f%% — category healthy"
                            cat (* 100 concrete-rate) (* 100 overall-rate)))
                  (t
                   (message "[category-health] %s: concrete %.0f%% vs overall %.0f%% (Δ%+.0f%%)"
                            cat (* 100 concrete-rate) (* 100 overall-rate) (* 100 gap))))))))
         cat-totals)))
    (setq gptel-ai-behaviors--best-concrete-tasks best-per-cat)
    ;; Track concrete task trigger rate: how often does each category need
    ;; the deterministic fallback (0 kept, >3 failures)?
    (let ((cat-triggers (make-hash-table :test 'equal))
          (results (condition-case nil (gptel-auto-workflow--parse-all-results) (error nil)))))
      (dolist (r (or results (condition-case nil (gptel-auto-workflow--parse-all-results) (error nil))))
        (let* ((r-target (plist-get r :target))
               (r-decision (plist-get r :decision))
               (r-kept (equal r-decision "kept"))
               (cat (and r-target (fboundp 'gptel-auto-workflow--categorize-target)
                        (gptel-auto-workflow--categorize-target r-target))))
          (when cat
            (let ((e (gethash cat cat-triggers (list :total 0 :kept 0 :failures 0 :consecutive-fail 0))))
              (setf (plist-get e :total) (1+ (plist-get e :total)))
              (if r-kept
                  (progn
                    (setf (plist-get e :kept) (1+ (plist-get e :kept)))
                    (setf (plist-get e :consecutive-fail) 0))
                (setf (plist-get e :failures) (1+ (plist-get e :failures)))
                (setf (plist-get e :consecutive-fail) (1+ (plist-get e :consecutive-fail))))
              (puthash cat e cat-triggers)))))
      (maphash
       (lambda (cat stats)
         (let* ((total (plist-get stats :total))
                (kept (plist-get stats :kept))
                (max-consecutive (plist-get stats :consecutive-fail))
                (trigger-rate (if (> total 0) (/ (float (- total kept)) total) 0)))
           (when (>= total 10)
             (cond
              ((> max-consecutive 5)
               (message "[concrete-trigger] ⚠ %s: %d consecutive failures — target may be broken"
                        cat max-consecutive))
              ((> trigger-rate 0.8)
               (message "[concrete-trigger] ⚠ %s: %.0f%% fail rate — experiments may be too complex"
                        cat (* 100 trigger-rate)))
              (t
               (message "[concrete-trigger] %s: %.0f%% fail rate (max %d consecutive)"
                        cat (* 100 trigger-rate) max-consecutive))))))
        cat-triggers)))

(defvar gptel-ai-behaviors--best-concrete-tasks (make-hash-table :test 'equal)
  "Hash table: category → (task-type . keep-rate). Updated each evolution cycle.")

(defun gptel-ai-behaviors--best-task-for-category (category)
  "Return the best task type symbol for CATEGORY, or nil."
  (let ((best (gethash category gptel-ai-behaviors--best-concrete-tasks)))
    (when best (car best))))

;; ─── Research Priorities Injection ───

(defun gptel-ai-behaviors--inject-research-priorities (orig-fn &rest args)
  "Inject research priorities from ontology/AutoTTS/AutoGo before loading findings."
  (let ((priorities (when (fboundp 'gptel-auto-workflow--format-research-priorities)
                     (gptel-auto-workflow--format-research-priorities))))
    (if priorities
        (concat priorities "\n" (apply orig-fn args))
      (apply orig-fn args))))

;; Register research priorities advice
(when (and (fboundp 'gptel-auto-workflow-load-research-findings)
           (not (advice-member-p #'gptel-ai-behaviors--inject-research-priorities
                                'gptel-auto-workflow-load-research-findings)))
  (advice-add 'gptel-auto-workflow-load-research-findings :around
              #'gptel-ai-behaviors--inject-research-priorities))

;; ─── Think-Intel → Behavior Feedback (Gap 2 closure) ───

(defun gptel-ai-behaviors--parse-think-intel-from-messages ()
  "Scan *Messages* for [think-intel] lines and adjust behavior defaults.
STUCK categories get #=act boost; ACTIVE categories maintain current hashtags.
Returns parsed entries for evolution analysis."
  (let ((results nil))
    (ignore-errors
      (with-current-buffer (or (get-buffer "*Messages*")
                               (error "No *Messages* buffer"))
        (goto-char (point-max))
        (while (re-search-backward
                "^\\[think-intel\\] \\([^|]+\\)|\\([^|]+\\)|\\([^|]+\\)|acts=\\([0-9]+\\)|expl=\\([0-9]+\\)|score=\\([0-9.-]+\\)"
                nil t 50)
          (let* ((category (intern (match-string 1)))
                 (verdict (match-string 3))
                 (acts (string-to-number (match-string 4)))
                 (score (string-to-number (match-string 6))))
            (push (list category verdict acts score) results)))))
    (let ((stuck-cats nil) (active-cats nil))
      (dolist (r results)
        (let ((cat (nth 0 r)) (verdict (nth 1 r)) (acts (nth 2 r)))
          (when (string-prefix-p "STUCK" verdict) (push cat stuck-cats))
          (when (and (> acts 0) (string-match-p "ACTIVE\\|PROGRESS" verdict))
            (push cat active-cats))))
      (dolist (cat (seq-uniq stuck-cats))
        (let* ((current (gptel-ai-behaviors--category-hashtags cat))
               (boosted (if (string-match-p "#=act" current)
                            current (concat current " #=act"))))
          (unless (equal current boosted)
            (push (cons cat boosted) gptel-ai-behaviors--category-defaults)
            (message "[ai-behaviors] STUCK %s → boosting #=act: (+%d)"
                     cat (length (seq-filter (lambda (r) (eq (nth 0 r) cat)) stuck-cats))))))
      (dolist (cat (seq-uniq active-cats))
        (message "[ai-behaviors] ACTIVE %s — maintaining current behaviors" cat)))
    results))

(provide 'gptel-auto-experiment-ai-behaviors)
;;; gptel-auto-experiment-ai-behaviors.el ends here
