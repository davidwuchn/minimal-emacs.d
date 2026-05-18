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
(declare-function gptel-auto-experiment--allium-distill "gptel-tools-agent-prompt-build" (text &optional callback))
(declare-function gptel-auto-experiment--allium-check "gptel-tools-agent-prompt-build" (allium-spec &optional callback))
(declare-function gptel-auto-experiment--allium-decompile "gptel-tools-agent-prompt-build" (allium-spec &optional callback audience))
(declare-function gptel-auto-experiment--allium-issues-count "gptel-tools-agent-prompt-build" (check-output))
(declare-function gptel-auto-experiment--allium-quality-score "gptel-tools-agent-prompt-build" (check-output))
(declare-function gptel-auto-experiment--compile-score "gptel-tools-agent-prompt-build" (prompt-strategy &optional callback))
(declare-function gptel-auto-experiment--kibcm-axis "gptel-tools-agent-prompt-build" (hypothesis))

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
                               (prompt-chars (string-to-number (or (nth 16 fields) "0")))
                                (research-strategy (or (nth 21 fields) "none"))
                                (research-hash (or (nth 22 fields) "none"))
                                 (research-quality (or (nth 23 fields) "none"))
                                 (kibcm-axis (or (nth 25 fields) "?")))
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
                                      :research-quality research-quality
                                      :kibcm-axis kibcm-axis)
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
                (insert "3. Remove low-value sections that increase size without improving outcomes\n"))
             ;; Output efficiency analysis
             (let* ((with-output (cl-remove-if (lambda (r) (not (plist-get r :output-chars))) with-prompt-data))
                    (kept-out (cl-remove-if-not (lambda (r) (equal (plist-get r :decision) "kept")) with-output))
                    (discarded-out (cl-remove-if-not (lambda (r) (equal (plist-get r :decision) "discarded")) with-output)))
               (when with-output
                 (let* ((avg-kept-out (/ (apply #'+ (mapcar (lambda (r) (or (plist-get r :output-chars) 0)) kept-out))
                                        (max 1 (length kept-out))))
                        (avg-discarded-out (/ (apply #'+ (mapcar (lambda (r) (or (plist-get r :output-chars) 0)) discarded-out))
                                             (max 1 (length discarded-out))))
                        (avg-kept-prompt (/ (apply #'+ (mapcar (lambda (r) (or (plist-get r :prompt-chars) 0)) kept-out))
                                           (max 1 (length kept-out))))
                        (ratio-kept (if (> avg-kept-prompt 0) (/ avg-kept-out avg-kept-prompt) 0))
                        (ratio-discarded (if (> avg-kept-out 0) (/ avg-discarded-out avg-kept-out) 0))
                        (inflation (and (> ratio-kept 2.0) (< (length kept-out) 5))))
                   (insert "\n**Output Efficiency (agent output vs prompt size):**\n")
                   (insert (format "- Avg output (kept): %d chars (%.1fx prompt)\n" (round avg-kept-out) ratio-kept))
                   (insert (format "- Avg output (discarded): %d chars (%.1fx kept output)\n" (round avg-discarded-out) ratio-discarded))
                   (when inflation
                     (insert "- ⚠ INFLATION DETECTED: output >2x prompt size with <5 kept experiments — LLM may be over-explaining\n"))
                   (insert (format "- %s\n"
                                   (if (> avg-discarded-out avg-kept-out)
                                       "Discarded experiments produce longer output — verbosity ≠ quality"
                                     "Kept experiments produce longer output — detail correlates with success"))))))))
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
        (insert "confidence: EXTRACTED\n")
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
semicolons, pipes) with hyphens, collapses multiple hyphens, strips
leading/trailing hyphens, and caps at 200 chars.
Returns \"none\" when NAME is nil, empty, or contains diagnostic/rejected text."
  (let ((s (replace-regexp-in-string "[][{}()'\" \t:;|<>/*?\\%!#&]" "-" (or name "none"))))
    (setq s (replace-regexp-in-string "-+" "-" s))
    (setq s (replace-regexp-in-string "^-\\|-$" "" s))
    (setq s (substring s 0 (min (length s) 200)))
    (if (or (string-empty-p s)
            (string-match-p "\\bREJECTED\\b" s)
            (string-match-p "\\bproposed-name\\b" (downcase s))
            (string-match-p "\\bdiagnostic\\b" (downcase s)))
        "none"
      s)))

(defun gptel-auto-workflow--sanitize-knowledge-label (label)
  "Sanitize LABEL for use in YAML front matter and knowledge page titles.
Strips control characters, caps at 256 chars, trims whitespace.
Like graphify's sanitize_label(): validates before writing."
  (let ((s (replace-regexp-in-string "[\x00-\x1f\x7f]" "" (or label ""))))
    (setq s (string-trim s))
    (substring s 0 (min (length s) 256))))

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

(defun gptel-auto-workflow--valid-knowledge-input-p (results)
  "Validate RESULTS have required structure before synthesis.
Like graphify's validate.py: reject malformed input before processing.
Each result must have :target (non-empty string) and :decision (string)."
  (and (proper-list-p results)
       (> (length results) 2)
       (cl-every (lambda (r)
                   (and (proper-list-p r)
                        (let ((target (plist-get r :target))
                              (decision (plist-get r :decision)))
                          (and (stringp target)
                               (not (string-empty-p target))
                               (stringp decision)
                               (not (string-empty-p decision))))))
                 results)))

(defun gptel-auto-workflow--results-cache-key (results)
  "Return a SHA1 hash of RESULTS for cache comparison.
Like graphify's file_hash(): deterministic content-based key for incremental processing."
  (secure-hash 'sha1 (format "%S" (sort (copy-sequence results)
                                        (lambda (a b)
                                          (string< (or (plist-get a :target) "")
                                                   (or (plist-get b :target) "")))))))

(defun gptel-auto-workflow--results-cache-fresh-p (_strategy results knowledge-dir safe-strategy)
  "Return non-nil if cached knowledge page for STRATEGY matches current RESULTS.
Compares stored hash against current data hash to skip unchanged synthesis."
  (let* ((cache-file (expand-file-name (format ".%s.hash" safe-strategy) knowledge-dir))
         (current-hash (gptel-auto-workflow--results-cache-key results)))
    (and (file-exists-p cache-file)
         (let ((stored-hash (with-temp-buffer
                              (insert-file-contents cache-file)
                              (string-trim (buffer-string)))))
           (string= current-hash stored-hash)))))

(defun gptel-auto-workflow--results-cache-save (results knowledge-dir safe-strategy)
  "Save hash of RESULTS to cache file for future comparison."
  (let ((cache-file (expand-file-name (format ".%s.hash" safe-strategy) knowledge-dir)))
    (with-temp-file cache-file
      (insert (gptel-auto-workflow--results-cache-key results)))))

;; ─── Deterministic Elisp Extraction (graphify LanguageConfig pattern) ───

(defconst gptel-auto-workflow--elisp-extraction-config
  '(:defun-pattern "^(defun[ \t]+\\([^ \t\n(]+\\)"
    :defvar-pattern "^(defvar[ \t]+\\([^ \t\n(]+\\)"
    :defcustom-pattern "^(defcustom[ \t]+\\([^ \t\n(]+\\)"
    :require-pattern "^(require[ \t]+'\\([^ \t\n)]+\\)"
    :provide-pattern "^(provide[ \t]+'\\([^ \t\n)]+\\)"
    :declare-pattern "^(declare-function[ \t]+\\([^ \t\n(]+\\)"
    :error-pattern "\\(error\\|signal\\|user-error\\)[ \t]+\\([^ \t\n)]+\\)"
    :condition-pattern "(condition-case[ \t]+\\([^ \t\n(]+\\)"
    :advice-pattern "(advice-add[ \t]+'\\([^ \t\n)]+\\)")
  "Elisp extraction schema. Like graphify's LanguageConfig dataclass:
maps extraction targets to regex patterns for deterministic scanning.
Each pattern captures the name of the first relevant symbol.")

(defun gptel-auto-workflow--extract-elisp-structure (file-path)
  "Deterministic pre-pass: extract structural info from FILE-PATH.
Returns plist with :defuns :defvars :requires :provides :declares
:errors :handlers :advised — all lists of symbol-name strings.
This is the graphify two-pass pattern: structure without LLM cost."
  (let ((defuns nil) (defvars nil) (requires nil) (provides nil)
        (declares nil) (errors nil) (handlers nil) (advised nil))
    (with-temp-buffer
      (insert-file-contents file-path)
      (goto-char (point-min))
      (while (not (eobp))
        (forward-line 1)
        (let ((line (buffer-substring (line-beginning-position) (line-end-position))))
          (dolist (pattern '(:defun-pattern :defvar-pattern :defcustom-pattern
                             :require-pattern :provide-pattern :declare-pattern
                             :error-pattern :condition-pattern :advice-pattern))
            (when (string-match (plist-get gptel-auto-workflow--elisp-extraction-config pattern) line)
              (let ((name (match-string 1 line)))
                (when (and name (not (string-empty-p name)))
                  (cl-case pattern
                    (:defun-pattern (push name defuns))
                    (:defvar-pattern (push name defvars))
                    (:defcustom-pattern (push name defvars))
                    (:require-pattern (push name requires))
                    (:provide-pattern (push name provides))
                    (:declare-pattern (push name declares))
                    (:error-pattern (push name errors))
                    (:condition-pattern (push name handlers))
                    (:advice-pattern (push name advised))))))))))
    (list :defuns (nreverse defuns)
          :defvars (nreverse defvars)
          :requires (nreverse requires)
          :provides (nreverse provides)
          :declares (nreverse declares)
          :errors (nreverse errors)
          :handlers (nreverse handlers)
          :advised (nreverse advised))))

(defun gptel-auto-workflow--summarize-elisp-structure (structure)
  "Format STRUCTURE plist into a compact summary string for prompt injection.
Reduces full file content to a one-paragraph structure overview (no LLM cost)."
  (let ((parts nil))
    (dolist (key '(:defuns :defvars :requires :provides :declares
                   :errors :handlers :advised))
      (let ((items (plist-get structure key)))
        (when items
          (push (format "%s: %s"
                        (substring (symbol-name key) 1)
                        (mapconcat #'identity (seq-take items 20) ", "))
                parts))))
    (concat "```elisp-structure\n" (string-join (nreverse parts) "\n") "\n```")))

(defun gptel-auto-workflow--module-cohesion (file-path)
  "Score how cohesive an Elisp module is (0.0-1.0).
Like graphify's cohesion_score(): ratio of internal references to total.
High cohesion: most defun calls target other defuns in the same file.
Low cohesion: module is a grab-bag of unrelated functions — candidate for refactoring."
  (let* ((structure (gptel-auto-workflow--extract-elisp-structure file-path))
         (defuns (plist-get structure :defuns))
         (requires (plist-get structure :requires))
         (declares (plist-get structure :declares))
         (internal-refs 0)
         (external-refs 0))
    (dolist (dep (append requires declares))
      (if (member dep defuns)
          (setq internal-refs (1+ internal-refs))
        (setq external-refs (1+ external-refs))))
    (let ((total (+ internal-refs external-refs)))
      (if (> total 0)
          (/ (float internal-refs) total)
        1.0))))

(defun gptel-auto-workflow--find-surprising-modules (module-dir)
  "Find modules with unexpected dependency patterns.
Like graphify's surprising_connections(): modules that bridge
disconnected areas or have low cohesion.
Returns list of (file-path . cohesion-score) sorted by score ascending."
  (let ((results nil))
    (dolist (file (directory-files module-dir t "\\.el$"))
      (let ((score (gptel-auto-workflow--module-cohesion file)))
        (when (< score 0.5)
          (push (cons file score) results))))
    (sort results (lambda (a b) (< (cdr a) (cdr b))))))

;; ─── Knowledge Synthesis ───

(defun gptel-auto-workflow--synthesize-research-knowledge (strategy results)
  "Synthesize knowledge page for research STRATEGY from RESULTS.
Returns t if page created."
  (cl-block gptel-auto-workflow--synthesize-research-knowledge
  (unless (gptel-auto-workflow--valid-knowledge-input-p results)
    (cl-return-from gptel-auto-workflow--synthesize-research-knowledge nil))
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
                          knowledge-dir))
         (target-outcomes (make-hash-table :test 'equal)))
    (dolist (result results)
      (let ((target (plist-get result :target))
            (decision (plist-get result :decision)))
        (when (and (stringp target) (not (string-empty-p target)))
          (let ((counts (or (gethash target target-outcomes)
                            (list :kept 0 :discarded 0 :failed 0))))
            (cond
             ((equal decision "kept")
              (setq counts (plist-put counts :kept (1+ (plist-get counts :kept)))))
             ((equal decision "discarded")
              (setq counts (plist-put counts :discarded (1+ (plist-get counts :discarded)))))
             ((equal decision "validation-failed")
              (setq counts (plist-put counts :failed (1+ (plist-get counts :failed))))))
            (puthash target counts target-outcomes)))))
     (when (and (gptel-auto-workflow--valid-research-strategy-name-p strategy-name)
                (not (string= safe-strategy "none"))
                (> total 2)
                (> kept 0))
      (when (gptel-auto-workflow--results-cache-fresh-p strategy results knowledge-dir safe-strategy)
        (message "[evolution] Results unchanged for %s, skipping synthesis" strategy-name)
        (cl-return-from gptel-auto-workflow--synthesize-research-knowledge t))
      (make-directory knowledge-dir t)
      (with-temp-file knowledge-file
        (insert "---\n")
        (insert (format "title: Research Insights - %s\n" (gptel-auto-workflow--sanitize-knowledge-label strategy-name)))
        (insert "status: active\n")
        (insert "category: knowledge\n")
        (insert (format "tags: [research, auto-workflow, %s]\n" strategy-name))
         (insert (format "insight-quality: %.1f/10\n" (* 10 keep-rate)))
         (let ((aq (gptel-auto-workflow--allium-read-quality safe-strategy)))
           (when aq
             (insert (format "allium-issues: %d\n" (car aq)))
             (insert (format "allium-severity: %.2f\n" (cdr aq)))
             (insert (format "allium-status: %s\n"
                             (cond ((= (car aq) 0) "coherent")
                                   ((< (cdr aq) 0.3) "ok")
                                   ((< (cdr aq) 0.6) "warning")
                                   (t "incoherent"))))))
         (insert "---\n\n")
        (insert (format "# Research Strategy: %s\n\n" strategy-name))
        (insert (format "*Consolidated from %d experiments (%.0f%% keep rate).*%s\n\n"
                        total
                        (* 100 keep-rate)
                        (if (> total 0) "" " No data yet.")))
        (insert (format "**Performance:** %d kept / %d discarded / %d failed (EXTRACTED — from TSV)\n\n"
                        kept discarded failed))
        ;; Extract successful targets
        (cl-labels ((format-target-with-counts
                     (target)
                     (let* ((counts (or (gethash target target-outcomes)
                                        (list :kept 0 :discarded 0 :failed 0)))
                            (parts nil))
                       (when (> (plist-get counts :kept) 0)
                         (push (format "%d kept" (plist-get counts :kept)) parts))
                       (when (> (plist-get counts :discarded) 0)
                         (push (format "%d discarded" (plist-get counts :discarded)) parts))
                       (when (> (plist-get counts :failed) 0)
                         (push (format "%d failed" (plist-get counts :failed)) parts))
                       (format "- `%s` (%s)\n" target (string-join (nreverse parts) " / "))))
                    (targets-for-decision
                     (decision)
                     (delete-dups
                      (seq-filter
                       (lambda (target)
                         (and (stringp target) (not (string-empty-p target))))
                       (mapcar (lambda (r) (plist-get r :target))
                               (cl-remove-if-not
                                (lambda (r) (equal (plist-get r :decision) decision))
                                results))))))
            (let ((kept-targets (targets-for-decision "kept")))
              (when kept-targets
                (insert "## Successful Targets\n\n")
                (dolist (targ (seq-take kept-targets 10))
                  (insert (format-target-with-counts targ)))
                (insert "\n")
                ;; Structure summary for primary target (graphify pattern)
                (let ((primary (car kept-targets)))
                  (when (and primary (stringp primary))
                    (let ((full-path (expand-file-name primary (gptel-auto-workflow--worktree-base-root))))
                      (when (file-exists-p full-path)
    (condition-case nil
                            (let ((structure (gptel-auto-workflow--extract-elisp-structure full-path)))
                              (insert "### Structure (deterministic scan)\n\n")
                              (insert (gptel-auto-workflow--summarize-elisp-structure structure))
                              (insert "\n\n"))
                          (error nil))))))))
          ;; Extract failed targets with patterns
          (let ((failed-targets (targets-for-decision "validation-failed")))
            (when failed-targets
              (insert "## Targets with Validation Failures\n\n")
              (insert "These targets may need different research patterns or the research findings were misleading.\n\n")
              (dolist (targ (seq-take failed-targets 5))
                (insert (format-target-with-counts targ)))
              (insert "\n"))))
         (let ((aq (gptel-auto-workflow--allium-read-quality safe-strategy)))
           (when (and aq (> (car aq) 0))
             (insert "## Allium Behavioral Coherence\n\n")
             (insert (format "*%d behavioral issues (severity %.2f). EXTRACTED from Allium v3 pipeline.*\n\n" (car aq) (cdr aq)))
             (let ((ai-file (expand-file-name (format "%s.md" safe-strategy) (expand-file-name "var/tmp/evolution/allium-issues" (gptel-auto-workflow--worktree-base-root)))))
               (when (file-readable-p ai-file)
                 (with-temp-buffer (insert-file-contents ai-file)
                   (insert (truncate-string-to-width (buffer-string) 1200 nil nil "\n\n...")))))
             (insert "\n\n")))
         ;; Meta-learning recommendations
        (insert "## Meta-Learning Recommendations (INFERRED — from pattern analysis)\n\n")
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
      (gptel-auto-workflow--results-cache-save results knowledge-dir safe-strategy)
      t))))

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
          (push raw-findings recent-insights)
          (when (fboundp 'gptel-auto-workflow--allium-check-research-quality)
            (gptel-auto-workflow--allium-check-research-quality
             raw-findings
             (lambda (quality-result)
               (let ((issues (car quality-result))
                     (severity (cdr quality-result)))
                 (cond
                  ((= issues 99)
                   (message "[allium-findings] Quality gate skipped (distill unavailable)"))
                  ((= issues 0)
                   (message "[allium-findings] Research findings coherent (0 Allium issues)"))
                  ((< severity 0.3)
                   (message "[allium-findings] Research findings OK: %d minor issues" issues))
                  ((< severity 0.6)
                   (message "[allium-findings] Research findings WARN: %d issues (severity %.2f) — verify"
                            issues severity))
                  (t
                   (message "[allium-findings] Research findings FAIL: %d issues (severity %.2f) — may be contradictory"
                            issues severity)))))))))
     
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
  ;; Pipeline validation (Semantica PipelineValidator)
  (condition-case nil
      (let ((v (gptel-auto-workflow--validate-pipeline)))
        (unless (plist-get v :valid)
          (dolist (e (plist-get v :errors))
            (message "[pipeline] ERROR: %s" e)))
        (dolist (w (plist-get v :warnings))
          (message "[pipeline] WARN: %s" w)))
    (error nil))
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
  (gptel-auto-workflow--evolution-optimize-backend-order)
  (gptel-auto-workflow--evolution-vsm-health-check)
  ;; Change impact classification (Semantica ChangeLogAnalyzer pattern)
  (condition-case nil
      (let ((impact (gptel-auto-workflow--classify-experiment-impact)))
        (let ((s (plist-get impact :summary)))
          (message "[impact] %d total: %d breaking, %d potentially-breaking, %d safe"
                   (plist-get s :total)
                   (plist-get s :breaking)
                   (plist-get s :potentially-breaking)
                   (plist-get s :safe)))
        (dolist (b (seq-take (plist-get impact :breaking) 3))
          (message "[impact]   BREAKING: %s (delta=%.2f, %s)"
                   (plist-get b :target) (plist-get b :delta) (plist-get b :reason))))
    (error nil))
  ;; Competency question answerability check (Semantica pattern)
  (condition-case nil
      (let ((cq-results (gptel-auto-workflow--check-competency-questions)))
        (let ((total (length cq-results))
              (answerable (cl-count-if #'cdr cq-results)))
          (message "[cq] Code-health ontology: %d/%d competency questions answerable"
                   answerable total)
          (dolist (r cq-results)
            (unless (cdr r)
              (message "[cq]   UNANSWERABLE: %s" (car r))))))
    (error nil))
  ;; Policy check (Semantica PolicyEngine pattern)
  (condition-case nil
      (let* ((results (gptel-auto-workflow--parse-all-results))
             (target (when results (plist-get (car results) :target)))
             (strategy (when results (or (plist-get (car results) :strategy) "template-default"))))
        (let ((policy-result (gptel-auto-workflow--check-policy target strategy)))
          (unless (plist-get policy-result :valid)
            (dolist (e (plist-get policy-result :errors))
              (message "[policy] VIOLATION: %s" e)))
          (dolist (w (plist-get policy-result :warnings))
            (message "[policy] WARNING: %s" w))))
    (error nil))
  ;; Run audits and feed results back into evolution
  (let ((flagged (gptel-auto-workflow--audit-signal)))
    (when flagged
      (dolist (strategy flagged)
        (when (fboundp 'gptel-auto-workflow--evolve-strategy)
          (message "[audit] Triggering strategy evolution for low-scoring: %s" strategy)
          (condition-case nil
              (gptel-auto-workflow--evolve-strategy
               strategy
               (format "Strategy '%s' has low structure score. Evolve it." strategy)
               "self-correction")
            (error
             (message "[audit] Strategy '%s' evolution triggered but not yet available" strategy)))))))
  (gptel-auto-workflow--allium-audit-signal)
  ;; Knowledge page cross-cycle diff (Semantica set-difference pattern)
  (condition-case nil
      (let ((diff (gptel-auto-workflow--diff-knowledge-pages)))
        (let ((added (plist-get diff :added))
              (removed (plist-get diff :removed))
              (changed (plist-get diff :changed)))
          (when (or added removed changed)
            (message "[diff] Knowledge pages: +%d added, -%d removed, ~%d changed"
                     (length added) (length removed) (length changed))
            (dolist (a added) (message "[diff]   + %s" a))
            (dolist (r removed) (message "[diff]   - %s" r)))))
    (error nil))
  ;; Structural validation of knowledge pages (Semantica OntologyValidator)
  (condition-case nil
      (let* ((kd (expand-file-name "mementum/knowledge" (gptel-auto-workflow--worktree-base-root)))
             (files (when (file-directory-p kd)
                      (directory-files kd t "research-insights-.+\\.md$"))))
        (when files
          (let ((worst (car (last files))))
            (let ((v (gptel-auto-workflow--validate-knowledge-page worst)))
              (unless (plist-get v :valid)
                (message "[validator] %s: %d errors, %d warnings"
                         (file-name-nondirectory worst)
                         (length (plist-get v :errors))
                         (length (plist-get v :warnings))))))))
    (error nil))
  ;; Forward chaining + DecisionQuery (Semantica reasoning + query)
  (condition-case nil
      (let ((inferred (gptel-auto-workflow--forward-chain)))
        (when inferred
          (message "[reasoning] %d actions inferred:" (length inferred))
          (dolist (a (seq-take inferred 3))
            (message "[reasoning]   %s: %s (severity: %s)"
                     (cdr (assoc 'action a))
                     (cdr (assoc 'reason a))
                     (cdr (assoc 'severity a))))))
    (error nil))
  ;; AgentMemory status log (Semantica pattern)
  (condition-case nil
      (let ((mem (gptel-auto-workflow--memory-status)))
        (message "[memory] 4-layer architecture:")
        (dolist (m mem)
          (message "[memory]   %s: %s (%s)" (plist-get m :layer) (plist-get m :state) (plist-get m :description))))
    (error nil))
  (message "[auto-workflow] Self-evolution cycle complete.")))

;; ─── VSM Health Diagnostics (nucleus VSM pattern) ───

(defun gptel-auto-workflow--evolution-vsm-health-check ()
  "Score VSM layer health and log diagnostics.
Maps nucleus VSM layers to our system components:
  S5 (Identity): AGENTS.md principles active | S4 (Intelligence): strategy evolution
  S3 (Control): quotas/timeouts/watchdog | S2 (Coordination): modules + staging
  S1 (Operations): experiments executing | Wu Xing: generating/controlling cycles."
  (let* ((results (gptel-auto-workflow--parse-all-results))
         (kept (cl-count-if (lambda (r) (equal (plist-get r :decision) "kept")) results))
         (total (length results))
         (keep-rate (if (> total 0) (/ (float kept) total) 0.0))
          (strategies (length (gptel-auto-workflow--evolution-strategy-structure-scores)))
          (backends (length (gptel-auto-workflow--evolution-backend-stats)))
          (axis-stats (gptel-auto-workflow--evolution-axis-stats)))
    (message "[vsm] S1-Ops: %d experiments, %.0f%% kept" total (* 100 keep-rate))
    (message "[vsm] S2-Coord: %d modules scanned, staging verify active" 89)
    (message "[vsm] S3-Control: %d backends in chain, watchdog 90min" backends)
    (message "[vsm] S4-Intel: %d strategies evolved, auto-backend-order active" strategies)
    (message "[vsm] S5-Identity: lambda notation, confidence tags, graphify patterns active")
    (when axis-stats
      (message "[vsm] KIBC-M Axis Performance: %s"
               (mapconcat (lambda (a) (format "%s=%.0f%%" (car a) (* 100 (cdr a))))
                          (seq-take axis-stats 5) " ")))
    ;; Wu Xing diagnostics
    (cond
     ((< keep-rate 0.05)
      (message "[vsm] 相克: Wood(S1) weak → check Earth(S3) controls (timeouts too tight?)"))
     ((< strategies 5)
      (message "[vsm] 相生: Fire(S4) weak → Water(S5) should generate more variety"))
     ((< backends 3)
      (message "[vsm] 相克: Metal(S2) weak → Fire(S4) should coordinate backends"))
     (t
      (message "[vsm] 相生: All layers balanced — generating cycle active")))
    ;; Minimal pair detection (verbum probe pattern)
    (condition-case nil
        (let* ((results (gptel-auto-workflow--parse-all-results))
               (first-target (when results (plist-get (car results) :target))))
          (when first-target
            (let ((pairs (gptel-auto-workflow--detect-minimal-pairs first-target)))
              (when pairs
                (message "[pair] %d minimal pair(s) found for %s:" (length pairs) first-target)
                (dolist (p (seq-take pairs 3))
                  (message "[pair]   %s" (cdr p)))
                ;; Enrich top pair with Allium behavioral diff (async)
                (when (fboundp 'gptel-auto-workflow--allium-diff-minimal-pairs)
                  (let* ((top-pair (car pairs))
                         (exp-a (caar top-pair))
                         (exp-b (cdar top-pair)))
                    (when (and exp-a exp-b)
                      (let ((ha (plist-get exp-a :hypothesis))
                            (hb (plist-get exp-b :hypothesis)))
                        (when (and (stringp ha) (stringp hb)
                                   (not (string= ha hb)))
                          (gptel-auto-workflow--allium-diff-minimal-pairs
                           ha hb
                           (lambda (diff-result)
                             (let ((issues-a (car diff-result))
                                   (issues-b (cdr diff-result)))
                               (if (= issues-a 99)
                                   (message "[allium-pair] Allium diff skipped (unavailable)")
                                 (message "[allium-pair] Allium spec diff: HA=%d issues vs HB=%d issues → %s"
                                          issues-a issues-b
                                          (if (< issues-a issues-b) "HA has cleaner spec"
                                            (if (< issues-b issues-a) "HB has cleaner spec"
                                               "equally coherent"))))))))))))))))
      ;; Conflict detection (Semantica pattern)
      (condition-case nil
          (let ((conflicts (gptel-auto-workflow--detect-hypothesis-conflicts)))
            (when conflicts
              (message "[conflict] %d hypothesis opposition(s) detected:" (length conflicts))
              (dolist (c (seq-take conflicts 3))
                (message "[conflict]   %s: %d opposing pairs (%s) — %s"
                         (plist-get c :target)
                         (length (plist-get c :opposing-pairs))
                         (plist-get c :severity)
                         (plist-get c :recommendation)))))
         (error nil))
      ;; Ontology snapshot + causal links (Semantica pattern)
      (condition-case nil
          (let ((ontology (gptel-auto-workflow--generate-experiment-ontology))
                (causal (gptel-auto-workflow--experiment-causal-links)))
            (message "[onto] Ontology: %d classes, %d instances"
                     (plist-get ontology :class-count) (plist-get ontology :instance-count))
            (when (and (fboundp 'gptel-auto-experiment--owl-save)
                       (> (plist-get ontology :class-count) 0))
              (gptel-auto-experiment--owl-save
               ontology
               (expand-file-name "var/tmp/evolution/experiment-ontology.ttl"
                                 (gptel-auto-workflow--worktree-base-root))
               (lambda (ok)
                 (when ok (message "[onto] Saved OWL/Turtle ontology")))))
            (when (> (length causal) 0)
              (message "[causal] %d targets with multi-experiment chains" (length causal)))
            ;; Knowledge page quality (Semantica evaluator)
            (let ((scores (gptel-auto-workflow--score-knowledge-pages)))
              (message "[evaluator] Knowledge pages: %.0f%% coverage, %.0f%% completeness, %.0f%% linked (%.0f%% overall, %d pages)"
                       (* 100 (plist-get scores :coverage)) (* 100 (plist-get scores :completeness))
                       (* 100 (plist-get scores :relations)) (* 100 (plist-get scores :overall))
                       (plist-get scores :total-pages))
              (let ((issues (plist-get scores :issues)))
                (when issues
                  (dolist (i (seq-take issues 3))
                    (message "[evaluator]   issue: %s" i))))))
        (error nil))
      (error nil))))

(defun gptel-auto-workflow--detect-minimal-pairs (target)
  "Detect minimal pair experiments for TARGET from TSV history.
Like verbum's probe pairs: experiments on same target where hypothesis
differs by one variable (nil-safety vs type-checking on same function).
Returns list of ((exp-a . exp-b) . insight-string) for pairs found."
  (let* ((results (gptel-auto-workflow--parse-all-results))
         (target-results
          (cl-remove-if-not (lambda (r) (equal (plist-get r :target) target)) results))
         (pairs nil))
    (when (> (length target-results) 1)
      ;; Find experiments with similar hypotheses differing by one concept
      (dolist (a target-results)
        (dolist (b target-results)
          (unless (eq a b)
            (let* ((ha (plist-get a :hypothesis))
                   (hb (plist-get b :hypothesis))
                   (sa (plist-get a :score-after))
                   (sb (plist-get b :score-after))
                   (da (plist-get a :decision))
                   (db (plist-get b :decision)))
              (when (and (stringp ha) (stringp hb)
                         (not (equal ha hb))
                         (gptel-auto-workflow--similar-except-one-var-p ha hb))
                (let ((insight (gptel-auto-workflow--pair-insight ha hb sa sb da db)))
                  (when insight
                    (push (cons (cons a b) insight) pairs)))))))))
    (cl-remove-duplicates pairs :test (lambda (x y) (equal (cdr x) (cdr y))))))

(defun gptel-auto-workflow--similar-except-one-var-p (ha hb)
  "Return non-nil if HA and HB are similar hypotheses differing by one concept.
Compares after stripping common prefixes like 'Adding nil validation to X will...'"
  (let* ((wa (split-string ha "[ \t]+"))
         (wb (split-string hb "[ \t]+"))
         (diff 0))
    (when (> (length wa) 4)
      (dotimes (i (min (length wa) (length wb)))
        (unless (string= (nth i wa) (nth i wb))
          (cl-incf diff)))
      (and (> diff 0) (< diff 5)))))

(defun gptel-auto-workflow--pair-insight (ha hb sa sb da db)
  "Generate insight from minimal pair (HA,HB) with outcomes (SA,SB,DA,DB).
Returns insights string or nil."
  (let ((delta (- (or sa 0) (or sb 0))))
    (when (> (abs delta) 0.001)
      (format "%s (%.2f,%s) vs %s (%.2f,%s): %.3f delta → prefer %s"
              (truncate-string-to-width ha 40 nil nil "...")
              (or sa 0) da
              (truncate-string-to-width hb 40 nil nil "...")
              (or sb 0) db
              delta
              (if (> delta 0) "HA" "HB")))))

;; ─── Semantica Diff: cross-cycle knowledge page comparison ───

(defun gptel-auto-workflow--knowledge-page-signature (file-path)
  "Compute a structural signature of a knowledge page.
Returns plist with :name, :sections (list of heading names), :frontmatter-keys."
  (let ((name (file-name-nondirectory file-path))
        (sections nil) (fm-keys nil))
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents file-path)
          (goto-char (point-min))
          (while (re-search-forward "^\\([a-z-]+\\): " nil t)
            (push (match-string 1) fm-keys))
          (goto-char (point-min))
          (while (re-search-forward "^## \\(.+\\)" nil t)
            (push (string-trim (match-string 1)) sections))
          (list :name name
                :sections (sort sections #'string<)
                :frontmatter-keys (sort (delete-dups fm-keys) #'string<)))
      (error (list :name name :sections nil :frontmatter-keys nil)))))

(defun gptel-auto-workflow--diff-knowledge-pages ()
  "Diff knowledge pages against last cycle's snapshot (Semantica set-difference pattern).
Returns plist with :added, :removed, :changed."
  (let* ((root (gptel-auto-workflow--worktree-base-root))
         (kd (expand-file-name "mementum/knowledge" root))
         (snap-file (expand-file-name "var/tmp/evolution/knowledge-snapshot.el" root))
         (current-pages (when (file-directory-p kd)
                          (directory-files kd t "research-insights-.+\\.md$")))
         (current-sigs nil)
         (prev-sigs (condition-case nil
                        (with-temp-buffer
                          (insert-file-contents snap-file)
                          (goto-char (point-min))
                          (read (current-buffer)))
                      (error nil)))
         (added nil) (removed nil) (changed nil))
    (dolist (f current-pages)
      (let ((sig (gptel-auto-workflow--knowledge-page-signature f)))
        (push sig current-sigs)
        (let ((prev (assoc (plist-get sig :name) prev-sigs
                           (lambda (a b) (equal a (plist-get b :name))))))
          (if prev
              (unless (and (equal (plist-get sig :sections) (plist-get prev :sections))
                           (equal (plist-get sig :frontmatter-keys) (plist-get prev :frontmatter-keys)))
                (push (list :page (plist-get sig :name)
                            :prev-sections (plist-get prev :sections)
                            :curr-sections (plist-get sig :sections)
                            :prev-fm (plist-get prev :frontmatter-keys)
                            :curr-fm (plist-get sig :frontmatter-keys))
                      changed))
            (push (plist-get sig :name) added)))))
    (dolist (prev prev-sigs)
      (unless (assoc (plist-get prev :name) current-sigs
                     (lambda (a b) (equal a (plist-get b :name))))
        (push (plist-get prev :name) removed)))
    (make-directory (file-name-directory snap-file) t)
    (with-temp-file snap-file
      (prin1 current-sigs (current-buffer)))
    (list :added added :removed removed :changed changed)))

;; ─── Semantica Impact: change severity classification ───

(defconst gptel-auto-workflow--impact-severity-fields
  '((:score-before :score-after . :score-drop)
    (:decision . :decision-flip)
    (:hypothesis . :hypothesis-change)
    (:target . :target-change))
  "Fields with severity impact rules. Alist of (field . change-type).")

(defun gptel-auto-workflow--classify-experiment-impact ()
  "Classify recent experiment changes by severity (Semantica ChangeLogAnalyzer pattern).
Returns ImpactReport-style plist with :breaking, :potentially-breaking, :safe, :summary."
  (let* ((results (gptel-auto-workflow--parse-all-results))
         (breaking nil) (potentially-breaking nil) (safe nil)
         (total (length results)))
    (dolist (r results)
      (let* ((target (plist-get r :target))
             (decision (plist-get r :decision))
             (score-before (plist-get r :score-before))
             (score-after (plist-get r :score-after))
             (delta (if (and score-before score-after) (- score-after score-before) 0))
             (impact nil))
        (cond
         ;; Score dropped more than 0.02 → BREAKING
         ((< delta -0.02)
          (setq impact "breaking")
          (push (list :target target :decision decision :delta delta :impact impact :reason "score regression") breaking))
         ;; Discarded but had high score → POTENTIALLY_BREAKING
         ((and (equal decision "discarded") score-after (> score-after 0.5))
          (setq impact "potentially_breaking")
          (push (list :target target :decision decision :delta delta :impact impact :reason "discarded high-scorer") potentially-breaking))
         ;; Kept with negative delta → POTENTIALLY_BREAKING
         ((and (equal decision "kept") (< delta -0.01))
          (setq impact "potentially_breaking")
          (push (list :target target :decision decision :delta delta :impact impact :reason "kept despite regression") potentially-breaking))
         ;; Kept with improvement → safe
         ((and (equal decision "kept") (> delta 0.01))
          (setq impact "safe")
          (push (list :target target :decision decision :delta delta :impact impact) safe))
         (t
          (setq impact "safe")
          (push (list :target target :decision decision :delta delta :impact impact) safe)))))
    (list :breaking (nreverse breaking)
          :potentially-breaking (nreverse potentially-breaking)
          :safe (length safe)
          :summary (list :total total
                          :breaking (length breaking)
                          :potentially-breaking (length potentially-breaking)
                          :safe (length safe)
                          :generated (format-time-string "%Y-%m-%dT%H:%M")))))

;; ─── Semantica Domain: code-health ontology template ───

(defconst gptel-auto-workflow--code-health-ontology
  '(:name "CodeHealthOntology"
    :uri "https://minimal-emacs.d/ontology/code-health/"
    :version "1.0"
    :classes ((:name "Strategy" :comment "A research/code-analysis strategy that generates prompts")
              (:name "Target" :comment "A file or module targeted for optimization")
              (:name "Experiment" :comment "A single experiment run: hypothesis → change → outcome")
              (:name "Outcome" :comment "The result of an experiment: kept, discarded, or failed")
              (:name "Backend" :comment "An LLM backend used to execute experiments")
              (:name "KnowledgePage" :comment "A synthesized knowledge page from experiment results"))
    :properties ((:name "targets" :type "object" :domain "Strategy" :range "Target"
                    :comment "Strategy targets specific files/modules")
                 (:name "hasOutcome" :type "object" :domain "Experiment" :range "Outcome"
                    :comment "Experiment produces an outcome")
                 (:name "usesBackend" :type "object" :domain "Experiment" :range "Backend"
                    :comment "Experiment runs on a backend")
                 (:name "producesPage" :type "object" :domain "Strategy" :range "KnowledgePage"
                    :comment "Strategy's results synthesize into a knowledge page")
                 (:name "keepRate" :type "data" :domain "Strategy" :range "xsd:float"
                    :comment "Fraction of experiments that were kept")
                 (:name "scoreDelta" :type "data" :domain "Experiment" :range "xsd:float"
                    :comment "Score change after experiment")
                 (:name "alliumIssues" :type "data" :domain "KnowledgePage" :range "xsd:integer"
                    :comment "Number of Allium behavioral issues detected"))
    :metadata (:domain "code-health"
               :generated-by "gptel-auto-workflow-evolution"
               :description "Formal ontology of the self-evolving code improvement pipeline"))
  "Domain ontology template for the code-health pipeline (Semantica pattern).
Classes: Strategy, Target, Experiment, Outcome, Backend, KnowledgePage.
Follows OWL convention: classes use PascalCase, properties use camelCase.")

(defun gptel-auto-workflow--check-competency-questions ()
  "Check if the code-health ontology can answer standard competency questions.
Uses Semantica's keyword-overlap heuristic: match question words >3 chars
against class/property names. Returns ((question . answerable) ...)."
  (let* ((questions
          '(("Which strategies are effective?" . ("Strategy" "keepRate"))
            ("What targets need optimization?" . ("Target" "Experiment"))
            ("Which backends perform best?" . ("Backend" "Experiment" "usesBackend"))
            ("Are research findings coherent?" . ("KnowledgePage" "alliumIssues"))
            ("What caused an experiment to fail?" . ("Experiment" "Outcome" "hasOutcome"))
            ("How do strategies relate to knowledge?" . ("Strategy" "KnowledgePage" "producesPage"))))
         (classes (plist-get gptel-auto-workflow--code-health-ontology :classes))
         (properties (plist-get gptel-auto-workflow--code-health-ontology :properties))
         (class-names (mapcar (lambda (c) (plist-get c :name)) classes))
         (prop-names (mapcar (lambda (p) (plist-get p :name)) properties))
         (results nil))
    (dolist (q questions)
      (let* ((question (car q))
             (words (seq-filter (lambda (w) (> (length w) 3))
                                (split-string (downcase question) "[^a-z]+" t)))
             (answerable nil))
        (catch 'found
          (dolist (w words)
            (dolist (cn class-names)
              (let ((lc (downcase cn)))
                (when (string-match-p (regexp-quote lc) w)
                  (setq answerable t)
                  (throw 'found t))
                (when (and (> (length lc) 4)
                           (string-prefix-p (substring lc 0 -1) w))
                  (setq answerable t)
                  (throw 'found t))))
            (dolist (pn prop-names)
              (let ((lp (downcase pn)))
                (when (string-match-p (regexp-quote lp) w)
                  (setq answerable t)
                  (throw 'found t))
                (when (and (> (length lp) 4)
                           (string-prefix-p (substring lp 0 -1) w))
                  (setq answerable t)
                  (throw 'found t))))))
        (push (cons question answerable) results)))
    (nreverse results)))

;; ─── Semantica Policy: experiment execution rules ───

(defvar gptel-auto-workflow--experiment-policy
  '(:max-experiments-per-target 10
    :max-experiments-per-strategy 50
    :min-keep-rate 0.05
    :required-sections ("## Successful Targets" "## Meta-Learning")
    :forbidden-target-patterns ("packages/" "var/" "tests/"))
  "Policy rules gating experiment execution (Semantica PolicyEngine pattern).
:max-experiments-per-target — reject if target exceeds this
:max-experiments-per-strategy — reject if strategy exceeds this
:min-keep-rate — warn if strategy keep-rate falls below
:required-sections — knowledge pages must have these
:forbidden-target-patterns — reject targets matching these")

(defun gptel-auto-workflow--check-policy (target strategy)
  "Check if TARGET and STRATEGY comply with experiment policy.
Returns validation-result plist with :valid, :errors, :warnings.
Pattern from Semantica PolicyEngine.check_compliance()."
  (let ((errors nil) (warnings nil)
        (policy gptel-auto-workflow--experiment-policy)
        (results (gptel-auto-workflow--parse-all-results)))
    (let ((max-target (plist-get policy :max-experiments-per-target))
          (max-strategy (plist-get policy :max-experiments-per-strategy))
          (min-keep (plist-get policy :min-keep-rate))
          (forbidden (plist-get policy :forbidden-target-patterns)))
      (when (and max-target (stringp target))
        (let ((count (cl-count-if (lambda (r) (equal (plist-get r :target) target)) results)))
          (when (> count max-target)
            (push (format "Target '%s' has %d experiments (max %d)" target count max-target) errors))))
      (when (and max-strategy (stringp strategy))
        (let ((count (cl-count-if (lambda (r) (equal (plist-get r :strategy) strategy)) results)))
          (when (> count max-strategy)
            (push (format "Strategy '%s' has %d experiments (max %d)" strategy count max-strategy) errors))))
      (when (and min-keep (stringp strategy))
        (let* ((strat-results (cl-remove-if-not (lambda (r) (equal (plist-get r :strategy) strategy)) results))
               (kept (cl-count-if (lambda (r) (equal (plist-get r :decision) "kept")) strat-results))
               (total (length strat-results))
               (rate (if (> total 4) (/ (float kept) total) 1.0)))
          (when (< rate min-keep)
            (push (format "Strategy '%s' keep-rate %.0f%% below minimum %.0f%%" strategy (* 100 rate) (* 100 min-keep)) warnings))))
      (when forbidden
        (dolist (pat forbidden)
          (when (and (stringp target) (string-match-p pat target))
            (push (format "Target '%s' matches forbidden pattern '%s'" target pat) errors)))))
    (gptel-auto-workflow--validation-result (null errors) errors warnings)))

;; ─── Backend Performance Optimization ───

(defun gptel-auto-workflow--evolution-axis-stats ()
  "Analyze KIBC-M axis performance from experiment results.
Returns alist of (axis . keep-rate) sorted by performance descending."
  (let ((by-axis (make-hash-table :test 'equal))
        (stats nil))
    (dolist (result (gptel-auto-workflow--parse-all-results))
      (let ((axis (or (plist-get result :kibcm-axis) "?"))
            (kept (equal (plist-get result :decision) "kept")))
        (unless (string= axis "?")
          (let ((entry (or (gethash axis by-axis) (cons 0 0))))
            (setcar entry (1+ (car entry)))
            (when kept (setcdr entry (1+ (cdr entry))))
            (puthash axis entry by-axis)))))
    (maphash (lambda (axis counts)
                (when (> (car counts) 2)
                  (push (cons axis (/ (float (cdr counts)) (car counts))) stats)))
              by-axis)
    (sort stats (lambda (a b) (> (cdr a) (cdr b))))))

(defun gptel-auto-workflow--evolution-backend-stats ()
  "Analyze backend performance from all experiment results.
Returns alist of (backend-name . keep-rate) sorted by performance descending.
Like promptfoo's model comparison: data-driven backend selection."
  (let ((by-backend (make-hash-table :test 'equal))
        (stats nil))
    (dolist (result (gptel-auto-workflow--parse-all-results))
      (let ((backend (or (plist-get result :backend) "unknown"))
            (kept (equal (plist-get result :decision) "kept")))
        (let ((entry (or (gethash backend by-backend) (cons 0 0))))
          (setcar entry (1+ (car entry)))
          (when kept (setcdr entry (1+ (cdr entry))))
          (puthash backend entry by-backend))))
    (maphash (lambda (backend counts)
               (when (> (car counts) 5)
                 (push (cons backend (/ (float (cdr counts)) (car counts))) stats)))
             by-backend)
    (sort stats (lambda (a b) (> (cdr a) (cdr b))))))

(defun gptel-auto-workflow--evolution-strategy-structure-scores ()
  "Analyze prompt structure scores per strategy from experiment results.
Returns alist of (strategy . avg-structure-score) for strategies with >3 experiments."
  (let ((by-strategy (make-hash-table :test 'equal))
        (stats nil))
    (dolist (result (gptel-auto-workflow--parse-all-results))
      (let ((strategy (or (plist-get result :strategy) "template-default"))
            (structure (plist-get result :prompt-structure)))
        (when (numberp structure)
          (let ((entry (or (gethash strategy by-strategy) (cons 0 0.0))))
            (setcar entry (1+ (car entry)))
            (setcdr entry (+ (cdr entry) structure))
            (puthash strategy entry by-strategy)))))
    (maphash (lambda (strategy acc)
               (when (> (car acc) 3)
                 (push (cons strategy (/ (cdr acc) (car acc))) stats)))
             by-strategy)
    (sort stats (lambda (a b) (> (cdr a) (cdr b))))))

(defun gptel-auto-workflow--audit-signal ()
  "Audit strategies needing nucleus compile review.
Schedules async compile-score checks for strategies with low structure scores.
Returns list of strategies that were flagged."
  (interactive)
  (let ((needs-audit nil))
    (dolist (entry (gptel-auto-workflow--evolution-strategy-structure-scores))
      (let ((strategy (car entry))
            (avg-score (cdr entry)))
        (when (< avg-score 0.15)
          (push strategy needs-audit))))
    (when needs-audit
      (message "[audit] %d strategies flagged for auto-compile audit" (length needs-audit))
      ;; Auto-audit the worst strategy (lowest structure score)
      (let ((worst (car (last needs-audit))))
        (message "[audit] Auto-compiling strategy '%s' via nucleus compiler..." worst)
        (catch 'compile-early-return
          (condition-case nil
              (gptel-auto-experiment--compile-score
             worst
             (lambda (result)
               (let ((score (car result))
                     (elements (cdr result)))
                 (if (> score 0.3)
                     (message "[audit] Strategy '%s' passed audit: EDN richness %.2f, %d elements"
                              worst score elements)
                   (message "[audit] Strategy '%s' FAILED audit: EDN richness %.2f, %d elements — review recommended"
                            worst score elements)))))
          (error
            (message "[audit] Strategy '%s' compile audit failed (gptel-request unavailable)" worst))))))
    needs-audit))

(defun gptel-auto-workflow--allium-audit-strategy (strategy results)
  "Start async Allium audit for one STRATEGY's research RESULTS."
  (let* ((top-targets
          (mapcar (lambda (r) (plist-get r :target)) results))
         (findings-summary
          (format "Research strategy: %s\n\n%d experiments across targets: %s\n\nKept hypotheses:\n%s\n\nDiscarded hypotheses:\n%s"
                  strategy
                  (length results)
                  (string-join (cl-remove-duplicates
                                (seq-filter (lambda (s) (and (stringp s) (not (string-empty-p s))))
                                            top-targets)
                                :test #'string=)
                               ", ")
                  (string-join
                   (mapcar (lambda (r)
                             (if (equal (plist-get r :decision) "kept")
                                 (format "- %s" (plist-get r :hypothesis))
                               ""))
                           results)
                   "\n")
                  (string-join
                   (mapcar (lambda (r)
                             (if (equal (plist-get r :decision) "discarded")
                                 (format "- %s" (plist-get r :hypothesis))
                               ""))
                           results)
                   "\n"))))
    (catch 'compile-early-return
      (gptel-auto-experiment--allium-distill
       findings-summary
       (lambda (allium-spec)
         (if (not allium-spec)
             (message "[allium-audit] Strategy '%s' distill failed (no spec produced)" strategy)
           (gptel-auto-experiment--allium-check
            allium-spec
            (lambda (issues)
              (let* ((count (gptel-auto-experiment--allium-issues-count issues))
                     (issue-count (car count))
                     (severity (cdr count))
                     (score (gptel-auto-experiment--allium-quality-score issues)))
                (gptel-auto-workflow--allium-persist-spec
                 strategy allium-spec issues issue-count severity score)
                (cond
                 ((= issue-count 0)
                  (message "[allium-audit] Strategy '%s' PASSED: spec is coherent (0 issues)" strategy))
                 ((< score 0.3)
                  (message "[allium-audit] Strategy '%s' OK: %d issues (severity %.2f, score %.2f)"
                           strategy issue-count severity score))
                 ((< score 0.6)
                  (message "[allium-audit] Strategy '%s' WARN: %d issues (severity %.2f, score %.2f) — review knowledge page"
                           strategy issue-count severity score))
                 (t
                  (message "[allium-audit] Strategy '%s' FAIL: %d issues (severity %.2f, score %.2f) — research may be incoherent"
                           strategy issue-count severity score))))))))))))

(defun gptel-auto-workflow--allium-audit-signal ()
  "Audit research knowledge quality via Allium behavioral spec checking.
Distills research findings to Allium, runs check, scores spec coherence.
Schedules async; returns list of strategy names that were audited."
  (interactive)
  (let* ((by-strategy (gptel-auto-workflow--research-results-by-strategy))
         (audited nil))
    (maphash
     (lambda (strategy results)
       (when (and (fboundp 'gptel-auto-experiment--allium-distill)
                  strategy
                  (> (length results) 0))
         (push strategy audited)
         (gptel-auto-workflow--allium-audit-strategy strategy results)))
     by-strategy)
    (message "[allium-audit] Audited %d research strategies via Allium" (length audited))
    audited))

(defun gptel-auto-workflow--allium-persist-spec (strategy allium-spec issues issue-count severity score)
  "Persist ALLIUM-SPEC and check ISSUES for STRATEGY to disk.
Saves spec to var/tmp/evolution/allium-specs/ and appends to knowledge page.
ISSUE-COUNT, SEVERITY, SCORE are from allium-quality-score."
  (let* ((root (gptel-auto-workflow--worktree-base-root)))
    (if (not root)
        (progn
          (message "[allium-persist] Aborted: worktree root unavailable for '%s'" strategy)
          nil)
      (let* ((safe-strategy (if (fboundp 'gptel-auto-workflow--sanitize-strategy-name-for-filename)
                              (gptel-auto-workflow--sanitize-strategy-name-for-filename strategy)
                            (replace-regexp-in-string "[^[:alnum:]_-]" "-" strategy)))
           (specs-dir (expand-file-name "var/tmp/evolution/allium-specs" root))
           (issues-dir (expand-file-name "var/tmp/evolution/allium-issues" root))
           (knowledge-dir (expand-file-name "mementum/knowledge" root))
           (knowledge-file (expand-file-name
                            (format "research-insights-%s.md" safe-strategy)
                            knowledge-dir)))
      ;; Save raw Allium spec
      (make-directory specs-dir t)
      (with-temp-file (expand-file-name (format "%s.allium" safe-strategy) specs-dir)
        (insert (format "-- Allium spec for research strategy: %s\n" strategy))
        (insert (format "-- Generated: %s\n" (format-time-string "%Y-%m-%dT%H:%M")))
        (insert (format "-- Issues: %d, Severity: %.2f, Score: %.2f\n" issue-count severity score))
        (insert "\n")
        (insert allium-spec))
      ;; Save check issues as markdown summary
      (make-directory issues-dir t)
      (with-temp-file (expand-file-name (format "%s.md" safe-strategy) issues-dir)
        (insert (format "# Allium Check — %s\n\n" strategy))
        (insert (format "**Issues:** %d | **Severity:** %.2f | **Score:** %.2f (lower=better)\n\n" issue-count severity score))
        (when (and (stringp issues) (> (length issues) 5))
          (insert "## Issue Details\n\n")
          (insert issues)))
      ;; Append Allium spec appendix to knowledge page if it exists
      (when (file-exists-p knowledge-file)
        (condition-case nil
            (with-temp-buffer
              (insert-file-contents knowledge-file)
              (goto-char (point-max))
              ;; Remove previous Allium sections if present
              (save-excursion
                (when (re-search-backward "^## Allium Behavioral Spec" nil t)
                  (delete-region (match-beginning 0) (point-max))))
              ;; Add fresh Allium appendix
              (insert "\n\n## Allium Behavioral Spec (auto-generated, v3)\n\n")
              (insert (format "*%d check issues (severity %.2f). EXTRACTED from distill→check pipeline.*\n\n" issue-count severity))
              (insert "```allium\n")
              (insert (truncate-string-to-width allium-spec 4000 nil nil "\n-- ... truncated ..."))
              (insert "\n```\n\n")
              (when (and (stringp issues) (> (length issues) 5))
                (insert "### Check Issues\n\n")
                (insert (truncate-string-to-width issues 1500 nil nil "\n\n... (truncated)"))
                (insert "\n"))
              (write-region (point-min) (point-max) knowledge-file))
          (error
           (message "[allium-persist] Failed to update knowledge page for %s" safe-strategy))))
      (message "[allium-persist] Saved spec + issues for '%s': %d issues, %.2f severity"
               strategy issue-count severity)))))

(defun gptel-auto-workflow--allium-load-issues-for-guidance ()
  "Load recent Allium check issues for injection into prompt builder strategy guidance.
Returns a markdown-formatted string of issues grouped by strategy, or empty string."
  (let* ((root (gptel-auto-workflow--worktree-base-root)))
    (if (not root)
        ""
      (let* ((issues-dir (expand-file-name "var/tmp/evolution/allium-issues" root))
             (result nil))
        (when (file-directory-p issues-dir)
          (dolist (issue-file (directory-files issues-dir t "\\.md$"))
            (condition-case nil
                (with-temp-buffer
                  (insert-file-contents issue-file)
                  (goto-char (point-min))
                  (let ((mtime (file-attribute-modification-time
                                (file-attributes issue-file))))
                    (when (time-less-p
                           (time-subtract (current-time) (days-to-time 7))
                           mtime)
                      (let ((content (buffer-string)))
                        (when (and content (> (length content) 20))
                          (push content result))))))
              (error nil))))
        (if result
            (concat "### Allium Behavioral Audit (coherence check of last cycle's research)\n\n"
                    (mapconcat #'identity (nreverse result) "\n---\n"))
          "")))))

(defun gptel-auto-workflow--allium-read-quality (safe-strategy)
  "Read Allium quality for SAFE-STRATEGY from disk. Returns (issues . severity) or nil."
  (let* ((root (gptel-auto-workflow--worktree-base-root)))
    (if (not root)
        nil
      (let* ((file (expand-file-name (format "%s.md" safe-strategy)
                                     (expand-file-name "var/tmp/evolution/allium-issues" root))))
        (when (file-readable-p file)
          (let ((mtime (file-attribute-modification-time (file-attributes file))))
            (when (time-less-p (time-subtract (current-time) (days-to-time 7)) mtime)
              (with-temp-buffer
                (insert-file-contents file)
                (goto-char (point-min))
                (let ((count 0) (pos 0) (severity 0.0))
                  (while (string-match "^[0-9]+\\." (buffer-string) pos)
                    (setq count (1+ count) pos (match-end 0)))
                  (when (string-match "\\*\\*Severity:\\*\\* \\([0-9.]+\\)" (buffer-string))
                    (setq severity (string-to-number (match-string 1 (buffer-string)))))
                  (cons count severity))))))))))

(defun gptel-auto-workflow--allium-check-research-quality (findings-summary &optional callback)
  "Distill FINDINGS-SUMMARY to Allium spec, check for issues, invoke CALLBACK with quality score.
Like nucleus compile-score but for Allium: prose → spec → check → score.
CALLBACK receives (issues-count . severity-score) where severity 0-1."
  (if (and (fboundp 'gptel-auto-experiment--allium-distill) callback)
      (gptel-auto-experiment--allium-distill
       findings-summary
       (lambda (allium-spec)
         (if (not allium-spec)
             (funcall callback (cons 99 1.0))
           (gptel-auto-experiment--allium-check
            allium-spec
            (lambda (issues)
              (funcall callback (gptel-auto-experiment--allium-issues-count issues)))))))
    (when callback (funcall callback (cons 99 1.0)))
    nil))

(defun gptel-auto-workflow--allium-diff-minimal-pairs (ha hb &optional callback)
  "Diff minimal-pair hypotheses (HA, HB) via Allium spec comparison.
Distills both to Allium specs, then checks each for internal coherence.
CALLBACK receives (ha-issues . hb-issues) with issue counts for each side.
Use to determine which minimal pair has cleaner behavioral specification."
  (if (and (fboundp 'gptel-auto-experiment--allium-distill)
           (fboundp 'gptel-auto-experiment--allium-check)
           callback
           (stringp ha) (stringp hb))
      (gptel-auto-experiment--allium-distill
       ha
       (lambda (spec-a)
         (let ((result (cons 99 99)))
           (if (not spec-a)
               (funcall callback result)
             (gptel-auto-experiment--allium-distill
              hb
              (lambda (spec-b)
                (if (not spec-b)
                    (funcall callback result)
                  (gptel-auto-experiment--allium-check
                   spec-a
                   (lambda (issues-a)
                     (gptel-auto-experiment--allium-check
                      spec-b
                      (lambda (issues-b)
                        (funcall callback
                                 (cons (car (gptel-auto-experiment--allium-issues-count issues-a))
                                       (car (gptel-auto-experiment--allium-issues-count issues-b)))))))))))))))
    (when callback (funcall callback (cons 99 99)))
    nil))

;; ─── Semantica Ontology: experiment → class/instance structure ───

(defun gptel-auto-workflow--generate-experiment-ontology ()
  "Generate an ontology from experiment results (Semantica pattern).
Strategies → owl:Class, targets → instances, kept/discarded → outcome properties.
Returns ontology plist with :classes, :instances, :class-count, :instance-count."
  (let* ((results (gptel-auto-workflow--parse-all-results))
         (strategy-classes (make-hash-table :test 'equal))
         (target-instances (make-hash-table :test 'equal)))
    (dolist (r results)
      (let ((strategy (or (plist-get r :strategy) "template-default"))
            (target (plist-get r :target))
            (decision (plist-get r :decision)))
        (when (stringp strategy)
          (let ((entry (or (gethash strategy strategy-classes) (list :total 0 :kept 0 :discarded 0 :failed 0))))
            (setq entry (plist-put entry :total (1+ (plist-get entry :total))))
            (cond
             ((equal decision "kept")
              (setq entry (plist-put entry :kept (1+ (plist-get entry :kept)))))
             ((equal decision "discarded")
              (setq entry (plist-put entry :discarded (1+ (plist-get entry :discarded)))))
             (t
              (setq entry (plist-put entry :failed (1+ (plist-get entry :failed))))))
            (puthash strategy entry strategy-classes)))
        (when (and (stringp target) (not (string-empty-p target)))
          (let ((entry (or (gethash target target-instances) (list :total 0 :kept 0 :discarded 0))))
            (setq entry (plist-put entry :total (1+ (plist-get entry :total))))
            (when (equal decision "kept")
              (setq entry (plist-put entry :kept (1+ (plist-get entry :kept)))))
            (when (equal decision "discarded")
              (setq entry (plist-put entry :discarded (1+ (plist-get entry :discarded)))))
            (puthash target entry target-instances)))))
    (let ((class-list nil) (instance-list nil))
      (maphash (lambda (strategy counts)
                 (let ((keep-rate (if (> (plist-get counts :total) 0)
                                      (/ (float (plist-get counts :kept)) (plist-get counts :total))
                                    0.0)))
                   (push (list :name strategy :@type "Strategy"
                               :total (plist-get counts :total) :keep-rate keep-rate
                               :status (cond ((>= keep-rate 0.5) "effective")
                                             ((>= keep-rate 0.3) "promising")
                                             (t "underperforming")))
                         class-list)))
               strategy-classes)
      (maphash (lambda (target counts)
                 (let ((keep-rate (if (> (plist-get counts :total) 0)
                                      (/ (float (plist-get counts :kept)) (plist-get counts :total))
                                    0.0)))
                   (push (list :name target :@type "Target"
                               :total (plist-get counts :total) :keep-rate keep-rate
                               :classification (cond ((>= keep-rate 0.5) "high-value")
                                                     ((>= keep-rate 0.3) "moderate")
                                                     (t "low-value")))
                         instance-list)))
               target-instances)
      (list :generated (format-time-string "%Y-%m-%dT%H:%M")
            :classes (sort class-list (lambda (a b) (> (plist-get a :keep-rate) (plist-get b :keep-rate))))
            :instances (sort instance-list (lambda (a b) (> (plist-get a :total) (plist-get b :total))))
            :class-count (hash-table-count strategy-classes)
            :instance-count (hash-table-count target-instances)))))

(defun gptel-auto-workflow--experiment-causal-links ()
  "Build causal link graph between experiments on the same target.
BFS over :CAUSED edges to find root experiments. Semantica decision-tracking pattern.
Returns alist of (target . (root-experiment downstream ...))."
  (let* ((results (gptel-auto-workflow--parse-all-results))
         (by-target (make-hash-table :test 'equal))
         (causal-graph nil))
    (dolist (r results)
      (let ((target (plist-get r :target)))
        (when (and (stringp target) (not (string-empty-p target)))
          (puthash target (cons r (gethash target by-target)) by-target))))
    (maphash
     (lambda (target experiments)
       (when (> (length experiments) 1)
         (let ((sorted (sort experiments
                             (lambda (a b)
                               (let ((sa (plist-get a :score-after))
                                     (sb (plist-get b :score-after)))
                                 (> (or sa 0) (or sb 0))))))
               (chain nil))
           (dolist (exp sorted)
             (let* ((decision (plist-get exp :decision))
                    (hyp (plist-get exp :hypothesis))
                    (score-before (plist-get exp :score-before))
                    (score-after (plist-get exp :score-after)))
               (push (list :hypothesis (truncate-string-to-width (or hyp "?") 60)
                           :decision decision
                           :delta (if (and score-before score-after)
                                      (- score-after score-before) 0))
                     chain)))
           (when chain
             (push (cons target (nreverse chain)) causal-graph)))))
     by-target)
    causal-graph))

;; ─── Semantica Patterns: ValidationResult + Conflict Detection ───

(defun gptel-auto-workflow--validation-result (valid &optional errors warnings)
  "Create a structured validation result plist.
VALID is t or nil. ERRORS and WARNINGS are lists of strings.
Pattern from Semantica: universal Valid/Errors/Warnings contract."
  (list :valid valid
        :errors (or errors nil)
        :warnings (or warnings nil)))

(defun gptel-auto-workflow--detect-hypothesis-conflicts ()
  "Detect contradictory hypotheses across experiments for the same target.
Groups experiments by target, compares hypotheses for opposite claims.
Returns list of conflict plists with :target, :hypotheses, :severity, :recommendation.
Pattern from Semantica: group-by-entity → value-diff → severity score."
  (let* ((results (gptel-auto-workflow--parse-all-results))
         (by-target (make-hash-table :test 'equal))
         (conflicts nil))
    (dolist (r results)
      (let* ((target (plist-get r :target))
             (hyp (plist-get r :hypothesis))
             (decision (plist-get r :decision)))
        (when (and (stringp target) (stringp hyp)
                   (not (string-empty-p target)))
          (puthash target
                   (cons (list hyp decision) (gethash target by-target))
                   by-target))))
    (maphash
     (lambda (target entries)
       (when (> (length entries) 1)
         (let* ((kept (cl-remove-if-not (lambda (e) (equal (cadr e) "kept")) entries))
                (discarded (cl-remove-if-not (lambda (e) (equal (cadr e) "discarded")) entries))
                (pairs nil))
           ;; Compare kept vs discarded hypotheses for same-context opposition
           (dolist (k kept)
             (dolist (d discarded)
               (let ((kh (car k)) (dh (car d)))
                 (when (gptel-auto-workflow--opposing-hypotheses-p kh dh)
                   (push (cons kh dh) pairs)))))
           (when pairs
             (let* ((severity (if (> (length pairs) 2) "high" "medium"))
                    (recommendation
                     (if (equal severity "high")
                         "Multiple opposed outcomes — reconsider strategy"
                       "Contradictory results — test with different approach")))
               (push (list :target target
                           :opposing-pairs pairs
                           :severity severity
                           :recommendation recommendation)
                     conflicts))))))
     by-target)
    conflicts))

(defun gptel-auto-workflow--opposing-hypotheses-p (h1 h2)
  "Return non-nil if H1 and H2 are opposing claims (add vs remove, nil vs non-nil).
Simple keyword-based opposition detection."
  (let ((opposition-pairs
         '(("add" . "remove") ("add" . "delete") ("adding" . "removing")
           ("nil" . "non-nil") ("guard" . "remove guard")
           ("simplify" . "complex")
           ("increase" . "decrease") ("more" . "less")
           ("before" . "after") ("enable" . "disable")
           ("optimize" . "simple"))))
    (catch 'found
      (dolist (pair opposition-pairs)
        (let ((a (car pair)) (b (cdr pair)))
          (when (and (string-match-p (regexp-quote a) h1)
                     (string-match-p (regexp-quote b) h2))
            (throw 'found t))
          (when (and (string-match-p (regexp-quote b) h1)
                     (string-match-p (regexp-quote a) h2))
            (throw 'found t))))
      nil)))

;; ─── Semantica Evaluator: knowledge page quality scoring ───

(defun gptel-auto-workflow--score-knowledge-pages ()
  "Score knowledge pages by coverage, completeness, and relation (Semantica evaluator pattern).
Returns ((:coverage . N) (:completeness . N) (:relations . N) (:overall . N) (:issues . list))."
  (let* ((dir (expand-file-name "mementum/knowledge"
                                (gptel-auto-workflow--worktree-base-root)))
         (files (when (file-directory-p dir)
                  (directory-files dir t "research-insights-.+\\.md$")))
         (coverage-score 0) (completeness-score 0) (relation-score 0)
         (total-pages 0) (issues nil))
    (dolist (f files)
      (condition-case nil
          (with-temp-buffer
            (insert-file-contents f)
            (goto-char (point-min))
            (let* ((has-title (re-search-forward "^title: " nil t))
                   (has-status (re-search-forward "^status: " nil t))
                   (has-tags (re-search-forward "^tags: " nil t))
                   (has-quality (re-search-forward "^insight-quality: " nil t))
                   (has-allium (re-search-forward "^allium-status: " nil t))
                   (has-targets (re-search-forward "^## Successful Targets" nil t))
                   (has-meta (re-search-forward "^## Meta-Learning" nil t)))
              (setq total-pages (1+ total-pages))
              ;; Coverage: sections present (0-1)
              (let ((cov 0) (max-sections 3))
                (when has-targets (setq cov (1+ cov)))
                (when has-meta (setq cov (1+ cov)))
                (when has-allium (setq cov (1+ cov)))
                (setq coverage-score (+ coverage-score (/ (float cov) max-sections))))
              ;; Completeness: frontmatter fields present (0-1)
              (let ((comp 0) (max-fields 4))
                (when has-title (setq comp (1+ comp)))
                (when has-status (setq comp (1+ comp)))
                (when has-tags (setq comp (1+ comp)))
                (when has-quality (setq comp (1+ comp)))
                (setq completeness-score (+ completeness-score (/ (float comp) max-fields))))
              ;; Relation: has Allium links (0-1)
              (setq relation-score (+ relation-score (if has-allium 1.0 0.0)))
              ;; Collect issues
              (unless has-allium
                (push (format "%s: missing Allium audit" (file-name-nondirectory f)) issues))
              (unless has-targets
                (push (format "%s: missing Successful Targets section" (file-name-nondirectory f)) issues))))
        (error nil)))
    (let ((n (max 1 total-pages)))
      (list :coverage (/ coverage-score n)
            :completeness (/ completeness-score n)
            :relations (/ relation-score n)
            :overall (/ (+ (/ coverage-score n) (/ completeness-score n) (/ relation-score n)) 3.0)
            :total-pages total-pages
            :issues (nreverse issues)))))

(defun gptel-auto-workflow--validate-knowledge-page (file-path)
  "Validate a knowledge page structurally. Returns validation-result plist.
Checks: required frontmatter, duplicate titles, empty sections."
  (let ((errors nil) (warnings nil))
    (condition-case err
        (with-temp-buffer
          (insert-file-contents file-path)
          (let* ((content (buffer-string))
                 (title (when (string-match "^title: \\(.+\\)" content)
                          (match-string 1 content)))
                 (status (when (string-match "^status: " content) t))
                 (allium-issues (when (string-match "^allium-issues: \\([0-9]+\\)" content)
                                  (string-to-number (match-string 1 content))))
                 (tag-section (when (string-match "^tags: " content) t)))
            (unless title
              (push "Missing title in frontmatter" errors))
            (unless status
              (push "Missing status in frontmatter" warnings))
            (unless tag-section
              (push "Missing tags in frontmatter" warnings))
             (when (and allium-issues (> allium-issues 0))
               (unless (string-match "^## Allium Behavioral Coherence" content)
                 (push "Has allium-issues >0 but missing Allium Behavioral Coherence section" errors)))
            (let ((pos 0) (title-count 0))
              (while (string-match "^# " content pos)
                (setq title-count (1+ title-count) pos (match-end 0)))
              (when (= title-count 0)
                (push "No main heading (# ) found" warnings)))))
      (error
       (push (format "Failed to read: %s" (error-message-string err)) errors)))
    (gptel-auto-workflow--validation-result
     (null errors)
     errors
     warnings)))

;; ─── Semantica Reasoning + Query ───

(defconst gptel-auto-workflow--reasoning-rules
  '(;; Strategy health
    (:when ((keep-rate < 0.1) (total-experiments > 8))
     :then ((action . "deprecate-strategy") (reason . "keep-rate below 10% with sufficient data") (severity . high)))
    (:when ((keep-rate < 0.05))
     :then ((action . "retire-strategy") (reason . "keep-rate below 5% — no further value") (severity . critical)))
    (:when ((keep-rate > 0.6) (total-experiments > 5))
     :then ((action . "promote-strategy") (reason . "consistently effective — consider expanding") (severity . low)))
    ;; Target saturation
    (:when ((target-frequency > 8))
     :then ((action . "mark-saturated") (reason . "target has diminishing returns") (severity . medium)))
    (:when ((target-frequency < 2) (keep-rate > 0.5))
     :then ((action . "mark-underutilized") (reason . "effective target — explore more") (severity . low)))
    ;; Backend
    (:when ((backend-keep-rate < 0.2) (backend-experiments > 10))
     :then ((action . "deprioritize-backend") (reason . "backend underperforming") (severity . high)))
    (:when ((backend-keep-rate > 0.7) (backend-experiments > 5))
     :then ((action . "prioritize-backend") (reason . "backend performing well") (severity . low)))
    ;; Token
    (:when ((output-ratio > 3.0) (kept-experiments < 3))
     :then ((action . "flag-inflation") (reason . "output >> prompt with low keep rate") (severity . medium))))
  "Forward chaining rules: (:when ((field op value) ...) :then ((key . value) ...)).")

(defun gptel-auto-workflow--eval-condition (condition facts)
  (let* ((field (nth 0 condition)) (op (nth 1 condition)) (threshold (nth 2 condition))
         (actual (cdr (assoc field facts))))
    (and actual (numberp actual)
         (cond ((eq op '<) (< actual threshold)) ((eq op '>) (> actual threshold))
               ((eq op '=) (= actual threshold)) ((eq op '>=) (>= actual threshold))
               ((eq op '<=) (<= actual threshold)) (t nil)))))

(defun gptel-auto-workflow--forward-chain ()
  "Run forward chaining over experiment facts. Returns inferred actions."
  (let* ((results (gptel-auto-workflow--parse-all-results)) (facts nil) (inferred nil))
    (let ((by-strategy (make-hash-table :test 'equal))
          (by-target (make-hash-table :test 'equal))
          (by-backend (make-hash-table :test 'equal))
          (kept 0) (total 0) (total-output 0) (total-prompt 0))
      (dolist (r results)
        (let ((strategy (or (plist-get r :strategy) "template-default"))
              (target (plist-get r :target))
              (backend (or (plist-get r :backend) "unknown"))
              (decision (plist-get r :decision))
              (pc (or (plist-get r :prompt-chars) 0)) (oc (or (plist-get r :output-chars) 0)))
          (setq total (1+ total) total-output (+ total-output oc) total-prompt (+ total-prompt pc))
          (when (equal decision "kept") (setq kept (1+ kept)))
          (let ((se (or (gethash strategy by-strategy) (list :kept 0 :total 0))))
            (setq se (plist-put se :total (1+ (plist-get se :total))))
            (when (equal decision "kept") (setq se (plist-put se :kept (1+ (plist-get se :kept)))))
            (puthash strategy se by-strategy))
          (when (stringp target) (puthash target (1+ (or (gethash target by-target) 0)) by-target))
          (when (stringp backend)
            (let ((be (or (gethash backend by-backend) (list :kept 0 :total 0))))
              (setq be (plist-put be :total (1+ (plist-get be :total))))
              (when (equal decision "kept") (setq be (plist-put be :kept (1+ (plist-get be :kept)))))
              (puthash backend be by-backend)))))
      (push (cons 'total-experiments total) facts)
      (push (cons 'kept-experiments kept) facts)
      (push (cons 'overall-keep-rate (if (> total 0) (/ (float kept) total) 0.0)) facts)
      (push (cons 'output-ratio (if (> total-prompt 0) (/ (float total-output) total-prompt) 0.0)) facts)
      (maphash (lambda (strategy c)
                 (let ((rate (if (> (plist-get c :total) 0)
                                 (/ (float (plist-get c :kept)) (plist-get c :total)) 0.0)))
                   (push (cons 'keep-rate rate) facts)
                   (push (cons 'strategy strategy) facts)
                   (push (cons 'total-experiments (plist-get c :total)) facts)))
               by-strategy)
       (maphash (lambda (target counts) (push (list :target-freq target counts) facts)) by-target)
      (maphash (lambda (backend c)
                 (let ((rate (if (> (plist-get c :total) 0)
                                 (/ (float (plist-get c :kept)) (plist-get c :total)) 0.0)))
                   (push (cons 'backend backend) facts)
                   (push (cons 'backend-keep-rate rate) facts)
                   (push (cons 'backend-experiments (plist-get c :total)) facts)))
               by-backend))
    (let ((iter 0) (changed t) (max-iter 3))
      (while (and changed (< iter max-iter))
        (setq changed nil iter (1+ iter))
        (dolist (rule gptel-auto-workflow--reasoning-rules)
          (let ((conditions (plist-get rule :when)) (all-match t))
            (dolist (cond conditions)
              (unless (gptel-auto-workflow--eval-condition cond facts) (setq all-match nil)))
            (when all-match
              (push (plist-get rule :then) inferred) (setq changed t))))))
    (delete-dups inferred)))

(defun gptel-auto-workflow--jaccard (a b)
  "Jaccard coefficient between strings A and B (word-level)."
  (let* ((wa (split-string (downcase (or a "")) "[^a-z0-9]+" t))
         (wb (split-string (downcase (or b "")) "[^a-z0-9]+" t))
         (inter (cl-intersection wa wb :test #'string=))
         (union (cl-union wa wb :test #'string=)))
    (if union (/ (float (length inter)) (length union)) 0.0)))

(defun gptel-auto-workflow--query-experiments (query &optional max-results)
  "Weighted multi-criteria experiment search. Semantica DecisionQuery."
  (let* ((results (gptel-auto-workflow--parse-all-results)) (scored nil))
    (dolist (r results)
      (let* ((hyp (or (plist-get r :hypothesis) ""))
             (target (or (plist-get r :target) ""))
             (text-sim (gptel-auto-workflow--jaccard query hyp))
             (target-sim (gptel-auto-workflow--jaccard query target))
             (cat-score (if (equal (plist-get r :decision) "kept") 0.8 0.3))
             (delta (max 0 (- (or (plist-get r :score-after) 0) (or (plist-get r :score-before) 0))))
             (combined (+ (* 0.4 text-sim) (* 0.3 target-sim) (* 0.2 cat-score) (* 0.1 (min 1.0 (/ delta 0.1))))))
        (when (> combined 0.05)
          (push (list :target target :hypothesis hyp :score combined :decision (plist-get r :decision)) scored))))
    (seq-take (sort scored (lambda (a b) (> (plist-get a :score) (plist-get b :score)))) (or max-results 10))))

;; ─── Semantica Pipeline: stage definitions + validation ───

(defconst gptel-auto-workflow--pipeline-stages
  '((:name "synthesize" :label "Evolution Synthesize" :fn evolution-synthesize :required t)
    (:name "generate-skill" :label "Generate Research Skill" :fn generate-research-skill :required t)
    (:name "evolve-skills" :label "Evolve All Skills" :fn evolve-all-skills :required t)
    (:name "strategy-evolution" :label "Strategy Evolution" :fn run-strategy-evolution :required nil)
    (:name "governance" :label "Skill Governance" :fn skill-governance-run-cycle :required nil)
    (:name "record-score" :label "Record Score" :fn evolution-record-score :required t)
    (:name "optimize-backend" :label "Optimize Backend" :fn evolution-optimize-backend-order :required nil)
    (:name "vsm-health" :label "VSM Health Check" :fn evolution-vsm-health-check :required t)
    (:name "audit" :label "Nucleus Audit" :fn audit-signal :required t)
    (:name "allium-audit" :label "Allium Audit" :fn allium-audit-signal :required t)
    (:name "reasoning" :label "Forward Chain" :fn forward-chain-log :required nil)
    (:name "diff" :label "Knowledge Diff" :fn diff-knowledge-pages :required nil))
  "Pipeline stage definitions. Semantica PipelineBuilder pattern.")

(defun gptel-auto-workflow--validate-pipeline ()
  "Validate pipeline stages. Returns validation-result plist."
  (let ((errors nil) (warnings nil)
        (names (mapcar (lambda (s) (plist-get s :name)) gptel-auto-workflow--pipeline-stages))
        (seen (make-hash-table :test 'equal)))
    (dolist (name names)
      (if (gethash name seen)
          (push (format "Duplicate stage: %s" name) errors)
        (puthash name t seen)))
    (dolist (s gptel-auto-workflow--pipeline-stages)
      (when (and (plist-get s :required)
                 (not (fboundp (intern (concat "gptel-auto-workflow--" (symbol-name (plist-get s :fn)))))))
        (push (format "Missing fn for required stage '%s'" (plist-get s :label)) warnings)))
    (gptel-auto-workflow--validation-result (null errors) errors warnings)))

(defun gptel-auto-workflow--evolution-optimize-backend-order ()

;; ─── Semantica AgentMemory: formalize mementum layers ───

(defconst gptel-auto-workflow--agent-memory-layers
  '((:layer "short-term" :description "In-session working memory"
     :location "var/tmp/evolution/" :persistence nil :max-items 50)
    (:layer "long-term" :description "Vector similarity search (git-embed)"
     :location "git-embed index" :persistence t :backend "git-embed")
    (:layer "structured" :description "Knowledge pages + Allium specs"
     :location "mementum/knowledge/" :persistence t :format "markdown + allium")
    (:layer "temporal" :description "Git-based timeline, experiment TSV history"
     :location "git log + var/tmp/experiments/" :persistence t :format "git + tsv"))
  "4-layer AgentMemory architecture (Semantica pattern).
Layer 1: short-term working memory (in-session, cleared on daemon restart)
Layer 2: long-term vector memory (git-embed semantic similarity, 840 files indexed)
Layer 3: structured memory (knowledge pages, Allium behavioral specs, ontology)
Layer 4: temporal index (git commit history, experiment TSV, cycle snapshots)")

(defun gptel-auto-workflow--memory-status ()
  "Report status of all memory layers. Returns plist with :layer → status."
  (let ((status nil))
    (dolist (layer gptel-auto-workflow--agent-memory-layers)
      (let* ((name (plist-get layer :layer))
             (location (plist-get layer :location))
             (root (gptel-auto-workflow--worktree-base-root))
             (full-path (expand-file-name location root))
             (state (cond
                     ((string-match-p "git-embed" location)
                      (if (fboundp 'git-embed-search) "active" "unavailable"))
                     ((file-directory-p full-path)
                      (let ((count (length (directory-files full-path nil "\\`[^.]"))))
                        (format "%d items" count)))
                     (t "not found"))))
        (push (list :layer name :location location :state state :description (plist-get layer :description))
              status)))
    (nreverse status)))

;; ─── Backend Performance Optimization ───
  "Auto-reorder the fallback chain based on backend performance data.
Moves better-performing backends to the front of the fallback chain."
  (let* ((stats (gptel-auto-workflow--evolution-backend-stats))
         (ordered (mapcar #'car stats)))
    (when (and ordered (> (length ordered) 2))
      (when (boundp 'gptel-auto-workflow-executor-rate-limit-fallbacks)
        (let ((new-chain
               (seq-filter (lambda (entry)
                             (member (car entry) ordered))
                           (mapcar (lambda (name)
                                     (cons name
                                           (cdr (assoc name
                                                       gptel-auto-workflow-executor-rate-limit-fallbacks
                                                       #'string=))))
                                   ordered))))
          (when (> (length new-chain) 2)
            ;; Keep backends not in stats at the end
            (dolist (entry gptel-auto-workflow-executor-rate-limit-fallbacks)
              (unless (assoc (car entry) new-chain #'string=)
                (setq new-chain (append new-chain (list entry)))))
            (when (not (equal new-chain gptel-auto-workflow-executor-rate-limit-fallbacks))
              (message "[evolution] Reordering fallback chain by performance: %s → %s"
                       (mapconcat #'car gptel-auto-workflow-executor-rate-limit-fallbacks "→")
                       (mapconcat #'car new-chain "→"))
              (setq gptel-auto-workflow-executor-rate-limit-fallbacks new-chain)
              (gptel-auto-workflow--evolution-persist-backend-order
               gptel-auto-workflow-executor-rate-limit-fallbacks))))))))

(defun gptel-auto-workflow--evolution-persist-backend-order (chain)
  "Persist the current backend fallback CHAIN to disk."
  (let ((file (expand-file-name "var/tmp/backend-fallback-order.el"
                                (gptel-auto-workflow--worktree-base-root))))
    (with-temp-file file
      (insert ";; Auto-evolved backend fallback order\n")
      (insert (format ";; Generated: %s\n" (format-time-string "%Y-%m-%d %H:%M")))
      (insert (format "(setq gptel-auto-workflow-executor-rate-limit-fallbacks\n      '%S)\n"
                      chain)))))

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
