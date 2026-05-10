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
                              (prompt-chars (string-to-number (or (nth 15 fields) "0")))
                              (research-strategy (or (nth 20 fields) "none"))
                              (research-hash (or (nth 21 fields) "none")))
                        (push (list :target target
                                    :hypothesis hypothesis
                                    :score-before score-before
                                    :score-after score-after
                                    :code-quality quality
                                    :delta delta-str
                                    :decision decision
                                    :grader-quality grader-q
                                    :prompt-chars prompt-chars
                                    :research-strategy research-strategy
                                    :research-hash research-hash)
                              records))))
                (forward-line 1)))))))
    (nreverse records)))

(defun gptel-auto-workflow--load-evolution-patterns ()
  "Load evolution patterns from skill.
Returns plist with :categories and :predictor, or nil."
  (when (fboundp 'gptel-auto-workflow--load-skill-content)
    (let ((skill (gptel-auto-workflow--load-skill-content "evolution-patterns")))
      (when skill
        (list :categories nil  ; Would parse from skill
              :predictor nil)))))

(defun gptel-auto-workflow--categorize-hypothesis (hypothesis)
  "Categorize HYPOTHESIS into a change type based on keyword matching.
Uses skill patterns if available, otherwise falls back to hardcoded rules."
  (let ((text (downcase (or hypothesis ""))))
    ;; TODO: Use (gptel-auto-workflow--load-evolution-patterns) to extend categories
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
               (insert (format "- **Average prompt size (kept):** %d chars\n" (round avg-kept-prompt)))
               (insert (format "- **Average prompt size (discarded):** %d chars\n" (round avg-discarded-prompt)))
               (insert (format "- **Success rate per 1000 chars (kept):** %.2f%%\n" efficiency-kept))
               (insert (format "- **Discarded rate per 1000 chars:** %.2f%%\n" efficiency-discarded))
               (insert (format "- **Optimal prompt range:** %s\n"
                               (if (< avg-kept-prompt avg-discarded-prompt)
                                   (format "Shorter prompts work better (%d vs %d chars)" (round avg-kept-prompt) (round avg-discarded-prompt))
                                 (format "Longer prompts work better (%d vs %d chars)" (round avg-kept-prompt) (round avg-discarded-prompt)))))
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
               (insert (format "- **Average prompt size (kept):** %d chars\n" (round avg-kept-prompt)))
               (insert (format "- **Average prompt size (discarded):** %d chars\n" (round avg-discarded-prompt)))
               (insert (format "- **Success rate per 1000 chars (kept):** %.2f%%\n" efficiency-kept))
               (insert (format "- **Discarded rate per 1000 chars:** %.2f%%\n" efficiency-discarded))
               (insert (format "- **Optimal prompt range:** %s\n"
                                (if (< avg-kept-prompt avg-discarded-prompt)
                                    (format "Shorter prompts work better (%d vs %d chars)" (round avg-kept-prompt) (round avg-discarded-prompt))
                                  (format "Longer prompts work better (%d vs %d chars)" (round avg-kept-prompt) (round avg-discarded-prompt)))))
               (insert "\n**Recommendations:**\n")
               (insert (format "1. Target prompt size: ~%d chars for best success rate\n" (round avg-kept-prompt)))
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
     ;; Second pass: group by target and score value
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
                                       :hypotheses nil :decisions nil
                                       :scores nil :qualities nil
                                       :values nil :lessons nil)
                      target-groups)
             (setq group (gethash target-key target-groups)))
           (plist-put group :count (1+ (plist-get group :count)))
           (push file (plist-get group :files))
           ;; Extract decision
           (let ((decision (if (string-match "\\*\\*Decision:\\*\\* \\(.+\\)" full-content)
                               (match-string 1 full-content)
                             "unknown")))
             (push decision (plist-get group :decisions)))
           ;; Extract hypothesis
           (when (string-match "\\*\\*Hypothesis:\\*\\* \\(.+\\)" full-content)
             (push (match-string 1 full-content) (plist-get group :hypotheses)))
           ;; Extract score
           (when (string-match "Score:\\*\\* \\([0-9.]+\\)" full-content)
             (push (string-to-number (match-string 1 full-content)) (plist-get group :scores)))
           ;; Extract quality
           (when (string-match "Quality:\\*\\* \\([0-9.]+\\)" full-content)
             (push (string-to-number (match-string 1 full-content)) (plist-get group :qualities)))
           ;; Score insight value (0-10)
           (let ((value 5)) ; start neutral
             ;; Bonus for clear decision
             (when (string-match-p "\\*\\*Decision:\\*\\* \\(kept\\|discarded\\|timeout\\|validation-failed\\|repeated-focus-symbol\\|grader-rejected\\)" full-content)
               (setq value (+ value 2)))
             ;; Bonus for actionable lesson
             (when (string-match-p "Lesson:" full-content)
               (setq value (+ value 3)))
             ;; Bonus for score/quality data
             (when (string-match-p "Score:" full-content)
               (setq value (+ value 1)))
             (when (string-match-p "Quality:" full-content)
               (setq value (+ value 1)))
             ;; Bonus for specific patterns mentioned
             (when (string-match-p "proper-list-p\\|nil guard\\|helper function\\|validation" full-content)
               (setq value (+ value 1)))
             ;; Penalty for empty/generic content
             (when (string-match-p "Unexpected experiment outcome\\.?$" full-content)
               (setq value (- value 4)))
             ;; Penalty for no hypothesis detail
             (when (or (null (plist-get group :hypotheses))
                       (< (length (car (plist-get group :hypotheses))) 20))
               (setq value (- value 2)))
             ;; Clamp to 0-10
             (setq value (max 0 (min 10 value)))
             (push value (plist-get group :values))
             ;; Extract lesson if present
             (when (string-match "Lesson:\\*\\* \\(.+\\)" full-content)
               (push (match-string 1 full-content) (plist-get group :lessons)))))))
     ;; Synthesize each group into a knowledge page
     (maphash
      (lambda (target-key group)
        (let* ((count (plist-get group :count))
               (decisions (plist-get group :decisions))
               (hypotheses (plist-get group :hypotheses))
               (values (plist-get group :values))
               (lessons (plist-get group :lessons))
               (kept-count (cl-count "kept" (append decisions nil) :test #'string=))
               (discarded-count (cl-count "discarded" (append decisions nil) :test #'string=))
               (failed-count (cl-count "validation-failed" (append decisions nil) :test #'string=))
               (timeout-count (cl-count "timeout" (append decisions nil) :test #'string=))
               (avg-value (if values (/ (cl-reduce #'+ values) (float (length values))) 0))
               (kept-hypotheses
                (let ((result nil))
                  (cl-do ((i 0 (1+ i)))
                      ((>= i (length hypotheses)))
                    (when (and (< i (length decisions))
                               (string= (nth i decisions) "kept"))
                      (push (nth i hypotheses) result)))
                  (nreverse result)))
               (discarded-hypotheses
                (let ((result nil))
                  (cl-do ((i 0 (1+ i)))
                      ((>= i (length hypotheses)))
                    (when (and (< i (length decisions))
                               (or (string= (nth i decisions) "discarded")
                                   (string= (nth i decisions) "validation-failed")
                                   (string= (nth i decisions) "timeout")))
                      (push (nth i hypotheses) result)))
                  (nreverse result)))
               (knowledge-file (expand-file-name
                                (format "experiment-insights-%s.md" target-key)
                                knowledge-dir)))
          ;; VALUE GATE: Only create knowledge page if insights have sufficient value
          (when (and (> count 2) (>= avg-value 5.0))
            (make-directory knowledge-dir t)
            (with-temp-file knowledge-file
              (insert "---\n")
              (insert (format "title: Experiment Insights - %s\n" target-key))
              (insert "status: active\n")
              (insert "category: knowledge\n")
              (insert (format "tags: [auto-workflow, experiments, %s]\n"
                              (replace-regexp-in-string "[ /]" "-" target-key)))
              (insert (format "insight-quality: %.1f/10\n" avg-value))
              (insert "---\n\n")
              (insert (format "# Experiment Insights: %s\n\n" target-key))
              (insert (format "*Consolidated from %d experiments (avg insight quality: %.1f/10).*\n\n"
                              count avg-value))
              (insert (format "**Keep rate:** %.0f%% (%d kept / %d discarded / %d failed / %d timeout)\n\n"
                              (if (> count 0) (* 100 (/ (float kept-count) count)) 0)
                              kept-count discarded-count failed-count timeout-count))
              ;; Successful patterns
              (when kept-hypotheses
                (insert "## Successful Patterns (What Works)\n\n")
                (let ((unique-kept (delete-dups kept-hypotheses)))
                  (dolist (h (seq-take unique-kept 5))
                    (insert (format "- %s\n" h)))
                  (insert "\n"))
                (insert "**Why these work:**\n")
                (insert "- Targeted changes to single functions\n")
                (insert "- Clear functional impact (not just style)\n")
                (insert "- Validation guards or bug fixes with measurable improvement\n\n"))
              ;; Failure patterns
              (when discarded-hypotheses
                (insert "## Failure Patterns (What to Avoid)\n\n")
                (let ((unique-failures (delete-dups discarded-hypotheses)))
                  (dolist (h (seq-take unique-failures 5))
                    (insert (format "- %s\n" h)))
                  (insert "\n"))
                (insert "**Why these fail:**\n")
                (insert "- Score tie without quality gain (need ≥0.01 improvement)\n")
                (insert "- Pure refactoring without bug fix (grader sees as style-only)\n")
                (insert "- Introducing undefined functions (Common Lisp symbols in Emacs Lisp)\n")
                (insert "- Complex control flow (catch/throw, non-local exits)\n")
                (insert "- Repeated focus on same function after 2+ non-kept attempts\n\n"))
              ;; Lessons learned
              (when lessons
                (insert "## Key Lessons\n\n")
                (dolist (lesson (seq-take (delete-dups lessons) 8))
                  (insert (format "- %s\n" lesson)))
                (insert "\n"))
              ;; Score predictor
              (insert "## Score Predictor\n\n")
              (insert "| Pattern | Predicts | Confidence |\n")
              (insert "|---------|----------|------------|\n")
              (insert "| Validation guard (proper-list-p, nil check) | KEEP | High |\n")
              (insert "| Bug fix + refactor combo | KEEP | High |\n")
              (insert "| Extract helper alone | DISCARD | Medium |\n")
              (insert "| catch/throw or complex flow | DISCARD | High |\n")
              (insert "| Common Lisp symbols (cw, file, plusp) | VALIDATION-FAILED | Very High |\n")
              (insert "| >50 lines changed | TIMEOUT/DISCARD | Medium |\n")
              (insert "\n"))
            ;; Archive individual files only if knowledge page created
            (make-directory archive-dir t)
            (dolist (file (plist-get group :files))
              (rename-file file (expand-file-name (file-name-nondirectory file) archive-dir) t))
            (setq consolidated (+ consolidated count))
            (message "[evolution] Consolidated %d insights for %s → %s (quality: %.1f/10)"
                     count target-key knowledge-file avg-value))
          ;; If quality too low, just archive without creating knowledge page
          (when (and (> count 2) (< avg-value 5.0))
            (make-directory archive-dir t)
            (dolist (file (plist-get group :files))
              (rename-file file (expand-file-name (file-name-nondirectory file) archive-dir) t))
            (setq consolidated (+ consolidated count))
            (message "[evolution] Archived %d low-value insights for %s (quality: %.1f/10 < 5.0, skipping knowledge page)"
                     count target-key avg-value))))
      target-groups)
     (when (> consolidated 0)
       (message "[evolution] Consolidated %d insight files across %d groups"
                consolidated (hash-table-count target-groups)))
     consolidated)))

;;; ─── Research Evolution ───

(defun gptel-auto-workflow--research-results-by-strategy ()
  "Group experiment results by research strategy.
Returns hash table mapping strategy name to list of results."
  (let ((results (gptel-auto-workflow--parse-all-results))
        (by-strategy (make-hash-table :test 'equal)))
    (dolist (r results)
      (let ((strategy (or (plist-get r :research-strategy) "none")))
        (unless (equal strategy "none")
          (puthash strategy (cons r (gethash strategy by-strategy)) by-strategy))))
    by-strategy))

(defun gptel-auto-workflow--synthesize-research-knowledge (strategy results)
  "Synthesize knowledge page for research STRATEGY from RESULTS.
Returns t if page created."
  (let* ((total (length results))
         (kept (cl-count-if (lambda (r) (equal (plist-get r :decision) "kept")) results))
         (discarded (cl-count-if (lambda (r) (equal (plist-get r :decision) "discarded")) results))
         (failed (cl-count-if (lambda (r) (equal (plist-get r :decision) "validation-failed")) results))
         (keep-rate (if (> total 0) (/ (float kept) total) 0.0))
         (knowledge-dir (expand-file-name "mementum/knowledge"
                                          (gptel-auto-workflow--worktree-base-root)))
         (knowledge-file (expand-file-name
                          (format "research-insights-%s.md" strategy)
                          knowledge-dir)))
    (when (> total 2)
      (make-directory knowledge-dir t)
      (with-temp-file knowledge-file
        (insert "---\n")
        (insert (format "title: Research Insights - %s\n" strategy))
        (insert "status: active\n")
        (insert "category: knowledge\n")
        (insert (format "tags: [research, auto-workflow, %s]\n" strategy))
        (insert (format "insight-quality: %.1f/10\n" (* 10 keep-rate)))
        (insert "---\n\n")
        (insert (format "# Research Strategy: %s\n\n" strategy))
        (insert (format "*Consolidated from %d experiments (%.0f%% keep rate).*%s\n\n"
                        total
                        (* 100 keep-rate)
                        (if (> total 0) "" " No data yet.")))
        (insert (format "**Performance:** %d kept / %d discarded / %d failed\n\n"
                        kept discarded failed))
        ;; Extract successful targets
        (let ((kept-targets (delete-dups
                             (mapcar (lambda (r) (plist-get r :target))
                                     (cl-remove-if-not
                                      (lambda (r) (equal (plist-get r :decision) "kept"))
                                      results)))))
          (when kept-targets
            (insert "## Successful Targets\n\n")
            (dolist (targ (seq-take kept-targets 10))
              (insert (format "- `%s`\n" targ)))
            (insert "\n")))
        ;; Extract failed targets with patterns
        (let ((failed-targets (delete-dups
                               (mapcar (lambda (r) (plist-get r :target))
                                       (cl-remove-if-not
                                        (lambda (r) (equal (plist-get r :decision) "validation-failed"))
                                        results)))))
          (when failed-targets
            (insert "## Targets with Validation Failures\n\n")
            (insert "These targets may need different research patterns or the research findings were misleading.\n\n")
            (dolist (targ (seq-take failed-targets 5))
              (insert (format "- `%s`\n" targ)))
            (insert "\n")))
        ;; Meta-learning recommendations
        (insert "## Meta-Learning Recommendations\n\n")
        (cond
         ((>= keep-rate 0.5)
          (insert "- **This strategy is effective.** Continue using it.\n")
          (insert "- Consider expanding the grep patterns to find similar issues.\n"))
         ((>= keep-rate 0.3)
          (insert "- **This strategy shows promise.** Refine the research prompt.\n")
          (insert "- Focus on more specific code patterns (e.g., specific functions rather than broad categories).\n"))
         ((> total 5)
          (insert "- **This strategy underperforms.** Consider evolving a new approach.\n")
          (insert "- The findings may be too generic or targeting the wrong files.\n")
          (insert "- Try combining with git history for recency bias.\n"))
         (t
          (insert "- **Insufficient data.** Run more experiments with this strategy.\n")))
        (insert "\n"))
      (message "[evolution] Synthesized research knowledge for %s → %s"
               strategy knowledge-file)
      t)))

(defun gptel-auto-workflow--evolution-research-synthesize ()
  "Synthesize research insights from all historical results.
Creates/updates knowledge pages per research strategy."
  (message "[evolution] Synthesizing research insights...")
  (let ((by-strategy (gptel-auto-workflow--research-results-by-strategy))
        (synthesized 0))
    (maphash
     (lambda (strategy results)
       (when (gptel-auto-workflow--synthesize-research-knowledge strategy results)
         (setq synthesized (1+ synthesized))))
     by-strategy)
    (message "[evolution] Synthesized %d research knowledge pages" synthesized)
    synthesized))

(defun gptel-auto-workflow--generate-research-skill ()
  "Generate FINDINGS.md skill file from research knowledge.
This skill is consumed by the researcher prompt builder."
  (let* ((skills-dir (expand-file-name "assistant/skills/auto-workflow"
                                       (gptel-auto-workflow--worktree-base-root)))
         (knowledge-dir (expand-file-name "mementum/knowledge"
                                          (gptel-auto-workflow--worktree-base-root)))
         (skill-file (expand-file-name "FINDINGS.md" skills-dir))
         (knowledge-files (when (file-directory-p knowledge-dir)
                            (directory-files knowledge-dir t "research-insights-.+\\.md$")))
         (best-strategy nil)
         (best-rate 0.0)
         (recent-insights nil)
         (memories-dir (expand-file-name "mementum/memories"
                                         (gptel-auto-workflow--worktree-base-root))))
    ;; Find best performing strategy
    (dolist (kf knowledge-files)
      (with-temp-buffer
        (insert-file-contents kf)
        (goto-char (point-min))
        (when (re-search-forward "Consolidated from \\([0-9]+\\) experiments (\\([0-9.]+\\)% keep rate)" nil t)
          (let ((count (string-to-number (match-string 1)))
                (rate (string-to-number (match-string 2))))
            (when (and (>= count 3) (> rate best-rate))
              (setq best-rate rate
                    best-strategy kf))))))
      ;; Collect recent external research insights from mementum
     (when (file-directory-p memories-dir)
       ;; Read recent 🔬 research memories
       (dolist (mf (directory-files memories-dir t "research-.+\.md$"))
         (let ((mtime (file-attribute-modification-time (file-attributes mf))))
           ;; Only include memories from last 14 days
           (when (time-less-p (time-subtract (current-time) (days-to-time 14)) mtime)
             (with-temp-buffer
               (insert-file-contents mf)
               (goto-char (point-min))
               ;; Extract digested insights section
               (when (re-search-forward "## Digested Insights" nil t)
                 (let ((start (point)))
                   (when (re-search-forward "^## " nil t)
                     (backward-char 3))
                   (push (buffer-substring start (point)) recent-insights))))))))
     ;; Generate skill file
    (make-directory skills-dir t)
    (with-temp-file skill-file
      (insert "---\n")
      (insert "name: research-strategies\n")
      (insert "description: External research insights digested by LLM. Feeds into directive hypotheses.\n")
      (insert "version: 2.0\n")
      (insert "---\n\n")
      (insert "# External Research Insights\n\n")
      (insert "*Digested by LLM from internet sources. Avoid re-researching these topics.*\n\n")
      
      ;; Include recent external insights
      (if recent-insights
          (progn
            (insert "## Recent Discoveries (last 14 days)\n\n")
            (dolist (insight (seq-take recent-insights 5))
              (insert insight)
              (insert "\n---\n\n"))
            (insert "\n"))
        (insert "*No recent external research. Run researcher to discover new ideas.*\n\n"))
      
      ;; Include internal strategy performance
      (insert "## Internal Research Strategy Performance\n\n")
      (insert "*These are our own code-analysis strategies, ranked by experiment success.*\n\n")
      (if best-strategy
          (progn
            (insert (format "**Best strategy:** %.1f%% keep rate\n\n" best-rate))
            (insert "### Effective Internal Patterns\n\n")
            (with-temp-buffer
              (insert-file-contents best-strategy)
              (goto-char (point-min))
              ;; Extract recommendations section
              (when (re-search-forward "## Meta-Learning Recommendations" nil t)
                (forward-line 2)
                (let ((start (point)))
                  (when (re-search-forward "^## " nil t)
                    (backward-char 3))
                  (insert (buffer-substring start (point)))))
              (buffer-string))
            (insert "\n"))
        (insert "*Insufficient internal data. Run more experiments with research-enabled target selection.*\n\n"))
      ;; Include all strategy summaries
      (when knowledge-files
        (insert "## All Strategies\n\n")
        (insert "| Strategy | Experiments | Keep Rate | Status |\n")
        (insert "|----------|-------------|-----------|--------|\n")
        (dolist (kf knowledge-files)
          (with-temp-buffer
            (insert-file-contents kf)
            (goto-char (point-min))
            (let ((strategy (when (re-search-forward "title: Research Insights - \\(.+\\)" nil t)
                             (match-string 1)))
                  (count 0)
                  (rate 0.0))
              (when (re-search-forward "Consolidated from \\([0-9]+\\) experiments (\\([0-9.]+\\)%" nil t)
                (setq count (string-to-number (match-string 1))
                      rate (string-to-number (match-string 2))))
              (when strategy
                (insert (format "| %s | %d | %.0f%% | %s |\n"
                               strategy count rate
                               (cond ((>= rate 50) "✅ Effective")
                                     ((>= rate 30) "🟡 Promising")
                                     ((> count 5) "❌ Underperforms")
                                     (t "⏳ Insufficient data"))))))))))
    (message "[evolution] Generated research skill: %s" skill-file)))

;;; ─── Script-Based Skill Evolution ───
;;
;; Skills now use agentskills.io standard with scripts/ directory.
;; Python scripts handle analysis and generation; Emacs Lisp is thin wrapper.

(defun gptel-auto-workflow--skill-evolution-script-dir ()
  "Return path to skill evolution scripts directory."
  (expand-file-name "assistant/skills/auto-workflow/scripts"
                    (gptel-auto-workflow--worktree-base-root)))

(defun gptel-auto-workflow--run-evolution-script (script-name &rest args)
  "Run SCRIPT-NAME from skill evolution scripts with ARGS.
Returns output string or nil on failure."
  (let* ((script-dir (gptel-auto-workflow--skill-evolution-script-dir))
         (script (expand-file-name script-name script-dir))
         (root (gptel-auto-workflow--worktree-base-root))
         (cmd (format "cd %s && python3 %s %s"
                      (shell-quote-argument root)
                      (shell-quote-argument script)
                      (mapconcat #'shell-quote-argument args " "))))
    (message "[evolution] Running: %s" script-name)
    (let ((output (shell-command-to-string cmd)))
      (if (string-match-p "^\\(?:Error\\|Traceback\\|FAILED\\):\\|failed with\\|failed:" output)
          (progn
            (message "[evolution] Script %s failed: %s" script-name output)
            nil)
        (message "[evolution] %s completed" script-name)
        output))))

(defun gptel-auto-workflow--update-directive-skill ()
  "Update DIRECTIVE.md by calling Python generation script.
Uses analyze_results.py + generate_directive.py pipeline."
  (message "[evolution] Updating directive skill via script...")
  (let ((output (gptel-auto-workflow--run-evolution-script
                 "evolve_skills.py" "--root" ".")))
    (when output
      (message "[evolution] Directive updated: %s"
               (expand-file-name "assistant/skills/auto-workflow/DIRECTIVE.md"
                                (gptel-auto-workflow--worktree-base-root))))
    output))

(defun gptel-auto-workflow--evolve-token-efficiency-skill ()
  "Update token-efficiency skill by calling Python generation script.
Token efficiency is now part of the unified evolution pipeline."
  (message "[evolution] Token-efficiency skill updated via unified evolution script")
  t)

(defun gptel-auto-workflow--load-directive-skill ()
  "Load evolved directive skill content.
Returns string or empty string if not found.
Uses standard skill loader for consistency."
  (let ((content (gptel-auto-workflow--load-skill-content "auto-workflow/DIRECTIVE")))
    (if (string-empty-p content)
        ""
      content)))

;;; ─── Unified Skill Evolution ───

(defun gptel-auto-workflow--evolve-researcher-skill ()
  "Update RESEARCHER.md skill based on research effectiveness.
Analyzes which research topics and sources produce the best downstream results."
  (message "[evolution] Evolving researcher skill...")
  (let* ((results (gptel-auto-workflow--parse-all-results))
         (research-results (cl-remove-if-not
                           (lambda (r)
                             (and (plist-get r :research-hash)
                                  (not (equal (plist-get r :research-hash) "none"))))
                           results))
         (skill-file (expand-file-name "assistant/skills/auto-workflow/RESEARCHER.md"
                                       (gptel-auto-workflow--worktree-base-root)))
         (total-research (length research-results))
         (kept-research (cl-count-if (lambda (r) (equal (plist-get r :decision) "kept"))
                                    research-results))
         (research-keep-rate (if (> total-research 0)
                                (/ (float kept-research) total-research)
                              0.0))
         ;; Analyze which topics are most effective
         (topic-performance (make-hash-table :test 'equal)))
    
    ;; Calculate performance per research topic
    (dolist (r research-results)
      (let ((target (plist-get r :target)))
        (when target
          (let* ((current (gethash target topic-performance))
                 (total (if current (1+ (car current)) 1))
                 (kept (if current
                          (if (equal (plist-get r :decision) "kept")
                              (1+ (cadr current))
                            (cadr current))
                        (if (equal (plist-get r :decision) "kept") 1 0))))
            (puthash target (list total kept) topic-performance)))))
    
    ;; Generate updated researcher skill
    (make-directory (file-name-directory skill-file) t)
    (with-temp-file skill-file
      (insert "---\n")
      (insert "name: auto-workflow-researcher\n")
      (insert "description: External idea hunter for auto-workflow. Searches internet for novel AI agent techniques and digests them for directive skill evolution.\n")
      (insert (format "version: %s\n" (format-time-string "%Y.%m.%d")))
      (insert (format "research-effectiveness: %.1f%%\n" (* 100 research-keep-rate)))
      (insert (format "total-research-experiments: %d\n" total-research))
      (insert "---\n\n")
      (insert "# Auto-Workflow Researcher\n\n")
      (insert "You are an **external research specialist** for an Emacs-based AI agent system.\n")
      (insert "Your job: hunt the internet for novel ideas that could improve our project.\n\n")
      
      ;; Dynamic topics based on performance
      (insert "## Current Research Performance\n\n")
      (insert (format "- Overall research effectiveness: %.1f%% (%d/%d experiments)\n"
                      (* 100 research-keep-rate) kept-research total-research))
      (insert "- Topics ranked by downstream success:\n\n")
      
      ;; Sort topics by keep rate
      (let ((sorted-topics nil))
        (maphash (lambda (target counts)
                   (let ((total (car counts))
                         (kept (cadr counts)))
                     (when (>= total 3)
                       (push (list :target target :rate (/ (float kept) total) :total total :kept kept)
                             sorted-topics))))
                 topic-performance)
        (setq sorted-topics (sort sorted-topics (lambda (a b) (> (plist-get a :rate) (plist-get b :rate)))))
        
        (if sorted-topics
            (dolist (topic (seq-take sorted-topics 10))
              (insert (format "  - `%s`: %.0f%% keep rate (%d/%d)\n"
                              (plist-get topic :target)
                              (* 100 (plist-get topic :rate))
                              (plist-get topic :kept)
                              (plist-get topic :total))))
          (insert "  - No statistically significant data yet (need ≥3 experiments per topic)\n")))
      
      (insert "\n## Mission\n\n")
      (insert "Search external sources for actionable techniques related to:\n")
      (insert "- AI agent architectures and workflows\n")
      (insert "- Emacs Lisp AI integration patterns\n")
      (insert "- LLM self-evolution and meta-learning\n")
      (insert "- Prompt engineering for code generation\n")
      (insert "- Error recovery and retry patterns in agent systems\n")
      (insert "- Benchmarking and evaluation frameworks\n\n")
      
      ;; Priority projects
      (insert "## Priority Projects to Monitor\n\n")
      (insert "### External Projects (Novel Patterns)\n")
      (insert "- **hermes-agent** — Agent orchestration and delegation patterns\n")
      (insert "- **zeroclaw** — Lightweight agent framework design\n")
      (insert "- **ml-intern** — ML-powered coding assistant techniques\n\n")
      (insert "### davidwuchn Repos (Upstream Improvements to Cherry-Pick)\n\n")
      (insert "**Core AI/LLM Infrastructure:**\n")
      (insert "- **https://github.com/davidwuchn/gptel** — LLM client for Emacs; watch for new backends, tool APIs, context management\n")
      (insert "- **https://github.com/davidwuchn/gptel-agent** — Agent mode for gptel; watch for subagent improvements, preset system changes\n")
      (insert "- **https://github.com/davidwuchn/nucleus** — AI prompting framework; watch for benchmark, evaluation, or agent loop changes\n")
      (insert "- **https://github.com/davidwuchn/mementum** — Git as AI Memory; watch for knowledge synthesis improvements\n")
      (insert "- **https://github.com/davidwuchn/ai-behaviors** — Behavior system for LLMs\n")
      (insert "- **https://github.com/davidwuchn/ai-code-interface.el** — Unified Emacs interface for OpenAI Codex, GitHub Copilot CLI, Claude Code, Gemini CLI, Opencode\n\n")
      (insert "**Agent Frameworks:**\n")
      (insert "- **https://github.com/davidwuchn/gastown** — Multi-agent workspace manager\n")
      (insert "- **https://github.com/davidwuchn/gbrain** — Garry's Opinionated OpenClaw/Hermes Agent Brain\n")
      (insert "- **https://github.com/davidwuchn/nullclaw** — Fastest, smallest, fully autonomous AI assistant infrastructure (Zig)\n")
      (insert "- **https://github.com/davidwuchn/zeroclaw** — Fast, small, fully autonomous AI personal assistant (Rust, cross-platform)\n")
      (insert "- **https://github.com/davidwuchn/genesis-agent** — Self-aware cognitive AI agent that reads, modifies \u0026 verifies its own code\n")
      (insert "- **https://github.com/davidwuchn/efrit** — Native elisp coding agent running in Emacs\n")
      (insert "- **https://github.com/davidwuchn/symphony** — Turns project work into isolated, autonomous implementation runs\n")
      (insert "- **https://github.com/davidwuchn/agency-agents** — Complete AI agency with specialized expert agents\n")
      (insert "- **https://github.com/davidwuchn/sem-assistant-el** — Vibecoded Personal Autonomous Assistant\n\n")
      (insert "**Context \u0026 Memory:**\n")
      (insert "- **https://github.com/davidwuchn/context-mode** — Context window optimization, sandboxes tool output, 98% reduction, 14 platforms\n")
      (insert "- **https://github.com/davidwuchn/Ori-Mnemos** — Local-first persistent agentic memory with Recursive Memory Harness\n")
      (insert "- **https://github.com/davidwuchn/verbum** — LLM attention and model architecture exploration\n\n")
      (insert "**Testing \u0026 Evaluation:**\n")
      (insert "- **https://github.com/davidwuchn/promptfoo** — Test prompts, agents, RAGs; AI red teaming and pentesting\n")
      (insert "- **https://github.com/davidwuchn/baml** — AI framework adding engineering to prompt engineering\n")
      (insert "- **https://github.com/davidwuchn/ATLAS** — Adaptive Test-time Learning and Autonomous Specialization\n\n")
      (insert "**Browser \u0026 Tool Integration:**\n")
      (insert "- **https://github.com/davidwuchn/browser** — Lightpanda headless browser for AI/automation\n")
      (insert "- **https://github.com/davidwuchn/browser-harness** — Self-healing harness enabling LLMs to complete any task\n\n")
      (insert "**Code Intelligence:**\n")
      (insert "- **https://github.com/davidwuchn/GitNexus** — Zero-Server Code Intelligence Engine, client-side knowledge graph\n")
      (insert "- **https://github.com/davidwuchn/graphify** — Turn any folder into a queryable knowledge graph\n")
      (insert "- **https://github.com/davidwuchn/LLMLingua** — Compress prompt and KV-Cache up to 20x\n\n")
      (insert "**Emacs \u0026 Lisp:**\n")
      (insert "- **https://github.com/davidwuchn/minimal-emacs.d** — Better Emacs defaults and optimized startup\n")
      (insert "- **https://github.com/davidwuchn/nelisp** — Emacs Lisp VM in pure Elisp + Rust syscall stub\n")
      (insert "- **https://github.com/davidwuchn/anvil.el** — (description TBD)\n")
      (insert "- **https://github.com/davidwuchn/skewed-emacs** — Setup for GNU Emacs, Gendl, and AI\n\n")
      (insert "**Other Languages \u0026 Platforms:**\n")
      (insert "- **https://github.com/davidwuchn/psi** — Extensible AI Agent in Clojure\n")
      (insert "- **https://github.com/davidwuchn/mycelium** — Maestro state machines + Malli contracts for AI graph workflows\n")
      (insert "- **https://github.com/davidwuchn/Aether** — Artificial Ecology For Thought and Emergent Reasoning\n")
      (insert "- **https://github.com/davidwuchn/tinygrad** — Deep learning framework\n")
      (insert "- **https://github.com/davidwuchn/electrobun** — Ultra fast, tiny, cross-platform desktop apps with TypeScript\n")
      (insert "- **https://github.com/davidwuchn/mmllm** — hey-china-hold-my-beer-llm\n")
      (insert "- **https://github.com/davidwuchn/clojure-skills** — Skills and Prompts for Clojure\n")
      (insert "- **https://github.com/davidwuchn/defold** — Free game engine (watch for agent-config patterns)\n")
      (insert "- **https://github.com/davidwuchn/defold-agent-config** — AI-assisted game dev with AGENTS.md and skills\n\n")
      (insert "Check their: recent commits, open issues, closed PRs, architecture decisions\n\n")
      
      ;; Sources
      (insert "## Sources\n\n")
      (insert "- **YouTube**: Recent tutorials on AI agent workflows, Emacs AI integration\n")
      (insert "- **X/Twitter**: Developer discussions on LLM tooling, agent patterns\n")
      (insert "- **GitHub**: Trending repos for ai-agent, emacs-ai, llm-workflow\n")
      (insert "- **arXiv**: Papers on agent architectures, meta-learning, code LLMs\n")
      (insert "- **HuggingFace**: New models, datasets, or spaces for code agents\n")
      (insert "- **Reddit**: r/emacs, r/LocalLLaMA, r/MachineLearning discussions\n\n")
      
      ;; Instructions
      (insert "## Instructions\n\n")
      (insert "1. Use WebSearch tool to find 3-5 recent/relevant items per topic\n")
      (insert "2. Use WebFetch tool to read promising pages/videos (max 3 fetches)\n")
      (insert "3. Focus on NOVEL ideas we haven't implemented (check git history first)\n")
      (insert "4. Extract specific, actionable techniques - not vague trends\n")
      (insert "5. For each insight, provide: source URL, key technique, how it applies to us\n")
      (insert "6. Max 1200 chars. Prioritize depth over breadth.\n")
      (insert "7. **MONITOR SPECIFIC PROJECTS**:\n")
      (insert "   - Check hermes-agent, zeroclaw, ml-intern for novel AI agent patterns\n")
      (insert "   - Check ALL https://github.com/davidwuchn repos for upstream improvements we should cherry-pick\n")
      (insert "   - Prioritize: gptel, gptel-agent, nucleus, mementum, ai-behaviors, ai-code-interface.el, context-mode, gastown, gbrain, nullclaw, genesis-agent, promptfoo, GitNexus, LLMLingua\n")
      (insert "   Look at: recent commits, open issues, closed PRs, architecture decisions\n")
      (insert "   Focus on: patterns we can adapt to our Emacs AI agent system\n\n")
      
      ;; Anti-patterns
      (insert "## Anti-patterns (avoid)\n\n")
      (insert "- Generic advice ('use AI', 'improve code')\n")
      (insert "- Ideas already in our codebase (check git log first)\n")
      (insert "- Purely theoretical without implementation path\n")
      (insert "- Tools requiring heavy external dependencies\n\n")
      
      ;; Auto-evolution note
      (insert "---\n\n")
      (insert "*This researcher skill auto-evolves. Performance data updates every cycle.*\n")
      (insert (format "*Current effectiveness: %.1f%% based on %d research-enabled experiments.*\n"
                      (* 100 research-keep-rate) total-research)))
    
    (message "[evolution] Evolved researcher skill: %s" skill-file)))

(defun gptel-auto-workflow--evolve-all-skills ()
  "Run self-evolution on ALL skills via Python scripts.
This is the main entry point for unified skill evolution.
Uses agentskills.io standard scripts/ directory."
  (message "[evolution] Running unified skill evolution via scripts...")
  
  ;; Single script handles all skill generation
  (let ((output (gptel-auto-workflow--run-evolution-script
                 "evolve_skills.py" "--root" ".")))
    (if output
        (progn
          (message "[evolution] Unified skill evolution complete")
          (message "[evolution] Output:\n%s" output))
      (message "[evolution] Skill evolution failed - check scripts")))
  
  ;; Also run research synthesis (still in Elisp for now)
  (gptel-auto-workflow--evolution-research-synthesize)
  (gptel-auto-workflow--generate-research-skill))

(defun gptel-auto-workflow-evolution-run-cycle ()
  "Run one full self-evolution cycle.
Extract → Verify → Synthesize → Evolve All Skills.
Skill injection happens on the next prompt."
  (interactive)
  (message "[auto-workflow] Running self-evolution cycle...")
  (gptel-auto-workflow--evolution-synthesize)
  (gptel-auto-workflow--evolution-consolidate-insights)
  (gptel-auto-workflow--evolve-all-skills)
  (message "[auto-workflow] Self-evolution cycle complete."))

;; ─── Init ───

;; Cache repo root at load time to avoid worktree issues later
(when (and (null gptel-auto-workflow--evolution-repo-root)
           (fboundp 'gptel-auto-workflow--evolution-repo-root))
  (gptel-auto-workflow--evolution-repo-root))

(provide 'gptel-auto-workflow-evolution)
;;; gptel-auto-workflow-evolution.el ends here
