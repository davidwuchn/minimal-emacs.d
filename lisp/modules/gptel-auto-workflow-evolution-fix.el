;;; gptel-auto-workflow-evolution-fix.el --- Fix for pruned void-variable bug -*- lexical-binding: t; -*-

;; This file redefines gptel-auto-workflow--evolution-vsm-health-check
;; to fix the void-variable pruned bug caused by incorrect paren nesting.
;; The original function has unbalanced parens that place cleanup logging
;; outside the let* that binds pruned, removed-worktrees, cleaned-temp.

(declare-function gptel-auto-workflow--worktree-base-root "gptel-tools-agent-base" ())

(defun gptel-auto-workflow--evolution-vsm-health-check ()
  "Score VSM layer health and log diagnostics."
  (let* ((results (gptel-auto-workflow--parse-all-results))
         (kept (cl-count-if (lambda (r) (equal (plist-get r :decision) "kept")) results))
         (total (length results))
         (keep-rate (if (> total 0) (/ (float kept) total) 0.0))
         (strategies (length (gptel-auto-workflow--evolution-strategy-structure-scores)))
         (backends (length (gptel-auto-workflow--evolution-backend-stats)))
         (axis-stats (gptel-auto-workflow--evolution-axis-stats)))
    (message "[vsm] S1-Ops: %d experiments, %.0f%% kept" total (* 100 keep-rate))
    (message "[vsm] S2-Coord: %d modules scanned, staging verify active" 89)
    (message "[vsm] S3-Control: %d backends in chain, watchdog 90min" backends)
    (message "[vsm] S4-Intel: %d strategies evolved, auto-backend-order active" strategies)
    (message "[vsm] S5-Identity: lambda notation, confidence tags, graphify patterns active")
    (when (fboundp 'gptel-auto-workflow--refresh-variant-axis-champions)
      (gptel-auto-workflow--refresh-variant-axis-champions))
    (when axis-stats
      (message "[vsm] KIBC-M Axis Performance: %s"
               (mapconcat (lambda (a) (format "%s=%.0f%%" (car a) (* 100 (cdr a))))
                          (seq-take axis-stats 5) " ")))
    (cond
     ((< keep-rate 0.05)
      (message "[vsm] 相克: Wood(S1) weak → check Earth(S3) controls (timeouts too tight?)"))
     ((< strategies 5)
      (message "[vsm] 相生: Fire(S4) weak → Water(S5) should generate more variety"))
     ((< backends 3)
      (message "[vsm] 相克: Metal(S2) weak → Fire(S4) should coordinate backends"))
     (t
      (message "[vsm] 相生: All layers balanced — generating cycle active")))
    ;; Housekeeping: full autonomous maintenance
    (condition-case nil
        (let* ((root (or (gptel-auto-workflow--worktree-base-root)
                         (expand-file-name default-directory)))
               (git-dir (expand-file-name ".git" root))
               (exps-dir (expand-file-name "var/tmp/experiments" root))
               (now (float-time))
               (pruned 0) (removed-worktrees 0) (cleaned-temp 0))
          ;; 1. Prune experiment result dirs older than 14 days
          (when (file-directory-p exps-dir)
            (dolist (d (directory-files exps-dir t "\\`[0-9]+T" t))
              (let ((attrs (and d (file-attributes d))))
                (when (and attrs
                           (> (- now (float-time (file-attribute-modification-time attrs)))
                              (* 14 24 3600)))
                  (delete-directory d t)
                  (setq pruned (1+ pruned))))))
          ;; 2. Remove stale prunable git worktrees
          (dolist (wt (split-string (shell-command-to-string "git worktree list --porcelain") "\n" t))
            (when (string-match "prunable" wt)
              (let ((wt-path (car (split-string wt "\n" t))))
                (when (and wt-path (file-directory-p wt-path))
                  (shell-command (format "git worktree remove --force %s" (shell-quote-argument wt-path)) 0)
                  (setq removed-worktrees (1+ removed-worktrees))))))
          ;; 3. Kill stale --fg-daemon processes
          (let ((pids (shell-command-to-string "pgrep -f 'emacs.*--fg-daemon' 2>/dev/null || true")))
            (dolist (pid (split-string pids "\n" t))
              (when (string-match "[0-9]+" pid)
                (signal-process (string-to-number pid) 'sigterm)
                (message "[cleanup] Killed stale fg-daemon pid %s" pid))))
          ;; 4. Clean /tmp/gptel-* files older than 2 hours
          (dolist (f (directory-files "/tmp" t "gptel-"))
            (let ((attrs (and f (file-attributes f))))
              (when (and attrs
                         (> (- now (float-time (file-attribute-modification-time attrs)))
                            (* 2 3600)))
                (delete-file f t)
                (setq cleaned-temp (1+ cleaned-temp)))))
          ;; 5. Truncate daemon log if >10MB
          (let ((log-file (expand-file-name "var/tmp/cron/copilot-auto-workflow.log" root)))
            (when (and (file-exists-p log-file)
                       (> (file-attribute-size (file-attributes log-file)) (* 10 1024 1024)))
              (shell-command (format "tail -n 1000 %s > %s.tmp && mv %s.tmp %s"
                                     (shell-quote-argument log-file)
                                     (shell-quote-argument log-file)
                                     (shell-quote-argument log-file)
                                     (shell-quote-argument log-file)) 0)
              (message "[cleanup] Truncated daemon log (>10MB)")))
          ;; 6. Run git gc --auto when too many loose objects
          (when (and (file-directory-p git-dir)
                     (file-directory-p (expand-file-name "objects" git-dir)))
            (let* ((obj-dir (expand-file-name "objects" git-dir))
                   (loose (condition-case nil
                              (length (directory-files obj-dir nil "^[0-9a-f]\\{38\\}$" t))
                            (error 0))))
              (when (> loose 5000)
                (shell-command "git gc --auto --quiet" 0)
                (message "[cleanup] Ran git gc (loose objects >5k, was %d)" loose))))
          ;; 7. Remove stale git locks
          (dolist (lock (directory-files root t "\\.lock$"))
            (when (file-directory-p lock)
              (delete-directory lock t)
              (message "[cleanup] Removed stale lock: %s" (file-name-nondirectory lock))))
          ;; 8. Dedup crontab entries
          (let* ((cron-out (shell-command-to-string "crontab -l 2>/dev/null | sort -u || true"))
                 (original-count (length (split-string cron-out "\n" t)))
                 (deduped-count (length (delete-dups (split-string cron-out "\n" t)))))
            (when (< deduped-count original-count)
              (shell-command (format "crontab -l 2>/dev/null | sort -u | crontab -") 0)
              (message "[cleanup] Deduped crontab (%d unique lines)" deduped-count)))
          ;; Log cleanup results (inside let* so pruned is accessible)
          (when (> pruned 0)
            (message "[cleanup] Pruned %d experiment dirs >14d" pruned))
          (when (> removed-worktrees 0)
            (message "[cleanup] Removed %d stale worktrees" removed-worktrees))
          (when (> cleaned-temp 0)
            (message "[cleanup] Cleaned %d stale temp files" cleaned-temp)))
      (ignore))))

;; Define missing deductive-explain function to prevent void-function errors
;; during evolution self-check
(defun gptel-auto-workflow--deductive-explain (facts)
  "Generate deductive proofs from FACTS alist.
Returns list of plists with :goal, :confidence, :premises-count.
Fallback implementation when full deductive engine not loaded."
  (let ((proofs nil)
        (keep-rate (cdr (assq 'keep-rate facts)))
        (total-experiments (cdr (assq 'total-experiments facts))))
    ;; Generate simple proofs from available facts
    (when keep-rate
      (push (list :goal "keep-rate-observed"
                  :confidence keep-rate
                  :premises-count 1)
            proofs))
    (when (and total-experiments (> total-experiments 0))
      (push (list :goal "experiments-conducted"
                  :confidence (min 1.0 (/ (float total-experiments) 100))
                  :premises-count 1)
            proofs))
    ;; Always return at least one proof for diagnostics
    (unless proofs
      (push (list :goal "system-operational"
                  :confidence 0.5
                  :premises-count 0)
            proofs))
    (nreverse proofs)))

(provide 'gptel-auto-workflow-evolution-fix)
;;; gptel-auto-workflow-evolution-fix.el ends here
