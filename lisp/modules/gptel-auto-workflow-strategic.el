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

(defvar gptel-auto-workflow--research-timer nil
  "Timer for periodic researcher runs.")

(defvar gptel-auto-workflow--last-research-findings ""
  "Cached research findings from last researcher run.")

(defun gptel-auto-workflow--discover-targets ()
  "Discover all Elisp files in lisp/modules/ as potential targets."
  (let* ((proj-root (gptel-auto-workflow--project-root))
         (modules-dir (and proj-root (expand-file-name "lisp/modules" proj-root)))
         (targets '()))
    (when (and modules-dir (file-directory-p modules-dir))
      (dolist (file (directory-files-recursively modules-dir "\\.el$"))
        (let ((rel-path (file-relative-name file proj-root)))
          (unless (or (string-match-p "-test\\.el$" file)
                      (string-match-p "-disabled\\.el$" file)
                      (string-match-p "/test/" file))
            (push rel-path targets)))))
    (reverse targets)))

(defun gptel-auto-workflow--gather-context ()
  "Gather context for LLM target selection.
Scans both lisp/modules/ and packages/ (forked packages)."
  (let* ((proj-root (gptel-auto-workflow--project-root)))
    (if proj-root
        (list :git-history (shell-command-to-string
                            (format "cd %s && git log --oneline -30 -- lisp/modules/ packages/ 2>/dev/null"
                                    proj-root))
              :file-sizes (shell-command-to-string
                           (format "cd %s && find lisp/modules packages -name '*.el' -type f -exec wc -l {} + 2>/dev/null | sort -rn | head -20"
                                   proj-root))
              :todos (shell-command-to-string
                      (format "cd %s && grep -rn 'TODO\\|FIXME\\|BUG\\|HACK' lisp/modules/ packages/ 2>/dev/null | head -30"
                              proj-root))
              :file-list (shell-command-to-string
                          (format "cd %s && find lisp/modules packages -name '*.el' -type f 2>/dev/null"
                                  proj-root)))
      (list :git-history "" :file-sizes "" :todos "" :file-list ""))))

(defun gptel-auto-workflow--research-patterns (callback)
  "Research code patterns.
CALLBACK receives research findings string.
Tells LLM how to use git grep for context."
  (let ((research-prompt "Analyze lisp/modules/ and packages/ for code issues.

Use Bash tool to run:
  git grep -n 'cl-return-from' -- lisp/modules/ packages/ | head -20
  git grep -n 'ignore-errors' -- lisp/modules/ packages/ | head -20

Report actionable issues only. Skip cleanup code, benchmarks, tests.
Format: file:line | issue | fix
Max 800 chars."))
    (message "[auto-workflow] Researching patterns...")
    (if (and gptel-auto-experiment-use-subagents
             (fboundp 'gptel-benchmark-call-subagent))
        (gptel-benchmark-call-subagent
         'researcher "Research patterns" research-prompt
         (lambda (result)
           (let ((findings (if (stringp result) result (format "%S" result))))
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

(defun gptel-auto-workflow--ask-analyzer-with-findings (research-findings callback)
  "Ask analyzer with optional RESEARCH-FINDINGS for target selection.
CALLBACK receives list of target files."
  (let* ((context (gptel-auto-workflow--gather-context))
         (max-targets gptel-auto-workflow-max-targets-per-run)
         (prompt (format "Select optimization targets for this Emacs Lisp project.

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

TASK: Select exactly %d files from lisp/modules/ or packages/ to optimize.

OUTPUT JSON ONLY:
{\"targets\": [{\"file\": \"lisp/modules/xxx.el\" or \"packages/xxx.el\", \"priority\": 1, \"reason\": \"why\"}]}"
                         (plist-get context :file-list)
                         (plist-get context :git-history)
                         (plist-get context :file-sizes)
                         (plist-get context :todos)
                         (if (string-empty-p research-findings)
                             "Not available (research disabled)"
                           (truncate-string-to-width research-findings 1000 nil nil "..."))
                         max-targets)))
    (if (and gptel-auto-experiment-use-subagents
             (fboundp 'gptel-benchmark-call-subagent))
        (progn
          (message "[auto-workflow] Asking analyzer to select targets...")
          (gptel-benchmark-call-subagent
           'analyzer
           "Select targets"
           prompt
           (lambda (result)
             (funcall callback (gptel-auto-workflow--parse-targets result)))))
      (funcall callback nil))))

(defun gptel-auto-workflow--validate-and-add-target (file proj-root targets max-targets)
  "Validate FILE and add to TARGETS if it exists.
Returns updated targets list.
;; ASSUMPTION: proj-root is a valid directory path
;; BEHAVIOR: Converts relative paths to absolute, checks existence, adds as relative
;; EDGE CASE: Returns targets unchanged if file doesn't exist or max reached
;; TEST: Verify file is added only if it exists and is within proj-root"
  (cond
   ((not (stringp file)) targets)
   ((>= (length targets) max-targets) targets)
   (t
    (let ((abs-path (if (file-name-absolute-p file)
                        file
                      (expand-file-name file proj-root))))
      (if (file-exists-p abs-path)
          (let ((rel-path (file-relative-name abs-path proj-root)))
            (if (member rel-path targets)
                targets
              (cons rel-path targets)))
        targets)))))

(defun gptel-auto-workflow--parse-targets (response)
  "Parse LLM RESPONSE to extract target file list."
  (let ((targets '())
        (proj-root (gptel-auto-workflow--project-root))
        (max-targets gptel-auto-workflow-max-targets-per-run))
    (when proj-root
      (condition-case _
          (with-temp-buffer
            (insert (if (stringp response) response (format "%S" response)))
            (goto-char (point-min))
            (when (re-search-forward "{" nil t)
              (goto-char (match-beginning 0))
              (let* ((data (json-read))
                     (target-list (plist-get data :targets)))
                (when (listp target-list)
                  (dolist (item target-list)
                    (when (and (< (length targets) max-targets)
                               (listp item))
                      (let ((file (plist-get item :file)))
                        (when (and file (stringp file))
                          (let ((abs-path (if (file-name-absolute-p file)
                                              file
                                            (expand-file-name file proj-root))))
                            (when (file-exists-p abs-path)
                              (push (file-relative-name abs-path proj-root) targets)))))))))))
        (error nil)))
    ;; Fallback: regex - matches files in subdirectories too
    (when (null targets)
      (with-temp-buffer
        (insert (if (stringp response) response (format "%S" response)))
        (goto-char (point-min))
        (while (and (< (length targets) max-targets)
                    (re-search-forward "\\(lisp/modules\\|packages\\)/[a-zA-Z0-9_/.-]+\\.el" nil t))
          (let ((file (match-string 0)))
            (let ((abs-path (expand-file-name file proj-root)))
              (when (file-exists-p abs-path)
                (cl-pushnew file targets :test #'equal)))))))
    (reverse targets)))

(defun gptel-auto-workflow-select-targets (callback)
  "Select targets for optimization.
CALLBACK receives list of target files.
LLM decides if available, otherwise uses static list."
  (when (functionp callback)
    (if gptel-auto-workflow-strategic-selection
        (gptel-auto-workflow--ask-analyzer-for-targets
         (lambda (targets)
           (if targets
               (progn
                 (message "[auto-workflow] Analyzer selected: %s" targets)
                 (funcall callback targets))
             (message "[auto-workflow] Using static targets")
             (funcall callback gptel-auto-workflow-targets))))
      (funcall callback gptel-auto-workflow-targets))))

;;; Periodic Research

(defun gptel-auto-workflow--research-file ()
  "Return path to research findings cache file."
  (expand-file-name "var/tmp/research-findings.md"
                    (gptel-auto-workflow--project-root)))

(defun gptel-auto-workflow-run-research ()
  "Run researcher and store findings to cache.
Call periodically to keep findings fresh.
Findings available to analyzer during target selection."
  (interactive)
  (message "[research] Starting periodic research...")
  (gptel-auto-workflow--research-patterns
   (lambda (findings)
     (setq gptel-auto-workflow--last-research-findings findings)
     (let ((file (gptel-auto-workflow--research-file)))
       (make-directory (file-name-directory file) t)
       (with-temp-file file
         (insert (format "# Research Findings\n\n> Updated: %s\n\n%s"
                         (format-time-string "%Y-%m-%d %H:%M")
                         findings)))
       (message "[research] Findings cached to %s (%d chars)"
                file (length findings))))))

(defun gptel-auto-workflow-load-research-findings ()
  "Load cached research findings from file.
Returns empty string if no cache exists."
  (if (not (string-empty-p gptel-auto-workflow--last-research-findings))
      (progn
        (message "[research] Using in-memory findings (%d chars)"
                 (length gptel-auto-workflow--last-research-findings))
        gptel-auto-workflow--last-research-findings)
    (let ((file (gptel-auto-workflow--research-file)))
      (if (file-exists-p file)
          (with-temp-buffer
            (insert-file-contents file)
            (goto-char (point-min))
            (forward-line 3)
            (let ((findings (buffer-substring (point) (point-max))))
              (message "[research] Loaded cached findings from %s (%d chars)"
                       file (length findings))
              findings))
        (progn
          (message "[research] No cached findings found at %s" file)
          "")))))

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
  "Show researcher status."
  (interactive)
  (list :running (timerp gptel-auto-workflow--research-timer)
        :interval gptel-auto-workflow-research-interval
        :findings-cached (not (string-empty-p gptel-auto-workflow--last-research-findings))
        :findings-length (length gptel-auto-workflow--last-research-findings)
        :cache-file (gptel-auto-workflow--research-file)))

(provide 'gptel-auto-workflow-strategic)

;;; gptel-auto-workflow-strategic.el ends here
