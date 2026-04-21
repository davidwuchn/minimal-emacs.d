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

(defcustom gptel-auto-workflow-research-interval (* 4 3600)
  "Interval in seconds between periodic researcher runs.
Default 4 hours. Set to 0 to disable periodic research.
Findings stored in var/tmp/research-findings.md for analyzer."
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

(defun gptel-auto-workflow--target-in-root-repo-p (abs-path proj-root)
  "Return non-nil when ABS-PATH belongs to the same git repo as PROJ-ROOT."
  (let ((project-git-root (locate-dominating-file proj-root ".git"))
        (target-git-root (locate-dominating-file
                          (file-name-directory (directory-file-name abs-path))
                          ".git")))
    (and project-git-root
         target-git-root
         (file-equal-p (expand-file-name project-git-root)
                       (expand-file-name target-git-root)))))

(defun gptel-auto-workflow--gather-context ()
  "Gather context for LLM target selection.
Scans only root-repo targets that can be integrated into staging."
  (let* ((proj-root (gptel-auto-workflow--effective-project-root))
         (safe-root (shell-quote-argument proj-root)))
    (list :git-history (shell-command-to-string
                        (format "cd %s && git log --oneline -30 -- lisp/modules/ 2>/dev/null"
                                safe-root))
          :file-sizes (shell-command-to-string
                       (format "cd %s && find lisp/modules -name '*.el' -type f -exec wc -l {} + 2>/dev/null | sort -rn | head -20"
                               safe-root))
          :todos (shell-command-to-string
                  (format "cd %s && grep -rn 'TODO\\|FIXME\\|BUG\\|HACK' lisp/modules/ 2>/dev/null | head -30"
                          safe-root))
          :file-list (shell-command-to-string
                      (format "cd %s && find lisp/modules -name '*.el' -type f 2>/dev/null"
                              safe-root)))))

(defun gptel-auto-workflow--research-patterns (callback)
  "Research code patterns.
CALLBACK receives research findings string.
Tells LLM how to use git grep for context."
  (let ((research-prompt "Analyze root-repo files under lisp/modules/ for code issues.

Use Bash tool to run:
  git grep -n 'cl-return-from' -- lisp/modules/ | head -20
  git grep -n 'ignore-errors' -- lisp/modules/ | head -20

Report actionable issues only. Skip cleanup code, benchmarks, tests.
Format: file:line | issue | fix
Max 800 chars."))
    (message "[auto-workflow] Researching patterns...")
    (if (and gptel-auto-experiment-use-subagents
             (fboundp 'gptel-benchmark-call-subagent))
        (gptel-benchmark-call-subagent
         'researcher "Research patterns" research-prompt
         (lambda (result)
           (let ((findings (gptel-auto-workflow--normalize-response result)))
             (message "[auto-workflow] Research complete: %d chars" (length findings))
             (funcall callback findings))))
      (funcall callback ""))))

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
MAX-TARGETS is the maximum number of targets to select."
  (format "Select optimization targets for this Emacs Lisp project.

FILES AVAILABLE:
%s

RECENT GIT HISTORY:
%s

FILES BY SIZE:
%s

KNOWN ISSUES (TODOs/FIXMEs):
%s

RESEARCH FINDINGS:
%s

TASK: Select exactly %d files from lisp/modules/ to optimize.
Do NOT choose files from packages/ or any nested git repo. Those are optimized separately and cannot be merged into the root staging branch by this workflow.

OUTPUT JSON ONLY:
{\"targets\": [{\"file\": \"lisp/modules/xxx.el\", \"priority\": 1, \"reason\": \"why\"}]}"
          (or (plist-get context :file-list) "")
          (or (plist-get context :git-history) "")
          (or (plist-get context :file-sizes) "")
          (or (plist-get context :todos) "")
          (if (or (null research-findings) (string-empty-p research-findings))
              "Not available (research disabled)"
            (truncate-string-to-width research-findings 1000 nil nil "..."))
          max-targets))

(defun gptel-auto-workflow--ask-analyzer-with-findings (research-findings callback)
  "Ask analyzer with optional RESEARCH-FINDINGS for target selection.
CALLBACK receives list of target files."
  (let* ((context (gptel-auto-workflow--gather-context))
         (max-targets gptel-auto-workflow-max-targets-per-run)
         (analyzer-timeout (max (or my/gptel-agent-task-timeout 0)
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

(defun gptel-auto-workflow--validate-and-add-target (file proj-root targets max-targets)
  "Validate FILE and add to TARGETS if it exists.
Returns updated targets list."
  (cond
   ((not (stringp file)) targets)
   ((>= (length targets) max-targets) targets)
   (t
    (let ((abs-path (if (file-name-absolute-p file)
                        file
                      (expand-file-name file proj-root)))
          (root-prefix (if (string-suffix-p "/" proj-root)
                           proj-root
                         (concat proj-root "/"))))
       (if (and (file-exists-p abs-path)
                (file-regular-p abs-path)
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

(defun gptel-auto-workflow--analyzer-transient-error-p (response)
  "Return non-nil when RESPONSE reflects a transient analyzer/provider failure."
  (and (gptel-auto-workflow--analyzer-error-p response)
       (gptel-auto-experiment--is-retryable-error-p response)))

(defun gptel-auto-workflow--filter-valid-targets (candidates proj-root max-targets)
  "Filter CANDIDATES to valid target files.
Returns list of validated relative paths, up to MAX-TARGETS."
  (when (null max-targets)
    (setq max-targets most-positive-fixnum))
  (let ((candidates-list (if (listp candidates) candidates (list candidates)))
        (results '()))
    (dolist (file candidates-list (reverse results))
      (unless (>= (length results) max-targets)
        (let ((new-results (gptel-auto-workflow--validate-and-add-target
                            file proj-root results max-targets)))
          (when (consp new-results)
            (setq results new-results)))))))

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
      (let ((targets (gptel-auto-workflow--parse-json-targets
                      normalized-response proj-root max-targets)))
        (if targets
            targets
          (progn
            (message "[auto-workflow] JSON parse failed, using regex fallback")
            (gptel-auto-workflow--parse-regex-targets
             normalized-response proj-root max-targets))))))))

(defun gptel-auto-workflow--json-object-p (value)
  "Return non-nil when VALUE looks like a JSON object alist."
  (and (consp value)
       (consp (car value))
       (symbolp (caar value))))

(defun gptel-auto-workflow--handle-analyzer-error-state (targets static-targets callback)
  "Handle analyzer error states and invoke CALLBACK with appropriate targets.
TARGETS is the analyzer result, STATIC-TARGETS is fallback list.
Returns non-nil if error state was handled."
  (cond
   ((and gptel-auto-workflow--analyzer-quota-exhausted
         (null targets))
    (message "[auto-workflow] Analyzer quota exhausted; using static targets")
    (funcall callback static-targets)
    t)
   ((and gptel-auto-workflow--analyzer-transient-failure
         (null targets))
    (message "[auto-workflow] Analyzer transient failure; using static targets")
    (funcall callback static-targets)
    t)
   ((null targets)
    (message "[auto-workflow] Analyzer returned no targets; using static targets")
    (funcall callback static-targets)
    t)
   (t nil)))

(defun gptel-auto-workflow--normalize-target-candidate (candidate)
  "Normalize parsed target CANDIDATE to a repo-relative path when possible."
  (cond
   ((not (stringp candidate)) nil)
   ((or (file-name-absolute-p candidate)
        (string-match-p "/" candidate))
    candidate)
   ((string-match-p "\\.el\\'" candidate)
    (concat "lisp/modules/" candidate))
   (t candidate)))

(defun gptel-auto-workflow--json-target-file (item)
  "Extract a target file path from parsed JSON ITEM."
  (cond
   ((stringp item)
    (gptel-auto-workflow--normalize-target-candidate item))
   ((gptel-auto-workflow--json-object-p item)
    (gptel-auto-workflow--normalize-target-candidate
     (or (cl-getf item 'file)
         (cl-getf item "file")
         (cl-getf item 'path)
         (cl-getf item "path")
         (cl-getf item 'target)
         (cl-getf item "target"))))
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
                      (or (cl-getf data 'targets)
                          (cl-getf data "targets")
                          (cl-getf data 'files)
                          (cl-getf data "files")
                          (cl-getf data 'paths)
                          (cl-getf data "paths")
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
LLM decides if available, otherwise uses static list."
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
               (progn
                 (message "[auto-workflow] Analyzer selected %d targets" (length targets))
                 (funcall callback targets)))))
        (funcall callback static-targets)))))

;;; Periodic Research

(defun gptel-auto-workflow--research-file ()
  "Return path to research findings cache file."
  (expand-file-name "var/tmp/research-findings.md"
                    (gptel-auto-workflow--effective-project-root)))

(defun gptel-auto-workflow-run-research ()
  "Run researcher and store findings to cache.
Call periodically to keep findings fresh.
Findings available to analyzer during target selection.
Findings are cached per-project."
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
                  proj-root (length findings)))))))

(defun gptel-auto-workflow-load-research-findings ()
  "Load cached research findings for current project.
Returns empty string if no cache exists.
Findings are cached per-project."
  (let* ((proj-root (gptel-auto-workflow--effective-project-root))
         (cache-key (gptel-auto-workflow--normalized-cache-key proj-root)))
    (let ((cached (gethash cache-key gptel-auto-workflow--research-findings-cache)))
      (if (and (stringp cached) (not (string-empty-p cached)))
          (progn
            (message "[research] Using in-memory findings for %s (%d chars)"
                     proj-root (length cached))
            cached)
        (let ((file (gptel-auto-workflow--research-file)))
          (if (file-exists-p file)
              (let ((findings
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
                         (if content-start
                             (buffer-substring content-start (point-max))
                           "")))))
                (puthash cache-key findings gptel-auto-workflow--research-findings-cache)
                (message "[research] Loaded cached findings for %s (%d chars)"
                         proj-root (length findings))
                findings)
            (progn
              (message "[research] No cached findings found for %s" proj-root)
              "")))))))

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
         (findings (or (gethash cache-key
                                gptel-auto-workflow--research-findings-cache
                                "")
                       "")))
    (list :running (timerp gptel-auto-workflow--research-timer)
          :interval gptel-auto-workflow-research-interval
          :project proj-root
          :findings-cached (and (stringp findings) (not (string-empty-p findings)))
          :findings-length (length findings)
          :cache-file (gptel-auto-workflow--research-file))))

(provide 'gptel-auto-workflow-strategic)

;;; gptel-auto-workflow-strategic.el ends here
