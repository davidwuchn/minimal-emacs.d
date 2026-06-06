;;; test-gptel-auto-workflow-human-interface.el --- Tests for human interface layer -*- lexical-binding: t; -*-

;; Copyright (C) 2026 OV5 Self-Improving Architecture

;; Author: OV5 System
;; Keywords: tests, human-interface, dashboard, alerts

;;; Commentary:

;; TDD tests for Phase 4 Task 4.3: Human Interface Layer
;; Tests for dashboard generation, alert system, and notification mechanisms

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'gptel-auto-workflow-human-interface)
(require 'gptel-auto-workflow-decision-classification)

;; ============================================================================
;; Helper macro for clean state
;; ============================================================================

(defmacro with-clean-human-interface-state (&rest body)
  "Execute BODY with clean human interface state."
  `(let ((gptel-auto-workflow--notification-queue nil)
         (gptel-auto-workflow--alert-history nil)
         (gptel-auto-workflow--dashboard-cache nil)
         (gptel-auto-workflow--notification-thresholds
          '(:high-risk t :medium-risk nil :low-risk nil))
         (gptel-auto-workflow--notification-methods '(:message)))
     ,@body))

;; ============================================================================
;; Dashboard Generation Tests
;; ============================================================================

(ert-deftest test-human-interface/generate-dashboard-summary ()
  "Should generate dashboard summary from approval history."
  (with-clean-human-interface-state
   ;; Setup test data
   (setq gptel-auto-workflow--approval-history
         '((:experiment-id "exp-001" :approval-type :auto-approved :timestamp "2026-06-06T10:00:00Z")
           (:experiment-id "exp-002" :approval-type :recommend-confirm :timestamp "2026-06-06T11:00:00Z")
           (:experiment-id "exp-003" :approval-type :require-review :timestamp "2026-06-06T12:00:00Z")))
   (let ((dashboard (gptel-auto-workflow--generate-dashboard-summary)))
     (should (plist-get dashboard :total-experiments))
     (should (plist-get dashboard :auto-approved-count))
     (should (plist-get dashboard :recommend-count))
     (should (plist-get dashboard :review-count))
     (should (plist-get dashboard :auto-approval-rate))
     (should (= 3 (plist-get dashboard :total-experiments)))
     (should (= 1 (plist-get dashboard :auto-approved-count)))
     (should (= 1 (plist-get dashboard :recommend-count)))
     (should (= 1 (plist-get dashboard :review-count))))))

(ert-deftest test-human-interface/generate-dashboard-detailed ()
  "Should generate detailed dashboard with experiment breakdown."
  (with-clean-human-interface-state
   (setq gptel-auto-workflow--approval-history
         '((:experiment-id "exp-001" :approval-type :auto-approved :target "file1.el")
           (:experiment-id "exp-002" :approval-type :require-review :target "file2.el")))
   (let ((dashboard (gptel-auto-workflow--generate-dashboard-detailed)))
     (should (plist-get dashboard :summary))
     (should (plist-get dashboard :recent-experiments))
     (should (plist-get dashboard :by-target))
     (should (= 2 (length (plist-get dashboard :recent-experiments)))))))

(ert-deftest test-human-interface/format-dashboard-text ()
  "Should format dashboard as human-readable text."
  (with-clean-human-interface-state
   (setq gptel-auto-workflow--approval-history
         '((:experiment-id "exp-001" :approval-type :auto-approved :target "file1.el")
           (:experiment-id "exp-002" :approval-type :recommend-confirm :target "file2.el")))
   (let ((text (gptel-auto-workflow--format-dashboard-text)))
     (should (stringp text))
     (should (string-match-p "OV5 Auto-Workflow Dashboard" text))
     (should (string-match-p "Total Experiments: 2" text))
     (should (string-match-p "Auto-Approved: 1" text))
     (should (string-match-p "Recommend: 1" text)))))

(ert-deftest test-human-interface/generate-dashboard-by-time ()
  "Should generate dashboard grouped by time period."
  (with-clean-human-interface-state
   (setq gptel-auto-workflow--approval-history
         '((:experiment-id "exp-001" :timestamp "2026-06-06T10:00:00Z")
           (:experiment-id "exp-002" :timestamp "2026-06-06T11:00:00Z")
           (:experiment-id "exp-003" :timestamp "2026-06-05T10:00:00Z")))
   (let ((dashboard (gptel-auto-workflow--generate-dashboard-by-time)))
     (should (plist-get dashboard :by-date))
     (should (>= (length (plist-get dashboard :by-date)) 1)))))

(ert-deftest test-human-interface/dashboard-caching ()
  "Should cache dashboard to avoid regeneration."
  (with-clean-human-interface-state
   (setq gptel-auto-workflow--approval-history
         '((:experiment-id "exp-001" :approval-type :auto-approved)))
   (let ((dashboard1 (gptel-auto-workflow--generate-dashboard-summary))
         (dashboard2 (gptel-auto-workflow--generate-dashboard-summary)))
     ;; Both should be equal (cached)
     (should (equal dashboard1 dashboard2)))))

;; ============================================================================
;; Alert System Tests
;; ============================================================================

(ert-deftest test-human-interface/create-alert-high-risk ()
  "Should create alert for high-risk experiments."
  (with-clean-human-interface-state
   (let ((experiment '(:experiment-id "exp-001"
                       :approval-type :require-review
                       :target "critical.el"
                       :risk-factors (:files-changed 10 :complexity 0.9))))
     (let ((alert (gptel-auto-workflow--create-alert experiment)))
       (should (plist-get alert :level))
       (should (plist-get alert :message))
       (should (plist-get alert :experiment-id))
       (should (eq :high (plist-get alert :level)))
       (should (string-match-p "High-risk experiment" (plist-get alert :message)))))))

(ert-deftest test-human-interface/create-alert-medium-risk ()
  "Should create alert for medium-risk experiments when enabled."
  (with-clean-human-interface-state
   (setq gptel-auto-workflow--notification-thresholds
         '(:high-risk t :medium-risk t :low-risk nil))
   (let ((experiment '(:experiment-id "exp-002"
                       :approval-type :recommend-confirm
                       :target "module.el")))
     (let ((alert (gptel-auto-workflow--create-alert experiment)))
       (should alert)
       (should (eq :medium (plist-get alert :level)))))))

(ert-deftest test-human-interface/no-alert-low-risk ()
  "Should not create alert for low-risk experiments."
  (with-clean-human-interface-state
   (setq gptel-auto-workflow--notification-thresholds
         '(:high-risk t :medium-risk nil :low-risk nil))
   (let ((experiment '(:experiment-id "exp-003"
                       :approval-type :auto-approved
                       :target "simple.el")))
     (let ((alert (gptel-auto-workflow--create-alert experiment)))
       (should-not alert)))))

(ert-deftest test-human-interface/queue-alert ()
  "Should queue alerts for delivery."
  (with-clean-human-interface-state
   (let ((alert '(:level :high :message "Test alert" :experiment-id "exp-001")))
     (gptel-auto-workflow--queue-alert alert)
     (should (= 1 (length gptel-auto-workflow--notification-queue)))
     (should (equal alert (car gptel-auto-workflow--notification-queue))))))

(ert-deftest test-human-interface/process-alert-queue ()
  "Should process and deliver queued alerts."
  (with-clean-human-interface-state
   (let ((alert1 '(:level :high :message "Alert 1" :experiment-id "exp-001"))
         (alert2 '(:level :medium :message "Alert 2" :experiment-id "exp-002")))
     (gptel-auto-workflow--queue-alert alert1)
     (gptel-auto-workflow--queue-alert alert2)
     (let ((delivered (gptel-auto-workflow--process-alert-queue)))
       (should (= 2 (length delivered)))
       (should (= 0 (length gptel-auto-workflow--notification-queue)))
       (should (= 2 (length gptel-auto-workflow--alert-history)))))))

(ert-deftest test-human-interface/alert-priority ()
  "Should prioritize high-risk alerts."
  (with-clean-human-interface-state
   (let ((alert-low '(:level :low :message "Low" :experiment-id "exp-003"))
         (alert-high '(:level :high :message "High" :experiment-id "exp-001"))
         (alert-medium '(:level :medium :message "Medium" :experiment-id "exp-002")))
     ;; Queue in random order
     (gptel-auto-workflow--queue-alert alert-medium)
     (gptel-auto-workflow--queue-alert alert-low)
     (gptel-auto-workflow--queue-alert alert-high)
     (let ((delivered (gptel-auto-workflow--process-alert-queue)))
       ;; Should be delivered in priority order: high, medium, low
       (should (eq :high (plist-get (nth 0 delivered) :level)))
       (should (eq :medium (plist-get (nth 1 delivered) :level)))
       (should (eq :low (plist-get (nth 2 delivered) :level)))))))

(ert-deftest test-human-interface/alert-history ()
  "Should maintain alert history."
  (with-clean-human-interface-state
   (let ((alert '(:level :high :message "Test" :experiment-id "exp-001"
                  :timestamp "2026-06-06T10:00:00Z")))
     (gptel-auto-workflow--record-alert alert)
     (should (= 1 (length gptel-auto-workflow--alert-history)))
     (should (equal alert (car gptel-auto-workflow--alert-history))))))

;; ============================================================================
;; Notification Tests
;; ============================================================================

(ert-deftest test-human-interface/send-notification-message ()
  "Should send notification via message buffer."
  (with-clean-human-interface-state
   (setq gptel-auto-workflow--notification-methods '(:message))
   (let ((alert '(:level :high :message "Test alert" :experiment-id "exp-001")))
     ;; Should not error
     (should-not (gptel-auto-workflow--send-notification alert)))))

(ert-deftest test-human-interface/send-notification-multiple-methods ()
  "Should send notification via multiple methods."
  (with-clean-human-interface-state
   (setq gptel-auto-workflow--notification-methods '(:message :log))
   (let ((alert '(:level :high :message "Test alert" :experiment-id "exp-001")))
     ;; Should not error
     (should-not (gptel-auto-workflow--send-notification alert)))))

(ert-deftest test-human-interface/notification-thresholds ()
  "Should respect notification thresholds."
  (with-clean-human-interface-state
   (setq gptel-auto-workflow--notification-thresholds
         '(:high-risk t :medium-risk nil :low-risk nil))
   (let ((high-alert '(:level :high :message "High" :experiment-id "exp-001"))
         (medium-alert '(:level :medium :message "Medium" :experiment-id "exp-002")))
     (should (gptel-auto-workflow--should-notify-p high-alert))
     (should-not (gptel-auto-workflow--should-notify-p medium-alert)))))

(ert-deftest test-human-interface/format-notification-text ()
  "Should format notification as human-readable text."
  (with-clean-human-interface-state
   (let ((alert '(:level :high
                  :message "High-risk experiment requires review"
                  :experiment-id "exp-001"
                  :target "critical.el")))
     (let ((text (gptel-auto-workflow--format-notification-text alert)))
       (should (stringp text))
       (should (string-match-p "HIGH" text))
       (should (string-match-p "exp-001" text))
       (should (string-match-p "critical.el" text))))))

;; ============================================================================
;; Report Generation Tests
;; ============================================================================

(ert-deftest test-human-interface/generate-daily-report ()
  "Should generate daily summary report."
  (with-clean-human-interface-state
   (setq gptel-auto-workflow--approval-history
         '((:experiment-id "exp-001" :approval-type :auto-approved :timestamp "2026-06-06T10:00:00Z")
           (:experiment-id "exp-002" :approval-type :recommend-confirm :timestamp "2026-06-06T11:00:00Z")
           (:experiment-id "exp-003" :approval-type :require-review :timestamp "2026-06-06T12:00:00Z")))
   (let ((report (gptel-auto-workflow--generate-daily-report)))
     (should (plist-get report :date))
     (should (plist-get report :total-experiments))
     (should (plist-get report :breakdown))
     (should (= 3 (plist-get report :total-experiments))))))

(ert-deftest test-human-interface/generate-weekly-report ()
  "Should generate weekly summary report."
  (with-clean-human-interface-state
   (setq gptel-auto-workflow--approval-history
         '((:experiment-id "exp-001" :timestamp "2026-06-01T10:00:00Z")
           (:experiment-id "exp-002" :timestamp "2026-06-03T10:00:00Z")
           (:experiment-id "exp-003" :timestamp "2026-06-06T10:00:00Z")))
   (let ((report (gptel-auto-workflow--generate-weekly-report)))
     (should (plist-get report :week-start))
     (should (plist-get report :week-end))
     (should (plist-get report :total-experiments)))))

(ert-deftest test-human-interface/format-report-markdown ()
  "Should format report as markdown."
  (with-clean-human-interface-state
   (let ((report '(:date "2026-06-06"
                   :total-experiments 3
                   :breakdown ((:approval-type :auto-approved :count 1)
                               (:approval-type :recommend-confirm :count 1)
                               (:approval-type :require-review :count 1)))))
     (let ((markdown (gptel-auto-workflow--format-report-markdown report)))
       (should (stringp markdown))
       (should (string-match-p "# Daily Report" markdown))
       (should (string-match-p "2026-06-06" markdown))
       (should (string-match-p "Total: 3" markdown))))))

(ert-deftest test-human-interface/format-report-text ()
  "Should format report as plain text."
  (with-clean-human-interface-state
   (let ((report '(:date "2026-06-06"
                   :total-experiments 2
                   :breakdown ((:approval-type :auto-approved :count 2)))))
     (let ((text (gptel-auto-workflow--format-report-text report)))
       (should (stringp text))
       (should (string-match-p "Daily Report" text))
       (should (string-match-p "2026-06-06" text))))))

;; ============================================================================
;; Integration Tests
;; ============================================================================

(ert-deftest test-human-interface/process-approval-with-alert ()
  "Should process approval decision and generate alert if needed."
  (with-clean-human-interface-state
   (setq gptel-auto-workflow--notification-thresholds
         '(:high-risk t :medium-risk nil :low-risk nil))
   (let ((decision '(:experiment-id "exp-001"
                     :approval-type :require-review
                     :target "critical.el"
                     :risk-factors (:files-changed 10 :complexity 0.9))))
     (gptel-auto-workflow--process-approval-decision decision)
     (should (= 1 (length gptel-auto-workflow--notification-queue)))
     (let ((alert (car gptel-auto-workflow--notification-queue)))
       (should (eq :high (plist-get alert :level)))))))

(ert-deftest test-human-interface/full-workflow ()
  "Should run full workflow: decision -> alert -> notification."
  (with-clean-human-interface-state
   (setq gptel-auto-workflow--notification-thresholds
         '(:high-risk t :medium-risk t :low-risk nil))
   (setq gptel-auto-workflow--notification-methods '(:message))
   (let ((decisions '((:experiment-id "exp-001"
                       :approval-type :auto-approved
                       :target "simple.el")
                      (:experiment-id "exp-002"
                       :approval-type :recommend-confirm
                       :target "module.el")
                      (:experiment-id "exp-003"
                       :approval-type :require-review
                       :target "critical.el"))))
     ;; Process all decisions
     (dolist (decision decisions)
       (gptel-auto-workflow--process-approval-decision decision))
     ;; Should have 2 alerts (medium and high risk)
     (should (= 2 (length gptel-auto-workflow--notification-queue)))
     ;; Process alerts
     (let ((delivered (gptel-auto-workflow--process-alert-queue)))
       (should (= 2 (length delivered)))
       (should (= 0 (length gptel-auto-workflow--notification-queue)))
       (should (= 2 (length gptel-auto-workflow--alert-history)))))))

(ert-deftest test-human-interface/dashboard-with-alerts ()
  "Should generate dashboard with alert information."
  (with-clean-human-interface-state
   (setq gptel-auto-workflow--approval-history
         '((:experiment-id "exp-001" :approval-type :require-review :target "critical.el")
           (:experiment-id "exp-002" :approval-type :auto-approved :target "simple.el")))
   (setq gptel-auto-workflow--alert-history
         '((:level :high :message "High-risk" :experiment-id "exp-001"
                   :timestamp "2026-06-06T10:00:00Z")))
   (let ((dashboard (gptel-auto-workflow--generate-dashboard-summary)))
     (should (plist-get dashboard :recent-alerts))
     (should (= 1 (length (plist-get dashboard :recent-alerts)))))))

;; ============================================================================
;; Edge Cases
;; ============================================================================

(ert-deftest test-human-interface/empty-history ()
  "Should handle empty approval history gracefully."
  (with-clean-human-interface-state
   (setq gptel-auto-workflow--approval-history nil)
   (let ((dashboard (gptel-auto-workflow--generate-dashboard-summary)))
     (should (plist-get dashboard :total-experiments))
     (should (= 0 (plist-get dashboard :total-experiments)))
     (should (= 0.0 (plist-get dashboard :auto-approval-rate))))))

(ert-deftest test-human-interface/malformed-decision ()
  "Should handle malformed decision data."
  (with-clean-human-interface-state
   (let ((decision '(:experiment-id "exp-001"))) ; Missing approval-type
     ;; Should not error
     (should-not (gptel-auto-workflow--process-approval-decision decision)))))

(ert-deftest test-human-interface/large-history ()
  "Should handle large approval history efficiently."
  (with-clean-human-interface-state
   ;; Create 100 decisions
   (setq gptel-auto-workflow--approval-history
         (cl-loop for i from 1 to 100
                  collect (list :experiment-id (format "exp-%03d" i)
                               :approval-type (if (zerop (mod i 3))
                                                  :require-review
                                                :auto-approved))))
   (let ((dashboard (gptel-auto-workflow--generate-dashboard-summary)))
     (should (= 100 (plist-get dashboard :total-experiments)))
     (should (> (plist-get dashboard :auto-approved-count) 0))
     (should (> (plist-get dashboard :review-count) 0)))))

(provide 'test-gptel-auto-workflow-human-interface)

;;; test-gptel-auto-workflow-human-interface.el ends here
