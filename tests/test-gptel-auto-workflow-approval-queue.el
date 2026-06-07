;;; test-gptel-auto-workflow-approval-queue.el --- Tests for approval queue -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OV5 Self-Improving Architecture

;; Author: OV5 System
;; Keywords: tests, approval, queue, human-in-the-loop

;;; Commentary:

;; ERT tests for gptel-auto-workflow-approval-queue.el.
;; Covers: enqueue, list, approve, reject, expiry, summary, pending-p.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-auto-workflow-approval-queue)

;; ── Helper Macros ──

(defmacro with-approval-queue-sandbox (&rest body)
  "Execute BODY with a temporary approval queue directory.
Cleans up all files after BODY completes."
  (declare (indent 0))
  `(let* ((tmp-dir (make-temp-name "/tmp/approval-queue-test-"))
          (gptel-auto-workflow-approval-queue-dir tmp-dir)
          (gptel-auto-workflow-approval-queue-expiry-seconds (* 7 24 60 60)))
     (unwind-protect
         (progn ,@body)
       (when (file-directory-p tmp-dir)
         (delete-directory tmp-dir t)))))

(defun test-approval-queue--make-proposal (risk component ptarget)
  "Create a sample tested-proposal plist for testing."
  (list :description (format "Fix %s issue in %s" component ptarget)
        :component component
        :confidence 0.7
        :risk risk
        :test-success-rate 0.8
        :test-status "pass"
        :pattern-type 'strategy
        :pattern-target ptarget))

;; ── Enqueue Tests ──

(ert-deftest test-approval-queue/enqueue-persist ()
  "Should enqueue a proposal and persist it as a .sexp file in pending dir."
  (with-approval-queue-sandbox
   (let* ((proposal
           (test-approval-queue--make-proposal
            "high" "strategy-harness" "lisp/harness.el"))
          (rollback-tag
           "monitoring-rollback-strategy-harness-lisp-harness-el")
          (entry
           (gptel-auto-workflow-approval-queue-enqueue
            proposal rollback-tag))
          (filepath
           (gptel-auto-workflow-approval-queue-file
            (plist-get entry :id))))
     ;; Entry has correct fields
     (should (plist-get entry :id))
     (should (equal (plist-get entry :status) "pending"))
     (should (equal (plist-get entry :source) "monitoring-agent"))
     (should (equal (plist-get entry :risk) "high"))
     (should (equal (plist-get entry :component) "strategy-harness"))
     (should (equal (plist-get entry :rollback-tag) rollback-tag))
     (should (> (plist-get entry :created-at) 0.0))
     (should (> (plist-get entry :expires-at)
                (plist-get entry :created-at)))
     ;; .sexp file exists in pending dir
     (should (file-exists-p filepath))
     ;; File content roundtrips correctly
     (let ((read-entry
            (gptel-auto-workflow-approval-queue--read-sexp-file filepath)))
       (should (equal (plist-get read-entry :id)
                      (plist-get entry :id)))
       (should (equal (plist-get read-entry :status) "pending"))))))

;; ── List Tests ──

(ert-deftest test-approval-queue/list-returns-pending ()
  "Should list pending entries sorted by :created-at ascending."
  (with-approval-queue-sandbox
   (let* ((p1 (test-approval-queue--make-proposal
               "high" "strategy-harness" "lisp/a.el"))
          (p2 (test-approval-queue--make-proposal
               "high" "strategy-harness" "lisp/b.el"))
          (e1 (gptel-auto-workflow-approval-queue-enqueue p1 "rollback-a"))
          (e2 (gptel-auto-workflow-approval-queue-enqueue p2 "rollback-b"))
          (entries (gptel-auto-workflow-approval-queue-list)))
     (should (= (length entries) 2))
     ;; Sorted by created-at ascending (e1 was created before e2)
     (should (<= (plist-get (car entries) :created-at)
                (plist-get (cadr entries) :created-at))))))

;; ── Approve Tests ──

(ert-deftest test-approval-queue/approve-moves-to-decisions ()
  "Should approve a proposal, moving it from pending to decisions dir."
  (with-approval-queue-sandbox
   (let* ((proposal
           (test-approval-queue--make-proposal
            "high" "strategy-harness" "lisp/harness.el"))
          (entry
           (gptel-auto-workflow-approval-queue-enqueue
            proposal "rollback-test"))
          (proposal-id (plist-get entry :id))
          (approved
           (gptel-auto-workflow-approval-queue-approve
            proposal-id "Looks good")))
     ;; Approved entry has correct fields
     (should (equal (plist-get approved :status) "approved"))
     (should (equal (plist-get approved :decision-by) "human"))
     (should (equal (plist-get approved :decision-note) "Looks good"))
     (should (> (plist-get approved :decision-at) 0.0))
     ;; Pending file is gone
     (should (not (file-exists-p
                   (gptel-auto-workflow-approval-queue-file proposal-id))))
     ;; Decisions file exists
     (should (file-exists-p
              (gptel-auto-workflow-approval-queue-decisions-file proposal-id)))
     ;; Queue list is now empty
     (should (= (length (gptel-auto-workflow-approval-queue-list)) 0)))))

;; ── Reject Tests ──

(ert-deftest test-approval-queue/reject-moves-to-decisions ()
  "Should reject a proposal, moving it from pending to decisions dir."
  (with-approval-queue-sandbox
   (let* ((proposal
           (test-approval-queue--make-proposal
            "high" "strategy-harness" "lisp/harness.el"))
          (entry
           (gptel-auto-workflow-approval-queue-enqueue
            proposal "rollback-test"))
          (proposal-id (plist-get entry :id))
          (rejected
           (gptel-auto-workflow-approval-queue-reject
            proposal-id "Too risky")))
     ;; Rejected entry has correct fields
     (should (equal (plist-get rejected :status) "rejected"))
     (should (equal (plist-get rejected :decision-by) "human"))
     (should (equal (plist-get rejected :decision-note) "Too risky"))
     (should (> (plist-get rejected :decision-at) 0.0))
     ;; Pending file is gone
     (should (not (file-exists-p
                   (gptel-auto-workflow-approval-queue-file proposal-id))))
     ;; Decisions file exists
     (should (file-exists-p
              (gptel-auto-workflow-approval-queue-decisions-file proposal-id))))))

;; ── Expiry Tests ──

(ert-deftest test-approval-queue/expiry-prune ()
  "Should mark expired proposals and move them to decisions dir."
  (with-approval-queue-sandbox
   ;; Use a very short expiry so entries expire immediately
   (let ((gptel-auto-workflow-approval-queue-expiry-seconds 0))
     (let* ((proposal
             (test-approval-queue--make-proposal
              "high" "strategy-harness" "lisp/harness.el"))
            (entry
             (gptel-auto-workflow-approval-queue-enqueue
              proposal "rollback-test"))
            (proposal-id (plist-get entry :id))
            (filepath
             (gptel-auto-workflow-approval-queue-file proposal-id)))
       ;; Entry was just created with 0 expiry — expires-at <= now
       ;; Wait a tiny bit so float-time advances past expires-at
       (sleep-for 0 10)
       (let ((pruned
              (gptel-auto-workflow-approval-queue-prune-expired)))
         (should (= pruned 1))
         ;; Pending file gone
         (should (not (file-exists-p filepath)))
         ;; Decisions file exists with expired status
         (let ((archived
                (gptel-auto-workflow-approval-queue--read-sexp-file
                 (gptel-auto-workflow-approval-queue-decisions-file
                  proposal-id))))
           (should (equal (plist-get archived :status) "expired"))
           (should (equal (plist-get archived :id) proposal-id))))))))

;; ── Summary Tests ──

(ert-deftest test-approval-queue/summary ()
  "Should return summary plist with pending, expired counts and oldest-created-at."
  (with-approval-queue-sandbox
   ;; Enqueue with 0 expiry so entries expire immediately
   (let ((gptel-auto-workflow-approval-queue-expiry-seconds 0))
     (let* ((p1 (test-approval-queue--make-proposal
                 "high" "strategy-harness" "lisp/a.el"))
            (_e1 (gptel-auto-workflow-approval-queue-enqueue p1 "rollback-a"))
            ;; Sleep so entries expire
            (_sleep (sleep-for 0 10))
            (pruned (gptel-auto-workflow-approval-queue-prune-expired)))
       ;; 1 entry expired and moved to decisions
       (should (= pruned 1))
       ;; Now enqueue 2 fresh entries with normal expiry for pending test
       (let ((gptel-auto-workflow-approval-queue-expiry-seconds (* 7 24 60 60)))
         (let* ((p2 (test-approval-queue--make-proposal
                     "high" "strategy-harness" "lisp/b.el"))
                (p3 (test-approval-queue--make-proposal
                     "high" "strategy-harness" "lisp/c.el"))
                (_e2 (gptel-auto-workflow-approval-queue-enqueue p2 "rollback-b"))
                (_e3 (gptel-auto-workflow-approval-queue-enqueue p3 "rollback-c"))
                (summary (gptel-auto-workflow-approval-queue-summary)))
           ;; 2 pending, 1 expired (from earlier)
           (should (= (plist-get summary :pending) 2))
           (should (= (plist-get summary :expired) 1))
           ;; oldest-created-at matches the earliest pending entry
           (should (> (plist-get summary :oldest-created-at) 0.0))))))))

;; ── Pending-p Tests ──

(ert-deftest test-approval-queue/pending-p ()
  "Should return t when there are pending proposals, nil when empty."
  (with-approval-queue-sandbox
   ;; Initially empty
   (should (not (gptel-auto-workflow-approval-queue-pending-p)))
   ;; Enqueue one
   (let* ((proposal
           (test-approval-queue--make-proposal
            "high" "strategy-harness" "lisp/harness.el"))
          (entry
           (gptel-auto-workflow-approval-queue-enqueue
            proposal "rollback-test")))
     (should (gptel-auto-workflow-approval-queue-pending-p))
     ;; Approve it
     (gptel-auto-workflow-approval-queue-approve
      (plist-get entry :id))
     (should (not (gptel-auto-workflow-approval-queue-pending-p))))))

(provide 'test-gptel-auto-workflow-approval-queue)
;;; test-gptel-auto-workflow-approval-queue.el ends here