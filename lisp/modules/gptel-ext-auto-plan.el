;;; gptel-ext-auto-plan.el --- Auto-create planning files for multi-step tasks -*- lexical-binding: t; -*-

;; Author: David Wu
;; Version: 1.0.0
;;
;; Detects multi-step instructions in gptel responses and automatically
;; creates task_plan.md / findings.md / progress.md scaffolds.

;;; Code:

(require 'project)

;;; Customization

(defcustom my/gptel-auto-plan-enabled t
  "Whether to auto-create planning files for multi-step tasks."
  :type 'boolean
  :group 'gptel)

(defcustom my/gptel-auto-plan-min-steps 3
  "Minimum numbered steps to trigger planning file creation."
  :type 'integer
  :group 'gptel)

(defcustom my/gptel-auto-plan-safe-root nil
  "Optional safe root directory for auto-plan files.

When nil, auto-plan uses the project root if available and otherwise
falls back to `default-directory` only when it is not a home or temp dir."
  :type '(choice (const :tag "Auto" nil) directory)
  :group 'gptel)

;;; Internal Variables

(defvar-local my/gptel-planning-files-created nil
  "Non-nil when planning files have been created for this buffer.")

;;; Helpers

(defun my/gptel--count-numbered-steps (text)
  "Count numbered steps like \"1.\" or \"2)\" in TEXT."
  (let ((count 0)
        (pos 0))
    (while (string-match "^\\s-*\\([0-9]+\\)[.)]" text pos)
      (setq count (1+ count))
      (setq pos (match-end 0)))
    count))

(defun my/gptel--planning-signal-p (text)
  "Return non-nil when TEXT looks like a multi-step plan."
  (or (string-match-p "\\b\\(Steps\\|Plan\\|Phases\\)\\b" text)
      (> (length text) 400)))

(defun my/gptel--planning-files-present-p (dir)
  "Return non-nil if planning files already exist in DIR."
  (and (file-exists-p (expand-file-name "task_plan.md" dir))
       (file-exists-p (expand-file-name "findings.md" dir))
       (file-exists-p (expand-file-name "progress.md" dir))))

(defun my/gptel--home-or-temp-dir-p (dir)
  "Return non-nil when DIR is home or temporary."
  (let* ((dir (file-truename (file-name-as-directory dir)))
         (home (file-truename (file-name-as-directory (expand-file-name "~"))))
         (tmp (file-truename (file-name-as-directory temporary-file-directory))))
    (or (string= dir home)
        (string= dir tmp)
        (string-prefix-p tmp dir))))

(defun my/gptel--resolve-planning-dir ()
  "Return a safe directory for planning files or nil if unsafe."
  (cond
   ((and my/gptel-auto-plan-safe-root
         (file-directory-p my/gptel-auto-plan-safe-root))
    (file-name-as-directory (expand-file-name my/gptel-auto-plan-safe-root)))
   ((project-current)
    (project-root (project-current)))
   ((and (stringp default-directory)
         (file-directory-p default-directory)
         (not (my/gptel--home-or-temp-dir-p default-directory)))
    default-directory)
   (t nil)))

;;; Core

(defun my/gptel--maybe-create-planning-files (text)
  "Create planning files when TEXT contains multi-step instructions."
  (when (and my/gptel-auto-plan-enabled
             (bound-and-true-p gptel-mode)
             (not my/gptel-planning-files-created)
             (my/gptel--planning-signal-p text)
             (>= (my/gptel--count-numbered-steps text) my/gptel-auto-plan-min-steps))
    (when-let ((dir (my/gptel--resolve-planning-dir)))
      (let ((plan (expand-file-name "task_plan.md" dir))
            (findings (expand-file-name "findings.md" dir))
            (progress (expand-file-name "progress.md" dir)))
        (unless (my/gptel--planning-files-present-p dir)
          (with-temp-file plan
            (insert "# Task Plan\n\n## Goal\n- \n\n## Phases\n- [ ] Phase 1\n\n## Errors Encountered\n| Error | Attempt | Resolution |\n| --- | --- | --- |\n"))
          (with-temp-file findings
            (insert "# Findings\n\n"))
          (with-temp-file progress
            (insert "# Progress\n\n")))
        (setq my/gptel-planning-files-created t)))))

;;; Hook Registration

(add-hook 'gptel-post-response-functions
          (lambda (_start _end)
            (my/gptel--maybe-create-planning-files (buffer-string))))

;;; Footer

(provide 'gptel-ext-auto-plan)
;;; gptel-ext-auto-plan.el ends here
