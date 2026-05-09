;;; gptel-auto-workflow-production.el --- Production integration for self-evolution -*- lexical-binding: t -*-

;; This module ties all self-evolution components together for production use.
;; It runs automatically when the auto-workflow daemon is active.

(require 'cl-lib)
(require 'gptel-auto-workflow-evolution)

;; ─── Configuration ───

(defcustom gptel-auto-workflow-evolution-interval 3600
  "Seconds between automatic evolution cycles (default: 1 hour)."
  :type 'integer
  :group 'gptel-tools-agent)

(defvar gptel-auto-workflow--evolution-timer nil
  "Timer for periodic evolution cycles.")

;; ─── Automatic Evolution ───

(defun gptel-auto-workflow--maybe-run-evolution ()
  "Run evolution cycle if enabled and not already running."
  (when (and gptel-auto-workflow-evolution-enabled
             (fboundp 'gptel-auto-workflow-evolution-run-cycle))
    (condition-case err
        (progn
          (message "[auto-workflow] Running scheduled evolution cycle...")
          (gptel-auto-workflow-evolution-run-cycle)
          (message "[auto-workflow] Evolution cycle complete."))
      (error
       (message "[auto-workflow] Evolution cycle error: %s" err)))))

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
                        (lambda (r) (plist-get r :kept))
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
      (insert (format "  Evolution enabled: %s\n" gptel-auto-workflow-evolution-enabled))
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
          (error nil)))
      
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
          (error nil)))
      
      (insert "\nPress q to quit\n")
      (goto-char (point-min))
      (local-set-key (kbd "q") #'kill-buffer-and-window))
     (pop-to-buffer buf))))

;; ─── Auto-start ───

(defun gptel-auto-workflow-evolution-auto-start ()
  "Auto-start evolution if enabled."
  (when gptel-auto-workflow-evolution-enabled
    (gptel-auto-workflow-start-evolution-timer)
    ;; Run initial cycle
    (run-with-idle-timer 60 nil #'gptel-auto-workflow--maybe-run-evolution)))

;; Start on load if daemon is running
(when (and (daemonp)
           gptel-auto-workflow-evolution-enabled)
  (gptel-auto-workflow-evolution-auto-start))

;; ─── Pipeline Verification ───

(defun gptel-auto-workflow--verify-pipeline-integration ()
  "Verify that research findings feed into directive and auto-workflow.
Checks:
1. Research findings file exists and has content
2. Directive skill exists and references recent findings
3. Research context is set for next auto-workflow run
Returns t if all checks pass, nil with warnings otherwise."
  (let* ((findings-file (expand-file-name "var/tmp/research-findings.md"))
         (directive-file (expand-file-name "assistant/skills/auto-workflow/DIRECTIVE.md"))
         (findings-ok nil)
         (directive-ok nil)
         (context-ok nil)
         (issues nil))
    
    ;; Check 1: Findings file
    (if (and (file-exists-p findings-file)
             (> (nth 7 (file-attributes findings-file)) 100))
        (setq findings-ok t)
      (push "Research findings file missing or too small" issues))
    
    ;; Check 2: Directive references findings (has been updated recently)
    (if (file-exists-p directive-file)
        (let ((mtime (nth 5 (file-attributes directive-file)))
              (findings-mtime (when (file-exists-p findings-file)
                                (nth 5 (file-attributes findings-file)))))
          (if (and findings-mtime mtime
                   (time-less-p findings-mtime mtime))
              (setq directive-ok t)
            (push "Directive not updated after latest findings" issues)))
      (push "Directive skill file not found" issues))
    
    ;; Check 3: Research context available
    (if (and (boundp 'gptel-auto-workflow--current-research-context)
             gptel-auto-workflow--current-research-context
             (plist-get gptel-auto-workflow--current-research-context :digested))
        (setq context-ok t)
      (push "No digested research context available" issues))
    
    ;; Report
    (if (and findings-ok directive-ok context-ok)
        (progn
          (message "[pipeline-verification] ✓ All checks passed: findings→directive integration working")
          t)
      (progn
        (message "[pipeline-verification] ✗ Issues found: %s"
                 (string-join (reverse issues) "; "))
        nil))))

(provide 'gptel-auto-workflow-production)
;;; gptel-auto-workflow-production.el ends here
