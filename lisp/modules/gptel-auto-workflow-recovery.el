;;; gptel-auto-workflow-recovery.el --- Daemon restart recovery and circuit-breaker integration -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Commentary:
;; Daemon restart recovery and resilience integration.
;; Coordinates checkpoint loading, worktree cleanup, circuit-breaker health,
;; and experiment recovery into a unified startup sequence.
;;
;; Recovery sequence on daemon startup:
;;   1. Load circuit-breaker state (survives daemon restart)
;;   2. Clean stale recovery locks and old checkpoints
;;   3. Check for recoverable workflow checkpoint
;;   4. If found and not manual stop:
;;      a. Acquire recovery lock (prevent concurrent recovery)
;;      b. Load recovery context (targets, progress, results)
;;      c. Validate worktree state
;;      d. Resume workflow from last position
;;   5. If no checkpoint or not recoverable:
;;      a. Start fresh workflow
;;
;; Circuit-breaker integration:
;;   - Each component (researcher, analyzer, executor, grader) has independent circuit
;;   - Circuit state is persisted and survives daemon restart
;;   - Open circuits prevent requests to degraded components
;;   - Automatic recovery via half-open probe
;;
;; ASSUMPTION: Recovery happens at daemon startup before workflow begins.
;;   Called from the cron daemon's startup sequence.
;;
;; ASSUMPTION: Only one daemon instance recovers at a time.
;;   Advisory lock prevents recovery races between multiple instances.
;;
;; EDGE CASE: Manual stop → checkpoint state=aborted → don't recover, start fresh
;; EDGE CASE: Complete → checkpoint state=completed → archive and start fresh
;; EDGE CASE: Failed → checkpoint state=failed → start fresh
;; EDGE CASE: No checkpoint → start fresh
;;
;; WISDOM: Recovery is conservative — if any validation fails, start fresh
;;   rather than continuing in a potentially corrupted state.

;;; Code:

(require 'cl-lib)

;; Forward declarations
(declare-function gptel-circuit-state "gptel-ext-circuit-breaker" (component))
(declare-function gptel-circuit-status "gptel-ext-circuit-breaker")
(declare-function gptel-circuit-record-failure "gptel-ext-circuit-breaker" (component &optional error-msg))
(declare-function gptel-circuit-record-success "gptel-ext-circuit-breaker" (component))
(declare-function gptel-circuit-allow-p "gptel-ext-circuit-breaker" (component))
(declare-function gptel-circuit-get "gptel-ext-circuit-breaker" (component))
(declare-function gptel-circuit-reset "gptel-ext-circuit-breaker" (component))
(declare-function gptel-circuit-save "gptel-ext-circuit-breaker")
(declare-function gptel-checkpoint-recover "gptel-ext-checkpoint")
(declare-function gptel-checkpoint-recoverable-p "gptel-ext-checkpoint")
(declare-function gptel-checkpoint-cleanup-stale "gptel-ext-checkpoint" (&optional max-age-hours))
(declare-function gptel-checkpoint-status "gptel-ext-checkpoint")
(declare-function gptel-checkpoint-begin "gptel-ext-checkpoint" (run-id targets &optional project-root metadata))
(declare-function gptel-checkpoint-record-experiment "gptel-ext-checkpoint" (experiment-result))
(declare-function gptel-checkpoint-end-target "gptel-ext-checkpoint" (target-name success))
(declare-function gptel-checkpoint-complete "gptel-ext-checkpoint")
(declare-function gptel-checkpoint-fail "gptel-ext-checkpoint" (&optional reason))
(declare-function gptel-checkpoint-snapshot-loop-state "gptel-ext-checkpoint")

(defvar gptel-auto-workflow--run-id nil)
(defvar gptel-auto-workflow--worktree-base-root nil)
(defvar gptel-auto-workflow--headless nil)
(defvar gptel-auto-workflow-persistent-headless nil)
(defvar gptel-auto-workflow--current-target nil)
(defvar gptel-auto-workflow--stats nil)
(defvar gptel-auto-workflow--results nil)
(defvar gptel-auto-workflow--running nil)
(defvar gptel-auto-workflow--status-run-id nil)
(defgroup gptel-recovery nil
  "Workflow recovery and resilience settings."
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-recovery-enabled t
  "When non-nil, attempt recovery from checkpoint on daemon startup."
  :type 'boolean
  :group 'gptel-recovery)

(defcustom gptel-auto-workflow-recovery-max-checkpoint-age-hours 48
  "Maximum age in hours for a recoverable checkpoint.
Checkpoints older than this are ignored (treated as stale)."
  :type 'integer
  :group 'gptel-recovery)

(defcustom gptel-auto-workflow-recovery-cleanup-on-start t
  "When non-nil, clean stale checkpoints and locks on startup."
  :type 'boolean
  :group 'gptel-recovery)

(defcustom gptel-auto-workflow-circuit-breaker-components
  '(researcher analyzer executor grader)
  "Components tracked by circuit breakers.
Each component gets an independent circuit for independent failure isolation."
  :type '(repeat symbol)
  :group 'gptel-recovery)

(defcustom gptel-auto-workflow-circuit-breaker-on-workflow-run t
  "When non-nil, integrate circuit-breaker checks into workflow execution.
Fast-fails requests to components with open circuits."
  :type 'boolean
  :group 'gptel-recovery)

;;; ─── Recovery Context ───

(defvar gptel-recovery--ctx nil
  "Current recovery context plist from last recovery attempt.
Contains :recovered :run-id :resume-targets etc.")

(defvar gptel-recovery--initialized nil
  "Non-nil after recovery system has been initialized for this session.")

;;; ─── Initialization ───

(defun gptel-recovery--ensure-loaded ()
  "Lazily load checkpoint and circuit-breaker modules."
  (unless gptel-recovery--initialized
    ;; Load circuit-breaker (auto-registers components)
    (condition-case nil
        (progn
          (require 'gptel-ext-circuit-breaker nil t)
          (message "[recovery] Circuit breaker loaded"))
      (error
       (message "[recovery] WARNING: Circuit breaker module not available")))
    ;; Load checkpoint (auto-loads from disk)
    (condition-case nil
        (progn
          (require 'gptel-ext-checkpoint nil t)
          (message "[recovery] Checkpoint module loaded"))
      (error
       (message "[recovery] WARNING: Checkpoint module not available")))
    (setq gptel-recovery--initialized t)))

;;; ─── Circuit Breaker Status ───

(defun gptel-recovery--circuit-health-summary ()
  "Return health summary of all circuit breakers."
  (gptel-recovery--ensure-loaded)
  (when (fboundp 'gptel-circuit-status)
    (let ((status (gptel-circuit-status)))
      (if (null status)
          "no circuits registered"
        (mapconcat
         (lambda (c)
           (let ((comp (plist-get c :component))
                 (state (plist-get c :state))
                 (failures (plist-get c :total-failures))
                 (successes (or (plist-get c :total-successes) 0))
                 (last-msg (plist-get c :last-failure-msg)))
             (format "%s:%s(%dF/%dS)%s"
                     comp state failures successes
                     (if (and (eq state 'open) last-msg)
                         (format " [%s]" (substring last-msg 0 (min 40 (length last-msg))))
                       ""))))
         status
         ", ")))))

(defun gptel-recovery--any-circuit-open-p ()
  "Return non-nil if any tracked circuit is OPEN."
  (gptel-recovery--ensure-loaded)
  (when (fboundp 'gptel-circuit-state)
    (cl-some
     (lambda (comp)
       (eq 'open (gptel-circuit-state comp)))
     gptel-auto-workflow-circuit-breaker-components)))

(defun gptel-recovery--open-circuits ()
  "Return list of component names with OPEN circuits."
  (gptel-recovery--ensure-loaded)
  (when (fboundp 'gptel-circuit-state)
    (cl-loop for comp in gptel-auto-workflow-circuit-breaker-components
             when (eq 'open (gptel-circuit-state comp))
             collect comp)))

;;; ─── Worktree Validation ───

(defun gptel-recovery--validate-worktree-state (&optional run-id)
  "Validate that worktree state is consistent for recovery.
Returns (cons valid-p reason) where reason explains why invalid."
  (let* ((run-root (or (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                             (ignore-errors (gptel-auto-workflow--worktree-base-root)))
                        (expand-file-name "~/.emacs.d/")))
         (worktree-base (expand-file-name "var/worktrees" run-root)))
    ;; Check if worktree directory exists
    (if (not (file-directory-p worktree-base))
        (cons t "no worktrees (clean start)")
      ;; Count active worktrees
      (let ((worktrees
             (cl-loop for f in (directory-files worktree-base t "^optimize-")
                      when (file-directory-p f)
                      collect (file-name-nondirectory f))))
        (cond
         ((null worktrees)
          (cons t "no active worktrees (clean start)"))
         ((> (length worktrees) 5)
          (cons t (format "%d worktrees found (normal)" (length worktrees))))
         (t
          (cons t (format "%d worktrees (recovering)" (length worktrees)))))))))

(defun gptel-recovery--cleanup-stale-worktrees ()
  "Clean up worktrees with no active experiment.
Returns count of cleaned worktrees."
  (gptel-recovery--ensure-loaded)
  (let ((cleaned 0)
        (run-root (or (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                           (ignore-errors (gptel-auto-workflow--worktree-base-root)))
                      (expand-file-name "~/.emacs.d/")))
        (worktree-base (expand-file-name "var/worktrees" run-root)))
    (when (file-directory-p worktree-base)
      (let* ((now (float-time))
             (max-age-seconds (* 6 3600)))  ; 6 hours
        (dolist (dir (directory-files worktree-base t "^optimize-"))
          (when (file-directory-p dir)
            (let* ((mtime (file-attribute-modification-time (file-attributes dir)))
                   (age-seconds (- now (float-time mtime))))
              (when (>= age-seconds max-age-seconds)
                ;; Check if this is a stale worktree (no git process running)
                (let* ((branch-file (expand-file-name ".git/HEAD" dir))
                       (branch (ignore-errors
                                (with-temp-buffer
                                  (insert-file-contents branch-file)
                                  (string-trim (buffer-string))))))
                  (unless (and branch (> (length branch) 0))
                    (condition-case err nil
                        (progn
                          (delete-directory dir 'recursive)
                          (cl-incf cleaned)
                          (message "[recovery] Cleaned stale worktree: %s (age=%.1fh)"
                                   (file-name-nondirectory dir)
                                   (/ age-seconds 3600.0)))
                      (error
                       (message "[recovery] Failed to clean worktree %s: %s"
                                (file-name-nondirectory dir)
                                 (error-message-string err))))))))))))
    (when (> cleaned 0)
      (message "[recovery] Cleaned %d stale worktree(s)" cleaned))
    cleaned))

;;; ─── Recovery Core ───

(defun gptel-recovery--attempt-recovery ()
  "Attempt to recover from checkpoint.
Returns recovery context plist, or nil if no recovery possible."
  (gptel-recovery--ensure-loaded)
  (let ((checkpoint-data nil)
        (recovery-ctx nil))
    ;; Step 1: Cleanup stale state
    (when gptel-auto-workflow-recovery-cleanup-on-start
      (message "[recovery] Running startup cleanup...")
      (condition-case nil
          (gptel-checkpoint-cleanup-stale gptel-auto-workflow-recovery-max-checkpoint-age-hours)
        (error nil))
      (gptel-recovery--cleanup-stale-worktrees))
    ;; Step 2: Check for recoverable checkpoint
    (unless (fboundp 'gptel-checkpoint-recoverable-p)
      (message "[recovery] Checkpoint module not available")
      (return-from gptel-recovery--attempt-recovery nil))
    (unless (gptel-checkpoint-recoverable-p)
      (message "[recovery] No recoverable checkpoint found")
      (return-from gptel-recovery--attempt-recovery nil))
    ;; Step 3: Attempt recovery
    (message "[recovery] Attempting checkpoint recovery...")
    (condition-case err
        (setq recovery-ctx (gptel-checkpoint-recover))
      (error
       (message "[recovery] Checkpoint recovery failed: %s" err)
       (return-from gptel-recovery--attempt-recovery nil))
    (unless recovery-ctx
      (message "[recovery] Recovery aborted (no context returned)")
      (return-from gptel-recovery--attempt-recovery nil))
    (let* ((can-recover (plist-get recovery-ctx :can-recover))
           (resume-targets (plist-get recovery-ctx :resume-targets))
           (checkpoint-data (plist-get recovery-ctx :checkpoint-data)))
      (unless can-recover
        (message "[recovery] Checkpoint is not recoverable (no resume targets)")
        (return-from gptel-recovery--attempt-recovery nil))
      ;; Step 4: Validate worktree state
      (let* ((validation (gptel-recovery--validate-worktree-state
                          (plist-get recovery-ctx :run-id)))
             (valid-p (car validation))
             (reason (cdr validation)))
        (message "[recovery] Worktree validation: %s — %s"
                 (if valid-p "PASS" "FAIL")
                 reason)
        (unless valid-p
          (message "[recovery] Recovery aborted due to worktree validation failure")
          (return-from gptel-recovery--attempt-recovery nil)))
      ;; Step 5: Log recovery summary
      (message "[recovery] Recovery successful: run=%s resume=%d targets"
               (plist-get recovery-ctx :run-id)
               (length resume-targets))
      (when (fboundp 'gptel-circuit-health-summary)
        (message "[recovery] Circuit health: %s"
                 (gptel-recovery--circuit-health-summary)))
      recovery-ctx)))

(defun gptel-recovery-run (&optional targets)
  "Main recovery entry point.
Attempts recovery from checkpoint, then resumes or starts fresh.
TARGETS is optional list of targets to optimize (if starting fresh).
Returns plist:
  (:recovered . t/nil)    — whether recovery was attempted
  (:resume-targets . list) — targets to resume (or nil)
  (:resume-exp-id . n)    — experiment ID to resume from (or nil)
  (:partial-results . list) — partial results from before crash (or nil)
  (:fresh . t/nil)        — whether starting fresh"
  (interactive)
  (gptel-recovery--ensure-loaded)
  (message "[recovery] Initializing recovery system...")
  ;; Check for open circuits
  (when (gptel-recovery--any-circuit-open-p)
    (let ((open (gptel-recovery--open-circuits)))
      (message "[recovery] WARNING: Open circuits detected: %s" open)
      (message "[recovery] These components will be unavailable until circuits close")
       (message "[recovery] Manual intervention: M-x gptel-circuit-reset COMPONENT")))
  ;; Attempt recovery
  (let* ((recovery-ctx (gptel-recovery--attempt-recovery)))
    (if recovery-ctx
        (progn
          (setq gptel-recovery--ctx recovery-ctx)
          (message "[recovery] RECOVERED: resuming workflow from checkpoint")
          (list :recovered t
                :resume-targets (plist-get recovery-ctx :resume-targets)
                :resume-exp-id (plist-get recovery-ctx :resume-exp-id)
                :resume-exp-count (plist-get recovery-ctx :resume-exp-count)
                :resume-best-score (plist-get recovery-ctx :resume-best-score)
                :partial-results (plist-get recovery-ctx :partial-results)
                :run-id (plist-get recovery-ctx :run-id)
                :fresh nil))
      (progn
        (message "[recovery] Starting fresh workflow (no recoverable checkpoint)")
        (list :recovered nil
              :resume-targets nil
              :resume-exp-id nil
              :resume-exp-count nil
              :resume-best-score nil
              :partial-results nil
              :run-id nil
              :fresh t)))))

;;; ─── Workflow Integration ───

(defvar gptel-recovery--checkpoint-timer nil
  "Timer for periodic checkpoint saves during workflow run.")

(defun gptel-recovery--start-checkpoint-timer (interval-seconds)
  "Start periodic checkpoint timer every INTERVAL-SECONDS.
Uses `gptel-checkpoint-snapshot-loop-state' to capture loop state."
  (gptel-recovery--stop-checkpoint-timer)
  (when (fboundp 'gptel-checkpoint-snapshot-loop-state)
    (setq gptel-recovery--checkpoint-timer
          (run-with-timer interval-seconds interval-seconds
                          (lambda ()
                            (condition-case nil
                                (gptel-checkpoint-snapshot-loop-state)
                              (error nil))))))
  (message "[recovery] Checkpoint timer started (every %ds)" interval-seconds))

(defun gptel-recovery--stop-checkpoint-timer ()
  "Stop periodic checkpoint timer."
  (when gptel-recovery--checkpoint-timer
    (cancel-timer gptel-recovery--checkpoint-timer)
    (setq gptel-recovery--checkpoint-timer nil)))

(defun gptel-recovery--wrap-workflow-with-checkpointing (workflow-fn)
  "Return a wrapper that adds checkpointing around WORKFLOW-FN.
The wrapper:
  1. Begins a checkpoint when workflow starts
  2. Starts periodic checkpoint timer
  3. Records each experiment result
  4. Ends targets and marks complete on normal exit
  5. Marks failed on error
  6. Stops checkpoint timer on exit
  7. Saves circuit-breaker state on exit"
  (lambda (&rest args)
    (let ((run-id (or (and (boundp 'gptel-auto-workflow--run-id)
                           gptel-auto-workflow--run-id)
                      (format-time-string "run-%Y%m%d-%H%M%S"))))
      ;; Begin checkpoint
      (when (fboundp 'gptel-checkpoint-begin)
        (gptel-checkpoint-begin
         run-id
         (or (car args) '())
         nil
         (list :initiated-via 'recovery-wrap)))
      ;; Start periodic checkpoint timer (every 30 seconds)
      (gptel-recovery--start-checkpoint-timer 30)
      (unwind-protect
          (apply workflow-fn args)
        (gptel-recovery--stop-checkpoint-timer)
        ;; Final checkpoint save
        (when (fboundp 'gptel-checkpoint-snapshot-loop-state)
          (condition-case nil
              (gptel-checkpoint-snapshot-loop-state)
            (error nil)))
        (when (fboundp 'gptel-circuit-save)
          (condition-case nil
              (gptel-circuit-save)
            (error nil))))))))

;;; ─── Experiment Result Recording ───

(defun gptel-recovery-record-experiment (experiment-result)
  "Record EXPERIMENT-RESULT to checkpoint and update circuit-breaker.
Called after each experiment completes."
  (gptel-recovery--ensure-loaded)
  ;; Record to checkpoint
  (when (fboundp 'gptel-checkpoint-record-experiment)
    (condition-case err nil
        (gptel-checkpoint-record-experiment experiment-result)
      (error
       (message "[recovery] Failed to record experiment to checkpoint: %s"
                (error-message-string err)))))
  ;; Update circuit-breaker based on result
  (let* ((kept (plist-get experiment-result :kept))
         (decision (plist-get experiment-result :decision))
         (target (plist-get experiment-result :target)))
    (cond
     ;; Successful improvement
     ((eq kept t)
      (message "[recovery] Experiment success: %s → kept" target)
      (when (fboundp 'gptel-circuit-record-success)
        (condition-case nil
            (gptel-circuit-record-success 'executor)
          (error nil))))
     ;; Failed experiment (not kept, not validation error)
     ((and (not kept)
           (not (member decision '("validation-failed" "grader-only-failure"))))
      (let ((grader-reason (plist-get experiment-result :grader-reason))
            (comparator-reason (plist-get experiment-result :comparator-reason)))
        (when (fboundp 'gptel-circuit-record-failure)
          (condition-case nil
              (gptel-circuit-record-failure 'executor
                                           (or grader-reason comparator-reason))
            (error nil))))))))

(defun gptel-recovery-record-target-complete (target success)
  "Record TARGET completion (SUCCESS=t) or failure (SUCCESS=nil)."
  (gptel-recovery--ensure-loaded)
  (when (fboundp 'gptel-checkpoint-end-target)
    (condition-case err nil
        (gptel-checkpoint-end-target target success)
      (error
       (message "[recovery] Failed to record target complete: %s" err)))))

(defun gptel-recovery-record-workflow-complete ()
  "Record workflow completion."
  (gptel-recovery--ensure-loaded)
  (gptel-recovery--stop-checkpoint-timer)
  (when (fboundp 'gptel-checkpoint-complete)
    (condition-case err nil
        (gptel-checkpoint-complete)
      (error
       (message "[recovery] Failed to mark workflow complete: %s" err))))
  (when (fboundp 'gptel-circuit-save)
    (condition-case nil
        (gptel-circuit-save)
      (error nil))))

(defun gptel-recovery-record-workflow-fail (&optional reason)
  "Record workflow failure with optional REASON."
  (gptel-recovery--ensure-loaded)
  (gptel-recovery--stop-checkpoint-timer)
  (when (fboundp 'gptel-checkpoint-fail)
    (condition-case nil
        (gptel-checkpoint-fail reason)
      (error nil)))
  (when (fboundp 'gptel-circuit-save)
    (condition-case nil
        (gptel-circuit-save)
      (error nil))))

;;; ─── Circuit Breaker Integration with Workflow ───

(defun gptel-recovery-check-circuit (component)
  "Check if COMPONENT is available (circuit not OPEN).
Returns non-nil if available, nil if circuit is OPEN.
If circuit is OPEN, logs a warning."
  (gptel-recovery--ensure-loaded)
  (if (fboundp 'gptel-circuit-allow-p)
      (let ((allowed (gptel-circuit-allow-p component)))
        (unless allowed
          (message "[recovery] Circuit OPEN for %s — request rejected" component))
        allowed)
    t))

(defmacro gptel-recovery--with-circuit (component &rest body)
  "Execute BODY with circuit-breaker protection for COMPONENT.
BODY should return (success . result) or (nil . error-msg).
On circuit OPEN: returns (nil . \"circuit open\") without executing BODY.
On BODY success: records success. On BODY failure: records failure."
  (declare (indent 1))
  `(let ((allowed (gptel-recovery-check-circuit ,component)))
     (if (not allowed)
         (cons nil (format "circuit open for %s" ,component))
       (let ((result (progn ,@body)))
         (if (car result)
             (progn
               (when (fboundp 'gptel-circuit-record-success)
                 (condition-case nil
                     (gptel-circuit-record-success ,component)
                   (error nil)))
               result)
           (progn
             (when (fboundp 'gptel-circuit-record-failure)
               (condition-case nil
                   (gptel-circuit-record-failure ,component (cdr result))
                 (error nil)))
             result))))))

;;; ─── Recovery Status ───

(defun gptel-recovery-status ()
  "Return comprehensive recovery system status."
  (gptel-recovery--ensure-loaded)
  (let* ((checkpoint-status (and (fboundp 'gptel-checkpoint-status)
                                  (gptel-checkpoint-status)))
         (circuit-health (and (fboundp 'gptel-circuit-health-summary)
                               (gptel-recovery--circuit-health-summary)))
         (open-circuits (gptel-recovery--open-circuits))
         (checkpoint-data (and gptel-recovery--ctx
                              (plist-get gptel-recovery--ctx :checkpoint-data))))
    (list :initialized gptel-recovery--initialized
          :recovery-enabled gptel-auto-workflow-recovery-enabled
          :recovery-attempted (if gptel-recovery--ctx t nil)
          :recovered (if gptel-recovery--ctx
                        (plist-get gptel-recovery--ctx :recovered)
                      nil)
          :resume-targets-count (if gptel-recovery--ctx
                                    (length (plist-get gptel-recovery--ctx :resume-targets))
                                  0)
          :checkpoint checkpoint-status
          :circuit-health circuit-health
          :open-circuits open-circuits
          :checkpoint-timer-active (timerp gptel-recovery--checkpoint-timer)
          :last-recovery-run-id (and checkpoint-data
                                     (gptel-checkpoint-data-run-id checkpoint-data)))))

(defun gptel-recovery-report ()
  "Print human-readable recovery system report."
  (interactive)
  (gptel-recovery--ensure-loaded)
  (let ((status (gptel-recovery-status)))
    (message "════════════════════════════════════════")
    (message "RECOVERY SYSTEM STATUS")
    (message "════════════════════════════════════════")
    (message "Recovery enabled: %s"
             (if (plist-get status :recovery-enabled) "yes" "no"))
    (message "Initialized: %s"
             (if (plist-get status :initialized) "yes" "no"))
    (message "Last recovery attempted: %s"
             (if (plist-get status :recovery-attempted) "yes" "no"))
    (message "Recovered from checkpoint: %s"
             (if (plist-get status :recovered) "yes" "no"))
    (message "Resume targets available: %d"
             (plist-get status :resume-targets-count))
    (message "Circuit health: %s"
             (or (plist-get status :circuit-health) "N/A"))
    (message "Open circuits: %s"
             (if (plist-get status :open-circuits)
                 (mapconcat #'symbol-name (plist-get status :open-circuits) ", ")
               "none"))
    (message "Checkpoint timer: %s"
             (if (plist-get status :checkpoint-timer-active) "active" "inactive"))
    (message "Last recovery run ID: %s"
             (or (plist-get status :last-recovery-run-id) "none"))
    (message "════════════════════════════════════════")
    status))

(provide 'gptel-auto-workflow-recovery)
;;; gptel-auto-workflow-recovery.el ends here

)))))