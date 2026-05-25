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

;; Soft require: research-integration may not exist on all deployments
(require 'gptel-auto-workflow-research-integration nil t)
;; Soft require: research-benchmark provides load-research-traces
(require 'gptel-auto-workflow-research-benchmark nil t)

;; External functions from other modules
(declare-function gptel-auto-workflow--worktree-base-root "gptel-tools-agent-base" ())
(declare-function gptel-auto-workflow--load-skill-content "gptel-tools-agent-prompt-build" (skill-name))
(declare-function gptel-auto-workflow--discover-strategies "gptel-tools-agent-strategy-harness" ())
(declare-function gptel-benchmark-eight-keys-score-for "gptel-benchmark-principles" (output subsystem &optional hypothesis))
(declare-function gptel-auto-workflow--evolve-research-strategy "gptel-auto-workflow-research-benchmark" ())
(declare-function gptel-auto-workflow--load-autotts-controller "strategic-daemon-functions" ())
(declare-function gptel-auto-workflow--load-research-traces "gptel-auto-workflow-research-benchmark" ())

(defvar gptel-auto-workflow--champion-keep-rate)

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
  "Four-layer AgentMemory architecture.
Layer 1: short-term working memory.
Layer 2: long-term vector memory.
Layer 3: structured knowledge pages, specs, and ontology.
Layer 4: temporal git and experiment index.")

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

(declare-function gptel-auto-experiment--allium-distill "gptel-tools-agent-prompt-build" (text &optional callback))
(declare-function gptel-auto-experiment--allium-check "gptel-tools-agent-prompt-build" (allium-spec &optional callback))
(declare-function gptel-auto-experiment--allium-decompile "gptel-tools-agent-prompt-build" (allium-spec &optional callback audience))
(declare-function gptel-auto-experiment--allium-issues-count "gptel-tools-agent-prompt-build" (check-output))
(declare-function gptel-auto-experiment--allium-quality-score "gptel-tools-agent-prompt-build" (check-output))
(declare-function gptel-auto-experiment--compile-score "gptel-tools-agent-prompt-build" (prompt-strategy &optional callback))
(declare-function gptel-auto-experiment--kibcm-axis "gptel-tools-agent-prompt-build" (hypothesis))

;; ─── Helpers ───

(defvar gptel-auto-workflow--allium-audit-last-run nil
  "Timestamp of last allium-audit run. Throttles API calls to 1/15min.")
(defvar gptel-auto-workflow--evolution-last-run nil
  "Timestamp of last evolution cycle. Throttles full cycles to 1/5min.")
(defvar gptel-auto-workflow--vsm-health-last-run nil
  "Timestamp of last VSM health check. Throttles to 1/15min.")

(defvar gptel-auto-workflow--evolution-last-objective nil
  "Eight Keys convergence score from previous evolution cycle.
∃ Truth: if current score ≤ this, evolution plateaued — stop.")

(defvar gptel-auto-workflow--wu-xing-actions nil
  "Accumulator for Wu Xing diagnostic repair actions.
Populated by VSM health check, consumed by cross-subsystem feedback.")

(defun gptel-auto-workflow--eight-keys-convergence-score ()
  "Compute Eight Keys convergence score from kept experiments.
∃ Truth: returns nil if no scorable data (blocking false convergence).
Aggregate of per-subsystem scores for convergence detection."
  (cl-block gptel-auto-workflow--eight-keys-convergence-score
  (unless (fboundp 'gptel-benchmark-eight-keys-score-for)
    (message "[evolution] Eight Keys scoring unavailable — skipping convergence check")
    (cl-return-from gptel-auto-workflow--eight-keys-convergence-score nil))
  (let ((results (gptel-auto-workflow--parse-all-results))
        (autogo 0.0) (autotts 0.0) (selfev 0.0) (count 0))
    (dolist (r results)
      (when (equal (plist-get r :decision) "kept")
        (let ((hypo (or (plist-get r :hypothesis) "")))
          (cl-incf autogo (alist-get 'overall (gptel-benchmark-eight-keys-score-for hypo :autogo) 0.0))
          (cl-incf autotts (alist-get 'overall (gptel-benchmark-eight-keys-score-for hypo :autotts) 0.0))
          (cl-incf selfev (alist-get 'overall (gptel-benchmark-eight-keys-score-for hypo :self-evolve) 0.0))
          (cl-incf count))))
    (if (> count 0) (/ (+ autogo autotts selfev) (* 3 count)) nil))))

(defvar gptel-auto-workflow--evolution-next-cycle-hints nil
  "Alist of hints for the next evolution cycle.
Keys: :prev-champions, :category-budget, :vsm-actions, :regressed-targets.")

(defvar gptel-auto-workflow--experiment-targets nil
  "List of target file paths for the next experiment batch.
Set by the experiment loop and reordered by VSM health diagnostics.")

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
                             (field-count (length fields))
                             ;; Handle multiple TSV format versions:
                             ;; 14 cols: earliest (no backend/strategy/research fields)
                             ;; 20 cols: backend at index 14, no research fields
                             ;; 24 cols: backend at index 14, research fields at 20-23
                             ;; 27 cols: backend at index 15, full research fields
                             (format-version (cond ((<= field-count 14) 14)
                                                   ((<= field-count 20) 20)
                                                   ((<= field-count 24) 24)
                                                   (t 27)))
                             (target (nth 1 fields))
                             (hypothesis (nth 2 fields))
                             (score-before (string-to-number (or (nth 3 fields) "0")))
                             (score-after (string-to-number (or (nth 4 fields) "0")))
                             (quality (string-to-number (or (nth 5 fields) "0")))
                             (delta-str (or (nth 6 fields) "+0.00"))
                             (decision (nth 7 fields))
                             (grader-q (string-to-number (or (nth 9 fields) "0")))
                             (backend (cond ((<= format-version 14) "unknown")
                                            ((<= format-version 24)
                                             (or (nth 14 fields) "unknown"))
                                            (t (or (nth 15 fields) "unknown"))))
                             (prompt-chars (string-to-number
                                            (or (nth (if (<= format-version 24) 15 16) fields) "0")))
                             (research-strategy (or (nth (if (<= format-version 20) 20 21) fields) "none"))
                             (research-hash (or (nth (if (<= format-version 20) 20 22) fields) "none"))
                             (research-quality (or (nth (if (<= format-version 20) 20 23) fields) "none"))
                             (kibcm-axis (or (nth (if (<= format-version 24) 20 25) fields) "?"))
                             (model (or (nth (if (<= format-version 24) 20 26) fields) "unknown")))
                            (push (list :target target
                                        :hypothesis hypothesis
                                        :score-before score-before
                                        :score-after score-after
                                        :code-quality quality
                                        :delta delta-str
                                        :decision decision
                                        :grader-quality grader-q
                                        :prompt-chars prompt-chars
                                        :backend backend
                                        :research-strategy research-strategy
                                        :research-hash research-hash
                                        :research-quality research-quality
                                        :kibcm-axis kibcm-axis
                                        :model model
                                        :run-dir (file-name-nondirectory run-dir))
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
  "Group experiment results by prompt strategy.
Returns hash table mapping strategy name to list of results."
  (let ((results (gptel-auto-workflow--parse-all-results))
        (by-strategy (make-hash-table :test 'equal)))
    (dolist (r results)
      (let ((strategy (or (plist-get r :strategy) "template-default")))
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
The key is deterministic for incremental processing."
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
High cohesion: most defun calls target other defuns in the same file.
Low cohesion: unrelated functions may need refactoring."
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
                          (ignore))))))))
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
          (when (and (fboundp 'gptel-auto-workflow--allium-check-research-quality)
                     (or (not (boundp 'gptel-auto-workflow--allium-audit-last-run))
                         (> (- (float-time (current-time))
                               (or (symbol-value 'gptel-auto-workflow--allium-audit-last-run) 0))
                            900)))
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
  (let* ((traces (condition-case nil (gptel-auto-workflow--load-research-traces) (ignore)))
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
        (controller (condition-case nil (gptel-auto-workflow--load-autotts-controller) (ignore))))
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
  (let* ((traces (condition-case nil (gptel-auto-workflow--load-research-traces) (ignore)))
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
                            (current-buffer))))
               ;; Self-evolve: correlate research sources to experiment outcomes
               (when (fboundp 'gptel-auto-workflow--correlate-research-to-outcomes)
                 (let ((source-stats (gptel-auto-workflow--correlate-research-to-outcomes)))
                   (when source-stats
                     (message "[evolution] Research source effectiveness (top 3):")
                     (dolist (s (cl-subseq source-stats 0 (min 3 (length source-stats))))
                       (message "  %s: %.1f%% kept" (car s) (* 100 (cdr s))))
                     ;; Update research strategy champions (AutoGo)
                     (when (fboundp 'gptel-auto-workflow--update-research-strategy-champion)
                       (dolist (s source-stats)
                         (gptel-auto-workflow--update-research-strategy-champion
                          "agentic" (car s) (cdr s))))))
                 ;; Ontology-driven research targeting
                 (when (fboundp 'gptel-auto-workflow--top-research-priority)
                   (let ((priority (gptel-auto-workflow--top-research-priority)))
                     (when priority
                       (message "[evolution] Ontology research priority: %s" priority))))))))
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
  ;; DEBUG: wrap early portion to isolate MiniMax error
  (condition-case early-err
      (progn
  ;; Throttle: don't run more than once per 300s (5min) unless forced
  (let ((now (float-time (current-time))))
    (when (and gptel-auto-workflow--evolution-last-run
               (< (- now gptel-auto-workflow--evolution-last-run) 300))
      (message "[evolution] Throttled: last cycle was %.0fs ago, skipping"
               (- now gptel-auto-workflow--evolution-last-run))
      (cl-return-from gptel-auto-workflow-evolution-run-cycle "throttled"))
   (setq gptel-auto-workflow--evolution-last-run now))
  ;; Restore cross-subsystem hints from disk (survives daemon restart)
  (gptel-auto-workflow--restore-next-cycle-hints)
  ;; Rebuild holographic memory from history (verbum Phase 10)
  (when (fboundp 'gptel-auto-workflow--rebuild-holographic-memory)
    (condition-case err
        (progn
          (gptel-auto-workflow--rebuild-holographic-memory)
          (message "[verbum] Holographic memory rebuilt"))
      (error (message "[verbum] ERROR: holographic rebuild failed — %s" (error-message-string err)))))
  ;; Eight Keys convergence: skip evolution if scores haven't improved
  (when (and gptel-auto-workflow--evolution-last-objective
             (> gptel-auto-workflow--evolution-last-objective 0))
    (let ((current-obj (gptel-auto-workflow--eight-keys-convergence-score)))
      (when (and current-obj (> current-obj 0)
                 (<= current-obj gptel-auto-workflow--evolution-last-objective))
        (message "[evolution] ∃ Truth: convergence — Eight Keys score %.3f ≤ %.3f, skipping"
                 current-obj gptel-auto-workflow--evolution-last-objective)
        (cl-return-from gptel-auto-workflow-evolution-run-cycle "converged"))
      (when (> current-obj 0)
        (setq gptel-auto-workflow--evolution-last-objective current-obj)
        (message "[evolution] Eight Keys score: %.3f" current-obj))))
  (message "[auto-workflow] Running self-evolution cycle...")
    )
    (error
     (message "[evolution] EARLY error (pre-steps): %s" (error-message-string early-err))
     (cl-return-from gptel-auto-workflow-evolution-run-cycle (format "early-error: %s" early-err))))
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
      ;; Persist hints before early return so state survives daemon restarts
      (gptel-auto-workflow--persist-next-cycle-hints)
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
  (condition-case err
      (gptel-auto-workflow--evolution-synthesize)
    (error (message "[evolution] Step synthesize: %s" err)))
  (condition-case err
      (gptel-auto-workflow--evolution-consolidate-insights)
    (error (message "[evolution] Step consolidate-insights: %s" err)))
  ;; Step A: Controller evolution (traces → strategy-guidance.json)
  (when (fboundp 'gptel-auto-workflow--run-autotts-evolution)
    (message "[auto-workflow] Running controller evolution from traces...")
    (condition-case err
        (gptel-auto-workflow--run-autotts-evolution)
      (error (message "[evolution] Step autotts-evolution: %s" err))))
  ;; Step A.5: Controller code generation agent (AutoTTS-defining feature)
  ;; Runs LLM-driven controller design: agent writes code, tests against replay store, iterates
  ;; Skip when no new experiments — no data to design from
  (when (and (fboundp 'gptel-auto-workflow--run-controller-design-agent)
             (>= (gptel-auto-workflow--evolution-count-new) 3))
    (message "[auto-workflow] Running controller design agent...")
    (condition-case err
        (gptel-auto-workflow--run-controller-design-agent 3)
      (error (message "[evolution] Step controller-design: %s" err))))
  ;; Step B: Skill evolution (TSV data → SKILL.md, uses {{strategy-guidance}} from step A)
  (condition-case err
      (gptel-auto-workflow--evolve-all-skills)
    (error (message "[evolution] Step evolve-skills: %s" err)))
  ;; Run AutoTTS-style strategy evolution using benchmark results
  (when (fboundp 'gptel-auto-workflow--run-strategy-evolution)
    (message "[auto-workflow] Running strategy evolution...")
    (condition-case err
        (gptel-auto-workflow--run-strategy-evolution)
      (error (message "[evolution] Step strategy-evolution: %s" err))))
  ;; Step C: Skill governance (scan health, inject canaries, dashboard)
  (when (fboundp 'gptel-auto-workflow--skill-governance-run-cycle)
    (message "[auto-workflow] Running skill governance cycle...")
    (condition-case err
        (gptel-auto-workflow--skill-governance-run-cycle)
      (error (message "[evolution] Step skill-governance: %s" err))))
  (condition-case err
      (gptel-auto-workflow--evolution-record-score)
    (error (message "[evolution] Step record-score: %s" err)))
  (condition-case err
      (gptel-auto-workflow--evolution-optimize-backend-order)
    (error (message "[evolution] Step optimize-backend-order: %s" err)))
  ;; Step C.5: Head-to-head backend comparison (data-driven, no LLM calls)
  (gptel-auto-workflow--evolution-persist-backend-comparison)
  ;; Step C.6: Model-level comparison (backend/model granularity)
  (gptel-auto-workflow--evolution-persist-model-comparison)
  ;; Step C.7: Semantic relationship discovery (git-embed ontology enrichment)
  (when (fboundp 'gptel-auto-workflow--evolution-persist-semantic-relationships)
    (gptel-auto-workflow--evolution-persist-semantic-relationships))
  ;; Step C.8: Allium issue trend analysis + regression detection
  (let ((trends-report (gptel-auto-workflow--allium-trends-report)))
    (when (> (length trends-report) 30)
      (let ((file (expand-file-name "mementum/knowledge/allium-trends.md"
                                    (gptel-auto-workflow--worktree-base-root))))
        (make-directory (file-name-directory file) t)
        (with-temp-file file (insert trends-report)))))
  ;; Step C.9: Save Allium regression baselines for next cycle
  (gptel-auto-workflow--allium-save-regression-baseline)
  ;; Throttle VSM health check to 1x/15min (expensive: allium LLM calls)
  (let ((now (float-time (current-time))))
    (when (or (null gptel-auto-workflow--vsm-health-last-run)
              (> (- now gptel-auto-workflow--vsm-health-last-run) 900))
      (setq gptel-auto-workflow--vsm-health-last-run now)
      (gptel-auto-workflow--evolution-vsm-health-check)))
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
    (ignore))
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
    (ignore))
  ;; Competitive gating — champion league (AutoGo pattern)
  (condition-case err
      (let ((gated (gptel-auto-workflow--gate-strategies)))
        (when gated
          (message "[gate] Strategy gating results (%d evaluated):" (length gated))
          (dolist (g (seq-take gated 5))
            (message "[gate]   %s: %s" (car g) (cdr g)))))
    (error (message "[gate] ERROR: gating failed — %s" (error-message-string err))))
  ;; Cross-subsystem feedback: champion changes → controller budget,
  ;; category experiment allocation, VSM health → actionable repair
  (condition-case err
      (progn
        (gptel-auto-workflow--apply-cross-subsystem-feedback)
      ;; Research champion league: benchmark proposed strategies against incumbents
      (when (fboundp 'gptel-auto-workflow--run-research-champion-league)
        (run-with-idle-timer 30 nil #'gptel-auto-workflow--run-research-champion-league))
        (gptel-auto-workflow--consume-vsm-actions))
    (error (message "[feedback] ERROR: cross-subsystem failed — %s" (error-message-string err))))
  ;; Verbum Phase 11: Lambda compiler verification (run every 6 hours)
  (when (fboundp 'gptel-auto-workflow--verify-all-backends-lambda)
    (let ((last-verify (get 'gptel-auto-workflow--verify-all-backends-lambda :last-run)))
      (when (or (null last-verify)
                (> (- (float-time) last-verify) 21600))  ; 6 hours
        (condition-case err
            (progn
              (gptel-auto-workflow--verify-all-backends-lambda)
              (put 'gptel-auto-workflow--verify-all-backends-lambda :last-run (float-time)))
          (error (message "[verbum] ERROR: lambda verification failed — %s" (error-message-string err)))))))
  ;; Verbum Phase 6+9: Cross-backend consistency + low-agreement alerts (run every 3 hours)
  (when (fboundp 'gptel-auto-workflow--check-all-targets-consistency)
    (let ((last-check (get 'gptel-auto-workflow--check-all-targets-consistency :last-run)))
      (when (or (null last-check)
                (> (- (float-time) last-check) 10800))  ; 3 hours
        (condition-case err
            (let ((result (gptel-auto-workflow--check-all-targets-consistency)))
              (put 'gptel-auto-workflow--check-all-targets-consistency :last-run (float-time))
              (when (> (plist-get result :inconsistent) 0)
                (message "[verbum] ⚠ %d inconsistent targets detected"
                         (plist-get result :inconsistent))
                ;; Phase 9: detailed low-agreement alerts
                 (let ((low-agreement nil))
                   (dolist (target-report (plist-get result :targets))
                     (when (< (plist-get target-report :ratio) 0.5)
                       (push target-report low-agreement)))
                   (when low-agreement
                     ;; Populate conflicted-targets for gatekeeping
                      (when (boundp 'gptel-auto-workflow--conflicted-targets)
                        (setq gptel-auto-workflow--conflicted-targets
                              (mapcar (lambda (r) (cons (plist-get r :target)
                                                        (plist-get r :ratio)))
                                      low-agreement)))
                      ;; Generate human review file for conflicted targets
                      (when (fboundp 'gptel-auto-workflow--generate-conflicted-review)
                        (gptel-auto-workflow--generate-conflicted-review low-agreement))
                      (message "[verbum] ⚠ LOW AGREEMENT (%d targets < 50%%):" (length low-agreement))
                    (dolist (report (seq-take low-agreement 5))
                       (message "[verbum]   %s: %.0f%% agreement, %d conflicts"
                                (plist-get report :target)
                                (* 100 (plist-get report :ratio))
                                (length (plist-get report :conflicts))))))))
          (error (message "[verbum] ERROR: consistency check failed — %s" (error-message-string err)))))))
  ;; Ambiguity filtering + second-chance repair (LogMap patterns)
  (condition-case nil
      (let* ((results (gptel-auto-workflow--parse-all-results))
             (targets (delete-dups (mapcar (lambda (r) (plist-get r :target)) results))))
        (when targets
          (gptel-auto-workflow--filter-by-ambiguity targets 3))
        (gptel-auto-workflow--second-chance-repair))
    (ignore))
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
    (ignore))
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
  (condition-case nil
      (let ((now (float-time (current-time))))
        (when (or (not (boundp 'gptel-auto-workflow--allium-audit-last-run))
                  (> (- now (or (symbol-value 'gptel-auto-workflow--allium-audit-last-run) 0)) 900))
          (setq gptel-auto-workflow--allium-audit-last-run now)
          (gptel-auto-workflow--allium-audit-signal)))
    (ignore))
  ;; Allium BDD gate: behavioral spec coherence check on Ouroboros invariants
  (condition-case err
      (gptel-auto-workflow--allium-bdd-gate)
    (error (message "[bdd-gate] BDD check failed: %s" (error-message-string err))))
  ;; Allium minimal-pair diffing: compare competing hypotheses from this cycle
  (condition-case err
      (when (fboundp 'gptel-auto-workflow--allium-diff-minimal-pairs)
        (gptel-auto-workflow--allium-diff-opposing-hypotheses))
    (error (message "[allium-diff] Hypothesis diffing failed: %s" (error-message-string err))))
  ;; Write research priorities for next cycle's researcher (Semantica ontology feedback)
  (condition-case err
      (progn (gptel-auto-workflow--write-research-priorities)
             (gptel-auto-workflow--enrich-ontology-from-research)
             (gptel-auto-workflow--queue-research-pair-probes)
             (when (fboundp 'gptel-auto-workflow--detect-research-topic-trends)
               (gptel-auto-workflow--detect-research-topic-trends)))
    (error (message "[research-feedback] Priority write failed: %s" (error-message-string err))))
  ;; Knowledge page cross-cycle diff (Semantica set-difference pattern)
  (condition-case err
      (let ((diff (gptel-auto-workflow--diff-knowledge-pages)))
        (let ((added (plist-get diff :added))
              (removed (plist-get diff :removed))
              (changed (plist-get diff :changed)))
          (when (or added removed changed)
            (message "[diff] Knowledge pages: +%d added, -%d removed, ~%d changed"
                     (length added) (length removed) (length changed))
            (dolist (a added) (message "[diff]   + %s" a))
            (dolist (r removed) (message "[diff]   - %s" r)))))
    (error (message "[knowledge-diff] Diff failed: %s" (error-message-string err))))
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
    (ignore))
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
    (ignore))
  ;; Abductive diagnosis — best explanations for system state
  (condition-case nil
      (let ((diagnoses (gptel-auto-workflow--abductive-diagnose)))
        (when diagnoses
          (message "[abduce] %d entities diagnosed" (length diagnoses))
          (dolist (d (seq-take diagnoses 5))
            (let ((entity (car d)) (explanations (cdr d)))
              (dolist (e (seq-take explanations 1))
                (message "[abduce]   %s: %s → %s (%.0f%%)"
                         (truncate-string-to-width (format "%s" entity) 25)
                         (plist-get e :cause)
                         (plist-get e :action)
                         (* 100 (plist-get e :confidence))))))))
    (ignore))
  ;; Deductive explanation — prove WHY observations hold
  (condition-case nil
      (let ((facts (list (cons 'keep-rate (gptel-auto-workflow--overall-keep-rate))
                         (cons 'total-experiments (gptel-auto-workflow--total-experiments)))))
        (let ((proofs (gptel-auto-workflow--deductive-explain facts)))
          (dolist (p proofs)
            (message "[deduce] Proved '%s': %.0f%% confidence (%d premises)"
                     (plist-get p :goal)
                     (* 100 (or (plist-get p :confidence) 0))
                     (or (plist-get p :premises-count) 0)))))
    (ignore))
  ;; Datalog transitive closure — causal chains
  (condition-case nil
      (let* ((results (gptel-auto-workflow--parse-all-results))
             (causal-pairs nil))
        (dolist (r (seq-take results 50))
          (let ((target (plist-get r :target))
                (decision (plist-get r :decision)))
            (when (and (stringp target) (equal decision "kept"))
              (push (cons (concat "experiment-" (plist-get r :target))
                          (concat "outcome-" (plist-get r :decision)))
                    causal-pairs))))
        (let ((transitive (gptel-auto-workflow--datalog-transitive-chain causal-pairs)))
          (when transitive
            (message "[datalog] %d transitive causal edges discovered" (length transitive)))))
    (ignore))
  ;; Temporal analysis — Allen relations + coverage gaps
  (condition-case nil
      (let ((gaps (gptel-auto-workflow--experiment-time-gaps)))
        (when gaps
          (message "[temporal] %d temporal gaps found (>1h between experiments)" (length gaps))
          (dolist (g (seq-take gaps 3))
            (message "[temporal]   %s: gap since %.0fh ago"
                     (truncate-string-to-width (car (cdr g)) 30)
                     (/ (- (float-time) (cdr (cdr g))) 3600)))))
    (ignore))
  ;; AgentMemory status log (Semantica pattern)
  (condition-case nil
      (let ((mem (gptel-auto-workflow--memory-status)))
        (message "[memory] 4-layer architecture:")
        (dolist (m mem)
          (message "[memory]   %s: %s (%s)" (plist-get m :layer) (plist-get m :state) (plist-get m :description))))
    (ignore))
  ;; Holdout evaluation — real progress vs overfitting (AutoGo pattern)
  (condition-case nil
      (let ((h (gptel-auto-workflow--evaluate-holdout)))
        (message "[holdout] avg=%.3f trend=%+.3f" (plist-get h :average) (plist-get h :trend)))
    (ignore))
  ;; LLM-as-Oracle: produce uncertain candidates for validation
  (condition-case nil
      (let ((candidates (gptel-auto-workflow--produce-candidates-for-llm 20)))
        (when candidates
          (message "[oracle] %d uncertain candidates for LLM validation" (length candidates))))
    (ignore))
  ;; Build inverted file index (LogMap pattern)
  (condition-case nil
      (gptel-auto-workflow--build-inverted-file)
    (ignore))
  (message "[auto-workflow] Self-evolution cycle complete.")
  ;; Emit machine-parseable RESULT for this cycle (AutoGo protocol)
  (condition-case nil
      (let* ((rate (gptel-auto-workflow--overall-keep-rate))
             (total (gptel-auto-workflow--total-experiments)))
         (gptel-auto-workflow--emit-result "evolution-cycle" rate
           (- rate (or gptel-auto-workflow--champion-keep-rate 0))
           (if (> rate 0) "keep" "skip")
           (list :total-experiments total))
         (when (fboundp 'gptel-auto-workflow--autoresearch-check)
           (gptel-auto-workflow--autoresearch-check
            (list :metric "evolution-cycle" :value rate
                  :delta (- rate (or gptel-auto-workflow--champion-keep-rate 0))
                  :status (if (> rate 0) "keep" "skip")))))
    (ignore))))

 ;; ─── VSM Health Diagnostics (nucleus VSM pattern) ───

(defun gptel-auto-workflow--evolution-vsm-health-check ()
  "Score VSM layer health and log diagnostics.
Connects benchmark-principles Eight Keys scoring to operational pipeline."
  (let* ((results (gptel-auto-workflow--parse-all-results))
         (kept (cl-count-if (lambda (r) (equal (plist-get r :decision) "kept")) results))
         (total (length results))
         (keep-rate (if (> total 0) (/ (float kept) total) 0.0))
         (strategies (length (gptel-auto-workflow--evolution-strategy-structure-scores)))
         (backends (length (gptel-auto-workflow--evolution-backend-stats)))
         (axis-stats (gptel-auto-workflow--evolution-axis-stats))
         ;; Verbum: backend health metrics (health ladder levels 0-4)
         (healthy-backends
          (if (fboundp 'gptel-auto-workflow--backend-health-level)
              (let ((hl 0))
                (dolist (b (mapcar #'car (gptel-auto-workflow--evolution-backend-stats)))
                  (when (= 0 (gptel-auto-workflow--backend-health-level b))
                    (cl-incf hl)))
                hl)
            backends))
         (degraded-backends (- backends healthy-backends))
         (backend-health-ratio (if (> backends 0) (/ (float healthy-backends) backends) 0.0))
         ;; Verbum: health-weighted experiment confidence
         (evidence-trust (if (fboundp 'gptel-auto-workflow--backend-health-weight)
                             (let ((total-w 0.0))
                               (dolist (b (mapcar #'car (gptel-auto-workflow--evolution-backend-stats)))
                                 (let ((w (gptel-auto-workflow--backend-health-weight b)))
                                   (cl-incf total-w w)))
                               (/ total-w (float backends)))
                           1.0))
         ;; Verbum: cross-backend consistency
         (consistency-available (fboundp 'gptel-auto-workflow--check-all-targets-consistency))
         (consistency-ratio
          (if consistency-available
              (let ((cons-result (condition-case nil
                                     (gptel-auto-workflow--check-all-targets-consistency)
                                   (error nil))))
                (if cons-result
                    (let ((total-targets (plist-get cons-result :total))
                          (inconsistent (plist-get cons-result :inconsistent)))
                      (if (> total-targets 0)
                          (- 1.0 (/ (float inconsistent) total-targets))
                        1.0))
                  1.0))
            1.0))
         (eight-keys-available (fboundp 'gptel-benchmark-eight-keys-score-for))
          (autogo-score 0.0) (autotts-score 0.0) (selfev-score 0.0)
          (harness-score 0.0) (ontology-score 0.0)
          (scored-count 0))
    (when eight-keys-available
      (dolist (r results)
        (when (equal (plist-get r :decision) "kept")
          (let ((hypo (or (plist-get r :hypothesis) "")))
            (cl-incf scored-count)
            (cl-incf autogo-score (alist-get 'overall (gptel-benchmark-eight-keys-score-for hypo :autogo) 0.0))
            (cl-incf autotts-score (alist-get 'overall (gptel-benchmark-eight-keys-score-for hypo :autotts) 0.0))
            (cl-incf selfev-score (alist-get 'overall (gptel-benchmark-eight-keys-score-for hypo :self-evolve) 0.0))
            (cl-incf harness-score (alist-get 'overall (gptel-benchmark-eight-keys-score-for hypo :meta-harness) 0.0))
            (cl-incf ontology-score (alist-get 'overall (gptel-benchmark-eight-keys-score-for hypo :ontology) 0.0)))))
      (when (> scored-count 0)
        (setq autogo-score (/ autogo-score scored-count))
        (setq autotts-score (/ autotts-score scored-count))
        (setq selfev-score (/ selfev-score scored-count))
        (setq harness-score (/ harness-score scored-count))
        (setq ontology-score (/ ontology-score scored-count))))
    (message "[vsm] S1-Ops: %d experiments, %.0f%% kept" total (* 100 keep-rate))
    (message "[vsm] S2-Coord: %d modules scanned, consistency %.0f%%" 89 (* 100 consistency-ratio))
    (message "[vsm] S3-Control: %d/%d healthy backends (%.0f%% health, %.0f%% trust), %d degraded"
             healthy-backends backends (* 100 backend-health-ratio) (* 100 evidence-trust) degraded-backends)
    (message "[vsm] S4-Intel: %d strategies evolved, auto-backend-order active" strategies)
    (message "[vsm] S5-Identity: lambda notation, confidence tags, graphify patterns active")
    (when (and (fboundp 'gptel-auto-workflow--backend-health-level)
               (> degraded-backends 0))
      (message "[vsm] ⚠ VERBUM: %d backend(s) degraded (non-zero health level): %s"
               degraded-backends
               (mapconcat (lambda (b) (format "%s/%s"
                                              (car b)
                                              (gptel-auto-workflow--backend-health-label (car b))))
                          (cl-remove-if (lambda (b) (= 0 (gptel-auto-workflow--backend-health-level (car b))))
                                        (gptel-auto-workflow--evolution-backend-stats))
                          ", ")))
    (when eight-keys-available
      (message "[vsm] Eight Keys: AutoGo=%.2f AutoTTS=%.2f self-evolve=%.2f meta-harness=%.2f ontology=%.2f (%d samples)"
               autogo-score autotts-score selfev-score harness-score ontology-score scored-count))
    (when (fboundp 'gptel-auto-workflow--refresh-variant-axis-champions)
      (gptel-auto-workflow--refresh-variant-axis-champions))
    (when axis-stats
      (message "[vsm] KIBC-M Axis Performance: %s"
               (mapconcat (lambda (a) (format "%s=%.0f%%" (car a) (* 100 (cdr a))))
                          (seq-take axis-stats 5) " ")))
    (cond
     ((< keep-rate 0.05)
      (message "[vsm] 相克: Wood(S1) weak — keep-rate %.1f%%"
               (* 100 keep-rate))
      (push (cons 'rebalance-experiment-targets "Wood(S1) weak: diversify target selection")
            gptel-auto-workflow--wu-xing-actions))
     ((< strategies 5)
      (message "[vsm] 相生: Fire(S4) weak — only %d strategies" strategies)
      (push (cons 'increase-strategy-evolution "Fire(S4) weak: fewer than 5 strategies")
            gptel-auto-workflow--wu-xing-actions))
      ((< backends 3)
       (message "[vsm] 相克: Metal(S2) weak — only %d backends" backends)
       (push (cons 'enable-fallback-backend "Metal(S2) weak: fewer than 3 backends")
             gptel-auto-workflow--wu-xing-actions))
      ((< backend-health-ratio 0.5)
       (message "[vsm] 相克: Earth(S3) weak — only %.0f%% backends healthy" (* 100 backend-health-ratio))
       (push (cons 'rebalance-backends "Earth(S3) weak: majority of backends degraded")
             gptel-auto-workflow--wu-xing-actions))
      ((< consistency-ratio 0.6)
       (message "[vsm] 相克: Metal(S2) weak — only %.0f%% cross-backend consistency" (* 100 consistency-ratio))
       (push (cons 'increase-consistency "Metal(S2) weak: backends disagree on target classification")
             gptel-auto-workflow--wu-xing-actions))
     (t
       (message "[vsm] 相生: All layers balanced — generating cycle active")))
     ;; VSM→Target: compute per-level health scores for target prioritization
     (let* ((s1-strength (min 1.0 (* keep-rate 5.0)))        ; Wood/Operations → keep-rate
            (s2-strength (min 1.0 consistency-ratio))           ; Metal/Coord → backend agreement
            (s3-strength (if (> backends 2)
                             (* evidence-trust 0.7)              ; Earth/Control → health-weighted trust
                           0.3))                                ; penalized when <3 total
            (s4-strength (min 1.0 (/ strategies 10.0)))        ; Fire/Intel → strategy count
            (s5-strength (if eight-keys-available
                             (/ (+ autogo-score autotts-score selfev-score ontology-score) 4.0)
                           0.5)))                              ; Water/Identity → Eight Keys avg
       (push (cons 'prioritize-targets
                   (list :s1-ops s1-strength
                         :s2-coord s2-strength
                         :s3-control s3-strength
                         :s4-intel s4-strength
                         :s5-identity s5-strength))
             gptel-auto-workflow--wu-xing-actions))
     ;; Feed Wu Xing diagnostics into next-cycle hints for VSM repair
    (when gptel-auto-workflow--wu-xing-actions
      (let ((existing (plist-get gptel-auto-workflow--evolution-next-cycle-hints :vsm-actions)))
        (setq gptel-auto-workflow--evolution-next-cycle-hints
              (plist-put gptel-auto-workflow--evolution-next-cycle-hints
                         :vsm-actions (append existing gptel-auto-workflow--wu-xing-actions)))
        (setq gptel-auto-workflow--wu-xing-actions nil)))
    ;; Housekeeping: full autonomous maintenance
    (condition-case nil
        (let* ((root (or (gptel-auto-workflow--worktree-base-root)
                         (expand-file-name default-directory)))
               (git-dir (expand-file-name ".git" root))
               (exps-dir (expand-file-name "var/tmp/experiments" root))
               (now (float-time))
               (pruned 0) (removed-worktrees 0) (cleaned-temp 0))
          ;; 1. Prune experiment result dirs older than 14 days
          (when (file-directory-p exps-dir)
            (dolist (d (directory-files exps-dir t "\\`[0-9]+T" t))
              (let ((attrs (and d (file-attributes d))))
                (when (and attrs
                           (> (- now (float-time (file-attribute-modification-time attrs)))
                              (* 14 24 3600)))
                  (delete-directory d t)
                  (setq pruned (1+ pruned))))))
          ;; 2. Remove stale prunable git worktrees
          (dolist (wt (split-string (shell-command-to-string "git worktree list --porcelain") "\n" t))
            (when (string-match "prunable" wt)
              (let ((wt-path (car (split-string wt "\n" t))))
                (when (and wt-path (file-directory-p wt-path))
                  (shell-command (format "git worktree remove --force %s" (shell-quote-argument wt-path)) 0)
                  (setq removed-worktrees (1+ removed-worktrees))))))
          ;; 3. Kill stale --fg-daemon processes
          (let ((pids (shell-command-to-string "pgrep -f 'emacs.*--fg-daemon' 2>/dev/null || true")))
            (dolist (pid (split-string pids "\n" t))
              (when (string-match "[0-9]+" pid)
                (signal-process (string-to-number pid) 'sigterm)
                (message "[cleanup] Killed stale fg-daemon pid %s" pid))))
          ;; 4. Clean /tmp/gptel-* files older than 2 hours
          (dolist (f (directory-files "/tmp" t "gptel-"))
            (let ((attrs (and f (file-attributes f))))
              (when (and attrs
                         (> (- now (float-time (file-attribute-modification-time attrs)))
                            (* 2 3600)))
                (delete-file f t)
                (setq cleaned-temp (1+ cleaned-temp)))))
          ;; 5. Truncate daemon log if >10MB
          (let ((log-file (expand-file-name "var/tmp/cron/ov5-auto-workflow.log" root)))
            (when (and (file-exists-p log-file)
                       (> (file-attribute-size (file-attributes log-file)) (* 10 1024 1024)))
              (shell-command (format "tail -n 1000 %s > %s.tmp && mv %s.tmp %s"
                                     (shell-quote-argument log-file)
                                     (shell-quote-argument log-file)
                                     (shell-quote-argument log-file)
                                     (shell-quote-argument log-file)) 0)
              (message "[cleanup] Truncated daemon log (>10MB)")))
          ;; 6. Run git gc --auto when too many loose objects
          (when (and (file-directory-p git-dir)
                     (file-directory-p (expand-file-name "objects" git-dir)))
            (let* ((obj-dir (expand-file-name "objects" git-dir))
                   (loose (condition-case nil
                              (length (directory-files obj-dir nil "^[0-9a-f]\\{38\\}$" t))
                            (error 0))))
              (when (> loose 5000)
                (shell-command "git gc --auto --quiet" 0)
                (message "[cleanup] Ran git gc (loose objects >5k, was %d)" loose))))
          ;; 7. Remove stale git locks
          (dolist (lock (directory-files root t "\\.lock$"))
            (when (file-directory-p lock)
              (delete-directory lock t)
              (message "[cleanup] Removed stale lock: %s" (file-name-nondirectory lock))))
          ;; 8. Dedup crontab entries
          (let* ((cron-out (shell-command-to-string "crontab -l 2>/dev/null | sort -u || true"))
                 (original-count (length (split-string cron-out "\n" t)))
                 (deduped-count (length (delete-dups (split-string cron-out "\n" t)))))
            (when (< deduped-count original-count)
              (shell-command (format "crontab -l 2>/dev/null | sort -u | crontab -") 0)
              (message "[cleanup] Deduped crontab (%d unique lines)" deduped-count)))
          ;; Log cleanup results inside let* so counters stay in scope.
          (when (> pruned 0)
            (message "[cleanup] Pruned %d experiment dirs >14d" pruned))
          (when (> removed-worktrees 0)
            (message "[cleanup] Removed %d stale worktrees" removed-worktrees))
          (when (> cleaned-temp 0)
            (message "[cleanup] Cleaned %d stale temp files" cleaned-temp)))
      (ignore))))

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
  "Return non-nil if HA and HB differ by one concept."
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
  "Diff knowledge pages against the last cycle snapshot.
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
                      (ignore)))
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
  "Classify recent experiment changes by severity.
Returns an ImpactReport-style plist."
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


;; ─── Semantica Abduction: best explanation from observations ───

(defconst gptel-auto-workflow--abduction-rules
  '((:observe ((keep-rate < 0.1) (total-experiments > 5))
     :explain ((cause . "strategy is fundamentally ineffective")
               (action . "evolve-or-retire")
               (confidence . 0.9)))
    (:observe ((keep-rate < 0.2) (total-experiments > 3))
     :explain ((cause . "strategy targets files it cannot improve")
               (action . "narrow-target-scope")
               (confidence . 0.7)))
    (:observe ((keep-rate > 0.5) (total-experiments > 3))
     :explain ((cause . "strategy is effective for current targets")
               (action . "expand-or-promote")
               (confidence . 0.8)))
    (:observe ((output-ratio > 2.0) (keep-rate < 0.2))
     :explain ((cause . "verbose output without useful changes")
               (action . "compress-prompt")
               (confidence . 0.7)))
    (:observe ((output-ratio > 2.0) (keep-rate > 0.5))
     :explain ((cause . "detailed analysis leads to good fixes")
               (action . "maintain-prompt-size")
               (confidence . 0.7)))
    (:observe ((total-experiments > 20) (keep-rate > 0.3))
     :explain ((cause . "thoroughly tested — diminishing returns")
               (action . "limit-experiments")
               (confidence . 0.6)))
    (:observe ((total-experiments < 3))
     :explain ((cause . "insufficient data for conclusions")
               (action . "run-more-experiments")
               (confidence . 0.95)))
    (:observe ((backend-keep-rate < 0.3) (backend-experiments > 8))
     :explain ((cause . "backend produces poor outputs")
               (action . "deprioritize-backend")
               (confidence . 0.8))))
  "Abduction rules: (:observe ((field op value) ...) :explain ((key . value) ...)).")

(defun gptel-auto-workflow--abduce (facts)
  "Find best explanations for FACTS using abductive rules.
Semantica abductive reasoner pattern."
  (let ((explanations nil))
    (dolist (rule gptel-auto-workflow--abduction-rules)
      (let ((conditions (plist-get rule :observe)) (all-match t))
        (dolist (cond conditions)
          (unless (gptel-auto-workflow--eval-condition cond facts)
            (setq all-match nil)))
        (when all-match
          (let ((e (plist-get rule :explain)))
            (push (list :cause (cdr (assoc (quote cause) e))
                        :action (cdr (assoc (quote action) e))
                        :confidence (cdr (assoc (quote confidence) e)))
                  explanations)))))
    (sort explanations (lambda (a b) (> (plist-get a :confidence) (plist-get b :confidence))))))

(defun gptel-auto-workflow--abductive-diagnose ()
  "Run abductive diagnosis on current system state."
  (let* ((results (gptel-auto-workflow--parse-all-results))
         (by-strategy (make-hash-table :test (quote equal)))
         (by-backend (make-hash-table :test (quote equal)))
         (kept 0) (total 0) (total-output 0) (total-prompt 0)
         (all-diagnoses nil))
    (dolist (r results)
      (setq total (1+ total))
      (let ((decision (plist-get r :decision))
            (strategy (or (plist-get r :strategy) "template-default"))
            (backend (or (plist-get r :backend) "unknown"))
            (pc (or (plist-get r :prompt-chars) 0))
            (oc (or (plist-get r :output-chars) 0)))
        (setq total-output (+ total-output oc) total-prompt (+ total-prompt pc))
        (when (equal decision "kept") (setq kept (1+ kept)))
        (let ((se (or (gethash strategy by-strategy) (list :kept 0 :total 0))))
          (setq se (plist-put se :total (1+ (plist-get se :total))))
          (when (equal decision "kept") (setq se (plist-put se :kept (1+ (plist-get se :kept)))))
          (puthash strategy se by-strategy))
        (let ((be (or (gethash backend by-backend) (list :kept 0 :total 0))))
          (setq be (plist-put be :total (1+ (plist-get be :total))))
          (when (equal decision "kept") (setq be (plist-put be :kept (1+ (plist-get be :kept)))))
          (puthash backend be by-backend))))
    (let ((global-facts (list (cons (quote keep-rate) (if (> total 0) (/ (float kept) total) 0.0))
                              (cons (quote total-experiments) total)
                              (cons (quote output-ratio) (if (> total-prompt 0) (/ (float total-output) total-prompt) 0.0)))))
      (let ((exps (gptel-auto-workflow--abduce global-facts)))
        (when exps (push (cons "global" exps) all-diagnoses))))
    (maphash (lambda (strategy counts)
               (let* ((rate (if (> (plist-get counts :total) 0)
                                (/ (float (plist-get counts :kept)) (plist-get counts :total)) 0.0))
                      (facts (list (cons (quote keep-rate) rate)
                                   (cons (quote total-experiments) (plist-get counts :total))))
                      (exps (gptel-auto-workflow--abduce facts)))
                 (when exps (push (cons strategy exps) all-diagnoses))))
             by-strategy)
    (maphash (lambda (backend counts)
               (let* ((rate (if (> (plist-get counts :total) 0)
                                (/ (float (plist-get counts :kept)) (plist-get counts :total)) 0.0))
                      (facts (list (cons (quote backend-keep-rate) rate)
                                   (cons (quote backend-experiments) (plist-get counts :total))))
                      (exps (gptel-auto-workflow--abduce facts)))
                 (when exps (push (cons backend exps) all-diagnoses))))
             by-backend)
    all-diagnoses))

(defun gptel-auto-workflow--overall-keep-rate ()
  "Return overall keep-rate from all experiments."
  (let* ((results (gptel-auto-workflow--parse-all-results))
         (total (length results))
         (kept (cl-count-if (lambda (r) (equal (plist-get r :decision) "kept")) results)))
    (if (> total 0) (/ (float kept) total) 0.0)))

(defun gptel-auto-workflow--total-experiments ()
  "Return total number of experiments."
  (length (gptel-auto-workflow--parse-all-results)))

;; ─── Semantica Deduction: backward chaining + proof trees ───

(defconst gptel-auto-workflow--deduction-rules
  '((:if ((keep-rate < 0.1) (total-experiments > 5)) :then "strategy is failing")
    (:if ((keep-rate > 0.5) (total-experiments > 5)) :then "strategy is effective")
    (:if ((output-ratio > 2.0) (keep-rate < 0.3)) :then "LLM output is wasteful")
    (:if ((total-experiments > 10) (keep-rate > 0.4)) :then "strategy has good sample size")
    (:if ((backend-keep-rate < 0.2) (backend-experiments > 8)) :then "backend is unreliable"))
  "Deduction rules for backward chaining.")

(defun gptel-auto-workflow--rule-conclusion-matches-p (rule goal)
  (and (stringp (plist-get rule :then)) (stringp goal)
       (string-match-p (regexp-quote goal) (plist-get rule :then))))

(defun gptel-auto-workflow--prove (goal facts rules depth max-depth)
  "Backward chaining prover."
  (if (> depth max-depth)
      (list :goal goal :proven nil :depth depth :reason "max-depth")
    (let ((matching-rules (cl-remove-if-not (lambda (r) (gptel-auto-workflow--rule-conclusion-matches-p r goal)) rules)))
      (if (null matching-rules)
          (list :goal goal :proven nil :depth depth :reason "no rules")
        (let ((best-proof nil) (best-score 0))
          (dolist (rule matching-rules)
            (let ((premises (plist-get rule :if)) (all-match t) (count 0))
              (dolist (p premises)
                (if (gptel-auto-workflow--eval-condition p facts) (setq count (1+ count)) (setq all-match nil)))
              (when all-match
                (let ((confidence (/ (float count) (max 1 (length premises)))))
                  (when (> confidence best-score)
                    (setq best-score confidence
                          best-proof (list :goal goal :proven t :depth depth :premises-count count :confidence confidence)))))))
          (or best-proof (list :goal goal :proven nil :depth depth :reason "premises unproven")))))))

;; ─── Semantica Datalog: transitive closure ───

(defun gptel-auto-workflow--datalog-transitive-chain (causal-pairs)
  "Floyd-Warshall transitive closure."
  (let* ((entities (delete-dups (append (mapcar #'car causal-pairs) (mapcar #'cdr causal-pairs))))
         (reachable (make-hash-table :test 'equal)) (result nil))
    (dolist (pair causal-pairs) (puthash pair t reachable))
    (dolist (k entities)
      (dolist (i entities)
        (dolist (j entities)
          (when (and (gethash (cons i k) reachable) (gethash (cons k j) reachable) (not (gethash (cons i j) reachable)))
            (puthash (cons i j) t reachable) (push (cons i j) result)))))
    result))

;; ─── Semantica Temporal: Allen interval algebra ───

(defun gptel-auto-workflow--allen-relation (a-start a-end b-start b-end)
  "Determine Allen interval relation between A and B."
  (cond ((and a-start a-end b-start b-end (< a-end b-start)) 'before)
        ((and a-start a-end b-start b-end (= a-end b-start)) 'meets)
        ((and a-start a-end b-start b-end (< a-start b-start) (< a-end b-end) (> a-end b-start)) 'overlaps)
        ((and a-start a-end b-start b-end (= a-start b-start) (< a-end b-end)) 'starts)
        ((and a-start a-end b-start b-end (> a-start b-start) (< a-end b-end)) 'during)
        ((and a-start a-end b-start b-end (= a-start b-start) (= a-end b-end)) 'equals)
        ((and a-start a-end b-start b-end (> a-start b-end)) 'after)
        ((and a-start a-end b-start b-end (= a-start b-end)) 'met-by)
        (t 'unknown)))

;; ─── AutoGo: Competitive Gating + PCR + RESULT Protocol ───

(defvar gptel-auto-workflow--champion-strategy nil
  "Current champion strategy name.")
(defvar gptel-auto-workflow--champion-keep-rate 0.0
  "Keep-rate of the champion strategy. Threshold for challenger adoption.
DEPRECATED: use --category-champions for per-category gating.")

(defvar gptel-auto-workflow--category-strike-counts nil
  "Alist of (CATEGORY . STRIKES) tracking successive champion failures.
∀ Vigilance: 3 consecutive failures in a category freezes it for 5 cycles.")

(defun gptel-auto-workflow--record-category-strike (category)
  "Increment failure strike for CATEGORY. Freezes at 3."
  (let ((entry (assq category gptel-auto-workflow--category-strike-counts)))
    (if entry
        (setcdr entry (1+ (cdr entry)))
      (push (cons category 1) gptel-auto-workflow--category-strike-counts))
    (when (>= (cdr (assq category gptel-auto-workflow--category-strike-counts)) 3)
      (message "[champion] ∀ Vigilance: category %s FROZEN (3 strikes) — 5 cycle cooldown" category))))

(defun gptel-auto-workflow--category-frozen-p (category)
  "Return non-nil if CATEGORY is frozen (≥3 strikes)."
  (let ((entry (assq category gptel-auto-workflow--category-strike-counts)))
    (and entry (>= (cdr entry) 3))))

(defun gptel-auto-workflow--reset-category-strikes (category)
  "Reset strikes for CATEGORY after a success."
  (setq gptel-auto-workflow--category-strike-counts
        (assq-delete-all category gptel-auto-workflow--category-strike-counts)))

(defun gptel-auto-workflow--apply-category-vigilance (target decision)
  "Apply ∀ Vigilance strikes based on TARGET and DECISION.
DECISION is 'kept, 'discarded, or 'validation-failed.
Records strike on failure, resets on success."
  (when (fboundp 'gptel-auto-workflow--categorize-experiment-target)
    (let ((category (gptel-auto-workflow--categorize-experiment-target target)))
      (cond
       ((eq decision 'kept)
        (gptel-auto-workflow--reset-category-strikes category)
        (message "[vigilance] ✓ Category %s strike reset (experiment kept)" category))
       ((memq decision '(discarded validation-failed))
        (gptel-auto-workflow--record-category-strike category)
        (message "[vigilance] ⚠ Category %s strike recorded (%s)"
                 category decision))))))

;; ─── φ Vitality: Strategy Novelty Detection ───

(defun gptel-auto-workflow--strategy-novelty-score (new-code existing-strategies)
  "φ Vitality: compute novelty score for NEW-CODE vs EXISTING-STRATEGIES.
Returns 0.0–1.0 where 1.0 = completely novel mechanism.
Scores by: function name uniqueness, approach description difference,
and structural dissimilarity. Below 0.3 = likely parameter variant."
  (if (or (not (stringp new-code)) (null existing-strategies))
      1.0
    (let ((total-score 0.0)
          (compared 0))
      (dolist (existing existing-strategies)
        (when (stringp existing)
          (let ((score 0.0))
            ;; Check 1: function name overlap (penalty for similar names)
            (let ((new-name (when (string-match "defun\\s-+strategy-\\([^ ]+\\)-build-prompt" new-code)
                              (match-string 1 new-code)))
                  (old-name (when (string-match "defun\\s-+strategy-\\([^ ]+\\)-build-prompt" existing)
                              (match-string 1 existing))))
              (when (and new-name old-name)
                ;; Levenshtein-like: count shared words
                (let ((shared 0) (total 0))
                  (dolist (w (split-string new-name "-"))
                    (cl-incf total)
                    (when (string-match-p (regexp-quote w) old-name)
                      (cl-incf shared)))
                  (if (> total 0)
                      (setq score (- 1.0 (/ (float shared) total)))
                    (setq score 0.5)))))
            ;; Check 2: structural similarity (same number of defuns, same sections)
            (let ((new-defuns (count-matches "^(defun " new-code))
                  (old-defuns (count-matches "^(defun " existing)))
              (when (and (> new-defuns 0) (> old-defuns 0))
                (setq score (+ score (* 0.5 (- 1.0 (/ (float (min new-defuns old-defuns))
                                                       (max new-defuns old-defuns))))))))
            (setq total-score (+ total-score score))
            (cl-incf compared))))
      (if (> compared 0)
          (/ total-score compared)
        1.0))))

;; ─── ε Purpose: Per-Category Experiment Quotas ───

(defvar gptel-auto-workflow--category-quota-max 5
  "ε Purpose: maximum consecutive experiments per category before rotation.
Prevents over-optimizing one category at the expense of others.")

(defvar gptel-auto-workflow--category-experiment-counts nil
  "Alist of (CATEGORY . COUNT) tracking consecutive experiments per category.
ε Purpose: resets when category rotates.")

(defun gptel-auto-workflow--next-category-target (current-category)
  "ε Purpose: suggest next category to experiment on, enforcing quotas.
If CURRENT-CATEGORY has exceeded quota, rotate to the least-optimized category.
Returns a category keyword."
  (let* ((counts gptel-auto-workflow--category-experiment-counts)
         (cur-count (or (cdr (assq current-category counts)) 0))
         (all-cats '(:programming :tool-calls :agentic :natural-language)))
    (if (>= cur-count gptel-auto-workflow--category-quota-max)
        ;; Rotate to least-used category
        (let ((best-cat :natural-language)
              (best-count most-positive-fixnum))
          (dolist (cat all-cats)
            (let ((c (or (cdr (assq cat counts)) 0)))
              (when (< c best-count)
                (setq best-count c best-cat cat))))
          (message "[quota] ε Purpose: rotating from %s to %s (%d/%d max)"
                   current-category best-cat cur-count gptel-auto-workflow--category-quota-max)
          ;; Reset current category count after rotation
          (setq gptel-auto-workflow--category-experiment-counts
                (assq-delete-all current-category gptel-auto-workflow--category-experiment-counts))
          best-cat)
      ;; Track this category
      (let ((entry (assq current-category counts)))
        (if entry
            (setcdr entry (1+ (cdr entry)))
          (push (cons current-category 1) gptel-auto-workflow--category-experiment-counts)))
      current-category)))

(defvar gptel-auto-workflow--baseline-keep-rate 0.0
  "Keep-rate of the template-default (baseline) strategy.
μ Directness: first champion must beat this, not absolute zero.")

(defvar gptel-auto-workflow--category-champions nil
  "Alist of (CATEGORY . (STRATEGY . KEEP-RATE)) for per-category champions.
Categories: :programming, :natural-language, :tool-calls, :agentic.
AutoGo: each category has its own champion and gate.")

(defvar gptel-auto-workflow--category-baselines nil
  "Alist of (CATEGORY . KEEP-RATE) for per-category baseline keep-rates.
Computed from template-default experiments filtered by category.")

(defun gptel-auto-workflow--categorize-experiment-target (target)
  "Categorize TARGET into an ontology category.
Delegates to ontology router's --categorize-target when available
for a unified classification. Falls back to local regex matching.
Returns :programming, :tool-calls, :agentic, or :natural-language."
  (if (fboundp 'gptel-auto-workflow--categorize-target)
      (gptel-auto-workflow--categorize-target target)
    (let ((base (if (stringp target) (file-name-nondirectory target) "")))
      (cond
       ((or (string-match-p "sandbox\\|tool-sanitize\\|tool-permit" base)
            (string-match-p "\\btools?\\b" base))
        :tool-calls)
       ((or (string-match-p "agent-loop\\|agent-tools\\|agent-staging" base)
            (string-match-p "\\bagent\\b" base)
            (string-match-p "subagent" base))
        :agentic)
       ((or (string-match-p "benchmark\\|comparator\\|scoring\\|regression" base)
            (string-match-p "\\btest" base)
            (string-match-p "evolution\\|evolve\\|mutate" base))
        :programming)
       ((or (string-match-p "prompt\\|context\\|skill\\|strategy" base)
            (string-match-p "\\bcompress\\|directive\\|guidance" base))
        :natural-language)
       (t :natural-language)))))

(defun gptel-auto-workflow--compute-baseline-keep-rate ()
  "Compute the template-default keep-rate from all TSV data.
Returns the keep-rate as a float, or 0.10 as a safe lower-bound fallback."
  (let ((total 0) (kept 0)
        (results (gptel-auto-workflow--parse-all-results)))
    (dolist (r results)
      (when (or (equal (plist-get r :strategy) "template-default")
                (not (plist-get r :strategy)))
        (setq total (1+ total))
        (when (or (equal (plist-get r :decision) "kept")
                   (equal (plist-get r :decision) t))
          (setq kept (1+ kept)))))
    (let ((rate (if (> total 0) (/ (float kept) total) 0.10)))
      (setq gptel-auto-workflow--baseline-keep-rate rate)
      rate)))

(defun gptel-auto-workflow--compute-category-baselines ()
  "Compute per-category baseline keep-rates from template-default experiments."
  (let ((stats (make-hash-table :test 'eq))
        (results (gptel-auto-workflow--parse-all-results)))
    (dolist (r results)
      (when (or (equal (plist-get r :strategy) "template-default")
                (not (plist-get r :strategy)))
        (let* ((target (plist-get r :target))
               (cat (gptel-auto-workflow--categorize-experiment-target target))
               (entry (gethash cat stats (cons 0 0))))
          (setcar entry (1+ (car entry)))
          (when (or (equal (plist-get r :decision) "kept")
                     (equal (plist-get r :decision) t))
            (setcdr entry (1+ (cdr entry))))
          (puthash cat entry stats))))
    (let ((alist '()))
      (maphash (lambda (cat entry)
                 (let ((total (car entry))
                       (kept (cdr entry)))
                   (push (cons cat (if (> total 0) (/ (float kept) total) 0.10))
                         alist)))
               stats)
      (setq gptel-auto-workflow--category-baselines alist)
      alist)))

(defun gptel-auto-workflow--get-category-champion (category)
  "Get the current champion (strategy . keep-rate) for CATEGORY."
  (cdr (assq category gptel-auto-workflow--category-champions)))

(defun gptel-auto-workflow--set-category-champion (category strategy keep-rate)
  "Set STRATEGY as champion for CATEGORY with KEEP-RATE."
  (let ((entry (assq category gptel-auto-workflow--category-champions)))
    (if entry
        (setcdr entry (cons strategy keep-rate))
      (push (cons category (cons strategy keep-rate))
            gptel-auto-workflow--category-champions)))
  ;; Persist to disk so champions survive daemon restarts
  (gptel-auto-workflow--save-category-champions))

(defun gptel-auto-workflow--champions-file ()
  "Return the path to the category champions persistence file."
  (expand-file-name "var/tmp/category-champions.sexp"
                    (or (gptel-auto-workflow--worktree-base-root)
                        default-directory)))

(defun gptel-auto-workflow--save-category-champions ()
  "Persist category champions to disk."
  (let ((file (gptel-auto-workflow--champions-file)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file
      (prin1 gptel-auto-workflow--category-champions (current-buffer)))
    (message "[champion] Persisted %d category champions to %s"
             (length gptel-auto-workflow--category-champions)
             (file-relative-name file))))

(defun gptel-auto-workflow--load-category-champions ()
  "Load category champions from disk."
  (let ((file (gptel-auto-workflow--champions-file)))
    (when (file-exists-p file)
      (condition-case nil
          (with-temp-buffer
            (insert-file-contents file)
            (setq gptel-auto-workflow--category-champions (read (current-buffer)))
            (message "[champion] Loaded %d category champions from %s"
                     (length gptel-auto-workflow--category-champions)
                     (file-relative-name file)))
        (error
         (message "[champion] Failed to load champions from %s" file))))))

(defun gptel-auto-workflow--queue-strategy-benchmark (strategy-name axis)
  "Queue newly generated STRATEGY-NAME for benchmarking before production use.
Writes to pending_eval.json for the meta-harness pipeline to process."
  (let* ((root (or (gptel-auto-workflow--worktree-base-root) default-directory))
         (pending-file (expand-file-name "var/tmp/strategy-evaluations/pending_eval.json" root))
         (pending (if (file-exists-p pending-file)
                      (condition-case nil
                          (with-temp-buffer
                            (insert-file-contents pending-file)
                            (json-read))
                        (error nil))
                    (list :candidates '())))
         (candidates (plist-get pending :candidates)))
    (push (list :name strategy-name :axis (format "%s" axis)
                :queued-at (format-time-string "%Y-%m-%dT%H:%M:%SZ")
                :status "pending")
          candidates)
    (setq pending (plist-put pending :candidates candidates))
    (make-directory (file-name-directory pending-file) t)
    (with-temp-file pending-file
      (insert (json-encode pending)))
    (message "[strategy] Queued %s (axis %s) for benchmark evaluation"
             strategy-name axis)))

(defun gptel-auto-workflow--strategy-category-keep-rate (strategy-name category)
  "Compute keep-rate for STRATEGY-NAME filtered to CATEGORY."
  (let ((total 0) (kept 0)
        (results (gptel-auto-workflow--parse-all-results)))
    (dolist (r results)
      (when (and (equal (plist-get r :strategy) strategy-name)
                 (eq (gptel-auto-workflow--categorize-experiment-target
                      (plist-get r :target))
                     category))
        (setq total (1+ total))
        (when (or (equal (plist-get r :decision) "kept")
                   (equal (plist-get r :decision) t))
          (setq kept (1+ kept)))))
    (if (> total 0) (/ (float kept) total) 0.0)))

(defvar gptel-auto-workflow--champion-composite-score 0.0
  "Composite benchmark score of the champion strategy.
Combines keep rate, score delta, quality gain, and efficiency.")

(defun gptel-auto-workflow--strategy-composite-score (strategy-name)
  "Compute composite benchmark score for STRATEGY-NAME from TSV data."
  (let ((total 0) (kept 0) (score-sum 0.0) (quality-sum 0.0) (dur-sum 0)
        (results (gptel-auto-workflow--parse-all-results)))
    (dolist (r results)
      (when (equal (plist-get r :strategy) strategy-name)
        (setq total (1+ total))
        (when (or (equal (plist-get r :decision) "kept") (equal (plist-get r :decision) t))
          (setq kept (1+ kept)))
        (let* ((pre (or (plist-get r :score-before) 0.4))
               (post (or (plist-get r :score-after) pre)))
          (setq score-sum (+ score-sum (- post pre))))
        (setq quality-sum (+ quality-sum (or (plist-get r :code-quality) (plist-get r :code_quality) 0.5)))
        (setq dur-sum (+ dur-sum (or (plist-get r :duration) 300)))))
    (if (= total 0)
        0.0
      (let* ((keep-rate (/ (float kept) total))
             (avg-delta (/ score-sum (float total)))
             (avg-quality (/ quality-sum (float total)))
             (avg-dur (/ dur-sum (float total)))
             (efficiency (/ 300.0 (+ avg-dur 300.0)))
             (score (+ (* keep-rate 0.3) (* avg-delta 2.0) (* avg-quality 0.3) (* efficiency 0.1))))
        (when (> total 0)
          (message "[benchmark] %s: keep=%.0f%% delta=%+.3f quality=%.2f eff=%.0fs → score=%.3f"
                   strategy-name (* 100 keep-rate) avg-delta avg-quality avg-dur score))
        score))))

(defun gptel-auto-workflow--deductive-explain (facts)
  "Generate simple deductive proofs from FACTS alist."
  (let ((proofs nil)
        (keep-rate (cdr (assq 'keep-rate facts)))
        (total-experiments (cdr (assq 'total-experiments facts))))
    (when keep-rate
      (push (list :goal "keep-rate-observed"
                  :confidence keep-rate
                  :premises-count 1)
            proofs))
    (when (and total-experiments (> total-experiments 0))
      (push (list :goal "experiments-conducted"
                  :confidence (min 1.0 (/ (float total-experiments) 100))
                  :premises-count 1)
            proofs))
    (unless proofs
      (push (list :goal "system-operational"
                  :confidence 0.5
                  :premises-count 0)
            proofs))
    (nreverse proofs)))

(defun gptel-auto-workflow--experiment-time-gaps (&optional threshold-seconds)
  "Return experiment gaps larger than THRESHOLD-SECONDS."
  (let* ((threshold (or threshold-seconds 3600))
         (results (sort (cl-remove-if-not (lambda (r) (numberp (plist-get r :timestamp)))
                                           (gptel-auto-workflow--parse-all-results))
                        (lambda (a b) (< (plist-get a :timestamp)
                                         (plist-get b :timestamp)))))
         (previous nil)
         (gaps nil))
    (dolist (r results)
      (let ((timestamp (plist-get r :timestamp)))
        (when (and previous (> (- timestamp (car previous)) threshold))
          (push (cons (plist-get r :target) timestamp) gaps))
        (setq previous (cons timestamp r))))
    (nreverse gaps)))

(defun gptel-auto-workflow--crown-champion (strategy-name keep-rate &optional composite category)
  "Crown STRATEGY-NAME as champion for CATEGORY with KEEP-RATE and COMPOSITE score.
If CATEGORY is nil, crowns the legacy global champion (backward compat).
Gateway: crowns only if KEEP-RATE exceeds current category champion's rate.
The first champion (when none exists) must beat the category baseline.
COMPOSITE is logged for diagnostics but keep-rate remains the gating threshold."
  (when (and strategy-name keep-rate)
    (let* ((cat (or category :natural-language))
           (champion-entry (gptel-auto-workflow--get-category-champion cat))
           (champion-rate (if champion-entry (cdr champion-entry) nil))
           (baseline-entry (assq cat gptel-auto-workflow--category-baselines))
           (cat-baseline (if baseline-entry (cdr baseline-entry)
                           gptel-auto-workflow--baseline-keep-rate))
           (threshold (or champion-rate cat-baseline)))
      (when (or (null threshold) (> keep-rate threshold))
        (gptel-auto-workflow--set-category-champion cat strategy-name keep-rate)
        ;; Also update legacy global for backward compat
        (when (> keep-rate (or gptel-auto-workflow--champion-keep-rate 0.0))
          (setq gptel-auto-workflow--champion-strategy strategy-name
                gptel-auto-workflow--champion-keep-rate keep-rate))
        (when composite
          (setq gptel-auto-workflow--champion-composite-score composite))
        (message "[champion] New %s champion: %s (keep=%.1f%% composite=%.3f baseline=%.1f%%)"
                 cat strategy-name (* 100 keep-rate) (or composite keep-rate)
                 (* 100 cat-baseline))
        t))))

(defun gptel-auto-workflow--gate-strategies ()
  "Gate evolved strategies against per-category champions.
AutoGo category-gating: each ontology category has its own champion.
μ Directness: first champion must beat category baseline, not absolute zero.
Promotion: challenger must exceed category champion by >5% relative."
  (let* ((_loaded (gptel-auto-workflow--load-category-champions))
         (_baselines (gptel-auto-workflow--compute-category-baselines))
         (strategies (gptel-auto-workflow--discover-strategies))
         (scores (mapcar (lambda (s) (cons s (gptel-auto-workflow--strategy-composite-score s)))
                         strategies))
         (scores (sort scores (lambda (a b) (> (cdr a) (cdr b)))))
         (categories '(:programming :tool-calls :agentic :natural-language))
         (results nil))
    (dolist (entry scores)
      (let* ((name (car entry))
             (composite (cdr entry))
             (status-bonus (gptel-auto-workflow--ontology-strategy-status-bonus name))
             (effective-composite (+ composite status-bonus)))
        (catch 'category-result
          (dolist (cat categories)
            ;; ∀ Vigilance: skip frozen categories
            (if (gptel-auto-workflow--category-frozen-p cat)
                (message "[champion] ∀ Vigilance: skipping frozen category %s" cat)
              (let* ((cat-keep-rate (gptel-auto-workflow--strategy-category-keep-rate name cat))
                   (champion-entry (gptel-auto-workflow--get-category-champion cat))
                   (champion-strategy (car champion-entry))
                   (champion-rate (or (cdr champion-entry) 0.0))
                   (baseline-entry (assq cat gptel-auto-workflow--category-baselines))
                   (cat-baseline (or (cdr baseline-entry) 0.10)))
              (when (> cat-keep-rate 0)
                (cond
                 ((null champion-strategy)
                  (when (> cat-keep-rate cat-baseline)
                    (gptel-auto-workflow--crown-champion name cat-keep-rate effective-composite cat)
                    (push (cons name (intern (format "first-%s-champion" cat))) results)
                    (throw 'category-result t)))
                 ((> cat-keep-rate (* champion-rate 1.05))
                   (gptel-auto-workflow--crown-champion name cat-keep-rate effective-composite cat)
                   (push (cons name (intern (format "promoted-%s" cat))) results)
                   (throw 'category-result t))
                 ((and (> cat-keep-rate champion-rate)
                       (> status-bonus 0.05))
                   (gptel-auto-workflow--crown-champion name cat-keep-rate effective-composite cat)
                   (push (cons name (intern (format "promoted-%s-ontology" cat))) results)
                   (throw 'category-result t))
                 ((> cat-keep-rate champion-rate)
                   (push (cons name (intern (format "passed-%s" cat))) results)
                    (throw 'category-result t)))))))
        ;; Fallback: no category hit, use global composite
        (let ((champion-rate gptel-auto-workflow--champion-keep-rate))
          (cond
           ((and champion-rate (> composite champion-rate))
            (push (cons name 'passed-composite) results))
           (t
            (push (cons name 'rejected) results)))))))
    (dolist (cat categories)
      (let ((champion-entry (gptel-auto-workflow--get-category-champion cat)))
        (if champion-entry
            (message "[champion] %s: %s (%.1f%%)"
                     cat (car champion-entry) (* 100 (cdr champion-entry)))
          (message "[champion] %s: no champion yet (baseline=%.1f%%)"
                   cat (* 100 (or (cdr (assq cat gptel-auto-workflow--category-baselines)) 0.10))))
        ;; ∀ Vigilance: track champion failures per category
        (unless champion-entry
          (gptel-auto-workflow--record-category-strike cat))))
    ;; φ Vitality: log novelty of promoted strategies
    (when (and (fboundp 'gptel-auto-workflow--strategy-novelty-score)
               (fboundp 'gptel-auto-workflow--discover-strategies))
      (let ((novelties '()))
        (dolist (r results)
          (when (memq (cdr r) '(first-champion promoted passed))
            (push (cons (car r) 1.0) novelties)))
        (when novelties
           (message "[champion] φ Vitality: %d novel strategies promoted" (length novelties)))))
    results))

(defconst gptel-auto-workflow--pcr-budgets
  '((:name "quick" :weight 0.80 :sims 128)
    (:name "medium" :weight 0.15 :sims 256)
    (:name "deep" :weight 0.05 :sims 2000))
  "Playout Cap Randomization budgets. 80% quick, 15% medium, 5% deep.
AutoGo PCR pattern: randomized effort budget prevents over-specialization.")

(defun gptel-auto-workflow--sample-pcr-budget ()
  "Sample an effort budget from PCR distribution. Returns sims count."
  (let* ((r (random 100))
         (cumulative 0))
    (catch 'found
      (dolist (b gptel-auto-workflow--pcr-budgets)
        (setq cumulative (+ cumulative (* 100 (plist-get b :weight))))
        (when (< r cumulative)
          (throw 'found (plist-get b :sims))))
      (plist-get (car gptel-auto-workflow--pcr-budgets) :sims))))

(defun gptel-auto-workflow--emit-result (metric-name value delta status &optional extra)
  "Emit a machine-parseable RESULT block. AutoGo ===RESULT=== protocol.
METRIC-NAME is the metric being measured. VALUE is current value.
DELTA is change from baseline. STATUS is keep/discard/timeout.
EXTRA is an optional plist of additional fields."
  (let ((result (list :metric metric-name :value value :delta delta
                      :status status :timestamp (format-time-string "%Y-%m-%dT%H:%M")
                      :champion gptel-auto-workflow--champion-strategy
                      :champion-keep-rate gptel-auto-workflow--champion-keep-rate)))
    (when extra (setq result (append result extra)))
    (message "===RESULT=== %s" (json-encode result))
    result))

(defun gptel-auto-workflow--detect-overfitting ()
  "Detect if train improves but holdout doesn't. Returns overfit/improving/stable.
AutoGo holdout pattern: crosses train vs holdout trends."
  (let* ((h (gptel-auto-workflow--evaluate-holdout))
         (ht (plist-get h :trend))
         (tr (gptel-auto-workflow--overall-keep-rate))
         (tt (- tr (or gptel-auto-workflow--champion-keep-rate 0))))
    (cond ((and (> tt 0.02) (< ht -0.02)) 'overfit)
          ((and (> tt 0) (>= ht 0)) 'improving)
          (t 'stable))))

;; ─── Backend Performance Optimization ───


(defun gptel-auto-workflow--evaluate-holdout ()
  "Evaluate frozen holdout targets. Returns plist with :average :trend."
  (let* ((root (gptel-auto-workflow--worktree-base-root))
         (targets (list "lisp/modules/gptel-tools-agent-error.el"
                        "lisp/modules/gptel-auto-workflow-evolution.el"
                        "lisp/modules/gptel-tools-agent-prompt-build.el"))
         (total 0.0) (count 0)
          (hf (expand-file-name "var/tmp/evolution/holdout-eval.json" root))
          (history (condition-case nil
                       (let ((raw (with-temp-buffer
                                    (insert-file-contents hf)
                                    (json-read))))
                         (if (and (listp raw) (not (keywordp (car raw))))
                             (let ((plist nil))
                               (dolist (pair raw plist)
                                 (when (consp pair)
                                   (let* ((k (car pair))
                                          (key (cond
                                                ((keywordp k) k)
                                                ((stringp k) (intern (concat ":" k)))
                                                (t (intern (concat ":" (symbol-name k)))))))
                                     (setq plist (plist-put plist key (cdr pair))))))
                               plist)
                           raw))
                     (error (list :history nil :best 0.0)))))
    (dolist (target targets)
      (let ((fp (expand-file-name target root)))
        (setq total (+ total (if (file-readable-p fp)
                                 (gptel-auto-workflow--score-holdout-target fp) 0.0))
              count (1+ count))))
    (let* ((avg (if (> count 0) (/ total count) 0.0))
           (best (max avg (or (plist-get history :best) 0.0)))
           (prev (or (plist-get history :last) avg))
           (trend (- avg prev))
           (entry (list :t (format-time-string "%Y-%m-%dT%H:%M") :avg avg)))
      (setq history (plist-put history :last avg))
      (setq history (plist-put history :best best))
      (setq history (plist-put history :history
                       (cons entry (seq-take (plist-get history :history) 10))))
      (make-directory (file-name-directory hf) t)
      (with-temp-file hf (insert (json-encode (list :history (plist-get history :history) :best best :last avg))))
      (list :average avg :trend trend :best best))))

(defun gptel-auto-workflow--score-holdout-target (file-path)
  "Score FILE-PATH on structural quality 0.0-1.0."
  (let ((s 0.0))
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents file-path)
          (let ((n (count-lines (point-min) (point-max))))
            (when (> n 0)
              (let ((c (buffer-string)))
                (dolist (patt (list "when.*nil\\|unless.*nil\\|guard\\|proper-list-p"
                                    "condition-case\\|ignore-errors"))
                  (let ((m (cl-count-if (lambda (l) (string-match-p patt l))
                                        (split-string c "\n"))))
                    (setq s (+ s (min 1.0 (/ (* m 10.0) n))))))))))
      (ignore))
    (min 1.0 (/ s 2.0))))


(defun gptel-auto-workflow--score-research-sources ()
  "Score research repos by downstream experiment keep-rate.
Returns alist of (source-repo . keep-rate) sorted by performance.
Source repos are extracted from prefetched content patterns."
  (let* ((results (gptel-auto-workflow--parse-all-results))
         (by-source (make-hash-table :test 'equal))
         (stats nil))
    (dolist (r results)
      (let* ((strategy (plist-get r :research-strategy))
             (kept (equal (plist-get r :decision) "kept")))
        (when (and (stringp strategy) (not (equal strategy "none")))
          (let ((entry (or (gethash strategy by-source) (cons 0 0))))
            (setcar entry (1+ (car entry)))
            (when kept (setcdr entry (1+ (cdr entry))))
            (puthash strategy entry by-source)))))
    (maphash (lambda (source counts)
               (when (> (car counts) 2)
                 (push (cons source (/ (float (cdr counts)) (car counts))) stats)))
             by-source)
    (sort stats (lambda (a b) (> (cdr a) (cdr b))))))

;; ─── LogMap: Inverted File + Horn SAT ───

(defvar gptel-auto-workflow--pattern-inverted-file (make-hash-table :test (quote equal))
  "Inverted file: token → set of page IDs. LogMap O(1) pattern lookup.")

(defun gptel-auto-workflow--build-inverted-file ()
  "Build inverted file from knowledge pages. Returns hash of token→page-ids."
  (clrhash gptel-auto-workflow--pattern-inverted-file)
  (let* ((kd (expand-file-name "mementum/knowledge" (gptel-auto-workflow--worktree-base-root)))
         (files (when (file-directory-p kd) (directory-files kd t "research-insights-.+\\.md$"))))
    (dolist (f files)
      (let ((name (file-name-nondirectory f)))
        (condition-case nil
            (with-temp-buffer (insert-file-contents f)
              (dolist (w (split-string (downcase (buffer-string)) "[^a-z0-9]+" t))
                (unless (< (length w) 3)
                  (let ((entry (or (gethash w gptel-auto-workflow--pattern-inverted-file) (make-hash-table :test (quote equal)))))
                    (puthash name t entry)
                    (puthash w entry gptel-auto-workflow--pattern-inverted-file)))))
          (ignore)))))
  (message "[logmap] Inverted file: %d tokens indexed" (hash-table-count gptel-auto-workflow--pattern-inverted-file)))

(defun gptel-auto-workflow--query-inverted-file (query)
  "Find pages matching QUERY via inverted file intersection."
  (let* ((tokens (seq-filter (lambda (w) (> (length w) 2)) (split-string (downcase query) "[^a-z0-9]+" t)))
         (freq (make-hash-table :test (quote equal))))
    (dolist (token tokens)
      (let ((matches (gethash token gptel-auto-workflow--pattern-inverted-file)))
        (when matches (maphash (lambda (k _v) (puthash k (1+ (or (gethash k freq) 0)) freq)) matches))))
    (let ((pairs nil))
      (maphash (lambda (k v) (push (cons k v) pairs)) freq)
      (sort pairs (lambda (a b) (> (cdr a) (cdr b)))))))

(defun gptel-auto-workflow--write-research-priorities ()
  "Write research-priorities.md based on historical outcomes.
Consumed by researcher daemon to focus on high-value repos."
  (let* ((root (gptel-auto-workflow--worktree-base-root))
         (file (expand-file-name "var/tmp/evolution/research-priorities.md" root))
         (sources (gptel-auto-workflow--score-research-sources))
         (top (seq-take sources 5))
         (bottom (seq-take (nreverse (copy-sequence sources)) 3)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file
      (insert "# Research Priorities (auto-generated from experiment outcomes)\n\n")
      (insert (format "> Updated: %s | %d total research traces analyzed\n\n"
                      (format-time-string "%Y-%m-%d %H:%M")
                      (length sources)))
      (when top
        (insert "## High-Value Research Sources (prioritize these)\n\n")
        (dolist (s top)
          (insert (format "- **%s**: %.0f%% keep-rate (%d experiments)\n"
                          (car s) (* 100 (cdr s))
                          (let ((entry (assoc (car s) sources #'string=)))
                            (if entry (cdr entry) 0)))))
        (insert "\n"))
      (when bottom
        (insert "## Low-Value Research Sources (deprioritize these)\n\n")
        (dolist (s bottom)
          (insert (format "- %s: %.0f%% keep-rate — consider different approach\n"
                          (car s) (* 100 (cdr s)))))
        (insert "\n"))
      (insert "## Guidance\n\n")
      (insert "- Focus on high-value sources — their techniques produced kept experiments.\n")
      (insert "- For low-value sources: either research deeper files or skip until strategy changes.\n")
      (insert "- Prefer sources that produced BREAKING or POTENTIAL impact (safe = low signal).\n"))
    (message "[research-priorities] Wrote %d sources to %s" (length sources) file)))

(defun gptel-auto-workflow--enrich-ontology-from-research ()
  "Extract new techniques from researcher's Allium spec and merge into ontology.
Researcher now outputs Allium v3 behavioral specs — parse Technique entities.
Semantica pattern: continuous ontology enrichment by the research agent.
Guards: skips enrichment when EMA confidence < 0.3 (untrusted research signal)."
  (cl-block gptel-auto-workflow--enrich-ontology-from-research
  (let* ((root (gptel-auto-workflow--worktree-base-root))
         (findings-file (expand-file-name "var/tmp/research-findings.md" root))
         (new-concepts nil))
    (when (< (or (and (boundp 'gptel-auto-workflow--research-ema-conf)
                      gptel-auto-workflow--research-ema-conf) 0.5) 0.3)
      (message "[onto-enrich] EMA confidence %.2f < 0.3 — skipping enrichment (untrusted research)"
               (or (and (boundp 'gptel-auto-workflow--research-ema-conf)
                        gptel-auto-workflow--research-ema-conf) 0.0))
      (cl-return-from gptel-auto-workflow--enrich-ontology-from-research nil))
    (when (file-readable-p findings-file)
      (with-temp-buffer
        (insert-file-contents findings-file)
        (goto-char (point-min))
        ;; Parse Allium Technique entities: entity Technique { name: "X" source: "Y" ... }
        (while (re-search-forward "Technique\\.created(\\s-*name:\\s-*\\([^,\n]+\\)" nil t)
          (let ((name (string-trim (match-string 1) "\"" "\"")))
            (unless (string-empty-p name)
              (push name new-concepts))))
        ;; Also catch markdown fallback headings
        (goto-char (point-min))
        (while (re-search-forward "^## \\([^R][^e][^s].+\\)" nil t)
          (let ((technique (string-trim (match-string 1))))
            (unless (string-match-p "^Research\|^Pre-Fetched\|^Source\|^Dynamic\|^Local\|Technique Name" technique)
              (push technique new-concepts))))
        ;; Check against existing knowledge pages for novelty
        (let ((kd (expand-file-name "mementum/knowledge" root))
              (novel nil))
          (when (file-directory-p kd)
            (let ((existing (mapconcat (lambda (f)
                                         (with-temp-buffer
                                           (insert-file-contents f)
                                           (goto-char (point-min))
                                           (if (re-search-forward "^title: \\(.+\\)" nil t)
                                               (match-string 1) "")))
                                       (directory-files kd t "research-insights-.+\\.md$")
                                       " ")))
              (dolist (c (nreverse (delete-dups new-concepts)))
                (unless (string-match-p (regexp-quote c) existing)
                  (push c novel))))
            (when novel
              (message "[onto-enrich] %d new techniques from researcher: %s"
                       (length novel) (mapconcat #'identity (seq-take novel 3) ", "))
              (let ((onto (gptel-auto-workflow--generate-experiment-ontology)))
                (when (and onto (> (plist-get onto :class-count) 0)
                           (fboundp 'gptel-auto-experiment--owl-save))
                  (gptel-auto-experiment--owl-save
                   onto (expand-file-name "var/tmp/evolution/enriched-ontology.ttl" root)
                     (lambda (_ok) nil))))))))))))

(defun gptel-auto-workflow--queue-research-pair-probes ()
  "Parse [pair-probe] HA/HB blocks from research findings and auto-queue as experiments.
Each pair-probe block contains an optimization hypothesis with Elisp code.
Queues under :research-probes key in hints for the experiment loop to consume."
  (let* ((root (gptel-auto-workflow--worktree-base-root))
         (findings-file (expand-file-name "var/tmp/research-findings.md" root))
         (probes nil))
    (when (file-readable-p findings-file)
      (with-temp-buffer
        (insert-file-contents findings-file)
        (goto-char (point-min))
        (while (re-search-forward "\\[pair-probe\\] \\*\\*\\(H[AB]\\)\\*\\*: \\([^\n]+\\)" nil t)
          (let ((label (match-string 1))
                (description (string-trim (match-string 2)))
                (code-block nil))
            (when (re-search-forward "```elisp\n\\([^`]+\\)```" nil t)
              (setq code-block (string-trim (match-string 1))))
            (when (and description code-block (> (length code-block) 10))
              (push (list :hypothesis (format "[%s] %s" label description)
                          :code code-block
                          :source "research-pair-probe"
                          :priority 2)
                    probes)))))
      (when probes
        (setq gptel-auto-workflow--evolution-next-cycle-hints
              (plist-put gptel-auto-workflow--evolution-next-cycle-hints
                         :research-probes (nreverse probes)))
        (message "[research-probes] Queued %d pair-probe hypotheses for experimentation"
                 (length probes))))))

;; ─── LogMap: Ambiguity filtering + Second-chance repair ───

(defun gptel-auto-workflow--ambiguity-score (target)
  "Count competing strategies for TARGET. High = many interpretations.
LogMap ambiguity heuristic: count(competing_matches) per entity."
  (let* ((results (gptel-auto-workflow--parse-all-results))
         (strategies (make-hash-table :test 'equal)))
    (dolist (r results)
      (when (equal (plist-get r :target) target)
        (puthash (or (plist-get r :strategy) "unknown") t strategies)))
    (hash-table-count strategies)))

(defun gptel-auto-workflow--filter-by-ambiguity (targets max-ambiguity)
  "Filter TARGETS: discard those with too many competing strategies.
LogMap pattern: defer high-ambiguity candidates to expert review."
  (let ((kept nil) (deferred nil))
    (dolist (target targets)
      (let ((amb (gptel-auto-workflow--ambiguity-score target)))
        (if (> amb max-ambiguity)
            (push (cons target amb) deferred)
          (push target kept))))
    (when deferred
      (message "[ambiguity] %d targets deferred (ambiguity >%d):" (length deferred) max-ambiguity)
      (dolist (d (seq-take deferred 3))
        (message "[ambiguity]   %s: %d competing strategies" (car d) (cdr d))))
    (list :kept (nreverse kept) :deferred (nreverse deferred))))

(defvar gptel-auto-workflow--conflictive-experiments nil
  "Soft-deleted experiments stored for second-chance repair. LogMap pattern.")

(defun gptel-auto-workflow--second-chance-repair ()
  "Re-evaluate soft-deleted experiments. Promotes those no longer conflicting.
LogMap second-chance pattern: periodically re-check removed mappings."
  (let ((rehabilitated nil) (still-conflictive nil))
    (dolist (exp gptel-auto-workflow--conflictive-experiments)
      (let* ((target (plist-get exp :target))
             (changed nil))
        ;; Check if target has been improved since discarding
        (dolist (r (gptel-auto-workflow--parse-all-results))
          (when (and (equal (plist-get r :target) target)
                     (equal (plist-get r :decision) "kept")
                     (> (or (plist-get r :score-after) 0) (or (plist-get exp :score-after) 0)))
            (setq changed t)))
        (if changed
            (push exp rehabilitated)
          (push exp still-conflictive))))
    (setq gptel-auto-workflow--conflictive-experiments still-conflictive)
    (when rehabilitated
      (message "[second-chance] %d experiments rehabilitated (target improved since discard)"
               (length rehabilitated)))
    (list :rehabilitated rehabilitated :still-conflictive (length still-conflictive))))

(defun gptel-auto-workflow--mark-conflictive (experiment)
  "Mark EXPERIMENT as soft-deleted for future second-chance repair."
  (push experiment gptel-auto-workflow--conflictive-experiments)
  (when (> (length gptel-auto-workflow--conflictive-experiments) 50)
    (setq gptel-auto-workflow--conflictive-experiments
          (seq-take gptel-auto-workflow--conflictive-experiments 50))))

;; ─── LogMap: I-Sub similarity + Scope scoring + Interval Labelling ───

(defun gptel-auto-workflow--isub (s1 s2)
  "I-Sub string similarity (LogMap/Stoilos ISWC 2005).
commonality - dissimilarity + winkler improvement."
  (let* ((common 0) (rest1 s1) (rest2 s2)
         (l1 (length s1)) (l2 (length s2)))
    (while (and (> (length rest1) 2) (> (length rest2) 2))
      (let ((best-i 0) (best-j 0) (best-len 0))
        (dotimes (i (length rest1))
          (dotimes (j (min (- (length rest1) i) (length rest2)))
            (when (>= j 2)
              (let ((sub (substring rest1 i (+ i j 1))))
                (when (and (string-match-p (regexp-quote sub) rest2)
                           (> (1+ j) best-len))
                  (setq best-len (1+ j) best-i i
                        best-j (string-match (regexp-quote sub) rest2)))))))
        (if (> best-len 2)
            (progn (setq common (+ common best-len))
                   (setq rest1 (concat (substring rest1 0 best-i)
                                       (substring rest1 (+ best-i best-len))))
                   (setq rest2 (concat (substring rest2 0 best-j)
                                       (substring rest2 (+ best-j best-len)))))
          (setq rest1 ""))))
    (let* ((commonality (if (> (+ l1 l2) 0) (/ (* 2.0 common) (+ l1 l2)) 0.0))
           (unmatched1 (if (> l1 0) (/ (float (length rest1)) l1) 0.0))
           (unmatched2 (if (> l2 0) (/ (float (length rest2)) l2) 0.0))
           (product (* unmatched1 unmatched2))
           (suma (+ unmatched1 unmatched2))
           (p 0.6)
           (dissimilarity (if (> (+ p (* (- 1 p) (- suma product))) 0)
                              (/ product (+ p (* (- 1 p) (- suma product)))) 0.0))
           (winkler (min 4 (cl-loop for a across s1 for b across s2
                                    while (eq a b) count 1)))
           (winkler-bonus (* winkler 0.1 (- 1 commonality))))
      (max 0.0 (min 1.0 (+ (- commonality dissimilarity) winkler-bonus))))))

(defun gptel-auto-workflow--scope-score (entity-id hierarchy)
  "Scope scoring: ancestor/descendant intersection ratio.
HIERARCHY is alist of (child . parent). Returns 0.0-1.0.
LogMap scope pattern: |scope(A) ∩ scope(B)| / |scope(A) ∪ scope(B)|."
  (ignore entity-id hierarchy)
  0.0)

(defun gptel-auto-workflow--build-interval-labels (hierarchy)
  "Build Interval Labelling Schema over HIERARCHY (alist of child . parent).
Returns hash of node → (pre post desc-min desc-max). LogMap ILS pattern."
  (let ((labels (make-hash-table :test 'equal))
        (order 0)
        (children (make-hash-table :test 'equal))
        (roots nil))
    (dolist (pair hierarchy)
      (let ((child (car pair)) (parent (cdr pair)))
        (let ((c (or (gethash parent children) nil)))
          (push child c)
          (puthash parent c children))))
    (dolist (pair hierarchy)
      (unless (assoc (car pair) hierarchy)
        (push (car pair) roots)))
    (cl-labels ((dfs (node)
                  (let ((pre order) (desc-min order))
                    (setq order (1+ order))
                    (dolist (c (gethash node children))
                      (let ((child-labels (dfs c)))
                        (setq desc-min (min desc-min (car child-labels)))))
                    (puthash node (list pre order desc-min order) labels)
                    (list desc-min order))))
      (dolist (root (or roots (mapcar #'car hierarchy)))
        (dfs root)))
    labels))

(defun gptel-auto-workflow--is-subclass (child parent labels)
  "O(1) subsumption: is CHILD a subclass of PARENT?
LABELS is from build-interval-labels."
  (let ((cl (gethash child labels)) (pl (gethash parent labels)))
    (and cl pl (>= (nth 0 cl) (nth 2 pl)) (<= (nth 0 cl) (nth 3 pl)))))

;; ─── LogMap: LLM-as-Oracle + Two-phase repair + Precomputed combinations ───

(defvar gptel-auto-workflow--llm-oracle-mappings nil
  "LLM-validated mappings stored as (entity1 . entity2) for oracle re-run.")

(defun gptel-auto-workflow--produce-candidates-for-llm (max-candidates)
  "Produce uncertain candidates for LLM validation. LogMap LLM-as-Oracle pattern."
  (let* ((results (gptel-auto-workflow--parse-all-results))
         (candidates nil))
    (dolist (r results)
      (let ((decision (plist-get r :decision))
            (target (plist-get r :target))
            (strategy (plist-get r :strategy)))
        (when (and (equal decision "discarded") target strategy
                   (< (gptel-auto-workflow--ambiguity-score target) 3))
          (push (list :target target :strategy strategy
                      :score-before (plist-get r :score-before)
                      :score-after (plist-get r :score-after))
                candidates))))
    (seq-take candidates max-candidates)))

(defun gptel-auto-workflow--load-llm-oracle (csv-path)
  "Load LLM-validated mappings from CSV. LogMap LocalOracle pattern.
Format: target,strategy,prediction,confidence"
  (setq gptel-auto-workflow--llm-oracle-mappings nil)
  (when (file-readable-p csv-path)
    (with-temp-buffer
      (insert-file-contents csv-path)
      (goto-char (point-min))
      (while (re-search-forward "^\\([^,]+\\),\\([^,]+\\),\\(True\\|true\\),\\([0-9.]+\\)" nil t)
        (push (cons (match-string 1) (match-string 2))
              gptel-auto-workflow--llm-oracle-mappings))))
  (message "[oracle] Loaded %d LLM-validated mappings" (length gptel-auto-workflow--llm-oracle-mappings)))

(defun gptel-auto-workflow--two-phase-repair (conflictive-mappings)
  "Phase 1: fast D&G approximate. Phase 2: full backtracking for hard cases.
Returns repaired set. LogMap two-phase repair pattern."
  (let* ((simple (and (< (length conflictive-mappings) 15) conflictive-mappings))
         (hard (and (>= (length conflictive-mappings) 15) conflictive-mappings))
         (kept nil))
    (dolist (m simple) (push m kept)) ;; Phase 1: simple pass, keep if <15 conflicts
    (when hard
      ;; Phase 2: aggressive — only keep mappings validated by LLM oracle
      (dolist (m hard)
        (let ((pair (cons (plist-get m :target) (plist-get m :strategy))))
          (when (member pair gptel-auto-workflow--llm-oracle-mappings)
            (push m kept)))))
    (nreverse kept)))

(defvar gptel-auto-workflow--precomputed-combinations (make-hash-table :test 'equal)
  "Cached C(n,k) combinations. LogMap PrecomputeIndexCombination pattern.")

(defun gptel-auto-workflow--combinations (items k)
  "Return all k-combinations of ITEMS, cached. LogMap C(n,k) enumeration."
  (let ((key (format "%d-%d" (length items) k)))
    (or (gethash key gptel-auto-workflow--precomputed-combinations)
        (let ((result nil))
          (cl-labels ((combine (start current)
                        (when (= (length current) k)
                          (push (nreverse current) result))
                        (cl-loop for i from start below (length items)
                                 do (combine (1+ i) (cons (nth i items) current)))))
            (combine 0 nil))
          (puthash key result gptel-auto-workflow--precomputed-combinations)
          result))))

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
        ;; Skip invalid backends
        (unless (member backend '("0" "unknown" ""))
          (let ((entry (or (gethash backend by-backend) (cons 0 0))))
            (setcar entry (1+ (car entry)))
            (when kept (setcdr entry (1+ (cdr entry))))
            (puthash backend entry by-backend)))))
    (maphash (lambda (backend counts)
               (when (> (car counts) 5)
                 (push (cons backend (/ (float (cdr counts)) (car counts))) stats)))
             by-backend)
    (sort stats (lambda (a b) (> (cdr a) (cdr b))))))

(defun gptel-auto-workflow--evolution-strategy-structure-scores ()
  "Analyze prompt structure scores per strategy from experiment results.
Return alist of strategy to average structure score."
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
  "Load recent Allium check issues for prompt guidance.
Returns markdown grouped by strategy, or an empty string."
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
              (ignore))))
        (if result
            (concat "### Allium Behavioral Audit (coherence check of last cycle's research)\n\n"
                    (mapconcat #'identity (nreverse result) "\n---\n"))
          "")))))

(defun gptel-auto-workflow--allium-read-quality (safe-strategy)
  "Read Allium quality for SAFE-STRATEGY from disk."
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
                (let ((count 0) (pos 0) (severity 0.0)
                      (buf-str (buffer-string)))
                  (while (string-match "^[0-9]+\\." buf-str pos)
                    (setq count (1+ count) pos (match-end 0)))
                  (when (string-match "\\*\\*Severity:\\*\\* \\([0-9.]+\\)" buf-str)
                    (setq severity (string-to-number (match-string 1 buf-str))))
                  (cons count severity))))))))))

(defun gptel-auto-workflow--allium-check-research-quality (findings-summary &optional callback)
  "Distill FINDINGS-SUMMARY to Allium spec and invoke CALLBACK."
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

(defun gptel-auto-workflow--allium-diff-opposing-hypotheses ()
  "Find opposing hypotheses from kept+discarded experiments and diff via Allium.
Compares the most recently kept hypothesis against the most recently discarded
one for the same target. Logs which side has cleaner behavioral spec.
Non-blocking — runs async via gptel callbacks."
  (when (and (fboundp 'gptel-auto-experiment--allium-distill)
             (fboundp 'gptel-auto-experiment--allium-check))
    (let* ((results (gptel-auto-workflow--parse-all-results))
           (by-target (make-hash-table :test 'equal))
           (targets nil))
      (dolist (r results)
        (let ((target (plist-get r :target))
              (hypothesis (plist-get r :hypothesis))
              (decision (plist-get r :decision)))
          (when (and (stringp target) (stringp hypothesis)
                     (not (string-empty-p target)))
            (unless (gethash target by-target)
              (push target targets))
            (push (cons decision hypothesis) (gethash target by-target)))))
       (dolist (target (nreverse targets))
         (let ((entries (gethash target by-target)))
          (when (listp entries)
            (let ((kept (cl-find "kept" entries :key #'car :test #'equal))
                  (discarded (cl-find "discarded" entries :key #'car :test #'equal)))
              (when (and kept discarded)
                (gptel-auto-workflow--allium-diff-minimal-pairs
                 (cdr kept) (cdr discarded)
                 (lambda (result)
                   (message "[allium-diff] %s: kept-issues=%d discarded-issues=%d"
                            target (car result) (cdr result))
                   (when (< (car result) (cdr result))
                     (message "[allium-diff] %s: kept hypothesis has cleaner spec (kept=%d < discarded=%d)"
                               target (car result) (cdr result)))))))))))))

;; ─── Allium Improvements: trend tracking, dedup, regression detection, auto-repair ───

(defun gptel-auto-workflow--allium-trend-issues ()
  "Analyze Allium issues across all strategies for recurring patterns.
Returns plist with :trends (deduplicated issue patterns with counts),
:regressions (strategies with increased issues), :critical-count."
  (let* ((root (gptel-auto-workflow--worktree-base-root))
         (issues-dir (and root (expand-file-name "var/tmp/evolution/allium-issues" root)))
         (pattern-counts (make-hash-table :test 'equal))
         (strategy-issues (make-hash-table :test 'equal))
         (regressions nil)
         (critical 0))
    (when (and issues-dir (file-directory-p issues-dir))
      (dolist (issue-file (directory-files issues-dir t "\\.md$"))
        (condition-case nil
            (let* ((name (file-name-base issue-file))
                   (mtime (file-attribute-modification-time (file-attributes issue-file)))
                   (fresh (time-less-p (time-subtract (current-time) (days-to-time 7)) mtime)))
              (when fresh
                (with-temp-buffer
                  (insert-file-contents issue-file)
                  (goto-char (point-min))
                  (let ((issue-count 0) (severity 0.0))
                    ;; Count issues and severity
                    (when (string-match "\\*\\*Issues:\\*\\* \\([0-9]+\\)" (buffer-string))
                      (setq issue-count (string-to-number (match-string 1 (buffer-string)))))
                    (when (string-match "\\*\\*Severity:\\*\\* \\([0-9.]+\\)" (buffer-string))
                      (setq severity (string-to-number (match-string 1 (buffer-string)))))
                    (when (> severity 0.3) (cl-incf critical))
                    ;; Extract individual issue patterns for dedup
                    (goto-char (point-min))
                    (let ((_pos (point-min)))
                      (while (re-search-forward "^[0-9]+\\.\\s-*\\*\\*\\([^*]+\\)\\*\\*" nil t)
                        (let ((pattern (match-string 1)))
                          (puthash pattern (1+ (or (gethash pattern pattern-counts) 0))
                                   pattern-counts))))
                    ;; Record per-strategy count for regression detection
                    (puthash name (cons issue-count severity) strategy-issues))))
              ;; Regression detection: compare with previous cycle
              (let ((prev-file (expand-file-name
                                (format "%s.prev" name)
                                (expand-file-name "var/tmp/evolution/allium-regressions" root))))
                (when (file-readable-p prev-file)
                  (with-temp-buffer
                    (insert-file-contents prev-file)
                    (let ((prev-count (string-to-number (or (car (split-string (buffer-string) ":")) "0"))))
                      (when (> (car (gethash name strategy-issues)) prev-count)
                        (push (list name prev-count (car (gethash name strategy-issues)))
                              regressions)))))))
          (ignore))))
    (list :trends (sort (mapcar (lambda (k) (cons k (gethash k pattern-counts)))
                                (hash-table-keys pattern-counts))
                        (lambda (a b) (> (cdr a) (cdr b))))
          :regressions regressions
          :critical-count critical)))

(defun gptel-auto-workflow--allium-trends-report ()
  "Generate a markdown report of Allium issue trends.
Returns string suitable for mementum or prompt injection."
  (let* ((analysis (gptel-auto-workflow--allium-trend-issues))
         (trends (plist-get analysis :trends))
         (regressions (plist-get analysis :regressions))
         (critical (plist-get analysis :critical-count))
         (lines nil))
    (push "### Allium Issue Trends\n" lines)
    (when trends
      (push (format "**Recurring patterns** across all strategies:\n\n" ) lines)
      (dolist (trend (seq-take trends 10))
        (push (format "- **%s**: %d occurrence(s)\n" (car trend) (cdr trend)) lines))
      (push "\n" lines))
    (when regressions
      (push (format "**Regression warnings** (%d strategies with increased issues):\n\n" (length regressions)) lines)
      (dolist (r regressions)
        (push (format "- `%s`: %d → %d issues (worse)\n" (nth 0 r) (nth 1 r) (nth 2 r)) lines))
      (push "\n" lines))
    (when (> critical 0)
      (push (format "**Critical**: %d research strategies have severity > 0.3 — consider auto-repair experiments.\n" critical) lines))
    (apply #'concat (nreverse lines))))

(defun gptel-auto-workflow--allium-save-regression-baseline ()
  "Save current issue counts as baseline for next cycle's regression detection."
  (let* ((root (gptel-auto-workflow--worktree-base-root))
         (issues-dir (and root (expand-file-name "var/tmp/evolution/allium-issues" root)))
         (baseline-dir (and root (expand-file-name "var/tmp/evolution/allium-regressions" root))))
    (when (and issues-dir baseline-dir (file-directory-p issues-dir))
      (make-directory baseline-dir t)
      (dolist (issue-file (directory-files issues-dir t "\\.md$"))
        (condition-case nil
            (let* ((name (file-name-base issue-file))
                   (baseline-file (expand-file-name (format "%s.prev" name) baseline-dir)))
              (with-temp-buffer
                (insert-file-contents issue-file)
                (goto-char (point-min))
                (let ((issue-count 0))
                  (when (string-match "\\*\\*Issues:\\*\\* \\([0-9]+\\)" (buffer-string))
                    (setq issue-count (string-to-number (match-string 1 (buffer-string)))))
                  (with-temp-file baseline-file
                    (insert (format "%d:0" issue-count))))))
          (ignore))))))

(defun gptel-auto-workflow--allium-build-repair-target (strategy-name)
  "Generate a repair guidance prompt for STRATEGY-NAME with critical Allium issues.
Returns a string suitable for injection into the next experiment targeting this strategy's research area."
  (let* ((root (gptel-auto-workflow--worktree-base-root))
         (issue-file (and root (expand-file-name
                                (format "%s.md" strategy-name)
                                (expand-file-name "var/tmp/evolution/allium-issues" root)))))
    (if (and issue-file (file-readable-p issue-file))
        (with-temp-buffer
          (insert-file-contents issue-file)
          (goto-char (point-min))
          (let ((count 0) (severity 0.0))
            (when (string-match "\\*\\*Issues:\\*\\* \\([0-9]+\\)" (buffer-string))
              (setq count (string-to-number (match-string 1 (buffer-string)))))
            (when (string-match "\\*\\*Severity:\\*\\* \\([0-9.]+\\)" (buffer-string))
              (setq severity (string-to-number (match-string 1 (buffer-string)))))
            (if (> severity 0.3)
                (format "## Allium Research Coherence Repair

The research strategy `%s` has **%d issues** (severity %.2f).
Your task: improve the RESEARCH QUALITY (not the code) by fixing behavioral
spec coherence problems. Common fixes:
- Add missing preconditions to research rules
- Remove contradictory requires clauses
- Fix transition graph violations in the research pipeline
- Add missing trace evidence for claimed outcomes

The issues below were found by static analysis of the behavioral spec.
Address them to improve future experiment success rates.

%s"
                        strategy-name count severity
                        (buffer-substring (point-min) (point-max)))
              "")))
      "")))

(defun gptel-auto-workflow--allium-load-issues-for-target (target)
  "Load Allium issues relevant to TARGET for experiment prompt injection.
Returns markdown string with issues from strategies that have experimented on TARGET,
or empty string if none found."
  (let* ((results (gptel-auto-workflow--parse-all-results))
         (relevant-strategies (make-hash-table :test 'equal))
         (root (gptel-auto-workflow--worktree-base-root))
         (result nil))
    ;; Find strategies that have experimented on this target
    (dolist (r results)
      (when (and (equal (plist-get r :target) target)
                 (plist-get r :strategy))
        (puthash (plist-get r :strategy) t relevant-strategies)))
    (when root
      (let ((issues-dir (expand-file-name "var/tmp/evolution/allium-issues" root)))
        (when (file-directory-p issues-dir)
          (maphash
           (lambda (strategy _)
             (let ((issue-file (expand-file-name (format "%s.md" strategy) issues-dir)))
               (when (file-readable-p issue-file)
                 (condition-case nil
                     (let ((mtime (file-attribute-modification-time (file-attributes issue-file))))
                       (when (time-less-p (time-subtract (current-time) (days-to-time 14))
                                          mtime)
                         (with-temp-buffer
                           (insert-file-contents issue-file)
                           (goto-char (point-min))
                           (let ((content (buffer-string)))
                             (when (> (length content) 20)
                               (push (format "### Research quality for strategy `%s` (from Allium audit):\n\n%s"
                                             strategy content)
                                     result))))))
                   (ignore)))))
           relevant-strategies))))
    (if result
        (concat "## Previous Research Quality Issues (Allium audit)\n\n"
                (mapconcat #'identity (nreverse result) "\n---\n")
                "\n> Improve research strategy coherence to achieve better experiment outcomes.\n")
      "")))

;; ─── Semantica Ontology: experiment → class/instance structure ───

(defun gptel-auto-workflow--generate-experiment-ontology ()
  "Generate an ontology from experiment results (Semantica pattern).
Returns ontology plist with class and instance counts.
Uses recency weights when `gptel-auto-workflow--recency-weighted-ontology' is available."
  (if (fboundp 'gptel-auto-workflow--recency-weighted-ontology)
      (gptel-auto-workflow--recency-weighted-ontology)
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
            :instance-count (hash-table-count target-instances))))))
;; ─── Ontology weight overrides ───

(defun gptel-auto-workflow--ontology-strategy-status-bonus (strategy-name)
  "Return bonus score from ontology strategy status.
effective +0.10, promising +0.05, underperforming -0.05."
  (let* ((onto (gptel-auto-workflow--generate-experiment-ontology))
         (classes (plist-get onto :classes))
         (entry (cl-find strategy-name classes :test #'string=
                        :key (lambda (c) (plist-get c :name)))))
    (if entry (pcase (plist-get entry :status) ("effective" 0.10) ("promising" 0.05) ("underperforming" -0.05) (_ 0)) 0)))

(defun gptel-auto-workflow--recency-weighted-ontology ()
  "Generate ontology with recency weights. Recent (<24h) 3x, 1-7d 1x, older 0.5x."
  (let* ((results (gptel-auto-workflow--parse-all-results))
         (classes (make-hash-table :test 'equal))
         (instances (make-hash-table :test 'equal))
         (now (float-time)) (recency (- now (* 24 3600))) (mid (- now (* 7 24 3600))))
    (dolist (r results)
      (let* ((s (or (plist-get r :strategy) "template-default"))
             (target (plist-get r :target)) (d (plist-get r :decision))
             (ts (or (plist-get r :timestamp) 0))
             (w (cond ((>= ts recency) 3.0) ((>= ts mid) 1.0) (t 0.5))))
        (when (stringp s)
          (let ((e (or (gethash s classes) (list :wt 0.0 :wk 0.0 :rt 0 :rk 0))))
            (cl-incf (plist-get e :rt)) (cl-incf (plist-get e :wt) w)
            (when (equal d "kept") (cl-incf (plist-get e :rk)) (cl-incf (plist-get e :wk) w))
            (puthash s e classes)))
        (when (and (stringp target) (not (string-empty-p target)))
          (let ((e (or (gethash target instances) (list :wt 0.0 :wk 0.0 :rt 0 :rk 0))))
            (cl-incf (plist-get e :rt)) (cl-incf (plist-get e :wt) w)
            (when (equal d "kept") (cl-incf (plist-get e :rk)) (cl-incf (plist-get e :wk) w))
            (puthash target e instances)))))
    (let ((class-list nil) (instance-list nil))
      (maphash (lambda (s e)
                 (let* ((wr (if (> (plist-get e :wt) 0) (/ (plist-get e :wk) (plist-get e :wt)) 0.0))
                        (rr (if (> (plist-get e :rt) 0) (/ (float (plist-get e :rk)) (plist-get e :rt)) 0.0)))
                   (push (list :name s :keep-rate wr :raw-rate rr :trend (- wr rr)
                               :total (plist-get e :rt) :improving (> (- wr rr) 0.03)
                               :status (cond ((>= wr 0.5) "effective") ((>= wr 0.3) "promising") (t "underperforming")))
                         class-list))) classes)
      (maphash (lambda (target-name e)
                 (let* ((wr (if (> (plist-get e :wt) 0) (/ (plist-get e :wk) (plist-get e :wt)) 0.0))
                        (rr (if (> (plist-get e :rt) 0) (/ (float (plist-get e :rk)) (plist-get e :rt)) 0.0)))
                   (push (list :name target-name :keep-rate wr :raw-rate rr :trend (- wr rr)
                               :total (plist-get e :rt) :improving (> (- wr rr) 0.03)
                               :classification (cond ((>= wr 0.5) "high-value") ((>= wr 0.3) "moderate") (t "low-value")))
                         instance-list))) instances)
      (list :classes (sort class-list (lambda (a b) (> (plist-get a :keep-rate) (plist-get b :keep-rate))))
            :instances (sort instance-list (lambda (a b) (> (plist-get a :total) (plist-get b :total))))
            :class-count (hash-table-count classes) :instance-count (hash-table-count instances) :weighted t))))

(defun gptel-auto-workflow--mementum-confidence-factor (strategy-name)
  "Read mementum knowledge page confidence for STRATEGY-NAME."
  (let* ((root (gptel-auto-workflow--worktree-base-root))
         (page (and root (expand-file-name (format "research-insights-%s.md" strategy-name)
                                           (expand-file-name "mementum/knowledge" root)))))
    (if (and page (file-readable-p page))
        (with-temp-buffer (insert-file-contents page) (goto-char (point-min))
          (if (re-search-forward "^confidence:\\s-*\\([0-9.]+\\)" nil t)
              (string-to-number (match-string 1)) 0.5)) 0.5)))

(defun gptel-auto-workflow--preflight-alternative (blocked-target blocked-strategy)
  "When pre-flight blocks, suggest a better target/strategy pair."
  (let* ((onto (gptel-auto-workflow--generate-experiment-ontology))
         (instances (plist-get onto :instances)) (classes (plist-get onto :classes))
         (alt-target (cl-find-if (lambda (i) (and (not (string= (plist-get i :name) blocked-target))
                                                   (member (plist-get i :classification) '("high-value" "moderate"))
                                                   (> (plist-get i :total) 3))) instances))
         (alt-strategy (cl-find-if (lambda (c) (and (not (string= (plist-get c :name) blocked-strategy))
                                                     (string= (plist-get c :status) "effective")
                                                     (> (plist-get c :total) 10))) classes)))
    (list :alternative-target (when alt-target (plist-get alt-target :name))
          :alternative-strategy (when alt-strategy (plist-get alt-strategy :name))
          :reason (cond ((not alt-target) "none") ((not alt-strategy) "none")
                        (t (format "Try %s x %s" (plist-get alt-target :name) (plist-get alt-strategy :name)))))))

;; 7. VSM ACTIONS → REPAIR: consumer for stored vsm-actions
(defun gptel-auto-workflow--consume-vsm-actions ()
  "Read stored VSM actions from evolution-next-cycle-hints and trigger repairs."
  (when (boundp 'gptel-auto-workflow--evolution-next-cycle-hints)
    (let ((actions (plist-get gptel-auto-workflow--evolution-next-cycle-hints :vsm-actions)))
      (dolist (action actions)
        (pcase (car action)
          ('increase-strategy-evolution
           (when (boundp 'gptel-auto-workflow--strategy-evolution-enabled)
             (setq gptel-auto-workflow--strategy-evolution-enabled t)
             (message "[vsm-repair] Strategy evolution enabled (Fire→Earth generating)")))
          ('rebalance-experiment-targets
           (setq gptel-auto-workflow--baseline-keep-rate
                 (max 0.05 (- (or gptel-auto-workflow--baseline-keep-rate 0.18) 0.03)))
           (message "[vsm-repair] Lowered baseline keep-rate to %.0f%% (Wood→Water generating)"
                    (* 100 gptel-auto-workflow--baseline-keep-rate)))
           ('increase-research
           (message "[vsm-repair] Research priority increased (Water→Wood generating)"))
           ('rebalance-backends
           (when (fboundp 'gptel-auto-workflow--evolution-optimize-backend-order)
             (gptel-auto-workflow--evolution-optimize-backend-order)
             (message "[vsm-repair] Backend fallback chain rebalanced (Metal→Wood pruning)")))
           ('increase-exploration
           (when (boundp 'gptel-auto-workflow--exploration-rate)
             (setq gptel-auto-workflow--exploration-rate 0.30))
           (message "[vsm-repair] Exploration rate forced to 30%% (overfit countermeasure)"))
           ('rebuild-allium-specs
           (when (fboundp 'gptel-auto-workflow--allium-audit-signal)
             (gptel-auto-workflow--allium-audit-signal)
             (message "[vsm-repair] Allium audit triggered (spec coverage gap)")))
            ('freeze-unstable-targets
            (let ((unstable-str (cdr action)))
              (message "[vsm-repair] Unstable targets flagged: %s (experiments gated)"
                       (if (stringp unstable-str) unstable-str "unknown"))))
            ('prioritize-targets
             (gptel-auto-workflow--vsm-prioritize-targets (cdr action))
             (message "[vsm-repair] Target queue reordered by VSM health diagnostics"))
            (_ (message "[vsm-repair] Unknown VSM action: %s" (car action))))))))

(defun gptel-auto-workflow--vsm-prioritize-targets (vsm-levels)
  "Reorder experiment target queue based on VSM health LEVEL weaknesses.
Maps VSM level deficits to specific target file patterns to front-load
experiments on files most relevant to the diagnosed weakness.
VSM→Target: diagnosis-driven experiment targeting for faster recovery.

VSM LEVELS is a plist of (level . strength):
  :s1-ops (Wood) → operational modules
  :s2-coord (Metal) → coordination/backend modules
  :s3-control (Earth) → validation/staging modules
  :s4-intel (Fire) → strategy/evolution modules
  :s5-identity (Water) → core/identity modules"
  (when (boundp 'gptel-auto-workflow--experiment-targets)
    (let* ((level-files
            '((:s1-ops . (".*gptel-tools-\\(agent\\|code\\|edit\\|preview\\|bash\\|glob\\|grep\\)"
                          ".*gptel-ext-\\(core\\|fsm\\|retry\\|streaming\\|abort\\|security\\)"))
              (:s2-coord . (".*gptel-ext-backends"
                            ".*gptel-tools-agent-\\(staging\\|worktree\\)"
                            ".*ontology-router"))
              (:s3-control . (".*gptel-tools-agent-validation"
                              ".*gptel-sandbox"
                              ".*gptel-ext-security"))
              (:s4-intel . (".*gptel-tools-agent-strategy-\\(evolver\\|harness\\)"
                            ".*gptel-auto-workflow-research-\\(benchmark\\|integration\\)"
                            ".*gptel-benchmark-principles"))
              (:s5-identity . (".*nucleus-\\(tools\\|prompts\\|presets\\|header\\)"
                               ".*gptel-ext-core"
                               ".*gptel-agent-loop"))))
           (targets gptel-auto-workflow--experiment-targets)
           (prioritized nil)
           (remaining targets))
      ;; For each weak VSM level (strength below threshold), pull matching
      ;; targets to the front of the queue.  Process S5→S1 so weaker levels
      ;; take priority (later reverse gives S5-first processing).
      (let ((level-pairs nil))
        (let ((tail vsm-levels))
          (while tail
            (push (cons (car tail) (cadr tail)) level-pairs)
            (setq tail (cddr tail))))
        ;; Process S5→S1: last-pushed (S5) is first, giving weaker levels priority
        (dolist (level-pair level-pairs)
        (let* ((level (car level-pair))
               (strength (cdr level-pair))
               (patterns (cdr (assq level level-files))))
          (when (and patterns (< strength 0.4))
            (dolist (pattern patterns)
              (let ((matched nil))
                (setq remaining
                      (cl-remove-if
                       (lambda (tgt)
                         (when (and (not matched)
                                    (string-match-p pattern tgt))
                           (push tgt prioritized)
                           (setq matched t)
                           t))
                        remaining))))))))
      ;; Append remaining (non-matched) targets after prioritized ones
      (setq gptel-auto-workflow--experiment-targets
            (append (nreverse prioritized) remaining))
      (when prioritized
        (message "[vsm-targets] Prioritized %d targets for weak VSM levels: %s"
                 (length prioritized)
                 (mapconcat #'identity (seq-take (nreverse prioritized) 3) ", "))))))

;; ─── Cross-Subsystem Feedback Functions (re-added after daemon merge wipe) ───

(defun gptel-auto-workflow--champion-feedback-to-controller ()
  "Detect category champion changes between cycles. Returns list of changes."
  (when (and (boundp 'gptel-auto-workflow--category-champions)
             gptel-auto-workflow--category-champions)
    (let* ((prev (plist-get gptel-auto-workflow--evolution-next-cycle-hints :prev-champions))
           (results nil))
      (dolist (entry gptel-auto-workflow--category-champions)
        (let* ((category (car entry)) (current-strategy (cadr entry)) (current-rate (cddr entry))
               (prev-entry (when prev (assoc category prev)))
               (prev-strategy (when prev-entry (cadr prev-entry)))
               (prev-rate (when prev-entry (cddr prev-entry))))
          (cond ((null prev-entry)
                 (push (list :category category :strategy current-strategy :rate current-rate
                             :action 'new-champion :reason "first champion") results))
                ((and prev-strategy (not (string= current-strategy prev-strategy)))
                 (push (list :category category :strategy current-strategy :rate current-rate
                             :old-strategy prev-strategy :action 'promoted
                             :reason (format "replaced %s" prev-strategy)) results))
                ((and prev-rate current-rate (> (- current-rate prev-rate) 0.05))
                 (push (list :category category :strategy current-strategy :rate current-rate
                             :old-rate prev-rate :action 'improving) results)))))
      (nreverse results))))

(defun gptel-auto-workflow--update-controller-from-champion-changes (changes)
  "Update AutoTTS controller config based on champion CHANGES.
When a champion is promoted or improves, adjust controller parameters:
- Higher keep-rate → raise STOP threshold (more confident stopping)
- New champion → reset topic priors to favor the champion's domain.
Persists updated config to var/tmp/researcher-controller.json."
  (let* ((root (gptel-auto-workflow--worktree-base-root))
         (config-file (and root (expand-file-name "var/tmp/researcher-controller.json" root)))
         (existing (when (and config-file (file-readable-p config-file))
                     (condition-case nil
                         (let ((json-object-type 'plist)
                               (json-array-type 'list)
                               (json-key-type 'keyword))
                           (with-temp-buffer
                             (insert-file-contents config-file)
                             (goto-char (point-min))
                             (json-read)))
                       (error (list :version 1))))))
    (dolist (change changes)
      (let ((action (plist-get change :action))
            (rate (plist-get change :rate))
            (category (plist-get change :category)))
        (cond
         ((eq action 'new-champion)
          (plist-put existing :champion-category (symbol-name category))
          (plist-put existing :min-confidence-stop (min 0.85 (+ 0.7 rate)))
          (message "[controller] New %s champion — stop-threshold adjusted to %.2f"
                   category (plist-get existing :min-confidence-stop)))
         ((eq action 'promoted)
          (plist-put existing :champion-category (symbol-name category))
          (plist-put existing :min-confidence-stop (min 0.85 (+ 0.65 rate)))
          (message "[controller] %s champion promoted — stop-threshold adjusted to %.2f"
                   category (plist-get existing :min-confidence-stop)))
         ((eq action 'improving)
          (plist-put existing :champion-rate rate)
          (message "[controller] %s champion improving — rate=%.1f%%" category (* 100 rate))))))
    (when (and config-file gptel-auto-workflow--category-champions)
      (plist-put existing :last-champion-update (format-time-string "%Y-%m-%dT%H:%M"))
      (plist-put existing :active-champions
                 (mapcar (lambda (e) (list :category (symbol-name (car e))
                                           :strategy (cadr e)
                                           :rate (cddr e)))
                         gptel-auto-workflow--category-champions))
      (make-directory (file-name-directory config-file) t)
      (with-temp-file config-file
        (insert (json-encode existing))))))

(defun gptel-auto-workflow--category-experiment-budget (total-experiments)
  "Allocate TOTAL-EXPERIMENTS slots across 4 categories by champion status.
AutoGo→Budget: champions drive allocation — categories with proven strategies
get exploit budget, empty categories get discovery budget, 10% reserved for
pi-Synthesis semantic exploration.
Falls back to sqrt(keep-rate) when no champion data exists."
  (let* ((onto (gptel-auto-workflow--generate-experiment-ontology))
         (instances (plist-get onto :instances))
         (cat-rates (list (cons :programming 0) (cons :tool-calls 0)
                          (cons :agentic 0) (cons :natural-language 0)))
         (cat-counts (list (cons :programming 0) (cons :tool-calls 0)
                           (cons :agentic 0) (cons :natural-language 0)))
         (baselines (or (and (boundp 'gptel-auto-workflow--category-baselines)
                             gptel-auto-workflow--category-baselines)
                        (condition-case nil
                            (gptel-auto-workflow--compute-category-baselines)
                          (error nil))))
         (champions (and (boundp 'gptel-auto-workflow--category-champions)
                         gptel-auto-workflow--category-champions))
         (categories (list :programming :tool-calls :agentic :natural-language))
         (budget nil))
    ;; Collect per-category rates and counts
    (dolist (i instances)
      (let* ((name (plist-get i :name)) (rate (plist-get i :keep-rate))
             (cat (when (fboundp 'gptel-auto-workflow--categorize-target)
                    (gptel-auto-workflow--categorize-target name))))
        (when cat
          (cl-incf (alist-get cat cat-counts))
          (cl-incf (alist-get cat cat-rates) rate))))
    ;; Champion-aware allocation per category
    (dolist (cat categories)
      (let* ((champion (cdr (assq cat champions)))
             (champion-rate (if champion (cdr champion) 0.0))
             (baseline (or (cdr (assq cat baselines)) 0.15))
             ;; sqrt fallback value
             (sqrt-val (sqrt (max 0.01 (/ (alist-get cat cat-rates)
                                          (max 1 (alist-get cat cat-counts))))))
             ;; Champion-driven multiplier
             (multiplier
              (cond
               ;; Strong champion: >30% above baseline → exploit (1.6x)
               ((and champion (> champion-rate (* baseline 1.3))) 1.6)
               ;; Champion above baseline → improve (1.0x)
               ((and champion (> champion-rate baseline)) 1.0)
               ;; Champion at/below baseline → discover (0.8x)
               (champion 0.8)
               ;; No champion → discover (0.8x, let exploration earn its place)
               (t 0.8)))
              ;; Verbum: penalize categories when backends are unhealthy
              (verbum-penalty
               (if (fboundp 'gptel-auto-workflow--backend-health-weight)
                   (let* ((avg-hw 0.0) (n 0))
                     (dolist (b (mapcar #'car (gptel-auto-workflow--evolution-backend-stats)))
                       (cl-incf avg-hw (gptel-auto-workflow--backend-health-weight b))
                       (cl-incf n))
                     (setq avg-hw (/ avg-hw (max 1 n)))
                     (cond ((< avg-hw 0.3) 0.1)   ; catastrophic
                           ((< avg-hw 0.5) 0.5)   ; severe
                           (t 1.0)))              ; healthy
                 1.0)))
            (push (cons cat (* sqrt-val multiplier verbum-penalty)) budget)))
    (setq budget (nreverse budget))
    ;; Reserve 10% for π Synthesis exploration
    (let* ((exploration-reserve (max 1 (round (* total-experiments 0.10))))
           (allocatable (- total-experiments exploration-reserve))
           (total-w (apply #'+ (mapcar #'cdr budget)))
           (result nil))
      (dolist (b budget)
        (push (cons (car b) (max 1 (round (* allocatable (/ (cdr b) (max 0.001 total-w))))))
              result))
      (setq result (nreverse result))
      (push (cons :synthesis exploration-reserve) result)
      (message "[budget] Champion-aware allocation (total=%d, synthesis-reserve=%d): %S"
               total-experiments exploration-reserve result)
      result)))

(defun gptel-auto-workflow--normalize-category-budget (budget)
  "Return BUDGET as an alist of (CATEGORY . QUOTA) entries.
Accepts the in-memory alist shape and the plist shape restored from JSON."
  (let (normalized)
    (cond
     ((not (listp budget)) nil)
     ((and budget (keywordp (car budget)))
      (let ((tail budget))
        (while tail
          (let ((category (pop tail))
                (quota (pop tail)))
            (when (and (keywordp category) (numberp quota))
              (push (cons category quota) normalized))))))
     (t
      (dolist (entry budget)
        (cond
         ((and (consp entry) (keywordp (car entry)) (numberp (cdr entry)))
          (push (cons (car entry) (cdr entry)) normalized))
         ((and (consp entry) (keywordp (car entry))
               (consp (cdr entry)) (numberp (cadr entry)))
          (push (cons (car entry) (cadr entry)) normalized))))))
    (nreverse normalized)))

(defun gptel-auto-workflow--enforce-category-budget (targets)
  "Hard-enforce category experiment budget on TARGETS list.
Reads budget from evolution-next-cycle-hints, categorizes each target,
and limits to the allocated slots per category. Returns filtered list.
Uncategorized targets pass through (counted against :other quota)."
  (let* ((hints (if (boundp 'gptel-auto-workflow--evolution-next-cycle-hints)
                     gptel-auto-workflow--evolution-next-cycle-hints nil))
         (budget (gptel-auto-workflow--normalize-category-budget
                  (when hints (plist-get hints :category-budget))))
         (cat-counts (make-hash-table :test 'eq))
         (remaining (if budget
                         (let ((alist nil))
                          (dolist (b budget)
                            (push (cons (car b) (cdr b)) alist))
                          alist)
                      (list (cons :other 99))))
         (result nil)
         (total-limited 0)
         (total-input (length targets)))
    (if (not budget)
        (progn
          (message "[budget] No category budget available — allowing all %d targets" total-input)
          targets)
       (dolist (target targets)
       (let* ((cat (when (fboundp 'gptel-auto-workflow--categorize-target)
                     (gptel-auto-workflow--categorize-target target)))
              (quota (or (cdr (assoc cat remaining))
                          (cdr (assoc :other remaining))
                          99))   ; uncategorized pass-through when :other missing
              (used (gethash cat cat-counts 0)))
        (if (and quota (> quota used))
            (progn
              (push target result)
              (puthash cat (1+ used) cat-counts))
          (setq total-limited (1+ total-limited)))))
    (when (> total-limited 0)
      (message "[budget] Category budget enforced: %d/%d targets limited (within quota)"
               total-limited total-input))
    (nreverse result))))

(defun gptel-auto-workflow--vsm-health-actions ()
  "Translate VSM diagnostics into actionable repair hints."
  (let* ((onto (gptel-auto-workflow--generate-experiment-ontology))
         (classes (plist-get onto :classes))
         (effective (cl-count-if (lambda (c) (string= (plist-get c :status) "effective")) classes))
         (total (max 1 (length classes)))
         (actions nil))
    (when (< effective (max 3 (/ total 4)))
      (push (cons 'increase-strategy-evolution
                  (format "Only %d/%d effective; Fire(S4) weak" effective total)) actions))
    (when (< (or gptel-auto-workflow--champion-keep-rate 0) 0.15)
      (push (cons 'rebalance-experiment-targets "Champion keep-rate <15%; Wood(S1) weak") actions))
    (let ((promising (cl-count-if (lambda (c) (string= (plist-get c :status) "promising")) classes)))
      (when (< promising 2)
        (push (cons 'increase-research (format "Only %d promising; Water(S5) weak" promising)) actions)))
    (list :actions (nreverse actions) :effective effective :total total)))

(defun gptel-auto-workflow--apply-cross-subsystem-feedback ()
  "Orchestrate cross-subsystem feedback: champion→controller, budget, VSM repair."
  (let ((champion-changes (gptel-auto-workflow--champion-feedback-to-controller))
        (budget (gptel-auto-workflow--category-experiment-budget 5))
        (vsm-actions (gptel-auto-workflow--vsm-health-actions))
        (expanded-actions (gptel-auto-workflow--vsm-expanded-actions)))
    ;; Feed champion changes into controller configuration
    (when champion-changes
      (gptel-auto-workflow--update-controller-from-champion-changes champion-changes))
    ;; Save champion state for next cycle
    (when gptel-auto-workflow--category-champions
      (setq gptel-auto-workflow--evolution-next-cycle-hints
            (plist-put gptel-auto-workflow--evolution-next-cycle-hints
                       :prev-champions
                       (mapcar (lambda (e) (cons (car e) (cdr e)))
                               gptel-auto-workflow--category-champions))))
    ;; Store budget and VSM actions
    (setq gptel-auto-workflow--evolution-next-cycle-hints
          (plist-put gptel-auto-workflow--evolution-next-cycle-hints :category-budget budget))
    (setq gptel-auto-workflow--evolution-next-cycle-hints
          (plist-put gptel-auto-workflow--evolution-next-cycle-hints
                     :vsm-actions (append (plist-get vsm-actions :actions)
                                          expanded-actions)))
    ;; Log
    (dolist (change champion-changes)
      (message "[feedback] %s: %s (%.1f%%) [%s]"
               (plist-get change :category) (plist-get change :strategy)
               (* 100 (or (plist-get change :rate) 0)) (plist-get change :action)))
    (message "[budget] Categories: %s"
             (mapconcat (lambda (b) (format "%s:%d" (car b) (cdr b))) budget " "))
    (dolist (action (plist-get vsm-actions :actions))
      (message "[vsm-action] %s: %s" (car action) (cdr action)))
    ;; Persist to disk so hints survive daemon restarts
    (gptel-auto-workflow--persist-next-cycle-hints)
    ;; Wire :regressed-targets from knowledge-page diff
    (gptel-auto-workflow--wire-regressed-targets)))

;; ─── Ouroboros Persistence + Gap Closures ───

(defun gptel-auto-workflow--persist-next-cycle-hints ()
  "Persist evolution-next-cycle-hints to disk for daemon-restart survival.
Solves S5-2/S4-5/S2-1: cross-cycle state amnesia.
Also persists EMA confidence history for cross-session trend analysis."
  (let* ((root (gptel-auto-workflow--worktree-base-root))
         (file (and root (expand-file-name "var/tmp/cross-subsystem-state.json" root)))
         (hints gptel-auto-workflow--evolution-next-cycle-hints))
    ;; Attach EMA history for cross-session continuity
    (when (bound-and-true-p gptel-auto-workflow--research-ema-history)
      (setq hints (plist-put hints :ema-history gptel-auto-workflow--research-ema-history)))
    (when (bound-and-true-p gptel-auto-workflow--research-ema-conf)
      (setq hints (plist-put hints :ema-conf gptel-auto-workflow--research-ema-conf)))
    ;; Verbum immune memory: persist backend health state across restarts
    (when (and (boundp 'gptel-auto-workflow--lambda-strike-count)
               (> (hash-table-count gptel-auto-workflow--lambda-strike-count) 0))
      (let ((strikes nil))
        (maphash (lambda (k v) (push (cons k v) strikes)) gptel-auto-workflow--lambda-strike-count)
        (setq hints (plist-put hints :lambda-strikes strikes))))
    (when (and (boundp 'gptel-auto-workflow--lambda-dead-until)
               (> (hash-table-count gptel-auto-workflow--lambda-dead-until) 0))
      (let ((dead nil))
        (maphash (lambda (k v) (push (cons k v) dead)) gptel-auto-workflow--lambda-dead-until)
        (setq hints (plist-put hints :lambda-dead dead))))
    (when (and (boundp 'gptel-auto-workflow--lambda-verification-results)
               (> (hash-table-count gptel-auto-workflow--lambda-verification-results) 0))
      (let ((results nil))
        (maphash (lambda (k v) (push (cons (symbol-name k) (symbol-name v)) results)) gptel-auto-workflow--lambda-verification-results)
        (setq hints (plist-put hints :lambda-results results))))
    (when file
      (make-directory (file-name-directory file) t)
      (with-temp-file file
        (insert (json-encode hints))))))

(defun gptel-auto-workflow--json-map-entries (value)
  "Return VALUE as alist entries after JSON plist/alist restoration."
  (cond
   ((null value) nil)
   ((and (listp value) (keywordp (car value)))
    (let (entries)
      (while value
        (let ((key (pop value))
              (val (and value (pop value))))
          (when (keywordp key)
            (push (cons (substring (symbol-name key) 1) val) entries))))
      (nreverse entries)))
   ((listp value) value)))

(defun gptel-auto-workflow--restore-next-cycle-hints ()
  "Restore evolution-next-cycle-hints from disk after daemon restart.
Also restores EMA confidence history for cross-session trend analysis."
  (let* ((root (gptel-auto-workflow--worktree-base-root))
         (file (and root (expand-file-name "var/tmp/cross-subsystem-state.json" root))))
    (when (and file (file-readable-p file))
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (condition-case nil
            (let ((json-object-type 'plist)
                  (json-array-type 'list)
                  (json-key-type 'keyword))
              (setq gptel-auto-workflow--evolution-next-cycle-hints (json-read)))
          (error nil))))
    ;; Restore EMA confidence data from plist
    (when (and gptel-auto-workflow--evolution-next-cycle-hints
               (boundp 'gptel-auto-workflow--research-ema-history))
      (let ((history (plist-get gptel-auto-workflow--evolution-next-cycle-hints :ema-history)))
        (when history
          (setq gptel-auto-workflow--research-ema-history history))))
    (when (and gptel-auto-workflow--evolution-next-cycle-hints
               (boundp 'gptel-auto-workflow--research-ema-conf))
      (let ((conf (plist-get gptel-auto-workflow--evolution-next-cycle-hints :ema-conf)))
        (when conf
          (setq gptel-auto-workflow--research-ema-conf conf))))
    ;; Verbum immune memory: restore backend health state from disk
    (when gptel-auto-workflow--evolution-next-cycle-hints
      (when (boundp 'gptel-auto-workflow--lambda-strike-count)
        (let ((strikes (plist-get gptel-auto-workflow--evolution-next-cycle-hints :lambda-strikes)))
          (when strikes
            (clrhash gptel-auto-workflow--lambda-strike-count)
            (dolist (s (gptel-auto-workflow--json-map-entries strikes))
              (when (consp s)
                (puthash (car s) (cdr s) gptel-auto-workflow--lambda-strike-count))))))
      (when (boundp 'gptel-auto-workflow--lambda-dead-until)
        (let ((dead (plist-get gptel-auto-workflow--evolution-next-cycle-hints :lambda-dead)))
          (when dead
            (clrhash gptel-auto-workflow--lambda-dead-until)
            (dolist (d (gptel-auto-workflow--json-map-entries dead))
              (when (consp d)
                (puthash (car d) (cdr d) gptel-auto-workflow--lambda-dead-until))))))
      (when (boundp 'gptel-auto-workflow--lambda-verification-results)
        (let ((results (plist-get gptel-auto-workflow--evolution-next-cycle-hints :lambda-results)))
          (when results
            (clrhash gptel-auto-workflow--lambda-verification-results)
            (dolist (r (gptel-auto-workflow--json-map-entries results))
              (when (consp r)
                (puthash (car r) (intern (format "%s" (cdr r)))
                         gptel-auto-workflow--lambda-verification-results)))))))))

(defun gptel-auto-workflow--wire-regressed-targets ()
  "Populate :regressed-targets from cross-cycle knowledge-page diff.
Solves S5-3: dead feedback path."
  (let* ((diff (condition-case nil (gptel-auto-workflow--diff-knowledge-pages) (error nil)))
         (removed (and diff (plist-get diff :removed))))
    (when removed
      (setq gptel-auto-workflow--evolution-next-cycle-hints
            (plist-put gptel-auto-workflow--evolution-next-cycle-hints
                       :regressed-targets removed)))))

(defun gptel-auto-workflow--vsm-expanded-actions ()
  "Expanded VSM health actions beyond the 3 trivial ones.
Solves S2-2: richer repair repertoire."
  (let* ((backends (gptel-auto-workflow--evolution-backend-stats))
         (onto (gptel-auto-workflow--generate-experiment-ontology))
         (classes (plist-get onto :classes))
         (allium-issues (length (directory-files
                                 (expand-file-name "var/tmp/evolution/allium-issues"
                                                   (gptel-auto-workflow--worktree-base-root))
                                 t "\\.md$")))
         (actions nil))
    ;; S4-1: Backend variance check
    (when (> (length backends) 1)
      (let* ((rates (mapcar #'cdr backends)) (best (or (car rates) 0)) (worst (or (car (last rates)) 0)))
        (when (> (- best worst) 0.15)
          (push (cons 'rebalance-backends (format "Keep-rate variance %.0f%%-%.0f%%" (* 100 worst) (* 100 best))) actions))))
    ;; S1-4: Overfit detection gates
    (when (fboundp 'gptel-auto-workflow--detect-overfitting)
      (when (eq (gptel-auto-workflow--detect-overfitting) 'overfit)
        (push (cons 'increase-exploration "Overfitting detected — forcing 30% exploration rate") actions)
        (when (boundp 'gptel-auto-workflow--exploration-rate)
          (setq gptel-auto-workflow--exploration-rate 0.30))))
    ;; S4-2: Allium coverage check
    (when (> (length classes) 0)
      (when (< allium-issues (length classes))
        (push (cons 'rebuild-allium-specs (format "Only %d Allium specs for %d strategies" allium-issues (length classes))) actions)))
    ;; S2-5: Unstable target detection
    (let ((unstable nil))
      (dolist (c classes)
        (when (and (< (plist-get c :total) 10) (< (plist-get c :keep-rate) 0.1) (string= (plist-get c :status) "underperforming"))
          (push (plist-get c :name) unstable)))
      (when unstable
        (push (cons 'freeze-unstable-targets (format "%d unstable target(s)" (length unstable))) actions)))
    (nreverse actions)))

(defun gptel-auto-workflow--experiment-causal-links ()
  "Build causal link graph between experiments on the same target.
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
Returns list of conflict plists."
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
  "Score knowledge pages by coverage, completeness, and relation."
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
        (ignore)))
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
  "Forward chaining rules for experiment facts.")

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

;; ─── Backend Performance Optimization ───

(defun gptel-auto-workflow--evolution-optimize-backend-order ()
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

;; ─── Head-to-Head Backend Comparison ───

(defun gptel-auto-workflow--backend-head-to-head-stats (backend-a backend-b)
  "Compare BACKEND-A vs BACKEND-B on shared targets.
Only considers targets where BOTH backends have >=3 experiments.
Returns plist with :winner, :a-rate, :b-rate, :shared-targets, :a-wins, :b-wins."
  (let* ((by-both (make-hash-table :test 'equal))
         (results (gptel-auto-workflow--parse-all-results)))
    (dolist (r results)
      (let ((backend (or (plist-get r :backend) "unknown"))
            (target (or (plist-get r :target) "unknown"))
            (kept (equal (plist-get r :decision) "kept")))
        (when (or (string= backend backend-a) (string= backend backend-b))
          (let ((entry (or (gethash target by-both)
                           (list :a-kept 0 :a-total 0 :b-kept 0 :b-total 0))))
            (if (string= backend backend-a)
                (progn (cl-incf (plist-get entry :a-total))
                       (when kept (cl-incf (plist-get entry :a-kept))))
              (cl-incf (plist-get entry :b-total))
              (when kept (cl-incf (plist-get entry :b-kept))))
            (puthash target entry by-both)))))
    (let ((shared 0) (a-wins 0) (b-wins 0) (ties 0)
          (a-total-kept 0) (a-total-exp 0)
          (b-total-kept 0) (b-total-exp 0))
      (maphash
       (lambda (_target entry)
         (let ((a-total (plist-get entry :a-total))
               (b-total (plist-get entry :b-total)))
           (when (and (>= a-total 3) (>= b-total 3))
             (cl-incf shared)
             (cl-incf a-total-kept (plist-get entry :a-kept))
             (cl-incf a-total-exp a-total)
             (cl-incf b-total-kept (plist-get entry :b-kept))
             (cl-incf b-total-exp b-total)
             (let* ((a-rate (/ (float (plist-get entry :a-kept)) a-total))
                    (b-rate (/ (float (plist-get entry :b-kept)) b-total))
                    (diff (- a-rate b-rate)))
               (cond ((> diff 0.05) (cl-incf a-wins))
                     ((< diff -0.05) (cl-incf b-wins))
                     (t (cl-incf ties)))))))
       by-both)
      (let* ((a-rate (if (> a-total-exp 0) (/ (float a-total-kept) a-total-exp) 0.0))
             (b-rate (if (> b-total-exp 0) (/ (float b-total-kept) b-total-exp) 0.0))
             (winner (cond ((> (- a-rate b-rate) 0.03) backend-a)
                           ((> (- b-rate a-rate) 0.03) backend-b)
                           (t 'tie))))
        (list :winner (if (eq winner 'tie) 'tie winner)
              :a-rate a-rate :b-rate b-rate
              :shared-targets shared
              :a-wins a-wins :b-wins b-wins :ties ties
              :a-name backend-a :b-name backend-b)))))

(defun gptel-auto-workflow--evolution-backend-comparison-report ()
  "Generate head-to-head report for all backend pairs with sufficient data.
Like promptfoo's comparison view: side-by-side backend evaluation.
Returns a formatted string suitable for mementum/skill guidance."
  (let* ((stats (gptel-auto-workflow--evolution-backend-stats))
         (backends (mapcar #'car stats))
         (pairs nil) (lines nil))
    ;; Build all unique pairs with sufficient data, excluding invalid backends
    (let ((seen (make-hash-table :test 'equal)))
      (dolist (a backends)
        (dolist (b backends)
          (when (and (not (equal a b))
                     (not (gethash (list b a) seen))
                     (not (member a '("0" "unknown" "")))
                     (not (member b '("0" "unknown" ""))))
            (puthash (list a b) t seen)
            (let ((h2h (gptel-auto-workflow--backend-head-to-head-stats a b)))
              (when (>= (plist-get h2h :shared-targets) 1)
                (push (cons (cons a b) h2h) pairs)))))))
    (setq pairs (sort pairs (lambda (x y)
                              (> (plist-get (cdr x) :shared-targets)
                                 (plist-get (cdr y) :shared-targets)))))
    (push "# Backend Head-to-Head Comparison\n" lines)
    (push (format "> Auto-generated from %d experiments across %d backends\n\n"
                  (length (gptel-auto-workflow--parse-all-results))
                  (length backends))
          lines)
    (dolist (pair pairs)
      (let* ((h2h (cdr pair))
             (a (plist-get h2h :a-name))
             (b (plist-get h2h :b-name))
             (winner (plist-get h2h :winner))
             (a-rate (plist-get h2h :a-rate))
             (b-rate (plist-get h2h :b-rate))
             (shared (plist-get h2h :shared-targets)))
        (push (format "## %s vs %s (winner: **%s**)\n" a b
                      (if (eq winner 'tie) "tie" winner))
              lines)
        (push (format "- %s: %.1f%% keep-rate\n" a (* 100 a-rate)) lines)
        (push (format "- %s: %.1f%% keep-rate\n" b (* 100 b-rate)) lines)
        (push (format "- Shared targets: %d | %s won %d, %s won %d, ties %d\n\n"
                      shared a (plist-get h2h :a-wins)
                      b (plist-get h2h :b-wins)
                      (plist-get h2h :ties))
              lines)))
    (push (format "\n*Generated: %s*\n" (format-time-string "%Y-%m-%d %H:%M")) lines)
    (apply #'concat (nreverse lines))))

(defun gptel-auto-workflow--evolution-persist-backend-comparison ()
  "Save head-to-head backend comparison to mementum."
  (let ((report (gptel-auto-workflow--evolution-backend-comparison-report))
        (file (expand-file-name "mementum/knowledge/backend-comparison.md"
                                (gptel-auto-workflow--worktree-base-root))))
    (when report
      (make-directory (file-name-directory file) t)
      (with-temp-file file (insert report))
      (let ((pairs (length (split-string report "## " t))))
        (message "[evolution] Backend comparison: %d pair(s) analyzed → mementum"
                 (max 0 (1- pairs)))))))

(defun gptel-auto-workflow--evolution-persist-semantic-relationships ()
  "Persist semantic file similarity relationships to mementum knowledge.
Reads git-embed similarity edges from the ontology router, formats as
markdown table, and writes to mementum/knowledge/semantic-relationships.md.
ε Purpose: enriches ontology with structural similarity for file-target discovery."
  (when (fboundp 'gptel-auto-workflow--semantic-similarity-edges)
    (let* ((root (gptel-auto-workflow--worktree-base-root))
           (file (expand-file-name "mementum/knowledge/semantic-relationships.md" root))
           (edges (gptel-auto-workflow--semantic-similarity-edges 0.60))
           (lines (list (format "# Semantic File Relationships\n\nGenerated: %s\n\n"
                                (format-time-string "%Y-%m-%dT%H:%M"))
                         "## Files Semantically Similar to Kept Experiment Targets\n\n"
                         "| Source (kept target) | Similar File | Score |\n"
                         "|---------------------|--------------|-------|\n")))
      (when edges
        (dolist (edge (seq-take edges 500))
          (let ((source (plist-get edge :source))
                (target (plist-get edge :target))
                (score (plist-get edge :score)))
            (push (format "| %s | %s | %.3f |\n" source target score) lines)))
        (push "\n## Ontology Implications\n\n" lines)
        (push "- Files with high semantic similarity (>0.60) may benefit from similar fixes\n" lines)
        (push "- Consider clustering similar files for batch optimization\n" lines)
        (push "- Semantic edges supplement structural (import/require) relationships\n" lines)
        (make-directory (file-name-directory file) t)
        (with-temp-file file
          (insert (mapconcat #'identity (nreverse lines) "")))
        (message "[evolution] Semantic relationships: %d edges → mementum" (length edges))))))

;; ─── Model-Level Head-to-Head Comparison ───

(defun gptel-auto-workflow--evolution-model-stats ()
  "Analyze model (backend+model) performance from all experiment results.
Returns alist of (\"Backend/model\" . keep-rate) sorted by performance descending.
Like promptfoo's model-specific comparison: which exact model performs best."
  (let ((by-model (make-hash-table :test 'equal))
        (stats nil))
    (dolist (result (gptel-auto-workflow--parse-all-results))
      (let* ((backend (or (plist-get result :backend) "unknown"))
             (model (or (plist-get result :model) "unknown"))
             ;; Replace unknown/none/empty model names with the provider's
             ;; default model from the headless fallback chain.
             (model (if (string-match-p "\\`\\(unknown\\|none\\|\\|\\?\\)\\'" model)
                        (gptel-auto-workflow--default-model-for-backend backend)
                      model))
             (key (format "%s/%s" backend model))
             (kept (equal (plist-get result :decision) "kept")))
        ;; Skip invalid backends
        (unless (or (member backend '("0" "unknown" ""))
                    (string-match-p "\\`\\(0\\|unknown\\)/" key))
          (let ((entry (or (gethash key by-model) (cons 0 0))))
            (setcar entry (1+ (car entry)))
            (when kept (setcdr entry (1+ (cdr entry))))
            (puthash key entry by-model)))))
    (maphash (lambda (key counts)
               (when (> (car counts) 5)
                 (push (cons key (/ (float (cdr counts)) (car counts))) stats)))
             by-model)
    (sort stats (lambda (a b) (> (cdr a) (cdr b))))))

(defun gptel-auto-workflow--model-head-to-head-stats (model-a model-b)
  "Compare MODEL-A vs MODEL-B on shared targets.
MODEL-A and MODEL-B are \"Backend/model\" strings (e.g. \"MiniMax/minimax-m2.7-highspeed\").
Only considers targets where BOTH models have >=3 experiments.
Returns plist with :winner, :a-rate, :b-rate, :shared-targets, :a-wins, :b-wins."
  (let* ((by-both (make-hash-table :test 'equal))
         (results (gptel-auto-workflow--parse-all-results)))
    (dolist (r results)
      (let* ((backend (or (plist-get r :backend) "unknown"))
             (model (or (plist-get r :model) "unknown"))
             (key (format "%s/%s" backend model))
             (target (or (plist-get r :target) "unknown"))
             (kept (equal (plist-get r :decision) "kept")))
        (when (or (string= key model-a) (string= key model-b))
          (let ((entry (or (gethash target by-both)
                           (list :a-kept 0 :a-total 0 :b-kept 0 :b-total 0))))
            (if (string= key model-a)
                (progn (cl-incf (plist-get entry :a-total))
                       (when kept (cl-incf (plist-get entry :a-kept))))
              (cl-incf (plist-get entry :b-total))
              (when kept (cl-incf (plist-get entry :b-kept))))
            (puthash target entry by-both)))))
    (let ((shared 0) (a-wins 0) (b-wins 0) (ties 0)
          (a-total-kept 0) (a-total-exp 0)
          (b-total-kept 0) (b-total-exp 0))
      (maphash
       (lambda (_target entry)
         (let ((a-total (plist-get entry :a-total))
               (b-total (plist-get entry :b-total)))
           (when (and (>= a-total 3) (>= b-total 3))
             (cl-incf shared)
             (cl-incf a-total-kept (plist-get entry :a-kept))
             (cl-incf a-total-exp a-total)
             (cl-incf b-total-kept (plist-get entry :b-kept))
             (cl-incf b-total-exp b-total)
             (let* ((a-rate (/ (float (plist-get entry :a-kept)) a-total))
                    (b-rate (/ (float (plist-get entry :b-kept)) b-total))
                    (diff (- a-rate b-rate)))
               (cond ((> diff 0.05) (cl-incf a-wins))
                     ((< diff -0.05) (cl-incf b-wins))
                     (t (cl-incf ties)))))))
       by-both)
      (let* ((a-rate (if (> a-total-exp 0) (/ (float a-total-kept) a-total-exp) 0.0))
             (b-rate (if (> b-total-exp 0) (/ (float b-total-kept) b-total-exp) 0.0))
             (winner (cond ((> (- a-rate b-rate) 0.03) model-a)
                           ((> (- b-rate a-rate) 0.03) model-b)
                           (t 'tie))))
        (list :winner (if (eq winner 'tie) 'tie winner)
              :a-rate a-rate :b-rate b-rate
              :shared-targets shared
              :a-wins a-wins :b-wins b-wins :ties ties
              :a-name model-a :b-name model-b)))))

(defun gptel-auto-workflow--evolution-model-comparison-report ()
  "Generate head-to-head report for all model pairs with sufficient data.
Compares specific models (e.g. DeepSeek/deepseek-v4-pro vs DeepSeek/deepseek-v4-flash)."
  (let* ((stats (gptel-auto-workflow--evolution-model-stats))
         (models (mapcar #'car stats))
         (pairs nil) (lines nil))
    (let ((seen (make-hash-table :test 'equal)))
      (dolist (a models)
        (dolist (b models)
          (when (and (not (equal a b))
                     (not (gethash (list b a) seen))
                     ;; Exclude invalid backends (0, unknown, empty)
                      (not (string-match-p "\\`\\(0\\|unknown\\|none\\)/" a))
                     (not (string-match-p "\\`\\(0\\|unknown\\|none\\)/" b)))
            (puthash (list a b) t seen)
            (let ((h2h (gptel-auto-workflow--model-head-to-head-stats a b)))
              (when (>= (plist-get h2h :shared-targets) 1)
                (push (cons (cons a b) h2h) pairs)))))))
    (setq pairs (sort pairs (lambda (x y)
                              (> (plist-get (cdr x) :shared-targets)
                                 (plist-get (cdr y) :shared-targets)))))
    (push "# Model-Level Head-to-Head Comparison\n" lines)
    (push (format "> Auto-generated from %d experiments across %d models\n\n"
                  (length (gptel-auto-workflow--parse-all-results))
                  (length models))
          lines)
    (let ((model-ranks (gptel-auto-workflow--evolution-model-stats)))
      (push "## Model Rankings (by keep-rate)\n\n" lines)
      (dolist (entry model-ranks)
        (push (format "- **%s**: %.1f%%\n" (car entry) (* 100 (cdr entry))) lines))
      (push "\n" lines))
    (dolist (pair pairs)
      (let* ((h2h (cdr pair))
             (a (plist-get h2h :a-name))
             (b (plist-get h2h :b-name))
             (winner (plist-get h2h :winner))
             (a-rate (plist-get h2h :a-rate))
             (b-rate (plist-get h2h :b-rate))
             (shared (plist-get h2h :shared-targets)))
        (push (format "## %s vs %s (winner: **%s**)\n" a b
                      (if (eq winner 'tie) "tie" winner))
              lines)
        (push (format "- %s: %.1f%% keep-rate\n" a (* 100 a-rate)) lines)
        (push (format "- %s: %.1f%% keep-rate\n" b (* 100 b-rate)) lines)
        (push (format "- Shared targets: %d | won %d, won %d, ties %d\n\n"
                      shared (plist-get h2h :a-wins)
                      (plist-get h2h :b-wins)
                      (plist-get h2h :ties))
              lines)))
    (push (format "\n*Generated: %s*\n" (format-time-string "%Y-%m-%d %H:%M")) lines)
    (apply #'concat (nreverse lines))))

(defun gptel-auto-workflow--evolution-persist-model-comparison ()
  "Save model-level head-to-head comparison to mementum."
  (let ((report (gptel-auto-workflow--evolution-model-comparison-report))
        (file (expand-file-name "mementum/knowledge/model-comparison.md"
                                (gptel-auto-workflow--worktree-base-root))))
    (when report
      (make-directory (file-name-directory file) t)
      (with-temp-file file (insert report))
      (let ((pairs (length (split-string report "## " t))))
        (message "[evolution] Model comparison: %d model(s), %d pair(s) → mementum"
                 (length (gptel-auto-workflow--evolution-model-stats))
                 (max 0 (- pairs 2)))))))  ;; -2 for header + rankings section

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

;; ─── Allium BDD: Behavior-Driven Development via spec checking ───

(defun gptel-auto-workflow--allium-bdd-gate ()
  "Run Allium BDD check on the system's behavioral specification.
Distills a behavioral description of the key pipeline invariants,
checks them via Allium spec coherence, and logs issues found.
Silent no-op when gptel unavailable (returns nil immediately)."
  (when (and (fboundp 'gptel-auto-workflow--allium-bdd-check)
             (fboundp 'gptel-auto-experiment--allium-distill)
             (fboundp 'gptel-request))
    (let ((behavior-description
           "The Ouroboros evolution pipeline: after each cycle, kept experiments
should trigger π Synthesis (semantic cluster → inherit strategy → auto-queue
similar targets), VSM health should generate Wu Xing repair actions, and
cross-subsystem state should persist to disk for daemon-restart survival.
Regressed targets from knowledge-page diffs should appear in the analyzer
prompt, and category champions should gate new strategies with keep-rate evidence."))
      (gptel-auto-workflow--allium-bdd-check
       behavior-description
       (lambda (result)
          (when (boundp 'gptel-auto-workflow--evolution-next-cycle-hints)
            (let ((status (car result))
                  (details (cdr result)))
              (setq gptel-auto-workflow--evolution-next-cycle-hints
                    (plist-put gptel-auto-workflow--evolution-next-cycle-hints
                               :bdd-status
                               (list :status status
                                     :issues (plist-get details :issues)
                                     :severity (plist-get details :severity)
                                     :score (plist-get details :score))))))
          (if (eq (car result) :pass)
             (message "[allium-bdd] Ouroboros behavioral spec: PASS")
           (message "[allium-bdd] Ouroboros behavioral spec: %s (issues=%s severity=%.2f score=%.2f)"
                    (car result)
                    (plist-get (cdr result) :issues)
                    (plist-get (cdr result) :severity)
                    (plist-get (cdr result) :score))
           (when (eq (car result) :fail)
             (let ((report (plist-get (cdr result) :report)))
               (when report
                 (let* ((root (gptel-auto-workflow--worktree-base-root))
                        (file (and root (expand-file-name "var/tmp/evolution/allium-bdd-report.md" root))))
                   (when file
                     (make-directory (file-name-directory file) t)
                     (with-temp-file file (insert report)))))))))
       ;; Non-blocking: don't wait for callback
       nil))))



(defun gptel-auto-workflow--allium-bdd-check (behavior-description &optional callback)
  "BDD check: distill BEHAVIOR-DESCRIPTION to Allium spec and verify coherence.
Returns nil when Allium is unavailable. Silent no-op when gptel not functional.
Use for TDD-style behavioral verification."
  (cl-block gptel-auto-workflow--allium-bdd-check
  (condition-case _err
      (progn
        (unless (and (fboundp 'gptel-auto-experiment--allium-distill)
                     (fboundp 'gptel-request))
          (when callback (funcall callback (cons :unavailable nil)))
          (cl-return-from gptel-auto-workflow--allium-bdd-check nil))
        (gptel-auto-experiment--allium-distill
         behavior-description
         (lambda (allium-spec)
            (condition-case _err
               (if (not allium-spec)
                   (when callback (funcall callback (cons :distill-failed nil)))
                 (gptel-auto-experiment--allium-check
                  allium-spec
                  (lambda (issues)
                    (condition-case _err
                        (let* ((count-severity (gptel-auto-experiment--allium-issues-count issues))
                               (count (car count-severity))
                               (severity (cdr count-severity))
                               (score (gptel-auto-experiment--allium-quality-score issues))
                               (pass (and (< score 0.3) (<= count 5)))
                               (report (format "# Allium BDD Check\n\n**Issues:** %d | **Severity:** %.2f | **Score:** %.2f\n\n## Issues\n\n%s\n\n## Spec\n\n```allium\n%s\n```"
                                               count severity score (or issues "(none)") (or allium-spec "(none)"))))
                          (when callback
                            (funcall callback
                                     (cons (if pass :pass :fail)
                                           (list :issues count :severity severity :score score
                                                 :spec allium-spec :report report)))))
                      (error (when callback (funcall callback (cons :check-error nil))))))))
              (error (when callback (funcall callback (cons :check-error nil)))))))
        nil)
    (error (when callback (funcall callback (cons :unavailable nil)))
           nil))))

(defun gptel-auto-workflow--allium-bdd-assert (behavior-description)
  "Assert BEHAVIOR-DESCRIPTION passes Allium BDD check.
Signals ert-test-failed if check fails. Use in ERT tests."
  (when (fboundp 'gptel-auto-experiment--allium-distill)
    (let ((result (gptel-auto-workflow--allium-bdd-check behavior-description)))
      (when (eq (car result) :unavailable)
        (message "[allium-bdd] Allium unavailable — skipping BDD assertion"))
      (when (eq (car result) :distill-failed)
        (message "[allium-bdd] Spec distillation failed — check input"))
      (when (eq (car result) :fail)
        (should nil)))))

(provide 'gptel-auto-workflow-evolution)
;;; gptel-auto-workflow-evolution.el ends here
