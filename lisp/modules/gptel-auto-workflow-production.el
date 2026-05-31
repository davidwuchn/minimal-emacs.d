;;; gptel-auto-workflow-production.el --- Production integration for self-evolution -*- lexical-binding: t -*-

;; This module ties all self-evolution components together for production use.
;; It runs automatically when the auto-workflow daemon is active.

(require 'cl-lib)
(declare-function gptel-auto-workflow-evolution-run-cycle "gptel-auto-workflow-evolution")
(declare-function gptel-auto-workflow--worktree-base-root "gptel-tools-agent-base")

;; ─── Configuration ───

(defcustom gptel-auto-workflow-evolution-interval 3600
  "Seconds between automatic evolution cycles (default: 1 hour)."
  :type 'integer
  :group 'gptel-tools-agent)

(defvar gptel-auto-workflow--evolution-timer nil
  "Timer for periodic evolution cycles.")

(defvar gptel-auto-workflow--gc-timer nil
  "Timer for periodic garbage collection.")

(defun gptel-auto-workflow--gc-trigger ()
  "Force garbage collection to prevent memory growth.
Emacs GC doesn't release memory to the OS, but periodic GC
prevents further allocation growth by reusing freed pages.
Runs every 300s (5min) to keep RSS from runaway growth."
  (garbage-collect)
  (message "[mem] GC triggered: %s"
           (let ((stats (gptel-auto-workflow--memory-status)))
             (mapconcat (lambda (m) (format "%s" (plist-get m :state)))
                        stats "; "))))

(defun gptel-auto-workflow-start-gc-timer ()
  "Start periodic GC timer."
  (gptel-auto-workflow-stop-gc-timer)
  (setq gptel-auto-workflow--gc-timer
        (run-with-timer 300 300 #'gptel-auto-workflow--gc-trigger))
  (message "[auto-workflow] GC timer started (300 second intervals)"))

(defun gptel-auto-workflow-stop-gc-timer ()
  "Stop GC timer."
  (when gptel-auto-workflow--gc-timer
    (cancel-timer gptel-auto-workflow--gc-timer)
    (setq gptel-auto-workflow--gc-timer nil)))

;; ─── Automatic Evolution ───

(defun gptel-auto-workflow--maybe-run-evolution ()
  "Run evolution cycle if enabled and not already running.
Also runs periodic mementum maintenance (index rebuild + synthesis)
every cycle when there are candidate memories to process."
  (when (and (bound-and-true-p gptel-auto-workflow-evolution-enabled)
             (fboundp 'gptel-auto-workflow-evolution-run-cycle))
    ;; Ensure base functions are available (breaks circular require)
    (unless (fboundp 'gptel-auto-workflow--worktree-base-root)
      (condition-case nil
          (load "gptel-tools-agent-base" nil t)
        (error nil)))
    (condition-case err
        (progn
          (message "[auto-workflow] Running scheduled evolution cycle...")
          (gptel-auto-workflow-evolution-run-cycle)
          (message "[auto-workflow] Evolution cycle complete."))
      (error
       (message "[auto-workflow] Evolution cycle error: %s" err)
       (let* ((frames (backtrace-frames))
              (bt (mapconcat (lambda (f) (format "  %S" f))
                             (seq-take frames 50) "\n"))
               (log-file (expand-file-name "var/tmp/cron/evolution-backtrace.log"
                                          (or (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                                                   (gptel-auto-workflow--worktree-base-root))
                                              user-emacs-directory))))
         (when (> (length bt) 0)
           (message "[auto-workflow] Evolution cycle backtrace:\n%s" bt)
           (make-directory (file-name-directory log-file) t)
           (with-temp-file log-file
             (insert (format-time-string "%Y-%m-%d %H:%M:%S\n"))
             (insert (format "Error: %s\n" err))
             (insert "Backtrace (50 frames):\n" bt "\n"))))))
    ;; Mementum maintenance: rebuild index + synthesize candidates.
    ;; Runs every cycle (hourly) but is cheap when no new memories exist.
    ;; Enable auto-approve in headless so synthesis actually writes files.
    (condition-case nil
        (when (fboundp 'gptel-mementum-build-index)
          (let ((gptel-mementum-headless-auto-approve t))
            (gptel-mementum-build-index)
            (when (fboundp 'gptel-mementum-synthesize-all-candidates)
              (gptel-mementum-synthesize-all-candidates nil t))))
      (error
       (message "[mementum] Maintenance error in evolution cycle")))))

(defun gptel-auto-workflow-start-evolution-timer ()
  "Start periodic evolution timer."
  (interactive)
  (gptel-auto-workflow-stop-evolution-timer)
  (setq gptel-auto-workflow--evolution-timer
        (run-with-timer gptel-auto-workflow-evolution-interval
                        gptel-auto-workflow-evolution-interval
                        #'gptel-auto-workflow--maybe-run-evolution))
  (message "[auto-workflow] Evolution timer started (%d second intervals)"
           gptel-auto-workflow-evolution-interval))

(defun gptel-auto-workflow-stop-evolution-timer ()
  "Stop evolution timer."
  (interactive)
  (when gptel-auto-workflow--evolution-timer
    (cancel-timer gptel-auto-workflow--evolution-timer)
    (setq gptel-auto-workflow--evolution-timer nil)
    (message "[auto-workflow] Evolution timer stopped")))

;; ─── Experiment Hook ───

(defvar gptel-auto-workflow--research-batch-results nil
  "Accumulator for research batch tracking.
List of experiment results sharing the same research context.
Reset when research context changes.")

(defun gptel-auto-workflow--experiment-complete-hook (experiment)
  "Hook called when EXPERIMENT completes.
Records to mementum and triggers evolution if needed."
  ;; Record to mementum
  (when (fboundp 'gptel-auto-workflow--mementum-record-experiment)
    (condition-case err
        (gptel-auto-workflow--mementum-record-experiment experiment)
      (error
       (message "[auto-workflow] Mementum recording error: %s" err))))
  
  ;; Track research batch for meta-learning
  (let ((research-hash (plist-get experiment :research-hash)))
    (when (and research-hash (not (equal research-hash "none")))
      ;; Check if this is a new research context
      (when (and gptel-auto-workflow--research-batch-results
                 (not (equal research-hash
                            (plist-get (car gptel-auto-workflow--research-batch-results) :research-hash))))
        ;; Research context changed - record previous batch
        (gptel-auto-workflow--record-research-batch))
      ;; Add to current batch
      (push experiment gptel-auto-workflow--research-batch-results)))
  
  ;; Record to holographic memory (verbum Phase 7)
  (when (fboundp 'gptel-auto-workflow--record-holographic-experiment)
    (condition-case err
        (gptel-auto-workflow--record-holographic-experiment experiment)
      (error (message "[auto-workflow] Holographic recording error: %s" err))))
  
  ;; Run evolution every N experiments
  (let ((exp-id (or (plist-get experiment :id) 0)))
    (when (and (> exp-id 0)
               (zerop (% exp-id 5))
               (fboundp 'gptel-auto-workflow-evolution-run-cycle))
      (run-with-idle-timer 30 nil #'gptel-auto-workflow--maybe-run-evolution))))

(defun gptel-auto-workflow--record-research-batch ()
  "Record accumulated research batch to mementum.
Called when research context changes or run completes."
  (when (and gptel-auto-workflow--research-batch-results
             (fboundp 'gptel-auto-workflow--mementum-record-research))
    (let* ((first-result (car gptel-auto-workflow--research-batch-results))
           (strategy (plist-get first-result :research-strategy))
           (hash (plist-get first-result :research-hash))
           (targets (delete-dups
                     (mapcar (lambda (r) (plist-get r :target))
                             gptel-auto-workflow--research-batch-results)))
            (kept-count (cl-count-if
                         (lambda (r) (eq (plist-get r :kept) t))
                         gptel-auto-workflow--research-batch-results))
           (total-count (length gptel-auto-workflow--research-batch-results)))
       (condition-case err
           (gptel-auto-workflow--mementum-record-research
            (list :strategy strategy
                  :hash hash
                  :targets targets
                  :kept-count kept-count
                  :total-count total-count
                  :findings (or (and (boundp 'gptel-auto-workflow--current-research-context)
                                     (plist-get gptel-auto-workflow--current-research-context :findings))
                                "")
                  :digested (or (and (boundp 'gptel-auto-workflow--current-research-context)
                                     (plist-get gptel-auto-workflow--current-research-context :digested))
                                "")))
         (error
          (message "[auto-workflow] Research recording error: %s" err))))
  ;; Reset batch
  (setq gptel-auto-workflow--research-batch-results nil))

;; ─── Status Dashboard ───

(defun gptel-auto-workflow-evolution-status ()
  "Show evolution system status."
  (interactive)
  (let ((buf (get-buffer-create "*Auto-Workflow Evolution*")))
    (with-current-buffer buf
      (erase-buffer)
      (insert "=== Auto-Workflow Evolution Status ===\n\n")
      
      ;; Evolution config
      (insert "Configuration:\n")
      (insert (format "  Evolution enabled: %s\n" (bound-and-true-p gptel-auto-workflow-evolution-enabled)))
      (insert (format "  Evolution interval: %d seconds\n" gptel-auto-workflow-evolution-interval))
      (insert (format "  Timer active: %s\n\n" 
                      (if gptel-auto-workflow--evolution-timer "YES" "NO")))
      
      ;; Knowledge file
      (let ((knowledge-file (expand-file-name
                             "mementum/knowledge/self-evolution.md"
                             (if (fboundp 'gptel-auto-workflow--worktree-base-root)
                                 (gptel-auto-workflow--worktree-base-root)
                               "/Users/davidwu/.emacs.d"))))
        (if (file-exists-p knowledge-file)
            (let ((size (nth 7 (file-attributes knowledge-file)))
                  (mtime (nth 5 (file-attributes knowledge-file))))
              (insert "Knowledge Base:\n")
              (insert (format "  File: %s\n" knowledge-file))
              (insert (format "  Size: %d bytes\n" size))
              (insert (format "  Last updated: %s\n\n" 
                              (format-time-string "%Y-%m-%d %H:%M" mtime))))
          (insert "Knowledge Base: NOT FOUND\n\n")))
      
      ;; Git stats
      (when (fboundp 'gptel-auto-workflow--git-raw-facts)
        (condition-case nil
            (let ((facts (gptel-auto-workflow--git-raw-facts)))
              (insert "Git History:\n")
              (insert (format "  Active branches: %d\n" 
                              (plist-get facts :total-active)))
              (insert (format "  Historical merges: %d\n" 
                              (plist-get facts :historical-merges)))
              (insert (format "  Merge rate: %.1f%%\n\n" 
                              (* 100 (plist-get facts :active-merge-rate)))))
          (ignore)))
      
      ;; Benchmark stats
      (when (fboundp 'gptel-auto-experiment--parse-all-results)
        (condition-case nil
            (let* ((records (gptel-auto-experiment--parse-all-results))
                   (total (length records))
                   (kept (cl-count-if (lambda (r) 
                                        (string= (plist-get r :decision) "kept"))
                                      records)))
              (insert "Benchmark Data:\n")
              (insert (format "  Total experiments: %d\n" total))
              (insert (format "  Kept: %d (%.1f%%)\n\n" 
                              kept (* 100.0 (/ (float kept) (max total 1))))))
          (ignore)))
      
      ;; Conflicted target review queue
      (when (and (boundp 'gptel-auto-workflow--conflicted-targets)
                 gptel-auto-workflow--conflicted-targets)
        (insert "Conflicted Target Review:\n")
        (let* ((conflicted (length gptel-auto-workflow--conflicted-targets))
               (review-file (when (fboundp 'gptel-auto-workflow--review-file-path)
                              (gptel-auto-workflow--review-file-path)))
               (decisions (when (and review-file (file-exists-p review-file)
                                     (fboundp 'gptel-auto-workflow--read-review-decisions))
                            (gptel-auto-workflow--read-review-decisions)))
               (approved 0) (dropped 0) (pending conflicted))
          (when decisions
            (maphash (lambda (target dec)
                       (pcase (plist-get dec :decision)
                         ('approved (cl-incf approved) (cl-decf pending))
                         ('dropped (cl-incf dropped) (cl-decf pending))))
                     decisions))
          (insert (format "  Total conflicted: %d\n" conflicted))
          (when (> approved 0)
            (insert (format "  Approved (override): %d\n" approved)))
          (when (> dropped 0)
            (insert (format "  Dropped (human): %d\n" dropped)))
          (insert (format "  Pending review: %d\n" pending))
          (when review-file
            (insert (format "  Review file: %s\n" review-file))))
        (insert "\n"))
      ;; Verbum integration status
      (insert "Verbum Integration:\n")
      (when (boundp 'gptel-auto-workflow--holographic-memory)
        (insert (format "  Holographic memory: %d target-axis pairs\n" 
                        (length gptel-auto-workflow--holographic-memory))))
      ;; Lambda verification report
      (when (fboundp 'gptel-auto-workflow--lambda-verification-report)
        (condition-case nil
            (let ((report (gptel-auto-workflow--lambda-verification-report)))
              (insert "\nLambda Verification Report:\n")
              (insert (format "  Healthy: %d, Degraded: %d, Unknown: %d\n"
                              (plist-get report :healthy)
                              (plist-get report :degraded)
                              (plist-get report :unknown)))
              (dolist (entry (plist-get report :backends))
                (insert (format "  %s: %s\n" (car entry) (cdr entry)))))
          (ignore)))
      (insert "\n")
      
      (insert "\nPress q to quit\n")
      (goto-char (point-min))
      (local-set-key (kbd "q") #'kill-buffer-and-window))
     (pop-to-buffer buf))))

;; ─── Auto-start ───

(defun gptel-auto-workflow-evolution-auto-start ()
  "Auto-start evolution and GC timers if enabled."
  (when (bound-and-true-p gptel-auto-workflow-evolution-enabled)
    (gptel-auto-workflow-start-evolution-timer)
    (gptel-auto-workflow-start-gc-timer)
    ;; Run initial cycle
    (run-with-idle-timer 60 nil #'gptel-auto-workflow--maybe-run-evolution)))

;; τ Wisdom: start on load when daemon is active and evolution is enabled.
(when (and (daemonp)
           (bound-and-true-p gptel-auto-workflow-evolution-enabled))
  (gptel-auto-workflow-evolution-auto-start))

;; ─── Pipeline Verification ───

(defun gptel-auto-workflow--verify-pipeline-integration ()
  "Verify that research findings feed into auto-workflow.
Checks:
1. Research findings file exists and has content
2. Research context is set for next auto-workflow run
Returns t if all checks pass, nil with warnings otherwise."
  (let* ((findings-file (expand-file-name "var/tmp/research-findings.md"))
         (findings-ok nil)
         (context-ok nil)
         (issues nil))
    
    ;; Check 1: Findings file
    (if (and (file-exists-p findings-file)
             (> (nth 7 (file-attributes findings-file)) 100))
        (setq findings-ok t)
      (push "Research findings file missing or too small" issues))
    
    ;; Check 2: Findings are recent (within last 24 hours)
    (let ((findings-mtime (when (file-exists-p findings-file)
                            (nth 5 (file-attributes findings-file)))))
      (if (and findings-mtime
               (time-less-p (time-subtract (current-time) findings-mtime)
                           (seconds-to-time 86400)))
          (setq context-ok t)
        (push "Research findings are stale (>24h old)" issues)))
    
    ;; Report
    (if (and findings-ok context-ok)
        (progn
          (message "[pipeline-verification] ✓ All checks passed")
          t)
      (let ((issue-str (string-join (reverse issues) "; ")))
        (message "[pipeline-verification] ✗ Issues found: %s" issue-str)
        (princ (format "ISSUES: %s\n" issue-str))
        nil))))

(provide 'gptel-auto-workflow-production)
;;; gptel-auto-workflow-production.el ends here
