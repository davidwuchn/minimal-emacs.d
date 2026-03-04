;;; nucleus-mode-switch.el --- Mode transition handler for nucleus -*- lexical-binding: t; -*-

;; Author: David Wu
;; Version: 1.1.0
;;
;; Handles mode transitions (plan <-> agent) and injects appropriate
;; system reminders to break LLM context carryover.
;; Auto-attaches PLAN.md to gptel-context on plan-mode entry.

(require 'cl-lib)

;;; Variables

(defvar nucleus--plan-mode-active nil
  "Tracks whether we were previously in plan mode.")

(make-variable-buffer-local 'nucleus--plan-mode-active)

(defvar nucleus--auto-context-files nil
  "Files auto-attached to `gptel-context' by mode transitions.
Only these files are removed on mode exit (preserves user-added context).")

(make-variable-buffer-local 'nucleus--auto-context-files)

(defcustom nucleus-plan-context-files '("PLAN.md")
  "Files to auto-attach to `gptel-context' when entering plan mode.
Each entry is a filename (not path) to look for in the project root.
Files that don't exist are silently skipped."
  :type '(repeat string)
  :group 'gptel)

;;; Mode Transition Detection

(defun nucleus--check-mode-transition (&rest _)
  "Advice to run after `gptel--apply-preset'.

Detects plan<->agent transitions and injects a system reminder in both
directions to break the LLM out of its prior mode mindset.
Dedup guard: only fires when the tracked state actually changes."
  (when (and (boundp 'gptel--preset)
             gptel--preset)
    (let ((was-plan nucleus--plan-mode-active)
          (is-plan (eq gptel--preset 'gptel-plan))
          (is-agent (eq gptel--preset 'gptel-agent)))
      ;; Only act when the state actually changes (dedup guard)
      (unless (eq was-plan is-plan)
        (setq-local nucleus--plan-mode-active is-plan)
        (cond
         ((and was-plan is-agent)
          (nucleus--detach-plan-context)
          (nucleus--inject-build-mode-reminder))
         ((and (not was-plan) is-plan)
          (nucleus--attach-plan-context)
          (nucleus--inject-plan-mode-reminder)))))))

(defun nucleus--inject-build-mode-reminder ()
  "Inject a system reminder when switching from plan to build mode.

Inserts after the last assistant exchange, before the current prompt."
  (when (and (derived-mode-p 'gptel-mode)
             (boundp 'gptel--tracking-marker)
             gptel--tracking-marker)
    (save-excursion
      (let ((insert-pos (marker-position gptel--tracking-marker)))
        (when insert-pos
          (goto-char insert-pos)
          (let ((reminder
                 (concat "\n\n<system-reminder>\n"
                         "Your operational mode has changed from plan to build.\n"
                         "You are no longer in read-only mode.\n"
                         "You are permitted to make file changes, run shell commands,\n"
                         "and utilize your full toolkit as needed.\n"
                         "Confirm by beginning your next response with: "
                         "[Mode: Agent | Tools: full]\n"
                         "</system-reminder>\n")))
            (unless (looking-back (regexp-quote "<system-reminder>")
                                  (max 0 (- (point) 100)))
              (insert reminder))))))))

(defun nucleus--inject-plan-mode-reminder ()
  "Inject a system reminder when switching from build to plan mode.

Inserts after the last assistant exchange, before the current prompt."
  (when (and (derived-mode-p 'gptel-mode)
             (boundp 'gptel--tracking-marker)
             gptel--tracking-marker)
    (save-excursion
      (let ((insert-pos (marker-position gptel--tracking-marker)))
        (when insert-pos
          (goto-char insert-pos)
          (let ((reminder
                 (concat "\n\n<system-reminder>\n"
                         "Your operational mode has changed from build to plan.\n"
                         "You are now in read-only mode.\n"
                         "Do not attempt file changes or shell commands.\n"
                         "Use only read-only tools: Glob, Grep, Read.\n"
                         "Confirm by beginning your next response with: "
                         "[Mode: Plan | Tools: read-only]\n"
                         "</system-reminder>\n")))
            (unless (looking-back (regexp-quote "<system-reminder>")
                                  (max 0 (- (point) 100)))
              (insert reminder))))))))

;;; Plan Context Auto-Attach

(defun nucleus--find-project-root ()
  "Return project root directory, or `default-directory' as fallback."
  (or (when-let* ((proj (project-current)))
        (project-root proj))
      default-directory))

(defun nucleus--attach-plan-context ()
  "Auto-attach plan context files to `gptel-context'.
Adds files from `nucleus-plan-context-files' found in the project root.
Tracks which files were auto-added in `nucleus--auto-context-files'."
  (when (boundp 'gptel-context)
    (let ((root (nucleus--find-project-root)))
      (dolist (name nucleus-plan-context-files)
        (let ((path (expand-file-name name root)))
          (when (and (file-readable-p path)
                     (not (member path gptel-context)))
            (push path gptel-context)
            (push path nucleus--auto-context-files)
            (message "[nucleus] Plan context: attached %s" name)))))))

(defun nucleus--detach-plan-context ()
  "Remove auto-attached plan context files from `gptel-context'.
Only removes files that were added by `nucleus--attach-plan-context'."
  (when (and (boundp 'gptel-context) nucleus--auto-context-files)
    (dolist (path nucleus--auto-context-files)
      (when (member path gptel-context)
        (setq gptel-context (delete path gptel-context))
        (message "[nucleus] Plan context: detached %s"
                 (file-name-nondirectory path))))
    (setq nucleus--auto-context-files nil)))

;;; Integration

;;;###autoload
(defun nucleus-mode-switch-setup ()
  "Setup mode transition tracking."
  (advice-add 'gptel--apply-preset :after #'nucleus--check-mode-transition))

(provide 'nucleus-mode-switch)

;;; nucleus-mode-switch.el ends here
