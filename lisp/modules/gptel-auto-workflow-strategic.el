;;; gptel-auto-workflow-strategic.el --- Strategic target selection for auto-workflow -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Commentary:
;; LLM-first target selection for auto-workflow.
;; Let the analyzer decide which files to optimize.

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
(require 'gptel-auto-workflow-research-cache nil t)
(require 'gptel-auto-workflow-research-benchmark nil t)
;; Post-load check: verify critical function is available
(unless (fboundp 'gptel-auto-workflow--trace-outcome-known-p)
  (message "[strategic] WARNING: research-benchmark functions not available"))

;; Global variables to avoid closure issues in daemon environments
;; where lexical-binding may not be properly enabled during load
(defvar gptel-auto-workflow--research-accumulated-findings nil
  "Temporary storage for accumulated findings during multi-turn research.")
(defvar gptel-auto-workflow--research-total-tokens nil
  "Temporary storage for total tokens during multi-turn research.")
(defvar gptel-auto-workflow--research-controller-config nil
  "Temporary storage for controller config during multi-turn research.")
(defvar gptel-auto-workflow--research-current-turn nil
  "Temporary storage for current turn number during multi-turn research.")
(defvar gptel-auto-workflow--research-max-turns nil
  "Temporary storage for max turns during multi-turn research.")
(defvar gptel-auto-workflow--research-prompt nil
  "Temporary storage for research prompt during multi-turn research.")

(declare-function gptel-auto-workflow--evolution-get-knowledge "gptel-auto-workflow-evolution" ())
(declare-function gptel-auto-workflow--filter-frontier-saturated-targets "gptel-tools-agent-prompt-build" (targets))
(defvar gptel-auto-experiment--critical-files)
(declare-function gptel-auto-experiment--quota-exhausted-p "gptel-tools-agent-error" (agent-output))
(declare-function gptel-auto-workflow--json-encode-plist "gptel-auto-workflow-ontology-router" (plist))
(declare-function gptel-auto-experiment--is-retryable-error-p "gptel-tools-agent-error" (response))
(declare-function gptel-auto-workflow--project-root "gptel-tools-agent-benchmark" ())
(declare-function gptel-auto-workflow--valid-strategy-name-p "gptel-tools-agent-strategy-evolver" (name))

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
    "lisp/modules/gptel-tools-grep.el"
    ;; Critical files require human approval (validation-hard-block)
    "lisp/modules/gptel-auto-workflow-beads.el"
    "lisp/modules/gptel-auto-workflow-production.el"
    "lisp/modules/gptel-auto-workflow-strategic.el"
    "lisp/modules/gptel-auto-workflow-evolution.el"
    "lisp/modules/gptel-tools-agent-staging-baseline.el"
    "lisp/modules/gptel-tools-agent-prompt-build.el"
    "mementum/gtm/strategy-roadmap.md"
    "mementum/decisions/")
  "Targets to skip during headless workflow runs.
These modules define tools the executor actively depends on. Loading optimize
worktree edits for them into the live daemon can destabilize the run before the
worker restores the original file.

Also includes critical files that require human approval (validation-hard-block)."
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
Contains :strategy :hash :findings :source :controller-decision for mementum
tracking.
Reset after each run.")

(defun gptel-auto-workflow--research-trace-for-hash (research-hash)
  "Return persisted research trace plist matching RESEARCH-HASH, if any."
  (when (and (stringp research-hash) (not (string-empty-p research-hash)))
    (let ((trace-dir (expand-file-name "var/tmp/research-traces"
                                       (gptel-auto-workflow--effective-project-root)))
          trace)
      (when (file-directory-p trace-dir)
        (catch 'found
          (dolist (file (directory-files trace-dir t "\\.json\\'"))
            (when (string-match-p (regexp-quote research-hash)
                                  (file-name-nondirectory file))
              (condition-case nil
                  (let ((json-object-type 'plist)
                        (json-array-type 'list)
                        (json-key-type 'keyword))
                    (with-temp-buffer
                      (insert-file-contents file)
                      (setq trace (json-read)))
                    (throw 'found trace))
                (error nil))))))
      trace)))

(defun gptel-auto-workflow--research-context-from-findings (findings &optional source)
  "Return a persisted research context plist for FINDINGS.
SOURCE defaults to external when FINDINGS look like external research."
  (when (and (stringp findings) (not (string-empty-p findings)))
    (let* ((research-hash (sha1 findings))
           (trace (gptel-auto-workflow--research-trace-for-hash research-hash))
           (inferred-source
            (or source
                (plist-get trace :source)
                (if (and (fboundp 'gptel-auto-workflow--research-has-external-content-p)
                         (gptel-auto-workflow--research-has-external-content-p findings))
                    "external"
                  "internal"))))
      (list :strategy (or (plist-get trace :strategy) "persisted-findings")
            :hash research-hash
            :findings findings
            :digested (or (plist-get trace :digested) findings)
            :source inferred-source
            :research-variant (or (and (boundp 'research-variant) research-variant) "default")
            :controller-decision (or (plist-get trace :controller-decision) "persisted")
            :timestamp (format-time-string "%Y-%m-%dT%H:%M:%SZ")))))

(defun gptel-auto-workflow--ensure-research-context (findings &optional source)
  "Ensure `gptel-auto-workflow--current-research-context' exists for FINDINGS."
  (when (and (stringp findings) (not (string-empty-p findings)))
    (let ((research-hash (sha1 findings)))
      (unless (and (listp gptel-auto-workflow--current-research-context)
                   (equal (plist-get gptel-auto-workflow--current-research-context :hash)
                          research-hash))
        (setq gptel-auto-workflow--current-research-context
              (gptel-auto-workflow--research-context-from-findings findings source))))
    gptel-auto-workflow--current-research-context))

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

(defcustom gptel-auto-workflow-analyzer-time-budget 300
  "Minimum timeout in seconds for analyzer target selection.
Increased from 180→300s: all backends are slow from this network,
and a 180s timeout causes cascading failures (analyzer → static
targets → experiments all timeout). Better to wait longer for a
good analysis than to fall back to unfocused targets."
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
  "Non-nil when analyzer target selection failed due to a transient provider
issue.")

(defvar gptel-auto-workflow--analyzer-quota-exhausted nil
  "Non-nil when analyzer target selection hit provider quota limits.")

(defvar gptel-auto-workflow--analyzer-failed-backends nil
  "Backend names to skip when retrying analyzer target selection.")

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
            (append gptel-auto-workflow--analyzer-failed-backends
                    gptel-auto-workflow--rate-limited-backends))))))

(defun gptel-auto-workflow--normalized-cache-key (&optional proj-root)
  "Return normalized cache key for PROJ-ROOT.
Ensures consistent cache lookups across different path representations.
BEHAVIOR: Strips trailing slash only — does NOT strip the last directory
component.
FIX: Was using file-name-directory which returned the parent directory,
causing cache collisions between sibling projects."
  (let ((root (or proj-root
                  (gptel-auto-workflow--project-root)
                  (expand-file-name "~/.emacs.d/"))))
    (directory-file-name root)))


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
BEHAVIOR: Uses wc -l for efficient line counting without loading files into
buffer."
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
EDGE CASE: Only caches context when shell commands produce non-empty output.
BUG FIX: Uses `equal' not `eq' for cache key comparison — `eq' on strings
compares object identity, causing cache misses when a freshly-computed
string has the same content but different identity."
  (let* ((proj-root (gptel-auto-workflow--effective-project-root))
         (cache-ttl (* 5 60))
         (now (float-time))
         (cache-entry (and (listp gptel-auto-workflow--context-cache)
                           (equal (car gptel-auto-workflow--context-cache) proj-root)
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
            (message "[auto-workflow] Context gathering failed: shell commands returned empty; using
empty context")
            (list :git-history "" :file-sizes "" :todos "" :file-list "")))))))

(defun gptel-auto-workflow--local-research-patterns ()
  "Perform local analysis when external research is unavailable.
Returns structured findings from codebase analysis, recent experiment results,
and git history — providing actionable self-evolution data without internet.
MULTI-LAYER ANALYSIS: code patterns + experiment failures + git trends."
  (let ((proj-root (gptel-auto-workflow--effective-project-root))
        (sections nil))
    ;; Layer 1: Codebase anti-pattern scan
    (let ((patterns '(("cl-return-from" . "Missing cl-block wrapper")
                      ("ignore-errors" . "Swallows errors silently")
                      ("with-temp-buffer" . "May leak buffer state in async")
                      ("set-buffer" . "May affect global buffer state")
                      ("condition-case nil" . "Swallows all errors including quit"))))
      (dolist (pattern patterns)
        (let* ((cmd (format "cd %s && git grep -nc '%s' -- lisp/modules/ 2>/dev/null"
                            (shell-quote-argument proj-root)
                            (car pattern)))
               (output (string-trim (shell-command-to-string cmd))))
          (when (and output (not (string-empty-p output)))
            (let ((count (string-to-number output)))
              (when (> count 0)
                (push (format "- `%s`: **%d** occurrences — %s"
                              (car pattern) count (cdr pattern))
                      sections)))))))
    ;; Layer 2: Recent experiment failure patterns
    (let* ((experiments-dir (expand-file-name "var/tmp/experiments" proj-root))
           (recent-failures nil))
      (when (file-directory-p experiments-dir)
        (dolist (tsv-file (directory-files experiments-dir t "results\\.tsv\\'" t))
          (condition-case nil
              (with-temp-buffer
                (insert-file-contents tsv-file)
                (dolist (line (cdr (split-string (buffer-string) "\n" t)))
                  (let ((fields (split-string line "\t")))
                    (when (and (>= (length fields) 2)
                               (member (nth 1 fields) '("validation-failed" "discarded" "timeout")))
                      (push (nth 0 fields) recent-failures)))))
            (error nil))))
      (when recent-failures
        (let ((top-failures (seq-take (sort (cl-remove-duplicates recent-failures :test #'string=)
                                            (lambda (a b)
                                              (> (cl-count a recent-failures :test #'string=)
                                                 (cl-count b recent-failures :test #'string=))))
                                      5)))
          (push (format "## Recent Experiment Failures (%d total)\n\n%s"
                        (length recent-failures)
                        (mapconcat (lambda (f)
                                     (format "- `%s`: failed **%d** times" f
                                             (cl-count f recent-failures :test #'string=)))
                                   top-failures "\n"))
                sections))))
    ;; Layer 3: Git commit trend analysis
    (let* ((cmd (format "cd %s && git log --oneline -30 -- lisp/modules/ 2>/dev/null"
                        (shell-quote-argument proj-root)))
           (output (string-trim (shell-command-to-string cmd))))
      (when (and output (not (string-empty-p output)))
        (let ((fix-count (cl-count-if (lambda (line) (string-match-p "^[a-f0-9]+ ⊘" line))
                                      (split-string output "\n" t)))
              (feature-count (cl-count-if (lambda (line) (string-match-p "^[a-f0-9]+ λ\\|🔁" line))
                                          (split-string output "\n" t))))
          (push (format "## Git Activity (last 30 commits to lisp/modules/)\n\n- **%d** bug fixes\n- **%d** feature/evolution commits\n- Focus: %s"
                        fix-count feature-count
                        (if (> fix-count feature-count) "stabilization" "feature development"))
                sections))))
    ;; Layer 4: Module complexity hotspots
    (let* ((cmd (format "cd %s && find lisp/modules -name '*.el' -exec wc -l {} + 2>/dev/null | sort
-rn | head -5"
                        (shell-quote-argument proj-root)))
           (output (string-trim (shell-command-to-string cmd))))
      (when (and output (not (string-empty-p output)))
        (push (format "## Module Complexity (top 5 by lines)\n\n```\n%s\n```" output)
              sections)))
    ;; Compose final report
    (if sections
        (concat "## Local Codebase Analysis (fallback — external research unavailable)\n\n"
                "> Auto-generated from local git history, experiment results, and codebase
scan.\n\n"
                (mapconcat #'identity (nreverse sections) "\n\n")
                "\n\n**Self-Evolution Directive:** Focus on the highest-failure modules above. "
                "Apply nil-safety patterns and validation guards to reduce failure rates.")
      "")))

(defun gptel-auto-workflow--load-research-skill ()
  "Load evolved research findings from var/tmp/evolution/findings.md.
Returns findings content or empty string if not found."
  (let* ((file (expand-file-name "var/tmp/evolution/findings.md"
                                 (gptel-auto-workflow--effective-project-root)))
         (content (when (file-exists-p file)
                    (with-temp-buffer
                      (insert-file-contents file)
                      (buffer-string)))))
    (if (or (null content) (string-empty-p content))
        ""
      (progn
        (message "[research] Loaded evolved findings (%d chars)" (length content))
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

(defun gptel-auto-workflow--json-read-hash-safe (file)
  "Read JSON FILE into a hash-table without maphash corruption.
Reads as plist internally, then manually builds hash table to avoid
iterating JSON-created hash tables with maphash (Emacs 30.2 issue).
Returns nil if FILE is missing or unreadable.
ASSUMPTION: JSON contains plist structure (alternating key-value pairs).
ASSUMPTION: Nested hash structures are plists starting with keyword keys.
BEHAVIOR: Logs error type on failure for adaptive debugging.
EDGE CASE: Empty plist data returns empty hash table (not nil)."
  (when (file-readable-p file)
    (condition-case err
        (let ((json-object-type 'plist)
              (json-array-type 'list))
          (let* ((data (json-read-file file))
                 (ht (make-hash-table :test 'equal)))
            ;; BEHAVIOR: Early return for empty plist (not nil), ensuring
            ;; hash table is always returned when file is readable
            (when data
              (while data
                (let* ((key (pop data))
                       (val (pop data))
                       (inner-ht (and (consp val) (keywordp (car val))
                                      (make-hash-table :test 'equal))))
                  (if (and inner-ht (consp val) (keywordp (car val)))
                      (let ((inner val))
                        (while inner
                          (let ((ik (pop inner))
                                (iv (pop inner)))
                            (when (and ik iv)
                              (puthash (if (keywordp ik) (substring (symbol-name ik) 1) ik) iv inner-ht))))
                        (puthash key inner-ht ht))
                    (puthash key val ht)))))
            ht))
      ;; BEHAVIOR: Log error type for φ Vitality - builds on discoveries
      ;; that parsing errors occur and what types they are
      (json-error
       (message "[json] %s: JSON parse error in %s: %s"
                (file-name-nondirectory file) file (error-message-string err))
       nil)
      (file-error
       (message "[json] %s: File error reading %s: %s"
                (file-name-nondirectory file) file (error-message-string err))
       nil)
      (error
       (message "[json] %s: Unexpected error reading %s: %s"
                (file-name-nondirectory file) file (error-message-string err))
       nil))))

(defun gptel-auto-workflow--load-researcher-meta-learning ()
  "Load meta-learning data for researcher skill.
Reads topic-performance.json and enriches with ontology category data.
Returns nil if data not available."
  (let* ((data-dir (expand-file-name "assistant/skills/researcher-prompt/data" 
                                     (gptel-auto-workflow--effective-project-root)))
         (topic-file (expand-file-name "topic-performance.json" data-dir)))
    (when (file-exists-p topic-file)
      (condition-case err
          (let* ((data (gptel-auto-workflow--json-read-hash-safe topic-file))
                 (topics (when data (gethash "topics" data))))
            (when (and topics (hash-table-p topics))
              (let ((total-exp (gethash "total_experiments" data 0))
                    (total-kept 0)
                    ;; Ontology enrichment: per-category research impact
                    (cat-impact (gptel-auto-workflow--research-impact-by-category)))
                (maphash
                 (lambda (_topic-key stats)
                   (when (hash-table-p stats)
                     (setq total-kept (+ total-kept (gethash "kept" stats 0)))))
                 topics)
                (list :effectiveness (if (> total-exp 0)
                                         (round (/ (* 100.0 total-kept) total-exp))
                                       0)
                      :kept total-kept
                      :total total-exp
                      :topics topics
                      :category-impact cat-impact))))  ; ontology enrichment
        (error 
         (message "[research] Error loading meta-learning data: %s" err)
         nil)))))

(defun gptel-auto-workflow--research-impact-by-category ()
  "Compute per-category research impact from experiment outcomes.
Returns formatted string showing which categories benefit from research,
or nil if insufficient data."
  (let* ((results (condition-case nil (gptel-auto-workflow--parse-all-results) (error nil)))
         (cat-stats (make-hash-table :test 'equal))
         (parts nil))
    (when results
      (dolist (r results)
        (let* ((target (plist-get r :target))
               (kept (equal (plist-get r :decision) "kept"))
               (has-research (plist-get r :has-research))
               (cat (and target (fboundp 'gptel-auto-workflow--categorize-target)
                         (gptel-auto-workflow--categorize-target target))))
          (when cat
            (let ((entry (gethash cat cat-stats (list :total 0 :kept 0 :with-research 0 :kept-with-research 0))))
              (setf (plist-get entry :total) (1+ (plist-get entry :total)))
              (when kept (setf (plist-get entry :kept) (1+ (plist-get entry :kept))))
              (when has-research
                (setf (plist-get entry :with-research) (1+ (plist-get entry :with-research)))
                (when kept (setf (plist-get entry :kept-with-research) (1+ (plist-get entry :kept-with-research)))))
              (puthash cat entry cat-stats))))))
    (maphash
     (lambda (cat stats)
       (let* ((with-r (plist-get stats :with-research))
              (kept-r (plist-get stats :kept-with-research))
              (total (plist-get stats :total))
              (rate (if (> with-r 0) (/ (float kept-r) with-r) 0))
              (need (if (> rate 0.1) "HIGH — continue" (if (> total 5) "LOW — skip" "INSUFFICIENT DATA"))))
         (when (>= total 3)
           (push (format "  %s: %.0f%% kept with research (%d/%d) → %s"
                         cat (* 100 rate) kept-r with-r need)
                 parts))))
     cat-stats)
    (when parts
      (concat "### Per-category research impact (ontology-enriched)\n"
              (mapconcat #'identity (nreverse parts) "\n")))))

(defun gptel-auto-workflow--substitute-researcher-variables (skill-content)
  "Substitute template variables in SKILL-CONTENT with meta-learning data.
Replaces {{research-effectiveness}}, {{kept-research}}, {{total-research}},
and {{topic-performance}} with live data.
Resilient: if SKILL.md was regenerated with hardcoded placeholder text by the
daemon's evolve_researcher.py, restores template variables before
substituting."
  (if (null skill-content)
      skill-content
    ;; RESTORE: convert hardcoded placeholders back to template variables.
    ;; The daemon's evolve_researcher.py regenerates SKILL.md with hardcoded
    ;; text each evolution cycle. This ensures the substitution always works.
    (setq skill-content
          (replace-regexp-in-string
           "Overall research effectiveness: [0-9.]+% ([0-9]+/[0-9]+ research-correlated experiments kept)"
           "Overall research effectiveness: {{research-effectiveness}}.0% ({{kept-research}}/{{total-research}} research-correlated experiments kept)"
           skill-content t t))
    (setq skill-content
          (replace-regexp-in-string
           "\\*No topic data available yet\\.\\*"
           "{{topic-performance}}\n\n{{research-champion}}\n\n{{ontology-gaps}}\n\n{{current-bottlenecks}}"
           skill-content t t))
    ;; RESTORE: The daemon's evolution cycle rewrites {{priority-repos}}
    ;; back into the full hardcoded repo list.  Detect and restore it.
    (setq skill-content
          (replace-regexp-in-string
           (concat "# Priority Repos to Explore .*?"
                   "\\(?:\n\\|.\\)*?"
                   "## Research Method Per Repo")
           "{{priority-repos}}\n\n## Research Method Per Repo"
           skill-content t t))
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
      ;; Inject AutoTTS strategy guidance from data/strategy-guidance.json
      (let ((guidance-json (gptel-auto-workflow--load-strategy-guidance-json)))
        (setq skill-content
              (replace-regexp-in-string
               "{{strategy-guidance}}"
               (if guidance-json
                   (gptel-auto-workflow--format-strategy-guidance-json guidance-json)
                 "*Controller not yet evolved.*")
               skill-content t t)))
      ;; Inject per-category research impact (ontology-enriched)
      (let ((cat-impact (plist-get meta-data :category-impact)))
        (when cat-impact
          (setq skill-content
                (replace-regexp-in-string
                 "{{category-impact}}" cat-impact
                 skill-content t t))))
      ;; Inject current executor bottlenecks so researcher targets real problems
      (let ((bottlenecks (gptel-auto-workflow--current-bottleneck-report)))
        (setq skill-content
              (replace-regexp-in-string
               "{{current-bottlenecks}}" bottlenecks
               skill-content t t)))
      ;; Inject AutoGo research champion for strategy guidance
      (let ((champion (gptel-auto-workflow--research-champion-report)))
        (setq skill-content
              (replace-regexp-in-string
               "{{research-champion}}" champion
               skill-content t t)))
      ;; Inject ontology knowledge gaps
      (let ((gaps (gptel-auto-workflow--ontology-gap-report)))
        (setq skill-content
              (replace-regexp-in-string
               "{{ontology-gaps}}" gaps
               skill-content t t)))
      ;; Inject priority repo URLs.  Keep the list short (3-4) so the
      ;; subagent can visit all within a single research turn's timeout.
      (let* ((repos
              '(("nucleus" . "AI prompting framework (VSM, lambda notation, Wu Xing)")
                ("mementum" . "Git-based AI memory (synthesis, recall protocol)")
                ("gptel" . "LLM backend integration -- new backends, tool APIs")))
             (repo-md
              (mapconcat
               (pcase-lambda (`(,name . ,desc))
                 (format "- **[%s](https://github.com/davidwuchn/%s)**: %s\n  - Read: AGENTS.md, README.md, recent commits\n  - Extract: 1-3 patterns applicable to Emacs Lisp AI agents"
                         name name desc))
               repos "\n")))
        (setq skill-content
              (replace-regexp-in-string
               "{{priority-repos}}" repo-md
               skill-content t t)))
      skill-content)))

(defun gptel-auto-workflow--current-bottleneck-report ()
  "Generate a bottleneck report showing what the executor is struggling with.
Returns markdown string listing over-experimented targets, low-keep-rate
files,
and timeout-heavy targets for the researcher to investigate."
  (let* ((results (and (fboundp 'gptel-auto-workflow--parse-all-results)
                       (ignore-errors (gptel-auto-workflow--parse-all-results))))
         (by-target (make-hash-table :test 'equal))
         (over-experimented nil)
         (lines nil))
    (when results
      (dolist (r results)
        (let ((target (plist-get r :target))
              (kept (equal (plist-get r :decision) "kept")))
          (when (stringp target)
            (let ((entry (or (gethash target by-target) (cons 0 0))))
              (cl-incf (car entry))
              (when kept (cl-incf (cdr entry)))
              (puthash target entry by-target)))))
      (maphash
       (lambda (target counts)
         (when (> (car counts) 10)
           (let ((keep-rate (if (> (car counts) 0)
                                (/ (float (cdr counts)) (car counts)) 0.0)))
             (push (cons target (list :total (car counts) :kept (cdr counts)
                                      :rate keep-rate))
                   over-experimented))))
       by-target)
      (when over-experimented
        (setq over-experimented
              (sort over-experimented
                    (lambda (a b) (> (plist-get (cdr a) :total)
                                     (plist-get (cdr b) :total)))))
        (push "## Current Executor Bottlenecks (research these problems)\n" lines)
        (push (format "> %d targets exceed max-experiments policy\n\n" (length over-experimented)) lines)
        (dolist (entry (seq-take over-experimented 5))
          (let ((detail (cdr entry)))
            (push (format "- **%s**: %d experiments (%.0f%% kept) — needs new approach\n"
                          (car entry)
                          (plist-get detail :total)
                          (* 100 (plist-get detail :rate)))
                  lines)))
        (push "\n**Researcher task**: find novel techniques for these high-attempt targets. Current strategies are failing.\n" lines)))
    (if lines
        (concat (mapconcat #'identity (nreverse lines) ""))
      "No executor bottlenecks detected. Continue with current research topics.\n")))

(defun gptel-auto-workflow--research-champion-report ()
  "AutoGo: report current research strategy champion for the researcher.
Returns markdown showing which strategy won and why."
  (if (and (boundp 'gptel-auto-workflow--research-strategies)
           gptel-auto-workflow--research-strategies
           (boundp 'gptel-auto-workflow--champion-strategy))
      (let ((champ gptel-auto-workflow--champion-strategy)
            (rate (or (and (boundp 'gptel-auto-workflow--champion-keep-rate)
                           gptel-auto-workflow--champion-keep-rate) 0.0)))
        (format "**Active Champion**: `%s` (keep-rate: %.0f%%)\n%s strategies competing. Focus
on techniques matching the champion's approach.\n"
                (or champ "none") (* 100 rate)
                (length gptel-auto-workflow--research-strategies)))
    "*No research champion yet — run more experiments to establish baselines.*\n"))

(defun gptel-auto-workflow--ontology-gap-report ()
  "Ontology: report knowledge gaps from experiment ontology.
Returns markdown listing under-explored categories and targets."
  (if (fboundp 'gptel-auto-workflow--generate-experiment-ontology)
      (let* ((onto (ignore-errors (gptel-auto-workflow--generate-experiment-ontology)))
             (classes (and onto (plist-get onto :classes)))
             (gaps nil))
        (when classes
          (dolist (c classes)
            (when (and (< (plist-get c :total) 5)
                       (string= (plist-get c :status) "underperforming"))
              (push (plist-get c :name) gaps)))
          (if gaps
              (format "## Ontology Knowledge Gaps (research these categories)\n\n%d under-explored
strategies:\n- %s\n"
                      (length gaps)
                      (mapconcat #'identity (seq-take gaps 5) "\n- "))
            "## Ontology Knowledge Gaps\n\nAll strategies have sufficient data. Focus on
improving keep-rates.\n")))
    "*Ontology unavailable — research general topics.*\n"))

(defun gptel-auto-workflow--detect-research-topic-trends ()
  "Detect emerging/declining research topics by comparing performance against
baseline.
Reads topic-performance.json, compares against stored baseline in
temporal-patterns.json,
updates emerging/mature/declining/unexplored classifications.
Called from evolution cycle — feeds into evolve_researcher.py via
temporal-patterns.json."
  (let* ((root (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                    (ignore-errors (gptel-auto-workflow--worktree-base-root))))
         (topic-file (and root (expand-file-name "assistant/skills/researcher-prompt/data/topic-performance.json" root)))
         (pattern-file (and root (expand-file-name "assistant/skills/researcher-prompt/data/temporal-patterns.json" root))))
    (when (and topic-file (file-readable-p topic-file))
      (let* ((json-object-type 'hash-table)
             (json-array-type 'list)
             (topic-data (json-read-file topic-file))
             (topics (gethash "topics" topic-data))
             (baseline (if (and pattern-file (file-readable-p pattern-file))
                           (condition-case nil (json-read-file pattern-file) (error nil))
                         (list (cons "patterns" (make-hash-table)))))
             (baseline-topics (when baseline
                                (let ((pats (gethash "patterns" baseline)))
                                  (when (hash-table-p pats)
                                    (let ((ht (make-hash-table :test 'equal)))
                                      (dolist (cat '(emerging mature declining unexplored))
                                        (let ((items (gethash (symbol-name cat) pats)))
                                          (when items
                                            (dolist (item items)
                                              (puthash item cat ht)))))
                                      ht)))))
             (emerging nil) (declining nil) (mature nil) (unexplored nil)
             (total-topics 0))
        (when (hash-table-p topics)
          (dolist (topic-key (hash-table-keys topics))
            (let* ((stats (gethash topic-key topics))
                   (rate (when (hash-table-p stats) (gethash "success_rate" stats 0)))
                   (total (when (hash-table-p stats) (gethash "total_experiments" stats 0)))
                   (prev-cat (when baseline-topics (gethash topic-key baseline-topics))))
              (setq total-topics (1+ total-topics))
              (cond
               ((< total 3)
                (push topic-key unexplored))
               ((and (>= total 10) (>= rate 0.3))
                (push topic-key mature))
               ((and prev-cat (memq prev-cat '(emerging mature))
                     (< total 10))
                (push topic-key declining))
               ((and (> rate 0.2) (or (not prev-cat) (memq prev-cat '(unexplored declining))))
                (push topic-key emerging))
               ((>= total 5)
                (push topic-key mature))
               (t
                (push topic-key unexplored))))))
        (when (and pattern-file (> total-topics 0))
          (let ((patterns (make-hash-table :test 'equal)))
            (puthash "emerging" (vconcat (nreverse emerging)) patterns)
            (puthash "mature" (vconcat (nreverse mature)) patterns)
            (puthash "declining" (vconcat (nreverse declining)) patterns)
            (puthash "unexplored" (vconcat (nreverse unexplored)) patterns)
            (make-directory (file-name-directory pattern-file) t)
            (with-temp-file pattern-file
              (let ((json-object-type 'hash-table)
                    (json-array-type 'list))
                (insert (json-encode
                         (list (cons "version" (format-time-string "%Y-%m-%dT%H:%M:%SZ"))
                               (cons "patterns" patterns))))))
            (message "[topic-trends] %d topics analyzed: +%d emerging, %d mature, -%d declining, ?%d unexplored"
                     total-topics (length emerging) (length mature)
                     (length declining) (length unexplored))))))))

(defun gptel-auto-workflow--format-topic-performance (topics)
  "Format TOPICS hash-table as markdown table.
Returns placeholder message if TOPICS is nil or empty."
  (if (or (null topics)
          (not (hash-table-p topics))
          (zerop (hash-table-count topics)))
      "*No topic performance data available.*"
    (let ((topic-list nil))
      (maphash
       (lambda (topic-key stats)
         (when (hash-table-p stats)
           (let ((success-rate (gethash "success_rate" stats 0))
                 (total (gethash "total_experiments" stats 0))
                 (kept (gethash "kept" stats 0))
                 (trend (gethash "trend" stats "stable")))
             (push (list topic-key success-rate total kept trend) topic-list))))
       topics)
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

(defun gptel-auto-workflow--select-best-research-variant ()
  "Select a research variant by champion league (reuses strategy infrastructure).
Returns the variant file stem (e.g. \"nil-safety\") or nil for default."
  (let* ((variants-dir (expand-file-name
                        "assistant/strategies/research-variants"
                        (gptel-auto-workflow--effective-project-root)))
         (variant-files (when (file-directory-p variants-dir)
                          (directory-files variants-dir nil "\\.md\\'"))))
    (when variant-files
      (let* ((stems (mapcar (lambda (f) (file-name-sans-extension f)) variant-files))
             (chosen (if (and (boundp 'gptel-auto-workflow--champion-strategy)
                              gptel-auto-workflow--champion-strategy
                              (member gptel-auto-workflow--champion-strategy stems))
                         ;; Champion is a valid variant — use it
                         gptel-auto-workflow--champion-strategy
                       ;; No champion or not a variant — try PCR
                       (if (< (random 100) 20)  ; 20% explore
                           (nth (random (length stems)) stems)
                         (car stems)))))  ; default to first
        (message "[research-variant] Selected: %s" chosen)
        chosen))))

(defun gptel-auto-workflow--select-best-digest-variant ()
  "Select a digest variant by champion league.
Returns the variant file stem or nil for default."
  (let* ((variants-dir (expand-file-name
                        "assistant/strategies/digest-variants"
                        (gptel-auto-workflow--effective-project-root)))
         (variant-files (when (file-directory-p variants-dir)
                          (directory-files variants-dir nil "\\.md\\'"))))
    (when variant-files
      (let* ((stems (mapcar (lambda (f) (file-name-sans-extension f)) variant-files))
             (chosen (if (and (boundp 'gptel-auto-workflow--champion-strategy)
                              gptel-auto-workflow--champion-strategy
                              (member gptel-auto-workflow--champion-strategy stems))
                         gptel-auto-workflow--champion-strategy
                       (if (< (random 100) 20)
                           (nth (random (length stems)) stems)
                         (car stems)))))
        (message "[digest-variant] Selected: %s" chosen)
        chosen))))

(defun gptel-auto-workflow--load-digest-variant-content (variant-name)
  "Load DIGEST-VARIANT-NAME .md content, or nil if missing."
  (when variant-name
    (let ((vf (expand-file-name
               (format "assistant/strategies/digest-variants/%s.md" variant-name)
               (gptel-auto-workflow--effective-project-root))))
      (when (file-exists-p vf)
        (with-temp-buffer
          (insert-file-contents vf)
          (string-trim (buffer-string)))))))

(defun gptel-auto-workflow--load-research-variant-content (variant-name)
  "Load RESEARCH-VARIANT-NAME .md content, or nil if missing."
  (when variant-name
    (let ((vf (expand-file-name
               (format "assistant/strategies/research-variants/%s.md" variant-name)
               (gptel-auto-workflow--effective-project-root))))
      (when (file-exists-p vf)
        (with-temp-buffer
          (insert-file-contents vf)
          (string-trim (buffer-string)))))))

(defun gptel-auto-workflow--build-research-prompt ()
  "Build external research prompt by loading RESEARCHER.md skill.

The researcher prompt is defined in
assistant/skills/researcher-prompt/SKILL.md
so humans can easily review and edit it without touching code.

Meta-learning data (topic performance, source effectiveness) is dynamically
substituted into the template before building the prompt.

Results feed into directive's 'Next Hypotheses' for target selection."
  (let* ((raw-skill (gptel-auto-workflow--load-researcher-skill))
         (base-prompt (gptel-auto-workflow--substitute-researcher-variables raw-skill))
          (skill-content (gptel-auto-workflow--load-research-skill))
          ;; Research variant selected by champion league (reuses strategy infrastructure)
         (research-variant (gptel-auto-workflow--select-best-research-variant))
         (variant-content (gptel-auto-workflow--load-research-variant-content research-variant))
         ;; Load AutoTTS-style strategy guidance via {{strategy-guidance}} template injection only
         (source-guidance (when (fboundp 'gptel-auto-workflow--apply-source-priority-to-prompt)
                            (gptel-auto-workflow--apply-source-priority-to-prompt "")))
         (recent-outcomes (gptel-auto-workflow--build-recent-trace-outcomes-string)))
    (concat (or base-prompt "")
            "\n\n"
            (if variant-content
                (concat variant-content "\n\n")
              "")
            "## Dynamic Context\n\n"
            (if (string-empty-p skill-content)
                ""
              (concat "### Previously Discovered Insights\n"
                      "*Avoid re-reporting these. Build upon or contradict them.*\n\n"
                      skill-content
                      "\n\n"))
            (if (and recent-outcomes (not (string-empty-p recent-outcomes)))
                (concat "### Previous Research Outcomes (Last 14 Days)\n"
                        "*How recent research runs performed downstream. Prioritize what worked, avoid what failed.*\n\n"
                        recent-outcomes
                        "\n\n")
              "")
            (if (and source-guidance (not (string-empty-p source-guidance)))
                (concat "### Source Scheduling (AutoTTS)\n"
                        source-guidance
                        "\n\n")
              "")
            "### Recent Failure Patterns\n"
            (gptel-auto-workflow--research-topics-string)
            "Remember: Be specific. 'Use AI better' is banned. Focus on techniques we can
implement in Emacs Lisp.")))

(defun gptel-auto-workflow--build-recent-trace-outcomes-string ()
  "Build a compact summary of recent research trace outcomes.
Shows which strategies/sources produced kept vs discarded downstream
experiments.
Returns empty string when no trace data is available."
  (let* ((traces (condition-case nil
                     (gptel-auto-workflow--load-research-traces)
                   (error nil)))
         (recent (and traces
                      (seq-take traces (min 20 (length traces)))))
         (source-stats (make-hash-table :test 'equal))
         (lines nil))
    (when recent
      (dolist (trace recent)
        (let ((source (or (plist-get trace :source) "unknown"))
              (strategy (or (plist-get trace :strategy) "unknown"))
              (success (gptel-auto-workflow--trace-success-p trace))
              (known (gptel-auto-workflow--trace-outcome-known-p trace)))
          (when known
            (let* ((key (format "%s via %s" source strategy))
                   (stats (gethash key source-stats '(0 0))))
              (puthash key (list (+ (nth 0 stats) (if success 1 0))
                                 (1+ (nth 1 stats)))
                       source-stats)))))
      (dolist (key (hash-table-keys source-stats))
        (let ((stats (gethash key source-stats)))
          (when stats
            (let ((kept (nth 0 stats))
                  (total (nth 1 stats)))
              (when (> total 0)
                (push (format "- **%s**: %d/%d kept (%.0f%%)"
                              key kept total
                              (* 100 (/ (float kept) total)))
                      lines))))))
      (if lines
          (string-join (sort lines #'string<) "\n")
        ""))))

(defun gptel-auto-workflow--load-strategy-guidance-json ()
  "Load strategy guidance JSON from data/ directory.
When `gptel-auto-workflow--current-experiment-axis' is set, tries the
axis-specific file first (strategy-guidance-K.json), falling back to global.
Returns plist with beta, own-priority, etc, or nil if not found."
  (let* ((data-dir (expand-file-name "assistant/skills/researcher-prompt/data"
                                     (gptel-auto-workflow--effective-project-root)))
         (axis (and (boundp 'gptel-auto-workflow--current-experiment-axis)
                    gptel-auto-workflow--current-experiment-axis
                    (not (equal gptel-auto-workflow--current-experiment-axis "?"))
                    (format "%s" gptel-auto-workflow--current-experiment-axis)))
         (axis-file (when axis
                      (expand-file-name (format "strategy-guidance-%s.json"
                                                (string-remove-prefix ":" axis)) data-dir)))
         (file (if (and axis-file (file-exists-p axis-file))
                   axis-file
                 (expand-file-name "strategy-guidance.json" data-dir))))
    (when (file-exists-p file)
      (condition-case err
          (let ((json-object-type 'plist)
                (json-key-type 'keyword))
            (prog1 (json-read-file file)
              (when (and axis-file (file-exists-p axis-file))
                (message "[autotts] Using per-axis guidance for %s" axis))))
        (error
         (message "[research] Failed to load strategy guidance: %s" err)
         nil)))))

(defun gptel-auto-workflow--format-strategy-guidance-json (guidance)
  "Format strategy GUIDANCE plist as markdown.
GUIDANCE is a plist from strategy-guidance.json."
  (let ((beta (or (plist-get guidance :beta) 0.5))
        (own-prio (or (plist-get guidance :own-priority) 70))
        (ext-prio (or (plist-get guidance :ext-priority) 15))
        (stop (or (plist-get guidance :stop-threshold) 70))
        (budget (or (plist-get guidance :token-budget) 8000))
        (method (or (plist-get guidance :learning-method) "unknown"))
        (evolved-at (or (plist-get guidance :evolved-at) "unknown"))
        (based-on (or (plist-get guidance :based-on-traces) 0))
        (best-topic (plist-get guidance :best-topic))
        (best-rate (or (plist-get guidance :best-topic-rate) 0.0)))
    (format
     (concat "**Evolved Controller Config** (updated %s from %d traces, %s):\n\n"
             "- Beta: %.2f (0 conservative, 1 exploratory)\n"
             "- Own repo priority: %.0f%%\n"
             "- External priority: %.0f%%\n"
             "- Stop threshold: %.0f%% confidence\n"
             "- Token budget: %d\n"
             "%s"
             "\n**Decision Rules**:\n"
             "1. If EMA confidence stabilizes above %.0f%% + have URLs → STOP early\n"
             "2. If confidence is rising → CONTINUE current source type\n"
             "3. If EMA confidence stagnates → BRANCH to a different source/angle\n"
             "4. If > %d tokens → CUT (return what you have)\n"
             "5. Check own repos (davidwuchn/*) FIRST before external\n\n"
             "*This guidance auto-evolves after each pipeline run.*")
     evolved-at based-on method beta own-prio ext-prio stop budget
     (if (and best-topic (> best-rate 0))
         (format "- Best topic: **%s** (%.0f%% keeper rate from %d+ skill experiments)\n"
                 best-topic (* 100 best-rate)
                 (or based-on 0))
       "")
     stop budget)))

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
       ;; Full analysis: RETIRED — Python scripts removed 2026-06-03
       (message "[meta-learn] Post-batch: Python scripts retired — skipping analysis")
       (setq triggered t))
      
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



(defun gptel-auto-workflow--digest-research-findings (raw-findings callback)
  "Digest RAW-FINDINGS if needed. Preserves external content, only digests
unstructured data.
CALLBACK receives findings string.

Heuristic: if raw findings contain URLs or structured techniques, they are
already
usable and digestion would lose 80%+ of the content. Only digest raw HTML
dumps."
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
    (message "[auto-workflow] External research already structured (%d chars), skipping
digestion"
             (length raw-findings))
    (funcall callback raw-findings))
   ;; Local/internal patterns: pass through (already formatted by local-research-patterns)
   ((and (> (length raw-findings) 100)
         (string-match-p "Pattern:" raw-findings))
    (message "[auto-workflow] Internal patterns already formatted (%d chars), skipping
digestion"
             (length raw-findings))
    (funcall callback raw-findings))
   ;; Everything else: try to digest (raw HTML, unstructured text, etc.)
   (t
    (let* ((digest-variant (gptel-auto-workflow--select-best-digest-variant))
           (variant-content (gptel-auto-workflow--load-digest-variant-content digest-variant))
           (template (or variant-content
                         (when (fboundp 'gptel-auto-workflow--load-skill-content)
                           (gptel-auto-workflow--load-skill-content "research-digest"))))
           (digest-prompt
            (if template
                (gptel-auto-workflow--substitute-template
                 template
                 `((raw-findings . ,(truncate-string-to-width raw-findings 4000 nil nil "..."))))
              ;; Fallback to hardcoded prompt
              (format "You are a research digest specialist. Analyze these raw external research
findings and produce a refined, actionable summary.

RAW FINDINGS:
%s

DIGESTION TASK:
1. Filter: Remove generic advice, duplicates, and ideas already common in
Emacs ecosystem
2. Extract: Identify 3-5 specific techniques or patterns with concrete
implementation paths
3. Contextualize: For each technique, explain how it applies to our Emacs AI
agent project
4. Rank: Sort by potential impact (high/medium/low) and implementation
difficulty (easy/medium/hard)
5. Format: Use structured output suitable for feeding into an experiment
planning system

OUTPUT FORMAT (strict):
## Digest: External Research Insights

### Technique 1: [Name]
- **Source type**: [YouTube|GitHub|arXiv|X|HuggingFace|Reddit]
- **Impact**: [high|medium|low]
- **Difficulty**: [easy|medium|hard]
- **Description**: [2-3 sentences on what it is]
- **Application**: [Specific module or pattern in our project it could
improve]
- **Implementation sketch**: [Concrete first step, 1-2 sentences]

[Repeat for each technique]

### Summary for Directive
- **Top hypothesis**: [Best technique to try next]
- **Target modules**: [Which files to experiment on]
- **Expected improvement**: [What metric or capability would improve]

RULES:
- Be specific. 'Use AI better' is banned.
- Focus on techniques we haven't implemented (check: no clj-refactor, no LSP,
no tree-sitter)
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
                       (setq gptel-auto-workflow--current-research-context
                             (plist-put gptel-auto-workflow--current-research-context
                                        :digested digested))
                       (when digest-variant
                         (setq gptel-auto-workflow--current-research-context
                               (plist-put gptel-auto-workflow--current-research-context
                                          :digest-variant digest-variant))))
                     (funcall callback digested))))))
            (if (fboundp 'gptel-request)
                (gptel-request
                    digest-prompt
                  :callback digest-callback
                  :system "You are a research analyst specializing in AI agent architectures and Emacs Lisp tooling. You distill raw research into actionable engineering insights."
                  :timeout 60)
              (progn
                (message "[auto-workflow] gptel-request unavailable, using raw findings")
                (funcall callback raw-findings)))))))))


(defun gptel-auto-workflow--research-patterns (callback &optional retry-count)
  "Hunt for external ideas from internet sources with real-time controller.
CALLBACK receives DIGESTED research findings string.
Optional RETRY-COUNT tracks recursive retries (max 3, with provider failover).

AutoTTS Multi-Turn: Research is broken into multiple shorter turns
with controller checkpoints between them. Controller decides after
each turn whether to STOP, CONTINUE, BRANCH, or CUT.

Pipeline: External hunt → Controller checkpoint → [Continue/Stop] → Digest
ASSUMPTION: Subagent may or may not be available.
BEHAVIOR: Uses subagent with web tools if available, otherwise returns empty.
BEHAVIOR: On failure, activates provider failover and retries (max 3).
EDGE CASE: Returns empty findings if subagent unavailable.
META-LEARNING: Feeds findings to analyzer selection and the project research
cache."
  (cl-block gptel-auto-workflow--research-patterns
    ;; Guard against concurrent research calls
    (when gptel-auto-workflow--research-in-progress
      (message "[auto-workflow] Research already in progress, skipping concurrent call")
      (funcall callback "")
      (cl-return-from gptel-auto-workflow--research-patterns))
    (setq gptel-auto-workflow--research-in-progress t)
    (let ((research-prompt (gptel-auto-workflow--build-research-prompt))
          (attempt (or retry-count 0)))
      (let ((controller-config (gptel-auto-workflow--load-autotts-controller)))
        (message "[auto-workflow] Hunting external ideas (multi-turn controller)...")
        (gptel-auto-workflow--reset-research-steps)
        (message "[autotts] Controller: own-repo-priority=%.0f%%, stop-threshold=%.0f%%"
                 (* 100 (or (plist-get controller-config :own-repo-priority) 0.7))
                 (* 100 (or (plist-get controller-config :min-confidence-stop) 0.7)))
        (message "[debug] subagents-enabled=%s fbound=%s caller=%s attempt=%d"
                 gptel-auto-experiment-use-subagents
                 (fboundp 'gptel-benchmark-call-subagent)
                 (format-time-string "%H:%M:%S") attempt)
        (if (and gptel-auto-experiment-use-subagents
                 (fboundp 'gptel-benchmark-call-subagent))
            ;; Wrap callback with retry-on-failure logic
            (gptel-auto-workflow--run-research-turn
             research-prompt 0
             (lambda (findings)
               ;; If findings are empty or too short, activate failover and retry
               (if (and (or (null findings) (string-empty-p findings)
                            (< (length findings) 100))
                        (< attempt 3)
                        (fboundp 'gptel-auto-workflow--activate-provider-failover))
                   (progn
                     (message "[auto-workflow] Research produced empty/short findings (%d chars, attempt %d);
failover and retry"
                              (if findings (length findings) 0) (1+ attempt))
                     (when-let* ((preset (and (boundp 'gptel-agent-preset) gptel-agent-preset))
                                 (backend (plist-get preset :backend)))
                       (gptel-auto-workflow--activate-provider-failover
                        "researcher" preset "empty research output" t))
                     (setq gptel-auto-workflow--research-in-progress nil)
                     (let ((cb callback)
                           (att (1+ attempt)))
                       (run-with-timer 0 nil
                                       (lambda ()
                                         (gptel-auto-workflow--research-patterns cb att)))))
                 ;; Findings are good enough or retries exhausted
                 (progn
                   (setq gptel-auto-workflow--research-in-progress nil)
                   (funcall callback (or findings ""))))))
          (progn
            (message "[auto-workflow] Subagent unavailable - skipping external research")
            (setq gptel-auto-workflow--research-in-progress nil)
            (funcall callback "")))))))

(defun gptel-auto-workflow--ask-analyzer-for-targets (callback)
  "Ask analyzer LLM to select optimization targets.
CALLBACK receives list of target files.

When frontier data is available (from prior experiments), skip the
15,000-char AI prompt entirely and use data-driven ranking.  The
frontier ranks targets by Pareto frontier size — smallest first =
least explored = highest opportunity.  This is instant, requires
no AI call, and never times out.

Only calls the AI analyzer when frontier data is empty (first run
or TSV history was cleared).

VALIDATION: Guards frontier-targets with proper-list-p to prevent
runtime errors when frontier-select-targets returns a malformed value."
  (let* ((frontier-ranked
          (and (fboundp 'gptel-auto-experiment--frontier-select-targets)
               (condition-case nil
                   (gptel-auto-experiment--frontier-select-targets
                    gptel-auto-workflow-max-targets-per-run)
                 (error nil))))
         (frontier-targets (and (proper-list-p frontier-ranked)
                                (mapcar #'car frontier-ranked))))
    (if (and frontier-targets (> (length frontier-targets) 0))
        ;; Fast path: frontier data available — skip the AI call entirely.
        (let* ((ranked (seq-take frontier-ranked
                                 (* 2 gptel-auto-workflow-max-targets-per-run)))
               ;; Ontology scheduler: filter by category health
                (healthy (seq-filter
                          (lambda (pair)
                            (let* ((target (car pair))
                                   (cat (and (fboundp 'gptel-auto-workflow--categorize-target)
                                             (gptel-auto-workflow--categorize-target target)))
                                   (frozen (and cat (fboundp 'gptel-auto-workflow--category-frozen-p)
                                                (gptel-auto-workflow--category-frozen-p cat))))
                              (if frozen
                                  (progn (message "[scheduler] ⏭ %s — category %s FROZEN" target cat) nil)
                                t)))
                          ranked))
                ;; Filter out protected files that require human approval
                (unprotected (seq-filter
                             (lambda (pair)
                               (let ((target (car pair))
                                     (protected nil))
                                 (dolist (pattern gptel-auto-experiment--critical-files)
                                   (when (string-match-p (regexp-quote pattern) target)
                                     (setq protected t)
                                     (message "[scheduler] ⏭ %s — PROTECTED file" target)))
                                 (not protected)))
                             healthy))
                (targets (mapcar #'car (seq-take unprotected gptel-auto-workflow-max-targets-per-run))))
           (message "[auto-workflow] Frontier: %d ranked → %d healthy → %d unprotected (skipped %d
frozen, %d protected)"
                    (length frontier-ranked) (length healthy) (length targets)
                    (- (length ranked) (length healthy))
                    (- (length healthy) (length unprotected)))
          (funcall callback targets))
      ;; Slow path: no frontier data — call AI analyzer with the full prompt.
      (if gptel-auto-workflow-research-targets
          (gptel-auto-workflow--research-patterns
           (lambda (research-findings)
             (gptel-auto-workflow--ask-analyzer-with-findings research-findings callback)))
        (gptel-auto-workflow--ask-analyzer-with-findings
         (ignore-errors (gptel-auto-workflow-load-research-findings)) callback)))))

(defun gptel-auto-workflow--build-analyzer-prompt (context research-findings max-targets)
  "Build prompt for analyzer LLM target selection.
CONTEXT is the gathered context plist.
RESEARCH-FINDINGS is the research findings string or empty.
MAX-TARGETS is the maximum number of targets to select.
META-LEARNING: Loads evolved research skills from mementum."
  (unless (plistp context)
    (setq context '()))
  (let* ((research-skill (gptel-auto-workflow--load-research-skill))
         (research-section (if (and research-skill (not (string-empty-p research-skill)))
                               (format "RESEARCH STRATEGY GUIDE:\n%s\n\n"
                                       (truncate-string-to-width research-skill 800 nil nil "..."))
                             ""))
         ;; Inject category budget + regressed targets from cross-subsystem feedback
         (hints-section
          (let* ((hints (and (boundp 'gptel-auto-workflow--evolution-next-cycle-hints)
                             gptel-auto-workflow--evolution-next-cycle-hints))
                 (raw-budget (plist-get hints :category-budget))
                 (budget (cond
                          ((fboundp 'gptel-auto-workflow--normalize-category-budget)
                           (gptel-auto-workflow--normalize-category-budget raw-budget))
                          ((and (listp raw-budget) (keywordp (car raw-budget)))
                           (let ((tail raw-budget) entries)
                             (while tail
                               (let ((category (pop tail))
                                     (quota (pop tail)))
                                 (when (and (keywordp category) (numberp quota))
                                   (push (cons category quota) entries))))
                             (nreverse entries)))
                          (t raw-budget)))
                 (champion-prev (plist-get hints :prev-champions))
                 (regressed (plist-get hints :regressed-targets))
                 (parts nil))
            (when budget
              (push (format "CATEGORY BUDGET (experiments allocated per category):\n%s"
                            (mapconcat (lambda (b) (format "- %s: %d" (car b) (cdr b))) budget "\n"))
                    parts))
            (when champion-prev
              (push (format "CHAMPION CHANGES (last cycle):\n%s"
                            (mapconcat (lambda (c) (format "- %s: %s (%.1f%%)"
                                                           (car c) (cadr c) (* 100 (or (cddr c) 0))))
                                       champion-prev "\n"))
                    parts))
            (when regressed
              (push (format "REGRESSED TARGETS (knowledge pages removed, prioritized):\n%s"
                            (mapconcat (lambda (tgt) (format "- %s" (truncate-string-to-width tgt 60 nil nil "..."))) regressed "\n"))
                    parts))
            ;; Verbum gate: inject degraded backends + conflicted targets
            (when (and (fboundp 'gptel-auto-workflow--backend-health-level)
                       (boundp 'gptel-auto-workflow-headless-subagent-fallbacks))
              (let ((degraded nil))
                (dolist (entry gptel-auto-workflow-headless-subagent-fallbacks)
                  (let* ((backend (car entry))
                         (level (gptel-auto-workflow--backend-health-level backend)))
                    (when (>= level 2)
                      (push (format "- %s (level %d: %s)"
                                    backend level
                                    (gptel-auto-workflow--backend-health-label backend))
                            degraded))))
                (when degraded
                  (push (format "⚠ DEGRADED BACKENDS (reduced routing weight):\n%s"
                                (mapconcat #'identity (nreverse degraded) "\n"))
                        parts))))
            (when (and (boundp 'gptel-auto-workflow--conflicted-targets)
                       gptel-auto-workflow--conflicted-targets)
              (let ((deferred-str (mapconcat (lambda (c) (format "- %s (%.0f%% agreement)"
                                                                 (car c) (* 100 (cdr c))))
                                             (seq-take gptel-auto-workflow--conflicted-targets 5) "\n")))
                (push (format "⚠ DEFERRED TARGETS (backend disagreement — skip this cycle):\n%s" deferred-str)
                      parts)))
            (when (and (fboundp 'gptel-auto-workflow--query-experiments)
                       (boundp 'gptel-auto-workflow-targets)
                       gptel-auto-workflow-targets)
              (let ((sample-query (or (car gptel-auto-workflow-targets) "optimization"))
                    (similar (gptel-auto-workflow--query-experiments
                              (or (car gptel-auto-workflow-targets) "") 5)))
                (when similar
                  (push (format "SIMILAR PAST EXPERIMENTS (successful approaches on related files):\n%s"
                                (mapconcat (lambda (s)
                                             (format "- %s: %s (score=%.2f, %s)"
                                                     (truncate-string-to-width (plist-get s :target) 40 nil nil "...")
                                                     (truncate-string-to-width (plist-get s :hypothesis) 60 nil nil "...")
                                                     (plist-get s :score)
                                                     (plist-get s :decision)))
                                           similar "\n"))
                        parts))))
            (if parts (concat (mapconcat #'identity (nreverse parts) "\n") "\n\n") ""))))
    (format "You are a code analyzer. Select target files to optimize.

RULES:
1. ONLY output the JSON below. NO explanation, NO commentary, NO markdown.
2. Every target must exist in the INPUT files list.
3. Prioritize files with TODO/FIXME comments and recent git activity.
4. DO NOT select protected files: %s
5. Max %d targets.

OUTPUT FORMAT — copy this exactly:
{\"targets\": [{\"file\": \"lisp/modules/foo.el\", \"priority\": 1,
\"reason\": \"has 3 TODO comments and recent changes\"}]}

%s%sINPUT:
  files: %s
  git(30d): %s
  sizes(top20): %s
  todo/fixme(30): %s
  research: %s
  history: %s"
            (mapconcat #'identity gptel-auto-experiment--critical-files ", ")
            max-targets
            research-section
            (or hints-section "")
            (or (plist-get context :file-list) "")
            (or (plist-get context :git-history) "")
            (or (plist-get context :file-sizes) "")
            (or (plist-get context :todos) "")
            (if (or (null research-findings) (string-empty-p research-findings))
                "Not available (research disabled)"
              (let* ((lines (split-string research-findings "\n"))
                     (apply-lines (seq-filter (lambda (l) (string-match-p "\\*\\*Apply:\\*\\*" l)) lines))
                     (apply-section
                      (if apply-lines
                          (concat "\n### Actionable Research Patterns (match to files below)\n"
                                  (mapconcat #'identity apply-lines "\n")
                                  "\n\n")
                        "")))
                (concat apply-section
                        (truncate-string-to-width research-findings 3000 nil nil "..."))))
            (if (fboundp 'gptel-auto-workflow--evolution-get-knowledge)
                (gptel-auto-workflow--evolution-get-knowledge)
              "HISTORICAL SUCCESS PATTERNS (from past experiments):\n- Focus on bug fixes and
error handling for best results"))))

(defun gptel-auto-workflow--ask-analyzer-with-findings (research-findings callback)
  "Ask analyzer with optional RESEARCH-FINDINGS for target selection.
CALLBACK receives list of target files.
ASSUMPTION: my/gptel-agent-task-timeout may be unbound in some configurations.
EDGE CASE: Unbound timeout variable defaults to 0, letting
analyzer-time-budget govern."
  (let* ((context (gptel-auto-workflow--gather-context))
         (max-targets gptel-auto-workflow-max-targets-per-run)
          (analyzer-timeout (min (or (and (boundp 'my/gptel-agent-task-timeout)
                                          my/gptel-agent-task-timeout)
                                     gptel-auto-workflow-analyzer-time-budget)
                                 gptel-auto-workflow-analyzer-time-budget))
         (prompt (gptel-auto-workflow--build-analyzer-prompt
                  context research-findings max-targets)))
    (if (and gptel-auto-experiment-use-subagents
             (fboundp 'gptel-benchmark-call-subagent))
        (cl-labels
            ((request-analyzer (attempt)
               (let ((attempt-candidate
                      (gptel-auto-workflow--analyzer-failover-candidate)))
                 (gptel-benchmark-call-subagent
                  'analyzer
                  "Select targets"
                  prompt
                  (lambda (result)
                    (let* ((targets (gptel-auto-workflow--parse-targets result))
                           (failed-backend
                            (and (null targets)
                                 (or gptel-auto-workflow--analyzer-quota-exhausted
                                     gptel-auto-workflow--analyzer-transient-failure)
                                 (or (car-safe attempt-candidate)
                                     (and (plistp gptel-agent-preset)
                                          (gptel-auto-workflow--preset-backend-name
                                           (plist-get gptel-agent-preset :backend)))))))
                      (when (and failed-backend
                                 (not (member failed-backend
                                              gptel-auto-workflow--analyzer-failed-backends)))
                        (push failed-backend
                              gptel-auto-workflow--analyzer-failed-backends))
                      (if-let* ((candidate
                                 (and (< attempt 2)        ; max 3 total attempts
                                      (null targets)
                                      (or gptel-auto-workflow--analyzer-quota-exhausted
                                          gptel-auto-workflow--analyzer-transient-failure)
                                      (gptel-auto-workflow--analyzer-failover-candidate))))
                          (progn
                            (message "[auto-workflow] Retrying analyzer target selection with %s/%s (attempt %d,
delay %ds)"
                                     (car candidate)
                                     (cdr candidate)
                                     (1+ attempt)
                                     (* 5 (expt 2 attempt)))
                            (gptel-auto-workflow--clear-analyzer-error-state)
                            (let ((att (1+ attempt)))
                              (run-with-timer (* 5 (expt 2 (1- att))) nil
                                              (lambda () (request-analyzer att)))))
                        (funcall callback targets))))
                  analyzer-timeout))))
          (message "[auto-workflow] Asking analyzer to select targets...")
          (setq gptel-auto-workflow--analyzer-failed-backends nil)
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
          (let ((rel-path (ignore-errors (file-relative-name abs-path proj-root))))
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
Long responses (>1000 chars) are assumed successful and never flagged as
errors.
Only checks retryable-error patterns for short responses that look like error
messages."
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
CALLBACK must be a function; guarded with fallback on invalid input.
BEHAVIOR: Returns non-nil if error state was handled.
EDGE CASE: Non-nil but malformed targets (improper list, atom) caught before
downstream crash."
  (cl-block gptel-auto-workflow--handle-analyzer-error-state
    ;; CRITICAL: clear accumulated backend health strikes from analyzer retries.
    ;; The analyzer probes every backend; if all are slow (network issues),
    ;; every one gets a strike and experiments can't dispatch. Reset after
    ;; target selection so experiments see a clean slate.
    (condition-case nil
        (progn
          (when (and (boundp 'gptel-auto-workflow--lambda-strike-count)
                     (hash-table-p gptel-auto-workflow--lambda-strike-count))
            (clrhash gptel-auto-workflow--lambda-strike-count))
          (when (and (boundp 'gptel-auto-workflow--lambda-dead-until)
                     (hash-table-p gptel-auto-workflow--lambda-dead-until))
            (clrhash gptel-auto-workflow--lambda-dead-until)))
      (error nil))
    ;; Guard: validate callback, use no-op fallback if invalid
    (unless (functionp callback)
      (message "[auto-workflow] Error state handler: callback is not a function (%S)" callback)
      (setq callback (lambda (x) (message "[auto-workflow] Dropped result: %S" x))))
    ;; Check error conditions in priority order; return t after invoking callback
    (cond
     ((and gptel-auto-workflow--analyzer-quota-exhausted
           (not targets))
      (message "[auto-workflow] Analyzer quota exhausted; using static targets")
      (funcall callback static-targets)
      (cl-return-from gptel-auto-workflow--handle-analyzer-error-state t))
     ((and gptel-auto-workflow--analyzer-transient-failure
           (not targets))
      (message "[auto-workflow] Analyzer transient failure; using static targets")
      (funcall callback static-targets)
      (cl-return-from gptel-auto-workflow--handle-analyzer-error-state t))
     ((not targets)
      (message "[auto-workflow] Analyzer returned no targets; using static targets")
      (funcall callback static-targets)
      (cl-return-from gptel-auto-workflow--handle-analyzer-error-state t))
     ((not (proper-list-p targets))
      (message "[auto-workflow] Analyzer returned malformed targets (%S); using static targets" targets)
      (funcall callback static-targets)
      (cl-return-from gptel-auto-workflow--handle-analyzer-error-state t))
     (t nil))))

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
Strips markdown code fences, tries multiple start positions.
Returns nil if parsing fails or no targets found.
Logs parsing failures for debugging."
  (cl-block gptel-auto-workflow--parse-json-targets
    (unless (gptel-auto-workflow--nonempty-string-p response)
      (message "[auto-workflow] Empty response in parse-json-targets")
      (cl-return-from gptel-auto-workflow--parse-json-targets nil))
    (let ((cleaned (gptel-auto-workflow--strip-markdown-fences response))
          (result nil))
      (condition-case err
          (with-temp-buffer
            (insert cleaned)
            (goto-char (point-min))
            (while (and (null result)
                        (re-search-forward "[{[]" nil t))
              (goto-char (match-beginning 0))
              (condition-case json-err
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
                      (setq result
                            (gptel-auto-workflow--filter-valid-targets
                             candidates proj-root max-targets))))
                (json-error
                 (goto-char (1+ (match-beginning 0))) ; skip past broken {
                 nil)))
            result)
        (error
         (message "[auto-workflow] Target parse error: %s" (error-message-string err))
         nil)))))

(defun gptel-auto-workflow--strip-markdown-fences (text)
  "Extract content from markdown code fences if present.
Returns TEXT unchanged if no code fences found."
  (let ((trimmed (string-trim text)))
    (cond
     ((string-match "```[a-z]*\n\\(\\(?:.\\|\n\\)*?\\)```" trimmed)
      (string-trim (match-string 1 trimmed)))
     ((string-match "`\\([^`]+\\)`" trimmed)
      (match-string 1 trimmed))
     (t trimmed))))

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

(defun gptel-auto-workflow--semantic-target-augmentation (targets)
  "Augment TARGETS with semantically similar files from git-embed.
Returns augmented list with up to 2 semantic suggestions appended.
Does not duplicate existing targets."
  (when (and (fboundp 'gptel-auto-workflow--semantic-target-suggestions)
             (<= (length targets) 3))  ; Only augment when we have few targets
    (let ((semantic (gptel-auto-workflow--semantic-target-suggestions 2)))
      (dolist (s semantic)
        (unless (member s targets)
          (setq targets (append targets (list s)))
          (message "[auto-workflow] Semantic suggestion: %s" s)))))
  targets)

(defun gptel-auto-workflow--inject-queued-targets (targets)
  "Inject targets queued by pi Synthesis and pair-probe research into TARGETS
list.
Reads :cluster-queued and :research-probes from evolution-next-cycle-hints.
pi Synthesis: interleaves semantic cluster targets at weighted intervals
(research-probes at position 2, high-confidence clusters every 3rd slot,
medium-confidence clusters every 5th slot) instead of blind append.
Returns augmented target list without modifying the hints."
  (let* ((hints (and (boundp 'gptel-auto-workflow--evolution-next-cycle-hints)
                     gptel-auto-workflow--evolution-next-cycle-hints))
         (cluster-queued (when hints (plist-get hints :cluster-queued)))
         (research-probes (when hints (plist-get hints :research-probes)))
         (result (copy-sequence targets))
         (seen (make-hash-table :test 'equal))
         (high-conf nil)
         (medium-conf nil)
         (probes nil))
    (dolist (item targets) (puthash item item seen))
    ;; Classify queued entries by priority
    (dolist (entry cluster-queued)
      (when (plist-get entry :target)
        (let ((tgt (plist-get entry :target))
              (score (or (plist-get entry :score) 0.5)))
          (unless (gethash tgt seen)
            (puthash tgt t seen)
            (if (>= score 0.75)
                (push tgt high-conf)
              (push tgt medium-conf))))))
    (setq high-conf (nreverse high-conf)
          medium-conf (nreverse medium-conf))
    (dolist (entry research-probes)
      (when (plist-get entry :target)
        (let ((tgt (plist-get entry :target)))
          (unless (gethash tgt seen)
            (puthash tgt t seen)
            (push tgt probes)))))
    (setq probes (nreverse probes))
    ;; Interleave: build new list with weighted placement
    (let ((interleaved nil)
          (hi-idx 0) (med-idx 0) (probe-idx 0))
      (dotimes (i (length result))
        (push (nth i result) interleaved)
        ;; Research probes every 2nd position (highest priority)
        (when (and (= 1 (mod i 2)) (< probe-idx (length probes)))
          (push (nth probe-idx probes) interleaved)
          (setq probe-idx (1+ probe-idx)))
        ;; High-confidence clusters every 3rd position
        (when (and (= 2 (mod i 3)) (< hi-idx (length high-conf)))
          (push (nth hi-idx high-conf) interleaved)
          (setq hi-idx (1+ hi-idx)))
        ;; Medium-confidence clusters every 5th position
        (when (and (= 4 (mod i 5)) (< med-idx (length medium-conf)))
          (push (nth med-idx medium-conf) interleaved)
          (setq med-idx (1+ med-idx))))
      ;; Append any remaining unplaced entries
      (while (< probe-idx (length probes))
        (push (nth probe-idx probes) interleaved)
        (setq probe-idx (1+ probe-idx)))
      (while (< hi-idx (length high-conf))
        (push (nth hi-idx high-conf) interleaved)
        (setq hi-idx (1+ hi-idx)))
      (while (< med-idx (length medium-conf))
        (push (nth med-idx medium-conf) interleaved)
        (setq med-idx (1+ med-idx)))
      (setq result (nreverse interleaved)))
    (when (> (length result) (length targets))
      (message "[inject] Interleaved %d queued targets (probes=%d hi=%d med=%d) -> %d total"
               (- (length result) (length targets))
               (length probes) (length high-conf) (length medium-conf)
               (length result)))
    result))

(defun gptel-auto-workflow--filter-deferred-targets (targets)
  "Remove TARGETS that are conflicted or holographically dead.
Conflicted: <50% backend agreement, deferred to next cycle.
Dead: >=5 attempts across all backends with 0% keep-rate, dropped permanently.
Returns filtered list."
  (if (not (and (boundp 'gptel-auto-workflow--conflicted-targets)
                gptel-auto-workflow--conflicted-targets))
      targets
    (let ((result nil) (deferred nil) (dead nil))
      ;; Load fresh review decisions each cycle
      (let ((decisions (gptel-auto-workflow--read-review-decisions)))
        (when (and decisions (> (hash-table-count decisions) 0))
          (setq gptel-auto-workflow--review-decisions decisions)))
      (dolist (target targets)
        (cond
         ;; Check human review decisions before deferring
         ((and gptel-auto-workflow--review-decisions
               (gethash target gptel-auto-workflow--review-decisions))
          (let ((dec (gethash target gptel-auto-workflow--review-decisions)))
            (pcase (plist-get dec :decision)
              ('approved
               (push target result)
               (message "[verbum] ✓ APPROVED %s (human override, route: %s)"
                        target (or (plist-get dec :backend) "any")))
              ('dropped
               (push target dead)
               (message "[verbum] ❌ DROPPED %s (human decision)" target))
              (_
               (push target deferred)
               (message "[verbum] ⚠ DEFERRED %s (pending review)" target)))))
         ((gptel-auto-workflow--target-conflicted-p target)
          (push target deferred)
          (message "[verbum] ⚠ DEFERRED %s (%.0f%% backend agreement)"
                   target (* 100 (gptel-auto-workflow--target-conflicted-p target))))
         ((and (fboundp 'gptel-auto-workflow--holographic-dead-targets)
               (assoc target (gptel-auto-workflow--holographic-dead-targets 5 0.0)))
          (push target dead)
          (message "[holographic] ⚠ DROPPED %s (≥5 attempts, 0%% keep — dead target)" target))
         (t (push target result))))
      (when deferred
        (message "[verbum] Deferred %d conflicted targets, dropped %d dead targets"
                 (length deferred) (length dead)))
      (nreverse result))))

;; ─── Conflicted Target Review Queue ───

(defvar gptel-auto-workflow--review-decisions nil
  "Hash table of human decisions on conflicted targets.
Key: target (string), value: plist with :decision (:approved/:dropped/:defer)
and optionally :backend (string) for approved targets.
Populated by --read-review-decisions from conflicted-review.md.")

(defvar gptel-auto-workflow--review-file nil
  "Path to conflicted target review file.
Defaults to mementum/knowledge/conflicted-review.md under project root.")

(defun gptel-auto-workflow--review-file-path ()
  "Return the path to the conflicted target review file."
  (or gptel-auto-workflow--review-file
      (expand-file-name "mementum/knowledge/conflicted-review.md"
                        (if (fboundp 'gptel-auto-workflow--worktree-base-root)
                            (gptel-auto-workflow--worktree-base-root)
                          user-emacs-directory))))

(defun gptel-auto-workflow--generate-conflicted-review (target-reports)
  "Generate a human-reviewable file for conflicted TARGET-REPORTS.
TARGET-REPORTS is a list of plists with :target, :ratio, :conflicts.
Writes to --review-file-path. Existing decisions are preserved."
  (let* ((path (gptel-auto-workflow--review-file-path))
         (dir (file-name-directory path))
         (existing-decisions (when (file-exists-p path)
                               (gptel-auto-workflow--read-review-decisions)))
         (reports (sort (copy-sequence target-reports)
                        (lambda (a b) (< (plist-get a :ratio) (plist-get b :ratio))))))
    (unless (file-directory-p dir)
      (make-directory dir t))
    (with-temp-file path
      (insert "# Conflicted Target Review\n\n")
      (insert (format "*Generated: %s | Pending: %d targets*\n\n"
                      (format-time-string "%Y-%m-%d %H:%M")
                      (length reports)))
      (insert "> Targets where <50% of backends agree on KIBC axis.\n")
      (insert "> Edit the status line and selection boxes below, then save.\n")
      (insert "> Decisions are re-read each cycle. Format:\n")
      (insert "> `**Status**: PENDING` / `**Status**: APPROVED (route: DeepSeek)` /
`**Status**: DROPPED`\n\n")
      (insert "---\n\n")
      (if (null reports)
          (insert "No conflicted targets pending review.\n")
        (dolist (report reports)
          (let* ((target (plist-get report :target))
                 (ratio (plist-get report :ratio))
                 (conflicts (plist-get report :conflicts))
                 (existing (when existing-decisions
                             (gethash target existing-decisions))))
            (insert (format "## Target: `%s`\n\n" target))
            (insert (format "- **Agreement**: %.0f%% (%s)\n"
                            (* 100 ratio)
                            (if conflicts
                                (format "%d backends disagree" (length conflicts))
                              "all backends")))
            (when conflicts
              (insert "- **Disagreeing backends**: ")
              (let ((votes nil))
                (dolist (c conflicts)
                  (push (format "`%s`→`%s` (expected `%s`)"
                                (plist-get c :backend)
                                (plist-get c :axis)
                                (plist-get c :expected))
                        votes))
                (insert (string-join (nreverse votes) ", ")))
              (insert "\n"))
            ;; Historical stats
            (when (fboundp 'gptel-auto-workflow--get-holographic-consensus)
              (let ((cons (gptel-auto-workflow--get-holographic-consensus target)))
                (when cons
                  (insert (format "- **Historical consensus**: %s axis, %d operations, %.0f%% confidence\n"
                                  (plist-get cons :axis)
                                  (or (plist-get cons :count) 0)
                                  (* 100 (or (plist-get cons :confidence) 0)))))))
            ;; Decision status
            (insert "\n**Status**: ")
            (cond
             ((and existing (eq (plist-get existing :decision) 'approved))
              (insert (format "APPROVED (route: %s)\n" (or (plist-get existing :backend) "any"))))
             ((and existing (eq (plist-get existing :decision) 'dropped))
              (insert "DROPPED\n"))
             (t
              (insert "PENDING\n")))
            (insert "\n- [ ] APPROVE → route to: `____`\n")
            (insert "- [ ] DROP → stop researching this target\n")
            (insert "- [ ] DEFER → try again next cycle\n\n")
            (insert "---\n\n"))))
      (insert "## Decision Log\n\n")
      (insert "*No decisions recorded yet.*\n"))
    (message "[verbum] Wrote conflicted target review: %s (%d targets)" path (length reports))
    path))

(defun gptel-auto-workflow--read-review-decisions ()
  "Parse conflicted-review.md for human decisions.
Returns a hash table of target → (:decision keyword :backend string-or-nil).
Call this before each cycle to pick up fresh decisions."
  (let* ((path (gptel-auto-workflow--review-file-path))
         (decisions (make-hash-table :test 'equal)))
    (when (file-exists-p path)
      (with-temp-buffer
        (insert-file-contents path)
        (goto-char (point-min))
        (let ((target nil) (status nil) (backend nil))
          (while (not (eobp))
            (cond
             ;; Find target header: ## Target: `file.el`
             ((looking-at "## Target: `\\([^`]+\\)`")
              (setq target (match-string 1)
                    status nil
                    backend nil))
             ;; Parse status line: **Status**: PENDING / APPROVED (route: DeepSeek) / DROPPED
             ((and target (looking-at "\\*\\*Status\\*\\*: \\([A-Z]+\\)"))
              (let ((word (match-string 1))
                    (line (buffer-substring (line-beginning-position) (line-end-position))))
                (cond
                 ((string= word "APPROVED")
                  (setq status 'approved)
                  (when (string-match "(route: \\([^)]+\\))" line)
                    (setq backend (match-string 1 line))))
                 ((string= word "DROPPED")
                  (setq status 'dropped))
                 ((string= word "PENDING")
                  (setq status nil)))))
             ;; Store decision at section boundary
             ((and target (looking-at "^##\\|^---\\|\\'"))
              (when status
                (puthash target (list :decision status :backend backend) decisions))
              (setq target nil status nil backend nil)))
            (forward-line 1))
          ;; Store last target
          (when (and target status)
            (puthash target (list :decision status :backend backend) decisions)))))
    (let ((count (hash-table-count decisions)))
      (when (> count 0)
        (message "[verbum] Read %d review decisions from %s" count path)))
    decisions))

(defun gptel-auto-workflow-select-targets (callback)
  "Select targets for optimization.
CALLBACK receives list of target files.
LLM decides if available, otherwise uses static list.
ASSUMPTION: gptel-auto-workflow--filter-frontier-saturated-targets returns a
list or nil.
EDGE CASE: External filter returns non-list value; listp guard prevents type
errors.
BEHAVIOR: Validates filtered result is a list before using it, falls back to
unfiltered targets."
  (when (functionp callback)
    (gptel-auto-workflow--clear-analyzer-error-state)
    (let* ((proj-root (gptel-auto-workflow--effective-project-root))
           (static-targets
            (gptel-auto-workflow--filter-valid-targets
             gptel-auto-workflow-targets
             proj-root
             gptel-auto-workflow-max-targets-per-run))
           (safe-targets (gptel-auto-workflow--filter-deferred-targets static-targets)))
      (if gptel-auto-workflow-strategic-selection
          (gptel-auto-workflow--ask-analyzer-for-targets
           (lambda (targets)
             (if (gptel-auto-workflow--handle-analyzer-error-state targets safe-targets callback)
                 nil  ; Error already handled
               (if (null targets)
                   (let* ((frontier-ranked
                           (and (fboundp 'gptel-auto-experiment--frontier-select-targets)
                                (gptel-auto-experiment--frontier-select-targets
                                 gptel-auto-workflow-max-targets-per-run)))
                          (frontier-targets (mapcar #'car frontier-ranked))
                          (effective-static (or safe-targets
                                                (and (fboundp 'gptel-auto-workflow--discover-targets)
                                                     (gptel-auto-workflow--discover-targets))))
                          ;; Frontier ranking first, static targets as padding
                          (merged (if frontier-targets
                                      (let ((remaining (- gptel-auto-workflow-max-targets-per-run
                                                          (length frontier-targets))))
                                        (append frontier-targets
                                                (seq-take (cl-remove-if (lambda (t2) (member t2 frontier-targets))
                                                                        effective-static)
                                                          (max 0 remaining))))
                                    effective-static))
                          (augmented (gptel-auto-workflow--semantic-target-augmentation merged)))
                     (message "[auto-workflow] Analyzer returned no targets; using frontier-ranked (%d) +
static (%d) = %d targets"
                              (length frontier-targets) (length effective-static) (length augmented))
                     (funcall callback augmented))
                 (let* ((filtered-targets (gptel-auto-workflow--filter-frontier-saturated-targets targets))
                        (final-targets (if (and filtered-targets (listp filtered-targets))
                                           filtered-targets
                                         targets))
                        ;; Pad with safe-targets when analyst returns fewer than max
                        (padded (if (and safe-targets
                                         (< (length final-targets) gptel-auto-workflow-max-targets-per-run))
                                    (append final-targets
                                            (seq-take (cl-remove-if (lambda (t2)
                                                                      (member t2 final-targets))
                                                                    safe-targets)
                                                      (- gptel-auto-workflow-max-targets-per-run
                                                         (length final-targets))))
                                  final-targets))
                        (budgeted-targets (if (fboundp 'gptel-auto-workflow--enforce-category-budget)
                                              (gptel-auto-workflow--enforce-category-budget padded)
                                            padded))
                        (augmented (gptel-auto-workflow--semantic-target-augmentation budgeted-targets))
                        (with-queued (gptel-auto-workflow--inject-queued-targets augmented)))
                   (unless (or (null filtered-targets) (listp filtered-targets))
                     (message "[auto-workflow] Frontier filter returned non-list (%S); using unfiltered targets"
                              filtered-targets))
                   (message "[auto-workflow] Analyzer selected %d targets, %d after frontier filtering"
                            (length targets) (length final-targets))
                   (funcall callback with-queued))))))
        (let* ((fallback-targets
                (or static-targets
                    (and (fboundp 'gptel-auto-experiment--frontier-select-targets)
                         (mapcar #'car (gptel-auto-experiment--frontier-select-targets
                                        gptel-auto-workflow-max-targets-per-run)))
                    (and (fboundp 'gptel-auto-workflow--discover-targets)
                         (gptel-auto-workflow--discover-targets))))
               (filtered-targets (if fallback-targets
                                     (gptel-auto-workflow--filter-frontier-saturated-targets fallback-targets)
                                   nil))
               (final-targets (if (and filtered-targets (listp filtered-targets))
                                  filtered-targets
                                fallback-targets))
               (budgeted-targets (if (fboundp 'gptel-auto-workflow--enforce-category-budget)
                                     (gptel-auto-workflow--enforce-category-budget final-targets)
                                   final-targets))
               (augmented (gptel-auto-workflow--semantic-target-augmentation budgeted-targets))
               (with-queued (gptel-auto-workflow--inject-queued-targets augmented)))
          (unless (or (null filtered-targets) (listp filtered-targets))
            (message "[auto-workflow] Frontier filter returned non-list (%S); using unfiltered targets"
                     filtered-targets))
          (message "[auto-workflow] Static/fallback: %d targets, %d after frontier filtering"
                   (length fallback-targets) (length final-targets))
          (funcall callback with-queued))))))

;;; ─── AutoTTS Trace Collection & Controller ───

(defvar gptel-auto-workflow--research-trace-dir
  (expand-file-name "var/tmp/research-traces")
  "Directory to save research traces for AutoTTS offline evaluation.")

(defvar gptel-auto-workflow--active-strategy nil
  "Currently active research strategy (evolved by benchmark system).")

(defun gptel-auto-workflow--load-active-strategy ()
  "Load persisted active strategy from var/tmp/researcher-strategy.json.
Called during research initialization to restore evolved strategy after daemon
restart."
  (when (and (null gptel-auto-workflow--active-strategy)
             (fboundp 'gptel-auto-workflow--worktree-base-root))
    (let ((strategy-file (expand-file-name "var/tmp/researcher-strategy.json"
                                           (gptel-auto-workflow--worktree-base-root))))
      (when (file-exists-p strategy-file)
        (condition-case nil
            (let* ((json-object-type 'plist)
                   (data (with-temp-buffer
                           (insert-file-contents strategy-file)
                           (goto-char (point-min))
                           (json-read))))
              (when (and (plist-get data :active-strategy)
                         (fboundp 'gptel-auto-workflow--valid-strategy-name-p)
                         (gptel-auto-workflow--valid-strategy-name-p
                          (plist-get data :active-strategy)))
                (setq gptel-auto-workflow--active-strategy
                      (plist-get data :active-strategy))
                (message "[autotts] Restored active strategy: %s"
                         gptel-auto-workflow--active-strategy)))
          (error nil))))))

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
Since we can't instrument subagent internals, we reconstruct from output.
EDGE CASE: nil or non-string OUTPUT returns nil safely."
  (when (stringp output)
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
      (let* ((json-start (string-match "```json" output))
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
    (reverse steps))))

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
                 :findings output
                 :output output
                 :prompt-length (length prompt)
                 :output-length (length output)
                 :has-urls (if (string-match-p "https?://" output) t nil)
                 :has-code (if (string-match-p "```" output) t nil)
                 :has-structure (if (string-match-p "## .*\\n" output) t nil)
                 :source (if (string-match-p "davidwuchn" output) "own-repo" "external")
                 :controller-decision (symbol-name (or controller-decision 'continue))
                 :confidence (or confidence (gptel-auto-workflow--estimate-confidence output))
                 :ema-conf (or (and (boundp 'gptel-auto-workflow--research-ema-conf)
                                    gptel-auto-workflow--research-ema-conf)
                               0.0)
                 :ema-delta (or (and (fboundp 'gptel-auto-workflow--research-ema-delta)
                                     (gptel-auto-workflow--research-ema-delta))
                                0.0)
                 :tokens-used (or tokens-used (/ (length output) 4))
                 ;; Step-level traces for AutoTTS offline evaluation
                 :steps all-steps
                 :step-count (length all-steps)
                 :turn-count (or (and (boundp 'gptel-auto-workflow--research-trace-log)
                                      (length gptel-auto-workflow--research-trace-log))
                                 1)
                 :trace-log (and (boundp 'gptel-auto-workflow--research-trace-log)
                                 gptel-auto-workflow--research-trace-log)
                 :metadata (list :tokens-estimate (/ (length output) 4)
                                 :confidence (or confidence (gptel-auto-workflow--estimate-confidence output))
                                 :step-count (length all-steps)
                                 :has-steps (if all-steps t nil)))))
      (with-temp-file trace-file
        (insert (gptel-auto-workflow--json-encode-plist trace-data)))
      (when (fboundp 'gptel-auto-workflow--research-cache-index-trace-file)
        (gptel-auto-workflow--research-cache-index-trace-file trace-file))
      (message "[autotts] Saved research trace: %s (%d steps)"
               (file-name-nondirectory trace-file)
               (or (length all-steps) 0)))))

(defun gptel-auto-workflow--estimate-confidence (output)
  "Estimate confidence score (0-1) from research output.
Heuristic based on AutoTTS confidence signals.
Returns 0.0 if OUTPUT is nil or not a string."
  (if (not (stringp output))
      0.0
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
      score)))

(defun gptel-auto-workflow--detect-research-topic (output-text)
  "Detect research topic from OUTPUT-TEXT.
Returns topic name string, or \='general\=' if unknown.
Topics: performance, nil-safety, error-handling, async, general."
  (let ((text (downcase (or output-text ""))))
    (cond
     ;; Performance indicators
     ((or (string-match-p "performance\\|benchmark\\|cache\\|speed\\|optimize\\|efficiency" text)
          (string-match-p "gptel-ext-context-cache\\|gptel-ext-retry" text))
      "performance")
     ;; Nil-safety indicators
     ((or (string-match-p "nil-safety\\|null\\|guard\\|sandbox\\|validation" text)
          (string-match-p "gptel-sandbox\\|gptel-ext-security" text))
      "nil-safety")
     ;; Error-handling indicators
     ((or (string-match-p "error-handling\\|exception\\|recover\\|retry" text)
          (string-match-p "gptel-ext-retry\\|gptel-ext-fsm" text))
      "error-handling")
     ;; Async indicators
     ((or (string-match-p "async\\|concurrent\\|parallel\\|loop" text)
          (string-match-p "gptel-agent-loop\\|gptel-ext-fsm" text))
      "async")
     (t "general"))))

(defun gptel-auto-workflow--get-topic-model (controller-config topic)
  "Get topic-specific model from CONTROLLER-CONFIG.
Returns topic model plist, or nil if not found."
  (let ((topic-models (plist-get controller-config :topic-models)))
    (when topic-models
      (cl-find-if (lambda (model)
                    (let ((model-topic (plist-get model :topic)))
                      (string= (if (keywordp model-topic)
                                   (substring (symbol-name model-topic) 1)
                                 model-topic)
                               topic)))
                  topic-models))))

(defun gptel-auto-workflow--get-self-evolution-topic-rate (topic)
  "Get keep rate for TOPIC from self-evolution experiment data.
Returns float 0-1, or nil if no data."
  (when (fboundp 'gptel-auto-workflow--parse-all-results)
    (let* ((results (ignore-errors (gptel-auto-workflow--parse-all-results)))
           (topic-results (cl-remove-if-not
                           (lambda (r)
                             (and (equal (plist-get r :decision) "kept")
                                  (string-match-p topic
                                                  (downcase (or (plist-get r :target) "")))))
                           results))
           (all-topic (cl-remove-if-not
                       (lambda (r)
                         (string-match-p topic
                                         (downcase (or (plist-get r :target) ""))))
                       results)))
      (when (> (length all-topic) 0)
        (/ (float (length topic-results)) (length all-topic))))))



(defun gptel-auto-workflow--statistical-prob-kept (controller-config output-length output-text)
  "Calculate P(kept) using learned statistical model.
CONTROLLER-CONFIG contains :model-intercept and :model-weights.
Returns probability as float, or nil if model not available.
Uses topic-specific model if available and topic detected."
  (let* ((topic (gptel-auto-workflow--detect-research-topic output-text))
         (topic-model (gptel-auto-workflow--get-topic-model controller-config topic))
         (use-topic-model (and topic-model
                               (> (or (plist-get topic-model :n-traces) 0) 3)))
         (intercept (if use-topic-model
                        (plist-get topic-model :intercept)
                      (plist-get controller-config :model-intercept)))
         (weights (if use-topic-model
                      (plist-get topic-model :weights)
                    (plist-get controller-config :model-weights))))
    (message "[autotts] Statistical model: %s (topic: %s, n=%d)"
             (if use-topic-model "topic-specific" "global")
             topic
             (or (if use-topic-model
                     (plist-get topic-model :n-traces)
                   (plist-get controller-config :model-n-traces)) 0))
    (when (and intercept weights)
      (let* ((has-urls (if (string-match-p "https?://" (or output-text "")) 1 0))
             (has-structure (if (string-match-p "## .*\n" (or output-text "")) 1 0))
             (has-code (if (string-match-p "```" (or output-text "")) 1 0))
             (source-own 1) ;; Assume own-repo for current context
             (confidence (gptel-auto-workflow--estimate-confidence (or output-text "")))
             (score (+ intercept
                       (* (or (plist-get weights :output_length) 0) output-length)
                       (* (or (plist-get weights :has_urls) 0) has-urls)
                       (* (or (plist-get weights :has_structure) 0) has-structure)
                       (* (or (plist-get weights :has_code) 0) has-code)
                       (* (or (plist-get weights :source_own) 0) source-own)
                       (* (or (plist-get weights :confidence) 0) confidence)
                       (* (or (plist-get weights :tokens_used) 0) (/ output-length 4))
                       (* (or (plist-get weights :step_count) 0) 1)))
             ;; Sigmoid
             (prob (/ 1.0 (+ 1.0 (exp (- score))))))
        (max 0.0 (min 1.0 prob))))))

;;; Periodic Research

(defun gptel-auto-workflow--research-file ()
  "Return path to research findings cache file."
  (expand-file-name "var/tmp/research-findings.md"
                    (gptel-auto-workflow--effective-project-root)))

(defun gptel-auto-workflow--research-fresh-enough-p (findings-file)
  "τ Wisdom: check if cached research is fresh enough to skip re-research.
Returns non-nil if the findings file is <1 hour old and has pattern content."
  (when (file-exists-p findings-file)
    (let* ((mtime (file-attribute-modification-time (file-attributes findings-file)))
           (age-seconds (- (float-time) (float-time mtime))))
      (when (< age-seconds 3600)  ; <1 hour old
        (with-temp-buffer
          (insert-file-contents findings-file)
          (goto-char (point-min))
          ;; Must have actual pattern content, not just header
          (> (count-lines (point-min) (point-max)) 5))))))

(defun gptel-auto-workflow-run-research (&optional completion-callback)
  "Run researcher and store findings to cache.
τ Wisdom: skips research if findings are fresh (<1h) and have content.
Call periodically to keep findings fresh.
Findings available to analyzer during target selection.
Findings are cached per-project.
When COMPLETION-CALLBACK is non-nil, call it after findings are cached."
  (interactive)
  (let* ((proj-root (gptel-auto-workflow--effective-project-root))
         (cache-key (gptel-auto-workflow--normalized-cache-key proj-root))
         (findings-file (gptel-auto-workflow--research-file)))
    ;; τ Wisdom: skip if cache is fresh enough
    (if (gptel-auto-workflow--research-fresh-enough-p findings-file)
        (progn
          (message "[research] τ Wisdom: skipping — findings still fresh (<1h)")
          (when completion-callback
            (let ((cached (or (gethash cache-key gptel-auto-workflow--research-findings-cache)
                              (ignore-errors (gptel-auto-workflow-load-research-findings)))))
              (funcall completion-callback cached))))
      (progn
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
              ;; Update dashboards after research completes
              (when (fboundp 'gptel-auto-workflow--update-gtm-dashboard)
                (condition-case err
                    (gptel-auto-workflow--update-gtm-dashboard findings)
                  (error (message "[dashboard] GTM update error: %s" err))))
               ;; Parse findings for innovation ideas
               (when (fboundp 'gptel-auto-workflow--innovation-queue-parse-findings)
                 (condition-case err
                     (let ((new-ideas (gptel-auto-workflow--innovation-queue-parse-findings findings)))
                       (when new-ideas
                         (message "[innovation] Queued %d new ideas from research"
                                  (length new-ideas))))
                   (error (message "[innovation] Parse error: %s" err))))
               ;; File beads from research findings (GTM → PMF)
               (when (fboundp 'gptel-auto-workflow--bead-file-from-research)
                 (condition-case err
                     (let ((bead-ids (gptel-auto-workflow--bead-file-from-research findings)))
                       (when bead-ids
                         (message "[bead] Filed %d beads from research findings"
                                  (length bead-ids))))
                   (error (message "[bead] Filing error: %s" err))))
               (when completion-callback
                 (funcall completion-callback findings)))))))))

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
      (gptel-auto-workflow--ensure-research-context file-findings)
      (message "[research] Loaded cached findings from disk for %s (%d chars)"
               proj-root (length file-findings))
      file-findings)
     ((and (stringp cached) (not (string-empty-p cached)))
      (gptel-auto-workflow--ensure-research-context cached)
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
    ;; The one-shot cron researcher queues an explicit job immediately after
    ;; loading this file. Avoid starting a competing implicit run first.
    (unless (gptel-auto-workflow--researcher-daemon-p)
      (gptel-auto-workflow-run-research))))

(defun gptel-auto-workflow--researcher-daemon-p ()
  "Return non-nil when running inside the dedicated researcher daemon."
  (or (equal (getenv "MINIMAL_EMACS_WORKFLOW_ROLE") "research")
      (equal (getenv "AUTO_WORKFLOW_EMACS_SERVER") "gtm-product-org")
      (equal (getenv "AUTO_WORKFLOW_EMACS_SERVER") "ov5-researcher")  ; backward compat
      (equal (or (daemonp) "") "gtm-product-org")
      (equal (or (daemonp) "") "ov5-researcher")  ; backward compat
      (and (boundp 'server-name)
           (or (equal server-name "gtm-product-org")
               (equal server-name "ov5-researcher")))))  ; backward compat

(defun gptel-auto-workflow-stop-periodic-research ()
  "Stop periodic researcher runs."
  (interactive)
  (when gptel-auto-workflow--research-timer
    (cancel-timer gptel-auto-workflow--research-timer)
    (setq gptel-auto-workflow--research-timer nil)
    (message "[research] Periodic research stopped")))

(defun gptel-auto-workflow-research-status ()
  "Show researcher status for current project.
When called interactively, displays formatted status.
When called programmatically, returns a status plist."
  (interactive)
  (let* ((proj-root (gptel-auto-workflow--effective-project-root))
         (cache-key (gptel-auto-workflow--normalized-cache-key proj-root))
         ;; Ensure nil-safety: initialize cache if needed
         (_ (when (null gptel-auto-workflow--research-findings-cache)
              (setq gptel-auto-workflow--research-findings-cache
                    (make-hash-table :test 'equal))))
         (findings (gethash cache-key gptel-auto-workflow--research-findings-cache))
         (cache-file (gptel-auto-workflow--research-file))
         (file-exists (file-exists-p cache-file))
         (file-attrs (and file-exists (file-attributes cache-file)))
         (file-size (or (and file-attrs (nth 7 file-attrs)) 0))
         (file-mtime (and file-attrs (nth 5 file-attrs)))
         (file-mtime-str (and file-mtime
                              (format-time-string "%Y-%m-%d %H:%M" file-mtime)))
         (status (list :running (timerp gptel-auto-workflow--research-timer)
                       :interval gptel-auto-workflow-research-interval
                       :project proj-root
                       :findings-cached (stringp findings)
                       :findings-length (if findings (length findings) 0)
                       :cache-file cache-file
                       :cache-file-exists file-exists
                       :cache-file-size file-size
                       :cache-file-mtime file-mtime-str)))
    ;; ASSUMPTION: Interactive calls expect visible output, programmatic calls expect return value
    ;; BEHAVIOR: Display formatted status when interactive, always return plist
    (when (called-interactively-p 'any)
      (message "[research] Status: %srunning | findings: %s (%d chars) | cache: %s"
               (if (plist-get status :running) "" "not ")
               (if (plist-get status :findings-cached) "cached" "none")
               (plist-get status :findings-length)
               (if (plist-get status :cache-file-exists)
                   (format "%s (%.1fKB, %s)"
                           (plist-get status :cache-file)
                           (/ (plist-get status :cache-file-size) 1024.0)
                           (plist-get status :cache-file-mtime))
                 "missing")))
    status))

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
    (progn
      (if (fboundp 'gptel-auto-workflow--evolve-research-strategy)
          (progn
            (message "[evolve] Running benchmark-based strategy evolution...")
            (gptel-auto-workflow--evolve-research-strategy)
            (message "[evolve] Strategy evolution complete"))
         ;; Fallback: Python scripts RETIRED 2026-06-03
         (message "[evolve] Python fallback retired — pure Elisp only"))
      (message "[evolve] Strategy evolution cycle complete"))))

;; Keep the AutoTTS-enhanced controller authoritative for interactive loads too.
;; The bootstrap already loads this after strategic.el; normal `require' needs the
;; same override path so runtime and cron use one controller implementation.
(let ((autotts-file (locate-library "strategic-daemon-functions")))
  (when autotts-file
    (load autotts-file nil 'nomessage)))

;; ─── Trace Synthesizer ───



(provide 'gptel-auto-workflow-strategic)

;;; gptel-auto-workflow-strategic.el ends here
