;;; gptel-auto-workflow-mementum.el --- Integrate auto-workflow with mementum -*- lexical-binding: t -*-

;; This module bridges auto-workflow experiments with the mementum memory system.
;; It creates atomic memories per experiment and synthesizes them into knowledge pages.
;;
;; Data flow:
;;   Experiment results ──→ Memories ──→ Knowledge synthesis ──→ Prompt injection
;;        ↓                    ↓              ↓                      ↓
;;     TSV + Git         mementum/      Weekly batch          Executor +
;;                        memories/      job updates           Analyzer
;;                                      knowledge/

(require 'cl-lib)
(require 'subr-x)
(declare-function gptel-auto-workflow--categorize-hypothesis "gptel-auto-workflow-evolution")
(declare-function gptel-auto-workflow--sanitize-llm-output "gptel-auto-workflow-evolution")
(declare-function gptel-auto-workflow--memory-schema-extract-from-file "gptel-auto-workflow-memory-schema")
(declare-function gptel-auto-workflow--git-compute-category-stats "gptel-auto-workflow-git-learning")
(declare-function gptel-auto-workflow--git-compute-target-stats "gptel-auto-workflow-git-learning")
(declare-function gptel-auto-workflow--git-experiment-commits "gptel-auto-workflow-git-learning")
(declare-function gptel-auto-workflow--worktree-base-root "gptel-tools-agent-base")

;; ─── Configuration ───

(defcustom gptel-auto-workflow-mementum-enabled t
  "When non-nil, write experiment results to mementum."
  :type 'boolean
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-mementum-dir "mementum"
  "Base directory for mementum memories and knowledge."
  :type 'directory
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-mementum-memory-dir "mementum/memories"
  "Directory for atomic memory files."
  :type 'directory
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-mementum-knowledge-dir "mementum/knowledge"
  "Directory for synthesized knowledge pages."
  :type 'directory
  :group 'gptel-tools-agent)

;; ─── Memory Creation ───

(defvar gptel-auto-workflow--mementum-symbol-map
  '((💡 . "insight")
    (❌ . "mistake")
    (✅ . "win")
    (🔄 . "shift")
    (🎯 . "decision")
    (🔬 . "research"))
  "Alist mapping emoji symbols to kebab-case filename prefixes.")

(defun gptel-auto-workflow--mementum-symbol-prefix (symbol)
  "Return kebab-case prefix for SYMBOL."
  (or (cdr (assq symbol gptel-auto-workflow--mementum-symbol-map))
      "memory"))

(defun gptel-auto-workflow--mementum-slug (text)
  "Generate a URL-safe slug from TEXT.
Returns empty string if TEXT is nil or empty."
  (let* ((text (or text ""))
         (clean (replace-regexp-in-string "[^a-zA-Z0-9]" "-" text))
         (collapsed (replace-regexp-in-string "-+" "-" clean))
         (slug (downcase (string-trim collapsed "-"))))
    (if (string-empty-p slug)
        "untitled"
      (substring slug 0 (min 80 (length slug))))))

(defvar gptel-auto-workflow--mementum-dedup-cache (make-hash-table :test 'equal)
  "Hash table mapping content SHA-256 → filename.
Used to skip duplicate memory writes without reading every file.
Loaded from .dedup-cache in memory directory on first use.")

(defun gptel-auto-workflow--mementum-dedup-cache-file ()
  "Return path to the dedup cache file."
  (expand-file-name ".dedup-cache"
                    (expand-file-name gptel-auto-workflow-mementum-memory-dir
                                      (gptel-auto-workflow--worktree-base-root))))

(defun gptel-auto-workflow--mementum-load-dedup-cache ()
  "Load dedup cache from file. Returns hash table (empty on failure)."
  (let ((cache (make-hash-table :test 'equal))
        (file (gptel-auto-workflow--mementum-dedup-cache-file)))
    (ignore-errors
      (when (file-exists-p file)
        (with-temp-buffer
          (insert-file-contents file)
          (dolist (line (split-string (buffer-string) "\n" t))
            (when (string-match "\\`\\([a-f0-9]\\{64\\}\\) \\(.+\\)\\'" line)
              (puthash (match-string 1 line) (match-string 2 line) cache))))))
    cache))

(defun gptel-auto-workflow--mementum-save-dedup-cache (cache)
  "Save CACHE (hash table) to the dedup cache file."
  (let ((file (gptel-auto-workflow--mementum-dedup-cache-file)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file
      (maphash (lambda (hash fname)
                 (insert (format "%s %s\n" hash fname)))
               cache))))

(defun gptel-auto-workflow--mementum-dedup-hash (content)
  "Return SHA-256 hex string of CONTENT, or nil if sha512 unavailable."
  (ignore-errors
    (when (and (fboundp 'secure-hash) (stringp content))
      (secure-hash 'sha256 content))))

(defun gptel-auto-workflow--mementum-write-memory (symbol slug content)
  "Write a memory file with SYMBOL prefix and SLUG.
CONTENT is the body text.
Returns the file path, or nil if the content is a
duplicate of an existing memory.
Deduplication uses SHA-256 content hashing
\(inspired by context-mode's EventDedup\)."
  ;; ── Lazy-init dedup cache ──
  (when (= 0 (hash-table-count gptel-auto-workflow--mementum-dedup-cache))
    (setq gptel-auto-workflow--mementum-dedup-cache
          (gptel-auto-workflow--mementum-load-dedup-cache)))
  (let* ((content (or content ""))
         (hash (gptel-auto-workflow--mementum-dedup-hash content))
         (slug (if (string-match-p "/" slug)
                   (replace-regexp-in-string "/" "-" slug)
                 slug))
         (dir (expand-file-name gptel-auto-workflow-mementum-memory-dir
                                (gptel-auto-workflow--worktree-base-root)))
         (prefix (gptel-auto-workflow--mementum-symbol-prefix symbol))
         (file (expand-file-name (format "%s-%s.md" prefix slug) dir)))
    ;; ASSUMPTION: hash-table lookup is sufficient for dedup;
    ;; no need to also check file existence (cache is authoritative)
    ;; EDGE CASE: if hash is nil (secure-hash unavailable), skip dedup
    (if (and hash (gethash hash gptel-auto-workflow--mementum-dedup-cache))
        (progn
          (when (fboundp 'gptel-auto-workflow--log)
            (gptel-auto-workflow--log "[mementum] DEDUP: skipping duplicate memory %s (hash %s)"
                                      slug (substring hash 0 8)))
          nil)
      (progn
        (make-directory dir t)
        (with-temp-file file
          (insert "---\n")
          (insert (format "valid-from: %s\n" (format-time-string "%Y-%m-%dT%H:%M")))
          (insert "---\n\n")
          (insert (format "# %s %s\n\n%s\n\n---\n*Generated by auto-workflow*\n"
                          (pcase symbol
                            ('💡 "Insight:")
                            ('❌ "Mistake:")
                            ('✅ "Win:")
                            ('🔄 "Shift:")
                            ('🎯 "Decision:")
                            ('🔬 "Research:"))
                          (format-time-string "%Y-%m-%d %H:%M")
                          content)))
        (when hash
          (puthash hash file gptel-auto-workflow--mementum-dedup-cache)
          (gptel-auto-workflow--mementum-save-dedup-cache
           gptel-auto-workflow--mementum-dedup-cache))
        (when (fboundp 'gptel-auto-workflow--memory-schema-extract-from-file)
          (gptel-auto-workflow--memory-schema-extract-from-file file))
        (dolist (old (gptel-auto-workflow--mementum-find-superseded slug dir file))
          (gptel-auto-workflow--mementum-supersede-memory old file)
          (when (fboundp 'gptel-auto-workflow--log)
            (gptel-auto-workflow--log "[mementum] SUPERSEDED: %s -> %s"
                                      (file-name-nondirectory old) slug)))
        file))))

(defun gptel-auto-workflow--mementum-record-experiment (experiment)
  "Record EXPERIMENT result to mementum.
EXPERIMENT is a plist with :target :hypothesis :score-before :score-after
:code-quality :decision :grader-quality :grader-reason."
  (when gptel-auto-workflow-mementum-enabled
    (when (not (proper-list-p experiment))
      (error "[mementum] EXPERIMENT must be a proper plist, got: %S" experiment))
    (when (equal (plist-get experiment :decision) "kept")
      (let* ((target (plist-get experiment :target))
             (hypothesis (plist-get experiment :hypothesis))
             (score-before (or (plist-get experiment :score-before) 0.0))
             (score-after (or (plist-get experiment :score-after) 0.0))
             (quality (or (plist-get experiment :code-quality) 0.0))
             (grader-q (or (plist-get experiment :grader-quality) 0))
             (change-type (gptel-auto-workflow--categorize-hypothesis hypothesis))
             (slug (gptel-auto-workflow--mementum-slug
                    (format "%s-%s" target hypothesis))))
        (gptel-auto-workflow--mementum-write-memory
         '✅ slug
         (format "**Target:** %s\n**Change type:** %s\n**Hypothesis:** %s\n**Score:** %.2f → %.2f\n**Quality:** %.2f\n**Grader:** %d/9\n\nThis change was kept because it improved the combined score or had significant quality gains."
                 target change-type hypothesis score-before score-after quality grader-q))))))

(defun gptel-auto-workflow--mementum-record-research (research-result)
  "Record RESEARCH-RESULT to mementum as an atomic memory.
RESEARCH-RESULT is a plist with :findings :targets :kept-count :total-count
:strategy :hash."
  (when gptel-auto-workflow-mementum-enabled
    (when (not (proper-list-p research-result))
      (error "[mementum] RESEARCH-RESULT must be a proper plist, got: %S" research-result))
     (let* ((strategy (or (plist-get research-result :strategy) "default"))
            (findings (or (plist-get research-result :findings) ""))
            (hash (or (plist-get research-result :hash)
                      (when (and (fboundp 'sha1) (not (string-empty-p findings)))
                        (sha1 findings))))
            (hash-str (or hash "no-data")))
       ;; Skip recording when strategy is invalid (none, nil, unknown)
       ;; These indicate missing research context, not actual research strategies
       (when (and (stringp strategy)
                  (not (string-empty-p strategy))
                  (not (member (downcase strategy) '("none" "nil" "unknown"))))
         (let* ((slug (format "%s-%s"
                              (if (string-prefix-p "research-" strategy)
                                  strategy
                                (concat "research-" strategy))
                              (substring hash-str 0 (min 8 (length hash-str)))))
                (targets (plist-get research-result :targets))
                (kept-count (or (plist-get research-result :kept-count) 0))
                (total-count (or (plist-get research-result :total-count) 0))
                (digested (or (plist-get research-result :digested) ""))
                (keep-rate (if (> total-count 0)
                               (/ (float kept-count) total-count)
                             0.0)))
           (gptel-auto-workflow--mementum-write-memory
            '🔬 slug
            (format "**Strategy:** %s\n**Findings hash:** %s\n**Targets:** %s\n**Outcome:** %d/%d kept (%.0f%%)\n\n**Raw Findings:**\n\n%s\n\n**Digested Insights:**\n\n%s\n\n**Meta-learning:** Research quality measured by downstream experiment success."
                    strategy
                    hash
                    (if targets (mapconcat #'identity targets ", ") "none")
                    kept-count
                    total-count
                    (* 100 keep-rate)
                    (gptel-auto-workflow--sanitize-llm-output
                     findings "(raw findings suppressed — contained tool output)")
                    (if (string-empty-p digested)
                        "[No digestion performed]"
                      (gptel-auto-workflow--sanitize-llm-output
                       digested "(digested insights suppressed — contained tool output)")))))))))

;; ─── Knowledge Synthesis ───

(defun gptel-auto-workflow--mementum-read-memories (days)
  "Read memories from the last N DAYS.
Returns list of (file-path . content) cons cells."
  (let* ((dir (expand-file-name gptel-auto-workflow-mementum-memory-dir
                                (gptel-auto-workflow--worktree-base-root)))
         (cutoff (time-subtract (current-time) (days-to-time days)))
         (memories nil))
    (when (file-directory-p dir)
      (dolist (file (directory-files dir t "\\.md$"))
        (let ((mtime (file-attribute-modification-time
                      (file-attributes file))))
          (when (time-less-p cutoff mtime)
            (push (cons file
                        (with-temp-buffer
                          (insert-file-contents file)
                          (buffer-string)))
                  memories)))))
    (nreverse memories)))

(defun gptel-auto-workflow--mementum-memory-valid-p (file)
  "Return non-nil if FILE is a valid (non-superseded) memory.
A memory is invalid if its frontmatter contains a `valid-until' key.
A file without frontmatter is considered valid."
  (with-temp-buffer
    (insert-file-contents file nil 0 1024)
    (goto-char (point-min))
    (if (not (re-search-forward "^---$" nil t 2))
        t
      (let ((frontmatter (buffer-substring (point-min) (point))))
        (not (string-match-p "^valid-until:" frontmatter))))))

(defun gptel-auto-workflow--mementum-read-valid-memories (days)
  "Read valid (non-superseded) memories from the last N DAYS.
Returns list of (file-path . content) cons cells."
  (cl-remove-if-not
   (lambda (entry) (gptel-auto-workflow--mementum-memory-valid-p (car entry)))
   (gptel-auto-workflow--mementum-read-memories days)))

(defun gptel-auto-workflow--mementum-supersede-memory (old-file new-file)
  "Mark OLD-FILE as superseded by NEW-FILE.
Adds `valid-until' and `superseded-by' to OLD-FILE's frontmatter."
  (let ((content (with-temp-buffer
                   (insert-file-contents old-file)
                   (buffer-string)))
        (now (format-time-string "%Y-%m-%dT%H:%M"))
        (new-slug (file-name-nondirectory new-file)))
    (with-temp-file old-file
      (insert content)
      (goto-char (point-min))
      (when (re-search-forward "^---$" nil t 1)
        (forward-line 1)
        (when (re-search-forward "^---$" nil t 1)
          (forward-line -1)
          (insert (format "valid-until: %s\nsuperseded-by: %s\n" now new-slug)))))))

(defun gptel-auto-workflow--mementum-find-superseded (slug dir &optional exclude-file)
  "Find existing memories in DIR matching SLUG that should be superseded.
EXCLUDE-FILE is a file path to exclude (e.g. the new file).
Returns list of file paths."
  (let ((matches nil))
    (when (file-directory-p dir)
      (dolist (file (directory-files dir t "\\.md$"))
        (let ((basename (file-name-nondirectory file)))
          (when (and (string-match-p (regexp-quote slug) basename)
                     (or (not exclude-file)
                         (not (string-equal (file-truename file)
                                            (file-truename exclude-file))))
                     (gptel-auto-workflow--mementum-memory-valid-p file))
            (push file matches)))))
    matches))

(defun gptel-auto-workflow--mementum-synthesize-knowledge ()
  "Synthesize recent memories into knowledge pages.
Updates auto-workflow-evolution.md with patterns from recent experiments."
  (when gptel-auto-workflow-mementum-enabled
    (let* ((memories (gptel-auto-workflow--mementum-read-memories 7))
           (knowledge-dir (expand-file-name gptel-auto-workflow-mementum-knowledge-dir
                                            (gptel-auto-workflow--worktree-base-root)))
           (knowledge-file (expand-file-name "auto-workflow-evolution.md" knowledge-dir))
           ;; Get git stats for synthesis (with nil guard)
           (git-commits (when (fboundp 'gptel-auto-workflow--git-experiment-commits)
                          (gptel-auto-workflow--git-experiment-commits)))
           (target-stats (when git-commits
                           (gptel-auto-workflow--git-compute-target-stats git-commits)))
           (category-stats (when git-commits
                             (gptel-auto-workflow--git-compute-category-stats git-commits))))

      (make-directory knowledge-dir t)

      ;; Build knowledge content
      (with-temp-file knowledge-file
        (insert "---\n")
        (insert "title: Auto-Workflow Evolution Patterns\n")
        (insert (format "status: active\n"))
        (insert "category: knowledge\n")
        (insert "tags: [auto-workflow, benchmark, evolution, patterns]\n")
        (insert "---\n\n")

        (insert "# Auto-Workflow Evolution Patterns\n\n")
        (insert "*This page is automatically synthesized from experiment results and git
history.*\n\n")

        ;; Section 1: Success Patterns by Change Type
        (insert "## Change Type Success Rates\n\n")
        (insert "Based on merged experiment commits (git history):\n\n")
        (dolist (stat category-stats)
          (let* ((cat (nth 0 stat))
                 (total (nth 1 stat))
                 (kept (nth 2 stat))
                 (rate (nth 3 stat))
                 (cat-name (pcase cat
                             ('bug-fix "Bug fixes / error handling")
                             ('performance "Performance improvements")
                             ('refactoring "Refactoring / deduplication")
                             ('safety "Safety / defensive checks")
                             ('feature "New features / enhancements")
                             ('other "Other changes"))))
            (when (> total 0)
              (insert (format "- **%s**: %.0f%% (%d/%d commits)\n"
                              cat-name (* 100 rate) kept total)))))
        (insert "\n")

        ;; Section 2: Target File Patterns
        (insert "## Target File Success Rates\n\n")
        (insert "Files ranked by experiment merge rate:\n\n")
        (dolist (stat target-stats)
          (let* ((target (nth 0 stat))
                 (total (nth 1 stat))
                 (kept (nth 2 stat))
                 (rate (nth 3 stat)))
            (insert (format "- `%s`: %.0f%% (%d/%d experiments)\n"
                            target (* 100 rate) kept total))))
        (insert "\n")

        ;; Section 3: Recent Memories
        (insert "## Recent Experiment Memories\n\n")
        (insert (format "*%d memories from last 7 days:*\n\n" (length memories)))
        (dolist (mem (seq-take memories 10))
          (let* ((file (car mem))
                 (content (cdr mem))
                 (filename (file-name-nondirectory file)))
            (insert (format "### %s\n\n" filename))
            (insert content)
            (insert "\n")))

        ;; Section 4: Recommendations
        (insert "## Recommendations for Next Experiments\n\n")
        (insert "Based on pattern analysis:\n\n")
        ;; Find best target
        (when target-stats
          (let ((best-target (car target-stats)))
            (insert (format "- **Prioritize target**: `%s` (%.0f%% success rate)\n"
                            (nth 0 best-target)
                            (* 100 (nth 3 best-target))))))
        ;; Find best category
        (when category-stats
          (let ((best-cat (car category-stats)))
            (insert (format "- **Prioritize change type**: %s (%.0f%% merge rate)\n"
                            (pcase (nth 0 best-cat)
                              ('bug-fix "bug fixes")
                              ('performance "performance improvements")
                              ('refactoring "refactoring")
                              ('safety "safety checks")
                              ('feature "new features")
                              (_ "other changes"))
                            (* 100 (nth 3 best-cat))))))
        (insert "\n"))

      (message "[auto-workflow] Synthesized knowledge to %s" knowledge-file)
      (when (fboundp 'gptel-auto-workflow--memory-schema-extract-from-file)
        (gptel-auto-workflow--memory-schema-extract-from-file knowledge-file))
      ;; Invalidate auto-workflow-evolution cache
      (when (fboundp 'gptel-auto-workflow--knowledge-cache-invalidate)
        (gptel-auto-workflow--knowledge-cache-invalidate 'auto-workflow-evolution)
        (message "[knowledge-cache] Invalidated auto-workflow-evolution")))))

;; ─── Prompt Integration ───

(defun gptel-auto-workflow--mementum-get-knowledge-for-prompt ()
  "Get synthesized knowledge text for prompt injection.
Returns a string or empty string if no knowledge available.
Uses cache to avoid repeated file reads."
  (let ((cached (when (fboundp 'gptel-auto-workflow--knowledge-cache-get)
                  (gptel-auto-workflow--knowledge-cache-get 'auto-workflow-evolution))))
    (if cached
        (progn
          (message "[knowledge-cache] Hit for auto-workflow-evolution (%d chars)" (length cached))
          cached)
      (let* ((knowledge-file (expand-file-name
                              "mementum/knowledge/auto-workflow-evolution.md"
                              (gptel-auto-workflow--worktree-base-root))))
        (if (file-exists-p knowledge-file)
            (let ((content
                   (with-temp-buffer
                     (insert-file-contents knowledge-file)
                     ;; Skip frontmatter
                     (goto-char (point-min))
                     (when (looking-at "---")
                       (forward-line 1)
                       (while (and (not (eobp)) (not (looking-at "---")))
                         (forward-line 1))
                       (forward-line 1))
                     (let ((content (buffer-string)))
                       (if (> (length content) 2000)
                           (concat (substring content 0 1500)
                                   "\n\n... [truncated for brevity] ...")
                         content)))))
              (when (fboundp 'gptel-auto-workflow--knowledge-cache-set)
                (gptel-auto-workflow--knowledge-cache-set 'auto-workflow-evolution content)
                (message "[knowledge-cache] Miss for auto-workflow-evolution, cached %d chars"
                         (length content)))
              content)
          "")))))

;; ─── Batch Job ───

(defun gptel-auto-workflow-mementum-weekly-job ()
  "Run weekly synthesis of experiment memories into knowledge.
Call this from a cron job or timer."
  (interactive)
  (message "[auto-workflow] Running weekly mementum synthesis...")
  (gptel-auto-workflow--mementum-synthesize-knowledge)
  (message "[auto-workflow] Mementum synthesis complete."))

;; ─── Memory Pruning ───

(defcustom gptel-auto-workflow-mementum-prune-max-age-days 30
  "Memories older than this many days are candidates for pruning.
Pruning keeps the most recent MAX-PER-TOPIC memories per topic and
discards older superseded ones. Memories newer than this are never
pruned regardless of count."
  :type 'integer
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-mementum-prune-max-per-topic 5
  "Maximum number of memories to keep per topic after pruning.
Older memories beyond this count are removed (within max-age constraint).
Prevents single-topic memory explosion (e.g. 37 insight-proposal-strategy-
harness memories cluttering the prompt)."
  :type 'integer
  :group 'gptel-tools-agent)

(defun gptel-auto-workflow--mementum-prune-stale ()
  "Prune stale memories: too old, or too many per topic.
Returns plist with :pruned-count, :kept-count, :topics-affected.

Strategy:
  1. Group memories by topic (extracted from filename)
  2. For each topic, keep newest MAX-PER-TOPIC memories
  3. Among the kept, also discard any older than MAX-AGE-DAYS
  4. Never delete memories referenced in active knowledge pages (TODO: future)

This runs cheaply: O(N) in number of memories, no LLM calls.
Called by `gptel-auto-workflow--mementum-prune-run' from cron."
  (let* ((memories-dir
          (let ((ws-fn (and (fboundp 'gptel-auto-workflow--expand-workspace-path)
                            (symbol-function 'gptel-auto-workflow--expand-workspace-path))))
            (if (functionp ws-fn)
                (expand-file-name
                 gptel-auto-workflow-mementum-memory-dir
                 (funcall ws-fn ""))
              (expand-file-name gptel-auto-workflow-mementum-memory-dir
                                default-directory))))
         (cutoff-time (float-time (time-subtract (current-time)
                                                 (days-to-time gptel-auto-workflow-mementum-prune-max-age-days))))
         (by-topic (make-hash-table :test 'equal))
         (pruned 0)
         (kept 0)
         (topics-affected 0))
    (when (file-directory-p memories-dir)
      ;; Group memory files by topic (slug before .md)
      (dolist (file (directory-files memories-dir t "\\.md$"))
        (let* ((basename (file-name-nondirectory file))
               (mod-time (float-time (nth 5 (file-attributes file))))
               ;; Topic = slug before the trailing discriminator + .md.
               ;; e.g. "insight-proposal-strategy-harness-abc123.md"
               ;;   -> "insight-proposal-strategy-harness"
               (stripped (if (string-match "\\.md$" basename)
                             (substring basename 0 (match-beginning 0))
                           basename))
               ;; Strip trailing -<hex-hash> (4-40 hex chars) or -<number>
               (topic (cond
                       ((string-match "\\-[a-f0-9]\\{4,40\\}$" stripped)
                        (substring stripped 0 (match-beginning 0)))
                       ((string-match "\\-[0-9]+$" stripped)
                        (substring stripped 0 (match-beginning 0)))
                       (t stripped))))
          (when (stringp topic)
            (push (cons file mod-time) (gethash topic by-topic)))))
      ;; For each topic, decide what to keep
      (maphash
        (lambda (_topic files)
         (setq files (cl-sort (copy-sequence files)
                              (lambda (a b) (> (cdr a) (cdr b)))))
          (let* ((keep-newest (seq-take files gptel-auto-workflow-mementum-prune-max-per-topic))
                (cutoff-keep (cl-remove-if (lambda (pair)
                                             (< (cdr pair) cutoff-time))
                                           keep-newest))
                (keep-keys (mapcar #'car cutoff-keep))
                (to-delete (cl-remove-if (lambda (pair)
                                           (member (car pair) keep-keys))
                                         files)))
           (when to-delete
             (setq topics-affected (1+ topics-affected))
             (dolist (pair to-delete)
               (ignore-errors (delete-file (car pair)))
               (setq pruned (1+ pruned))))
           (setq kept (+ kept (length cutoff-keep)))))
       by-topic))
    (list :pruned-count pruned
          :kept-count kept
          :topics-affected topics-affected
          :cutoff-days gptel-auto-workflow-mementum-prune-max-age-days)))

(defun gptel-auto-workflow--mementum-prune-run ()
  "Run mementum memory pruning and write a memory about the result.
Called from `gptel-auto-workflow-cron' or manually."
  (interactive)
  (let* ((result (gptel-auto-workflow--mementum-prune-stale))
         (pruned (plist-get result :pruned-count))
         (kept (plist-get result :kept-count))
         (topics (plist-get result :topics-affected)))
    (message "[mementum] Prune: kept %d, pruned %d across %d topics"
             kept pruned topics)
    (when (> pruned 0)
      (when (fboundp 'gptel-auto-workflow--mementum-write-memory)
        (ignore-errors
          (gptel-auto-workflow--mementum-write-memory
           '✅ (format "mementum-prune-%s" (format-time-string "%Y%m%d"))
           (format "**Mementum pruned %d stale memories** (kept %d across %d topics, max-age=%d days, max-per-topic=%d).\n\nKeeps memory bank bounded; old or over-represented memories removed."
                   pruned kept topics
                   (plist-get result :cutoff-days)
                      gptel-auto-workflow-mementum-prune-max-per-topic)))))
    result))

(provide 'gptel-auto-workflow-mementum)
;;; gptel-auto-workflow-mementum.el ends here
