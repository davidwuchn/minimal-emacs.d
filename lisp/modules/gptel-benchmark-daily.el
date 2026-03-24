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
(require 'gptel-benchmark-memory)
(require 'gptel-benchmark-instincts nil t)

;;; Customization

(defgroup gptel-benchmark-daily nil
  "Daily integration for benchmarking."
  :group 'gptel-benchmark)

(defcustom gptel-benchmark-daily-auto-collect t
  "Whether to auto-collect metrics on skill/workflow runs."
  :type 'boolean
  :group 'gptel-benchmark-daily)

(defcustom gptel-benchmark-daily-evolution-interval 5
  "Base interval for evolution cycles.
Adaptive mode adjusts this based on φ (vitality) scores:
  - High φ (>0.7): Longer interval (stable patterns)
  - Low φ (<0.5): Shorter interval (needs validation)"
  :type 'integer
  :group 'gptel-benchmark-daily)

(defcustom gptel-benchmark-daily-adaptive-interval t
  "Whether to adapt evolution interval based on φ scores."
  :type 'boolean
  :group 'gptel-benchmark-daily)

;;; State

(defvar gptel-benchmark-daily-runs nil
  "List of today's benchmark runs.")

(defvar gptel-benchmark-daily-run-count 0
  "Count of runs since last evolution cycle.")

;;; Setup

(defun gptel-benchmark-daily-setup ()
  "Setup daily benchmark integration.
Adds hooks to auto-collect metrics on skill/workflow runs.
Reads mementum state on session start for continuity.
All scheduled tasks moved to cron (see cron.d/auto-workflow)."
  (interactive)
  (gptel-benchmark-memory-orient)
  (advice-add 'gptel-workflow-benchmark-run :around
              #'gptel-benchmark-daily--wrap-workflow-run)
  (advice-add 'gptel-skill-benchmark-run :around
              #'gptel-benchmark-daily--wrap-skill-run)
  (message "[daily-bench] Integration enabled (scheduled tasks via cron)"))

(defun gptel-benchmark-daily-teardown ()
  "Remove daily benchmark integration hooks."
  (interactive)
  (advice-remove 'gptel-workflow-benchmark-run
                 #'gptel-benchmark-daily--wrap-workflow-run)
  (advice-remove 'gptel-skill-benchmark-run
                 #'gptel-benchmark-daily--wrap-skill-run)
  (message "[daily-bench] Integration disabled"))

;;; Collection Hooks

(defun gptel-benchmark-daily--wrap-workflow-run (orig-fun &rest args)
  "Wrap workflow run to auto-collect metrics.
ORIG-FUN is the original function, ARGS are its arguments."
  (let* ((workflow-name (car args))
         (test-id (cadr args))
         (result (apply orig-fun args)))
    (when gptel-benchmark-daily-auto-collect
      (let ((entry (list :type 'workflow
                         :name workflow-name
                         :test-id test-id
                         :results result
                         :timestamp (format-time-string "%H:%M:%S"))))
        (push entry gptel-benchmark-daily-runs)
        (gptel-benchmark-daily--update-state entry)
        (cl-incf gptel-benchmark-daily-run-count)
        (gptel-benchmark-daily--maybe-evolve entry)))
    result))

(defun gptel-benchmark-daily--wrap-skill-run (orig-fun &rest args)
  "Wrap skill run to auto-collect metrics.
ORIG-FUN is the original function, ARGS are its arguments."
  (let* ((skill-name (car args))
         (test-id (cadr args))
         (result (apply orig-fun args)))
    (when gptel-benchmark-daily-auto-collect
      (let ((entry (list :type 'skill
                         :name skill-name
                         :test-id test-id
                         :results result
                         :timestamp (format-time-string "%H:%M:%S"))))
        (push entry gptel-benchmark-daily-runs)
        (gptel-benchmark-daily--update-state entry)
        (cl-incf gptel-benchmark-daily-run-count)
        (gptel-benchmark-daily--maybe-evolve entry)))
    result))

(defun gptel-benchmark-daily--update-state (entry)
  "Update mementum state with ENTRY summary."
  (let* ((type (plist-get entry :type))
         (name (plist-get entry :name))
         (timestamp (plist-get entry :timestamp))
         (results (plist-get entry :results))
         (state-content (gptel-benchmark-memory-read-state))
         (new-section (format "\n### Run: %s/%s @ %s\n- Result: %s\n"
                              type name timestamp
                              (if results "completed" "unknown"))))
    (when state-content
      (gptel-benchmark-memory-update-state
       (concat state-content new-section)))))

(defun gptel-benchmark-daily--adaptive-interval ()
  "Calculate adaptive evolution interval based on φ scores.
Higher φ → longer interval (stable patterns need less evolution).
Lower φ → shorter interval (experimental patterns need more validation)."
  (if (not gptel-benchmark-daily-adaptive-interval)
      gptel-benchmark-daily-evolution-interval
    (let* ((memories (gptel-benchmark-memory-list 'memories))
           (total-phi 0.0)
           (count 0))
      (dolist (mem memories)
        (let ((phi (or (plist-get (car mem) :phi) 0.5)))
          (setq total-phi (+ total-phi phi))
          (cl-incf count)))
      (if (= count 0)
          gptel-benchmark-daily-evolution-interval
        (let* ((avg-phi (/ total-phi count))
               (multiplier (cond ((> avg-phi 0.7) 1.5)
                                 ((< avg-phi 0.5) 0.5)
                                 (t 1.0))))
          (max 1 (round (* gptel-benchmark-daily-evolution-interval multiplier))))))))

(defun gptel-benchmark-daily--maybe-evolve (entry)
  "Run evolution cycle if interval reached.
ENTRY contains run details including results."
  (let ((effective-interval (gptel-benchmark-daily--adaptive-interval)))
    (when (>= gptel-benchmark-daily-run-count effective-interval)
      (setq gptel-benchmark-daily-run-count 0)
      (let* ((name (plist-get entry :name))
             (type (plist-get entry :type))
             (results (plist-get entry :results)))
        (if results
            (progn
              (gptel-benchmark-evolve-with-improvement name type results)
              (message "[daily-bench] Evolution + improvement cycle completed for %s/%s (interval: %d)" type name effective-interval))
          (gptel-benchmark-evolution-cycle "daily-interval")
          (message "[daily-bench] Evolution cycle triggered (interval: %d)" effective-interval)))
      (gptel-benchmark-daily--check-synthesis))))

(defun gptel-benchmark-daily--check-synthesis ()
  "Check if any topics are ready for synthesis.
Triggers synthesis for:
  1. Topics with >= 3 memories
  2. Patterns with φ > 0.8 (crystallized)
  3. Contradictory memories (needs reconciliation)"
  (let* ((memories (gptel-benchmark-memory-list 'memories))
         (topic-counts (make-hash-table :test 'equal))
         (high-phi-patterns '())
         (contradictions '()))
    (dolist (mem memories)
      (let* ((slug (cadr mem))
             (meta (car mem))
             (phi (or (plist-get meta :phi) 0.5))
             (topic (replace-regexp-in-string "-[0-9]+$" "" (file-name-sans-extension slug))))
        (puthash topic (1+ (gethash topic topic-counts 0)) topic-counts)
        (when (> phi 0.8)
          (push (cons topic phi) high-phi-patterns))))
    (maphash
     (lambda (topic count)
       (when (>= count 3)
         (message "[daily-bench] Synthesizing topic: %s (%d memories)" topic count)
         (gptel-benchmark-memory-synthesize topic)))
     topic-counts)
    (dolist (pattern high-phi-patterns)
      (message "[daily-bench] Crystallized pattern: %s (φ=%.2f) → knowledge candidate"
               (car pattern) (cdr pattern)))
    (when contradictions
      (message "[daily-bench] Contradictions detected: %d topics need reconciliation"
               (length contradictions)))))

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