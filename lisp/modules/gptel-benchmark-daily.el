;;; gptel-benchmark-daily.el --- Daily workflow/skill integration -*- lexical-binding: t; -*-

;; Copyright (C) 2025 David Wu
;; Author: David Wu
;; Version: 1.0.0
;; Keywords: ai, benchmark, daily, integration

;;; Commentary:

;; Integration layer for using benchmark system in daily workflow/skill operations.
;;
;; Features:
;; - Auto-collect metrics on every skill/workflow run
;; - Periodic evolution cycles
;; - Dashboard for quick status
;; - Hooks for seamless integration
;;
;; Usage:
;;   (gptel-benchmark-daily-setup)  ; Enable daily integration
;;   M-x gptel-benchmark-dashboard   ; Show status
;;   M-x gptel-benchmark-daily-review ; Review today's results

;;; Code:

(require 'cl-lib)
(require 'gptel-benchmark-principles)
(require 'gptel-benchmark-core)
(require 'gptel-benchmark-evolution)
(require 'gptel-benchmark-auto-improve)
(require 'gptel-benchmark-integrate)

;;; Customization

(defgroup gptel-benchmark-daily nil
  "Daily integration for benchmarking."
  :group 'gptel-benchmark)

(defcustom gptel-benchmark-daily-auto-collect t
  "Whether to auto-collect metrics on skill/workflow runs."
  :type 'boolean
  :group 'gptel-benchmark-daily)

(defcustom gptel-benchmark-daily-evolution-interval 5
  "Run evolution cycle every N benchmark runs."
  :type 'integer
  :group 'gptel-benchmark-daily)

(defcustom gptel-benchmark-daily-report-time "18:00"
  "Time to show daily report (24h format, or nil to disable)."
  :type '(choice (string :tag "Time")
                 (const :tag "Disabled" nil))
  :group 'gptel-benchmark-daily)

;;; State

(defvar gptel-benchmark-daily-runs nil
  "List of today's benchmark runs.")

(defvar gptel-benchmark-daily-run-count 0
  "Count of runs since last evolution cycle.")

(defvar gptel-benchmark-daily-timer nil
  "Timer for daily report.")

;;; Setup

(defun gptel-benchmark-daily-setup ()
  "Setup daily benchmark integration.
Adds hooks to auto-collect metrics on skill/workflow runs."
  (interactive)
  ;; Hook into workflow execution
  (advice-add 'gptel-workflow-benchmark-run :after
              #'gptel-benchmark-daily--collect-workflow)
  
  ;; Hook into skill execution
  (advice-add 'gptel-skill-benchmark-run :after
              #'gptel-benchmark-daily--collect-skill)
  
  ;; Setup daily report timer
  (when gptel-benchmark-daily-report-time
    (gptel-benchmark-daily--setup-report-timer))
  
  (message "[daily-bench] Integration enabled"))

(defun gptel-benchmark-daily-teardown ()
  "Remove daily benchmark integration hooks."
  (interactive)
  (advice-remove 'gptel-workflow-benchmark-run
                 #'gptel-benchmark-daily--collect-workflow)
  (advice-remove 'gptel-skill-benchmark-run
                 #'gptel-benchmark-daily--collect-skill)
  (when gptel-benchmark-daily-timer
    (cancel-timer gptel-benchmark-daily-timer))
  (message "[daily-bench] Integration disabled"))

;;; Collection Hooks

(defun gptel-benchmark-daily--collect-workflow (workflow-name test-id)
  "Collect metrics after workflow run.
WORKFLOW-NAME and TEST-ID from the advised function."
  (when gptel-benchmark-daily-auto-collect
    (let ((entry (list :type 'workflow
                       :name workflow-name
                       :test-id test-id
                       :timestamp (format-time-string "%H:%M:%S"))))
      (push entry gptel-benchmark-daily-runs)
      (cl-incf gptel-benchmark-daily-run-count)
      (gptel-benchmark-daily--maybe-evolve))))

(defun gptel-benchmark-daily--collect-skill (skill-name test-id)
  "Collect metrics after skill run.
SKILL-NAME and TEST-ID from the advised function."
  (when gptel-benchmark-daily-auto-collect
    (let ((entry (list :type 'skill
                       :name skill-name
                       :test-id test-id
                       :timestamp (format-time-string "%H:%M:%S"))))
      (push entry gptel-benchmark-daily-runs)
      (cl-incf gptel-benchmark-daily-run-count)
      (gptel-benchmark-daily--maybe-evolve))))

(defun gptel-benchmark-daily--maybe-evolve ()
  "Run evolution cycle if interval reached."
  (when (>= gptel-benchmark-daily-run-count
             gptel-benchmark-daily-evolution-interval)
    (setq gptel-benchmark-daily-run-count 0)
    (gptel-benchmark-evolution-cycle "daily-interval")
    (message "[daily-bench] Evolution cycle triggered")))

;;; Dashboard

(defun gptel-benchmark-dashboard ()
  "Show benchmark dashboard."
  (interactive)
  (let* ((evolution-state gptel-benchmark-evolution-state)
         (capabilities (plist-get evolution-state :capabilities))
         (cycle (plist-get evolution-state :cycle))
         (improvements gptel-benchmark-improvements)
         (today-runs gptel-benchmark-daily-runs))
    (with-output-to-temp-buffer "*Benchmark Dashboard*"
      (princ "╔══════════════════════════════════════════════════╗\n")
      (princ "║          BENCHMARK DAILY DASHBOARD               ║\n")
      (princ "╚══════════════════════════════════════════════════╝\n\n")
      
      ;; Evolution Status
      (princ "┌─────────────────────────────────────────────────┐\n")
      (princ "│ EVOLUTION STATUS                               │\n")
      (princ "├─────────────────────────────────────────────────┤\n")
      (princ (format "│ Cycles: %-5d  Capabilities: %-2d  COMPLETE: %s │\n"
                     cycle
                     (length capabilities)
                     (if (plist-get evolution-state :ai-complete-p) "YES" "No ")))
      (princ "└─────────────────────────────────────────────────┘\n\n")
      
      ;; Capabilities
      (princ "┌─────────────────────────────────────────────────┐\n")
      (princ "│ CAPABILITY EMERGENCE (相生 Pathway)            │\n")
      (princ "├─────────────────────────────────────────────────┤\n")
      (dolist (cap '(interface capability self-awareness extension memory))
        (princ (format "│ %s %-13s                            │\n"
                       (if (memq cap capabilities) "✓" "○")
                       cap)))
      (princ "└─────────────────────────────────────────────────┘\n\n")
      
      ;; Today's Activity
      (princ "┌─────────────────────────────────────────────────┐\n")
      (princ (format "│ TODAY'S ACTIVITY (%s)                    │\n"
                     (format-time-string "%Y-%m-%d")))
      (princ "├─────────────────────────────────────────────────┤\n")
      (princ (format "│ Runs: %-4d  Improvements: %-4d               │\n"
                     (length today-runs)
                     (length improvements)))
      (princ "└─────────────────────────────────────────────────┘\n\n")
      
      ;; Wu Xing Health
      (princ "┌─────────────────────────────────────────────────┐\n")
      (princ "│ WU XING ELEMENT HEALTH                         │\n")
      (princ "├─────────────────────────────────────────────────┤\n")
      (let ((diagnosis (gptel-benchmark-diagnose-elements
                         (list (cons nil (list :overall-score 0.8)))))
            (elements '(water wood fire earth metal)))
        (dolist (el elements)
          (let* ((d (cl-find-if (lambda (x) (eq (plist-get x :element) el)) diagnosis))
                 (score (if d (plist-get d :score) 0.5))
                 (status (if d (plist-get d :status) 'unknown)))
            (princ (format "│ %-5s %s %-6.0f%%  %-10s              │\n"
                           el
                           (pcase status
                             ('excellent "████")
                             ('healthy  "███░")
                             ('adequate "██░░")
                             ('deficient "█░░░")
                             ('critical "░░░░")
                             (_ "████"))
                           (* 100 score)
                           status)))))
      (princ "└─────────────────────────────────────────────────┘\n\n")
      
      ;; Quick Actions
      (princ "┌─────────────────────────────────────────────────┐\n")
      (princ "│ QUICK ACTIONS                                  │\n")
      (princ "├─────────────────────────────────────────────────┤\n")
      (princ "│ M-x gptel-benchmark-daily-review    Review day │\n")
      (princ "│ M-x gptel-benchmark-evolution-cycle Next cycle │\n")
      (princ "│ M-x gptel-benchmark-improvement-report History │\n")
      (princ "└─────────────────────────────────────────────────┘\n"))))

;;; Daily Review

(defun gptel-benchmark-daily-review ()
  "Review today's benchmark activity."
  (interactive)
  (let ((runs (reverse gptel-benchmark-daily-runs))
        (improvements gptel-benchmark-improvements))
    (with-output-to-temp-buffer "*Daily Benchmark Review*"
      (princ "╔══════════════════════════════════════════════════╗\n")
      (princ (format "║        DAILY REVIEW - %s              ║\n"
                     (format-time-string "%Y-%m-%d")))
      (princ "╚══════════════════════════════════════════════════╝\n\n")
      
      ;; Summary
      (princ "【SUMMARY】\n")
      (princ (format "  Total runs: %d\n" (length runs)))
      (princ (format "  Improvements applied: %d\n" (length improvements)))
      (princ (format "  Evolution cycles: %d\n\n"
                     (/ (length runs) gptel-benchmark-daily-evolution-interval)))
      
      ;; Runs by type
      (let ((skills 0) (workflows 0))
        (dolist (r runs)
          (if (eq (plist-get r :type) 'skill)
              (cl-incf skills)
            (cl-incf workflows)))
        (princ "【BY TYPE】\n")
        (princ (format "  Skills: %d  |  Workflows: %d\n\n" skills workflows)))
      
      ;; Recent improvements
      (princ "【RECENT IMPROVEMENTS】\n")
      (if improvements
          (let ((recent (seq-take improvements 5)))
            (dolist (impr recent)
              (princ (format "  %s %s/%s: %s\n"
                             (plist-get impr :timestamp)
                             (plist-get impr :type)
                             (plist-get impr :name)
                             (plist-get (plist-get impr :improvement) :action)))))
        (princ "  None today\n")))))

;;; Report Timer

(defun gptel-benchmark-daily--setup-report-timer ()
  "Setup timer for daily report."
  (when gptel-benchmark-daily-timer
    (cancel-timer gptel-benchmark-daily-timer))
  (let* ((time-parts (split-string gptel-benchmark-daily-report-time ":"))
         (hour (string-to-number (car time-parts)))
         (min (string-to-number (cadr time-parts)))
         (now (decode-time))
         (now-hour (decoded-time-hour now))
         (now-min (decoded-time-minute now))
         (secs-until (+ (* (- hour now-hour) 3600)
                        (* (- min now-min) 60)))
         (run-today (or (> hour now-hour)
                        (and (= hour now-hour) (> min now-min)))))
    (setq gptel-benchmark-daily-timer
          (run-with-timer secs-until nil
                          #'gptel-benchmark-daily--show-report))))

(defun gptel-benchmark-daily--show-report ()
  "Show daily report notification."
  (message "[daily-bench] Daily report: %d runs, %d improvements, %d capabilities"
           (length gptel-benchmark-daily-runs)
           (length gptel-benchmark-improvements)
           (length (plist-get gptel-benchmark-evolution-state :capabilities))))

;;; Auto-benchmark on Save/Commit

(defun gptel-benchmark-daily-after-save ()
  "Hook to run after saving benchmark-related files."
  (when (and buffer-file-name
             (string-match-p "workflow-tests\\|skill-tests" buffer-file-name))
    (message "[daily-bench] Test file saved - consider running benchmarks")))

(defun gptel-benchmark-daily-after-commit ()
  "Hook to run after git commit."
  (let ((msg (shell-command-to-string "git log -1 --format=%s")))
    (when (string-match-p "λ\\|◈\\|Δ" msg)
      (message "[daily-bench] Learning commit detected - evolution cycle")
      (gptel-benchmark-evolution-cycle "commit-hook"))))

;;; Integration with Existing Commands

(defun gptel-benchmark-daily-wrap-skill-run (orig-fun &rest args)
  "Wrap skill run to auto-collect metrics."
  (let ((result (apply orig-fun args)))
    (when gptel-benchmark-daily-auto-collect
      (let ((entry (list :type 'skill
                         :name (car args)
                         :test-id (cadr args)
                         :timestamp (format-time-string "%H:%M:%S")
                         :result result)))
        (push entry gptel-benchmark-daily-runs)
        (cl-incf gptel-benchmark-daily-run-count)
        (gptel-benchmark-daily--maybe-evolve)))
    result))

;;; Report Generation

(defun gptel-benchmark-daily-report-json ()
  "Generate JSON report of daily activity."
  (let ((report (list :date (format-time-string "%Y-%m-%d")
                      :runs (length gptel-benchmark-daily-runs)
                      :improvements (length gptel-benchmark-improvements)
                      :capabilities (length (plist-get gptel-benchmark-evolution-state :capabilities))
                      :ai-complete (plist-get gptel-benchmark-evolution-state :ai-complete-p)
                      :evolution-cycle (plist-get gptel-benchmark-evolution-state :cycle))))
    (json-encode report)))

;;; Provide

(provide 'gptel-benchmark-daily)

;;; gptel-benchmark-daily.el ends here