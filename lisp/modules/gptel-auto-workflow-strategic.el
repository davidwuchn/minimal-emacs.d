;;; gptel-auto-workflow-strategic.el --- Strategic target selection for auto-workflow -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Commentary:
;; LLM-first target selection for auto-workflow.
;; Let the analyzer decide which files to optimize.
;;
;; PURPOSE (ε):
;;   Goal: Automate intelligent selection of optimization targets
;;   Measurable outcome: Select 3 highest-impact files per run
;;   Success metric: Files selected have TODOs/FIXMEs or recent activity
;;
;; WISDOM (τ):
;;   Planning: Gather git history, file sizes, and known issues before selection
;;   Error prevention: Fallback to static targets if LLM unavailable
;;   Foresight: Exclude test files and disabled modules from selection
;;
;; ASSUMPTIONS:
;;   - Project root contains lisp/modules/ directory
;;   - Git is available for history analysis
;;   - LLM subagent (analyzer) may or may not be available
;;
;; EDGE CASES:
;;   - No LLM available → fallback to static target list
;;   - JSON parse fails → regex fallback for file extraction
;;   - Empty target list → use gptel-auto-workflow-targets

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'gptel-tools-agent)
(require 'gptel-benchmark-subagent nil t)

(declare-function gptel-auto-workflow--evolution-get-knowledge "gptel-auto-workflow-evolution" ())
(declare-function gptel-auto-workflow--filter-frontier-saturated-targets "gptel-tools-agent-prompt-build" (targets))
(declare-function gptel-auto-experiment--quota-exhausted-p "gptel-tools-agent-error" (agent-output))
(declare-function gptel-auto-experiment--is-retryable-error-p "gptel-tools-agent-error" (response))
(declare-function gptel-auto-workflow--project-root "gptel-tools-agent-benchmark" ())

(defcustom gptel-auto-workflow-strategic-selection t
  "When non-nil, use LLM-based target selection.
When nil, use static targets from gptel-auto-workflow-targets.
Monthly subscription: LLM selection finds best targets each run."
  :type 'boolean
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-max-targets-per-run 5
  "Maximum targets to optimize per workflow run.
Monthly subscription: 5 is optimal (diminishing returns after 3-4)."
  :type 'integer
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-headless-target-denylist
  '("lisp/modules/gptel-tools-bash.el"
    "lisp/modules/gptel-tools-code.el"
    "lisp/modules/gptel-tools-edit.el"
    "lisp/modules/gptel-tools-glob.el"
    "lisp/modules/gptel-tools-grep.el")
  "Targets to skip during headless workflow runs.
These modules define tools the executor actively depends on. Loading optimize
worktree edits for them into the live daemon can destabilize the run before the
worker restores the original file."
  :type '(repeat string)
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-research-targets nil
  "When non-nil, researcher finds patterns/issues before target selection.
Adds ~30-60s latency but may improve target quality.
Researcher looks for: anti-patterns, architectural issues, code smells.
Default nil for speed (analyzer has enough context from git/history)."
  :type 'boolean
  :group 'gptel-tools-agent)

(defvar gptel-auto-workflow--current-research-context nil
  "Plist tracking current research run context.
Set when research runs before target selection.
Contains :strategy :hash :findings for mementum tracking.
Reset after each run.")

(defcustom gptel-auto-workflow-research-interval (* 4 3600)
  "Interval in seconds between periodic researcher runs.
Default 4 hours. Set to 0 to disable periodic research.
Findings stored in var/tmp/research-findings.md for analyzer."
  :type 'integer
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-max-research-turns 3
  "Maximum turns for multi-turn research with real-time controller.
Each turn is a separate subagent call with controller checkpoint.
Higher values allow deeper research but cost more tokens.
AutoTTS: Controller stops early if confidence threshold met."
  :type 'integer
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-analyzer-time-budget 120
  "Minimum timeout in seconds for analyzer target selection.
Target selection can require more context synthesis than the default subagent
timeout, so keep a dedicated budget to avoid unnecessary static fallbacks."
  :type 'integer
  :group 'gptel-tools-agent)

(defvar gptel-auto-workflow--research-timer nil
  "Timer for periodic researcher runs.")

(defvar gptel-auto-workflow--research-findings-cache (make-hash-table :test 'equal)
  "Hash table mapping project roots to cached research findings.")

(defvar gptel-auto-workflow--research-in-progress nil
  "Non-nil when a research call is currently in flight.
Prevents concurrent research-patterns calls from interleaving.")

(defvar gptel-auto-workflow--context-cache nil
  "Cached context for analyzer prompt, keyed by project root.
Cached value: plist with :context :timestamp keys.
Cache is invalidated after 5 minutes to avoid stale data.")

(defvar gptel-auto-workflow--analyzer-transient-failure nil
  "Non-nil when analyzer target selection failed due to a transient provider issue.")

(defvar gptel-auto-workflow--analyzer-quota-exhausted nil
  "Non-nil when analyzer target selection hit provider quota limits.")

(defun gptel-auto-workflow--clear-analyzer-error-state ()
  "Reset analyzer target-selection error flags before a fresh attempt."
  (setq gptel-auto-workflow--analyzer-transient-failure nil
        gptel-auto-workflow--analyzer-quota-exhausted nil))

(defun gptel-auto-workflow--analyzer-failover-candidate ()
  "Return the next analyzer failover provider candidate, if any."
  (when (and (fboundp 'gptel-auto-workflow--rate-limit-failover-candidates)
             (fboundp 'gptel-auto-workflow--first-available-provider-candidate)
             (boundp 'gptel-auto-workflow--rate-limited-backends))
    (let ((candidates
           (gptel-auto-workflow--rate-limit-failover-candidates "analyzer")))
      (and (listp candidates)
           (gptel-auto-workflow--first-available-provider-candidate
            candidates
            gptel-auto-workflow--rate-limited-backends)))))

(defun gptel-auto-workflow--normalized-cache-key (&optional proj-root)
  "Return normalized cache key for PROJ-ROOT.
Ensures consistent cache lookups across different path representations."
  (let ((root (or proj-root
                  (gptel-auto-workflow--project-root)
                  (expand-file-name "~/.emacs.d/"))))
    (directory-file-name (file-name-directory root))))


(defun gptel-auto-workflow--effective-project-root ()
  "Return the effective project root for workflow operations.
Uses `gptel-auto-workflow--project-root' if available, otherwise
falls back to the user's Emacs configuration directory."
  (or (gptel-auto-workflow--project-root)
      (expand-file-name "~/.emacs.d/")))

(defun gptel-auto-workflow--skip-headless-target-p (rel-path)
  "Return non-nil when REL-PATH should be skipped for a headless run."
  (and (stringp rel-path)
       (or gptel-auto-workflow--headless
           gptel-auto-workflow--cron-job-running
           gptel-auto-workflow-persistent-headless)
       (member rel-path gptel-auto-workflow-headless-target-denylist)))

(defun gptel-auto-workflow--discover-targets ()
  "Discover all Elisp files in lisp/modules/ as potential targets."
  (let* ((proj-root (gptel-auto-workflow--effective-project-root))
         (modules-dir (expand-file-name "lisp/modules" proj-root))
         (targets '()))
    (when (file-directory-p modules-dir)
      (dolist (file (directory-files-recursively modules-dir "\\.el$"))
        (let ((rel-path (file-relative-name file proj-root)))
          (unless (or (string-match-p "-test\\.el$" file)
                      (string-match-p "-disabled\\.el$" file)
                      (string-match-p "/test/" file))
            (push rel-path targets)))))
    (reverse targets)))

(defun gptel-auto-workflow--filter-large-files (files max-lines)
  "Filter FILES to exclude those with more than MAX-LINES lines.
Returns list of file paths under the limit.
BEHAVIOR: Uses wc -l for efficient line counting without loading files into buffer."
  (unless (and (integerp max-lines) (> max-lines 0))
    (setq max-lines most-positive-fixnum))
  (let (result)
    (dolist (file files (reverse result))
      (when (and (file-exists-p file)
                 (let ((line-count (if (executable-find "wc")
                                       (with-temp-buffer
                                         (call-process "wc" nil t nil "-l" file)
                                         (string-to-number (string-trim (buffer-string))))
                                     (with-temp-buffer
                                       (insert-file-contents file)
                                       (count-lines (point-min) (point-max))))))
                   (<= line-count max-lines)))
        (push file result)))))

(defun gptel-auto-workflow--target-in-root-repo-p (abs-path proj-root)
  "Return non-nil when ABS-PATH belongs to the same git repo as PROJ-ROOT."
  (when (and (stringp abs-path) (stringp proj-root) (not (string-empty-p abs-path)))
    (let ((project-git-root (locate-dominating-file proj-root ".git"))
          (target-git-root (locate-dominating-file
                            (file-name-directory (directory-file-name abs-path))
                            ".git")))
      (and project-git-root
           target-git-root
           (file-equal-p (expand-file-name project-git-root)
                         (expand-file-name target-git-root))))))

(defun gptel-auto-workflow--gather-context ()
  "Gather context for LLM target selection.
Scans only root-repo targets that can be integrated into staging.
Uses caching to avoid redundant shell command execution.
EDGE CASE: Only caches context when shell commands produce non-empty output."
  (let* ((proj-root (gptel-auto-workflow--effective-project-root))
         (cache-ttl (* 5 60))
         (now (float-time))
         (cache-entry (and (listp gptel-auto-workflow--context-cache)
                           (eq (car gptel-auto-workflow--context-cache) proj-root)
                           (listp (cdr gptel-auto-workflow--context-cache))
                           (cdr gptel-auto-workflow--context-cache)))
         (cached-context (and cache-entry
                              (plist-member cache-entry :context)
                              (plist-get cache-entry :context)))
         (cache-time (and cache-entry
                          (plist-member cache-entry :timestamp)
                          (plist-get cache-entry :timestamp)))
         (cache-valid (and cached-context cache-time
                           (< (- now cache-time) cache-ttl))))
    (if cache-valid
        (progn
          (message "[auto-workflow] Using cached context for %s" proj-root)
          cached-context)
      (let* ((safe-root (shell-quote-argument proj-root))
             (git-history (shell-command-to-string
                           (format "cd %s && git log --oneline -30 -- lisp/modules/ 2>/dev/null"
                                   safe-root)))
             (file-list-shell (shell-command-to-string
                               (format "cd %s && find lisp/modules -name '*.el' -type f 2>/dev/null"
                                       safe-root))))
        (if (and (stringp git-history) (stringp file-list-shell)
                 (not (string-empty-p git-history))
                 (not (string-empty-p file-list-shell)))
            (let* ((context (list :git-history git-history
                                  :file-sizes (shell-command-to-string
                                               (format "cd %s && find lisp/modules -name '*.el' -type f -exec wc -l {} + 2>/dev/null | sort -rn | head -20"
                                                       safe-root))
                                  :todos (shell-command-to-string
                                          (format "cd %s && grep -rn 'TODO\\|FIXME\\|BUG\\|HACK' lisp/modules/ 2>/dev/null | head -30"
                                                  safe-root))
                                  :file-list (let* ((all-files (delq nil
                                                                     (mapcar (lambda (s)
                                                                               (unless (string-empty-p s) s))
                                                                             (split-string file-list-shell "\n" t))))
                                                    (nonempty-files (delq nil
                                                                          (mapcar (lambda (f)
                                                                                    (let ((abs-path (expand-file-name f proj-root)))
                                                                                      (when (file-exists-p abs-path) f)))
                                                                                  all-files))))
                                               (mapconcat #'identity
                                                          (gptel-auto-workflow--filter-large-files
                                                           nonempty-files 1000)
                                                          "\n")))))
              (setq gptel-auto-workflow--context-cache (cons proj-root (list :context context :timestamp now)))
              (message "[auto-workflow] Cached new context for %s" proj-root)
              context)
          (progn
            (message "[auto-workflow] Context gathering failed: shell commands returned empty; using empty context")
            (list :git-history "" :file-sizes "" :todos "" :file-list "")))))))

(defun gptel-auto-workflow--local-research-patterns ()
  "Perform local grep-based pattern analysis when subagents unavailable.
Returns a string with findings about common code issues.
ASSUMPTION: Project root has lisp/modules/ directory with git history.
BEHAVIOR: Scans for dangerous patterns (cl-return-from, ignore-errors, etc.)
EDGE CASE: Returns empty string if no patterns found or git unavailable."
  (let ((proj-root (gptel-auto-workflow--effective-project-root))
        (patterns '(("cl-return-from" . "Potential missing cl-block wrapper")
                    ("ignore-errors" . "Swallows errors silently")
                    ("set-buffer" . "May affect global buffer state")
                    ("goto-char" . "May move cursor unexpectedly")))
        (results '()))
    (dolist (pattern patterns)
      (let* ((grep-cmd (format "cd %s && git grep -n '%s' -- lisp/modules/ 2>/dev/null | head -5"
                               (shell-quote-argument proj-root)
                               (car pattern)))
             (output (shell-command-to-string grep-cmd)))
        (when (and output (not (string-empty-p (string-trim output))))
          (push (format "Pattern: %s (%s)\n%s"
                        (car pattern) (cdr pattern)
                        (string-trim-right output))
                results))))
    (if results
        (mapconcat #'identity (nreverse results) "\n\n")
      "")))

(defun gptel-auto-workflow--load-research-skill ()
  "Load evolved research skill from FINDINGS.md.
Returns skill content or empty string if not found.
Uses standard skill loader for consistency."
  (let ((content (gptel-auto-workflow--load-skill-content "auto-workflow/FINDINGS")))
    (if (or (null content) (string-empty-p content))
        ""
      (progn
        (message "[research] Loaded evolved skill (%d chars)" (length content))
        content))))

(defun gptel-auto-workflow--load-directive-skill ()
  "Load evolved directive skill from DIRECTIVE.md.
Returns skill content or empty string if not found.
Uses standard skill loader for consistency."
  (let ((content (gptel-auto-workflow--load-skill-content "auto-workflow/DIRECTIVE")))
    (if (or (null content) (string-empty-p content))
        ""
      (progn
        (message "[directive] Loaded evolved skill (%d chars)" (length content))
        content))))

(defun gptel-auto-workflow--research-topics-string ()
  "Return current research topics based on project focus and recent experiments.

Topics evolve based on:
- Recent experiment failures (what we need help with)
- Directive hypotheses (what we're investigating)
- Current active targets (what modules need improvement)

Returns formatted string for research prompt."
  (let* ((topics '("AI agent workflow architectures (multi-step, state machines, planning)"
                   "Emacs Lisp AI integration patterns (gptel, comint, async processes)"
                   "LLM self-evolution and meta-learning (auto-prompting, strategy search)"
                   "Code analysis automation (static analysis, AST parsing, linting)"
                   "Prompt engineering for code generation (chain-of-thought, few-shot)"
                   "Error recovery and retry patterns in agent systems"
                   "Benchmarking and evaluation frameworks for AI-generated code"
                   "Git-based memory and knowledge systems for AI agents"
                   "hermes-agent project: agent orchestration and delegation patterns"
                   "zeroclaw project: lightweight agent framework design"
                   "ml-intern project: ML-powered coding assistant techniques"))
         (proj-root (gptel-auto-workflow--effective-project-root))
         ;; Check recent experiment failures for hints
         (failure-patterns
          (condition-case nil
              (with-temp-buffer
                (call-process "git" nil t nil "log" "--grep=validation-failed\\|timeout\\|error" "--oneline" "-10" "--" "assistant/strategies/" "lisp/modules/")
                (let ((lines (split-string (buffer-string) "\n" t)))
                  (when (> (length lines) 3)
                    (format "\nRecent failure patterns: %d validation/timeout errors in last 10 commits"
                            (length lines)))))
            (error nil))))
    (concat (mapconcat (lambda (topic) (concat "- " topic)) topics "\n")
            (or failure-patterns ""))))

(defun gptel-auto-workflow--load-researcher-skill ()
  "Load researcher skill from researcher-prompt.
Returns skill content or empty string if not found.
Uses standard skill loader so humans can edit researcher-prompt/SKILL.md."
  (let ((content (gptel-auto-workflow--load-skill-content "researcher-prompt")))
    (if (or (null content) (string-empty-p content))
        (progn
          (message "[research] RESEARCHER.md skill not found, using default")
          "")
      (progn
        (message "[research] Loaded researcher skill (%d chars)" (length content))
        content))))

(defun gptel-auto-workflow--load-researcher-meta-learning ()
  "Load meta-learning data for researcher skill.
Reads topic-performance.json and returns formatted stats.
Returns nil if data not available."
  (let* ((data-dir (expand-file-name "assistant/skills/researcher-prompt/data" 
                                     (gptel-auto-workflow--effective-project-root)))
         (topic-file (expand-file-name "topic-performance.json" data-dir)))
    (when (file-exists-p topic-file)
      (condition-case err
          (let* ((json-object-type 'hash-table)
                 (json-array-type 'list)
                 (data (json-read-file topic-file))
                 (topics (gethash "topics" data)))
            (when (and topics (hash-table-p topics))
              (let ((total-exp (gethash "total_experiments" data 0))
                    (total-kept 0))
                ;; Calculate total kept across all topics
                (maphash (lambda (topic stats)
                           (setq total-kept (+ total-kept (gethash "kept" stats 0))))
                         topics)
                (list :effectiveness (if (> total-exp 0)
                                         (round (/ (* 100.0 total-kept) total-exp))
                                       0)
                      :kept total-kept
                      :total total-exp
                      :topics topics))))
        (error 
         (message "[research] Error loading meta-learning data: %s" err)
         nil)))))

(defun gptel-auto-workflow--substitute-researcher-variables (skill-content)
  "Substitute template variables in SKILL-CONTENT with meta-learning data.
Replaces {{research-effectiveness}}, {{kept-research}}, {{total-research}},
and {{topic-performance}} with live data."
  (if (null skill-content)
      skill-content
    (let* ((meta-data (gptel-auto-workflow--load-researcher-meta-learning))
           (effectiveness (or (plist-get meta-data :effectiveness) 16))
           (kept (or (plist-get meta-data :kept) 0))
           (total (or (plist-get meta-data :total) 870))
           (topics (plist-get meta-data :topics)))
      ;; Replace variables
      (setq skill-content 
            (replace-regexp-in-string 
             "{{research-effectiveness}}" 
             (number-to-string effectiveness)
             skill-content t t))
      (setq skill-content 
            (replace-regexp-in-string 
             "{{kept-research}}" 
             (number-to-string kept)
             skill-content t t))
      (setq skill-content 
            (replace-regexp-in-string 
             "{{total-research}}" 
             (number-to-string total)
             skill-content t t))
      ;; Replace topic-performance with formatted table
      (if topics
          (let ((topic-md (gptel-auto-workflow--format-topic-performance topics)))
            (setq skill-content 
                  (replace-regexp-in-string 
                   "{{topic-performance}}" topic-md
                   skill-content t t)))
        (setq skill-content 
              (replace-regexp-in-string 
               "{{topic-performance}}" 
               "*No topic data available yet.*"
               skill-content t t)))
      skill-content)))

(defun gptel-auto-workflow--format-topic-performance (topics)
  "Format TOPICS hash-table as markdown table.
Returns placeholder message if TOPICS is nil or empty."
  (if (or (null topics)
          (not (hash-table-p topics))
          (zerop (hash-table-count topics)))
      "*No topic performance data available.*"
    (let ((topic-list nil))
      ;; Convert hash table to list for sorting
      (maphash (lambda (topic stats)
                 (let ((success-rate (gethash "success_rate" stats 0))
                       (total (gethash "total_experiments" stats 0))
                       (kept (gethash "kept" stats 0))
                       (trend (gethash "trend" stats "stable")))
                   (push (list topic success-rate total kept trend) topic-list)))
               topics)
      ;; Sort by success rate descending
      (setq topic-list (sort topic-list (lambda (a b) (> (nth 1 a) (nth 1 b)))))
      ;; Format as markdown
      (concat "| Topic | Success Rate | Kept/Total | Trend |\n"
              "|-------|--------------|------------|-------|\n"
              (mapconcat 
               (lambda (item)
                 (let ((topic (nth 0 item))
                       (rate (nth 1 item))
                       (total (nth 2 item))
                       (kept (nth 3 item))
                       (trend (nth 4 item)))
                   (format "| %s | %.0f%% | %d/%d | %s |"
                           topic (* 100 rate) kept total trend)))
               (seq-take topic-list 10)
               "\n")))))

(defun gptel-auto-workflow--build-research-prompt ()
  "Build external research prompt by loading RESEARCHER.md skill.

The researcher prompt is defined in assistant/skills/researcher-prompt/SKILL.md
so humans can easily review and edit it without touching code.

Meta-learning data (topic performance, source effectiveness) is dynamically
substituted into the template before building the prompt.

Results feed into directive's 'Next Hypotheses' for target selection."
  (let* ((raw-skill (gptel-auto-workflow--load-researcher-skill))
         (base-prompt (gptel-auto-workflow--substitute-researcher-variables raw-skill))
         (skill-content (gptel-auto-workflow--load-research-skill))
         (directive-content (gptel-auto-workflow--load-directive-skill))
         (priority-targets (gptel-auto-workflow--directive-extract-priority-targets directive-content))
         ;; Load AutoTTS-style strategy guidance from replay store
         (strategy-guidance (gptel-auto-workflow--load-strategy-guidance)))
    (concat (or base-prompt "")
            "\n\n"
            "## Dynamic Context\n\n"
            (if (string-empty-p skill-content)
                ""
              (concat "### Previously Discovered Insights\n"
                      "*Avoid re-reporting these. Build upon or contradict them.*\n\n"
                      skill-content
                      "\n\n"))
            (if priority-targets
                (concat "### Current Project Targets (from directive)\n"
                        "*Research ideas that could improve these specific modules:*\n"
                        priority-targets
                        "\n\n")
              "")
            (if strategy-guidance
                (concat "### Strategy Performance (AutoTTS Replay Store)\n"
                        strategy-guidance
                        "\n\n")
              "")
            "### Recent Failure Patterns\n"
            (gptel-auto-workflow--research-topics-string)
            "Remember: Be specific. 'Use AI better' is banned. Focus on techniques we can implement in Emacs Lisp.")))

;;; Meta-Learning Researcher Triggers

(defun gptel-auto-workflow--trigger-researcher-meta-learning (trigger-type)
  "Trigger researcher skill evolution based on TRIGGER-TYPE.

TRIGGER-TYPE can be:
- `pre-research' — Lightweight cache read before research cycle
- `post-batch' — Full analysis after N experiments complete
- `threshold' — Emergency re-analysis when keep rate drops
- `memory' — Incremental update when new research memory created

Returns t if evolution was triggered, nil otherwise."
  (let* ((root (gptel-auto-workflow--effective-project-root))
         (script-dir (expand-file-name "assistant/skills/researcher-prompt/scripts" root))
         (data-dir (expand-file-name "assistant/skills/researcher-prompt/data" root))
         (skill-file (expand-file-name "assistant/skills/researcher-prompt/SKILL.md" root))
         (triggered nil))
    (cl-case trigger-type
      (pre-research
       ;; Lightweight: just ensure cache exists, substitute variables
       (message "[meta-learn] Pre-research: Loading topic performance cache")
       (gptel-auto-workflow--load-researcher-meta-learning)
       (setq triggered t))
      
      (post-batch
       ;; Full analysis: run Python scripts
       (message "[meta-learn] Post-batch: Running full research outcome analysis")
       (let ((analyze-script (expand-file-name "analyze_research_outcomes.py" script-dir))
             (evolve-script (expand-file-name "evolve_researcher.py" script-dir)))
         (when (and (file-exists-p analyze-script) (file-exists-p evolve-script))
           ;; Run analysis
           (let ((analyze-cmd (format "cd %s && python3 %s --experiments-dir var/tmp/experiments --memories-dir mementum/memories --output-dir %s --lookback-days 90"
                                      root analyze-script data-dir)))
             (message "[meta-learn] Running: %s" analyze-cmd)
             (let ((output (shell-command-to-string analyze-cmd)))
               (message "[meta-learn] Analysis output: %s" output)))
           ;; Evolve skill
           (let ((evolve-cmd (format "cd %s && python3 %s --data-dir %s --skill %s"
                                     root evolve-script data-dir skill-file)))
             (message "[meta-learn] Running: %s" evolve-cmd)
             (let ((output (shell-command-to-string evolve-cmd)))
               (message "[meta-learn] Evolution output: %s" output)))
           (setq triggered t))))
      
      (threshold
       ;; Emergency: check if keep rate below threshold
       (let* ((meta-data (gptel-auto-workflow--load-researcher-meta-learning))
              (effectiveness (or (plist-get meta-data :effectiveness) 100)))
         (when (< effectiveness 14)
           (message "[meta-learn] Threshold alert: keep rate %d%% < 14%%, triggering emergency re-analysis"
                    effectiveness)
           (gptel-auto-workflow--trigger-researcher-meta-learning 'post-batch)
           (setq triggered t))))
      
      (memory
       ;; Incremental: just update source effectiveness
       (message "[meta-learn] Memory ingestion: Incremental update")
       ;; For now, just reload cache. In future, could append to JSON directly.
       (gptel-auto-workflow--load-researcher-meta-learning)
       (setq triggered t)))
    
    triggered))

(defun gptel-auto-workflow--maybe-trigger-researcher-evolution ()
  "Check if researcher evolution should be triggered.
Called periodically by the auto-workflow loop.
Returns t if triggered."
  (let* ((meta-data (gptel-auto-workflow--load-researcher-meta-learning))
         (effectiveness (or (plist-get meta-data :effectiveness) 100))
         (total (or (plist-get meta-data :total) 0))
         ;; Trigger every 50 experiments or when keep rate drops
         (should-trigger (or (< effectiveness 14)
                             (and (> total 0) (zerop (mod total 50))))))
    (when should-trigger
      (if (< effectiveness 14)
          (gptel-auto-workflow--trigger-researcher-meta-learning 'threshold)
        (gptel-auto-workflow--trigger-researcher-meta-learning 'post-batch)))
    should-trigger))

(defun gptel-auto-workflow--directive-extract-priority-targets (directive-content)
  "Extract high-priority targets from DIRECTIVE-CONTENT.
Returns formatted string or nil."
  (when (and directive-content (not (string-empty-p directive-content)))
    (with-temp-buffer
      (insert directive-content)
      (goto-char (point-min))
      (let ((targets nil))
        ;; Look for Active Targets table
        (when (re-search-forward "## Active Targets" nil t)
          (forward-line 2) ; Skip header
          (forward-line 1) ; Skip separator
          (while (looking-at "| `\\([^`]+\\)` | [^|]+ | [^|]+ | [^|]+ | \\(✅\\|🟡\\)")
            (push (match-string 1) targets)
            (forward-line 1)))
        (if targets
            (mapconcat (lambda (targ) (format "- %s" targ)) (nreverse targets) "\n")
          nil)))))

(defun gptel-auto-workflow--research-git-patterns-from-history ()
  "Extract effective code patterns from git history and mementum.
Returns string of grep patterns or nil."
  (condition-case err
      (let* ((root (gptel-auto-workflow--effective-project-root))
             (knowledge-dir (expand-file-name "mementum/knowledge" root))
             (patterns nil))
        ;; Look for successful patterns in research knowledge
        (when (file-directory-p knowledge-dir)
          (dolist (kf (directory-files knowledge-dir t "research-insights-.+\\.md$"))
            (with-temp-buffer
              (insert-file-contents kf)
              (goto-char (point-min))
              ;; Extract successful targets to infer patterns
              (when (re-search-forward "## Successful Targets" nil t)
                (forward-line 2)
                (while (looking-at "^- `\\(.+\\)`")
                  (let ((target (match-string 1)))
                    ;; Infer pattern from target filename
                    (when (string-match "\\(cache\\|sanitize\\|error\\|validate\\|guard\\)" target)
                      (push (format "git grep -n '%s' -- lisp/modules/ | head -10"
                                    (match-string 1 target))
                            patterns)))
                  (forward-line 1))))))
        (if patterns
            (concat "Suggested grep commands based on successful targets:\n"
                    (mapconcat #'identity (delete-dups patterns) "\n"))
          nil))
    (error
     (message "[research] Error extracting git patterns: %s" err)
     nil)))

(defun gptel-auto-workflow--digest-research-findings (raw-findings callback)
  "Digest RAW-FINDINGS if needed.  Preserves external content, only digests unstructured data.
CALLBACK receives findings string.

Heuristic: if raw findings contain URLs or structured techniques, they are already
usable and digestion would lose 80%+ of the content.  Only digest raw HTML dumps."
  (cond
   ;; Empty: nothing to do
   ((or (null raw-findings) (string-empty-p raw-findings))
    (funcall callback ""))
    ;; Already structured external research: pass through to avoid destruction
    ((and (> (length raw-findings) 300)
          (or (> (length raw-findings) 500)  ; Medium+ = likely structured research
              (string-match-p "https?://" raw-findings)
              (string-match-p "## .*Technique\|Source type:\|Impact:\|Application:" raw-findings)
              (string-match-p "\b\(GitHub\|arXiv\|YouTube\|Reddit\|HuggingFace\|X/Twitter\)\b" raw-findings)))
     (message "[auto-workflow] External research already structured (%d chars), skipping digestion"
              (length raw-findings))
     (funcall callback raw-findings))
   ;; Local/internal patterns: pass through (already formatted by local-research-patterns)
   ((and (> (length raw-findings) 100)
         (string-match-p "Pattern:" raw-findings))
    (message "[auto-workflow] Internal patterns already formatted (%d chars), skipping digestion"
             (length raw-findings))
    (funcall callback raw-findings))
   ;; Everything else: try to digest (raw HTML, unstructured text, etc.)
   (t
    (let* ((template (when (fboundp 'gptel-auto-workflow--load-skill-content)
                       (gptel-auto-workflow--load-skill-content "research-digest")))
           (digest-prompt
            (if template
                (gptel-auto-workflow--substitute-template
                 template
                 `((raw-findings . ,(truncate-string-to-width raw-findings 4000 nil nil "..."))))
              ;; Fallback to hardcoded prompt
              (format "You are a research digest specialist. Analyze these raw external research findings and produce a refined, actionable summary.

RAW FINDINGS:
%s

DIGESTION TASK:
1. Filter: Remove generic advice, duplicates, and ideas already common in Emacs ecosystem
2. Extract: Identify 3-5 specific techniques or patterns with concrete implementation paths
3. Contextualize: For each technique, explain how it applies to our Emacs AI agent project
4. Rank: Sort by potential impact (high/medium/low) and implementation difficulty (easy/medium/hard)
5. Format: Use structured output suitable for feeding into an experiment planning system

OUTPUT FORMAT (strict):
## Digest: External Research Insights

### Technique 1: [Name]
- **Source type**: [YouTube|GitHub|arXiv|X|HuggingFace|Reddit]
- **Impact**: [high|medium|low]
- **Difficulty**: [easy|medium|hard]
- **Description**: [2-3 sentences on what it is]
- **Application**: [Specific module or pattern in our project it could improve]
- **Implementation sketch**: [Concrete first step, 1-2 sentences]

[Repeat for each technique]

### Summary for Directive
- **Top hypothesis**: [Best technique to try next]
- **Target modules**: [Which files to experiment on]
- **Expected improvement**: [What metric or capability would improve]

RULES:
- Be specific. 'Use AI better' is banned.
- Focus on techniques we haven't implemented (check: no clj-refactor, no LSP, no tree-sitter)
- Quality over quantity. Include ALL novel insights found."
                      (truncate-string-to-width raw-findings 4000 nil nil "...")))))
      (message "[auto-workflow] Digesting unstructured research findings with LLM...")
      ;; Ensure we use an available backend for digestion
      (when (fboundp 'gptel-auto-experiment--maybe-failover-main-backend)
        (gptel-auto-experiment--maybe-failover-main-backend))
      ;; Use idempotent callback wrapper to prevent duplicate invocations
      (let ((digest-callback
             (let ((called nil))
               (lambda (response _info)
                 (unless called
                   (setq called t)
                   (let* ((candidate (if (stringp response)
                                         response
                                       (format "%s" response)))
                          (trimmed (string-trim candidate))
                          (digested (if (or (string-empty-p trimmed)
                                            (string= trimmed "nil")
                                            (< (length trimmed) 80)
                                            (gptel-auto-workflow--research-error-p trimmed))
                                        raw-findings
                                      candidate)))
                     (when (eq digested raw-findings)
                       (message "[auto-workflow] Digestion returned unusable output; preserving raw findings"))
                     (message "[auto-workflow] Digestion complete: %d chars → %d chars"
                              (length raw-findings) (length digested))
                     ;; Update context with digested version
                     (when (boundp 'gptel-auto-workflow--current-research-context)
                       (plist-put gptel-auto-workflow--current-research-context
                                  :digested digested))
                     (funcall callback digested)))))))
        (if (fboundp 'gptel-request)
            (gptel-request
                digest-prompt
              :callback digest-callback
              :system "You are a research analyst specializing in AI agent architectures and Emacs Lisp tooling. You distill raw research into actionable engineering insights.")
          (progn
            (message "[auto-workflow] gptel-request unavailable, using raw findings")
              (funcall callback raw-findings))))))))

(defun gptel-auto-workflow--run-research-turn (research-prompt turn callback 
                                                      &optional accumulated-findings total-tokens)
  "Run a single research TURN with controller checkpoint.
RESEARCH-PROMPT is the prompt for this turn.
TURN is the turn number (0-indexed).
CALLBACK receives final digested findings.
ACCUMULATED-FINDINGS is findings from previous turns.
TOTAL-TOKENS tracks cumulative token usage across turns.
AutoTTS: Controller decides after each turn whether to STOP, CONTINUE, or BRANCH."
  (let* ((controller-config (gptel-auto-workflow--load-autotts-controller))
         (max-turns gptel-auto-workflow-max-research-turns)
         (current-prompt (if (and accumulated-findings (> (length accumulated-findings) 0))
                             (gptel-auto-workflow--build-followup-prompt
                              research-prompt accumulated-findings turn)
                           research-prompt))
         (turn-label (format "External research turn %d/%d" (1+ turn) max-turns)))
    (message "[autotts] Starting %s" turn-label)
    (gptel-benchmark-call-subagent
     'researcher turn-label current-prompt
     (lambda (result)
       (let* ((raw-findings (gptel-auto-workflow--normalize-response result))
              (has-external (gptel-auto-workflow--research-has-external-content-p raw-findings))
              (research-error-p (gptel-auto-workflow--research-error-p raw-findings))
              (effective-findings (if research-error-p
                                      (gptel-auto-workflow--local-research-patterns)
                                    raw-findings))
              (findings-hash (sha1 raw-findings))
              (strategy (or (and (boundp 'gptel-auto-workflow--active-strategy)
                                 gptel-auto-workflow--active-strategy)
                            "default"))
              (confidence (gptel-auto-workflow--estimate-confidence raw-findings))
              (turn-tokens (/ (length raw-findings) 4))
              (cumulative-tokens (+ (or total-tokens 0) turn-tokens))
              ;; Merge with accumulated findings
              (merged-findings (if (and accumulated-findings (> (length accumulated-findings) 0))
                                   (concat accumulated-findings "\n\n---\n\n" effective-findings)
                                 effective-findings))
              ;; Controller decision based on merged state
              (controller-decision (gptel-auto-workflow--controller-decide-research-flow
                                    controller-config (length merged-findings))))
         ;; Log this turn as a step
         (gptel-auto-workflow--log-research-step
          'search
          (list :query (format "turn-%d" turn)
                :output-length (length raw-findings)
                :cumulative-tokens cumulative-tokens)
          confidence)
         (message "[autotts] Turn %d result: %d chars, confidence=%.2f, decision=%s, cumulative-tokens=%d"
                  (1+ turn) (length raw-findings) confidence controller-decision cumulative-tokens)
         ;; Check controller decision
         (cond
          ;; STOP: We have good findings, return them
          ((eq controller-decision 'stop)
           (message "[autotts] Controller STOP after turn %d (confidence=%.2f)"
                    (1+ turn) confidence)
           (gptel-auto-workflow--finalize-research
            research-prompt merged-findings strategy findings-hash
            controller-decision confidence cumulative-tokens callback))
          ;; CUT: Over budget, return what we have
          ((eq controller-decision 'cut)
           (message "[autotts] Controller CUT after turn %d (budget exceeded)"
                    (1+ turn))
           (gptel-auto-workflow--finalize-research
            research-prompt merged-findings strategy findings-hash
            controller-decision confidence cumulative-tokens callback))
          ;; CONTINUE or BRANCH: Keep going if not at max turns
          ((< turn (1- max-turns))
           (message "[autotts] Controller %s, proceeding to turn %d"
                    controller-decision (1+ turn))
           (gptel-auto-workflow--run-research-turn
            research-prompt (1+ turn) callback
            merged-findings cumulative-tokens))
          ;; Max turns reached
          (t
           (message "[autotts] Max turns (%d) reached, returning accumulated findings"
                    max-turns)
           (gptel-auto-workflow--finalize-research
            research-prompt merged-findings strategy findings-hash
            'max-turns confidence cumulative-tokens callback)))))
     ;; Shorter timeout per turn (180s) vs single long call (600s)
     ;; Total time: max-turns * 180s = 540s (comparable to 600s single call)
     180)))

(defun gptel-auto-workflow--build-followup-prompt (base-prompt accumulated-findings turn)
  "Build follow-up prompt for turn TURN with ACCUMULATED-FINDINGS.
BASE-PROMPT is the original research prompt."
  (format "%s\n\n---\n\n**Previous findings (turn %d):**\n%s\n\n**Continue researching.** Focus on gaps or new angles not covered above. Avoid repeating what was already found."
          base-prompt
          turn
          (truncate-string-to-width accumulated-findings 2000 nil nil "...")))

(defun gptel-auto-workflow--finalize-research (prompt findings strategy hash 
                                                      controller-decision confidence tokens-used callback)
  "Finalize research session and invoke CALLBACK with digested findings.
Saves trace, runs benchmark, and digests findings."
  ;; Store raw research context
  (setq gptel-auto-workflow--current-research-context
        (list :strategy strategy
              :hash hash
              :findings findings
              :source "external"
              :timestamp (format-time-string "%Y-%m-%dT%H:%M:%SZ")))
  (message "[auto-workflow] External research raw: %d chars (hash: %s)"
           (length findings) (substring hash 0 8))
  ;; Save research trace for AutoTTS-style offline evaluation
  (gptel-auto-workflow--save-research-trace
   prompt findings strategy hash
   controller-decision confidence tokens-used)
  ;; Run AutoTTS benchmark if available
  (when (fboundp 'gptel-auto-workflow--benchmark-research-strategy)
    (gptel-auto-workflow--benchmark-research-strategy
     strategy "external-research"
     (lambda (result)
       (message "[benchmark] Research strategy '%s' scored: %.2f"
                strategy (or (plist-get result :quality) 0.0)))))
  ;; Digest and callback
  (gptel-auto-workflow--digest-research-findings
   findings
   (lambda (digested)
     ;; Write internal patterns to separate file for DIRECTIVE.md
     (let ((internal-file (expand-file-name "var/tmp/internal-research.md"
                                            (gptel-auto-workflow--effective-project-root))))
       (make-directory (file-name-directory internal-file) t)
       (with-temp-file internal-file
         (insert (format "# Internal Code Analysis\n\n> Updated: %s\n\n%s"
                         (format-time-string "%Y-%m-%d %H:%M")
                         digested))))
      ;; Always pass findings to callback
      (funcall callback digested))))

(defun gptel-auto-workflow--research-patterns (callback &optional retry-count)
  "Hunt for external ideas from internet sources with real-time controller.
CALLBACK receives DIGESTED research findings string.
Optional RETRY-COUNT tracks recursive retries (max 2).

AutoTTS Multi-Turn: Research is broken into multiple shorter turns
with controller checkpoints between them. Controller decides after
each turn whether to STOP, CONTINUE, BRANCH, or CUT.

Pipeline: External hunt → Controller checkpoint → [Continue/Stop] → Digest
ASSUMPTION: Subagent may or may not be available.
BEHAVIOR: Uses subagent with web tools if available, otherwise returns empty.
EDGE CASE: Returns empty findings if subagent unavailable.
META-LEARNING: Stores digested insights in FINDINGS.md for future reference."
  (cl-block gptel-auto-workflow--research-patterns
  ;; Guard against concurrent research calls
  (when gptel-auto-workflow--research-in-progress
    (message "[auto-workflow] Research already in progress, skipping concurrent call")
    (funcall callback "")
    (cl-return-from gptel-auto-workflow--research-patterns))
  (setq gptel-auto-workflow--research-in-progress t)
  (let ((research-prompt (gptel-auto-workflow--build-research-prompt))
        (attempt (or retry-count 0))
        (controller-config (gptel-auto-workflow--load-autotts-controller)))
    (message "[auto-workflow] Hunting external ideas (multi-turn controller)...")
    ;; AutoTTS: Reset step trace accumulator for this session
    (gptel-auto-workflow--reset-research-steps)
    (message "[autotts] Controller: own-repo-priority=%.0f%%, stop-threshold=%.0f%%"
             (* 100 (or (plist-get controller-config :own-repo-priority) 0.7))
             (* 100 (or (plist-get controller-config :min-confidence-stop) 0.7)))
    ;; DEBUG: Log subagent availability and current state
    (message "[debug] subagents-enabled=%s fbound=%s caller=%s"
             gptel-auto-experiment-use-subagents
             (fboundp 'gptel-benchmark-call-subagent)
             (format-time-string "%H:%M:%S"))
    (if (and gptel-auto-experiment-use-subagents
             (fboundp 'gptel-benchmark-call-subagent))
        ;; Multi-turn research with controller checkpoints
        (gptel-auto-workflow--run-research-turn research-prompt 0 callback)
      (progn
        (message "[auto-workflow] Subagent unavailable - skipping external research")
        ;; Reset flag before calling callback
        (setq gptel-auto-workflow--research-in-progress nil)
        (funcall callback "")))))))

(defun gptel-auto-workflow--ask-analyzer-for-targets (callback)
  "Ask analyzer LLM to select optimization targets.
CALLBACK receives list of target files.
When gptel-auto-workflow-research-targets is non-nil, researcher
finds patterns first for better selection."
  (if gptel-auto-workflow-research-targets
      (gptel-auto-workflow--research-patterns
       (lambda (research-findings)
         (gptel-auto-workflow--ask-analyzer-with-findings research-findings callback)))
    (gptel-auto-workflow--ask-analyzer-with-findings
     (gptel-auto-workflow-load-research-findings) callback)))

(defun gptel-auto-workflow--build-analyzer-prompt (context research-findings max-targets)
  "Build prompt for analyzer LLM target selection.
CONTEXT is the gathered context plist.
RESEARCH-FINDINGS is the research findings string or empty.
MAX-TARGETS is the maximum number of targets to select.
META-LEARNING: Loads evolved directive and research skills from mementum."
  (unless (plistp context)
    (setq context '()))
  (let* ((directive (gptel-auto-workflow--load-directive-skill))
         (research-skill (gptel-auto-workflow--load-research-skill))
         (directive-section (if directive
                                (format "EVOLVED PROGRAM DIRECTIVE (from %d experiments):\n%s\n\n"
                                        (or (when (string-match "total-experiments: \\([0-9]+\\)" directive)
                                              (string-to-number (match-string 1 directive)))
                                            0)
                                        (truncate-string-to-width
                                         (replace-regexp-in-string "^---$\\|^---\\n.*\\n---\\n" "" directive)
                                         1500 nil nil "..."))
                              ""))
         (research-section (if (and research-skill (not (string-empty-p research-skill)))
                               (format "RESEARCH STRATEGY GUIDE:\n%s\n\n"
                                       (truncate-string-to-width research-skill 800 nil nil "..."))
                             "")))
    (format "Select optimization targets for this Emacs Lisp project.

%s%sFILES AVAILABLE:
%s

RECENT GIT HISTORY:
%s

FILES BY SIZE:
%s

KNOWN ISSUES (TODOs/FIXMEs):
%s

EXTERNAL RESEARCH FINDINGS (new ideas from internet):
%s

TASK: Select exactly %d files from lisp/modules/ to optimize.
Do NOT choose files from packages/ or any nested git repo. Those are optimized separately and cannot be merged into the root staging branch by this workflow.

SIZE CONSTRAINT: Skip files over 1000 lines. They are too large for focused experiments.
Example: gptel-tools-agent.el (11,481 lines) is EXCLUDED. Focus on smaller files.

%s

PRIORITIZE: Files where external research insights can be applied.
  Example: Research found \"async process monitoring\" → target files with process handling
  Example: Research found \"state machine pattern\" → target files with complex control flow
AVOID: Recently-refactored files with no remaining issues.
AVOID: Files over 1000 lines (too large for focused changes).
HINT: External research insights suggest novel approaches. Consider targets that could benefit from these techniques even if they don't have obvious bugs.

OUTPUT JSON ONLY:
{\"targets\": [{\"file\": \"lisp/modules/xxx.el\", \"priority\": 1, \"reason\": \"why\"}]}"
            directive-section
            research-section
            (or (plist-get context :file-list) "")
            (or (plist-get context :git-history) "")
            (or (plist-get context :file-sizes) "")
            (or (plist-get context :todos) "")
            (if (or (null research-findings) (string-empty-p research-findings))
                "Not available (research disabled)"
              (truncate-string-to-width research-findings 3500 nil nil "..."))
            max-targets
            (if (fboundp 'gptel-auto-workflow--evolution-get-knowledge)
                (gptel-auto-workflow--evolution-get-knowledge)
              "HISTORICAL SUCCESS PATTERNS (from past experiments):\n- Focus on bug fixes and error handling for best results"))))

(defun gptel-auto-workflow--ask-analyzer-with-findings (research-findings callback)
  "Ask analyzer with optional RESEARCH-FINDINGS for target selection.
CALLBACK receives list of target files.
ASSUMPTION: my/gptel-agent-task-timeout may be unbound in some configurations.
EDGE CASE: Unbound timeout variable defaults to 0, letting analyzer-time-budget govern."
  (let* ((context (gptel-auto-workflow--gather-context))
         (max-targets gptel-auto-workflow-max-targets-per-run)
         (analyzer-timeout (max (or (and (boundp 'my/gptel-agent-task-timeout)
                                         my/gptel-agent-task-timeout)
                                    0)
                                gptel-auto-workflow-analyzer-time-budget))
         (prompt (gptel-auto-workflow--build-analyzer-prompt
                  context research-findings max-targets)))
    (if (and gptel-auto-experiment-use-subagents
             (fboundp 'gptel-benchmark-call-subagent))
        (cl-labels
            ((request-analyzer (attempt)
               (gptel-benchmark-call-subagent
                'analyzer
                "Select targets"
                prompt
                (lambda (result)
                  (let* ((targets (gptel-auto-workflow--parse-targets result))
                         (candidate
                          (and (zerop attempt)
                               (null targets)
                               (or gptel-auto-workflow--analyzer-quota-exhausted
                                   gptel-auto-workflow--analyzer-transient-failure)
                               (gptel-auto-workflow--analyzer-failover-candidate))))
                    (if candidate
                        (progn
                          (message "[auto-workflow] Retrying analyzer target selection with %s/%s"
                                   (car candidate)
                                   (cdr candidate))
                          (gptel-auto-workflow--clear-analyzer-error-state)
                          (request-analyzer (1+ attempt)))
                      (funcall callback targets))))
                analyzer-timeout)))
          (message "[auto-workflow] Asking analyzer to select targets...")
          (request-analyzer 0))
      (funcall callback nil))))

(defun gptel-auto-workflow--validate-and-add-target (file proj-root targets)
  "Validate FILE and add to TARGETS if it exists.
FILE can be a string path or a JSON object (alist) with file/path/target keys.
Caller is responsible for enforcing max-targets limit.
Returns updated targets list."
  (cond
   ((gptel-auto-workflow--json-object-p file)
    (let ((extracted-file (or (alist-get 'file file)
                              (cdr (assoc "file" file))
                              (alist-get 'path file)
                              (cdr (assoc "path" file))
                              (alist-get 'target file)
                              (cdr (assoc "target" file)))))
      (gptel-auto-workflow--validate-and-add-target extracted-file proj-root targets)))
   ((not (stringp file)) targets)
   ((not (gptel-auto-workflow--nonempty-string-p file)) targets)
   ((not (and (stringp proj-root) (not (string-empty-p proj-root)))) targets)
   (t
    (let ((abs-path (if (file-name-absolute-p file)
                        file
                      (expand-file-name file proj-root)))
          (root-prefix (if (string-suffix-p "/" proj-root)
                           proj-root
                         (concat proj-root "/"))))
      (if (and (file-exists-p abs-path)
               (string-prefix-p root-prefix abs-path)
               (gptel-auto-workflow--target-in-root-repo-p abs-path proj-root))
          (let ((rel-path (file-relative-name abs-path proj-root)))
            (if (gptel-auto-workflow--skip-headless-target-p rel-path)
                (progn
                  (message "[auto-workflow] Skipping self-hosting target in headless run: %s"
                           rel-path)
                  targets)
              (if (member rel-path targets)
                  targets
                (cons rel-path targets))))
        targets)))))

(defun gptel-auto-workflow--normalize-response (response)
  "Normalize RESPONSE to a string.
If RESPONSE is already a string, return it.
Otherwise, convert using princ representation."
  (if (stringp response) response (format "%S" response)))

(defun gptel-auto-workflow--response-snippet (response &optional max-len)
  "Return RESPONSE collapsed to a short single-line string for logging."
  (when (stringp response)
    (truncate-string-to-width
     (replace-regexp-in-string "[[:space:]\n\r\t]+" " " response)
     (or max-len 160)
     nil nil "...")))

(defun gptel-auto-workflow--analyzer-error-p (response)
  "Return non-nil when RESPONSE is an analyzer task failure wrapper."
  (and (stringp response)
       (string-match-p "\\`Error:" response)))

(defun gptel-auto-workflow--research-has-external-content-p (response)
  "Return non-nil when RESPONSE contains actual external research references.
Checks for URLs, specific source types, or external project mentions.
A response with only internal code analysis is not external research.
Also treats long responses (>1000 chars) as likely external research,
since the researcher subagent digests fetched content and may not
include raw URLs in the summary."
  (and (stringp response)
        (> (length response) 200)
        (or (> (length response) 400)  ; Medium+ responses = digested external research
            (string-match-p "https?://" response)
            (string-match-p "\\b\\(GitHub\\|arXiv\\|YouTube\\|Reddit\\|HuggingFace\\|X/Twitter\\)\\b" response)
            (string-match-p "\\b\\(karthink/gptel\\|hermes-agent\\|zeroclaw\\|ml-intern\\)\\b" response))))

(defun gptel-auto-workflow--research-error-p (response)
  "Return non-nil when RESPONSE is a researcher task failure wrapper.
Treats short responses (< 500 chars) without external references as failures.
Long responses (>1000 chars) are assumed successful and never flagged as errors.
Only checks retryable-error patterns for short responses that look like error messages."
  (and (stringp response)
       (or (string-match-p "\\`Error:" response)
           ;; Only check retryable errors for short responses (<1000 chars)
           ;; that are likely error messages, not valid research output
           (and (< (length response) 1000)
                (fboundp 'gptel-auto-experiment--is-retryable-error-p)
                (gptel-auto-experiment--is-retryable-error-p response))
           ;; Only flag as missing external content if short AND no refs
           (and (< (length response) 500)
                (not (gptel-auto-workflow--research-has-external-content-p response))))))

(defun gptel-auto-workflow--analyzer-transient-error-p (response)
  "Return non-nil when RESPONSE reflects a transient analyzer/provider failure."
  (and (gptel-auto-workflow--analyzer-error-p response)
       (gptel-auto-experiment--is-retryable-error-p response)))

(defun gptel-auto-workflow--filter-valid-targets (candidates proj-root max-targets)
  "Filter CANDIDATES to valid target files.
Returns list of validated relative paths, up to MAX-TARGETS.
ASSUMPTION: candidates is nil or a list of file paths/objects.
ASSUMPTION: proj-root is a non-empty string or nil.
EDGE CASE: nil candidates returns empty list.
EDGE CASE: nil proj-root causes all candidates to be skipped.
BEHAVIOR: Only consumes quota slots when targets are actually added."
  (unless (listp candidates)
    (if (null candidates)
        (setq candidates nil)
      (setq candidates (list candidates))))
  (unless (and (integerp max-targets) (> max-targets 0))
    (setq max-targets most-positive-fixnum))
  (let ((targets '())
        (remaining-slots max-targets))
    (dolist (file candidates (reverse targets))
      (when (and (gptel-auto-workflow--nonempty-string-p file)
                 (> remaining-slots 0))
        (let* ((pre-count (length targets))
               (new-targets (gptel-auto-workflow--validate-and-add-target
                             file proj-root targets)))
          (when (> (length new-targets) pre-count)
            (setq targets new-targets)
            (cl-decf remaining-slots)))))))

(defun gptel-auto-workflow--parse-targets (response)
  "Parse LLM RESPONSE to extract target file list.
Logs when fallback to regex parsing is used."
  (let ((proj-root (gptel-auto-workflow--effective-project-root))
        (max-targets gptel-auto-workflow-max-targets-per-run)
        (normalized-response (gptel-auto-workflow--normalize-response response)))
    (cond
     ((gptel-auto-experiment--quota-exhausted-p normalized-response)
      (setq gptel-auto-workflow--analyzer-quota-exhausted t)
      (message "[auto-workflow] Analyzer quota exhausted during target selection")
      nil)
     ((gptel-auto-workflow--analyzer-transient-error-p normalized-response)
      (setq gptel-auto-workflow--analyzer-transient-failure t)
      (message "[auto-workflow] Analyzer transient failure during target selection: %s"
               (gptel-auto-workflow--response-snippet normalized-response 120))
      nil)
     ((gptel-auto-workflow--analyzer-error-p normalized-response)
      (message "[auto-workflow] Analyzer error during target selection: %s"
               (gptel-auto-workflow--response-snippet normalized-response 120))
      nil)
     (t
      (let ((json-targets (gptel-auto-workflow--parse-json-targets
                           normalized-response proj-root max-targets)))
        (if json-targets
            json-targets
          (progn
            (message "[auto-workflow] JSON parse returned no targets, trying regex fallback")
            (gptel-auto-workflow--parse-regex-targets
             normalized-response proj-root max-targets))))))))

(defun gptel-auto-workflow--json-object-p (value)
  "Return non-nil when VALUE looks like a JSON object alist.
ASSUMPTION: value is either nil, a proper alist, or invalid input.
EDGE CASE: nil returns nil, non-list atoms return nil."
  (when (listp value)
    (and (consp value)
         (consp (car value))
         (or (symbolp (caar value))
             (stringp (caar value))))))

(defun gptel-auto-workflow--handle-analyzer-error-state (targets static-targets callback)
  "Handle analyzer error states and invoke CALLBACK with appropriate targets.
TARGETS is the analyzer result, STATIC-TARGETS is fallback list.
Returns non-nil if error state was handled."
  (cond
   ((and gptel-auto-workflow--analyzer-quota-exhausted
         (not targets))
    (message "[auto-workflow] Analyzer quota exhausted; using static targets")
    (funcall callback static-targets)
    t)
   ((and gptel-auto-workflow--analyzer-transient-failure
         (not targets))
    (message "[auto-workflow] Analyzer transient failure; using static targets")
    (funcall callback static-targets)
    t)
   ((not targets)
    (message "[auto-workflow] Analyzer returned no targets; using static targets")
    (funcall callback static-targets)
    t)
   (t nil)))

(defun gptel-auto-workflow--normalize-target-candidate (candidate)
  "Normalize parsed target CANDIDATE to a repo-relative path when possible."
  (cond
   ((not (stringp candidate)) nil)
   ((string-empty-p candidate) nil)
   ((or (file-name-absolute-p candidate)
        (string-match-p "/" candidate))
    candidate)
   ((string-match-p "\\.el\\'" candidate)
    (concat "lisp/modules/" candidate))
   (t candidate)))

(defun gptel-auto-workflow--json-target-file (item)
  "Extract a target file path from parsed JSON ITEM.
BEHAVIOR: Handles string paths, alist objects, and invalid input.
EDGE CASE: nil or non-list returns nil safely."
  (cond
   ((stringp item)
    (gptel-auto-workflow--normalize-target-candidate item))
   ((gptel-auto-workflow--json-object-p item)
    (gptel-auto-workflow--normalize-target-candidate
     (or (alist-get 'file item)
         (cdr (assoc "file" item))
         (alist-get 'path item)
         (cdr (assoc "path" item))
         (alist-get 'target item)
         (cdr (assoc "target" item)))))
   (t nil)))

(defun gptel-auto-workflow--nonempty-string-p (s)
  "Return non-nil if S is a non-empty string."
  (and (stringp s) (not (string-empty-p s))))

(defun gptel-auto-workflow--parse-json-targets (response proj-root max-targets)
  "Parse JSON from RESPONSE to extract targets.
Returns nil if parsing fails or no targets found.
Logs parsing failures for debugging."
  (cl-block gptel-auto-workflow--parse-json-targets
    (unless (gptel-auto-workflow--nonempty-string-p response)
      (message "[auto-workflow] Empty response in parse-json-targets")
      (cl-return-from gptel-auto-workflow--parse-json-targets nil))
    (condition-case err
        (with-temp-buffer
          (insert response)
          (goto-char (point-min))
          (when (re-search-forward "[{[]" nil t)
            (goto-char (match-beginning 0))
            (let* ((json-array-type 'list)
                   (json-object-type 'alist)
                   (json-key-type 'symbol)
                   (data (json-read))
                   (target-list
                    (cond
                     ((gptel-auto-workflow--json-object-p data)
                      (or (alist-get 'targets data)
                          (alist-get 'files data)
                          (alist-get 'paths data)
                          (and (gptel-auto-workflow--json-target-file data)
                               (list data))))
                     ((listp data) data)))
                   (candidates
                    (and (listp target-list)
                         (delq nil
                               (mapcar #'gptel-auto-workflow--json-target-file
                                       target-list)))))
              (when candidates
                (gptel-auto-workflow--filter-valid-targets
                 candidates proj-root max-targets)))))
      (json-error
       (message "[auto-workflow] JSON parse error: %s" (error-message-string err))
       nil)
      (error
       (message "[auto-workflow] Target parse error: %s" (error-message-string err))
       nil))))

(defun gptel-auto-workflow--parse-regex-targets (response proj-root max-targets)
  "Parse RESPONSE using regex fallback to extract targets.
Returns list of validated file paths."
  (cl-block gptel-auto-workflow--parse-regex-targets
    (unless (gptel-auto-workflow--nonempty-string-p response)
      (message "[auto-workflow] Empty response in parse-regex-targets")
      (cl-return-from gptel-auto-workflow--parse-regex-targets nil))
    (with-temp-buffer
      (insert response)
      (goto-char (point-min))
      (let ((candidates '()))
        (while (re-search-forward "lisp/modules/[a-zA-Z0-9_/.-]+\\.el" nil t)
          (push (match-string 0) candidates))
        (goto-char (point-min))
        (when (null candidates)
          (while (re-search-forward "\\b\\([a-zA-Z0-9_-]+\\.el\\)\\b" nil t)
            (push (gptel-auto-workflow--normalize-target-candidate (match-string 1))
                  candidates)))
        (gptel-auto-workflow--filter-valid-targets
         (nreverse candidates) proj-root max-targets)))))

(defun gptel-auto-workflow-select-targets (callback)
  "Select targets for optimization.
CALLBACK receives list of target files.
LLM decides if available, otherwise uses static list.
ASSUMPTION: gptel-auto-workflow--filter-frontier-saturated-targets returns a list or nil.
EDGE CASE: External filter returns non-list value; listp guard prevents type errors.
BEHAVIOR: Validates filtered result is a list before using it, falls back to unfiltered targets."
  (when (functionp callback)
    (gptel-auto-workflow--clear-analyzer-error-state)
    (let* ((proj-root (gptel-auto-workflow--effective-project-root))
           (static-targets
            (gptel-auto-workflow--filter-valid-targets
             gptel-auto-workflow-targets
             proj-root
             gptel-auto-workflow-max-targets-per-run)))
      (if gptel-auto-workflow-strategic-selection
          (gptel-auto-workflow--ask-analyzer-for-targets
           (lambda (targets)
             (if (gptel-auto-workflow--handle-analyzer-error-state targets static-targets callback)
                 nil  ; Error already handled
               (if (null targets)
                   (progn
                     (message "[auto-workflow] Analyzer returned no targets; using static targets")
                     (funcall callback static-targets))
                 (let* ((filtered-targets (gptel-auto-workflow--filter-frontier-saturated-targets targets))
                        (final-targets (if (and filtered-targets (listp filtered-targets))
                                           filtered-targets
                                         targets)))
                   (unless (or (null filtered-targets) (listp filtered-targets))
                     (message "[auto-workflow] Frontier filter returned non-list (%S); using unfiltered targets"
                              filtered-targets))
                   (message "[auto-workflow] Analyzer selected %d targets, %d after frontier filtering"
                            (length targets) (length final-targets))
                   (funcall callback final-targets))))))
        (let* ((filtered-targets (if static-targets
                                     (gptel-auto-workflow--filter-frontier-saturated-targets static-targets)
                                   nil))
               (final-targets (if (and filtered-targets (listp filtered-targets))
                                  filtered-targets
                                static-targets)))
          (unless (or (null filtered-targets) (listp filtered-targets))
            (message "[auto-workflow] Frontier filter returned non-list (%S); using unfiltered targets"
                     filtered-targets))
          (message "[auto-workflow] Static: %d targets, %d after frontier filtering"
                   (length static-targets) (length final-targets))
          (funcall callback final-targets))))))

;;; ─── AutoTTS Trace Collection & Controller ───

(defvar gptel-auto-workflow--research-trace-dir
  (expand-file-name "var/tmp/research-traces")
  "Directory to save research traces for AutoTTS offline evaluation.")

(defvar gptel-auto-workflow--active-strategy nil
  "Currently active research strategy (evolved by benchmark system).")

(defvar gptel-auto-workflow--research-steps nil
  "List of step-level traces for current research session.
Each step is a plist with :step :type :query :url :timestamp :confidence.
Accumulated during research and saved with session trace.
Reset at start of each research session.
Enables AutoTTS offline evaluation of per-step decisions.")

(defun gptel-auto-workflow--reset-research-steps ()
  "Reset the research steps accumulator for a new session."
  (setq gptel-auto-workflow--research-steps nil))

(defun gptel-auto-workflow--log-research-step (step-type data &optional confidence)
  "Log a research step for AutoTTS trace collection.
STEP-TYPE is symbol: search, fetch, analyze, branch, stop.
DATA is plist with step-specific data (:query :url :output :timestamp).
CONFIDENCE is optional confidence score (0-1) for this step.
Call during or after research to build step-level timeline."
  (let ((step (list :step (length gptel-auto-workflow--research-steps)
                    :type (symbol-name step-type)
                    :timestamp (format-time-string "%Y-%m-%dT%H:%M:%SZ")
                    :confidence (or confidence 0.0)
                    :data data)))
    (push step gptel-auto-workflow--research-steps)
    (message "[autotts] Step %d: %s %s"
             (plist-get step :step)
             (plist-get step :type)
             (or (plist-get data :query) (plist-get data :url) ""))))

(defun gptel-auto-workflow--extract-research-steps (output)
  "Extract inferred research steps from researcher OUTPUT.
Parses output for evidence of tool calls (WebSearch queries, WebFetch URLs).
Returns list of step plists.
Since we can't instrument subagent internals, we reconstruct from output."
  (let ((steps nil)
        (step-idx 0))
    ;; Extract WebSearch queries (look for search patterns)
    (save-match-data
      (let ((pos 0))
        (while (string-match
                "\\(?:WebSearch\\|Search\\|Query\\)[^:]*:?\\s-*\\(\\(?:[^\n]*\\(?:github\\|arxiv\\|reddit\\|stackoverflow\\|huggingface\\)\\|[^\n]+\\)\\)"
                output pos)
          (let ((query (match-string 1 output)))
            (when (and query (> (length query) 5))
              (push (list :step step-idx
                          :type "search"
                          :query (string-trim query)
                          :timestamp (format-time-string "%Y-%m-%dT%H:%M:%SZ")
                          :confidence 0.5)
                    steps)
              (setq step-idx (1+ step-idx))))
          (setq pos (match-end 0)))))
    ;; Extract WebFetch URLs (look for fetched URLs)
    (save-match-data
      (let ((pos 0))
        (while (string-match
                "\\(?:WebFetch\\|Fetch\\|Reading\\)[^:]*:?\\s-*\\(https?://[^\s\n]+\\)"
                output pos)
          (let ((url (match-string 1 output)))
            (when url
              (push (list :step step-idx
                          :type "fetch"
                          :url url
                          :timestamp (format-time-string "%Y-%m-%dT%H:%M:%SZ")
                          :confidence 0.6)
                    steps)
              (setq step-idx (1+ step-idx))))
          (setq pos (match-end 0)))))
    ;; Extract analyzed sections (headers indicate analysis steps)
    (save-match-data
      (let ((pos 0))
        (while (string-match "^##\\s-+\\(.+\\)$" output pos)
          (let ((section (match-string 1 output)))
            (when (and section (> (length section) 3))
              (push (list :step step-idx
                          :type "analyze"
                          :section (string-trim section)
                          :timestamp (format-time-string "%Y-%m-%dT%H:%M:%SZ")
                          :confidence 0.7)
                    steps)
              (setq step-idx (1+ step-idx))))
          (setq pos (match-end 0)))))
    ;; Extract decision points from JSON metadata at end
    (save-match-data
      (let ((json-start (string-match "```json" output))
            (json-end (string-match "```" output (if json-start (+ json-start 7) 0))))
        (when (and json-start json-end (> json-end json-start))
          (let* ((json-str (string-trim (substring output (+ json-start 7) json-end)))
                 (json-object-type 'plist))
            (condition-case nil
                (let ((metadata (json-read-from-string json-str)))
                  (push (list :step step-idx
                              :type "decision"
                              :strategy (plist-get metadata :strategy)
                              :sources (plist-get metadata :sources_checked)
                              :topics (plist-get metadata :topics_covered)
                              :estimated-tokens (plist-get metadata :estimated_tokens)
                              :confidence-label (plist-get metadata :confidence)
                              :timestamp (format-time-string "%Y-%m-%dT%H:%M:%SZ")
                              :confidence (cond
                                           ((string= (plist-get metadata :confidence) "high") 0.9)
                                           ((string= (plist-get metadata :confidence) "medium") 0.6)
                                           (t 0.3)))
                        steps))
              (error nil))))))
    ;; If we found explicit steps, prefer those over parsed ones
    (or (reverse steps) nil)))

(defun gptel-auto-workflow--merge-steps-with-session (steps)
  "Merge parsed STEPS into the session step accumulator.
Called after research completes to combine explicit and parsed steps."
  (when steps
    (dolist (step steps)
      (push step gptel-auto-workflow--research-steps))
    (setq gptel-auto-workflow--research-steps
          (sort gptel-auto-workflow--research-steps
                (lambda (a b) (< (plist-get a :step) (plist-get b :step)))))))

(defun gptel-auto-workflow--save-research-trace (prompt output strategy hash &optional controller-decision confidence tokens-used)
  "Save research session trace for AutoTTS offline evaluation.
PROMPT is the research prompt sent to subagent.
OUTPUT is the raw response.
STRATEGY is the strategy name used.
HASH is the findings hash.
CONTROLLER-DECISION is symbol: stop, continue, branch, or cut.
CONFIDENCE is estimated confidence score (0-1).
TOKENS-USED is estimated token count."
  (let* ((trace-dir gptel-auto-workflow--research-trace-dir)
         (timestamp (format-time-string "%Y%m%d-%H%M%S"))
         (trace-file (expand-file-name (format "%s-%s.json" timestamp hash)
                                      trace-dir))
         ;; Extract step-level data from output
         (parsed-steps (gptel-auto-workflow--extract-research-steps output))
         ;; Merge with any explicitly logged steps
         (all-steps (or (progn
                          (gptel-auto-workflow--merge-steps-with-session parsed-steps)
                          gptel-auto-workflow--research-steps)
                        parsed-steps)))
    (make-directory trace-dir t)
    (let ((trace-data
           (list :timestamp (format-time-string "%Y-%m-%dT%H:%M:%SZ")
                 :strategy strategy
                 :findings-hash hash
                 :prompt-length (length prompt)
                 :output-length (length output)
                 :has-urls (if (string-match-p "https?://" output) t nil)
                 :has-code (if (string-match-p "```" output) t nil)
                 :has-structure (if (string-match-p "## .*\\n" output) t nil)
                 :source (if (string-match-p "davidwuchn" output) "own-repo" "external")
                 :controller-decision (symbol-name (or controller-decision 'continue))
                 :confidence (or confidence (gptel-auto-workflow--estimate-confidence output))
                 :tokens-used (or tokens-used (/ (length output) 4))
                 ;; Step-level traces for AutoTTS offline evaluation
                 :steps all-steps
                 :step-count (length all-steps)
                 :metadata (list :tokens-estimate (/ (length output) 4)
                                :confidence (or confidence (gptel-auto-workflow--estimate-confidence output))
                                :step-count (length all-steps)
                                :has-steps (if all-steps t nil)))))
      (with-temp-file trace-file
        (insert (json-encode trace-data)))
      (message "[autotts] Saved research trace: %s (%d steps)"
               (file-name-nondirectory trace-file)
               (or (length all-steps) 0)))))

(defun gptel-auto-workflow--estimate-confidence (output)
  "Estimate confidence score (0-1) from research output.
Heuristic based on AutoTTS confidence signals."
  (let ((score 0.0)
        (len (length output)))
    ;; URLs present = credible
    (when (string-match-p "https?://" output)
      (setq score (+ score 0.3)))
    ;; Structured format = organized thinking
    (when (string-match-p "## .*\\n" output)
      (setq score (+ score 0.2)))
    ;; Code examples = specific
    (when (string-match-p "```" output)
      (setq score (+ score 0.2)))
    ;; Length appropriate
    (cond ((> len 3000) (setq score (+ score 0.2)))
          ((> len 1000) (setq score (+ score 0.1)))
          (t (setq score (+ score 0.05))))
    ;; Actionable items
    (when (string-match-p "\\*\\*" output)
      (setq score (+ score 0.1)))
    score))

(defun gptel-auto-workflow--load-autotts-controller ()
  "Load AutoTTS controller configuration.
Returns plist with controller parameters."
  (let ((controller-file (expand-file-name "var/tmp/researcher-controller.json"
                                          (gptel-auto-workflow--effective-project-root))))
    (if (file-exists-p controller-file)
        (let ((json-object-type 'plist))
          (with-temp-buffer
            (insert-file-contents controller-file)
            (json-read)))
      ;; Default controller config
      (list :own-repo-priority 0.7
            :fork-priority 0.4
            :external-priority 0.15
            :web-priority 0.05
            :min-confidence-stop 0.7
            :max-tokens-budget 8000
            :min-insights-for-stop 2
            :stagnation-window 2))))

(defun gptel-auto-workflow--controller-decide-research-flow (controller-config output-length)
  "AutoTTS controller: decide what to do next based on state.
CONTROLLER-CONFIG is plist with parameters.
OUTPUT-LENGTH is current response length.
Returns symbol: stop, continue, branch, or cut."
  (let ((tokens-used (/ output-length 4))
        (max-tokens (or (plist-get controller-config :max-tokens-budget) 8000))
        (min-confidence (or (plist-get controller-config :min-confidence-stop) 0.7)))
    (cond
     ;; Over budget → cut
     ((> tokens-used max-tokens)
      (message "[autotts] Controller: CUT (budget %d/%d)" tokens-used max-tokens)
      'cut)
     ;; High confidence + good length → stop
     ((and (> output-length 2000)
           (string-match-p "https?://" output-length))
      (message "[autotts] Controller: STOP (good output)")
      'stop)
     ;; Default → continue
     (t 'continue))))

(defun gptel-auto-workflow--load-strategy-guidance ()
  "Load AutoTTS strategy guidance from controller config.
Returns formatted string with current controller parameters."
  (let* ((controller-config (gptel-auto-workflow--load-autotts-controller))
         (own-priority (* 100 (or (plist-get controller-config :own-repo-priority) 0.7)))
         (external-priority (* 100 (or (plist-get controller-config :external-priority) 0.15)))
         (stop-threshold (* 100 (or (plist-get controller-config :min-confidence-stop) 0.7)))
         (budget (or (plist-get controller-config :max-tokens-budget) 8000))
         (based-on (or (plist-get controller-config :based-on-traces) 0))
         (evolved-at (or (plist-get controller-config :evolved-at) "never")))
    (concat
     "**Current Controller Config** (evolved " evolved-at " from " (number-to-string based-on) " traces):\n\n"
     "- Own repo priority: " (format "%.0f%%" own-priority) "\n"
     "- External priority: " (format "%.0f%%" external-priority) "\n"
     "- Stop threshold: " (format "%.0f%%" stop-threshold) " confidence\n"
     "- Token budget: " (number-to-string budget) "\n\n"
     "**Decision Rules**:\n"
     "1. If confidence > " (format "%.0f%%" stop-threshold) " + have URLs → STOP early\n"
     "2. If output < 1000 chars → CONTINUE searching\n"
     "3. If > " (number-to-string budget) " tokens → CUT (return what you have)\n"
     "4. Check own repos (davidwuchn/*) FIRST before external\n")))

;;; Periodic Research

(defun gptel-auto-workflow--research-file ()
  "Return path to research findings cache file."
  (expand-file-name "var/tmp/research-findings.md"
                    (gptel-auto-workflow--effective-project-root)))

(defun gptel-auto-workflow-run-research (&optional completion-callback)
  "Run researcher and store findings to cache.
Call periodically to keep findings fresh.
Findings available to analyzer during target selection.
Findings are cached per-project.
When COMPLETION-CALLBACK is non-nil, call it after findings are cached."
  (interactive)
  (let* ((proj-root (gptel-auto-workflow--effective-project-root))
         (cache-key (gptel-auto-workflow--normalized-cache-key proj-root)))
    (message "[research] Starting periodic research for %s..." proj-root)
    (gptel-auto-workflow--research-patterns
     (lambda (findings)
       (puthash cache-key findings gptel-auto-workflow--research-findings-cache)
       (let ((file (gptel-auto-workflow--research-file)))
         (make-directory (file-name-directory file) t)
         (with-temp-file file
           (insert (format "# Research Findings\n\n> Project: %s\n> Updated: %s\n\n%s"
                           proj-root
                           (format-time-string "%Y-%m-%d %H:%M")
                           findings)))
         (message "[research] Findings cached for %s (%d chars)"
                  proj-root (length findings))
         (when completion-callback
           (funcall completion-callback findings)))))))

(defun gptel-auto-workflow-load-research-findings ()
  "Load cached research findings for current project.
Returns empty string if no cache exists.
Findings are cached per-project."
  (let* ((proj-root (gptel-auto-workflow--effective-project-root))
         (cache-key (gptel-auto-workflow--normalized-cache-key proj-root))
         (cached (gethash cache-key gptel-auto-workflow--research-findings-cache))
         (file (gptel-auto-workflow--research-file))
         (file-findings nil))
    (when (file-exists-p file)
      (setq file-findings
            (with-temp-buffer
              (insert-file-contents file)
              (goto-char (point-min))
              (let ((content-start nil))
                (while (and (not (eobp)) (not content-start))
                  (if (looking-at "^$")
                      (progn
                        (forward-line 1)
                        (setq content-start (point)))
                    (forward-line 1)))
                (string-trim
                 (if content-start
                     (buffer-substring content-start (point-max))
                   ""))))))
    (cond
     ((and (stringp file-findings)
           (not (string-empty-p file-findings))
           (or (not (stringp cached))
               (string-empty-p cached)
               (> (length file-findings) (length cached))))
      (puthash cache-key file-findings gptel-auto-workflow--research-findings-cache)
      (message "[research] Loaded cached findings from disk for %s (%d chars)"
               proj-root (length file-findings))
      file-findings)
     ((and (stringp cached) (not (string-empty-p cached)))
      (message "[research] Using in-memory findings for %s (%d chars)"
               proj-root (length cached))
      cached)
     (t
      (message "[research] No cached findings found for %s" proj-root)
      ""))))

(defun gptel-auto-workflow-start-periodic-research ()
  "Start periodic researcher runs.
Findings cached for analyzer to use during target selection.
Set `gptel-auto-workflow-research-interval' to control frequency."
  (interactive)
  (when (and gptel-auto-workflow-research-interval
             (> gptel-auto-workflow-research-interval 0))
    (gptel-auto-workflow-stop-periodic-research)
    (setq gptel-auto-workflow--research-timer
          (run-with-timer gptel-auto-workflow-research-interval
                          gptel-auto-workflow-research-interval
                          #'gptel-auto-workflow-run-research))
    (message "[research] Periodic research started (interval: %ds)"
             gptel-auto-workflow-research-interval)
    (gptel-auto-workflow-run-research)))

(defun gptel-auto-workflow-stop-periodic-research ()
  "Stop periodic researcher runs."
  (interactive)
  (when gptel-auto-workflow--research-timer
    (cancel-timer gptel-auto-workflow--research-timer)
    (setq gptel-auto-workflow--research-timer nil)
    (message "[research] Periodic research stopped")))

(defun gptel-auto-workflow-research-status ()
  "Show researcher status for current project."
  (interactive)
  (let* ((proj-root (gptel-auto-workflow--effective-project-root))
         (cache-key (gptel-auto-workflow--normalized-cache-key proj-root))
         (findings (gethash cache-key
                            gptel-auto-workflow--research-findings-cache
                            ""))
         (cache-file (gptel-auto-workflow--research-file))
         (file-exists (file-exists-p cache-file))
         (file-attrs (and file-exists (file-attributes cache-file)))
         (file-size (or (and file-attrs (nth 7 file-attrs)) 0))
         (file-mtime (and file-attrs (nth 5 file-attrs)))
         (file-mtime-str (and file-mtime
                              (format-time-string "%Y-%m-%d %H:%M" file-mtime))))
    (list :running (timerp gptel-auto-workflow--research-timer)
          :interval gptel-auto-workflow-research-interval
          :project proj-root
          :findings-cached (and (stringp findings) (not (string-empty-p findings)))
          :findings-length (length findings)
          :cache-file cache-file
          :cache-file-exists file-exists
          :cache-file-size file-size
          :cache-file-mtime file-mtime-str)))

;;; ─── AutoTTS via Benchmark System ───

;; Reuse benchmark infrastructure instead of building separate AutoTTS.
;; gptel-auto-workflow-research-benchmark.el provides:
;; - Strategy benchmarking using gptel-benchmark-call-subagent
;; - Research output scoring
;; - Automatic strategy evolution

(defun gptel-auto-workflow--run-strategy-evolution ()
  "Run AutoTTS-style strategy evolution using benchmark system.
Uses gptel-auto-workflow-research-benchmark.el to:
1. Load research traces
2. Evolve controller from trace analysis
3. Benchmark strategies offline
4. Pick best based on quality/tokens efficiency
5. Update active strategy and controller for next run."
  (message "[evolve] Running AutoTTS evolution cycle...")
  (if (fboundp 'gptel-auto-workflow--run-autotts-evolution)
      ;; Full AutoTTS evolution (traces → controller → strategy)
      (gptel-auto-workflow--run-autotts-evolution)
    ;; Fallback: just evolve strategy from benchmark results
    (if (fboundp 'gptel-auto-workflow--evolve-research-strategy)
        (progn
          (message "[evolve] Running benchmark-based strategy evolution...")
          (gptel-auto-workflow--evolve-research-strategy)
          (message "[evolve] Strategy evolution complete"))
      ;; Fallback to Python script
      (let* ((root (gptel-auto-workflow--worktree-base-root))
             (script (expand-file-name "assistant/skills/researcher-prompt/scripts/unified-evolution.py" root)))
        (when (file-executable-p script)
          (message "[evolve] Running Python evolution fallback...")
          (let ((output (shell-command-to-string (format "cd %s && python3 %s"
                                                          (shell-quote-argument root)
                                                          (shell-quote-argument script)))))
            (message "[evolve] %s" output))))
    (message "[evolve] Strategy evolution cycle complete"))))

(provide 'gptel-auto-workflow-strategic)

;;; gptel-auto-workflow-strategic.el ends here
)
