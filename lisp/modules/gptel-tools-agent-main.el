;;; gptel-tools-agent-main.el --- Main entry point, workflow control -*- lexical-binding: t; -*-
;; Part of gptel-tools-agent split

(require 'cl-lib)
;; Optional: monitoring-agent may not be available in all environments
;; If it fails to load, monitoring-cycle is silently skipped via fboundp guards
(ignore-errors (require 'gptel-auto-workflow-monitoring-agent))

(declare-function gptel-auto-workflow--plist-get "gptel-tools-agent-base")
(declare-function gptel-prefix-cache-on-run-start "gptel-ext-prefix-cache")
(declare-function gptel-prefix-cache-on-run-end "gptel-ext-prefix-cache")
(declare-function gptel-knowledge--frontier-select-targets "gptel-auto-workflow-knowledge-reasoning")
(declare-function gptel-knowledge--dialectic-check "gptel-auto-workflow-knowledge-reasoning")
(declare-function gptel-auto-workflow--gap-prioritize-targets "gptel-auto-workflow-evolution" (targets))
(declare-function gptel-benchmark-eight-keys-weakest-with-signals "gptel-benchmark-principles")
(declare-function gptel-auto-workflow--read-file-contents "gptel-tools-agent-base")
(declare-function gptel-auto-experiment--reset-grade-state "gptel-tools-agent-benchmark")
(declare-function gptel-auto-experiment--target-keep-rate-from-tsv "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-experiment-loop "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-workflow--clear-rate-limited-backends "gptel-tools-agent-prompt-build")
(declare-function gptel-auto-workflow--clear-runtime-subagent-provider-overrides "gptel-tools-agent-prompt-build")
(declare-function gptel-auto-workflow--commit-integrated-p "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--current-run-id "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--default-dir "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--disable-headless-suppression "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-workflow--discard-worktree-buffers "gptel-tools-agent-worktree")
(declare-function gptel-auto-workflow--enable-headless-suppression "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-workflow--ensure-results-file "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--git-result "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-workflow--make-idempotent-callback "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--make-run-id "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--mark-messages-start "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-workflow--migrate-legacy-provider-defaults "gptel-tools-agent-prompt-build")
(declare-function gptel-auto-workflow--non-empty-string-p "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--optimize-branches "gptel-tools-agent-subagent")
(declare-function gptel-auto-workflow--optimize-worktrees "gptel-tools-agent-subagent")
(declare-function gptel-auto-workflow--persist-status "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-workflow--project-root "gptel-tools-agent-benchmark")
(declare-function gptel-auto-workflow--recover-orphans "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--remote-optimize-branches "gptel-tools-agent-worktree")
(declare-function gptel-auto-workflow--remote-tracking-optimize-branches "gptel-tools-agent-subagent")
(declare-function gptel-auto-workflow--require-magit-dependencies "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--restart-watchdog-timer "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-workflow--run-callback-live-p "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--safe-call "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--seed-live-root-load-path "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--shared-remote "gptel-tools-agent-worktree")
(declare-function gptel-auto-workflow--status-active-p "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-workflow--status-placeholder-p "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-workflow--status-plist "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-workflow--sync-staging-with-main "gptel-tools-agent-git")
(declare-function gptel-auto-workflow--terminate-active-shell-processes "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--update-progress "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-workflow--with-skipped-submodule-sync "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-workflow--worktree-base-root "gptel-tools-agent-base")
(declare-function gptel-auto-workflow-load-research-findings "gptel-auto-workflow-strategic")
(declare-function gptel-auto-workflow-read-persisted-status "gptel-tools-agent-experiment-loop")
(declare-function gptel-mementum--reset-synthesis-state "gptel-tools-agent-research")
(declare-function my/gptel--reset-agent-task-state "gptel-tools-agent-subagent")
(declare-function my/gptel--sanitize-for-logging "gptel-tools-agent-git")

(defvar gptel-auto-workflow--running nil)
(defvar gptel-auto-workflow--results nil)
(defvar gptel-auto-workflow--cron-job-running nil)
(defvar gptel-auto-workflow--watchdog-timer nil)
(defvar gptel-auto-workflow--status-refresh-timer nil)
(defvar gptel-auto-workflow-status-refresh-interval)
(defvar gptel-auto-workflow--cron-job-timer)
(defvar gptel-auto-workflow--run-id)
(defvar gptel-auto-workflow--run-project-root)
(defvar gptel-auto-workflow--current-project)
(defvar gptel-auto-workflow--current-target)
(defvar gptel-auto-workflow--stats)
(defvar gptel-auto-workflow--force-idle-status-overwrite)
(defvar gptel-auto-workflow-targets)
(defvar gptel-model)
(defvar gptel-auto-workflow--cached-baseline-results)
(defvar gptel-auto-workflow-use-staging)
(defvar gptel-backend)
(defvar gptel-auto-experiment-time-budget)
(defvar gptel-auto-workflow--last-progress-time)
(defvar gptel-auto-workflow--cron-safe-step nil
  "Current step in gptel-auto-workflow-cron-safe for debugging.")
(defvar gptel-auto-workflow--cron-zero-streak 0
  "Consecutive cycles where cron-error-propagation + zero-experiments-stuck
co-occur.
Reset to 0 on any healthy cycle. When >=3, clears cron-safe-step to force a
fresh cycle.")
(defvar gptel-auto-experiment--api-error-count)
(defvar gptel-auto-experiment--quota-exhausted)
(defvar gptel-auto-experiment-delay-between)
(defvar gptel-auto-experiment-max-retries)
(defvar gptel-auto-experiment-validation-retry-time-budget)
(defvar gptel-auto-experiment-validation-retry-active-grace)
(defvar gptel-auto-workflow-persistent-headless)
(defvar gptel-auto-workflow--status-run-id)
(defvar gptel-auto-workflow--worktree-state)
(defvar gptel-auto-workflow-worktree-base)
(defvar gptel-auto-workflow--project-root-override)
(defvar gptel-benchmark-eight-keys-definitions)
(defvar gptel-auto-workflow-run-async)
(defvar gptel-auto-workflow--lambda-strike-count)
(defvar gptel-auto-workflow--lambda-dead-until)
(defvar gptel-auto-experiment-max-per-target)

(defcustom gptel-auto-workflow--critical-functions
  '(gptel-auto-workflow-run-async--guarded
    gptel-experiment-loop
    gptel-auto-experiment-loop
    gptel-tools-agent-register
    gptel-auto-workflow--normalized-projects
    gptel-auto-workflow--discover-targets
    my/gptel--reset-agent-task-state
    gptel-auto-workflow--backend-available-p
    gptel-auto-workflow--rate-limit-failover-candidates
    gptel-auto-workflow--agent-base-preset)
  "List of symbol-valued critical functions that must be fboundp.
Self-healing check verifies these are all bound before running experiments.
If any are void, the system rolls back the most recent change."
  :type '(repeat symbol)
  :group 'gptel-auto-workflow)

(defcustom gptel-auto-workflow--self-heal-enabled t
  "Non-nil means run self-healing health check before experiments.
When t, `gptel-auto-workflow-cron-safe' validates critical function
existence and can auto-rollback broken changes."
  :type 'boolean
  :group 'gptel-auto-workflow)

(defcustom gptel-auto-workflow--process-timeout-secs 1800
  "Timeout in seconds for blocking subprocess calls during verification.

300s was too short for the 89-file test suite (~30 min full run).
1800s (30 min) prevents indefinite hangs while allowing legitimate
test runs to complete. Exit code 124 if timeout expires."
  :type 'integer
  :group 'gptel-auto-workflow)

(defun gptel-auto-workflow--call-process-with-watchdog (program &optional infile destination display &rest args)
  "Run blocking PROGRAM with timeout while pausing the workflow watchdog.

Uses GNU timeout(1) to prevent indefinite hangs during long verification runs.
Returns 124 if timeout expired, or the actual process exit code otherwise.

This avoids false watchdog force-stops when long local verification phases
block
Emacs long enough for a queued watchdog check to fire immediately afterward."
  (let ((workflow-active (or gptel-auto-workflow--running
                             gptel-auto-workflow--cron-job-running))
        (use-timeout (and (stringp program)
                           (or (string= program "bash")
                               (string= program "sh")
                               (string= program "emacs")
                               (string-suffix-p ".sh" program)))))
    (when workflow-active
      (when (timerp gptel-auto-workflow--watchdog-timer)
        (cancel-timer gptel-auto-workflow--watchdog-timer))
      (setq gptel-auto-workflow--watchdog-timer nil))
    (unwind-protect
        (if (and use-timeout (not noninteractive))
            (apply #'call-process "timeout" infile destination display
                   (number-to-string gptel-auto-workflow--process-timeout-secs)
                   program args)
          (apply #'call-process program infile destination display args))
      (when workflow-active
        (gptel-auto-workflow--update-progress)
        (gptel-auto-workflow--persist-status)
        (gptel-auto-workflow--restart-watchdog-timer)))))

(defun gptel-auto-workflow--stop-status-refresh-timer ()
  "Cancel the active workflow status refresh timer, if any."
  (when (timerp gptel-auto-workflow--status-refresh-timer)
    (cancel-timer gptel-auto-workflow--status-refresh-timer))
  (setq gptel-auto-workflow--status-refresh-timer nil))

(defun gptel-auto-workflow--refresh-status-if-running ()
  "Refresh the persisted workflow snapshot while the workflow is active.
Also monitors memory and triggers GC when RSS exceeds threshold."
  (if (or gptel-auto-workflow--running
          gptel-auto-workflow--cron-job-running)
      (progn
        (condition-case err
            (gptel-auto-workflow--persist-status)
          (error
           (message "[auto-workflow] Status refresh failed: %s"
                    (error-message-string err))
           (gptel-auto-workflow--stop-status-refresh-timer)))
        ;; Memory management: Emacs default GC (gc-cons-threshold = 800KB)
        ;; handles heap compaction.  The periodic GC timer (300s, see
        ;; gptel-auto-workflow-production.el) forces full GC every 5 min.
        ;; RSS stays at 2.9GB from malloc caching — this is normal.
        ;; Watchdog handles physical memory (>5GB → restart).
        nil)
    (gptel-auto-workflow--stop-status-refresh-timer)))

(defun gptel-auto-workflow--maybe-start-status-refresh-timer ()
  "Start the workflow status refresh timer if conditions are met."
  (when (timerp gptel-auto-workflow--status-refresh-timer)
    (cancel-timer gptel-auto-workflow--status-refresh-timer)
    (setq gptel-auto-workflow--status-refresh-timer nil))
  (when (and (or gptel-auto-workflow--running
                 (bound-and-true-p gptel-auto-workflow--cron-job-running))
             (numberp gptel-auto-workflow-status-refresh-interval)
             (> gptel-auto-workflow-status-refresh-interval 0))
    (setq gptel-auto-workflow--status-refresh-timer
          (run-with-timer gptel-auto-workflow-status-refresh-interval
                          gptel-auto-workflow-status-refresh-interval
                          #'gptel-auto-workflow--refresh-status-if-running))))

(defun gptel-auto-workflow--start-status-refresh-timer ()
  "Start the workflow status refresh timer if a workflow run is active."
  (gptel-auto-workflow--maybe-start-status-refresh-timer))

(defun gptel-auto-workflow-force-stop ()
  "Force stop a stuck workflow.
Interactive command to recover from hung workflow state.
Resilient to partial module loads — guards all optional function calls
so the recovery command itself never crashes before resetting state."
  (interactive)
  ;; ASSUMPTION: These functions may be void after partial load / failed require.
  ;; BEHAVIOR: Guard each with fboundp so force-stop always completes.
  ;; EDGE CASE: Module not loaded → skip that cleanup step, still reset state.
  ;; TEST: Call force-stop after unloading a module; state should still reset.
  (when (fboundp 'my/gptel--reset-agent-task-state)
    (my/gptel--reset-agent-task-state))
  (when (fboundp 'gptel-auto-workflow--clear-runtime-subagent-provider-overrides)
    (gptel-auto-workflow--clear-runtime-subagent-provider-overrides))
  (when (fboundp 'gptel-mementum--reset-synthesis-state)
    (gptel-mementum--reset-synthesis-state))
  (when (fboundp 'gptel-auto-experiment--reset-grade-state)
    (gptel-auto-experiment--reset-grade-state))
  (when gptel-auto-workflow--cron-job-timer
    (cancel-timer gptel-auto-workflow--cron-job-timer)
    (setq gptel-auto-workflow--cron-job-timer nil))
  (gptel-auto-workflow--stop-status-refresh-timer)
  (when (fboundp 'gptel-auto-workflow--terminate-active-shell-processes)
    (gptel-auto-workflow--terminate-active-shell-processes))
  (setq gptel-auto-workflow--running nil
        gptel-auto-workflow--cron-job-running nil
        gptel-auto-workflow--run-id nil
        gptel-auto-workflow--run-project-root nil
        gptel-auto-workflow--current-project nil
        gptel-auto-workflow--current-target nil)
  (setq gptel-auto-workflow--stats
        (plist-put gptel-auto-workflow--stats :phase "idle"))
  (let ((gptel-auto-workflow--force-idle-status-overwrite t))
    (gptel-auto-workflow--persist-status))
  (when gptel-auto-workflow--watchdog-timer
    (cancel-timer gptel-auto-workflow--watchdog-timer)
    (setq gptel-auto-workflow--watchdog-timer nil))
  (message "[auto-workflow] Force-stopped"))

(defun gptel-auto-workflow--headless-p ()
  "Check if running on a headless server (Linux, Pi5, etc).
Returns non-nil if this machine should run 24/7 background jobs.
Detection: macOS (darwin) = user machine, Linux = headless."
  (not (eq system-type 'darwin)))

(defun gptel-auto-workflow--default-quiet-hours ()
  "Auto-detect quiet hours based on OS.
Returns nil for all systems - rely on 30-min inactivity check instead.
This allows cron-scheduled runs while still protecting active use.

Users can override in their config if needed."
  nil)

(defvar gptel-auto-workflow-quiet-hours (gptel-auto-workflow--default-quiet-hours)
  "List of hours (0-23) when auto-workflow should NOT run.
Default is nil for all systems - we rely on:
  - 30-min inactivity check
  - Cron schedule (macOS: 10AM,2PM,6PM; Pi5: every 4h)

Override in your config:
  (setq gptel-auto-workflow-quiet-hours
        \\='(9 10 11 12 13 14 15 16 17))  ; Work hours
  (setq gptel-auto-workflow-quiet-hours
        \\='(0 1 2 3 4 5 6))  ; Night only")

(defcustom gptel-auto-workflow-skip-if-unsaved nil
  "If non-nil, skip auto-workflow when there are unsaved buffers.
Default is nil since unsaved buffers are normal when using Emacs."
  :type 'boolean
  :group 'gptel)

(defcustom gptel-auto-workflow-skip-if-recent-input t
  "If non-nil, skip when user has typed within last N minutes.
See `gptel-auto-workflow-recent-input-minutes'."
  :type 'boolean
  :group 'gptel)

(defcustom gptel-auto-workflow-recent-input-minutes 30
  "Minutes of inactivity required before auto-workflow can run.
Default 30 min covers lunch breaks and short meetings."
  :type 'integer
  :group 'gptel)

(defun gptel-auto-workflow--active-use-p ()
  "Check if Emacs is being actively used.
Returns cons cell (REASONS . REASONS) where REASONS is a list
of strings describing why workflow should skip.
Returns (nil . nil) if safe to run."
  (let ((reasons '()))
    (when gptel-auto-workflow-skip-if-unsaved
      (let ((unsaved (cl-remove-if-not
                      (lambda (buf)
                        (and (buffer-file-name buf)
                             (buffer-modified-p buf)))
                      (buffer-list))))
        (when (and unsaved (> (length unsaved) 0))
          (push (format "%d unsaved buffers" (length unsaved)) reasons))))
    (when (and gptel-auto-workflow-skip-if-recent-input
               (boundp 'last-command-event-time)
               last-command-event-time)
      (let* ((last-input-seconds (float-time (time-subtract nil last-command-event-time)))
             (last-input-minutes (/ last-input-seconds 60.0)))
        (when (< last-input-minutes gptel-auto-workflow-recent-input-minutes)
          (push (format "recent input (%.1f min ago)" last-input-minutes) reasons))))
    (when gptel-auto-workflow-quiet-hours
      (let ((current-hour (string-to-number (format-time-string "%H"))))
        (when (memq current-hour gptel-auto-workflow-quiet-hours)
          (push (format "quiet hours (hour %d)" current-hour) reasons))))
    (cons reasons reasons)))

(defun gptel-auto-workflow-status ()
  "Return current workflow status as plist.
Returns (:running :kept :total :phase :results)."
  (let* ((local-status
          (and (or gptel-auto-workflow--running
                   (bound-and-true-p gptel-auto-workflow--cron-job-running)
                   gptel-auto-workflow--stats)
               (gptel-auto-workflow--status-plist)))
         (persisted-status (gptel-auto-workflow-read-persisted-status)))
    (cond
     ((and (gptel-auto-workflow--status-placeholder-p local-status)
           (gptel-auto-workflow--status-active-p persisted-status))
      persisted-status)
     (local-status)
     (persisted-status)
     (t
      (gptel-auto-workflow--status-plist)))))


(defun gptel-auto-workflow--sanitize-unicode (str)
  "Sanitize Unicode characters in STR for safe display.
Replaces curly quotes, dashes, and zero-width characters with ASCII
equivalents.
Returns empty string if STR is nil or not a string."
  (if (not (stringp str))
      ""
    (let ((clean str))
      (setq clean (replace-regexp-in-string
                   (regexp-opt (mapcar #'char-to-string '(?\u2018 ?\u2019 ?\u0060)))
                   "'"
                   clean))
      (setq clean (replace-regexp-in-string
                   (regexp-opt (mapcar #'char-to-string '(?\u201C ?\u201D)))
                   "\""
                   clean))
      (setq clean (replace-regexp-in-string
                   (regexp-opt (mapcar #'char-to-string '(?\u2013 ?\u2014)))
                   "-"
                   clean))
      (setq clean (replace-regexp-in-string (string ?\u2026) "..." clean))
      (setq clean (replace-regexp-in-string (string ?\u00A0) " " clean))
      (setq clean (replace-regexp-in-string
                   (regexp-opt (mapcar #'char-to-string '(?\u200B ?\u200C ?\u200D)))
                   ""
                   clean))
      clean)))


(defun gptel-auto-workflow-log ()
  "Return recent workflow log lines as a list (filtered, sanitized).
Safe for external tools - contains only [auto-] and [nucleus] messages."
  (with-current-buffer "*Messages*"
    (let ((lines (split-string (buffer-string) "\n" t))
          result)
      (dolist (line lines)
        (when (string-match-p "^\\[auto-\\]\\|^\\[nucleus\\]" line)
          (push (gptel-auto-workflow--sanitize-unicode line) result)))
      (seq-take (nreverse result) 20))))

(declare-function gptel-auto-workflow-select-targets "gptel-auto-workflow-strategic")
(declare-function gptel-auto-workflow--git-cmd "gptel-tools-agent-base")

(defun gptel-auto-workflow--process-rss-kb ()
  "Return current Emacs process RSS in kilobytes, or nil.
Works on Linux (/proc) and macOS (ps)."
  (let ((pid (emacs-pid)))
    (when pid
      (or
       ;; Linux: read VmRSS from /proc/PID/status
       (condition-case nil
           (with-temp-buffer
             (insert-file-contents (format "/proc/%d/status" pid) nil nil nil)
             (goto-char (point-min))
             (when (re-search-forward "VmRSS:\\s-+\\([0-9]+\\)" nil t)
               (string-to-number (match-string 1))))
         (error nil))
       ;; macOS: use ps command (different platforms have different ps output)
       (condition-case nil
           (with-temp-buffer
             (call-process "ps" nil t nil "-o" "rss=" "-p" (format "%d" pid))
             (goto-char (point-min))
             (when (re-search-forward "\\([0-9]+\\)" nil t)
               (string-to-number (match-string 1))))
         (error nil))))))

(defun gptel-auto-workflow-run-async (&optional targets completion-callback)
  "Run auto-workflow asynchronously with TARGETS.
Non-blocking - returns immediately.
Check status with `gptel-auto-workflow-status'.
TARGETS defaults to `gptel-auto-workflow-targets'.
COMPLETION-CALLBACK is called with results when all targets are done.

Skips if Emacs is in active use (unsaved buffers, recent input, etc.).
Check `gptel-auto-workflow--active-use-p' for details.

Usage:
  emacsclient -e \\='(gptel-auto-workflow-run-async)'
  emacsclient -e \\='(gptel-auto-workflow-status)'
  M-x gptel-auto-workflow-run"
  (interactive)
  (cl-block gptel-auto-workflow-run-async
    (when gptel-auto-workflow--running
      (error "[auto-workflow] Already running. Check status first."))
    (let ((active (gptel-auto-workflow--active-use-p)))
      (when (car active)
        (setq gptel-auto-workflow--stats
              (list :phase "skipped" :total 0 :kept 0))
        (gptel-auto-workflow--persist-status)
        (message "[auto-workflow] Skipping: %s" (string-join (car active) ", "))
        (cl-return-from gptel-auto-workflow-run-async nil)))
    ;; Human decision gate: block if pending decisions exist
    ;; Uses truthiness (not eq t) — pending-decisions-p contract is "return non-nil"
    (when (and (fboundp 'gptel-auto-workflow--pending-decisions-p)
               (gptel-auto-workflow--pending-decisions-p))
      (setq gptel-auto-workflow--stats
            (list :phase "blocked" :total 0 :kept 0))
      (gptel-auto-workflow--persist-status)
      (message "[auto-workflow] BLOCKED: Pending human decision in mementum/decisions/")
      (cl-return-from gptel-auto-workflow-run-async nil))
    (gptel-auto-workflow--require-magit-dependencies)
    (gptel-auto-workflow--migrate-legacy-provider-defaults)
    ;; Load git-tracked backend preference before any experiment runs.
    (when (fboundp 'gptel-auto-workflow--ensure-backend-preference-loaded)
      (condition-case nil
          (gptel-auto-workflow--ensure-backend-preference-loaded)
        (error nil)))
    ;; Load context database (Phase 3: Software as Consumable)
    (when (fboundp 'gptel-auto-workflow--context-db-load)
      (condition-case nil
          (gptel-auto-workflow--context-db-load)
        (error nil)))
    ;; Recover experiments stuck in staging-pending before starting new work.
    ;; Safe to call every run: already-merged branches are skipped.
    (when (and gptel-auto-workflow-use-staging
               (fboundp 'gptel-auto-experiment--recover-stale-staging-pending))
      (condition-case err
          (gptel-auto-experiment--recover-stale-staging-pending)
        (error
         (message "[staging-recovery] Recovery sweep skipped: %s"
                  (error-message-string err)))))
    (gptel-auto-workflow--clear-runtime-subagent-provider-overrides)
    (gptel-auto-workflow--clear-rate-limited-backends)
    (when (fboundp 'gptel-auto-workflow--clear-run-failed-backends)
      (gptel-auto-workflow--clear-run-failed-backends))
     ;; Apply pipeline auto-fix signals (bridge between bash Step 0.5 and daemon)
     ;; The pipeline writes signal files; the daemon reads them here.
     ;; This closes the DETECT→ACT→KEEP-GOING loop.
     (when (fboundp 'gptel-auto-workflow-self-audit-apply-pipeline-signals)
       (let ((signals (gptel-auto-workflow-self-audit-apply-pipeline-signals)))
         (when (> signals 0)
           (message "[daemon] Applied %d pipeline auto-fix signals" signals))))
    ;; Default to Moonshot for headless workflows instead of global MiniMax
    ;; (which is usually quota-exhausted).  The ontology router will
    ;; reorder backends once it has experiment data. Only set when
    ;; persistent-headless is active so interactive sessions keep the
    ;; user's chosen default.
    (when (and (boundp 'gptel-auto-workflow-persistent-headless)
               gptel-auto-workflow-persistent-headless
               (boundp 'gptel--moonshot)
               gptel--moonshot
               (fboundp 'my/gptel-api-key)
               (my/gptel-api-key "api.kimi.com"))
      (setq gptel-backend gptel--moonshot
            gptel-model 'kimi-k2.6)
      ;; Refresh agent presets so they use Moonshot instead of the stale
      ;; MiniMax that was snapshotted during daemon startup.
      (when (fboundp 'nucleus--override-gptel-agent-presets)
        (nucleus--override-gptel-agent-presets)))
    ;; Set generous timeout for headless daemon experiments.
    ;; gptel-auto-workflow-cron-safe sets this to 900, but evolution timer
    ;; calls run-async directly which uses the default 300. Without this,
    ;; executor hits 480s hard timeout (300+180 grace) before completing.
    (when (and (boundp 'gptel-auto-workflow-persistent-headless)
               gptel-auto-workflow-persistent-headless)
      (setq gptel-auto-experiment-time-budget 900))
    ;; Restore research context from findings file.  Survives daemon restart
    ;; between pipeline Steps 3 and 4 — loads the findings saved by the
    ;; researcher so experiment metadata links back to the research trace.
    (condition-case err
        (when (fboundp 'gptel-auto-workflow--ensure-research-context)
          (gptel-auto-workflow--ensure-research-context
           (or (gptel-auto-workflow-load-research-findings) "")))
      (error
       (message "[auto-workflow] Research context restore skipped: %s"
                (error-message-string err))))
    ;; Auto-discover targets when .dir-locals.el didn't set them (daemon restart).
    (unless gptel-auto-workflow-targets
      ;; Try re-loading .dir-locals.el first — defcustom in
      ;; gptel-tools-agent-subagent.el resets the global to '() when
      ;; modules are loaded, silently overriding dir-locals.  Re-read
      ;; here so the configured targets win over auto-discover.
      (condition-case nil
          (let ((buf (get-buffer-create " *dir-locals-cron*")))
            (with-current-buffer buf
              (setq-local default-directory (gptel-auto-workflow--default-dir))
              (setq-local enable-local-variables t)
              (hack-dir-local-variables-non-file-buffer)
              (when (local-variable-p 'gptel-auto-workflow-targets)
                (setq gptel-auto-workflow-targets
                      (buffer-local-value 'gptel-auto-workflow-targets buf))
                (setq-default gptel-auto-workflow-targets gptel-auto-workflow-targets))
              (kill-buffer buf)))
        (error nil))
      (unless gptel-auto-workflow-targets
        (let ((discovered (and (fboundp 'gptel-auto-workflow--discover-targets)
                               (gptel-auto-workflow--discover-targets))))
          (when discovered
            (setq gptel-auto-workflow-targets discovered)
            (setq-default gptel-auto-workflow-targets discovered)
           (message "[auto-workflow] Auto-discovered %d targets"
                    (length discovered))))))
    ;; Restore self-healing lessons from mementum (cross-session learning).
    ;; Previous sessions' "what finally worked" knowledge survives daemon restart.
    ;; Uses ignore-errors to swallow ALL errors (broken pipe, file read, etc.)
    ;; so this never blocks the experiment trigger.
    (ignore-errors
      (when (and (boundp 'gptel-auto-workflow--self-healing-log)
                 (fboundp 'gptel-auto-workflow--mementum-slug))
        (let ((mem-dir (expand-file-name "mementum/memories/"
                                         (gptel-auto-workflow--default-dir))))
          (when (file-directory-p mem-dir)
            (dolist (f (directory-files mem-dir t "self-heal-lesson-.*\\.md$"))
              (with-temp-buffer
                (insert-file-contents f)
                (goto-char (point-min))
                (when (re-search-forward "Final fix: \\(.+\\)" nil t)
                  (let ((fix (match-string 1)))
                    (push (list :timestamp (float-time)
                                :diagnosis "restored-lesson"
                                :remedy fix
                                :effective t
                                :from-prior-session t)
                          gptel-auto-workflow--self-healing-log)))
                (message "[auto-workflow] Restored self-heal lesson: %s"
                         (file-name-base f))))))))
    ;; Check innovation queue for pending ideas from GTM Mayor
    (when (fboundp 'gptel-auto-workflow--innovation-queue-list)
      (condition-case err
          (let ((pending (gptel-auto-workflow--innovation-queue-list "pending")))
            (when pending
              (message "[innovation] %d queued ideas awaiting experiments"
                       (length pending))))
        (error (message "[innovation] Queue check error: %s" err))))
    ;; Phase 6: Read GTM strategy roadmap
    (when (fboundp 'gptel-auto-workflow--read-gtm-strategy)
      (condition-case err
          (let ((focus (gptel-auto-workflow--read-gtm-strategy 'current-focus)))
            (when focus
              (message "[pmf] Following GTM strategy: %s"
                       (car (split-string focus "\n")))))
        (error (message "[pmf] Strategy read error: %s" err))))
    ;; Pre-warm baseline cache so first experiment doesn't fail
    ;; while the full test suite runs (~21 min) to create it.
    (when (and (fboundp 'gptel-auto-workflow--main-baseline-test-results)
               (or (null gptel-auto-workflow--cached-baseline-results)
                   (not (eq (plist-get gptel-auto-workflow--cached-baseline-results :exit-code) 0))))
      (message "[auto-workflow] Warming baseline cache (first run may take ~2min)...")
      (condition-case nil
          (gptel-auto-workflow--main-baseline-test-results)
        (error (message "[auto-workflow] Baseline warm failed (will retry on first experiment)"))))
    (setq gptel-auto-workflow--current-project (gptel-auto-workflow--default-dir)
          gptel-auto-workflow--run-project-root (gptel-auto-workflow--default-dir)
          gptel-auto-workflow--run-id (or gptel-auto-workflow--run-id
                                          (gptel-auto-workflow--make-run-id))
          gptel-auto-experiment--api-error-count 0
          gptel-auto-experiment--quota-exhausted nil
          gptel-auto-workflow--running t
          gptel-auto-workflow--stats (list :phase "selecting" :total 0 :kept 0)
          gptel-auto-workflow--last-progress-time (current-time))
    (gptel-auto-workflow--ensure-results-file gptel-auto-workflow--run-id)
    ;; Phase 0: Self-heal diagnostics (if enabled)
    (when gptel-auto-workflow--self-heal-enabled
      (message "[self-heal] Running pre-experiment diagnostics...")
      (run-hooks 'gptel-auto-workflow-before-experiment-hook))
    (unless gptel-auto-workflow--cron-job-running
      (gptel-auto-workflow--mark-messages-start))
    (gptel-auto-workflow--start-status-refresh-timer)
    (gptel-auto-workflow--persist-status)
    ;; Start watchdog timer
    (gptel-auto-workflow--restart-watchdog-timer)
    ;; Phase 2: Restore persisted self-healing state (survives daemon restart)
    (when (fboundp 'gptel-auto-workflow--load-self-healing-state)
      (condition-case err
          (gptel-auto-workflow--load-self-healing-state)
        (error (message "[self-heal] State restore skipped: %s"
                        (error-message-string err)))))
    ;; Phase 3: Byte-compiler self-heal — fix warnings before experiments
    (when (and gptel-auto-workflow--self-heal-enabled
               (fboundp 'gptel-auto-workflow--self-heal-byte-compiler))
      (condition-case err
          (let ((result (gptel-auto-workflow--self-heal-byte-compiler)))
            (when (> (plist-get result :remaining-warnings) 0)
              (message "[self-heal] Byte-compiler: %d warnings remain after auto-fix"
                       (plist-get result :remaining-warnings))))
        (error (message "[self-heal] Byte-compiler self-heal error: %s"
                        (error-message-string err)))))
    ;; Phase 4: Self-diagnostic probe — verify grader health before wasting experiments
    (when (and (fboundp 'gptel-auto-workflow--probe-before-experiments)
               (not (gptel-auto-workflow--probe-before-experiments)))
      (message "[auto-workflow] Diagnostic probe failed: grader broken, experiments halted")
      (setq gptel-auto-workflow--running nil)
      (cl-return-from gptel-auto-workflow-run-async nil))
    ;; Phase 4a: Git lock detection — prevent concurrent run collisions
    (let ((git-lock (expand-file-name ".git/index.lock"
                                       (gptel-auto-workflow--default-dir))))
      (when (file-exists-p git-lock)
        (let ((lock-age (- (float-time) (float-time (file-attribute-modification-time
                                                       (file-attributes git-lock))))))
          (if (> lock-age 600)
              (progn
                (message "[preflight] Removing stale git lock (%.0fs old): %s" lock-age git-lock)
                (delete-file git-lock))
            (message "[preflight] Git lock exists (%.0fs old), aborting: %s" lock-age git-lock)
            (setq gptel-auto-workflow--running nil)
            (cl-return-from gptel-auto-workflow-run-async nil)))))
    ;; Phase 4b: Daemon socket health — verify Emacs daemon is responsive
    (when (and (boundp 'gptel-auto-workflow-persistent-headless)
               gptel-auto-workflow-persistent-headless)
      (let ((socket-dir (or (getenv "XDG_RUNTIME_DIR")
                            (getenv "TMPDIR")
                            (format "/tmp/emacs%d" (user-uid)))))
        (when (and socket-dir (file-directory-p socket-dir))
          (let ((socket (expand-file-name "server" socket-dir)))
            (when (and (file-exists-p socket)
                       (not (file-executable-p socket)))
              (message "[preflight] Daemon socket exists but not executable, may need restart: %s" socket))))))
    ;; Wrap completion-callback with memory/disk cleanup for 24/7 operation
     (let ((cleanup-callback
            (lambda (results)
              ;; Self-healing: check if pipeline itself is broken (0% keep rate, etc.)
              (when (fboundp 'gptel-auto-workflow--maybe-self-heal)
                (condition-case err
                    (gptel-auto-workflow--maybe-self-heal)
                  (error (message "[self-heal] Error during self-healing: %s"
                                  (error-message-string err)))))
              ;; Recovery verification: did last remediation work?
              (when (fboundp 'gptel-auto-workflow--verify-recovery)
                (condition-case err
                    (gptel-auto-workflow--verify-recovery)
                  (error (message "[self-heal] Error during recovery verification: %s"
                                  (error-message-string err)))))
              ;; Garbage collect to reclaim memory from LLM API calls
              (garbage-collect)
             ;; Prune stale git worktrees to prevent disk accumulation
             (ignore-errors
               (gptel-auto-workflow--git-cmd "git worktree prune" 30))
             ;; Report memory after cleanup
             (let ((rss (gptel-auto-workflow--process-rss-kb)))
               (when rss
                 (message "[mem] Post-run RSS: %.0fMB" (/ rss 1024.0))))
             (when completion-callback
               (funcall completion-callback results)))))
       (cl-labels ((dispatch-targets (selected-targets)
                    (unless (fboundp 'gptel-auto-workflow--run-with-targets)
                      (condition-case nil
                          (load-file (expand-file-name "lisp/modules/gptel-tools-agent-main.el"
                                                        (gptel-auto-workflow--default-dir)))
                        (error nil)))
                    (if (fboundp 'gptel-auto-workflow--run-with-targets)
                        (gptel-auto-workflow--run-with-targets selected-targets cleanup-callback)
                      (setq gptel-auto-workflow--running nil
                            gptel-auto-workflow--current-target nil
                            gptel-auto-workflow--current-project nil
                            gptel-auto-workflow--run-project-root nil)
                      (setq gptel-auto-workflow--stats
                            (plist-put gptel-auto-workflow--stats :phase "error"))
                      (gptel-auto-workflow--persist-status)
                      (message "[auto-workflow] Dispatch function unavailable after target selection")
                      (when completion-callback
                        (funcall completion-callback nil)))))
        (if targets
            (dispatch-targets targets)
          (require 'gptel-auto-workflow-strategic)
          (gptel-auto-workflow-select-targets #'dispatch-targets))))
    'started))

(defun gptel-auto-workflow-run-async--guarded (&optional targets completion-callback)
  "Run auto-workflow with active-use guard using catch/throw.
Same as `gptel-auto-workflow-run-async' but safe for cron jobs."
  (catch 'skip-workflow
    (when gptel-auto-workflow--running
      (error "[auto-workflow] Already running. Check status first."))
    (let ((active (gptel-auto-workflow--active-use-p)))
      (when (car active)
        (message "[auto-workflow] Skipping: %s" (string-join (car active) ", "))
        (throw 'skip-workflow nil)))
    (gptel-auto-workflow-run-async targets completion-callback)))

(defun gptel-auto-workflow--reload-live-support (&optional proj-root)
  "Reload workflow support modules and agent presets from PROJ-ROOT."
  (let ((root (file-name-as-directory
               (expand-file-name
                (or proj-root
                    (gptel-auto-workflow--default-dir)
                    default-directory)))))
    (gptel-auto-workflow--seed-live-root-load-path root)
    (load-file (expand-file-name "lisp/modules/gptel-benchmark-principles.el" root))
    (load-file (expand-file-name "lisp/modules/gptel-ext-context.el" root))
    (load-file (expand-file-name "lisp/modules/gptel-ext-fsm-utils.el" root))
    (load-file (expand-file-name "lisp/modules/gptel-ext-retry.el" root))
    (load-file (expand-file-name "lisp/modules/gptel-ext-tool-sanitize.el" root))
    (load-file (expand-file-name "lisp/modules/gptel-tools-agent-experiment-core.el" root))
    (load-file (expand-file-name "lisp/modules/gptel-tools-agent-prompt-build.el" root))
    (load-file (expand-file-name "lisp/modules/gptel-auto-workflow-ontology-router.el" root))
    (load-file (expand-file-name "lisp/modules/gptel-auto-workflow-skill-graph.el" root))
    (when (fboundp 'skill-graph-init)
      (condition-case err
          (skill-graph-init)
        (error (message "[skill-graph] Init failed: %s" (error-message-string err)))))
    (load-file (expand-file-name "lisp/modules/gptel-auto-workflow-projects.el" root))
    (load-file (expand-file-name "lisp/modules/gptel-tools-agent-error.el" root))
    (load-file (expand-file-name "lisp/modules/gptel-benchmark-subagent.el" root))
    (load-file (expand-file-name "lisp/modules/nucleus-prompts.el" root))
    (load-file (expand-file-name "lisp/modules/nucleus-presets.el" root))
    ;; Context interception: PreToolUse/PostToolUse hooks, auto-indexing, session events
    (condition-case nil
        (load-file (expand-file-name "lisp/modules/gptel-nucleus-context-intercept.el" root))
      (error (message "[nucleus] context-intercept module unavailable, skipping")))
    ;; Ensure gptel-agent--task has FSM position guard for analyzer dispatch
    (load-file (expand-file-name "packages/gptel-agent/gptel-agent-tools.el" root))
    (condition-case err (load-file (expand-file-name "lisp/modules/gptel-auto-workflow-strategic.el" root)) (error (message "[reload] strategic.el skipped (load error: %s)" (error-message-string err))))
    ;; Always re-read .dir-locals after module load. The defcustom in
    ;; gptel-tools-agent-subagent.el can overwrite project-local targets with
    ;; the fallback list during daemon startup, so empty-checking is not enough.
    ;; Use setq-default because hack-dir-local-variables-non-file-buffer creates
    ;; a buffer-local binding that shadows the global.
    (let ((loaded-targets nil))
      (condition-case nil
          (with-temp-buffer
            (setq-local default-directory root)
            (setq-local enable-local-variables t)
            (hack-dir-local-variables-non-file-buffer)
            (when (local-variable-p 'gptel-auto-workflow-targets)
              (setq loaded-targets
                    (buffer-local-value 'gptel-auto-workflow-targets
                                        (current-buffer)))))
        (error nil))
      (when loaded-targets
        (setq-default gptel-auto-workflow-targets loaded-targets))
      (when (and (boundp 'gptel-auto-workflow-targets)
                 (or (null gptel-auto-workflow-targets)
                     (equal gptel-auto-workflow-targets '())))
        (when (fboundp 'gptel-auto-workflow--discover-targets)
          (let ((discovered (gptel-auto-workflow--discover-targets)))
            (when discovered
              (setq gptel-auto-workflow-targets discovered)
              (message "[init] Populated %d auto-workflow targets" (length discovered)))))))
    (condition-case err (load-file (expand-file-name "lisp/modules/strategic-daemon-functions.el" root)) (error (message "[reload] daemon-functions.el skipped (load error: %s)" (error-message-string err))))
    ;; strategic.el requires gptel-auto-workflow-research-cache via (require '... nil t).
    ;; If that require succeeded, featurep will be t and we skip the re-load.
    (unless (featurep 'gptel-auto-workflow-research-cache)
      (condition-case err (load-file (expand-file-name "lisp/modules/gptel-auto-workflow-research-cache.el" root)) (error (message "[reload] research-cache.el skipped (load error: %s)" (error-message-string err)))))
    (condition-case err (load-file (expand-file-name "lisp/modules/gptel-auto-workflow-research-benchmark.el" root)) (error (message "[reload] research-benchmark.el skipped (load error: %s)" (error-message-string err))))
    (condition-case err (load-file (expand-file-name "lisp/modules/gptel-auto-workflow-projects.el" root)) (error (message "[reload] projects.el skipped (load error: %s)" (error-message-string err))))
    ;; Ensure gptel-agent is loaded before setting up agent dirs and
    ;; registering custom agents (analyzer, grader, comparator, etc.).
    ;; nucleus-presets-setup-agents checks (featurep 'gptel-agent) and
    ;; silently skips agent registration if it's nil.  Without this,
    ;; the auto-workflow fails with "Unknown agent type: analyzer".
    (when (fboundp 'require)
      (condition-case nil (require 'gptel-agent) (error nil)))
    (if (fboundp 'nucleus-presets-setup-agents)
        (progn
          (nucleus-presets-setup-agents)
          (if (fboundp 'nucleus--after-agent-update)
              (nucleus--after-agent-update)
            (when (fboundp 'nucleus--register-gptel-directives)
              (nucleus--register-gptel-directives))
            (when (fboundp 'nucleus--override-gptel-agent-presets)
              (nucleus--override-gptel-agent-presets))))
      (when (fboundp 'nucleus--register-gptel-directives)
        (nucleus--register-gptel-directives))
      (when (fboundp 'nucleus--override-gptel-agent-presets)
        (nucleus--override-gptel-agent-presets))
      ;; Initialize legacy provider fallback variables (safe to call repeatedly)
      (when (fboundp 'gptel-auto-workflow--migrate-legacy-provider-defaults)
        (gptel-auto-workflow--migrate-legacy-provider-defaults)))))


(defun gptel-auto-workflow-cron-safe (&optional completion-callback)
  "Run auto-workflow with full cleanup for cron jobs.
Cancels stale timers, kills orphaned buffers, resets state, then runs.
Safe to call from cron - handles all edge cases.
Sets `gptel-auto-workflow-persistent_headless' to prevent interactive prompts.
When COMPLETION-CALLBACK is non-nil, call it after the workflow finishes."
  ;; Load base module first: default-dir is needed before reload-live-support runs
  (condition-case nil
      (load-file (expand-file-name "lisp/modules/gptel-tools-agent-base.el"
                                   user-emacs-directory))
    (error nil))
  (let* ((proj-root (gptel-auto-workflow--default-dir))
         (finish
          (gptel-auto-workflow--make-idempotent-callback
           (lambda (&optional results)
             (gptel-auto-workflow--disable-headless-suppression)
             (when completion-callback
               (funcall completion-callback results))))))
    (setq gptel-auto-workflow--cron-safe-step "start")
    (condition-case err
        (progn
          (setq gptel-auto-workflow--cron-safe-step "setq-defaults")
          (setq default-directory proj-root
                 gptel-auto-workflow-persistent-headless t
                 message-log-max 10000
                 gptel-auto-experiment-delay-between 0
                 gptel-auto-experiment-max-retries 3  ; 3 attempts for transient network errors
                 gptel-auto-experiment-time-budget 900
                 ;; Reduced from 120s to 60s to fail faster on slow model retries
                 ;; This avoids wasting 300s on validation-retry-failed experiments
                 gptel-auto-experiment-validation-retry-time-budget 60
                 gptel-auto-experiment-validation-retry-active-grace 60)
          (setq gptel-auto-workflow--cron-safe-step "enable-headless")
          (gptel-auto-workflow--enable-headless-suppression)
          (setq gptel-auto-workflow--cron-safe-step "check-running")
          (if gptel-auto-workflow--running
              (progn
                (message "[auto-workflow] Job already running; skipping new request")
                (gptel-auto-workflow--disable-headless-suppression)
                nil)
            ;; HARDEN: Disable native-comp deferred compilation during workflow startup
            ;; to prevent void-variable bugs in closures on arm64 Emacs 30.1.
            (when (and (featurep 'native-compile)
                       (boundp 'native-comp-deferred-compilation))
              (setq native-comp-deferred-compilation nil))
            ;; Enable headless suppression before requiring/loading workflow
            ;; dependencies so worker startup does not byte-compile unrelated ELPA
            ;; packages on load.
            (require 'magit)
            (require 'json)
            (setq gptel-auto-workflow--cron-safe-step "load-agent")
            (condition-case err
                (load-file (expand-file-name "lisp/modules/gptel-tools-agent.el" proj-root))
              (error (message "[auto-workflow] Load gptel-tools-agent error: %S" err)))
            (setq gptel-auto-workflow--cron-safe-step "reload-support")
            (condition-case err
                (when (fboundp 'gptel-auto-workflow--reload-live-support)
                  (gptel-auto-workflow--reload-live-support proj-root))
              (error (message "[auto-workflow] Reload-live-support error: %S" err)))
            (setq gptel-auto-workflow--cron-safe-step "cleanup")
            (setq gptel-auto-experiment--api-error-count 0)
            ;; Clear accumulated backend health strikes so old failures
            ;; don't quarantine all backends on restart.
            (when (and (boundp 'gptel-auto-workflow--lambda-strike-count)
                       (hash-table-p gptel-auto-workflow--lambda-strike-count))
              (clrhash gptel-auto-workflow--lambda-strike-count))
            (when (and (boundp 'gptel-auto-workflow--lambda-dead-until)
                       (hash-table-p gptel-auto-workflow--lambda-dead-until))
              (clrhash gptel-auto-workflow--lambda-dead-until))
            (when (and (boundp 'gptel-auto-workflow--backend-lambda-health-cache)
                       (hash-table-p gptel-auto-workflow--backend-lambda-health-cache))
              (clrhash gptel-auto-workflow--backend-lambda-health-cache))
            (gptel-auto-workflow--safe-call "Cleanup" #'gptel-auto-workflow--cleanup-stale-state)
             (gptel-auto-workflow--safe-call "Sync staging"
               (lambda ()
                 (condition-case nil
                     (with-timeout (300 (message "[auto-workflow] Sync staging timed out after 300s, skipping"))
                       (gptel-auto-workflow--sync-staging-with-main))
                   ((error quit)
                    (message "[auto-workflow] Sync staging failed or timed out, continuing")))))
            (gptel-auto-workflow--safe-call
             "Orphan scan"
             (lambda ()
               (let ((orphans (gptel-auto-workflow--recover-orphans)))
                 (when orphans
                   (message
                    "[auto-workflow] ⚠ Found %d orphan commit(s) from previous run; leaving them
tracked for manual recovery"
                    (length orphans))))))
            (let ((started
                   (let ((gptel-auto-workflow-skip-if-recent-input nil))
                     (gptel-auto-workflow-run-async--guarded
                      nil
                      finish))))
              (unless started
                (funcall finish nil))
              started)))
       (error
         (let* ((err-msg (my/gptel--sanitize-for-logging
                          (error-message-string err) 160))
                (bt (with-output-to-string (backtrace))))
             (let ((step (and (boundp 'gptel-auto-workflow--cron-safe-step)
                              gptel-auto-workflow--cron-safe-step)))
               (ignore-errors (message "[auto-workflow] Cron error at step %S: %s" step err-msg))
               (with-temp-file (expand-file-name "var/tmp/cron-error.txt"
                                                (or (and (boundp 'minimal-emacs-user-directory)
                                                         minimal-emacs-user-directory)
                                                    default-directory))
                (insert (format "Time: %s\nStep: %S\nError: %s\nBacktrace:\n%s\n"
                                (format-time-string "%Y-%m-%dT%H:%M:%S")
                                step err-msg bt))))
           (setq gptel-auto-workflow--stats
                 (list :phase "error" :total 0 :kept 0))
           (gptel-auto-workflow--persist-status)
           (condition-case err nil
               (funcall finish nil)
             (error (message "[auto-workflow] Finish callback also failed: %s"
                             (error-message-string err))))
           nil)))))


(defun gptel-auto-workflow--experiment-suffix ()
  "Get experiment suffix based on hostname.
Returns short hostname like \='onepi5\=', \='daylight\=', or \='macbook\='.
Works across macOS and Linux."
  (let ((name (downcase (system-name))))
    (cond
     ((string-match "^\\([a-z0-9]+\\)" name)
      (match-string 1 name))
     (t "unknown"))))

(defun gptel-auto-workflow--self-heal-check (&optional proj-root)
  "Validate system health before running experiments.
Returns t if healthy, nil if broken (and attempts auto-rollback).
Checks:
1. Critical function symbols exist (fboundp)
2. Byte-compiler self-heal (fix warnings, verify parens)
3. Load of critical modules succeeds

If unhealthy and rollback succeeds, returns t after recovery."
  (let ((healthy t)
        (proj-root (or proj-root (gptel-auto-workflow--default-dir))))
    ;; Check 1: Critical function existence
    (dolist (sym gptel-auto-workflow--critical-functions)
      (unless (fboundp sym)
        (message "[self-heal] ⚠ Critical function void: %s" sym)
        (setq healthy nil)))
    ;; Check 2: Byte-compiler self-heal — fix warnings across all modules
    (when healthy
      (when (fboundp 'gptel-auto-workflow--self-heal-byte-compiler)
        (condition-case err
            (let ((result (gptel-auto-workflow--self-heal-byte-compiler)))
              (when (> (plist-get result :remaining-warnings) 0)
                (message "[self-heal] ⚠ %d byte-compiler warnings remain"
                         (plist-get result :remaining-warnings))))
          (error
           (message "[self-heal] ⚠ Byte-compiler self-heal error: %s"
                    (error-message-string err))
           (setq healthy nil)))))
    ;; Check 3: Load critical modules (idempotent)
    (when healthy
      (condition-case err
          (let ((module-dir (expand-file-name "lisp/modules" proj-root)))
            (dolist (mod '("gptel-tools-agent-subagent"
                           "gptel-tools-agent-prompt-build"
                           "gptel-tools-agent-experiment-core"))
              (let ((file (expand-file-name (concat mod ".el") module-dir)))
                (when (file-exists-p file)
                  (load file 'noerror 'nomessage)))))
        (error
         (message "[self-heal] ⚠ Module load failed: %s" (error-message-string err))
         (setq healthy nil))))
    (if healthy
        (message "[self-heal] ✓ System healthy — %d critical functions bound, syntax OK"
                 (length gptel-auto-workflow--critical-functions))
      ;; Auto-rollback
      (message "[self-heal] ! System unhealthy — attempting auto-rollback")
      (gptel-auto-workflow--self-heal-rollback proj-root))
    ;; Check 4: Scan daemon messages for recurring runtime errors
    ;; OV5 self-detection: catch void-variable, wrong-type-argument, listp
    ;; patterns that indicate code regressions the byte-compiler can't detect.
    (when (and healthy (fboundp 'gptel-auto-workflow--detect-runtime-errors))
      (condition-case nil
          (let ((errors (gptel-auto-workflow--detect-runtime-errors)))
            (when errors
              (message "[self-heal] ⚠ %d recurring runtime errors detected (see *Messages*)"
                       (length errors))
              (dolist (e (seq-take errors 3))
                (message "[self-heal]   %S" e))))
        (error nil)))
    ;; Check 5: Cron-zero combo — pipeline stuck with error propagation
    ;; If both cron-error-propagation and zero-experiments-stuck appear,
    ;; the pipeline is blocked.  Track consecutive occurrences and force
    ;; a fresh cycle after 3+ in a row.
    (condition-case nil
        (let ((issues (gptel-auto-workflow--detect-runtime-errors)))
          (if (and issues
                   (cl-find "cron-error-propagation" issues
                            :key (lambda (e) (plist-get e :pattern)))
                   (cl-find "zero-experiments-stuck" issues
                            :key (lambda (e) (plist-get e :pattern))))
              (progn
                (ignore-errors (message "[self-heal] HIGH: cron-error + zero-experiments detected — pipeline stuck"))
                (when (boundp 'gptel-auto-workflow--self-healing-log)
                  (push (list :timestamp (float-time)
                              :diagnosis "cron-zero-combo"
                              :remedy "retry-experiment-trigger"
                              :severity "HIGH"
                              :effective 'PENDING)
                        gptel-auto-workflow--self-healing-log))
                (cl-incf gptel-auto-workflow--cron-zero-streak)
                (when (>= gptel-auto-workflow--cron-zero-streak 3)
                  (ignore-errors (message "[self-heal] cron-zero streak >=3, clearing cron-safe-step to force fresh cycle"))
                  (setq gptel-auto-workflow--cron-safe-step nil)
                  (setq gptel-auto-workflow--cron-zero-streak 0)))
            ;; Healthy cycle: reset streak counter
            (when (> gptel-auto-workflow--cron-zero-streak 0)
              (setq gptel-auto-workflow--cron-zero-streak 0))))
      (error nil))
    healthy))

(defun gptel-auto-workflow--detect-runtime-errors ()
  "Scan recent daemon log for recurring runtime errors.
Returns a list of plists (:pattern LABEL :count N :remedy STRING), or nil if
clean.
Detects: void-variable, wrong-type-argument, listp, wrong-number-of-arguments,
cron-error-propagation, zero-experiments, llm-nil-response, connection-broken,
bdd-spec-failure, staging-setup-failure.
OV5 uses this for self-diagnosis before experiments."
  (let* ((log-dir (expand-file-name "var/log" (gptel-auto-workflow--default-dir)))
         (files (directory-files log-dir t "\\.log$" t))
         (newest (car (sort files
                            (lambda (a b)
                              (> (float-time (file-attribute-modification-time
                                              (file-attributes a)))
                                 (float-time (file-attribute-modification-time
                                              (file-attributes b))))))))
         ;; Each entry: (REGEXP LABEL THRESHOLD REMEDY)
         ;; Existing patterns keep threshold=3 (same as old > count 2).
         ;; New OV5 pipeline patterns use threshold=2 (default); bdd uses 3.
         (patterns '(("void-variable"              "void-variable"              3 nil)
                     ("wrong-type-argument"         "wrong-type-argument"        3 nil)
                     ("Wrong type argument"         "listp"                      3 nil)
                     ("wrong-number-of-arguments"   "wrong-number-of-arguments"  3 nil)
                     ("Experiment run error"        "experiment-run-error"       3 nil)
                     ("cross-subsystem failed"      "cross-subsystem-crash"      3 nil)
                     ("consecutive failures"        "consecutive-failures"       3 nil)
                     ("Daemon crashed"              "daemon-crash"               3 nil)
                     ("Cron error at step"          "cron-error-propagation"     2 "self-heal-lesson-restore-error-propagation")
                     ("0 total, 0 kept"             "zero-experiments-stuck"     2 "retry-experiment-trigger")
                     ("0 experiments"               "zero-experiments-evolution" 2 "check-evolution-cycle-config")
                     ("new-experiments=0"           "zero-experiments-evolution" 2 "check-evolution-cycle-config")
                     ("LLM returned nil/non-string" "llm-nil-response"           2 "check-mementum-synthesis-api")
                     ("connection broken by remote peer" "connection-broken"     2 "restart-llm-subprocess")
                     ("allium-bdd.*:fail"           "bdd-spec-failure"           3 "investigate-systematic-bdd-failures")
                      ("Missing staging branch configuration" "staging-setup-failure" 2 "reinitialize-staging-branch")
                      ("target dispatch failed"        "target-dispatch-failure"  1 "check-target-dispatch-error")
                      ("grader broken"                 "grader-broken"            2 "check-grader-backend")
                      ("Provider failure"              "provider-failure"         2 "check-llm-provider")))
         (results nil))
    (when (and newest (file-readable-p newest)
               ;; Only scan if file was written in last 2 hours
               (< (- (float-time)
                     (float-time (file-attribute-modification-time
                                  (file-attributes newest))))
                  7200))
      (with-temp-buffer
        (insert-file-contents newest)
        (dolist (p patterns)
          (let ((regexp (nth 0 p))
                (label  (nth 1 p))
                (threshold (nth 2 p))
                (remedy (nth 3 p))
                (count 0))
            (goto-char (point-min))
            (while (re-search-forward regexp nil t)
              (cl-incf count))
            (when (>= count threshold)
              (push (list :pattern label :count count :remedy remedy)
                    results)))))
      ;; Dedup: merge entries with the same :pattern label, keeping the highest count
      (let ((merged (make-hash-table :test 'equal)))
        (dolist (entry results)
          (let ((label (plist-get entry :pattern))
                (count (plist-get entry :count))
                (remedy (plist-get entry :remedy)))
            (if (gethash label merged)
                (when (> count (plist-get (gethash label merged) :count))
                  (puthash label (list :pattern label :count count :remedy remedy) merged))
              (puthash label (list :pattern label :count count :remedy remedy) merged))))
        (setq results nil)
        (maphash (lambda (_k v) (push v results)) merged)))
    (nreverse results)))

(defun gptel-auto-workflow--self-heal-rollback (&optional proj-root)
  "Roll back the most recent commit that changes .el files.
Used when self-heal check detects a broken system.
Removes only the files touched by the breaking commit (not the entire commit),
then re-validates. Returns t if recovery succeeded."
  (let ((proj-root (or proj-root (gptel-auto-workflow--default-dir))))
    (condition-case err
        (let* ((files
                (with-temp-buffer
                  (call-process "git" nil '(t nil) nil
                                "-C" proj-root "diff" "--name-only"
                                "HEAD~1..HEAD" "--" "*.el")
                  (split-string (buffer-string) "\n" t)))
               (rolled-back 0))
          (dolist (file files)
            (when (file-exists-p (expand-file-name file proj-root))
              (call-process "git" nil nil nil
                            "-C" proj-root "checkout" "HEAD~1" "--" file)
              (cl-incf rolled-back)
              (message "[self-heal]   Rolled back: %s" file)))
          (when (> rolled-back 0)
            (message "[self-heal] ✓ Rolled back %d file(s) from HEAD~1" rolled-back)
            ;; Re-verify after rollback
            (let ((recovered t))
              (dolist (sym gptel-auto-workflow--critical-functions)
                (unless (fboundp sym)
                  (setq recovered nil)))
              (if recovered
                  (message "[self-heal] ✓ Recovery confirmed — all critical functions restored")
                (message "[self-heal] ✗ Recovery failed — critical functions still void; manual
intervention needed")))
            t))
      (error
       (message "[self-heal] ⚠ Rollback error: %S" err)
       nil))))

(defun gptel-auto-workflow--cleanup-integrated-remote-optimize-branches (&optional proj-root)
  "Delete remote optimize branches already integrated.
Prune stale tracking refs afterward.

Only remote optimize branches whose tip commit is already contained in
staging or main are deleted."
  (let* ((default-directory (or proj-root (gptel-auto-workflow--default-dir)))
         (remote (gptel-auto-workflow--shared-remote)))
    (if (not (file-directory-p default-directory))
        0
      (let* ((tracking-before
              (length
               (gptel-auto-workflow--remote-tracking-optimize-branches default-directory)))
             (remote-branches
              (gptel-auto-workflow--remote-optimize-branches default-directory))
             (integrated nil)
             (deleted 0))
        (dolist (entry remote-branches)
          (let ((branch (plist-get entry :branch))
                (head (plist-get entry :head)))
            (when (and (gptel-auto-workflow--non-empty-string-p branch)
                       (gptel-auto-workflow--non-empty-string-p head)
                       (gptel-auto-workflow--commit-integrated-p head))
              (push branch integrated))))
        (let ((pending (nreverse integrated)))
          (while pending
            (let ((batch nil)
                  (count 0))
              (while (and pending (< count 25))
                (push (car pending) batch)
                (setq pending (cdr pending))
                (cl-incf count))
              (setq batch (nreverse batch))
              (let* ((delete-command
                      (format "git push %s --delete %s"
                              remote
                              (mapconcat #'shell-quote-argument batch " ")))
                     (delete-result
                      (gptel-auto-workflow--with-skipped-submodule-sync
                       (lambda ()
                         (gptel-auto-workflow--git-result delete-command 180)))))
                (if (= 0 (or (cdr delete-result) -1))
                    (cl-incf deleted (length batch))
                  (message "[auto-workflow] Failed to delete remote optimize branches %s: %s"
                           (mapconcat #'identity batch ", ")
                           (my/gptel--sanitize-for-logging (car delete-result) 200)))))))
        (when (> deleted 0)
          (message "[auto-workflow] Deleted %d integrated remote optimize branch(es)" deleted))
        (when (> tracking-before 0)
          (let ((prune-result
                 (gptel-auto-workflow--git-result
                  (format "git remote prune %s" remote)
                  180)))
            (if (= 0 (or (cdr prune-result) -1))
                (let* ((tracking-after
                        (length
                         (gptel-auto-workflow--remote-tracking-optimize-branches
                          default-directory)))
                       (pruned (max 0 (- tracking-before tracking-after))))
                  (when (> pruned 0)
                    (message "[auto-workflow] Pruned %d stale remote optimize tracking ref(s)"
                             pruned)))
              (message "[auto-workflow] Failed to prune %s optimize tracking refs: %s"
                       remote
                       (my/gptel--sanitize-for-logging (car prune-result) 200)))))
        deleted))))

(defun gptel-auto-workflow--cleanup-old-worktrees ()
  "Remove stale optimize state from previous runs.
Called at start of new run to ensure clean state.
Local optimize branches are only removed for the current host suffix. Remote
optimize branches are only removed when their tip commit is already integrated
into staging or main."
  (let* ((proj-root (gptel-auto-workflow--worktree-base-root))
         (worktree-base-dir (or gptel-auto-workflow-worktree-base
                                "var/tmp/experiments"))
         (worktree-base (expand-file-name worktree-base-dir proj-root))
         (optimize-dir (expand-file-name "optimize" worktree-base))
         (suffix (gptel-auto-workflow--experiment-suffix))
         (pattern (format "%s\\(?:-r[[:alnum:]]+\\)?-exp"
                          (regexp-quote suffix)))
         (removed 0)
         (removed-branches (make-hash-table :test 'equal)))
    (let ((default-directory proj-root))
      (call-process "git" nil nil nil "worktree" "prune"))
    (let ((attached-worktrees
           (sort (copy-sequence (gptel-auto-workflow--optimize-worktrees proj-root))
                 (lambda (a b)
                   (> (length (plist-get a :path))
                      (length (plist-get b :path)))))))
      (dolist (entry attached-worktrees)
        (let ((path (plist-get entry :path))
              (branch (plist-get entry :branch)))
          (condition-case err
              (progn
                (gptel-auto-workflow--discard-worktree-buffers path)
                (call-process "git" nil nil nil "worktree" "remove" "-f" path)
                (when (file-exists-p path)
                  (delete-directory path t))
                (call-process "git" nil nil nil "branch" "-D" branch)
                (puthash branch t removed-branches)
                (cl-incf removed))
            (error
             (message "[auto-workflow] Failed to cleanup %s: %s" path err))))))
    (dolist (branch (gptel-auto-workflow--optimize-branches proj-root))
      (unless (gethash branch removed-branches)
        (condition-case err
            (progn
              (call-process "git" nil nil nil "branch" "-D" branch)
              (puthash branch t removed-branches)
              (cl-incf removed))
          (error
           (message "[auto-workflow] Failed to delete optimize branch %s: %s"
                    branch err)))))
    (cl-incf removed
             (gptel-auto-workflow--cleanup-integrated-remote-optimize-branches
              proj-root))
    (when (file-exists-p optimize-dir)
      (let ((dirs (directory-files optimize-dir t pattern)))
        (dolist (dir dirs)
          (when (file-exists-p dir)
            (condition-case err
                (progn
                  (gptel-auto-workflow--discard-worktree-buffers dir)
                  (delete-directory dir t)
                  (cl-incf removed))
              (error
               (message "[auto-workflow] Failed to cleanup %s: %s" dir err)))))))
    (when (> removed 0)
      (message "[auto-workflow] Cleaned %d old optimize items" removed))
    removed))

(defun gptel-auto-workflow--cleanup-stale-state ()
  "Clean up stale timers, buffers, and state from aborted runs.
Resilient to partial module loads — guards all optional function calls
so cleanup never crashes before resetting state."
  (let* ((proj-root (gptel-auto-workflow--default-dir))
         (cleaned 0)
         (queued-run-id
          (and (bound-and-true-p gptel-auto-workflow--cron-job-running)
               (or (and (stringp gptel-auto-workflow--run-id)
                        (not (string-empty-p gptel-auto-workflow--run-id))
                        gptel-auto-workflow--run-id)
                   (and (stringp gptel-auto-workflow--status-run-id)
                        (not (string-empty-p gptel-auto-workflow--status-run-id))
                        gptel-auto-workflow--status-run-id)))))
    (when proj-root
      (setq gptel-auto-workflow--cron-safe-step "reset-agent")
      (when (fboundp 'my/gptel--reset-agent-task-state)
        (my/gptel--reset-agent-task-state))
      (setq gptel-auto-workflow--cron-safe-step "clear-overrides")
      (when (fboundp 'gptel-auto-workflow--clear-runtime-subagent-provider-overrides)
        (gptel-auto-workflow--clear-runtime-subagent-provider-overrides))
      ;; Clear accumulated backend health strikes so old failures
      ;; don't quarantine all backends on restart (no backend left).
      (setq gptel-auto-workflow--cron-safe-step "clear-lambda-health")
      ;; Force-initialize strike tables if missing (defvar may not have run yet)
      (unless (hash-table-p (and (boundp 'gptel-auto-workflow--lambda-strike-count)
                                 gptel-auto-workflow--lambda-strike-count))
        (setq gptel-auto-workflow--lambda-strike-count (make-hash-table :test 'equal)))
      (unless (hash-table-p (and (boundp 'gptel-auto-workflow--lambda-dead-until)
                                 gptel-auto-workflow--lambda-dead-until))
        (setq gptel-auto-workflow--lambda-dead-until (make-hash-table :test 'equal)))
      (clrhash gptel-auto-workflow--lambda-strike-count)
      (clrhash gptel-auto-workflow--lambda-dead-until)
      ;; Clear cached health so backend-level re-evaluates fresh
      (when (and (boundp 'gptel-auto-workflow--backend-lambda-health-cache)
                 (hash-table-p gptel-auto-workflow--backend-lambda-health-cache))
        (clrhash gptel-auto-workflow--backend-lambda-health-cache))
      (setq gptel-auto-workflow--cron-safe-step "reset-mementum")
      (when (fboundp 'gptel-mementum--reset-synthesis-state)
        (gptel-mementum--reset-synthesis-state))
      (setq gptel-auto-workflow--cron-safe-step "reset-grade")
      (when (fboundp 'gptel-auto-experiment--reset-grade-state)
        (gptel-auto-experiment--reset-grade-state))
      (setq gptel-auto-workflow--cron-safe-step "cancel-timer")
      (when gptel-auto-workflow--cron-job-timer
        (cancel-timer gptel-auto-workflow--cron-job-timer)
        (setq gptel-auto-workflow--cron-job-timer nil))
      (setq gptel-auto-workflow--cron-safe-step "stop-refresh")
      (gptel-auto-workflow--stop-status-refresh-timer)
      (setq gptel-auto-workflow--cron-safe-step "cleanup-worktrees")
      (gptel-auto-workflow--cleanup-old-worktrees)
      (dolist (timer (copy-sequence timer-list))
        (condition-case err
            (when (timerp timer)
              (let* ((fn-rep (condition-case nil
                                 (prin1-to-string (timer--function timer))
                               (error ""))))
                (when (and (stringp fn-rep)
                           (or (string-match-p "nucleus" fn-rep)
                               (string-match-p "gptel.*agent" fn-rep)
                               (string-match-p "auto-experiment" fn-rep)))
                  (cancel-timer timer)
                  (cl-incf cleaned))))
          (error
           (message "[auto-workflow] Timer cleanup error: %S" err))))
      (dolist (buf (buffer-list))
        (when (buffer-live-p buf)
          (with-current-buffer buf
            (when (and (stringp default-directory)
                       (string-match-p (format "optimize/.*-%s" (gptel-auto-workflow--experiment-suffix)) default-directory)
                       (not (file-exists-p default-directory)))
              (kill-buffer buf)
              (cl-incf cleaned)))))
      (setq gptel-auto-workflow--running nil
            gptel-auto-workflow--status-run-id queued-run-id
            gptel-auto-workflow--run-id queued-run-id
            gptel-auto-workflow--current-target nil)
      (setq gptel-auto-workflow--stats
            (plist-put gptel-auto-workflow--stats
                       :phase (if (bound-and-true-p gptel-auto-workflow--cron-job-running)
                                  (or (and (listp gptel-auto-workflow--stats)
                                           (plist-get gptel-auto-workflow--stats :phase))
                                      "queued")
                                "idle")))
      (gptel-auto-workflow--persist-status)
      (clrhash gptel-auto-workflow--worktree-state))
    (when (> cleaned 0)
      (message "[auto-workflow] Cleaned %d stale items" cleaned))))

(defun gptel-auto-workflow--kept-target-count (results)
  "Return the number of distinct targets with kept results in RESULTS."
  (let ((seen (make-hash-table :test 'equal))
        (count 0))
    (dolist (result results count)
      (let ((target (plist-get result :target)))
        (when (and (plist-get result :kept)
                   (stringp target)
                   (not (gethash target seen)))
          (puthash target t seen)
          (cl-incf count))))))

(defun gptel-auto-workflow--run-with-targets (targets completion-callback)
  "Run experiments for TARGETS sequentially."
  (cl-block gptel-auto-workflow--run-with-targets
    (let* ((proj-root (gptel-auto-workflow--default-dir))
         (validated-targets
          (if (fboundp 'gptel-auto-workflow--filter-valid-targets)
              (gptel-auto-workflow--filter-valid-targets
               targets proj-root most-positive-fixnum)
            targets))
           (validated-targets
            (if (and (fboundp 'gptel-knowledge--frontier-select-targets)
                     (fboundp 'gptel-auto-workflow--results-file-path))
                (let* ((tsv (gptel-auto-workflow--results-file-path))
                       (frontier (and (file-readable-p tsv)
                                      (gptel-knowledge--frontier-select-targets tsv (length validated-targets))))
                       (ranked (plist-get frontier :targets)))
                  (if (and ranked (> (length ranked) 0))
                      (let ((frontier-set (delete-dups ranked))
                            (rest nil))
                        (dolist (tgt validated-targets)
                          (unless (member tgt frontier-set)
                            (push tgt rest)))
                        (append frontier-set (nreverse rest)))
                    validated-targets))
              validated-targets))
           (validated-targets
            (if (fboundp 'gptel-auto-workflow--gap-prioritize-targets)
                (gptel-auto-workflow--gap-prioritize-targets validated-targets)
              validated-targets))
          (dropped-count (- (length targets) (length validated-targets)))
          (run-id (gptel-auto-workflow--current-run-id))
         (callback-run-id (and gptel-auto-workflow--running
                               gptel-auto-workflow--run-id))
         (run-buffer (current-buffer))
         (all-results '())
         (kept-count 0)
         (finish
          (gptel-auto-workflow--make-idempotent-callback
           (lambda ()
             (let ((final-phase (if gptel-auto-experiment--quota-exhausted
                                    "quota-exhausted"
                                  "complete")))
                (gptel-auto-workflow--clear-runtime-subagent-provider-overrides)
                (gptel-auto-workflow--stop-status-refresh-timer)
                ;; Invalidate prefix cache when run ends
                (when (fboundp 'gptel-prefix-cache-on-run-end)
                  (gptel-prefix-cache-on-run-end))
                (setq gptel-auto-workflow--running nil
                      gptel-auto-workflow--run-project-root nil
                      gptel-auto-workflow--current-target nil
                      gptel-auto-workflow--current-project nil)
               (setq gptel-auto-workflow--stats
                     (plist-put gptel-auto-workflow--stats :phase final-phase))
                (message "[auto-workflow] Complete: %d experiments, %d targets improved"
                         (length all-results) kept-count)
                (when (fboundp 'gptel-auto-experiment--log-run-summary)
                  (gptel-auto-experiment--log-run-summary all-results run-id))
                (gptel-auto-workflow--persist-status)
               (when completion-callback
                 (funcall completion-callback all-results)))))))
    (when (> dropped-count 0)
      (message "[auto-workflow] Dropped %d invalid target%s before dispatch"
               dropped-count
               (if (= dropped-count 1) "" "s")))
    (when (null validated-targets)
      (setq gptel-auto-workflow--running nil
            gptel-auto-workflow--current-target nil
            gptel-auto-workflow--current-project nil
            gptel-auto-workflow--run-project-root nil)
      (setq gptel-auto-workflow--stats
            (plist-put gptel-auto-workflow--stats :phase "complete"))
      (message "[auto-workflow] Complete: %d experiments, %d targets improved"
               0 0)
      (gptel-auto-workflow--persist-status)
      (message "[auto-workflow] No valid targets remain after filtering")
      (when completion-callback
        (funcall completion-callback nil))
      (cl-return-from gptel-auto-workflow--run-with-targets nil))
    ;; Set project context for subagent routing
    (setq gptel-auto-workflow--current-project proj-root
          gptel-auto-workflow--run-project-root proj-root)
    (setq gptel-auto-workflow--stats
          (plist-put gptel-auto-workflow--stats :phase "running"))
    (setq gptel-auto-workflow--stats
          (plist-put gptel-auto-workflow--stats :total (length validated-targets)))
    (setq gptel-auto-workflow--stats
          (plist-put gptel-auto-workflow--stats :kept 0))
    (gptel-auto-workflow--persist-status)
    (message "[auto-workflow] Starting %s with %d targets" run-id (length validated-targets))
    ;; Compute prefix cache for this run (DeepSeek-Reasonix style):
    ;; Stable prefix (AGENTS.md + tools + mementum) computed once, reused
    ;; across all experiments. Enables LLM prefix-cache hits.
    (when (fboundp 'gptel-prefix-cache-on-run-start)
      (condition-case err
          (gptel-prefix-cache-on-run-start run-id)
        (error
         (message "[prefix-cache] Compute failed: %s" (error-message-string err)))))
    ;; Priority ordering: sort targets by keep-rate ascending (hardest first)
    (let* ((ordered-targets
            (if (fboundp 'gptel-auto-experiment--target-keep-rate-from-tsv)
                (sort (copy-sequence validated-targets)
                      (lambda (a b)
                        (let ((rate-a (or (gptel-auto-experiment--target-keep-rate-from-tsv a) 0.5))
                              (rate-b (or (gptel-auto-experiment--target-keep-rate-from-tsv b) 0.5)))
                          (< rate-a rate-b))))
              validated-targets))
           (redistributed-budget 0))
      (when (and (> (length ordered-targets) 1)
                 (not (equal ordered-targets validated-targets)))
        (message "[priority-order] Reordered %d targets by keep-rate (hardest first): %s"
                 (length ordered-targets)
                 (mapconcat (lambda (tgt) (format "%s(%.0f%%)" tgt (* 100 (or (gptel-auto-experiment--target-keep-rate-from-tsv tgt) 50))))
                            ordered-targets " → ")))
      (cl-labels
         ((finish-run ()
            ;; Record any pending research batch before finishing
            (when (and (fboundp 'gptel-auto-workflow--record-research-batch)
                       (boundp 'gptel-auto-workflow--research-batch-results)
                       gptel-auto-workflow--research-batch-results)
              (gptel-auto-workflow--record-research-batch))
            (funcall finish))
         (run-next (remaining-targets)
           (if (null remaining-targets)
               (finish-run)
             (let ((target (car remaining-targets)))
               (setq gptel-auto-workflow--current-target target)
               (let ((target-complete
                      (gptel-auto-workflow--make-idempotent-callback
                        (lambda (results)
                          (if (not (gptel-auto-workflow--run-callback-live-p callback-run-id))
                              (message "[auto-workflow] Ignoring stale target completion for %s; run %s is no longer active"
                                       target run-id)
                           (setq all-results (append all-results results))
                           (setq kept-count
                                  (gptel-auto-workflow--kept-target-count all-results))
                           (setq gptel-auto-workflow--stats
                                  (plist-put gptel-auto-workflow--stats :kept kept-count))
                           ;; DIALECTIC moderator: forced backend swap on
                           ;; 3+ consecutive failures for this target
                           (when (and (fboundp 'gptel-knowledge--dialectic-check)
                                      (fboundp 'gptel-auto-workflow--clear-runtime-subagent-provider-overrides)
                                      results
                                      (cl-every (lambda (r) (not (equal (plist-get r :decision) "kept"))) results))
                             (let ((dialectic (gptel-knowledge--dialectic-check
                                               (mapcar (lambda (r)
                                                         (list :id (plist-get r :id)
                                                               :decision (plist-get r :decision)
                                                               :failure-type (if (plist-get r :error) :timeout :quality-drop)))
                                                       results))))
                               (when (plist-get dialectic :intervention)
                                 (message "[dialectic] %s: %s — %s"
                                          target
                                          (plist-get dialectic :prompt)
                                          (plist-get dialectic :forced-action))
                                 (when (eq (plist-get dialectic :forced-action) :backend-swap)
                                   (gptel-auto-workflow--clear-runtime-subagent-provider-overrides)
(message "[dialectic] Forced backend swap for next target")))))
                            ;; After-experiment hook: monitoring agent and post-batch analysis
                            ;; Monitoring agent registers itself in this hook via:
                            ;; (add-hook 'gptel-auto-workflow-after-experiment-hook
                            ;;           #'gptel-auto-workflow--monitoring-cycle)
                            (condition-case err
                                (run-hooks 'gptel-auto-workflow-after-experiment-hook)
                              (error
                               (message "[monitoring] Post-batch hook error: %s"
                                        (error-message-string err))))
                            (gptel-auto-workflow--persist-status)
                           (if gptel-auto-experiment--quota-exhausted
                                 (progn
                                   (message "[auto-workflow] Provider quota exhausted for %s; continuing with remaining targets"
                                            target)
                                   (setq gptel-auto-experiment--quota-exhausted nil)
                                   (gptel-auto-workflow--clear-rate-limited-backends)
                                   (if (buffer-live-p run-buffer)
                                       (with-current-buffer run-buffer
                                         (let ((default-directory proj-root)
                                               (gptel-auto-workflow--project-root-override proj-root)
                                               (gptel-auto-workflow--current-project proj-root)
                                               (gptel-auto-workflow--run-project-root proj-root))
                                           (run-next (cdr remaining-targets))))
                                     (let ((default-directory proj-root)
                                           (gptel-auto-workflow--project-root-override proj-root)
                                           (gptel-auto-workflow--current-project proj-root)
                                           (gptel-auto-workflow--run-project-root proj-root))
                                       (run-next (cdr remaining-targets)))))
                              ;; Budget reallocation: redistribute unused slots from
                              ;; early-saturating targets to targets that need more help
                              (let* ((actual-count (length results))
                                     (budget (max gptel-auto-experiment-max-per-target 1))
                                     (unused (max 0 (- budget actual-count)))
                                     (new-redistributed (+ redistributed-budget unused)))
                                (when (> unused 0)
                                  (message "[budget-realloc] %s used %d/%d experiments (+%d spare → %d total redistributed)"
                                           target actual-count budget unused new-redistributed))
                                (setq redistributed-budget new-redistributed)
                                ;; Boost next target's budget with redistributed slots
                                (when (and (> redistributed-budget 0) (cdr remaining-targets))
                                  (let ((boosted (+ gptel-auto-experiment-max-per-target
                                                     redistributed-budget)))
                                    (setq gptel-auto-experiment-max-per-target boosted)
                                    (setq redistributed-budget 0)
                                    (message "[budget-realloc] Next target gets budget=%d (including %d redistributed)"
                                             boosted unused)))
                                (if (buffer-live-p run-buffer)
                                 (with-current-buffer run-buffer
                                   (let ((default-directory proj-root)
                                         (gptel-auto-workflow--project-root-override proj-root)
                                         (gptel-auto-workflow--current-project proj-root)
                                         (gptel-auto-workflow--run-project-root proj-root))
                                     (run-next (cdr remaining-targets))))
                                (let ((default-directory proj-root)
                                      (gptel-auto-workflow--project-root-override proj-root)
                                      (gptel-auto-workflow--current-project proj-root)
                                      (gptel-auto-workflow--run-project-root proj-root))
                                  (run-next (cdr remaining-targets)))))))))))
                 (gptel-auto-experiment-loop target target-complete))))))
      (condition-case err
          (if (buffer-live-p run-buffer)
              (with-current-buffer run-buffer
                (let ((default-directory proj-root)
                      (gptel-auto-workflow--project-root-override proj-root)
                      (gptel-auto-workflow--current-project proj-root)
                      (gptel-auto-workflow--run-project-root proj-root))
                  (run-next validated-targets)))
            (let ((default-directory proj-root)
                  (gptel-auto-workflow--project-root-override proj-root)
                  (gptel-auto-workflow--current-project proj-root)
                  (gptel-auto-workflow--run-project-root proj-root))
              (run-next validated-targets)))
        (error
         (setq gptel-auto-workflow--running nil
               gptel-auto-workflow--current-target nil
               gptel-auto-workflow--current-project nil
               gptel-auto-workflow--run-project-root nil)
         (setq gptel-auto-workflow--stats
               (plist-put gptel-auto-workflow--stats :phase "error"))
         (gptel-auto-workflow--persist-status)
         (message "[auto-workflow] Initial target dispatch failed: %s"
                  (error-message-string err))
          (when completion-callback
            (funcall completion-callback nil)))))))))


(defun gptel-auto-workflow-run (&optional targets)
  "Run auto-workflow asynchronously.
Non-blocking - returns immediately.
Check status with `gptel-auto-workflow-status'.
TARGETS defaults to `gptel-auto-workflow-targets'."
  (interactive)
  (gptel-auto-workflow-run-async targets))

;;; Autonomous Research Agent (directive.md + skills + mementum)

(defcustom gptel-auto-workflow-program-file "docs/directive.md"
  "Path to directive.md (human-editable objectives)."
  :type 'file
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-skills-dir "mementum/knowledge"
  "Directory containing optimization-skills/ and mutations/."
  :type 'directory
  :group 'gptel-tools-agent)

(defvar gptel-auto-workflow--program nil
  "Parsed directive.md content.")

(defvar gptel-auto-workflow--skills nil
  "Loaded optimization skills for current run.")

(defun gptel-auto-workflow-load-program ()
  "Load and parse docs/directive.md."
  (let* ((file (expand-file-name gptel-auto-workflow-program-file
                                 (gptel-auto-workflow--project-root)))
         (content (gptel-auto-workflow--read-file-contents file))
         (targets '())
         (immutable '())
         (mutations '()))
    (when content
      (with-temp-buffer
        (insert content)
        (goto-char (point-min))
        (when (re-search-forward "^## Targets" nil t)
          (forward-line 1)
          (when (re-search-forward "^```" nil t)
            (forward-line 1)
            (while (and (not (looking-at "```")) (not (eobp)))
              (let ((line (string-trim (thing-at-point 'line t))))
                (when (and (> (length line) 0) (not (string-match-p "^#" line)))
                  (push line targets)))
              (forward-line 1))))
        (goto-char (point-min))
        (when (re-search-forward "^### Immutable Files" nil t)
          (forward-line 1)
          (when (re-search-forward "^```" nil t)
            (forward-line 1)
            (while (and (not (looking-at "```")) (not (eobp)))
              (let ((line (string-trim (thing-at-point 'line t))))
                (when (> (length line) 0)
                  (push line immutable)))
              (forward-line 1))))
        (goto-char (point-min))
        (when (re-search-forward "^Allowed mutation types:" nil t)
          (forward-line 1)
          (while (and (not (looking-at "^##")) (not (eobp)))
            (when (looking-at "- \\[x\\] \\([a-z-]+\\)")
              (push (match-string 1) mutations))
            (forward-line 1)))))
    (list :targets (nreverse targets)
          :immutable (nreverse immutable)
          :mutations (nreverse mutations)
          :file file)))

(defun gptel-auto-workflow-skill-path (target type)
  "Get skill path for TARGET. TYPE is \\='target or \\='mutation."
  (let* ((target-name (if (gptel-auto-workflow--non-empty-string-p target)
                          target
                        "unknown"))
         (name (file-name-sans-extension (file-name-nondirectory target-name)))
         (parts (if (> (length name) 0) (split-string name "-") (list name)))
         (skill-name-candidate (car (last parts)))
         (skill-name (if (gptel-auto-workflow--non-empty-string-p skill-name-candidate)
                         skill-name-candidate
                       "unknown")))
    (if (eq type 'target)
        (format "%s/optimization-skills/%s.md" gptel-auto-workflow-skills-dir skill-name)
      (format "%s/mutations/%s.md" gptel-auto-workflow-skills-dir target-name))))

(defun gptel-auto-workflow-skill-load (skill-file)
  "Load skill from SKILL-FILE."
  (let ((file (expand-file-name skill-file (gptel-auto-workflow--project-root))))
    (when (file-exists-p file)
      (let ((content (gptel-auto-workflow--read-file-contents file))
            (skill (list :file skill-file)))
        (when (string-match "^phi:[[:space:]]*\\([0-9.]+\\)" content)
          (plist-put skill :phi (string-to-number (match-string 1 content))))
        (when (string-match "^mutation-skills:[[:space:]]*\n\\(\\(?:  - .+\n\\)+\\)" content)
          (let ((refs (match-string 1 content)))
            (plist-put skill :mutation-skills
                       (mapcar (lambda (line)
                                 (string-trim (replace-regexp-in-string "^  - " "" line)))
                               (split-string refs "\n" t)))))
        (plist-put skill :content content)
        skill))))

(defun gptel-auto-workflow-recall-skills (target)
  "Load target skill + referenced mutation skills for TARGET."
  (let* ((target-skill-file (gptel-auto-workflow-skill-path target 'target))
         (target-skill (gptel-auto-workflow-skill-load target-skill-file))
         (mutation-skills '()))
    (when target-skill
      (dolist (ref (plist-get target-skill :mutation-skills))
        (let ((ms (gptel-auto-workflow-skill-load ref)))
          (when ms (push ms mutation-skills)))))
    (list :target-skill target-skill
          :mutation-skills (nreverse mutation-skills))))

(defun gptel-auto-workflow-skill-suggest-hypothesis (skills)
  "Get suggested hypothesis from SKILLS."
  (let* ((target-skill (plist-get skills :target-skill))
         (content (when (and target-skill
                             (proper-list-p target-skill))
                    (plist-get target-skill :content))))
    (when (and (stringp content)
               (string-match "^## Next Hypothesis\n\n\\(.+\\)" content))
      (match-string 1 content))))

(defun gptel-auto-workflow--extract-mutation-templates (skills)
  "Extract hypothesis templates from mutation skills in SKILLS.
Returns list of template strings for hypothesis generation."
  (let* ((mutation-skills (plist-get skills :mutation-skills))
         (templates '()))
    (dolist (ms mutation-skills)
      (let ((content (plist-get ms :content)))
        (when content
          (let ((start (string-match "## Hypothesis Templates" content)))
            (when start
              (let* ((code-start (string-match "```\n" content start))
                     (code-end (when code-start (string-match "\n```" content (+ code-start 4)))))
                (when (and code-start code-end)
                  (let ((raw (substring content (+ code-start 4) code-end)))
                    (dolist (line (split-string raw "\n" t))
                      (when (string-match-p "^\"" line)
                        (push (string-trim line "\"\\s-*" "\"\\s-*") templates)))))))))))
    (nreverse templates)))

(defun gptel-auto-workflow--format-weakest-keys (baseline-scores)
  "Format weakest keys for prompt from BASELINE-SCORES.
Returns formatted string with key names and signals."
  (when baseline-scores
    (let* ((weakest (gptel-benchmark-eight-keys-weakest-with-signals baseline-scores 2))
           (lines '()))
      (dolist (item weakest)
        (let* ((key (plist-get item :key))
               (score (plist-get item :score))
               (signals (plist-get item :signals))
               (def (alist-get key gptel-benchmark-eight-keys-definitions))
               (name (if def (plist-get def :name) "Unknown"))
               (symbol (if def (plist-get def :symbol) "?")))
          (push (format "- %s %s: %.0f%% (focus: %s)"
                        symbol name (* 100 score)
                        (string-join (or signals '("improve")) ", "))
                lines)))
      (mapconcat #'identity (nreverse lines) "\n"))))

(defun gptel-auto-workflow-orient ()
  "Orient for auto-workflow run. Load program.md and skills."
  (let ((program (gptel-auto-workflow-load-program)))
    (setq gptel-auto-workflow--program program)
    (message "[autonomous] Loaded program: %d targets"
             (length (plist-get program :targets)))
    (let ((skills '()))
      (dolist (target (plist-get program :targets))
        (push (cons target (gptel-auto-workflow-recall-skills target)) skills))
      (setq gptel-auto-workflow--skills skills))
    program))

;;; Skill Evolution (Continuity + Compounding)

(defun gptel-auto-workflow-detect-mutation (hypothesis)
  "Detect mutation type from HYPOTHESIS string."
  (cond
   ((string-match-p "cache\\|Cache\\|memoize\\|memo" hypothesis) "caching")
   ((string-match-p "lazy\\|defer\\|on-demand\\|delay" hypothesis) "lazy-init")
   ((string-match-p "simplif\\|remove\\|merge\\|reduce\\|eliminate" hypothesis) "simplification")
   (t "unknown")))

(defun gptel-auto-workflow-update-target-skill (target results)
  "Update TARGET skill file with RESULTS from night."
  (let* ((skill-file (gptel-auto-workflow-skill-path target 'target))
         (file (expand-file-name skill-file (gptel-auto-workflow--project-root))))
    (when (file-exists-p file)
      (let* ((content (gptel-auto-workflow--read-file-contents file))
             (by-mutation (make-hash-table :test 'equal))
             (successful '())
             (failed '())
             (best-hypothesis nil)
             (best-delta 0)
             (total-kept 0)
             (score-before nil)
             (score-after nil))
        (dolist (r results)
          (let* ((hypothesis (gptel-auto-workflow--plist-get r :hypothesis ""))
                 (mutation (gptel-auto-workflow-detect-mutation hypothesis))
                 (kept (gptel-auto-workflow--plist-get r :kept nil))
                 (delta (gptel-auto-workflow--plist-get r :delta 0)))
            (when (and kept (> delta best-delta))
              (setq best-delta delta
                    best-hypothesis hypothesis))
            (when kept (cl-incf total-kept))
            (unless score-before
              (setq score-before (gptel-auto-workflow--plist-get r :score-before nil)))
            (when (and kept (gptel-auto-workflow--plist-get r :score-after nil))
              (setq score-after (gptel-auto-workflow--plist-get r :score-after nil)))
            (puthash mutation (cons r (gethash mutation by-mutation)) by-mutation)))
        (maphash
         (lambda (mutation mutation-results)
           (let* ((kept-count (cl-count-if (lambda (r) (gptel-auto-workflow--plist-get r :kept nil)) mutation-results))
                  (total (length mutation-results))
                  (success-rate (if (> total 0) (/ (* 100 kept-count) total) 0))
                  (kept-results (cl-remove-if-not (lambda (r) (gptel-auto-workflow--plist-get r :kept nil)) mutation-results))
                  (avg-delta (if kept-results
                                 (/ (apply #'+ (mapcar (lambda (r) (gptel-auto-workflow--plist-get r :delta 0)) kept-results))
                                    (length kept-results))
                               0))
                  (best (car (sort kept-results (lambda (a b)
                                                  (> (gptel-auto-workflow--plist-get a :delta 0)
                                                     (gptel-auto-workflow--plist-get b :delta 0))))))
                  (best-hyp (when best (gptel-auto-workflow--plist-get best :hypothesis ""))))
             (if (>= success-rate 50)
                 (push (list mutation success-rate avg-delta best-hyp) successful)
               (when (< success-rate 50)
                 (push (list mutation success-rate 
                             (if (< success-rate 50) "Low success rate" ""))
                       failed)))))
         by-mutation)
        (with-temp-buffer
          (insert content)
          (goto-char (point-min))
          (when (re-search-forward "^runs:[[:space:]]*\\([0-9]+\\)" nil t)
            (replace-match (format "runs: %d" (1+ (string-to-number (match-string 1))))))
          (goto-char (point-min))
          (when (re-search-forward "^phi:[[:space:]]*\\([0-9.]+\\)" nil t)
            (let* ((total (length results))
                   (new-phi (if (> total 0) (/ (float total-kept) total) 0.5)))
              (replace-match (format "phi: %.2f" new-phi))))
          (goto-char (point-min))
          (when (re-search-forward "^## Successful Mutations" nil t)
            (forward-line 3)
            (delete-region (point) (when (re-search-forward "^## " nil t) (match-beginning 0)))
            (backward-char 1)
            (dolist (s (nreverse successful))
              (insert (format "| %s | %.0f%% | %+.2f | %s |\n"
                              (nth 0 s) (nth 1 s) (nth 2 s) (or (nth 3 s) "-")))))
          (goto-char (point-min))
          (when (re-search-forward "^## Failed Mutations" nil t)
            (forward-line 3)
            (delete-region (point) (when (re-search-forward "^## " nil t) (match-beginning 0)))
            (backward-char 1)
            (dolist (f (nreverse failed))
              (insert (format "| %s | %.0f%% | %s |\n"
                              (nth 0 f) (nth 1 f) (nth 2 f)))))
          (goto-char (point-min))
          (when (re-search-forward "^## Nightly History" nil t)
            (forward-line 3)
            (let ((date (format-time-string "%Y-%m-%d"))
                  (exp-count (length results)))
              (insert (format "| %s | %d | %d | %.2f | %.2f | %+.2f |\n"
                              date exp-count total-kept
                              (or score-before 0)
                              (or score-after 0)
                              (if (and score-before score-after)
                                  (- score-after score-before)
                                0)))))
          (goto-char (point-min))
          (when (re-search-forward "^## Next Hypothesis" nil t)
            (forward-line 1)
            (delete-region (point) (when (re-search-forward "^## " nil t) (match-beginning 0)))
            (backward-char 1)
            (insert (format "\n%s\n" (or best-hypothesis "(Run more experiments)"))))
          (write-region (point-min) (point-max) file))))))

(defun gptel-auto-workflow--daemon-health ()
  "Return a plist with daemon health status for pipeline digest.
Checks: running state, experiment count, keep-rate, rate-limited backends."
  (let* ((running (and (boundp 'gptel-auto-workflow--running)
                       gptel-auto-workflow--running))
         (target (and (boundp 'gptel-auto-workflow--current-target)
                      gptel-auto-workflow--current-target))
         (rate-limited (and (boundp 'gptel-auto-workflow--rate-limited-backends)
                            (length gptel-auto-workflow--rate-limited-backends)))
         (grade-timeout (and (boundp 'gptel-auto-experiment-grade-timeout)
                             gptel-auto-experiment-grade-timeout)))
    (format "running=%s target=%s rate-limited=%d grade-timeout=%ds"
            (if running "yes" "no")
            (or target "none")
            (or rate-limited 0)
            (or grade-timeout 900))))

(provide 'gptel-tools-agent-main)
;;; gptel-tools-agent-main.el ends here