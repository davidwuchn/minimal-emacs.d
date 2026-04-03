;;; gptel-benchmark-rollback.el --- Safety rollback for improvements -*- lexical-binding: t; -*-

;; Copyright (C) 2025 David Wu
;; Author: David Wu
;; Version: 1.0.0
;; Keywords: ai, benchmark, rollback, safety

;;; Commentary:

;; Safety mechanism for rolling back failed improvements.
;; Maintains history of all changes and allows restoration.

;;; Code:

(require 'cl-lib)
(require 'gptel-benchmark-core)

;;; Customization

(defgroup gptel-benchmark-rollback nil
  "Safety rollback for improvements."
  :group 'gptel-benchmark)

(defcustom gptel-benchmark-rollback-history-size 50
  "Maximum number of rollback checkpoints to keep."
  :type 'integer
  :group 'gptel-benchmark-rollback)

(defcustom gptel-benchmark-rollback-auto-backup t
  "Whether to automatically backup before changes."
  :type 'boolean
  :group 'gptel-benchmark-rollback)

;;; History Storage

(defvar gptel-benchmark-rollback-history (make-hash-table :test 'equal)
  "Hash table mapping file paths to list of checkpoints.")

(defvar gptel-benchmark-rollback-current-session nil
  "List of checkpoints created in current session.")

;;; Checkpoint Management

(defun gptel-benchmark-rollback-create-checkpoint (file &optional description)
  "Create a rollback checkpoint for FILE.
DESCRIPTION is optional human-readable description.
Returns checkpoint ID."
  (when (and gptel-benchmark-rollback-auto-backup (file-exists-p file))
    (let* ((checkpoint-id (format "cp-%s" (format-time-string "%Y%m%d-%H%M%S")))
           (content (with-temp-buffer
                      (insert-file-contents file)
                      (buffer-string)))
           (checksum (secure-hash 'md5 content))
           (checkpoint (list :id checkpoint-id
                             :file file
                             :content content
                             :checksum checksum
                             :description (or description "Auto-checkpoint")
                             :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S"))))
      (let ((history (gethash file gptel-benchmark-rollback-history)))
        (push checkpoint history)
        (when (> (length history) gptel-benchmark-rollback-history-size)
          (setq history (butlast history (- (length history) gptel-benchmark-rollback-history-size))))
        (puthash file history gptel-benchmark-rollback-history))
      (push checkpoint gptel-benchmark-rollback-current-session)
      (message "[rollback] Created checkpoint %s for %s" checkpoint-id file)
      checkpoint-id)))

(defun gptel-benchmark-rollback-restore (file checkpoint-id)
  "Restore FILE to state at CHECKPOINT-ID.
Returns t on success, nil on failure."
  (let ((checkpoint (gptel-benchmark-rollback--find-checkpoint file checkpoint-id)))
    (if checkpoint
        (progn
          (with-temp-file file
            (insert (plist-get checkpoint :content)))
          (message "[rollback] Restored %s to %s" file checkpoint-id)
          t)
      (message "[rollback] Checkpoint %s not found for %s" checkpoint-id file)
      nil)))

(defun gptel-benchmark-rollback-restore-latest (file)
  "Restore FILE to most recent checkpoint.
Returns checkpoint ID on success, nil on failure."
  (let ((history (gethash file gptel-benchmark-rollback-history)))
    (when (and history (> (length history) 0))
      (let ((latest (car history)))
        (gptel-benchmark-rollback-restore file (plist-get latest :id))))))

(defun gptel-benchmark-rollback-restore-session ()
  "Restore all files changed in current session.
Uses latest checkpoint for each file."
  (interactive)
  (let ((files-to-restore (make-hash-table :test 'equal)))
    (dolist (checkpoint gptel-benchmark-rollback-current-session)
      (let ((file (plist-get checkpoint :file)))  ; key by file path, not ID, for deduplication
        (puthash file checkpoint files-to-restore)))
    (maphash (lambda (_file checkpoint)
               (gptel-benchmark-rollback-restore 
                (plist-get checkpoint :file)
                (plist-get checkpoint :id)))
             files-to-restore)
    (message "[rollback] Restored %d files from session" (hash-table-count files-to-restore))))

;;; History Queries

(defun gptel-benchmark-rollback-list-checkpoints (file)
  "List all checkpoints for FILE."
  (gethash file gptel-benchmark-rollback-history))

(defun gptel-benchmark-rollback-show-history (file)
  "Show rollback history for FILE."
  (interactive "fFile: ")
  (let ((history (gethash file gptel-benchmark-rollback-history)))
    (with-output-to-temp-buffer (format "*Rollback History: %s*" file)
      (princ (format "=== Rollback History: %s ===\n\n" file))
      (if (not history)
          (princ "No checkpoints found.\n")
        (dolist (cp history)
          (princ (format "[%s] %s\n"
                         (plist-get cp :timestamp)
                         (plist-get cp :description)))
          (princ (format "  ID: %s\n" (plist-get cp :id)))
          (princ (format "  Checksum: %s\n\n" (plist-get cp :checksum))))))))

(defun gptel-benchmark-rollback-diff (file checkpoint-id)
  "Show diff between current FILE and CHECKPOINT-ID."
  (let ((checkpoint (gptel-benchmark-rollback--find-checkpoint file checkpoint-id)))
    (when checkpoint
      (let ((temp-file (gptel-benchmark-make-temp-file "rollback-diff"))
            (diff-buffer (get-buffer-create "*Rollback Diff*")))
        (with-temp-file temp-file
          (insert (plist-get checkpoint :content)))
        (with-current-buffer diff-buffer
          (erase-buffer)
          (call-process "diff" nil t nil "-u" temp-file file)
          (goto-char (point-min)))
        (delete-file temp-file)
        (display-buffer diff-buffer)))))

;;; Internal Functions

(defun gptel-benchmark-rollback--find-checkpoint (file checkpoint-id)
  "Find checkpoint CHECKPOINT-ID for FILE in history."
  (let ((history (gethash file gptel-benchmark-rollback-history)))
    (cl-find-if (lambda (cp) (equal (plist-get cp :id) checkpoint-id)) history)))

;;; Git Integration

(defun gptel-benchmark-rollback-git-revert (file)
  "Revert FILE using git checkout."
  (interactive "fFile to revert: ")
  (when (file-exists-p file)
    (let ((result (call-process "git" nil nil nil "checkout" "--" file)))
      (if (= result 0)
          (message "[rollback] Git reverted %s" file)
        (message "[rollback] Git revert failed for %s" file)))))

(defun gptel-benchmark-rollback-git-reset-hard (n)
  "Reset to N commits ago using git reset --hard.
WARNING: This is destructive and cannot be undone."
  (interactive "nCommits to reset: ")
  (when (y-or-n-p (format "Reset %d commits? This cannot be undone! " n))
    (let ((result (call-process "git" nil nil nil "reset" "--hard" (format "HEAD~%d" n))))
      (if (= result 0)
          (message "[rollback] Reset %d commits" n)
        (message "[rollback] Git reset failed")))))

;;; Cleanup

(defun gptel-benchmark-rollback-clear-session ()
  "Clear current session checkpoints."
  (setq gptel-benchmark-rollback-current-session nil)
  (message "[rollback] Session cleared"))

(defun gptel-benchmark-rollback-clear-all ()
  "Clear all rollback history."
  (interactive)
  (clrhash gptel-benchmark-rollback-history)
  (setq gptel-benchmark-rollback-current-session nil)
  (message "[rollback] All history cleared"))

;;; Provide

(provide 'gptel-benchmark-rollback)

;;; gptel-benchmark-rollback.el ends here