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

;; ── Find Existing Pending ──

(defun gptel-auto-workflow-approval-queue--find-pending-by-target (component pattern-target)
  "Return list of pending entries matching COMPONENT and PATTERN-TARGET.
Returns nil if no matching pending entries exist."
  (let* ((pending-dir
          (expand-file-name
           "pending"
           (expand-file-name gptel-auto-workflow-approval-queue-dir)))
         (files (when (file-directory-p pending-dir)
                  (directory-files pending-dir t "\\.sexp$")))
         (matches nil))
    (dolist (f files)
      (let ((entry (gptel-auto-workflow-approval-queue--read-sexp-file f)))
        (when (and entry
                   (equal (plist-get entry :component) component)
                   (equal (plist-get entry :pattern-target) pattern-target))
          (push entry matches))))
    matches))

(defun gptel-auto-workflow-approval-queue--count-pending-by-target (component pattern-target)
  "Return count of pending entries matching COMPONENT and PATTERN-TARGET."
  (length (gptel-auto-workflow-approval-queue--find-pending-by-target component pattern-target)))

;; ── Enqueue ──

(defun gptel-auto-workflow-approval-queue-enqueue (tested-proposal rollback-tag)
  "Persist TESTED-PROPOSAL as a pending approval queue entry.
ROLLBACK-TAG is the git rollback tag for emergency recovery.
Generates a stable proposal-id slug, writes a .sexp file to the
pending directory, and returns the full queue-entry plist.
Skips enqueue if an identical proposal (same component+target) already
exists in the pending queue (deduplication).
Queue-entry plist keys: :id, :created-at, :expires-at, :status,
:source, :proposal, :risk, :component, :pattern-target, :rollback-tag."
   (let* ((risk (or (plist-get tested-proposal :risk) "unknown"))
          (component (or (plist-get tested-proposal :component) "unknown"))
          (ptarget (or (plist-get tested-proposal :pattern-target) "unknown"))
          ;; Dedup: skip if identical proposal already pending
          (existing-count (gptel-auto-workflow-approval-queue--count-pending-by-target
                           component ptarget)))
     (if (> existing-count 0)
         (progn
           (message "[approval-queue] Skipping duplicate: %s/%s (%d already pending)"
                    component ptarget existing-count)
           nil)
       (let* ((now (float-time))
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
         queue-entry))))

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
  "Display pending approval queue entries in a temp buffer for interactive
review."
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

;; ── Auto-approve Recurring Proposals ──

(defcustom gptel-auto-workflow-approval-queue-auto-approve-threshold 3
  "Number of duplicate pending proposals before auto-approving the oldest.
When the same component+target has more than this many pending proposals,
the oldest is auto-approved and the rest are rejected as duplicates.
This closes the loop for recurring patterns without human intervention."
  :type 'integer
  :group 'gptel-tools-agent)

(defun gptel-auto-workflow-approval-queue-auto-approve-recurring ()
  "Auto-approve oldest pending proposal when duplicates exceed threshold.
For each component+target pair with > auto-approve-threshold pending:
1. Keep the oldest, approve it (move to decisions as approved)
2. Reject all others as duplicates (move to decisions as rejected)
Returns list of auto-approved proposal IDs."
  (let* ((pending-dir
          (expand-file-name
           "pending"
           (expand-file-name gptel-auto-workflow-approval-queue-dir)))
         (decisions-dir
          (expand-file-name
           "decisions"
           (expand-file-name gptel-auto-workflow-approval-queue-dir)))
         (files (when (file-directory-p pending-dir)
                  (directory-files pending-dir t "\\.sexp$")))
         ;; Group by component+target
         (groups (make-hash-table :test 'equal))
         (auto-approved nil))
    ;; Group all pending entries by (component . pattern-target)
    (dolist (f files)
      (let ((entry (gptel-auto-workflow-approval-queue--read-sexp-file f)))
        (when entry
          (let ((key (cons (or (plist-get entry :component) "")
                          (or (plist-get entry :pattern-target) ""))))
            (push (cons f entry) (gethash key groups))))))
    ;; Process groups exceeding threshold
    (make-directory decisions-dir t)
    (maphash
     (lambda (key entries)
       (when (> (length entries) gptel-auto-workflow-approval-queue-auto-approve-threshold)
         ;; Sort by :created-at ascending (oldest first)
         (setq entries (sort entries
                             (lambda (a b)
                               (< (or (plist-get (cdr a) :created-at) 0.0)
                                  (or (plist-get (cdr b) :created-at) 0.0)))))
         ;; Approve oldest
         (let* ((oldest-pair (car entries))
                (oldest-file (car oldest-pair))
                (oldest-entry (cdr oldest-pair))
                (oldest-id (plist-get oldest-entry :id))
                (approved-entry
                 (let ((e (copy-sequence oldest-entry)))
                   (setq e (plist-put e :status "approved"))
                   (setq e (plist-put e :decision-at (float-time)))
                   (setq e (plist-put e :decision-by "auto-approve-recurring"))
                   (plist-put e :decision-note
                              (format "Auto-approved: %d duplicate proposals for %s"
                                      (length entries) key))))
                (dest (gptel-auto-workflow-approval-queue-decisions-file oldest-id)))
           (with-temp-file dest
             (prin1 approved-entry (current-buffer)))
           (delete-file oldest-file)
           (message "[approval-queue] Auto-approved recurring proposal: %s (%d duplicates)"
                    oldest-id (1- (length entries)))
           (push oldest-id auto-approved))
         ;; Reject all others as duplicates
          (dolist (pair (cdr entries))
            (let* ((entry (cdr pair))
                   (f (car pair))
                   (id (plist-get entry :id))
                   (rejected-entry
                    (let ((e (copy-sequence entry)))
                      (setq e (plist-put e :status "rejected"))
                      (setq e (plist-put e :decision-at (float-time)))
                      (setq e (plist-put e :decision-by "auto-approve-dedup"))
                      (plist-put e :decision-note
                                 (format "Duplicate of auto-approved proposal for %s" key))))
                   (dest (gptel-auto-workflow-approval-queue-decisions-file id)))
             (with-temp-file dest
               (prin1 rejected-entry (current-buffer)))
             (delete-file f)))))
     groups)
    (nreverse auto-approved)))

;; ── Dedup Cleanup ──

(defun gptel-auto-workflow-approval-queue-dedup ()
  "Collapse duplicate pending proposals, keeping only the newest per target.
For each component+target pair with multiple pending proposals:
keep only the newest, reject all older ones.
Returns count of proposals removed."
  (interactive)
  (let* ((pending-dir
          (expand-file-name
           "pending"
           (expand-file-name gptel-auto-workflow-approval-queue-dir)))
         (decisions-dir
          (expand-file-name
           "decisions"
           (expand-file-name gptel-auto-workflow-approval-queue-dir)))
         (files (when (file-directory-p pending-dir)
                  (directory-files pending-dir t "\\.sexp$")))
         (groups (make-hash-table :test 'equal))
         (removed 0))
    ;; Group by component+target
    (dolist (f files)
      (let ((entry (gptel-auto-workflow-approval-queue--read-sexp-file f)))
        (when entry
          (let ((key (cons (or (plist-get entry :component) "")
                          (or (plist-get entry :pattern-target) ""))))
            (push (cons f entry) (gethash key groups))))))
    ;; For each group with >1 entry, keep newest, reject rest
    (make-directory decisions-dir t)
    (maphash
     (lambda (key entries)
       (when (> (length entries) 1)
         ;; Sort by :created-at descending (newest first)
         (setq entries (sort entries
                             (lambda (a b)
                               (> (or (plist-get (cdr a) :created-at) 0.0)
                                  (or (plist-get (cdr b) :created-at) 0.0)))))
         ;; Keep newest, reject older ones
          (dolist (pair (cdr entries))
            (let* ((entry (cdr pair))
                   (f (car pair))
                   (id (plist-get entry :id))
                   (rejected-entry
                    (let ((e (copy-sequence entry)))
                      (setq e (plist-put e :status "rejected"))
                      (setq e (plist-put e :decision-at (float-time)))
                      (setq e (plist-put e :decision-by "dedup-cleanup"))
                      (plist-put e :decision-note
                                 (format "Duplicate removed by dedup cleanup for %s" key))))
                   (dest (gptel-auto-workflow-approval-queue-decisions-file id)))
             (with-temp-file dest
               (prin1 rejected-entry (current-buffer)))
             (delete-file f)
             (setq removed (1+ removed))))))
     groups)
    (when (> removed 0)
      (message "[approval-queue] Dedup cleanup: removed %d duplicate proposals" removed))
    removed))

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

;; ── Executor: Consume approved proposals ──

(defun gptel-auto-workflow-approval-queue-execute-approved ()
  "Process all approved proposals in the decisions directory.
For each approved proposal:
1. Create a git rollback tag (if :rollback-tag present)
2. Write deployment memory to mementum
3. Mark the proposal as :deployed with :deployed-at timestamp
Returns list of executed proposal IDs."
  (let ((decisions-dir
         (expand-file-name
          "decisions"
          (expand-file-name gptel-auto-workflow-approval-queue-dir)))
        (executed nil))
    (when (file-directory-p decisions-dir)
      (dolist (f (directory-files decisions-dir t "\\.sexp$"))
        (let ((entry (gptel-auto-workflow-approval-queue--read-sexp-file f)))
          (when (and entry
                     (equal (plist-get entry :status) "approved")
                     (not (plist-get entry :deployed-at)))
            (let* ((proposal-id (plist-get entry :id))
                   (rollback-tag (plist-get entry :rollback-tag))
                   (component (or (plist-get entry :component) "unknown"))
                   (risk (or (plist-get entry :risk) "unknown"))
                   (description (or (plist-get entry :description) "No description")))
              ;; Create git rollback tag
              (when (and rollback-tag (fboundp 'gptel-auto-workflow--git-cmd))
                (condition-case nil
                    (gptel-auto-workflow--git-cmd
                     (format "git tag %s" (shell-quote-argument rollback-tag)) 30)
                  (error
                   (message "[approval-queue] Failed to create rollback tag: %s" rollback-tag))))
              ;; Write deployment memory
              (when (fboundp 'gptel-auto-workflow--mementum-write-memory)
                (condition-case nil
                    (gptel-auto-workflow--mementum-write-memory
                     '✅ (format "approved-deploy-%s" (or proposal-id "unknown"))
                     (format "**Approved and deployed:** %s\n**Risk:** %s\n**Component:** %s\n**Rollback tag:** %s\n\nDeployed by approval queue executor after human approval."
                             description risk component (or rollback-tag "none")))
                  (error nil)))
              ;; Mark as deployed
              (let* ((updated (plist-put entry :status "deployed"))
                    (updated (plist-put updated :deployed-at (float-time))))
                (with-temp-file f
                  (prin1 updated (current-buffer)))
                (message "[approval-queue] Deployed approved proposal: %s (component: %s)"
                         proposal-id component)
                (push proposal-id executed)))))))
    (nreverse executed)))

;; ── Priority Injector: Feed approved proposals into next experiment cycle ──

(defvar gptel-auto-workflow-approval-queue-priority-file
  "var/tmp/approval-priorities.el"
  "File where approved-proposal priorities are written for next cycle.
Each line: (target-file . priority-bonus).
The target file is the :pattern-target of an approved proposal.
Priority bonus 0.5 = boost 50% over baseline priority.")

(defun gptel-auto-workflow-approval-queue-prioritize-targets (&optional targets)
  "Inject approved-proposal targets into TARGETS priority list.
Returns updated targets alist with priority bonuses for approved targets.
If TARGETS is nil, returns just the approved targets as a fresh list."
  (interactive)
  (let* ((decisions-dir
          (expand-file-name
           "decisions"
           (expand-file-name gptel-auto-workflow-approval-queue-dir)))
         (approved-targets nil))
    (when (file-directory-p decisions-dir)
      (dolist (f (directory-files decisions-dir t "\\.sexp$"))
        (let ((entry (gptel-auto-workflow-approval-queue--read-sexp-file f)))
          (when (and entry
                     (equal (plist-get entry :status) "approved")
                     (plist-get entry :pattern-target))
            (push (cons (plist-get entry :pattern-target) 0.5) approved-targets)))))
    (if targets
        ;; Merge: add approved-targets that aren't in targets
        (append targets
                (cl-remove-if (lambda (approved)
                                (assoc (car approved) targets))
                              approved-targets))
      approved-targets)))

(defun gptel-auto-workflow-approval-queue-persist-priorities ()
  "Write approved-proposal priorities to disk for next experiment cycle.
The next workflow run reads this file and biases target selection toward
approved proposals. Returns count of priorities written."
  (let* ((priorities (gptel-auto-workflow-approval-queue-prioritize-targets))
         (root (or (and (fboundp 'gptel-auto-workflow--expand-workspace-path)
                        (gptel-auto-workflow--expand-workspace-path ""))
                   default-directory))
         (file (expand-file-name gptel-auto-workflow-approval-queue-priority-file
                                 root)))
    (when priorities
      (make-directory (file-name-directory file) t)
      (with-temp-file file
        (insert ";;; Auto-generated by approval-queue-prioritize-targets\n")
        (insert ";;; Format: list of (target-file . priority-bonus)\n")
        (pp priorities (current-buffer)))
      (length priorities))))

(provide 'gptel-auto-workflow-approval-queue)
;;; gptel-auto-workflow-approval-queue.el ends here
