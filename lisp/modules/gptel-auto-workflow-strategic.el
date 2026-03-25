;;; gptel-auto-workflow-strategic.el --- Strategic target selection for auto-workflow -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Commentary:
;; LLM-first target selection for auto-workflow.
;; Let the analyzer decide which files to optimize.

;;; Code:

(require 'gptel-tools-agent)

(defcustom gptel-auto-workflow-strategic-selection t
  "When non-nil, use LLM-based target selection.
When nil, use static targets from gptel-auto-workflow-targets."
  :type 'boolean
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-max-targets-per-run 3
  "Maximum targets to process in one auto-workflow run."
  :type 'integer
  :group 'gptel-tools-agent)

(defun gptel-auto-workflow--discover-targets ()
  "Discover all Elisp files in lisp/modules/ as potential targets."
  (let* ((proj-root (gptel-auto-workflow--project-root))
         (modules-dir (expand-file-name "lisp/modules" proj-root))
         (targets '()))
    (when (file-directory-p modules-dir)
      (dolist (file (directory-files-recursively modules-dir "\\.el$"))
        (let ((rel-path (file-relative-name file proj-root)))
          (unless (or (string-match-p "-test\\.el$" file)
                      (string-match-p "-disabled\\.el$" file)
                      (string-match-p "/test/" file))
            (push rel-path targets)))))
    (nreverse targets)))

(defun gptel-auto-workflow--gather-context ()
  "Gather context for LLM target selection.
Returns plist with git history, file sizes, TODOs."
  (let* ((proj-root (gptel-auto-workflow--project-root)))
    (list :git-history (shell-command-to-string
                        (format "cd %s && git log --oneline -30 -- lisp/modules/*.el 2>/dev/null"
                                proj-root))
          :file-sizes (shell-command-to-string
                        (format "cd %s && wc -l lisp/modules/*.el 2>/dev/null | sort -rn | head -15"
                                proj-root))
          :todos (shell-command-to-string
                  (format "cd %s && grep -n 'TODO\\|FIXME\\|BUG\\|HACK' lisp/modules/*.el 2>/dev/null | head -20"
                          proj-root))
          :file-list (shell-command-to-string
                       (format "cd %s && ls lisp/modules/*.el 2>/dev/null"
                               proj-root)))))

(defun gptel-auto-workflow--ask-analyzer-for-targets (callback)
  "Ask analyzer LLM to select optimization targets.
CALLBACK receives list of target files."
  (let* ((context (gptel-auto-workflow--gather-context))
         (prompt (format "Select optimization targets for this Emacs Lisp project.

FILES AVAILABLE:
%s

RECENT GIT HISTORY:
%s

FILES BY SIZE:
%s

KNOWN ISSUES (TODOs/FIXMEs):
%s

TASK: Select exactly 3 files from lisp/modules/ to optimize tonight.

OUTPUT JSON ONLY:
{\"targets\": [{\"file\": \"lisp/modules/xxx.el\", \"priority\": 1, \"reason\": \"why\"}]}"
                        (plist-get context :file-list)
                        (plist-get context :git-history)
                        (plist-get context :file-sizes)
                        (plist-get context :todos))))
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

(defun gptel-auto-workflow--parse-targets (response)
  "Parse LLM RESPONSE to extract target file list."
  (let ((targets '()))
    ;; Try JSON
    (condition-case nil
        (with-temp-buffer
          (insert (if (stringp response) response (format "%S" response)))
          (goto-char (point-min))
          (when (re-search-forward "{" nil t)
            (goto-char (match-beginning 0))
            (let* ((data (json-read))
                   (list (cdr (assq 'targets data))))
              (dolist (item list)
                (let ((file (cdr (assq 'file item))))
                  (when (and file (file-exists-p file))
                    (push file targets)))))))
      (error nil))
    ;; Fallback: regex
    (when (null targets)
      (with-temp-buffer
        (insert (if (stringp response) response (format "%S" response)))
        (goto-char (point-min))
        (while (re-search-forward "lisp/modules/[a-zA-Z0-9_-]+\\.el" nil t)
          (let ((file (match-string 0)))
            (cl-pushnew file targets :test #'equal)))))
    (nreverse targets)))

(defun gptel-auto-workflow-select-targets (callback)
  "Select targets for optimization.
CALLBACK receives list of target files.
LLM decides if available, otherwise uses static list."
  (if gptel-auto-workflow-strategic-selection
      (gptel-auto-workflow--ask-analyzer-for-targets
       (lambda (targets)
         (if targets
             (progn
               (message "[auto-workflow] Analyzer selected: %s" targets)
               (funcall callback targets))
           (message "[auto-workflow] Using static targets")
           (funcall callback gptel-auto-workflow-targets))))
    (funcall callback gptel-auto-workflow-targets)))

(provide 'gptel-auto-workflow-strategic)

;;; gptel-auto-workflow-strategic.el ends here