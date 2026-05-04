;;; gptel-tools-agent-main.el --- Main entry point, workflow control -*- lexical-binding: t; -*-
;; Part of gptel-tools-agent split

(defun gptel-auto-workflow--call-process-with-watchdog (program &optional infile destination display &rest args)
  "Run blocking PROGRAM while pausing the workflow watchdog.

This avoids false watchdog force-stops when long local verification phases block
Emacs long enough for a queued watchdog check to fire immediately afterward."
  (let ((workflow-active (or gptel-auto-workflow--running
                             gptel-auto-workflow--cron-job-running)))
    (when workflow-active
      (when (timerp gptel-auto-workflow--watchdog-timer)
        (cancel-timer gptel-auto-workflow--watchdog-timer))
      (setq gptel-auto-workflow--watchdog-timer nil))
    (unwind-protect
        (apply #'call-process program infile destination display args)
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
  "Refresh the persisted workflow snapshot while the workflow is active."
  (if (or gptel-auto-workflow--running
          gptel-auto-workflow--cron-job-running)
      (condition-case-unless-debug err
          (gptel-auto-workflow--persist-status)
        (error
         (message "[auto-workflow] Status refresh failed: %s"
                  (error-message-string err))
         (gptel-auto-workflow--stop-status-refresh-timer)))
    (gptel-auto-workflow--stop-status-refresh-timer)))

(defun gptel-auto-workflow--maybe-start-status-refresh-timer ()
  "Start the workflow status refresh timer if conditions are met."
  (when (timerp gptel-auto-workflow--status-refresh-timer)
    (cancel-timer gptel-auto-workflow--status-refresh-timer)
    (setq gptel-auto-workflow--status-refresh-timer nil))
  (when (and (or gptel-auto-workflow--running
                 gptel-auto-workflow--cron-job-running)
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
Interactive command to recover from hung workflow state."
  (interactive)
  (my/gptel--reset-agent-task-state)
  (gptel-auto-workflow--clear-runtime-subagent-provider-overrides)
  (gptel-mementum--reset-synthesis-state)
  (gptel-auto-experiment--reset-grade-state)
  (when gptel-auto-workflow--cron-job-timer
    (cancel-timer gptel-auto-workflow--cron-job-timer)
    (setq gptel-auto-workflow--cron-job-timer nil))
  (gptel-auto-workflow--stop-status-refresh-timer)
  (gptel-auto-workflow--terminate-active-shell-processes)
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
  - 30-min inactivity check (gptel-auto-workflow-skip-if-recent-input)
  - Cron schedule (macOS: 10AM,2PM,6PM; Pi5: every 4h)

Override in your config:
  (setq gptel-auto-workflow-quiet-hours '(9 10 11 12 13 14 15 16 17))  ; Work hours
  (setq gptel-auto-workflow-quiet-hours '(0 1 2 3 4 5 6))  ; Night only")

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
Replaces curly quotes, dashes, and zero-width characters with ASCII equivalents.
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

(defun gptel-auto-workflow-run-async (&optional targets completion-callback)
  "Run auto-workflow asynchronously with TARGETS.
Non-blocking - returns immediately, check status with `gptel-auto-workflow-status'.
TARGETS defaults to `gptel-auto-workflow-targets'.
COMPLETION-CALLBACK is called with results when all targets are done.

Skips if Emacs is in active use (unsaved buffers, recent input, etc.).
Check `gptel-auto-workflow--active-use-p' for details.

Usage:
  emacsclient -e '(gptel-auto-workflow-run-async)'
  emacsclient -e '(gptel-auto-workflow-status)'
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
    (gptel-auto-workflow--require-magit-dependencies)
    (gptel-auto-workflow--migrate-legacy-provider-defaults)
    (gptel-auto-workflow--clear-runtime-subagent-provider-overrides)
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
    (unless gptel-auto-workflow--cron-job-running
      (gptel-auto-workflow--mark-messages-start))
    (gptel-auto-workflow--start-status-refresh-timer)
    (gptel-auto-workflow--persist-status)
    ;; Start watchdog timer
    (gptel-auto-workflow--restart-watchdog-timer)
    (if targets
        (gptel-auto-workflow--run-with-targets targets completion-callback)
      (require 'gptel-auto-workflow-strategic)
      (gptel-auto-workflow-select-targets
       (lambda (selected-targets)
         (gptel-auto-workflow--run-with-targets selected-targets completion-callback))))
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
    (load-file (expand-file-name "lisp/modules/gptel-ext-context.el" root))
    (load-file (expand-file-name "lisp/modules/gptel-ext-fsm-utils.el" root))
    (load-file (expand-file-name "lisp/modules/gptel-ext-retry.el" root))
    (load-file (expand-file-name "lisp/modules/gptel-ext-tool-sanitize.el" root))
    (load-file (expand-file-name "lisp/modules/nucleus-presets.el" root))
    (load-file (expand-file-name "lisp/modules/gptel-auto-workflow-strategic.el" root))
    (load-file (expand-file-name "lisp/modules/gptel-auto-workflow-projects.el" root))
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
        (nucleus--override-gptel-agent-presets)))))


(defun gptel-auto-workflow-cron-safe (&optional completion-callback)
  "Run auto-workflow with full cleanup for cron jobs.
Cancels stale timers, kills orphaned buffers, resets state, then runs.
Safe to call from cron - handles all edge cases.
Sets `gptel-auto-workflow-persistent_headless' to prevent interactive prompts.
When COMPLETION-CALLBACK is non-nil, call it after the workflow finishes."
  (let* ((proj-root (gptel-auto-workflow--default-dir))
         (finish
          (gptel-auto-workflow--make-idempotent-callback
           (lambda (&optional results)
             (gptel-auto-workflow--disable-headless-suppression)
             (when completion-callback
               (funcall completion-callback results))))))
    (condition-case err
        (progn
          (setq default-directory proj-root
                gptel-auto-workflow-persistent-headless t)
          (gptel-auto-workflow--enable-headless-suppression)
          (if gptel-auto-workflow--running
              (progn
                (message "[auto-workflow] Job already running; skipping new request")
                (funcall finish nil)
                nil)
            ;; Enable headless suppression before requiring/loading workflow
            ;; dependencies so worker startup does not byte-compile unrelated ELPA
            ;; packages on load.
            (require 'magit)
            (require 'json)
            (load-file (expand-file-name "lisp/modules/gptel-tools-agent.el" proj-root))
            (when (fboundp 'gptel-auto-workflow--reload-live-support)
              (gptel-auto-workflow--reload-live-support proj-root))
            (setq gptel-auto-experiment--api-error-count 0)
            (gptel-auto-workflow--safe-call "Cleanup" #'gptel-auto-workflow--cleanup-stale-state)
            (gptel-auto-workflow--safe-call "Sync staging" #'gptel-auto-workflow--sync-staging-with-main)
            (gptel-auto-workflow--safe-call
             "Orphan scan"
             (lambda ()
               (let ((orphans (gptel-auto-workflow--recover-orphans)))
                 (when orphans
                   (message
                    "[auto-workflow] ⚠ Found %d orphan commit(s) from previous run; leaving them tracked for manual recovery"
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
       (message "[auto-workflow] Cron error: %s"
                (my/gptel--sanitize-for-logging (error-message-string err) 160))
       (setq gptel-auto-workflow--stats
             (list :phase "error" :total 0 :kept 0))
       (gptel-auto-workflow--persist-status)
       (funcall finish nil)
       nil))))


(defun gptel-auto-workflow--experiment-suffix ()
  "Get experiment suffix based on hostname.
Returns short hostname like 'onepi5', 'daylight', or 'macbook'.
Works across macOS and Linux."
  (let ((name (downcase (system-name))))
    (cond
     ((string-match "^\\([a-z0-9]+\\)" name)
      (match-string 1 name))
     (t "unknown"))))

(defun gptel-auto-workflow--cleanup-integrated-remote-optimize-branches (&optional proj-root)
  "Delete remote optimize branches already integrated and prune stale tracking refs.

Only remote optimize branches whose tip commit is already contained in staging or
main are deleted. Stale shared-remote optimize tracking refs are pruned
afterward."
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
                (if (= 0 (cdr delete-result))
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
            (if (= 0 (cdr prune-result))
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
  "Clean up stale timers, buffers, and state from aborted runs."
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
      (my/gptel--reset-agent-task-state)
      (gptel-auto-workflow--clear-runtime-subagent-provider-overrides)
      (gptel-mementum--reset-synthesis-state)
      (gptel-auto-experiment--reset-grade-state)
      (when gptel-auto-workflow--cron-job-timer
        (cancel-timer gptel-auto-workflow--cron-job-timer)
        (setq gptel-auto-workflow--cron-job-timer nil))
      (gptel-auto-workflow--stop-status-refresh-timer)
      (gptel-auto-workflow--cleanup-old-worktrees)
      (dolist (timer (copy-sequence timer-list))
        (when (timerp timer)
          (let* ((fn-rep (condition-case nil
                             (prin1-to-string (timer--function timer))
                           (error ""))))
            (when (and (stringp fn-rep)
                       (or (string-match-p "nucleus" fn-rep)
                           (string-match-p "gptel.*agent" fn-rep)
                           (string-match-p "auto-experiment" fn-rep)))
              (cancel-timer timer)
              (cl-incf cleaned)))))
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
                                  (or (plist-get gptel-auto-workflow--stats :phase)
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
  (let* ((run-id (gptel-auto-workflow--current-run-id))
         (callback-run-id (and gptel-auto-workflow--running
                               gptel-auto-workflow--run-id))
         (proj-root (gptel-auto-workflow--default-dir))
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
               (setq gptel-auto-workflow--running nil
                     gptel-auto-workflow--run-project-root nil
                     gptel-auto-workflow--current-target nil
                     gptel-auto-workflow--current-project nil)
               (setq gptel-auto-workflow--stats
                     (plist-put gptel-auto-workflow--stats :phase final-phase))
               (message "[auto-workflow] Complete: %d experiments, %d targets improved"
                        (length all-results) kept-count)
               (gptel-auto-workflow--persist-status)
               (when completion-callback
                 (funcall completion-callback all-results)))))))
    ;; Set project context for subagent routing
    (setq gptel-auto-workflow--current-project proj-root
          gptel-auto-workflow--run-project-root proj-root)
    (setq gptel-auto-workflow--stats
          (plist-put gptel-auto-workflow--stats :phase "running"))
    (setq gptel-auto-workflow--stats
          (plist-put gptel-auto-workflow--stats :total (length targets)))
    (setq gptel-auto-workflow--stats
          (plist-put gptel-auto-workflow--stats :kept 0))
    (gptel-auto-workflow--persist-status)
    (message "[auto-workflow] Starting %s with %d targets" run-id (length targets))
    (cl-labels
        ((finish-run ()
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
                           (gptel-auto-workflow--persist-status)
                           (if gptel-auto-experiment--quota-exhausted
                               (progn
                                 (message "[auto-workflow] Provider quota exhausted; stopping remaining targets")
                                 (finish-run))
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
                                 (run-next (cdr remaining-targets))))))))))
                 (gptel-auto-experiment-loop target target-complete))))))
      (if (buffer-live-p run-buffer)
          (with-current-buffer run-buffer
            (let ((default-directory proj-root)
                  (gptel-auto-workflow--project-root-override proj-root)
                  (gptel-auto-workflow--current-project proj-root)
                  (gptel-auto-workflow--run-project-root proj-root))
              (run-next targets)))
        (let ((default-directory proj-root)
              (gptel-auto-workflow--project-root-override proj-root)
              (gptel-auto-workflow--current-project proj-root)
              (gptel-auto-workflow--run-project-root proj-root))
          (run-next targets))))))

(defun gptel-auto-workflow-run (&optional targets)
  "Run auto-workflow asynchronously.
Non-blocking - returns immediately, check status with `gptel-auto-workflow-status'.
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
  "Get skill path for TARGET. TYPE is 'target or 'mutation."
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
         (content (when target-skill (plist-get target-skill :content))))
    (when (and content (string-match "^## Next Hypothesis\n\n\\(.+\\)" content))
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
                  (kept-deltas (mapcar (lambda (r) (or (gptel-auto-workflow--plist-get r :delta 0) 0)) kept-results))
                  (avg-delta (if (and kept-results kept-deltas)
                                 (/ (apply #'+ kept-deltas) (length kept-deltas))
                               0))
                  (best (car (sort kept-results (lambda (a b)
                                                  (> (or (gptel-auto-workflow--plist-get a :delta 0) 0)
                                                     (or (gptel-auto-workflow--plist-get b :delta 0) 0))))))
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

(provide 'gptel-tools-agent-main)
;;; gptel-tools-agent-main.el ends here
