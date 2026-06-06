;;; gptel-auto-workflow-human-interface.el --- Human interface layer -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OV5 Self-Improving Architecture

;; Author: OV5 System
;; Keywords: human-interface, dashboard, alerts, notifications

;;; Commentary:

;; Phase 4 Task 4.3: Human Interface Layer
;; Provides dashboards, alerts, and notifications for human oversight

;;; Code:

(require 'cl-lib)

;; ============================================================================
;; Configuration
;; ============================================================================

(defvar gptel-auto-workflow--notification-queue nil
  "Queue of pending notifications.")

(defvar gptel-auto-workflow--alert-history nil
  "History of sent alerts.")

(defvar gptel-auto-workflow--dashboard-cache nil
  "Cached dashboard data.")

(defconst gptel-auto-workflow--notification-thresholds
  '((high-risk . 0.7)
    (medium-risk . 0.3)
    (low-risk . 0.0))
  "Risk thresholds for notification triggering.")

(defvar gptel-auto-workflow--notification-policy
  '(:high-risk t :medium-risk nil :low-risk nil)
  "Thresholds for when to send notifications.
:high-risk - always notify for high-risk decisions
:medium-risk - notify for medium-risk when t
:low-risk - notify for low-risk when t")

;; Forward declaration from decision-classification.el
(defvar gptel-auto-workflow--approval-history nil
  "Approval history for experiments.")

(defvar gptel-auto-workflow--notification-methods
  '(:message)
  "Methods for sending notifications.
:message - use Emacs message function
:log - write to log file")

;; ============================================================================
;; Dashboard Generation
;; ============================================================================

(defun gptel-auto-workflow--generate-dashboard-summary ()
  "Generate dashboard summary from approval history.
Includes business context from context database when available."
  (let* ((history (or gptel-auto-workflow--approval-history nil))
         (total (length history))
         (auto-approved (cl-count :auto-approved history
                                  :key (lambda (d) (plist-get d :approval-type))))
         (recommend (cl-count :recommend-confirm history
                              :key (lambda (d) (plist-get d :approval-type))))
         (review (cl-count :require-review history
                           :key (lambda (d) (plist-get d :approval-type))))
         (auto-rate (if (> total 0)
                        (/ (float auto-approved) total)
                      0.0))
         (recent-alerts (cl-subseq (or gptel-auto-workflow--alert-history nil)
                                   0
                                   (min 5 (length (or gptel-auto-workflow--alert-history nil)))))
         ;; Get business context from context database (Phase 3)
         (context-summary (when (fboundp 'gptel-auto-workflow--get-context-summary)
                           (gptel-auto-workflow--get-context-summary))))
    (list :total-experiments total
          :auto-approved-count auto-approved
          :recommend-count recommend
          :review-count review
          :auto-approval-rate auto-rate
          :recent-alerts recent-alerts
          :context-summary context-summary
          :timestamp (format-time-string "%Y-%m-%dT%H:%M:%SZ"))))

(defun gptel-auto-workflow--generate-dashboard-detailed ()
  "Generate detailed dashboard with experiment breakdown."
  (let* ((history (or gptel-auto-workflow--approval-history nil))
         (summary (gptel-auto-workflow--generate-dashboard-summary))
         (recent (cl-subseq history 0 (min 10 (length history))))
         (by-target (gptel-auto-workflow--group-by-target history)))
    (list :summary summary
          :recent-experiments recent
          :by-target by-target
          :timestamp (format-time-string "%Y-%m-%dT%H:%M:%SZ"))))

(defun gptel-auto-workflow--group-by-target (history)
  "Group experiments by target."
  (let ((groups (make-hash-table :test 'equal)))
    (dolist (exp history)
      (let* ((target (or (plist-get exp :target) "unknown"))
             (existing (gethash target groups nil)))
        (puthash target (cons exp existing) groups)))
    (let ((result nil))
      (maphash (lambda (target exps)
                 (push (cons target (length exps)) result))
               groups)
      result)))

(defun gptel-auto-workflow--format-dashboard-text ()
  "Format dashboard as human-readable text."
  (let* ((dashboard (gptel-auto-workflow--generate-dashboard-summary))
         (total (plist-get dashboard :total-experiments))
         (auto (plist-get dashboard :auto-approved-count))
         (recommend (plist-get dashboard :recommend-count))
         (review (plist-get dashboard :review-count))
         (rate (plist-get dashboard :auto-approval-rate)))
    (format "OV5 Auto-Workflow Dashboard\n%s\n\nTotal Experiments: %d\nAuto-Approved: %d\nRecommend: %d\nRequire Review: %d\nAuto-Approval Rate: %.1f%%"
            (make-string 30 ?=)
            total auto recommend review (* rate 100.0))))

(defun gptel-auto-workflow--generate-dashboard-by-time ()
  "Generate dashboard grouped by time period."
  (let* ((history (or gptel-auto-workflow--approval-history nil))
         (by-date (make-hash-table :test 'equal)))
    (dolist (exp history)
      (let* ((timestamp (plist-get exp :timestamp))
             (date (when timestamp (substring timestamp 0 10)))
             (existing (when date (gethash date by-date nil))))
        (when date
          (puthash date (cons exp existing) by-date))))
    (let ((result nil))
      (maphash (lambda (date exps)
                 (push (cons date (length exps)) result))
               by-date)
      (list :by-date (sort result (lambda (a b) (string< (car b) (car a))))
            :timestamp (format-time-string "%Y-%m-%dT%H:%M:%SZ")))))

;; ============================================================================
;; Alert System
;; ============================================================================

(defun gptel-auto-workflow--create-alert (experiment)
  "Create alert for EXPERIMENT based on approval type."
  (let* ((approval-type (plist-get experiment :approval-type))
         (experiment-id (plist-get experiment :experiment-id))
         (target (or (plist-get experiment :target) "unknown"))
         (level (cond ((eq approval-type :require-review) :high)
                      ((eq approval-type :recommend-confirm) :medium)
                      ((eq approval-type :auto-approved) :low)
                      (t nil))))
    (when (and level (gptel-auto-workflow--should-notify-for-level-p level))
      (list :level level
            :message (format "%s-risk experiment requires attention: %s"
                             (capitalize (substring (symbol-name level) 1))
                             target)
            :experiment-id experiment-id
            :target target
            :timestamp (format-time-string "%Y-%m-%dT%H:%M:%SZ")))))

(defun gptel-auto-workflow--should-notify-for-level-p (level)
  "Check if notifications should be sent for LEVEL."
  (let ((thresholds gptel-auto-workflow--notification-thresholds))
    (cond ((eq level :high) (plist-get thresholds :high-risk))
          ((eq level :medium) (plist-get thresholds :medium-risk))
          ((eq level :low) (plist-get thresholds :low-risk))
          (t nil))))

(defun gptel-auto-workflow--queue-alert (alert)
  "Queue ALERT for delivery."
  (push alert gptel-auto-workflow--notification-queue))

(defun gptel-auto-workflow--process-alert-queue ()
  "Process and deliver queued alerts."
  (let* ((queue (sort gptel-auto-workflow--notification-queue
                      (lambda (a b)
                        (let ((level-a (plist-get a :level))
                              (level-b (plist-get b :level)))
                          (cond ((and (eq level-a :high) (not (eq level-b :high))) t)
                                ((and (eq level-b :high) (not (eq level-a :high))) nil)
                                ((and (eq level-a :medium) (eq level-b :low)) t)
                                (t nil))))))
         (delivered nil))
    (dolist (alert queue)
      (gptel-auto-workflow--send-notification alert)
      (gptel-auto-workflow--record-alert alert)
      (push alert delivered))
    (setq gptel-auto-workflow--notification-queue nil)
    (nreverse delivered)))

(defun gptel-auto-workflow--record-alert (alert)
  "Record ALERT in history."
  (push alert gptel-auto-workflow--alert-history))

;; ============================================================================
;; Notification Mechanisms
;; ============================================================================

(defun gptel-auto-workflow--send-notification (alert)
  "Send ALERT via configured methods."
  (let ((methods gptel-auto-workflow--notification-methods)
        (text (gptel-auto-workflow--format-notification-text alert)))
    (when (memq :message methods)
      (message "[OV5 Alert] %s" text))
    (when (memq :log methods)
      (let ((base-root (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                            (gptel-auto-workflow--worktree-base-root)))
            (timestamp (format-time-string "%Y-%m-%d %H:%M:%S")))
        (when base-root
          (let ((log-file (expand-file-name "mementum/alerts.log" base-root)))
            (make-directory (file-name-directory log-file) t)
            (with-temp-buffer
              (when (file-exists-p log-file)
                (insert-file-contents log-file))
              (goto-char (point-max))
              (insert (format "[%s] %s\n" timestamp text))
              (write-region (point-min) (point-max) log-file))))))
    nil))

(defun gptel-auto-workflow--format-notification-text (alert)
  "Format ALERT as human-readable text."
  (let* ((level (or (plist-get alert :level) :unknown))
         (message (or (plist-get alert :message) "No message"))
         (experiment-id (plist-get alert :experiment-id))
         (target (plist-get alert :target)))
    (format "[%s] %s (ID: %s, Target: %s)"
            (upcase (symbol-name level))
            message
            experiment-id
            target)))

(defun gptel-auto-workflow--should-notify-p (alert)
  "Check if ALERT should be sent based on thresholds."
  (let ((level (plist-get alert :level)))
    (gptel-auto-workflow--should-notify-for-level-p level)))

;; ============================================================================
;; Report Generation
;; ============================================================================

(defun gptel-auto-workflow--generate-daily-report ()
  "Generate daily summary report."
  (let* ((history (or gptel-auto-workflow--approval-history nil))
         (today (format-time-string "%Y-%m-%d"))
         (today-exps (cl-remove-if-not
                      (lambda (exp)
                        (let ((timestamp (plist-get exp :timestamp)))
                          (and timestamp (string-prefix-p today timestamp))))
                      history))
         (breakdown (gptel-auto-workflow--count-by-approval-type today-exps)))
    (list :date today
          :total-experiments (length today-exps)
          :breakdown breakdown
          :timestamp (format-time-string "%Y-%m-%dT%H:%M:%SZ"))))

(defun gptel-auto-workflow--count-by-approval-type (experiments)
  "Count experiments by approval type."
  (let ((counts (make-hash-table :test 'eq)))
    (dolist (exp experiments)
      (let* ((type (plist-get exp :approval-type))
             (count (gethash type counts 0)))
        (puthash type (1+ count) counts)))
    (let ((result nil))
      (maphash (lambda (type count)
                 (push (list :approval-type type :count count) result))
               counts)
      result)))

(defun gptel-auto-workflow--generate-weekly-report ()
  "Generate weekly summary report."
  (let* ((history (or gptel-auto-workflow--approval-history nil))
         (now (current-time))
         (week-ago (time-subtract now (days-to-time 7)))
         (week-exps (cl-remove-if-not
                     (lambda (exp)
                       (let ((timestamp (plist-get exp :timestamp)))
                         (when timestamp
                           (time-less-p week-ago (date-to-time timestamp)))))
                     history)))
    (list :week-start (format-time-string "%Y-%m-%d" week-ago)
          :week-end (format-time-string "%Y-%m-%d" now)
          :total-experiments (length week-exps)
          :timestamp (format-time-string "%Y-%m-%dT%H:%M:%SZ"))))

(defun gptel-auto-workflow--format-report-markdown (report)
  "Format REPORT as markdown."
  (let* ((date (plist-get report :date))
         (total (plist-get report :total-experiments))
         (breakdown (plist-get report :breakdown)))
    (format "# Daily Report - %s\n\n## Summary\n\nTotal: %d experiments\n\n## Breakdown\n\n%s"
            date
            total
            (mapconcat (lambda (item)
                         (format "- %s: %d"
                                 (capitalize (symbol-name (plist-get item :approval-type)))
                                 (plist-get item :count)))
                       breakdown
                       "\n"))))

(defun gptel-auto-workflow--format-report-text (report)
  "Format REPORT as plain text."
  (let* ((date (plist-get report :date))
         (total (plist-get report :total-experiments))
         (breakdown (plist-get report :breakdown)))
    (format "Daily Report - %s\n%s\n\nTotal: %d experiments\n\nBreakdown:\n%s"
            date
            (make-string 40 ?=)
            total
            (mapconcat (lambda (item)
                         (format "  %s: %d"
                                 (capitalize (symbol-name (plist-get item :approval-type)))
                                 (plist-get item :count)))
                       breakdown
                       "\n"))))

;; ============================================================================
;; Integration
;; ============================================================================

(defun gptel-auto-workflow--process-approval-decision (decision)
  "Process approval DECISION and generate alert if needed."
  (let ((alert (gptel-auto-workflow--create-alert decision)))
    (when alert
      (gptel-auto-workflow--queue-alert alert))))

(provide 'gptel-auto-workflow-human-interface)

;;; gptel-auto-workflow-human-interface.el ends here
