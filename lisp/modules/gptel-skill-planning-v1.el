;;; gptel-skill-planning-v1.el --- GPTel Planning Skill v1.1 Modules -*- lexical-binding: t -*-

;; Copyright (C) 2024 David Wu

;; Author: David Wu <davidwu@example.com>
;; Keywords: ai, planning, workflow

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Planning skill v1.1 modules for robust task handling.

;;; Code:

(require 'cl-lib)

(defun gptel-skill-plan-nil-guard (input)
  "Return error message if INPUT is nil or empty."
  (when (or (null input) (string-empty-p (string-trim input)))
    (user-error "No input provided. Please describe your task before planning.")))

(defun gptel-skill-plan-recover-session ()
  "Recover planning session from checkpoint.
Returns plist with :status, :plan-file, :progress-file, and :last-phase."
  (let ((plan-file "docs/plans/task_plan.md")
        (progress-file "docs/plans/progress.md")
        (last-phase nil)
        (status 'no-existing-session))
    (when (file-exists-p plan-file)
      (setq status 'plan-found)
      (message "Recovering session from %s" plan-file)
      ;; Parse plan file to find last phase
      (with-temp-buffer
        (insert-file-contents plan-file)
        (goto-char (point-min))
        (when (re-search-forward "\\(?:## \\|### \\)Phase [0-9]+: \\(.+\\)" nil t)
          (setq last-phase (match-string 1)))))
    (when (file-exists-p progress-file)
      (setq status 'progress-found)
      (message "Progress file found, resuming from last phase")
      ;; Parse progress file to find last completed action
      (with-temp-buffer
        (insert-file-contents progress-file)
        (goto-char (point-min))
        (when (re-search-forward "\\[x\\] \\(.*\\)" nil t)
          (message "Last completed: %s" (match-string 1)))))
    (list :status status
          :plan-file (when (file-exists-p plan-file) plan-file)
          :progress-file (when (file-exists-p progress-file) progress-file)
          :last-phase last-phase)))

(defun gptel-skill-plan-detect-conflict ()
  "Detect conflicting plan files.
Returns plist with :conflicts (list of files) and :resolution-needed (boolean)."
  (let ((plan-files (file-expand-wildcards "docs/plans/PLAN*.md"))
        (conflicts '())
        (resolution-needed nil)
        (most-recent nil))
    (when (> (length plan-files) 1)
      (setq resolution-needed t)
      (message "Warning: Multiple plan files detected (%d)" (length plan-files))
      ;; Compare timestamps to find most recent
      (setq most-recent (car (sort (copy-sequence plan-files)
                                   (lambda (a b)
                                     (time-less-p (file-attribute-modification-time
                                                   (file-attributes b))
                                                  (file-attribute-modification-time
                                                   (file-attributes a)))))))
      (dolist (file plan-files)
        (unless (equal file most-recent)
          (let ((file-time (file-attribute-modification-time (file-attributes file)))
                (recent-time (file-attribute-modification-time (file-attributes most-recent))))
            (push (list :file file
                        :time file-time
                        :age-seconds (float-time (time-subtract recent-time file-time)))
                  conflicts))))
      (message "Most recent: %s" most-recent)
      (message "Consider merging or archiving older versions"))
    (list :conflicts (if conflicts (cons most-recent conflicts) plan-files)
          :resolution-needed resolution-needed
          :most-recent (when (> (length plan-files) 1) most-recent))))
(defun gptel-skill-plan-should-skip-p (task)
  "Return t if TASK is too simple for planning."
  (or (gptel-skill-plan-single-action-p task)
      (gptel-skill-plan-no-dependencies-p task)
      (gptel-skill-plan-no-risk-p task)
      (gptel-skill-plan-familiar-task-p task)))

(defun gptel-skill-plan-single-action-p (task)
  "Check if TASK is a single action (< 5 min).
Uses keyword matching to identify simple operations."
  (let ((keywords '("rename" "move" "delete" "open" "show" "list" "cat" "read")))
    (cl-some (lambda (kw) (string-match-p kw task)) keywords)))

(defun gptel-skill-plan-no-dependencies-p (task)
  "Check if TASK has no dependencies.
Looks for dependency keywords like after, before, depends."
  (not (string-match-p (regexp-quote "after\\|before\\|depends") task)))

(defun gptel-skill-plan-no-risk-p (task)
  "Check if TASK has no risk factors.
Looks for dangerous operations like delete, remove, destroy, overwrite."
  (not (string-match-p (regexp-quote "delete\\|remove\\|destroy\\|overwrite") task)))

(defun gptel-skill-plan-familiar-task-p (task)
  "Check if TASK is familiar (done 5+ times).
Uses simple keyword matching as placeholder for task history tracking.
Returns t if task contains familiar patterns."
  (let ((familiar-patterns '("commit" "push" "test" "build" "compile"
                             "lint" "format" "deploy" "restart" "reload"))
        (match-count 0))
    (dolist (pattern familiar-patterns)
      (when (string-match-p pattern task)
        (cl-incf match-count)))
    ;; Consider task familiar if it matches 2+ known patterns
    (>= match-count 2)))

(defun gptel-skill-plan-3-strike-retry (action failures)
  "Handle repeated failures with mutation."
  (cond
   ((= failures 1)
    (message "Strike 1: Retrying same action")
    (gptel-skill-plan-retry-same action))
   ((= failures 2)
    (message "Strike 2: Retrying with modified approach")
    (gptel-skill-plan-retry-mutated action))
   ((>= failures 3)
    (message "Strike 3: Escalating to user")
    (gptel-skill-plan-escalate action failures))))

(defun gptel-skill-plan-retry-same (action)
  "Retry ACTION with same approach.
Returns plist with retry metadata."
  (message "Retry attempt 1: Same approach for %s" action)
  (list :status 'retry
        :action action
        :strike 1
        :approach 'same
        :timestamp (current-time-string)
        :message "Retrying with identical parameters"))

(defun gptel-skill-plan-retry-mutated (action)
  "Retry ACTION with mutated approach.
Applies different strategy or parameters to avoid previous failure.
Returns plist with retry metadata."
  (message "Retry attempt 2: Mutated approach for %s" action)
  (list :status 'retry-mutated
        :action action
        :strike 2
        :approach 'mutated
        :mutations '(:timeout-increase :alternative-method :simplified-scope)
        :timestamp (current-time-string)
        :message "Retrying with modified parameters and alternative approach"))

(defun gptel-skill-plan-escalate (action failures)
  "Escalate failed ACTION after FAILURES attempts.
Presents user with options: retry, skip, or abort.
Returns plist with escalation metadata."
  (message "Strike 3: Escalating after %d failures for %s" failures action)
  (let ((escalation-options '(:retry-with-user-guidance :skip-action :abort-task :manual-intervention)))
    (list :status 'escalated
          :action action
          :failures failures
          :options escalation-options
          :timestamp (current-time-string)
          :message "Action failed after 3 attempts. User intervention required."
          :recommended-action 'manual-intervention
          :error-summary (format "Action '%s' failed %d times with different approaches" action failures))))

(provide 'gptel-skill-planning-v1)

;;; gptel-skill-planning-v1.el ends here
