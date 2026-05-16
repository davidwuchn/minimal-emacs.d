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
(require 'json)
(require 'seq)
(require 'subr-x)

;; External functions from other modules
(declare-function gptel-auto-workflow--worktree-base-root "gptel-tools-agent" ())
(declare-function gptel-auto-workflow--load-skill-content "gptel-tools-agent-prompt-build" (skill-name))

;; AutoTTS-style research evolution via benchmark system
(declare-function gptel-auto-workflow--evolve-research-strategy "gptel-auto-workflow-research-benchmark" ())
(declare-function gptel-auto-workflow--load-autotts-controller "strategic-daemon-functions" ())
(declare-function gptel-auto-workflow--load-research-traces "gptel-auto-workflow-research-benchmark" ())

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

(defun gptel-auto-workflow--evolution-normalize-history (history)
  "Return HISTORY as a plist, accepting legacy alist JSON shapes."
  (cond
   ((not (listp history))
    (list :scores nil :best 0.0))
   ((keywordp (car history))
    history)
   (t
    (let (plist)
      (dolist (entry history)
        (when (consp entry)
          (setq plist (plist-put plist
                                 (intern (format ":%s" (car entry)))
                                 (cdr entry)))))
      plist))))

(defun gptel-auto-workflow--evolution-score-list (scores)
  "Return SCORES as a list of score plists."
  (cond
   ((null scores) nil)
   ((and (listp scores) (keywordp (car scores)))
    (list scores))
   ((and (listp scores)
         (listp (car scores))
         (keywordp (caar scores)))
    scores)
   (t nil)))

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
                               (research-hash (or (nth 21 fields) "none"))
                               (research-quality (or (nth 22 fields) "none")))
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
                                     :research-hash research-hash
                                     :research-quality research-quality)
                               records))))
                (forward-line 1)))))))
    (nreverse records)))

(defvar gptel-auto-workflow--evolution-patterns-cache nil
  "Cached evolution patterns from skill. Reset on skill reload.")

(defun gptel-auto-workflow--load-evolution-patterns ()
  "Load evolution patterns from skill.
Returns plist with :high-signal-keywords (alist of keyword . success-rate)
and :anti-patterns (list of strings), or nil."
  (when (fboundp 'gptel-auto-workflow--load-skill-content)
    (let ((skill (gptel-auto-workflow--load-skill-content "evolution-patterns")))
      (when (and skill (> (length skill) 0))
        (let ((keywords nil)
              (anti-patterns nil))
          (with-temp-buffer
            (insert skill)
            (goto-char (point-min))
            (when (re-search-forward "^### High-Signal Keywords$" nil t)
              (forward-line 1)
              (while (looking-at "^- `\\([^`]+\\)`: \\([0-9]+\\)%")
                (push (cons (match-string 1)
                            (/ (string-to-number (match-string 2)) 100.0))
                      keywords)
                (forward-line 1)))
            (goto-char (point-min))
            (when (re-search-forward "^## Failure Patterns" nil t)
              (forward-line 1)
              (while (looking-at "^- \\(.*\\)$")
                (push (match-string 1) anti-patterns)
                (forward-line 1))))
          (list :high-signal-keywords (nreverse keywords)
                :anti-patterns (nreverse anti-patterns)))))))

(defun gptel-auto-workflow--get-evolution-patterns ()
  "Return cached evolution patterns, loading if needed."
  (or gptel-auto-workflow--evolution-patterns-cache
      (setq gptel-auto-workflow--evolution-patterns-cache
            (gptel-auto-workflow--load-evolution-patterns))))

(defun gptel-auto-workflow--categorize-hypothesis (hypothesis)
  "Categorize HYPOTHESIS into a change type based on keyword matching.
Uses evolved skill patterns when available, with hardcoded fallback."
  (let ((text (downcase (or hypothesis "")))
        (patterns (gptel-auto-workflow--get-evolution-patterns)))
    (cond
     ((and patterns
           (cl-some (lambda (kw)
                      (and (>= (cdr kw) 0.6)
                           (string-match-p (regexp-quote (car kw)) text)
                           (member (car kw) '("defensive" "validate" "sanitize"
                                              "secure" "audit" "harden" "robustness"))
                           t))
                    (plist-get patterns :high-signal-keywords)))
      'safety)
     ((string-match-p "safety\\|defensive\\|type.*check\\|assert\\|sanitize\\|escape\\|validate" text)
      'safety)
     ((string-match-p "secure\\|audit\\|harden" text)
      'safety)
     ((string-match-p "bug\\|fix\\|nil\\|error\\|runtime\\|crash\\|prevent\\|guard\\|off-by-one\\|boundary\\|threshold\\|inaccurate" text)
      'bug-fix)
     ((string-match-p "safeguard\\|protect\\|check.*nil\\|null\\|missing.*check" text)
      'bug-fix)
     ((string-match-p "performance\\|cache\\|optimize\\|speed\\|slow\\|complexity\\|hot path\\|efficient" text)
      'performance)
     ((string-match-p "reduce.*time\\|faster\\|memory\\|allocation\\|gc" text)
      'performance)
     ((string-match-p "extract\\|duplicate\\|dedup\\|refactor\\|helper\\|rename\\|organiz\\|cleanup" text)
      'refactoring)
     ((string-match-p "consolidat\\|centraliz\\|reus\\|maintainability\\|clarity" text)
      'refactoring)
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
              (cl-flet ((collect (k v) (push (cons k v) result)))
                (maphash #'collect freq))
              (sort result (lambda (a b) (> (cdr a) (cdr b)))))))))

;; ─── Phase 2: Verify ──→ Benchmark as Pattern Validator ───

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
      (cl-flet ((collect-target (key data)
                 (let* ((target (car key))
                        (cat (cdr key))
                        (total (nth 0 data))
                        (kept (nth 1 data))
                        (rate (if (> total 0) (/ (float kept) total) 0.0)))
                   (when (>= total 3)
                     (let ((existing (assoc target result)))
                       (if existing
                           (push (list cat rate total) (cdr existing))
                         (push (cons target (list (list cat rate total))) result)))))))
        (maphash #'collect-target target-stats))
      ;; Sort each target's categories by success rate
      (dolist (item result)
        (setcdr item (sort (cdr item)
                           (lambda (a b) (> (nth 1 a) (nth 1 b))))))
      ;; Sort targets by total experiment count
      (sort result (lambda (a b)
                     (> (cl-reduce #'+ (mapcar (lambda (x) (nth 2 x)) (cdr a)))
                        (cl-reduce #'+ (mapcar (lambda (x) (nth 2 x)) (cdr b)))))))))

;; ─── Phase 3: Synthesize ──→ Mementum as Knowledge ───

(defun gptel-auto-workflow--evolution-synthesize ()
  "Synthesize git facts and benchmark verification into skill files.
This is the CENTRAL function of self-evolution.
Writes runtime evolution data under var/tmp/evolution/."
  (when gptel-auto-workflow-evolution-enabled
    (let* ((_git-facts (gptel-auto-workflow--git-raw-facts))
             (knowledge-dir (expand-file-name "mementum/knowledge"
                                              (gptel-auto-workflow--worktree-base-root)))
             (token-skill-file (expand-file-name "var/tmp/evolution/token-efficiency.md"
                                                 (gptel-auto-workflow--worktree-base-root)))
             (skills-dir (expand-file-name "assistant/skills/auto-workflow"
                                           (gptel-auto-workflow--worktree-base-root)))
             (_mutation-skill-file (expand-file-name "mutations.md" skills-dir)))

      (make-directory knowledge-dir t)
      (make-directory (expand-file-name "var/tmp/evolution"
                                        (gptel-auto-workflow--worktree-base-root)) t)

      ;; ─── Token Efficiency Data (runtime generated) ───
      ;; Written to var/tmp/evolution/ as learned data, not a skill definition.
      ;; Loaded directly by prompt builder without skill loader overhead.
      (with-temp-file token-skill-file
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
          (if (or (null with-prompt-data) (null kept-results))
              (insert "*Insufficient data for token efficiency analysis (need kept experiments with prompt_chars).*\n")
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
               (insert "- compress-trigger: prompt exceeds optimal size\n")
               (insert "\n**Recommendations:**\n")
               (insert (format "1. Target prompt size: ~%d chars for best success rate\n" (round avg-kept-prompt)))
               (insert "2. Compress knowledge sections if prompt exceeds optimal size\n")
               (insert "3. Remove low-value sections that increase size without improving outcomes\n"))))
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
            (cl-flet ((log-section (section stats)
                        (let* ((with (plist-get stats :with))
                               (kept (plist-get stats :kept))
                               (rate (if (> with 0) (/ (* 100.0 kept) with) 0)))
                          (insert (format "- **%s**: %.0f%% success (%d/%d experiments)\n"
                                          section rate kept with)))))
              (maphash #'log-section section-stats)))
          (insert "\n**Section Inclusion Config:**\n")
          (insert "- default: include all\n")
          (insert "- a-b-test-enabled: t\n")
          (insert "- omit-rate: 0.2\n")
          (insert "- min-samples: 10\n"))
         (insert "\n"))

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
                        (while (and (not (eobp)) (not (looking-at "---")))
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
                                        :pairs nil :hypotheses nil :decisions nil
                                        :scores nil :qualities nil
                                        :values nil :lessons nil)
                      target-groups)
             (setq group (gethash target-key target-groups)))
           (setq group (plist-put group :count (1+ (plist-get group :count))))
           (setq group (plist-put group :files (cons file (plist-get group :files))))
           (let ((decision (if (string-match "\\*\\*Decision:\\*\\* \\(.+\\)" full-content)
                               (match-string 1 full-content)
                             "unknown"))
                 (hypothesis (when (string-match "\\*\\*Hypothesis:\\*\\* \\(.+\\)" full-content)
                               (match-string 1 full-content))))
             (setq group (plist-put group :pairs (cons (cons decision hypothesis) (plist-get group :pairs))))
             (setq group (plist-put group :decisions (cons decision (plist-get group :decisions))))
             (when hypothesis
               (setq group (plist-put group :hypotheses (cons hypothesis (plist-get group :hypotheses))))))
           (when (string-match "Score:\\*\\* \\([0-9.]+\\)" full-content)
             (setq group (plist-put group :scores (cons (string-to-number (match-string 1 full-content)) (plist-get group :scores)))))
           (when (string-match "Quality:\\*\\* \\([0-9.]+\\)" full-content)
             (setq group (plist-put group :qualities (cons (string-to-number (match-string 1 full-content)) (plist-get group :qualities)))))
           (let ((value 5))
             (when (string-match-p "\\*\\*Decision:\\*\\* \\(kept\\|discarded\\|timeout\\|validation-failed\\|repeated-focus-symbol\\|grader-rejected\\)" full-content)
               (setq value (+ value 2)))
             (when (string-match-p "Lesson:" full-content)
               (setq value (+ value 3)))
             (when (string-match-p "Score:" full-content)
               (setq value (+ value 1)))
             (when (string-match-p "Quality:" full-content)
               (setq value (+ value 1)))
             (when (string-match-p "proper-list-p\\|nil guard\\|helper function\\|validation" full-content)
               (setq value (+ value 1)))
             (when (string-match-p "Unexpected experiment outcome\\.?$" full-content)
               (setq value (- value 4)))
             (when (or (null (plist-get group :hypotheses))
                       (< (length (car (plist-get group :hypotheses))) 20))
               (setq value (- value 2)))
             (setq value (max 0 (min 10 value)))
             (setq group (plist-put group :values (cons value (plist-get group :values))))
             (when (string-match "Lesson:\\*\\* \\(.+\\)" full-content)
               (setq group (plist-put group :lessons (cons (match-string 1 full-content) (plist-get group :lessons))))))
            (puthash target-key group target-groups)))
     ;; Synthesize each group into a knowledge page
     (maphash
       (lambda (target-key group)
         (let* ((count (plist-get group :count))
                (decisions (plist-get group :decisions))
                (pairs (plist-get group :pairs))
                (values (plist-get group :values))
                (lessons (plist-get group :lessons))
                (kept-count (cl-count "kept" (append decisions nil) :test #'string=))
                (discarded-count (cl-count "discarded" (append decisions nil) :test #'string=))
                (failed-count (cl-count "validation-failed" (append decisions nil) :test #'string=))
                (timeout-count (cl-count "timeout" (append decisions nil) :test #'string=))
                (avg-value (if values (/ (cl-reduce #'+ values) (float (length values))) 0))
                (kept-hypotheses
                 (delq nil (mapcar (lambda (p)
                                     (when (string= (car p) "kept") (cdr p)))
                                   (append pairs nil))))
                (discarded-hypotheses
                 (delq nil (mapcar (lambda (p)
                                     (when (member (car p) '("discarded" "validation-failed" "timeout"))
                                       (cdr p)))
                                   (append pairs nil))))
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
      consolidated))))

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

(defun gptel-auto-workflow--sanitize-strategy-name-for-filename (name)
  "Sanitize strategy NAME for use as a filename component.
Replaces characters unsafe in filenames (brackets, quotes, spaces, colons,
semicolons, pipes) with hyphens, collapses multiple hyphens, and strips
leading/trailing hyphens."
  (let ((s (replace-regexp-in-string "[][{}()'\" \t:;|<>/*?\\%!#&]" "-" (or name "none"))))
    (setq s (replace-regexp-in-string "-+" "-" s))
    (setq s (replace-regexp-in-string "^-\\|-$" "" s))
    (if (string-empty-p s) "none" s)))

(defun gptel-auto-workflow--valid-research-strategy-name-p (name)
  "Return non-nil when NAME is safe to synthesize as a research strategy.

Historical TSV rows can contain diagnostic strings such as rejected strategy
evolution messages.  Those are useful logs, but they must not become active
knowledge pages or YAML tags."
  (and (stringp name)
       (let ((trimmed (string-trim name)))
         (and (not (string-empty-p trimmed))
              (not (member (downcase trimmed) '("none" "nil" "unknown")))
              (not (string-match-p "\\`[[]strategy-evolution[]]" trimmed))
              (not (string-match-p "\\bREJECTED\\b" trimmed))
              (string-match-p "\\`[[:alnum:]][[:alnum:]_-]*\\'" trimmed)))))

(defun gptel-auto-workflow--synthesize-research-knowledge (strategy results)
  "Synthesize knowledge page for research STRATEGY from RESULTS.
Returns t if page created."
  (let* ((strategy-name (and (stringp strategy) (string-trim strategy)))
         (total (length results))
         (kept (cl-count-if (lambda (r) (equal (plist-get r :decision) "kept")) results))
         (discarded (cl-count-if (lambda (r) (equal (plist-get r :decision) "discarded")) results))
         (failed (cl-count-if (lambda (r) (equal (plist-get r :decision) "validation-failed")) results))
         (keep-rate (if (> total 0) (/ (float kept) total) 0.0))
         (safe-strategy (gptel-auto-workflow--sanitize-strategy-name-for-filename strategy-name))
         (knowledge-dir (expand-file-name "mementum/knowledge"
                                           (gptel-auto-workflow--worktree-base-root)))
         (knowledge-file (expand-file-name
                          (format "research-insights-%s.md" safe-strategy)
                          knowledge-dir)))
    (when (and (gptel-auto-workflow--valid-research-strategy-name-p strategy-name)
               (> total 2)
               (> kept 0))
      (make-directory knowledge-dir t)
      (with-temp-file knowledge-file
        (insert "---\n")
        (insert (format "title: Research Insights - %s\n" strategy-name))
        (insert "status: active\n")
        (insert "category: knowledge\n")
        (insert (format "tags: [research, auto-workflow, %s]\n" strategy-name))
        (insert (format "insight-quality: %.1f/10\n" (* 10 keep-rate)))
        (insert "---\n\n")
        (insert (format "# Research Strategy: %s\n\n" strategy-name))
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
          (insert "- **Insufficient data.** Run more experiments with this strategy.\n"))))
      (message "[evolution] Synthesized research knowledge for %s → %s"
               strategy-name knowledge-file)
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
  "Generate findings file from research knowledge consumed by prompt builder.
Writes to var/tmp/evolution/findings.md."
  (let* ((evolution-dir (expand-file-name "var/tmp/evolution"
                                          (gptel-auto-workflow--worktree-base-root)))
         (knowledge-dir (expand-file-name "mementum/knowledge"
                                         (gptel-auto-workflow--worktree-base-root)))
         (skill-file (expand-file-name "findings.md" evolution-dir))
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
               ;; Extract digested insights section (supports both heading and bold formats)
               (when (re-search-forward "\\(## Digested Insights\\|\\*\\*Digested Insights:\\*\\*\\)" nil t)
                 ;; For bold format, move past newline to content
                 (when (looking-at-p "\n")
                   (forward-char 1))
                  (let ((start (point)))
                    (if (re-search-forward "^\\(## \\|\\*\\*[^:]+:\\*\\*\\)" nil t)
                        (backward-char (length (match-string 0)))
                      (goto-char (point-max)))
                    (push (buffer-substring-no-properties start (point)) recent-insights))))))))
     ;; Read raw research findings from pipeline
     (let* ((raw-findings-file (expand-file-name "var/tmp/research-findings.md"
                                                  (gptel-auto-workflow--worktree-base-root)))
            (raw-findings (when (file-readable-p raw-findings-file)
                            (let ((size (file-attribute-size (file-attributes raw-findings-file))))
                              ;; Only use if >500 bytes and <7 days old
                              (when (and size
                                         (> size 500)
                                         (time-less-p
                                          (time-subtract (current-time) (days-to-time 7))
                                          (file-attribute-modification-time (file-attributes raw-findings-file))))
                                  (with-temp-buffer
                                    (insert-file-contents raw-findings-file)
                                    ;; Clean raw findings: strip LLM conversational noise
                                    (goto-char (point-min))
                                    (while (re-search-forward "^\\(?:Researcher result for task:.*$\\|I'll \\(?:conduct\\|follow\\|dig\\|check\\|search\\|fetch\\|look\\|analyze\\|examine\\|explore\\|start\\|use\\|begin\\|try\\|run\\|read\\|review\\|investigate\\).*\\|Good results.*$\\|Let me \\(?:fetch\\|search\\|dig\\|check\\|look\\|analyze\\|examine\\|explore\\|find\\|review\\|investigate\\|see\\).*\\|Based on my research.*$\\|Excellent findings!?.*$\\|Found a relevant.*$\\)" nil t)
                                      (replace-match ""))
                                    ;; Strip remaining conversational lines (first-person present tense)
                                    (goto-char (point-min))
                                    (while (re-search-forward "^\\(?:Now I \\|Now let me \\|Let me now \\)" nil t)
                                      (replace-match ""))
                                    ;; Strip empty reasoning blocks
                                    (goto-char (point-min))
                                    (while (re-search-forward "\\(reasoning\\s-*\\.\\s-*olle\\)" nil t)
                                      (let ((start (match-beginning 0)))
                                        (when (re-search-forward "}
" nil t)
                                          (delete-region start (point)))))
                                    ;; Collapse multiple blank lines
                                    (goto-char (point-min))
                                    (while (re-search-forward "\n\\{3,\\}" nil t)
                                      (replace-match "\n\n"))
                                    (buffer-string)))))))
       (when raw-findings
         (push raw-findings recent-insights)))
     
      ;; Generate skill file
    (make-directory evolution-dir t)
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

(declare-function gptel-auto-workflow--load-directive-skill "gptel-auto-workflow-strategic" ())

;;; ─── Dynamic Content Generators ───

(defun gptel-auto-workflow--generate-source-effectiveness-section ()
  "Generate markdown section showing source effectiveness from traces.
Returns string with table of source → keep rate."
  (let* ((traces (condition-case nil (gptel-auto-workflow--load-research-traces) (error nil)))
         (own-repo-kept 0) (own-repo-total 0)
         (external-kept 0) (external-total 0)
         (content ""))
    (dolist (trace traces)
      (let* ((source (or (plist-get trace :source) "unknown"))
             (outcomes (plist-get trace :outcomes)))
        (dolist (o outcomes)
          (cond ((string= source "own-repo")
                 (setq own-repo-total (1+ own-repo-total))
                  (when (eq (plist-get o :kept) t)
                    (setq own-repo-kept (1+ own-repo-kept))))
                ((string= source "external")
                 (setq external-total (1+ external-total))
                 (when (eq (plist-get o :kept) t)
                   (setq external-kept (1+ external-kept))))))))
    (setq content (concat content "## Source Effectiveness\n\n"))
    (if (or (> own-repo-total 0) (> external-total 0))
        (progn
          (setq content (concat content "| Source | Kept | Total | Rate | Strategy |\n"))
          (setq content (concat content "|--------|------|-------|------|----------|\n"))
          (when (> own-repo-total 0)
            (setq content (concat content (format "| own-repo | %d | %d | %.0f%% | own-repos-first |\n"
                                                  own-repo-kept own-repo-total
                                                  (* 100 (/ (float own-repo-kept) own-repo-total))))))
          (when (> external-total 0)
            (setq content (concat content (format "| external | %d | %d | %.0f%% | deep-external |\n"
                                                  external-kept external-total
                                                  (* 100 (/ (float external-kept) external-total)))))))
      (setq content (concat content "*No source effectiveness data yet.*\n")))
    content))

(defun gptel-auto-workflow--generate-controller-guidance-section ()
  "Generate markdown section with controller config and topic models.
Returns string with controller guidance."
  (let ((content "## Controller Guidance\n\n")
        (controller (condition-case nil (gptel-auto-workflow--load-autotts-controller) (error nil))))
    (if controller
        (progn
          (setq content (concat content "Current controller configuration (evolved from trace outcomes):\n\n"))
          (setq content (concat content (format "- **Stop threshold**: %.2f\n"
                                                (or (plist-get controller :min-confidence-stop) 0.7))))
          (setq content (concat content (format "- **Token budget**: %d tokens\n"
                                                (or (plist-get controller :max-tokens-budget) 8000))))
          (setq content (concat content (format "- **Own-repo priority**: %.0f%%\n"
                                                (* 100 (or (plist-get controller :own-repo-priority) 0.7)))))
          (let ((topic-models (plist-get controller :topic-models)))
            (when topic-models
              (setq content (concat content "\n**Topic-specific strategies**:\n\n"))
              (dolist (tm topic-models)
                (let ((topic (plist-get tm :topic))
                      (n (plist-get tm :n-traces))
                      (base (plist-get tm :base-rate)))
                  (setq content (concat content (format "- %s: %d traces, %.0f%% base rate\n"
                                                        topic n (* 100 base)))))))
            content))
      (concat content "*Controller not yet evolved. Using heuristic defaults.*\n"))))

(defun gptel-auto-workflow--generate-dynamic-instructions ()
  "Generate markdown section with dynamic instructions based on trace outcomes.
Returns string with source strategy and controller awareness."
  (let* ((traces (condition-case nil (gptel-auto-workflow--load-research-traces) (error nil)))
         (own-repo-kept 0) (own-repo-total 0)
         (external-kept 0) (external-total 0)
         (content "## Instructions\n\n"))
    (dolist (trace traces)
      (let* ((source (or (plist-get trace :source) "unknown"))
             (outcomes (plist-get trace :outcomes)))
        (dolist (o outcomes)
          (cond ((string= source "own-repo")
                 (setq own-repo-total (1+ own-repo-total))
                  (when (eq (plist-get o :kept) t)
                    (setq own-repo-kept (1+ own-repo-kept))))
                ((string= source "external")
                 (setq external-total (1+ external-total))
                 (when (eq (plist-get o :kept) t)
                   (setq external-kept (1+ external-kept))))))))
    (setq content (concat content "### Source Strategy (learned from outcomes)\n"))
    (cond ((and (> own-repo-total 0) (> external-total 0))
           (let ((own-rate (/ (float own-repo-kept) own-repo-total))
                 (ext-rate (/ (float external-kept) external-total)))
             (cond ((> own-rate (+ ext-rate 0.2))
                    (setq content (concat content "- **PRIORITY**: Search davidwuchn/* repos FIRST\n")))
                   ((> ext-rate (+ own-rate 0.2))
                    (setq content (concat content "- **PRIORITY**: Search external sources FIRST\n")))
                   (t (setq content (concat content "- **BALANCED**: Both sources effective\n"))))))
          ((> own-repo-total 0)
           (setq content (concat content "- **OWN REPOS**: Check davidwuchn/* repos first\n")))
          (t (setq content (concat content "- **DEFAULT**: Use own-repos-first strategy\n"))))
    (setq content (concat content "\n### Controller Awareness\n"))
    (setq content (concat content "- STOP early if you have 2+ insights with URLs\n"))
    (setq content (concat content "- CONTINUE if you found URLs but need more depth\n"))
    (setq content (concat content "- BRANCH if no new insights after 2 turns\n"))
    content))

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
         (skill-file (expand-file-name "var/tmp/evolution/researcher.md"
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
        (cl-flet ((collect-topic (target counts)
                    (let ((total (car counts))
                          (kept (cadr counts)))
                      (when (>= total 3)
                        (push (list :target target :rate (/ (float kept) total) :total total :kept kept)
                              sorted-topics)))))
          (maphash #'collect-topic topic-performance))
        (setq sorted-topics (sort sorted-topics (lambda (a b) (> (plist-get a :rate) (plist-get b :rate)))))
        
        (if sorted-topics
            (dolist (topic (seq-take sorted-topics 10))
              (insert (format "  - `%s`: %.0f%% keep rate (%d/%d)\n"
                              (plist-get topic :target)
                              (* 100 (plist-get topic :rate))
                              (plist-get topic :kept)
                              (plist-get topic :total))))
          (insert "  - No statistically significant data yet (need ≥3 experiments per topic)\n")))
      
      ;; Dynamic sections
      (insert "\n")
      (insert (gptel-auto-workflow--generate-source-effectiveness-section))
      (insert "\n")
      (insert (gptel-auto-workflow--generate-controller-guidance-section))
      (insert "\n")
      (insert (gptel-auto-workflow--generate-dynamic-instructions))
      (insert "\n")
      
      (insert "## Mission\n\n")
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
      (insert "## Output Format\n\n")
      (insert "Return a compact structured digest. End with JSON metadata so AutoTTS can replay decisions offline:\n\n")
      (insert "```json\n")
      (insert "{\n")
      (insert "  \"strategy_used\": \"own-repos-first\",\n")
      (insert "  \"sources_checked\": [\"davidwuchn/gptel\"],\n")
      (insert "  \"topics_covered\": [\"nil-safety\"],\n")
      (insert "  \"confidence_final\": 0.75,\n")
      (insert "  \"insights_count\": 2,\n")
      (insert "  \"tokens_estimate\": 2500\n")
      (insert "}\n")
      (insert "```\n\n")
       
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

(defun gptel-auto-workflow--evolve-researcher-from-feedback ()
  "Update researcher skill based on end-to-end experiment feedback.
Analyzes which research quality levels (external/internal/none) correlate
with kept experiments, and updates the researcher prompt accordingly."
  (message "[evolution] Analyzing researcher end-to-end feedback...")
  (let* ((results (gptel-auto-workflow--parse-all-results))
         ;; Group by research quality
         (by-quality (make-hash-table :test 'equal))
         (total-kept 0)
         (total-experiments 0))
    
    ;; Count experiments by research quality
    (dolist (r results)
      (let ((quality (or (plist-get r :research-quality) "none"))
            (decision (plist-get r :decision)))
        (when (and quality (not (string= quality "none")))
          (let ((current (or (gethash quality by-quality)
                              (let ((c (cons 0 0)))
                                (puthash quality c by-quality)
                                c))))
            (setq total-experiments (1+ total-experiments))
            (when (equal decision "kept")
              (setq total-kept (1+ total-kept))
              (setcar current (1+ (car current))))
            (setcdr current (1+ (cdr current)))
            (puthash quality current by-quality)))))
    
    ;; Calculate effectiveness per quality level
    (let ((stats nil))
      (cl-flet ((collect-quality (quality counts)
                 (let ((kept (car counts))
                       (total (cdr counts)))
                   (when (> total 0)
                     (push (list :quality quality
                                 :kept kept
                                 :total total
                                 :rate (/ (float kept) total))
                           stats)))))
        (maphash #'collect-quality by-quality))
      
      ;; Log findings
      (if stats
          (progn
            (message "[evolution] Research quality effectiveness:")
            (dolist (s (sort stats (lambda (a b) (> (plist-get a :rate) (plist-get b :rate)))))
              (message "  %s: %.1f%% (%d/%d)"
                       (plist-get s :quality)
                       (* 100 (plist-get s :rate))
                       (plist-get s :kept)
                       (plist-get s :total)))
            
            ;; Update researcher skill with feedback
            (let ((_skill-file (expand-file-name "assistant/skills/researcher-prompt/SKILL.md"
                                                (gptel-auto-workflow--worktree-base-root)))
                  (best-quality (plist-get (car stats) :quality))
                  (best-rate (plist-get (car stats) :rate)))
              (when (and best-quality (> best-rate 0))
                (message "[evolution] Best research quality: %s (%.1f%%) - updating skill guidance"
                         best-quality (* 100 best-rate))
                ;; Store feedback for next researcher run
                (let ((feedback-file (expand-file-name "var/tmp/researcher-feedback.sexp"
                                                       (gptel-auto-workflow--worktree-base-root))))
                  (with-temp-file feedback-file
                    (prin1 (list :best-quality best-quality
                                 :best-rate best-rate
                                 :stats stats
                                 :timestamp (format-time-string "%Y-%m-%dT%H:%M:%SZ"))
                           (current-buffer)))))))
        (message "[evolution] No research-enabled experiments to analyze yet")))))

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
  (gptel-auto-workflow--generate-research-skill)
  
  ;; Evolve researcher skill with dynamic content (source effectiveness + controller guidance)
  (gptel-auto-workflow--evolve-researcher-skill)

  ;; Analyze researcher end-to-end effectiveness
  (gptel-auto-workflow--evolve-researcher-from-feedback)

  ;; Cross-layer feedback: inject the latest controller config into researcher skill.
  ;; (Controller evolution runs before this via evolution-run-cycle → run-autotts-evolution)
  (when (fboundp 'gptel-auto-workflow--update-skill-with-controller)
    (let ((controller-config
           (when (fboundp 'gptel-auto-workflow--load-autotts-controller)
             (gptel-auto-workflow--load-autotts-controller))))
      (when controller-config
        (gptel-auto-workflow--update-skill-with-controller controller-config)))))

(defun gptel-auto-workflow-evolution-run-cycle ()
  "Run one full self-evolution cycle.
Extract → Verify → Controller Evolution → Skill Evolution.
Controller evolves from traces first so SKILL.md sees fresh strategy-guidance."
  (interactive)
  (cl-block gptel-auto-workflow-evolution-run-cycle
  (message "[auto-workflow] Running self-evolution cycle...")
  (let ((new-experiments (gptel-auto-workflow--evolution-count-new))
        (has-research (and (getenv "PIPELINE_FINDINGS_FILE")
                           (file-exists-p (getenv "PIPELINE_FINDINGS_FILE")))))
    (when (and (< new-experiments 3) (not has-research))
      (let ((message (format "[evolution] Insufficient new data (%d experiments, no research). Skipping."
                             new-experiments)))
        (message "%s" message)
        (cl-return-from gptel-auto-workflow-evolution-run-cycle message))))
  ;; Consume pipeline env vars for research-aware evolution
  (let ((research-quality (getenv "PIPELINE_RESEARCH_QUALITY"))
        (findings-file (getenv "PIPELINE_FINDINGS_FILE"))
        (_internal-file (getenv "PIPELINE_INTERNAL_FILE")))
    (when research-quality
      (message "[evolution] Pipeline research quality: %s" research-quality)
      (when (string= research-quality "external")
        (message "[evolution] External research available: controller thresholds optimized")))
    (when findings-file
      (message "[evolution] Findings file: %s" findings-file)))
  (gptel-auto-workflow--evolution-synthesize)
  (gptel-auto-workflow--evolution-consolidate-insights)
  ;; Step A: Controller evolution (traces → strategy-guidance.json)
  (when (fboundp 'gptel-auto-workflow--run-autotts-evolution)
    (message "[auto-workflow] Running controller evolution from traces...")
    (gptel-auto-workflow--run-autotts-evolution))
  ;; Step A.5: Controller code generation agent (AutoTTS-defining feature)
  ;; Runs LLM-driven controller design: agent writes code, tests against replay store, iterates
  (when (fboundp 'gptel-auto-workflow--run-controller-design-agent)
    (message "[auto-workflow] Running controller design agent...")
    (gptel-auto-workflow--run-controller-design-agent 3))
  ;; Step B: Skill evolution (TSV data → SKILL.md, uses {{strategy-guidance}} from step A)
  (gptel-auto-workflow--evolve-all-skills)
  ;; Run AutoTTS-style strategy evolution using benchmark results
  (when (fboundp 'gptel-auto-workflow--run-strategy-evolution)
    (message "[auto-workflow] Running strategy evolution...")
    (gptel-auto-workflow--run-strategy-evolution))
  ;; Step C: Skill governance (scan health, inject canaries, dashboard)
  (when (fboundp 'gptel-auto-workflow--skill-governance-run-cycle)
    (message "[auto-workflow] Running skill governance cycle...")
    (gptel-auto-workflow--skill-governance-run-cycle))
  (gptel-auto-workflow--evolution-record-score)
  (message "[auto-workflow] Self-evolution cycle complete.")))

;; ─── Evolution Quality Gates ───

(defun gptel-auto-workflow--evolution-record-score ()
  "Record current evolution quality score for trend tracking.
Saves to var/tmp/evolution-scores.json."
  (let* ((results (gptel-auto-workflow--parse-all-results))
         (kept (cl-count-if (lambda (r) (equal (plist-get r :decision) "kept")) results))
         (total (length results))
         (score (if (> total 0) (/ (float kept) (float total)) 0.0))
         (score-file (expand-file-name "var/tmp/evolution-scores.json"
                                       (or (gptel-auto-workflow--worktree-base-root) "~")))
          (history (gptel-auto-workflow--evolution-normalize-history
                    (condition-case nil
                        (let ((json-object-type 'plist)
                              (json-array-type 'list))
                          (with-temp-buffer
                            (insert-file-contents score-file)
                            (goto-char (point-min))
                            (json-read)))
                      (error (list :scores nil :best 0.0)))))
          (scores (gptel-auto-workflow--evolution-score-list
                   (plist-get history :scores)))
          (best (plist-get history :best)))
    (setq history (plist-put history :last-score score))
    (setq history (plist-put history :last-total total))
    (setq history (plist-put history :scores
                (cons (list :timestamp (format-time-string "%Y-%m-%dT%H:%M")
                           :score score :total total)
                      (seq-take scores 20))))
    (when (> score (or best 0.0))
      (setq history (plist-put history :best score))
      (setq history (plist-put history :best-at (format-time-string "%Y-%m-%dT%H:%M"))))
    (make-directory (file-name-directory score-file) t)
    (with-temp-file score-file
      (insert (json-encode history)))
    (message "[evolution] Recorded score: %.4f (best: %.4f, total: %d)" score (plist-get history :best) total)
    score))

(defun gptel-auto-workflow--evolution-count-new ()
  "Count new experiments since last recorded score."
  (let* ((score-file (expand-file-name "var/tmp/evolution-scores.json"
                                       (or (gptel-auto-workflow--worktree-base-root) "~")))
          (last-total (condition-case nil
                          (let ((json-object-type 'plist))
                            (with-temp-buffer
                              (insert-file-contents score-file)
                              (goto-char (point-min))
                              (plist-get (gptel-auto-workflow--evolution-normalize-history
                                          (json-read))
                                         :last-total)))
                        (error 0)))
         (results (gptel-auto-workflow--parse-all-results))
         (current (length results)))
    (- current (or (ignore-errors (float last-total)) 0))))

;; ─── Skill Governance Integration ───

(defun gptel-auto-workflow--evolution-get-recently-evolved-skills ()
  "Return list of skill names that were recently evolved (last 2 cycles).
Used by skill-governance to select candidates for A/B testing."
  (let ((skills-dir (expand-file-name "assistant/skills" user-emacs-directory))
        (recent nil)
        (cutoff (- (float-time) (* 48 3600))))  ;; last 48 hours
    (when (file-directory-p skills-dir)
      (dolist (skill-dir (directory-files skills-dir t "^[^._]"))
        (when (file-directory-p skill-dir)
          (let ((skill-file (expand-file-name "SKILL.md" skill-dir)))
            (when (and (file-exists-p skill-file)
                        (let ((mtime (file-attribute-modification-time (file-attributes skill-file))))
                         (and mtime (> (float-time mtime) cutoff))))
              (push (file-name-nondirectory skill-dir) recent))))))
    (delete-dups recent)))

;; ─── Init ───

;; Cache repo root at load time to avoid worktree issues later
(when (and (null gptel-auto-workflow--evolution-repo-root)
           (fboundp 'gptel-auto-workflow--evolution-repo-root))
  (gptel-auto-workflow--evolution-repo-root))

(provide 'gptel-auto-workflow-evolution)
;;; gptel-auto-workflow-evolution.el ends here
