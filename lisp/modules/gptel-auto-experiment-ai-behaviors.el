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
  (file-directory-p gptel-ai-behaviors-root))

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

(defun gptel-ai-behaviors--category-hashtags (category)
  "Return the hashtag string for CATEGORY (ai-behaviors format)."
  (pcase category
    (:agentic "#=code #contract #checklist #scope #legible #concise")
    (:programming "#=code #subtract #concrete #legible")
    (:tool-calls "#=code #defensive #boundary #robust #legible")
    (:natural-language "#=code #coherence #depth #concrete #legible")
    (_ "#=code #legible #concise")))

(defun gptel-ai-behaviors--inject (category)
  "Resolve hashtags for CATEGORY and return formatted context.
Returns empty string if ai-behaviors repo is not available."
  (when (and category (gptel-ai-behaviors--repo-available-p))
    (let* ((hashtags (gptel-ai-behaviors--category-hashtags category))
           (resolved (gptel-ai-behaviors--expand hashtags))
           (content (car resolved))
           (mode-tag (cdr resolved)))
      (when (> (length content) 0)
        (concat (if mode-tag
                    (format "<operating-mode name=\"%s\">\n%s\n</operating-mode>\n"
                            mode-tag content)
                  (format "<behavior-modifiers>\n%s\n</behavior-modifiers>\n"
                          content))
                "<framework>
HARD CONSTRAINTs define what the current mode IS — they are not overridable.
When a behavior modifier causes you to make a point you would not otherwise make,
mark it: (#name) after the sentence.
</framework>\n")))))

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
     :mode "#=code"
     :description "Write production code. Implement. Do NOT redesign or research."
     :hard-constraints ("code ∩ {UnrequestedFeatures, OverEngineering, UnjustifiedDeps} = ∅"
                        "Read existing code first — match conventions"
                        "Change ONLY what the hypothesis specifies")
     :transition "when task is complete ⊣ {#Review, #Test}")
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
  "Return the N most frequently hit hashtags for CATEGORY.
Returns string of space-separated hashtags, or empty string."
  (when category
    (let ((hits (make-hash-table :test 'equal)))
      (maphash (lambda (key count)
                 (when (eq (car key) category)
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
        (mapconcat #'identity violations "; ")))))

(defun gptel-ai-behaviors--recommend-for-prompt (target)
  "Return formatted recommended behaviors string for TARGET, or empty.
Uses reasoning→behavior mappings from previous experiments."
  (when (and target (fboundp 'gptel-auto-workflow--categorize-target))
    (let* ((category (gptel-auto-workflow--categorize-target target))
           (recs (gptel-ai-behaviors--recommend-behaviors category 3)))
      (when (> (length recs) 0)
        (concat "## Recommended Behaviors (from reasoning patterns)\n"
                "These behaviors were effective in similar experiments:\n"
                "  " recs "\n")))))

(provide 'gptel-auto-experiment-ai-behaviors)
;;; gptel-auto-experiment-ai-behaviors.el ends here
