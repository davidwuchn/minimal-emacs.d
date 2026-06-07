;;; gptel-auto-workflow-approval-queue.el --- Human approval queue for high-risk proposals -*- lexical-binding: t -*-

;; Copyright (C) 2026 OV5 Self-Improving Architecture

;; Author: OV5 System
;; Keywords: automation, approval, human-in-the-loop, queue

;;; Commentary:

;; Approval queue for high-risk monitoring agent proposals.
;; Persists proposals as pending .sexp files, supports approve/reject/expiry,
;; and integrates with the monitoring agent's deploy-proposal function.
;; When deploy-action is "approval-required", proposals are enqueued here
;; instead of auto-deployed, closing the last gap in the OV5 self-improving loop.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

;; ── Configuration ──

(defcustom gptel-auto-workflow-approval-queue-expiry-seconds (* 7 24 60 60)
  "Seconds before a pending proposal is automatically marked expired.
Default is 7 days (604800 seconds).  Expired proposals are moved to
the decisions directory and cannot be approved."
  :type 'integer
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-approval-queue-dir "var/approval-queue"
  "Base directory for the approval queue, relative to `default-directory'.
Contains two subdirectories: pending/ for active proposals and
decisions/ for archived approved/rejected/expired proposals."
  :type 'string
  :group 'gptel-tools-agent)

;; ── File Path Helpers ──

(defun gptel-auto-workflow-approval-queue-file (proposal-id)
  "Return absolute path to the pending .sexp file for PROPOSAL-ID."
  (expand-file-name
   (concat "pending/" proposal-id ".sexp")
   (expand-file-name gptel-auto-workflow-approval-queue-dir)))

(defun gptel-auto-workflow-approval-queue-decisions-file (proposal-id)
  "Return absolute path to the archived decisions .sexp file for PROPOSAL-ID."
  (expand-file-name
   (concat "decisions/" proposal-id ".sexp")
   (expand-file-name gptel-auto-workflow-approval-queue-dir)))

;; ── Enqueue ──

(defun gptel-auto-workflow-approval-queue-enqueue (tested-proposal rollback-tag)
  "Persist TESTED-PROPOSAL as a pending approval queue entry.
ROLLBACK-TAG is the git rollback tag for emergency recovery.
Generates a stable proposal-id slug, writes a .sexp file to the
pending directory, and returns the full queue-entry plist.
Queue-entry plist keys: :id, :created-at, :expires-at, :status,
:source, :proposal, :risk, :component, :pattern-target, :rollback-tag."
  (let* ((risk (or (plist-get tested-proposal :risk) "unknown"))
         (component (or (plist-get tested-proposal :component) "unknown"))
         (ptarget (or (plist-get tested-proposal :pattern-target) "unknown"))
         (now (float-time))
         (timestamp (format-time-string "%Y%m%dT%H%M%S" now))
         (component-slug (replace-regexp-in-string
                          "[^a-zA-Z0-9]" "-" (downcase component)))
         (ptarget-slug (replace-regexp-in-string
                        "[^a-zA-Z0-9]" "-" (downcase ptarget)))
         (proposal-id (format "proposal-%s-%s-%s" timestamp component-slug ptarget-slug))
         (expires-at (+ now gptel-auto-workflow-approval-queue-expiry-seconds))
         (queue-entry
          (list :id proposal-id
                :created-at now
                :expires-at expires-at
                :status "pending"
                :source "monitoring-agent"
                :proposal tested-proposal
                :risk risk
                :component component
                :pattern-target ptarget
                :rollback-tag rollback-tag))
         (pending-dir
          (expand-file-name
           "pending"
           (expand-file-name gptel-auto-workflow-approval-queue-dir)))
         (filepath (gptel-auto-workflow-approval-queue-file proposal-id)))
    (make-directory pending-dir t)
    (with-temp-file filepath
      (prin1 queue-entry (current-buffer)))
    queue-entry))

;; ── Read Helpers ──

(defun gptel-auto-workflow-approval-queue--read-sexp-file (filepath)
  "Read and return the plist stored in FILEPATH (.sexp format).
Returns nil if file does not exist or cannot be read."
  (when (file-exists-p filepath)
    (with-temp-buffer
      (insert-file-contents filepath)
      (goto-char (point-min))
      (read (current-buffer)))))

;; ── List ──

(defun gptel-auto-workflow-approval-queue-list (&optional include-expired)
  "Return a list of pending queue entries sorted by :created-at ascending.
When INCLUDE-EXPIRED is non-nil, entries past their expiry are included.
Otherwise, expired entries are pruned first."
  (unless include-expired
    (gptel-auto-workflow-approval-queue-prune-expired))
  (let* ((pending-dir
          (expand-file-name
           "pending"
           (expand-file-name gptel-auto-workflow-approval-queue-dir)))
         (files
          (when (file-directory-p pending-dir)
            (directory-files pending-dir t "\\.sexp$")))
         (entries nil))
    (dolist (f files)
      (let ((entry (gptel-auto-workflow-approval-queue--read-sexp-file f)))
        (when entry
          (push entry entries))))
    (sort entries
          (lambda (a b)
            (< (or (plist-get a :created-at) 0.0)
               (or (plist-get b :created-at) 0.0))))))

;; ── Prune Expired ──

(defun gptel-auto-workflow-approval-queue-prune-expired ()
  "Mark expired pending proposals and move them to the decisions directory.
An entry is expired when (float-time) > its :expires-at value.
Returns the number of entries pruned."
  (let* ((pending-dir
          (expand-file-name
           "pending"
           (expand-file-name gptel-auto-workflow-approval-queue-dir)))
         (decisions-dir
          (expand-file-name
           "decisions"
           (expand-file-name gptel-auto-workflow-approval-queue-dir)))
         (files
          (when (file-directory-p pending-dir)
            (directory-files pending-dir t "\\.sexp$")))
         (now (float-time))
         (pruned 0))
    (make-directory decisions-dir t)
    (dolist (f files)
      (let ((entry (gptel-auto-workflow-approval-queue--read-sexp-file f)))
        (when (and entry
                   (> now (or (plist-get entry :expires-at) 0.0)))
          (let* ((id (plist-get entry :id))
                 (expired-entry (plist-put entry :status "expired"))
                 (dest (gptel-auto-workflow-approval-queue-decisions-file id)))
            (with-temp-file dest
              (prin1 expired-entry (current-buffer)))
            (delete-file f)
            (setq pruned (1+ pruned))))))
    pruned))

;; ── Interactive Review ──

(defun gptel-auto-workflow-approval-queue-review ()
  "Display pending approval queue entries in a temp buffer for interactive review."
  (interactive)
  (gptel-auto-workflow-approval-queue-prune-expired)
  (let ((entries (gptel-auto-workflow-approval-queue-list t))
        (buf (get-buffer-create "*Approval Queue*")))
    (with-current-buffer buf
      (erase-buffer)
      (if (null entries)
          (insert "No pending proposals in the approval queue.\n")
        (dolist (entry entries)
          (let* ((id (plist-get entry :id))
                 (status (plist-get entry :status))
                 (risk (plist-get entry :risk))
                 (component (plist-get entry :component))
                 (proposal (plist-get entry :proposal))
                 (desc (or (plist-get proposal :description) "N/A"))
                 (rollback (plist-get entry :rollback-tag))
                 (created (plist-get entry :created-at))
                 (expires (plist-get entry :expires-at)))
            (insert (format "─── Proposal: %s ───\n" id))
            (insert (format "  Status:      %s\n" status))
            (insert (format "  Risk:         %s\n" risk))
            (insert (format "  Component:    %s\n" component))
            (insert (format "  Description:  %s\n" desc))
            (insert (format "  Rollback tag: %s\n" rollback))
            (insert (format "  Created:      %s\n"
                           (format-time-string "%Y-%m-%d %H:%M:%S" created)))
            (insert (format "  Expires:      %s\n"
                           (format-time-string "%Y-%m-%d %H:%M:%S" expires)))
            (insert "\n"))))
      (goto-char (point-min)))
    (display-buffer buf)))

;; ── Approve ──

(defun gptel-auto-workflow-approval-queue-approve (proposal-id &optional note)
  "Approve proposal PROPOSAL-ID with optional NOTE.
Moves the entry from pending to decisions, setting :status to \"approved\",
:decision-at, :decision-by, and :decision-note.
Returns the updated plist, or nil if the proposal was not found."
  (let* ((filepath (gptel-auto-workflow-approval-queue-file proposal-id))
         (entry (gptel-auto-workflow-approval-queue--read-sexp-file filepath)))
    (when entry
      (let* ((updated (plist-put entry :status "approved"))
             (updated (plist-put updated :decision-at (float-time)))
             (updated (plist-put updated :decision-by "human"))
             (updated (plist-put updated :decision-note (or note "")))
             (dest (gptel-auto-workflow-approval-queue-decisions-file proposal-id)))
        (make-directory (file-name-directory dest) t)
        (with-temp-file dest
          (prin1 updated (current-buffer)))
        (delete-file filepath)
        updated))))

;; ── Reject ──

(defun gptel-auto-workflow-approval-queue-reject (proposal-id &optional note)
  "Reject proposal PROPOSAL-ID with optional NOTE.
Moves the entry from pending to decisions, setting :status to \"rejected\",
:decision-at, :decision-by, and :decision-note.
Returns the updated plist, or nil if the proposal was not found."
  (let* ((filepath (gptel-auto-workflow-approval-queue-file proposal-id))
         (entry (gptel-auto-workflow-approval-queue--read-sexp-file filepath)))
    (when entry
      (let* ((updated (plist-put entry :status "rejected"))
             (updated (plist-put updated :decision-at (float-time)))
             (updated (plist-put updated :decision-by "human"))
             (updated (plist-put updated :decision-note (or note "")))
             (dest (gptel-auto-workflow-approval-queue-decisions-file proposal-id)))
        (make-directory (file-name-directory dest) t)
        (with-temp-file dest
          (prin1 updated (current-buffer)))
        (delete-file filepath)
        updated))))

;; ── Pending Check ──

(defun gptel-auto-workflow-approval-queue-pending-p ()
  "Return non-nil if there are any pending (non-expired) proposals in the queue."
  (> (length (gptel-auto-workflow-approval-queue-list)) 0))

;; ── Summary ──

(defun gptel-auto-workflow-approval-queue-summary ()
  "Return a summary plist of the approval queue state.
Keys: :pending (count of non-expired pending), :expired (count of expired
in decisions dir), :oldest-created-at (float-time of oldest pending entry,
or 0.0 if none)."
  (let* ((pending-entries (gptel-auto-workflow-approval-queue-list))
         (pending-count (length pending-entries))
         (decisions-dir
          (expand-file-name
           "decisions"
           (expand-file-name gptel-auto-workflow-approval-queue-dir)))
         (expired-count 0)
         (oldest-created 0.0))
    ;; Count expired in decisions dir
    (when (file-directory-p decisions-dir)
      (let ((decision-files (directory-files decisions-dir t "\\.sexp$")))
        (dolist (f decision-files)
          (let ((entry (gptel-auto-workflow-approval-queue--read-sexp-file f)))
            (when (and entry
                       (equal (plist-get entry :status) "expired"))
              (setq expired-count (1+ expired-count)))))))
    ;; Find oldest pending
    (dolist (entry pending-entries)
      (let ((ca (or (plist-get entry :created-at) 0.0)))
        (when (or (= oldest-created 0.0) (< ca oldest-created))
          (setq oldest-created ca))))
    (list :pending pending-count
          :expired expired-count
          :oldest-created-at oldest-created)))

(provide 'gptel-auto-workflow-approval-queue)
;;; gptel-auto-workflow-approval-queue.el ends here