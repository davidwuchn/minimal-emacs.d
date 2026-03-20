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

;;; Memory Operations

(defun gptel-benchmark-memory-init ()
  "Initialize mementum directory structure."
  (let ((mem-dir (expand-file-name "memories" gptel-benchmark-memory-dir))
        (know-dir (expand-file-name "knowledge" gptel-benchmark-memory-dir)))
    (unless (file-exists-p mem-dir)
      (make-directory mem-dir t))
    (unless (file-exists-p know-dir)
      (make-directory know-dir t))
    (unless (file-exists-p (expand-file-name "state.md" gptel-benchmark-memory-dir))
      (gptel-benchmark-memory-update-state "Initialized mementum"))))

(defun gptel-benchmark-memory-read-state ()
  "Read working memory state.md."
  (let ((state-file (expand-file-name "state.md" gptel-benchmark-memory-dir)))
    (when (file-exists-p state-file)
      (with-temp-buffer
        (insert-file-contents state-file)
        (buffer-string)))))

(defun gptel-benchmark-memory-update-state (content)
  "Update working memory state.md with CONTENT."
  (let ((state-file (expand-file-name "state.md" gptel-benchmark-memory-dir)))
    (with-temp-file state-file
      (insert content))
    (when gptel-benchmark-memory-auto-commit
      (gptel-benchmark-memory-commit "🔄 update: state"))))

(defun gptel-benchmark-memory-create (slug symbol content)
  "Create a new memory with SLUG, SYMBOL, and CONTENT.
Memory files are <200 words and contain one insight."
  (let* ((symbol-str (alist-get symbol gptel-benchmark-memory-symbols "💡"))
         (mem-file (expand-file-name (format "memories/%s.md" slug)
                                     gptel-benchmark-memory-dir))
         (full-content (format "%s %s\n\n%s" symbol-str slug content)))
    (when (> (length (split-string content)) 200)
      (error "Memory content exceeds 200 words"))
    (with-temp-file mem-file
      (insert full-content))
    (when gptel-benchmark-memory-auto-commit
      (gptel-benchmark-memory-commit (format "%s %s" symbol-str slug)))
    mem-file))

(defun gptel-benchmark-memory-create-knowledge (topic frontmatter content)
  "Create knowledge page for TOPIC with FRONTMATTER and CONTENT.
Knowledge is AI documentation written for future AI sessions."
  (let* ((know-file (expand-file-name (format "knowledge/%s.md" topic)
                                       gptel-benchmark-memory-dir))
         (full-content (format "%s\n\n%s" frontmatter content)))
    (with-temp-file know-file
      (insert full-content))
    (when gptel-benchmark-memory-auto-commit
      (gptel-benchmark-memory-commit (format "💡 %s" topic)))
    know-file))

(defun gptel-benchmark-memory-update (slug content)
  "Update memory SLUG with new CONTENT."
  (let ((mem-file (expand-file-name (format "memories/%s.md" slug)
                                     gptel-benchmark-memory-dir)))
    (unless (file-exists-p mem-file)
      (error "Memory not found: %s" slug))
    (with-temp-file mem-file
      (insert content))
    (when gptel-benchmark-memory-auto-commit
      (gptel-benchmark-memory-commit (format "🔄 update: %s" slug)))))

(defun gptel-benchmark-memory-delete (slug)
  "Delete memory SLUG."
  (let ((mem-file (expand-file-name (format "memories/%s.md" slug)
                                     gptel-benchmark-memory-dir)))
    (unless (file-exists-p mem-file)
      (error "Memory not found: %s" slug))
    (delete-file mem-file)
    (when gptel-benchmark-memory-auto-commit
      (gptel-benchmark-memory-commit (format "❌ delete: %s" slug)))))

(defun gptel-benchmark-memory-search (query &optional depth)
  "Search memories for QUERY with optional DEPTH (fibonacci: 1,2,3,5,8,13).
Uses git grep for semantic search, git log for temporal search."
  (let ((d (or depth 2))
        (results '()))
    ;; Semantic search via git grep
    (call-process "git" nil t nil "grep" "-i" "-l" query "--" 
                  (expand-file-name "mementum/" gptel-benchmark-memory-dir))
    ;; Temporal search via git log
    (call-process "git" nil t nil "log" (format "-n %d" d) "--oneline" "--"
                  (expand-file-name "mementum/memories/" gptel-benchmark-memory-dir)
                  (expand-file-name "mementum/knowledge/" gptel-benchmark-memory-dir))
    results))

(defun gptel-benchmark-memory-read (path)
  "Read memory or knowledge at PATH."
  (let ((full-path (expand-file-name path gptel-benchmark-memory-dir)))
    (when (file-exists-p full-path)
      (with-temp-buffer
        (insert-file-contents full-path)
        (buffer-string)))))

(defun gptel-benchmark-memory-list (&optional type)
  "List all memories of TYPE (memories, knowledge, or all)."
  (let* ((mem-dir (expand-file-name "memories" gptel-benchmark-memory-dir))
         (know-dir (expand-file-name "knowledge" gptel-benchmark-memory-dir))
         (results '()))
    (when (or (eq type 'memories) (eq type 'all) (null type))
      (when (file-exists-p mem-dir)
        (dolist (f (directory-files mem-dir t "\\.md$"))
          (push (list 'memory (file-name-nondirectory f)) results))))
    (when (or (eq type 'knowledge) (eq type 'all) (null type))
      (when (file-exists-p know-dir)
        (dolist (f (directory-files know-dir t "\\.md$"))
          (push (list 'knowledge (file-name-nondirectory f)) results))))
    (nreverse results)))

;;; Synthesis (OODA loop)

(defun gptel-benchmark-memory-synthesize (topic)
  "Synthesize memories about TOPIC into knowledge.
Triggered when >=3 memories exist on same topic."
  (let ((related-memories (gptel-benchmark-memory-search topic)))
    (when (>= (length related-memories) 3)
      (let ((knowledge-content (format "---\ntitle: %s\nstatus: open\nrelated:\n  - %s\n---\n\nSynthesized from %d memories."
                                        topic
                                        (mapconcat #'identity related-memories "\n  - ")
                                        (length related-memories))))
        (gptel-benchmark-memory-create-knowledge topic 
                                                 (format "---\ntitle: %s\nstatus: open\n---\n" topic)
                                                 knowledge-content)))))

;;; Metabolism (Wu Xing aligned)

(defun gptel-benchmark-memory-metabolize (observations)
  "Process OBSERVATIONS through memory metabolism cycle.
Aligned with Wu Xing: observe(Wood) -> memory(Fire) -> synthesize(Earth) -> knowledge(Metal) -> archive(Water)"
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
  (let ((default-directory (or (file-name-directory gptel-benchmark-memory-dir)
                               default-directory)))
    (call-process "git" nil nil nil "add" (expand-file-name "mementum/" gptel-benchmark-memory-dir))
    (call-process "git" nil nil nil "commit" "-m" message)))

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
  (let* ((symbol (alist-get key gptel-benchmark-memory-symbols))
         (slug (format "eight-keys-%s" key))
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