;;; gptel-benchmark-memory.el --- Mementum-based memory for benchmarking -*- lexical-binding: t; -*-

;; Copyright (C) 2025 David Wu
;; Author: David Wu
;; Version: 1.0.0
;; Keywords: ai, benchmark, memory, mementum

;;; Commentary:

;; Mementum-based memory protocol for AI benchmarking.
;; Uses git as memory substrate with three storage types:
;; - Working memory (state.md) - read first every session
;; - Memories (mementum/memories/) - raw observations, <200 words
;; - Knowledge (mementum/knowledge/) - synthesized documentation
;;
;; Seven operations: create, create-knowledge, update, delete, search, read, synthesize
;; Human governance: AI proposes, human approves, AI commits
;;
;; Integrates with:
;; - Eight Keys (symbols map to memory symbols)
;; - Wu Xing (memory metabolism follows element cycles)
;; - VSM (S4 Intelligence handles memory operations)

;;; Code:

(require 'cl-lib)

;;; Customization

(defgroup gptel-benchmark-memory nil
  "Mementum-based memory for benchmarking."
  :group 'gptel-benchmark)

(defcustom gptel-benchmark-memory-dir "./mementum/"
  "Directory for mementum memory storage."
  :type 'directory
  :group 'gptel-benchmark-memory)

(defcustom gptel-benchmark-memory-auto-commit t
  "Whether to automatically commit memory changes."
  :type 'boolean
  :group 'gptel-benchmark-memory)

(defcustom gptel-benchmark-memory-phi-threshold 0.3
  "Minimum φ (vitality) score for memories.
Memories below this threshold are candidates for pruning."
  :type 'float
  :group 'gptel-benchmark-memory)

(defcustom gptel-benchmark-memory-prune-age-days 30
  "Minimum age in days before a low-φ memory can be pruned.
Prevents pruning of new memories that haven't been validated yet."
  :type 'integer
  :group 'gptel-benchmark-memory)

;;; Memory Symbols (aligned with Eight Keys)

(defconst gptel-benchmark-memory-symbols
  '((insight . "💡")
    (shift . "🔄")
    (decision . "🎯")
    (meta . "🌀")
    (mistake . "❌")
    (win . "✅")
    (pattern . "🔁")
    (vitality . "φ")      ; Eight Keys alignment
    (clarity . "fractal")
    (purpose . "ε")
    (wisdom . "τ")
    (synthesis . "π")
    (directness . "μ")
    (truth . "∃")
    (vigilance . "∀"))
  "Memory symbols for encoding insights.
Core symbols from Mementum + Eight Keys symbols.")

(defun gptel-benchmark-memory--project-root ()
  "Find project root directory.
In batch mode, searches upward from command-line-default-directory.
In interactive mode, uses project.el or falls back to git root."
  (or (when (fboundp 'project-root)
        (when-let ((proj (project-current nil)))
          (project-root proj)))
      (locate-dominating-file default-directory ".git")
      (when noninteractive
        (locate-dominating-file command-line-default-directory ".git"))
      default-directory))

(defun gptel-benchmark-memory--resolve-dir ()
  "Resolve gptel-benchmark-memory-dir to absolute path."
  (let ((root (gptel-benchmark-memory--project-root)))
    (expand-file-name "mementum/" root)))

;;; Memory Operations

(defun gptel-benchmark-memory-init ()
  "Initialize mementum directory structure."
  (let* ((mem-dir (gptel-benchmark-memory--resolve-dir))
         (memories (expand-file-name "memories" mem-dir))
         (knowledge (expand-file-name "knowledge" mem-dir)))
    (unless (file-exists-p memories)
      (make-directory memories t))
    (unless (file-exists-p knowledge)
      (make-directory knowledge t))
    (unless (file-exists-p (expand-file-name "state.md" mem-dir))
      (gptel-benchmark-memory-update-state "Initialized mementum"))))

(defun gptel-benchmark-memory-read-state ()
  "Read working memory state.md."
  (let ((state-file (expand-file-name "state.md" (gptel-benchmark-memory--resolve-dir))))
    (when (file-exists-p state-file)
      (with-temp-buffer
        (insert-file-contents state-file)
        (buffer-string)))))

(defun gptel-benchmark-memory-update-state (content)
  "Update working memory state.md with CONTENT."
  (let ((state-file (expand-file-name "state.md" (gptel-benchmark-memory--resolve-dir))))
    (with-temp-file state-file
      (insert content))
    (when gptel-benchmark-memory-auto-commit
      (gptel-benchmark-memory-commit "🔄 update: state"))))

(defun gptel-benchmark-memory-create (slug symbol content)
  "Create a new memory with SLUG, SYMBOL, and CONTENT.
Memory files are <200 words and contain one insight.
Returns nil and logs warning if content appears to be noise."
  (cl-block gptel-benchmark-memory-create
    (let* ((mem-dir (gptel-benchmark-memory--resolve-dir))
           (symbol-str (alist-get symbol gptel-benchmark-memory-symbols "💡"))
           (mem-file (expand-file-name (format "memories/%s.md" slug) mem-dir))
           (full-content (format "%s %s\n\n%s" symbol-str slug content)))
      (when (> (length (split-string content)) 200)
        (error "Memory content exceeds 200 words"))
      (when (gptel-benchmark-memory--noise-p content)
        (message "[memory] Skipping noise memory: %s" slug)
        (cl-return-from gptel-benchmark-memory-create nil))
      (with-temp-file mem-file
        (insert full-content))
      (when gptel-benchmark-memory-auto-commit
        (gptel-benchmark-memory-commit (format "%s %s" symbol-str slug)))
      mem-file)))

(defun gptel-benchmark-memory--noise-p (content)
  "Check if CONTENT is noise (null results, no insight).
Returns t if content should be rejected."
  (or (string-match-p "0 issues.*0 improvements" content)
      (string-match-p "0 anti-patterns.*0 improvements" content)
      (string-match-p "Observed 0.*applied 0" content)
      (string-match-p "0 → 0 → 0" content)))

(defun gptel-benchmark-memory-audit ()
  "Audit all memories for noise. Return list of noise files."
  (interactive)
  (let* ((mem-dir (expand-file-name "memories/" (gptel-benchmark-memory--resolve-dir)))
         (files (when (file-exists-p mem-dir)
                  (directory-files mem-dir t "\\.md$")))
         (noise-files '()))
    (dolist (file files)
      (let ((content (with-temp-buffer
                       (insert-file-contents file)
                       (buffer-string))))
        (when (gptel-benchmark-memory--noise-p content)
          (push file noise-files))))
    (when (called-interactively-p 'interactive)
      (if noise-files
          (message "[memory] Found %d noise memories: %s" 
                   (length noise-files) 
                   (mapconcat #'file-name-nondirectory noise-files ", "))
        (message "[memory] No noise memories found")))
    noise-files))

;;; Memory Pruning (φ-based quality control)

(defun gptel-benchmark-memory-read-phi (slug)
  "Read φ score from memory SLUG.
Returns 0.5 if no φ metadata found (default)."
  (let* ((mem-dir (gptel-benchmark-memory--resolve-dir))
         (mem-file (expand-file-name (format "memories/%s.md" slug) mem-dir)))
    (if (file-exists-p mem-file)
        (with-temp-buffer
          (insert-file-contents mem-file)
          (goto-char (point-min))
          (if (re-search-forward "^φ:\\s-*\\([0-9.]+\\)" nil t)
              (string-to-number (match-string 1))
            0.5))
      0.5)))

(defun gptel-benchmark-memory-update-phi (slug phi)
  "Update φ score for memory SLUG to PHI.
Adds or updates φ metadata in memory frontmatter."
  (let* ((mem-dir (gptel-benchmark-memory--resolve-dir))
         (mem-file (expand-file-name (format "memories/%s.md" slug) mem-dir)))
    (when (file-exists-p mem-file)
      (let ((content (with-temp-buffer
                       (insert-file-contents mem-file)
                       (buffer-string))))
        (with-temp-file mem-file
          (if (string-match "^φ:\\s-*[0-9.]+" content)
              (insert (replace-match (format "φ: %.2f" phi) t t content))
            (goto-char (point-min))
            (if (string-match "^---" content)
                (progn
                  (forward-line 1)
                  (insert (format "φ: %.2f\n" phi))
                  (insert (substring content (point))))
              (insert (format "φ: %.2f\n\n" phi))
              (insert content))))))))

(defun gptel-benchmark-memory-low-phi-memories ()
  "Find all memories with φ below threshold.
Returns list of (slug phi age-days) for each low-φ memory."
  (let* ((mem-dir (expand-file-name "memories/" (gptel-benchmark-memory--resolve-dir)))
         (files (when (file-exists-p mem-dir)
                  (directory-files mem-dir t "\\.md$")))
         (low-phi '()))
    (dolist (file files)
      (let* ((slug (file-name-nondirectory file))
             (phi (gptel-benchmark-memory-read-phi (file-name-sans-extension slug)))
             (age-days (floor (/ (float-time (time-subtract (current-time)
                                                            (file-attribute-modification-time
                                                             (file-attributes file))))
                                 86400))))
        (when (< phi gptel-benchmark-memory-phi-threshold)
          (push (list (file-name-sans-extension slug) phi age-days) low-phi))))
    (nreverse low-phi)))

(defun gptel-benchmark-memory-prune (&optional dry-run)
  "Prune low-φ memories older than `gptel-benchmark-memory-prune-age-days'.
If DRY-RUN is non-nil, only report what would be pruned without deleting.
Returns list of pruned memories."
  (interactive "P")
  (let* ((low-phi (gptel-benchmark-memory-low-phi-memories))
         (pruned '()))
    (dolist (entry low-phi)
      (cl-destructuring-bind (slug phi age-days) entry
        (when (>= age-days gptel-benchmark-memory-prune-age-days)
          (if dry-run
              (message "[memory] Would prune: %s (φ=%.2f, age=%dd)" slug phi age-days)
            (progn
              (gptel-benchmark-memory-archive slug)
              (push (list slug phi age-days) pruned)
              (message "[memory] Pruned: %s (φ=%.2f, age=%dd)" slug phi age-days))))))
    (when (called-interactively-p 'interactive)
      (if pruned
          (message "[memory] Pruned %d low-φ memories" (length pruned))
        (message "[memory] No memories eligible for pruning")))
    pruned))

(defun gptel-benchmark-memory-archive (slug)
  "Archive memory SLUG by moving to archive directory.
Archived memories are preserved but not active."
  (let* ((mem-dir (gptel-benchmark-memory--resolve-dir))
         (mem-file (expand-file-name (format "memories/%s.md" slug) mem-dir))
         (archive-dir (expand-file-name "memories/archive/" mem-dir))
         (archive-file (expand-file-name (format "%s.md" slug) archive-dir)))
    (unless (file-exists-p archive-dir)
      (make-directory archive-dir t))
    (when (file-exists-p mem-file)
      (rename-file mem-file archive-file t)
      (when gptel-benchmark-memory-auto-commit
        (gptel-benchmark-memory-commit (format "🗄 archive: %s (low φ)" slug))))))

(defun gptel-benchmark-memory-quality-report ()
  "Generate memory quality report based on φ scores.
Shows distribution of φ scores and identifies quality issues."
  (interactive)
  (let* ((mem-dir (expand-file-name "memories/" (gptel-benchmark-memory--resolve-dir)))
         (files (when (file-exists-p mem-dir)
                  (directory-files mem-dir t "\\.md$")))
         (phi-values '())
         (buckets '((0.0 . 0.2) (0.2 . 0.4) (0.4 . 0.6) (0.6 . 0.8) (0.8 . 1.0)))
         (bucket-counts (make-hash-table :test 'equal)))
    (dolist (file files)
      (let ((phi (gptel-benchmark-memory-read-phi
                  (file-name-sans-extension (file-name-nondirectory file)))))
        (push phi phi-values)))
    (dolist (phi phi-values)
      (dolist (bucket buckets)
        (when (and (>= phi (car bucket)) (<= phi (cdr bucket)))
          (puthash bucket (1+ (gethash bucket bucket-counts 0)) bucket-counts))))
    (with-output-to-temp-buffer "*Memory Quality Report*"
      (princ "╔══════════════════════════════════════════════════╗\n")
      (princ "║           MEMORY QUALITY REPORT                  ║\n")
      (princ "╚══════════════════════════════════════════════════╝\n\n")
      (princ (format "Total memories: %d\n\n" (length phi-values)))
      (princ "┌─────────────────────────────────────────────────┐\n")
      (princ "│ φ DISTRIBUTION                                  │\n")
      (princ "├─────────────────────────────────────────────────┤\n")
      (dolist (bucket buckets)
        (let* ((count (gethash bucket bucket-counts 0))
               (bar (make-string (min count 20) ?█))
               (label (format "%.1f-%.1f" (car bucket) (cdr bucket))))
          (princ (format "│ %-7s %-20s %3d              │\n" label bar count))))
      (princ "└─────────────────────────────────────────────────┘\n\n")
      (let ((low-count (length (gptel-benchmark-memory-low-phi-memories))))
        (princ (format "Low-φ memories (below %.2f): %d\n"
                       gptel-benchmark-memory-phi-threshold low-count))
        (when (> low-count 0)
          (princ "\nLow-φ memories:\n")
          (dolist (entry (gptel-benchmark-memory-low-phi-memories))
            (princ (format "  - %s (φ=%.2f, age=%dd)\n"
                           (nth 0 entry) (nth 1 entry) (nth 2 entry)))))))))

(defun gptel-benchmark-memory-create-knowledge (topic frontmatter content)
  "Create knowledge page for TOPIC with FRONTMATTER and CONTENT.
Knowledge is AI documentation written for future AI sessions."
  (let* ((mem-dir (gptel-benchmark-memory--resolve-dir))
         (know-file (expand-file-name (format "knowledge/%s.md" topic) mem-dir))
         (full-content (format "%s\n\n%s" frontmatter content)))
    (with-temp-file know-file
      (insert full-content))
    (when gptel-benchmark-memory-auto-commit
      (gptel-benchmark-memory-commit (format "💡 %s" topic)))
    know-file))

(defun gptel-benchmark-memory-update (slug content)
  "Update memory SLUG with new CONTENT."
  (let* ((mem-dir (gptel-benchmark-memory--resolve-dir))
         (mem-file (expand-file-name (format "memories/%s.md" slug) mem-dir)))
    (unless (file-exists-p mem-file)
      (error "Memory not found: %s" slug))
    (with-temp-file mem-file
      (insert content))
    (when gptel-benchmark-memory-auto-commit
      (gptel-benchmark-memory-commit (format "🔄 update: %s" slug)))))

(defun gptel-benchmark-memory-delete (slug)
  "Delete memory SLUG."
  (let* ((mem-dir (gptel-benchmark-memory--resolve-dir))
         (mem-file (expand-file-name (format "memories/%s.md" slug) mem-dir)))
    (unless (file-exists-p mem-file)
      (error "Memory not found: %s" slug))
    (delete-file mem-file)
    (when gptel-benchmark-memory-auto-commit
      (gptel-benchmark-memory-commit (format "❌ delete: %s" slug)))))

(defun gptel-benchmark-memory-search (query &optional depth)
  "Search memories for QUERY with optional DEPTH (fibonacci: 1,2,3,5,8,13).
Uses git grep for semantic search, git log for temporal search.
Returns list of matching file paths."
  (let* ((mem-dir (gptel-benchmark-memory--resolve-dir))
         (d (or depth 2))
         (grep-regexp (format "--grep=%s" query))
         (results '()))
    (dolist (subdir '("memories" "knowledge"))
      (let ((subdir-path (expand-file-name subdir mem-dir)))
        (when (file-exists-p subdir-path)
          (dolist (file (directory-files-recursively subdir-path "\\.md$"))
            (when (with-temp-buffer
                    (insert-file-contents file)
                    (goto-char (point-min))
                    (re-search-forward query nil t))
              (push file results))))))
    (when (>= (length results) d)
      (nreverse (butlast results (- (length results) d))))
    (nreverse results)))

(defun gptel-benchmark-memory-read (path)
  "Read memory or knowledge at PATH."
  (let ((full-path (expand-file-name path (gptel-benchmark-memory--resolve-dir))))
    (when (file-exists-p full-path)
      (with-temp-buffer
        (insert-file-contents full-path)
        (buffer-string)))))

(defun gptel-benchmark-memory-list (&optional type)
  "List all memories of TYPE (memories, knowledge, or all)."
  (let* ((mem-dir (gptel-benchmark-memory--resolve-dir))
         (memories-dir (expand-file-name "memories" mem-dir))
         (knowledge-dir (expand-file-name "knowledge" mem-dir))
         (results '()))
    (when (or (eq type 'memories) (eq type 'all) (null type))
      (when (file-exists-p memories-dir)
        (dolist (f (directory-files memories-dir t "\\.md$"))
          (push (list 'memory (file-name-nondirectory f)) results))))
    (when (or (eq type 'knowledge) (eq type 'all) (null type))
      (when (file-exists-p knowledge-dir)
        (dolist (f (directory-files knowledge-dir t "\\.md$"))
          (push (list 'knowledge (file-name-nondirectory f)) results))))
    (nreverse results)))

;;; Synthesis (OODA loop)

(defun gptel-benchmark-memory-synthesize (topic)
  "Synthesize memories about TOPIC into knowledge.
Triggered when >=3 memories exist on same topic.
Reads actual memory content and creates proper knowledge page."
  (let* ((related-files (gptel-benchmark-memory-search topic))
         (memories-with-content '()))
    (when (>= (length related-files) 3)
      (dolist (file related-files)
        (let* ((mem-dir (gptel-benchmark-memory--resolve-dir))
               (file-path (if (string-prefix-p "/" file)
                              file
                            (expand-file-name file 
                                             (expand-file-name "memories" mem-dir))))
               (content (when (file-exists-p file-path)
                          (with-temp-buffer
                            (insert-file-contents file-path)
                            (buffer-string)))))
          (when content
            (push (list :file file :content content) memories-with-content))))
      (when (>= (length memories-with-content) 3)
        (let* ((synthesized-content (gptel-benchmark--synthesize-content topic memories-with-content))
               (frontmatter (format "---\ntitle: %s\nstatus: open\ncategory: synthesized\ntags:\n  - %s\nrelated:\n%s\n---\n"
                                    topic topic
                                    (mapconcat (lambda (m) 
                                                 (format "  - %s" (plist-get m :file)))
                                               memories-with-content "\n"))))
          (gptel-benchmark-memory-create-knowledge topic frontmatter synthesized-content)
          (message "[memory] Synthesized %d memories into knowledge: %s" 
                   (length memories-with-content) topic))))))

(defun gptel-benchmark--synthesize-content (topic memories)
  "Create synthesized content from MEMORIES about TOPIC."
  (let ((sections '()))
    (push (format "# %s\n\nSynthesized from %d memories on %s.\n" 
                  topic (length memories) (format-time-string "%Y-%m-%d"))
          sections)
    (push "\n## Key Insights\n\n" sections)
    (dolist (mem memories)
      (let ((content (plist-get mem :content)))
        (push (format "- %s\n" 
                      (or (gptel-benchmark--extract-key-point content)
                          (substring content 0 (min 100 (length content)))))
              sections)))
    (push "\n## Patterns\n\nPatterns identified across memories.\n" sections)
    (push "\n## Actions\n\nRecommended actions based on synthesis.\n" sections)
    (apply #'concat (nreverse sections))))

(defun gptel-benchmark--extract-key-point (content)
  "Extract the key point from CONTENT.
Returns first sentence or nil."
  (when (string-match "^\\(.+?[.!?]\\)" content)
    (match-string 1 content)))

;;; Metabolism (Wu Xing aligned)

(defun gptel-benchmark-memory-metabolize (observations)
  "Process OBSERVATIONS through memory metabolism cycle.
Aligned with Wu Xing: observe(Wood) -> memory(Fire) ->
synthesize(Earth) -> knowledge(Metal) -> archive(Water)."
  (dolist (obs observations)
    (let* ((symbol (plist-get obs :symbol))
           (slug (plist-get obs :slug))
           (content (plist-get obs :content)))
      (gptel-benchmark-memory-create slug symbol content)
      ;; Check if synthesis needed (Fire -> Earth)
      (let ((related (gptel-benchmark-memory-search slug)))
        (when (>= (length related) 3)
          (gptel-benchmark-memory-synthesize slug))))))

;;; Git Integration

(defun gptel-benchmark-memory-commit (message)
  "Commit memory changes with MESSAGE."
  (let* ((root (gptel-benchmark-memory--project-root))
         (mem-dir (expand-file-name "mementum/" root)))
    (let ((default-directory root))
      (call-process "git" nil nil nil "add" mem-dir)
      (call-process "git" nil nil nil "commit" "-m" message))))

;;; λ-Orient (OODA first action)

(defun gptel-benchmark-memory-orient ()
  "Orient to current project state.
Read state.md -> follow related -> search relevant -> read needed.
Should be first action in every session."
  (let ((state (gptel-benchmark-memory-read-state)))
    (when state
      (message "[mementum] State loaded: %d chars" (length state)))
    state))

;;; Integration with Eight Keys

(defun gptel-benchmark-memory-store-eight-keys-insight (key insights)
  "Store Eight Keys INSIGHTS for KEY as memory."
  (let* ((slug (format "eight-keys-%s" key))
         (content (mapconcat #'identity insights "\n")))
    (gptel-benchmark-memory-create slug key content)))

;;; Integration with Wu Xing Diagnostics

(defun gptel-benchmark-memory-store-diagnosis (diagnosis)
  "Store Wu Xing DIAGNOSIS as memory."
  (let ((content (format "Wu Xing diagnosis:\n%s"
                         (mapconcat (lambda (d)
                                      (format "- %s/%s: %.0f%% (%s)"
                                              (plist-get d :element)
                                              (plist-get d :vsm)
                                              (* 100 (plist-get d :score))
                                              (plist-get d :status)))
                                    diagnosis "\n"))))
    (gptel-benchmark-memory-create "wu-xing-diagnosis" 'meta content)))

;;; Provide

(provide 'gptel-benchmark-memory)

;;; gptel-benchmark-memory.el ends here