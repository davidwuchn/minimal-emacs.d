;;; gptel-auto-workflow-evolution.el --- Self-evolution engine using mementum as source of truth -*- lexical-binding: t -*-

;; Architecture:
;;   Git History ──┐
;;                 ├──→ MEMENTUM ──→ Prompt Injection ──→ Experiments ──→ ...
;;   Benchmark ────┘      ↑                                      │
;;                        └──────────────────────────────────────┘
;;
;; Mementum is the SINGLE SOURCE OF TRUTH for self-evolution.
;; Git provides raw facts. Benchmark provides verification.
;; Both feed into mementum. Prompts read from mementum only.

(require 'cl-lib)
(require 'subr-x)

;; External functions from other modules
(declare-function gptel-auto-workflow--worktree-base-root "gptel-tools-agent" ())

;; ─── Helpers ───

(defvar gptel-auto-workflow--evolution-repo-root nil
  "Cached git repository root for self-evolution.
Captured at load time to avoid worktree issues.")

(defun gptel-auto-workflow--evolution-repo-root ()
  "Return the git repository root for self-evolution.
Uses cached value from load time, or detects from current directory."
  (or gptel-auto-workflow--evolution-repo-root
      (setq gptel-auto-workflow--evolution-repo-root
            (string-trim
             (shell-command-to-string
              "git rev-parse --show-toplevel 2>/dev/null || echo ''")))))

;; ─── Benchmark Parsing ───

(defun gptel-auto-workflow--parse-all-results ()
  "Parse all historical results.tsv files into a list of experiment records."
  (let ((results-dir (expand-file-name "var/tmp/experiments"
                                       (gptel-auto-workflow--worktree-base-root)))
        (records nil))
    (when (file-directory-p results-dir)
      (dolist (run-dir (directory-files results-dir t "^202[0-9]-"))
        (let ((tsv-file (expand-file-name "results.tsv" run-dir)))
          (when (file-exists-p tsv-file)
            (with-temp-buffer
              (insert-file-contents tsv-file)
              (goto-char (point-min))
              (forward-line 1)
              (while (not (eobp))
                (let ((line (buffer-substring-no-properties
                             (line-beginning-position) (line-end-position))))
                  (unless (string-empty-p line)
                    (let* ((fields (split-string line "\t"))
                           (target (nth 1 fields))
                           (hypothesis (nth 2 fields))
                           (score-before (string-to-number (or (nth 3 fields) "0")))
                           (score-after (string-to-number (or (nth 4 fields) "0")))
                           (quality (string-to-number (or (nth 5 fields) "0")))
                           (delta-str (or (nth 6 fields) "+0.00"))
                           (decision (nth 7 fields))
                             (grader-q (string-to-number (or (nth 9 fields) "0")))
                             (prompt-chars (string-to-number (or (nth 15 fields) "0"))))
                       (push (list :target target
                                   :hypothesis hypothesis
                                   :score-before score-before
                                   :score-after score-after
                                   :code-quality quality
                                   :delta delta-str
                                   :decision decision
                                   :grader-quality grader-q
                                   :prompt-chars prompt-chars)
                             records))))
                (forward-line 1)))))))
    (nreverse records)))

(defun gptel-auto-workflow--categorize-hypothesis (hypothesis)
  "Categorize HYPOTHESIS into a change type based on keyword matching."
  (let ((text (downcase (or hypothesis ""))))
    (cond
     ;; Safety patterns - check first (more specific)
     ((or (string-match-p "safety\\|defensive\\|type.*check\\|assert\\|sanitize\\|escape\\|validate" text)
          (string-match-p "secure\\|audit\\|harden" text))
      'safety)
     ;; Bug fix patterns
     ((or (string-match-p "bug\\|fix\\|nil\\|error\\|runtime\\|crash\\|prevent\\|guard\\|off-by-one\\|boundary\\|threshold\\|inaccurate" text)
          (string-match-p "safeguard\\|protect\\|check.*nil\\|null\\|missing.*check" text))
      'bug-fix)
     ;; Performance patterns
     ((or (string-match-p "performance\\|cache\\|optimize\\|speed\\|slow\\|complexity\\|hot path\\|efficient" text)
          (string-match-p "reduce.*time\\|faster\\|memory\\|allocation\\|gc" text))
      'performance)
     ;; Refactoring patterns
     ((or (string-match-p "extract\\|duplicate\\|dedup\\|refactor\\|helper\\|rename\\|organiz\\|cleanup" text)
          (string-match-p "consolidat\\|centraliz\\|reus\\|maintainability\\|clarity" text))
      'refactoring)
     ;; Default
     (t 'other))))

;; ─── Configuration ───

(defcustom gptel-auto-workflow-evolution-enabled t
  "When non-nil, enable self-evolution via mementum."
  :type 'boolean
  :group 'gptel-tools-agent)

;; ─── Phase 1: Extract ──→ Git History as Raw Facts ───

(defun gptel-auto-workflow--git-raw-facts ()
  "Extract raw facts from git history.
Returns plist with :merged-commits :abandoned-branches :target-frequency.
Always runs git commands from the main repo root to avoid worktree issues."
  (let* ((repo-root (or (gptel-auto-workflow--evolution-repo-root)
                        (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                             (gptel-auto-workflow--worktree-base-root))))
         (git-cmd (if (and repo-root (not (string-empty-p repo-root)))
                      (format "git -C '%s' " repo-root)
                    "git "))
         (all-branches-raw
          (split-string
           (shell-command-to-string
            (concat git-cmd "branch -r --list 'origin/optimize/*'"))
           "\n" t))
         (all-branches
          (cl-remove-if #'null
                        (mapcar (lambda (b)
                                  (when (string-match "origin/optimize/\\(.+\\)" b)
                                    (match-string 1 b)))
                                all-branches-raw)))
         (merge-commits
          (split-string
           (shell-command-to-string
            (concat git-cmd "log --grep='Merge optimize/' --format='%s'"))
           "\n" t))
         (merged-branches
          (cl-remove-duplicates
           (cl-remove-if (lambda (b) (or (null b) (string-empty-p b)))
                         (mapcar (lambda (m)
                                   (when (string-match "Merge optimize/\\([^ ]+\\)" m)
                                     (match-string 1 m)))
                                 merge-commits))
           :test #'equal))
         (active-merged (cl-intersection all-branches merged-branches :test #'equal))
         (active-abandoned (cl-set-difference all-branches merged-branches :test #'equal)))
    (list :total-active (length all-branches)
          :historical-merges (length merged-branches)
          :active-merged (length active-merged)
          :active-abandoned (length active-abandoned)
          :active-merge-rate (if (> (length all-branches) 0)
                                 (/ (float (length active-merged))
                                    (length all-branches))
                               0.0)
          :target-frequency
          (let ((freq (make-hash-table :test 'equal)))
            (dolist (branch all-branches)
              (let ((target (when (string-match "\\([^-]+\\)" branch)
                              (match-string 1 branch))))
                (when target
                  (puthash target (1+ (gethash target freq 0)) freq))))
            (let (result)
              (maphash (lambda (k v) (push (cons k v) result)) freq)
              (sort result (lambda (a b) (> (cdr a) (cdr b)))))))))

;; ─── Phase 2: Verify ──→ Benchmark as Pattern Validator ───

(defun gptel-auto-workflow--benchmark-verify-patterns (patterns)
  "Verify PATTERNS against benchmark data.
PATTERNS is an alist of (name . hypothesis-function).
Returns alist of (name . verified-score)."
  (let ((records (gptel-auto-workflow--parse-all-results))
        (verified nil))
    (dolist (pattern patterns)
      (let* ((name (car pattern))
             (hypothesis-matcher (cdr pattern))
             (matching (cl-remove-if-not
                        (lambda (r)
                          (funcall hypothesis-matcher (plist-get r :hypothesis)))
                        records))
             (kept (cl-count-if (lambda (r) (string= (plist-get r :decision) "kept"))
                                matching))
             (total (length matching)))
        (push (list name total kept
                    (if (> total 0) (/ (float kept) total) 0.0))
              verified)))
    (nreverse verified)))

;; ─── Phase 2.5: Per-Target Pattern Analysis ───

(defun gptel-auto-workflow--target-pattern-analysis ()
  "Analyze which hypothesis categories succeed for each target.
Returns alist of target → (category success-rate count)."
  (let ((records (gptel-auto-workflow--parse-all-results))
        (target-stats (make-hash-table :test 'equal)))
    ;; Collect per-target category counts
    (dolist (rec records)
      (let* ((target (file-name-nondirectory (or (plist-get rec :target) "unknown")))
             (cat (symbol-name (gptel-auto-workflow--categorize-hypothesis
                                (plist-get rec :hypothesis))))
             (decision (plist-get rec :decision))
             (key (cons target cat)))
        (let ((current (gethash key target-stats '(0 0))))
          (puthash key
                   (list (1+ (nth 0 current))
                         (if (string= decision "kept")
                             (1+ (nth 1 current))
                           (nth 1 current)))
                   target-stats))))
    ;; Convert to sorted alist
    (let ((result nil))
      (maphash (lambda (key data)
                 (let* ((target (car key))
                        (cat (cdr key))
                        (total (nth 0 data))
                        (kept (nth 1 data))
                        (rate (if (> total 0) (/ (float kept) total) 0.0)))
                   (when (>= total 3)
                     (let ((existing (assoc target result)))
                       (if existing
                           (push (list cat rate total) (cdr existing))
                         (push (cons target (list (list cat rate total))) result))))))
               target-stats)
      ;; Sort each target's categories by success rate
      (dolist (item result)
        (setcdr item (sort (cdr item)
                           (lambda (a b) (> (nth 1 a) (nth 1 b))))))
      ;; Sort targets by total experiment count
      (sort result (lambda (a b)
                     (> (cl-reduce #'+ (mapcar (lambda (x) (nth 2 x)) (cdr a)))
                        (cl-reduce #'+ (mapcar (lambda (x) (nth 2 x)) (cdr b)))))))))

(defun gptel-auto-workflow--evolution-pending-drafts ()
  "Scan mementum knowledge drafts and return list of (topic age-days preview)."
  (let* ((drafts-dir (expand-file-name "mementum/knowledge/drafts"
                                       (gptel-auto-workflow--worktree-base-root)))
         (drafts '())
         (now (current-time)))
    (when (file-directory-p drafts-dir)
      (dolist (file (directory-files drafts-dir t "\\.md$"))
        (let* ((topic (file-name-sans-extension (file-name-nondirectory file)))
               (mtime (file-attribute-modification-time (file-attributes file)))
               (age-days (/ (float-time (time-subtract now mtime)) 86400))
               (preview (with-temp-buffer
                          (insert-file-contents file)
                          (goto-char (point-min))
                          (when (looking-at "---")
                            (forward-line 1)
                            (while (not (looking-at "---"))
                              (forward-line 1))
                            (forward-line 1))
                          (buffer-substring (point) (min (+ (point) 300) (point-max))))))
          (push (list topic age-days preview) drafts))))
    ;; Sort by age descending (oldest first)
    (sort drafts (lambda (a b) (> (nth 1 a) (nth 1 b))))))

;; ─── Phase 3: Synthesize ──→ Mementum as Knowledge ───

(defun gptel-auto-workflow--evolution-synthesize ()
  "Synthesize git facts and benchmark verification into skill files.
This is the CENTRAL function of self-evolution.
Writes to optimization-skills/ as skill files that the prompt builder consumes."
  (when gptel-auto-workflow-evolution-enabled
    (let* ((_git-facts (gptel-auto-workflow--git-raw-facts))
            (skills-dir (expand-file-name "assistant/skills/auto-workflow"
                                          (gptel-auto-workflow--worktree-base-root)))
            (_token-skill-file (expand-file-name "token-efficiency.md" skills-dir))
            (_mutation-skill-file (expand-file-name "mutations.md" skills-dir)))

      (make-directory skills-dir t)

      ;; ─── Skill 1: Token Efficiency (SKILL.md for gptel-agent) ───
      (with-temp-file (expand-file-name "SKILL.md" skills-dir)
        (insert "---\n")
        (insert "name: token-efficiency\n")
        (insert "description: Controls prompt compression and section inclusion based on experiment results\n")
        (insert "version: 1.0\n")
        (insert (format "updated: %s\n" (format-time-string "%Y-%m-%d %H:%M")))
        (insert "---\n\n")

        (insert "# Token Efficiency\n\n")
        (insert "This skill auto-evolves based on experiment results.\n")
        (insert "It controls prompt compression and section inclusion.\n\n")

        ;; Section 1: Token Efficiency Analysis
        (insert "## Token Efficiency Analysis\n\n")
        (insert "Correlation between prompt size and experiment success:\n\n")
        (let* ((all-results (gptel-auto-workflow--parse-all-results))
               (with-prompt-data (cl-remove-if (lambda (r) (= 0 (plist-get r :prompt-chars))) all-results))
               (kept-results (cl-remove-if-not (lambda (r) (equal (plist-get r :decision) "kept")) with-prompt-data))
               (discarded-results (cl-remove-if-not (lambda (r) (equal (plist-get r :decision) "discarded")) with-prompt-data)))
          (if (null with-prompt-data)
              (insert "*Insufficient data for token efficiency analysis (need prompt_chars in results).*\n")
            (let* ((avg-kept-prompt (/ (apply #'+ (mapcar (lambda (r) (plist-get r :prompt-chars)) kept-results))
                                       (max 1 (length kept-results))))
                   (avg-discarded-prompt (/ (apply #'+ (mapcar (lambda (r) (plist-get r :prompt-chars)) discarded-results))
                                            (max 1 (length discarded-results))))
                   (efficiency-kept (if (> avg-kept-prompt 0)
                                        (/ (* 100.0 (length kept-results)) avg-kept-prompt)
                                      0))
                   (efficiency-discarded (if (> avg-discarded-prompt 0)
                                             (/ (* 100.0 (length discarded-results)) avg-discarded-prompt)
                                           0)))
              (insert (format "- **Average prompt size (kept):** %d chars\n" avg-kept-prompt))
              (insert (format "- **Average prompt size (discarded):** %d chars\n" avg-discarded-prompt))
              (insert (format "- **Success rate per 1000 chars (kept):** %.2f%%\n" efficiency-kept))
              (insert (format "- **Discarded rate per 1000 chars:** %.2f%%\n" efficiency-discarded))
              (insert (format "- **Optimal prompt range:** %s\n"
                              (if (< avg-kept-prompt avg-discarded-prompt)
                                  (format "Shorter prompts work better (%d vs %d chars)" avg-kept-prompt avg-discarded-prompt)
                                (format "Longer prompts work better (%d vs %d chars)" avg-kept-prompt avg-discarded-prompt))))
              (insert "\n**Prompt Compression Config:**\n")
              (insert (format "- topic-knowledge-max-chars: %d\n" (max 100 (min 800 (- (floor avg-kept-prompt) 3000)))))
              (insert "- compress-behavior: auto\n")
              (insert "- compress-trigger: prompt exceeds optimal size\n"))))
        (insert "\n")

        ;; Section 2: Section A/B Test Results
        (insert "## Section A/B Test Results\n\n")
        (insert "Which prompt sections improve outcomes:\n\n")
        (let* ((all-results (gptel-auto-workflow--parse-all-results))
               (section-stats (make-hash-table :test 'equal)))
          (dolist (result all-results)
            (let ((sections (or (plist-get result :sections-included) "all"))
                  (decision (plist-get result :decision)))
              (dolist (section (split-string sections "," t))
                (let* ((key (string-trim section))
                       (stats (gethash key section-stats (list :with 0 :kept 0))))
                  (puthash key
                           (list :with (1+ (plist-get stats :with))
                                 :kept (if (equal decision "kept")
                                          (1+ (plist-get stats :kept))
                                        (plist-get stats :kept)))
                           section-stats)))))
          (if (= 0 (hash-table-count section-stats))
              (insert "*No A/B test data yet. Run experiments with varying sections.*\n")
            (maphash (lambda (section stats)
                       (let* ((with (plist-get stats :with))
                              (kept (plist-get stats :kept))
                              (rate (if (> with 0) (/ (* 100.0 kept) with) 0)))
                         (insert (format "- **%s**: %.0f%% success (%d/%d experiments)\n"
                                         section rate kept with))))
                     section-stats))
          (insert "\n**Section Inclusion Config:**\n")
          (insert "- default: include all\n")
          (insert "- a-b-test-enabled: t\n")
          (insert "- omit-rate: 0.2\n")
          (insert "- min-samples: 10\n"))
        (insert "\n"))

        ;; Section 4: Token Efficiency Analysis
        (insert "## Token Efficiency Analysis\n\n")
        (insert "Correlation between prompt size and experiment success:\n\n")
        (let* ((all-results (gptel-auto-workflow--parse-all-results))
               (with-prompt-data (cl-remove-if (lambda (r) (= 0 (plist-get r :prompt-chars))) all-results))
               (kept-results (cl-remove-if-not (lambda (r) (equal (plist-get r :decision) "kept")) with-prompt-data))
               (discarded-results (cl-remove-if-not (lambda (r) (equal (plist-get r :decision) "discarded")) with-prompt-data)))
          (if (null with-prompt-data)
              (insert "*Insufficient data for token efficiency analysis (need prompt_chars in results).\n")
            (let* ((avg-kept-prompt (/ (apply #'+ (mapcar (lambda (r) (plist-get r :prompt-chars)) kept-results))
                                       (max 1 (length kept-results))))
                   (avg-discarded-prompt (/ (apply #'+ (mapcar (lambda (r) (plist-get r :prompt-chars)) discarded-results))
                                            (max 1 (length discarded-results))))
                   (efficiency-kept (if (> avg-kept-prompt 0)
                                        (/ (* 100.0 (length kept-results)) avg-kept-prompt)
                                      0))
                   (efficiency-discarded (if (> avg-discarded-prompt 0)
                                             (/ (* 100.0 (length discarded-results)) avg-discarded-prompt)
                                           0)))
              (insert (format "- **Average prompt size (kept):** %d chars\n" avg-kept-prompt))
              (insert (format "- **Average prompt size (discarded):** %d chars\n" avg-discarded-prompt))
              (insert (format "- **Success rate per 1000 chars (kept):** %.2f%%\n" efficiency-kept))
              (insert (format "- **Discarded rate per 1000 chars:** %.2f%%\n" efficiency-discarded))
              (insert (format "- **Optimal prompt range:** %s\n"
                              (if (< avg-kept-prompt avg-discarded-prompt)
                                  (format "Shorter prompts work better (%d vs %d chars)" avg-kept-prompt avg-discarded-prompt)
                                (format "Longer prompts work better (%d vs %d chars)" avg-kept-prompt avg-discarded-prompt))))
              (insert "\n**Recommendations:**\n")
              (insert (format "1. Target prompt size: ~%d chars for best success rate\n" avg-kept-prompt))
              (insert "2. Compress knowledge sections if prompt exceeds optimal size\n")
              (insert "3. Remove low-value sections that increase size without improving outcomes\n"))))
        (insert "\n")

        ;; Section 5: Per-Target Patterns
        (insert "## Per-Target Success Patterns\n\n")
        (insert "Which change types work best for each target file:\n\n")
        (let ((target-analysis (gptel-auto-workflow--target-pattern-analysis)))
          (if (null target-analysis)
              (insert "*Insufficient data for per-target analysis (need ≥3 experiments per target).*\n")
            (dolist (target-data target-analysis)
              (let ((target (car target-data))
                    (patterns (cdr target-data)))
                (insert (format "### `%s`\n\n" target))
                (dolist (pattern (seq-take patterns 3))
                  (let ((cat (nth 0 pattern))
                        (rate (nth 1 pattern))
                        (count (nth 2 pattern)))
                    (insert (format "- **%s**: %.0f%% (%d experiments)\n"
                                    cat (* 100 rate) count))))
                (insert "\n")))))

        ;; Section 5: Auto-Approved Knowledge (Trust-but-Verify)
        (insert "## Auto-Approved Knowledge Pages\n\n")
        (let ((knowledge-dir (expand-file-name "mementum/knowledge"
                                               (gptel-auto-workflow--worktree-base-root)))
              (auto-approved '()))
          (when (file-directory-p knowledge-dir)
            (dolist (file (directory-files knowledge-dir t "\\.md$"))
              (unless (member (file-name-nondirectory file) '("self-evolution.md"))
                (with-temp-buffer
                  (insert-file-contents file)
                  (goto-char (point-min))
                  (when (looking-at "<!--")
                    (let ((topic (file-name-sans-extension (file-name-nondirectory file)))
                          (confidence 0)
                          (sources 0)
                          (warnings nil)
                          (valid nil))
                      (when (re-search-forward "Confidence: \\([0-9]+\\)%" nil t)
                        (setq confidence (string-to-number (match-string 1))))
                      (when (re-search-forward "Sources: \\([0-9]+\\)" nil t)
                        (setq sources (string-to-number (match-string 1))))
                      (when (re-search-forward "Warnings: \\(.+\\)$" nil t)
                        (let ((warn-str (match-string 1)))
                          (unless (string= warn-str "none")
                            (setq warnings (split-string warn-str ", ")))))
                      (when (re-search-forward "Auto-approved: yes (\\(passed\\|flagged\\))" nil t)
                        (setq valid (string= (match-string 1) "passed")))
                      (push (list topic confidence sources warnings valid) auto-approved)))))))
          (if (null auto-approved)
              (insert "*No auto-approved knowledge pages yet.*\n")
            (insert (format "*%d knowledge page(s) auto-approved (trust-but-verify):*\n\n" (length auto-approved)))
            (dolist (page (sort auto-approved (lambda (a b) (> (nth 1 a) (nth 1 b)))))
              (let ((topic (nth 0 page))
                    (confidence (nth 1 page))
                    (sources (nth 2 page))
                    (warnings (nth 3 page))
                    (valid (nth 4 page)))
                (insert (format "### `%s`\n\n" topic))
                (insert (format "- **Confidence:** %d%%\n" confidence))
                (insert (format "- **Sources:** %d memories\n" sources))
                (insert (format "- **Status:** %s\n" (if valid "✓ Passed" "⚠ Flagged")))
                (when warnings
                  (insert (format "- **Warnings:** %s\n" (mapconcat #'identity warnings ", "))))
                (insert "\n")))))
        (insert "\n")

        (insert "## Feedback Loop\n\n")
        (insert "```\n")
        (insert "Experiments → Git History → Facts\n")
        (insert "     ↓            ↓          ↓\n")
        (insert "Benchmark → Verification → MEMENTUM\n")
        (insert "     ↑                           ↓\n")
        (insert "Prompt Injection ← Knowledge ←─┘\n")
        (insert "```\n")))

      (message "[auto-workflow] Synthesized self-evolution skills")
      ;; Invalidate self-evolution cache so next prompt gets fresh knowledge
      (when (fboundp 'gptel-auto-workflow--knowledge-cache-invalidate)
        (gptel-auto-workflow--knowledge-cache-invalidate 'self-evolution)
        (message "[knowledge-cache] Invalidated self-evolution")))

;; ─── Phase 4: Inject ──→ Prompts Read from Mementum ───

(defun gptel-auto-workflow--evolution-get-knowledge ()
  "Get self-evolution knowledge for prompt injection.
This is the ONLY interface between mementum and prompts.
Uses cache to avoid repeated file reads."
  (let ((cached (when (fboundp 'gptel-auto-workflow--knowledge-cache-get)
                  (gptel-auto-workflow--knowledge-cache-get 'self-evolution))))
    (if cached
        (progn
          (message "[knowledge-cache] Hit for self-evolution (%d chars)" (length cached))
          cached)
      (let ((evolution-file (expand-file-name
                             "mementum/knowledge/self-evolution.md"
                             (gptel-auto-workflow--worktree-base-root))))
        (if (file-exists-p evolution-file)
            (let ((content
                   (with-temp-buffer
                     (insert-file-contents evolution-file)
                     (goto-char (point-min))
                     ;; Skip frontmatter
                     (when (looking-at "---")
                       (forward-line 1)
                       (while (not (looking-at "---"))
                         (forward-line 1))
                       (forward-line 1))
                     (buffer-string))))
              (when (fboundp 'gptel-auto-workflow--knowledge-cache-set)
                (gptel-auto-workflow--knowledge-cache-set 'self-evolution content)
                (message "[knowledge-cache] Miss for self-evolution, cached %d chars"
                         (length content)))
              content)
          "")))))

;; ─── Integration ───

(defun gptel-auto-workflow--evolution-consolidate-insights ()
  "Consolidate individual mementum/memories insight files into knowledge pages.
Groups insights by target module, synthesizes patterns, archives old files.
Prevents the linear growth of one-insight-per-file over hundreds of experiments."
  (interactive)
  (cl-block gptel-auto-workflow--evolution-consolidate-insights
  (let* ((repo-root (or (gptel-auto-workflow--evolution-repo-root)
                        default-directory))
         (memories-dir (expand-file-name "mementum/memories" repo-root))
         (knowledge-dir (expand-file-name "mementum/knowledge" repo-root))
         (archive-dir (expand-file-name "archive" memories-dir))
         (insight-files (when (file-directory-p memories-dir)
                          (directory-files memories-dir t "^insight-")))
         (target-groups (make-hash-table :test 'equal))
         (consolidated 0))
    (when (null insight-files)
      (message "[evolution] No insight files to consolidate")
      (cl-return-from gptel-auto-workflow--evolution-consolidate-insights 0))
    ;; First pass: archive low-value staging/verification insights
    (make-directory archive-dir t)
    (dolist (file insight-files)
      (when (string-match-p "staging-" (file-name-nondirectory file))
        (message "[evolution] Skipping low-value insight: %s" (file-name-nondirectory file))
        (rename-file file (expand-file-name (file-name-nondirectory file) archive-dir) t)
        (setq insight-files (delete file insight-files))
        (setq consolidated (1+ consolidated))))
    ;; Second pass: group by target
    (dolist (file insight-files)
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (let* ((full-content (buffer-string))
               (target-key
                (cond
                 ((string-match "\\*\\*Target:\\*\\* \\(.+\\)" full-content)
                  (let ((tgt (match-string 1 full-content)))
                    (if (string-match "lisp/modules/\\(.+\\)" tgt)
                        (file-name-sans-extension (match-string 1 tgt))
                      (replace-regexp-in-string "[ /]" "-" tgt))))
                 ((string-match "^insight-\\([^-]+\\)-\\([^-]+\\)"
                                (file-name-nondirectory file))
                  (format "%s-%s" (match-string 1 (file-name-nondirectory file))
                          (match-string 2 (file-name-nondirectory file))))
                 (t "general")))
               (group (gethash target-key target-groups)))
          (unless group
            (puthash target-key (list :target target-key :count 0 :files nil
                                      :hypotheses nil :decisions nil)
                     target-groups)
            (setq group (gethash target-key target-groups)))
          (plist-put group :count (1+ (plist-get group :count)))
          (push file (plist-get group :files))
          (when (string-match "\\*\\*Decision:\\*\\* \\(.+\\)" full-content)
            (push (match-string 1 full-content) (plist-get group :decisions)))
          (when (string-match "\\*\\*Hypothesis:\\*\\* \\(.+\\)" full-content)
            (push (match-string 1 full-content) (plist-get group :hypotheses))))))
    ;; Synthesize each group into a knowledge page
    (maphash
     (lambda (target-key group)
       (let* ((count (plist-get group :count))
              (decisions (plist-get group :decisions))
              (hypotheses (plist-get group :hypotheses))
              (kept-count (cl-count "kept" (append decisions nil) :test #'string=))
              (kept-hypotheses
               (let ((result nil))
                 (cl-do ((i 0 (1+ i)))
                     ((>= i (length hypotheses)))
                   (when (and (< i (length decisions))
                              (string= (nth i decisions) "kept"))
                     (push (nth i hypotheses) result)))
                 (nreverse result)))
              (knowledge-file (expand-file-name
                               (format "experiment-insights-%s.md" target-key)
                               knowledge-dir)))
         (when (> count 3)
           (make-directory knowledge-dir t)
           (with-temp-file knowledge-file
             (insert "---\n")
             (insert (format "title: Experiment Insights - %s\n" target-key))
             (insert "status: active\n")
             (insert "category: knowledge\n")
             (insert (format "tags: [auto-workflow, experiments, %s]\n"
                             (replace-regexp-in-string "[ /]" "-" target-key)))
             (insert (format "updated: %s\n" (format-time-string "%Y-%m-%d %H:%M")))
             (insert "---\n\n")
             (insert (format "# Experiment Insights: %s\n\n" target-key))
             (insert (format "*Consolidated from %d experiments.*\n\n" count))
             (insert (format "**Keep rate:** %.0f%% (%d kept / %d total)\n\n"
                             (if (> count 0) (* 100 (/ (float kept-count) count)) 0)
                             kept-count count))
             (when kept-hypotheses
               (insert "## Successful Improvements\n\n")
               (dolist (h (seq-take (delete-dups kept-hypotheses) 10))
                 (insert (format "- %s\n" h)))
               (insert "\n"))))
         ;; Archive individual files
         (make-directory archive-dir t)
         (dolist (file (plist-get group :files))
           (rename-file file (expand-file-name (file-name-nondirectory file) archive-dir) t))
         (setq consolidated (+ consolidated count))
         (message "[evolution] Consolidated %d insights for %s → %s"
                  count target-key knowledge-file)))
     target-groups)
    (when (> consolidated 0)
      (message "[evolution] Consolidated %d insight files across %d groups"
               consolidated (hash-table-count target-groups)))
    consolidated)))

(defun gptel-auto-workflow-evolution-run-cycle ()
  "Run one full self-evolution cycle.
Extract → Verify → Synthesize → (Inject happens on next prompt)."
  (interactive)
  (message "[auto-workflow] Running self-evolution cycle...")
  (gptel-auto-workflow--evolution-synthesize)
  (gptel-auto-workflow--evolution-consolidate-insights)
  (message "[auto-workflow] Self-evolution cycle complete."))

;; ─── Init ───

;; Cache repo root at load time to avoid worktree issues later
(when (and (null gptel-auto-workflow--evolution-repo-root)
           (fboundp 'gptel-auto-workflow--evolution-repo-root))
  (gptel-auto-workflow--evolution-repo-root))

(provide 'gptel-auto-workflow-evolution)
;;; gptel-auto-workflow-evolution.el ends here
