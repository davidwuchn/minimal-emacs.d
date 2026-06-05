;;; gptel-ext-checkpoint.el --- Workflow state persistence and recovery -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Commentary:
;; Checkpoint system for workflow state persistence across daemon restarts.
;;
;; State machine:
;;   PENDING     → Initial state; not yet started
;;   RUNNING     → Experiment in progress; may have partial results
;;   CHECKPOINTED→ Periodic save during RUNNING; recoverable
;;   RECOVERED   → Loaded from checkpoint on startup
;;   COMPLETED   → Normal finish
;;   FAILED      → Hard failure; not recoverable
;;   ABORTED     → Manual stop; not recoverable
;;
;; Checkpoint data:
;;   - Workflow metadata (run-id, targets, current-target, progress)
;;   - Partial experiment results (experiments that completed before crash)
;;   - Experiment loop state (no-improvement-count, best-score, exp-id)
;;   - Circuit breaker state (tracked separately but checkpointed together)
;;   - Timestamp of last checkpoint
;;
;; ASSUMPTION: Checkpoints are saved periodically (every N experiments or
;;   every N seconds) and loaded on daemon startup.
;;
;; ASSUMPTION: Only COMPLETED experiments are considered valid results.
;;   RUNNING/CHECKPOINTED experiments are re-run from scratch.
;;
;; WISDOM: Saving checkpoint after each experiment balances crash recovery
;;   coverage against disk I/O overhead. Daemon restarts mid-experiment
;;   lose at most 1 experiment's worth of work.
;;
;; EDGE CASE: Multiple concurrent daemon restarts → only one should
;;   recover. Use advisory lock file. Others start fresh.

;;; Code:

(require 'cl-lib)
(require 'json)

;; Forward declarations
(declare-function gptel-circuit-state "gptel-ext-circuit-breaker" (component))
(declare-function gptel-circuit-status "gptel-ext-circuit-breaker")
(declare-function gptel-circuit--save-persistent "gptel-ext-circuit-breaker")

(defgroup gptel-checkpoint nil
  "Workflow state persistence and recovery."
  :group 'gptel)

;;; ─── State Machine ───

(defconst gptel-checkpoint--states '(pending running checkpointed recovered completed failed aborted)
  "Valid workflow checkpoint states.")

(defun gptel-checkpoint--valid-state-p (state)
  "Return non-nil if STATE is a valid checkpoint state."
  (memq state gptel-checkpoint--states))

;;; ─── Paths ───

(defun gptel-checkpoint--base-dir ()
  "Return checkpoint base directory."
  (expand-file-name "var/tmp/checkpoints"
                    (or (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                             (ignore-errors (gptel-auto-workflow--worktree-base-root)))
                        user-emacs-directory)))

(defun gptel-checkpoint--active-path ()
  "Return path to active checkpoint file."
  (expand-file-name "active.ckpt" (gptel-checkpoint--base-dir)))

(defun gptel-checkpoint--lock-path ()
  "Return path to recovery lock file (advisory lock for recovery race).".
  (expand-file-name "recovery.lock" (gptel-checkpoint--base-dir)))

(defun gptel-checkpoint--history-dir ()
  "Return checkpoint history directory (completed checkpoints)."
  (expand-file-name "history" (gptel-checkpoint--base-dir)))

(defun gptel-checkpoint--experiments-dir ()
  "Return directory for per-experiment partial results."
  (expand-file-name "experiments" (gptel-checkpoint--base-dir)))

;;; ─── Checkpoint Data Structure ───

(cl-defstruct (gptel-checkpoint-data
                (:constructor gptel-checkpoint-data-create))
  version              ; format version (integer)
  state                ; workflow state symbol
  run-id               ; unique run identifier
  project-root         ; project root path
  targets              ; list of target file paths
  current-target       ; target currently being processed
  targets-done         ; list of completed target names
  targets-failed       ; list of failed target names
  current-exp-id       ; experiment ID within current target
  current-exp-count    ; total experiments run for current target
  current-best-score   ; best score for current target
  no-improvement-count ; no-improvement counter
  results              ; list of completed experiment results (plist)
  total-experiments    ; total experiments across all targets
  started-at           ; ISO timestamp
  checkpoint-at        ; ISO timestamp
  last-target-at      ; ISO timestamp of last target transition
  experiment-loop-snapshot ; plist of experiment loop variables
  metadata             ; arbitrary extra metadata plist
  )

(defun gptel-checkpoint--current-version () 1)

;;; ─── Serialization ───

(defun gptel-checkpoint--serialize (data)
  "Serialize checkpoint DATA to JSON string."
  (let ((plist
         (list :version (gptel-checkpoint-data-version data)
               :state (symbol-name (gptel-checkpoint-data-state data))
               :run-id (gptel-checkpoint-data-run-id data)
               :project-root (gptel-checkpoint-data-project-root data)
               :targets (gptel-checkpoint-data-targets data)
               :current-target (gptel-checkpoint-data-current-target data)
               :targets-done (gptel-checkpoint-data-targets-done data)
               :targets-failed (gptel-checkpoint-data-targets-failed data)
               :current-exp-id (gptel-checkpoint-data-current-exp-id data)
               :current-exp-count (gptel-checkpoint-data-current-exp-count data)
               :current-best-score (or (gptel-checkpoint-data-current-best-score data) 0.0)
               :no-improvement-count (gptel-checkpoint-data-no-improvement-count data)
               :results (mapcar #'gptel-checkpoint--serialize-result
                               (gptel-checkpoint-data-results data))
               :total-experiments (gptel-checkpoint-data-total-experiments data)
               :started-at (gptel-checkpoint-data-started-at data)
               :checkpoint-at (gptel-checkpoint-data-checkpoint-at data)
               :last-target-at (gptel-checkpoint-data-last-target-at data)
               :experiment-loop-snapshot (gptel-checkpoint-data-experiment-loop-snapshot data)
               :metadata (gptel-checkpoint-data-metadata data))))
    (json-encode plist)))

(defun gptel-checkpoint--serialize-result (result)
  "Serialize a single experiment RESULT plist to alist for JSON."
  (let ((fields '(:id :target :target-type :score-before :score-after :kept
                  :decision :grader-reason :comparator-reason :hypothesis
                  :research-hash :timestamp :duration :code-quality
                  :staging-branch :staging-status)))
    (cl-loop for field in fields
             for val = (plist-get result field)
             when val
              collect (cons (substring (symbol-name field) 1) val))))

(defun gptel-checkpoint--deserialize (json-string)
  "Deserialize JSON-STRING to checkpoint-data struct."
  (let* ((json-object-type 'plist)
         (json-array-type 'list)
         (json-key-type 'keyword)
         (plist (json-read-from-string json-string)))
    (gptel-checkpoint-data-create
     :version (or (plist-get plist :version) 1)
     :state (intern (or (plist-get plist :state) "pending"))
     :run-id (plist-get plist :run-id)
     :project-root (plist-get plist :project-root)
     :targets (plist-get plist :targets)
     :current-target (plist-get plist :current-target)
     :targets-done (plist-get plist :targets-done)
     :targets-failed (plist-get plist :targets-failed)
     :current-exp-id (or (plist-get plist :current-exp-id) 1)
     :current-exp-count (or (plist-get plist :current-exp-count) 0)
     :current-best-score (or (plist-get plist :current-best-score) 0.0)
     :no-improvement-count (or (plist-get plist :no-improvement-count) 0)
     :results (mapcar #'gptel-checkpoint--deserialize-result
                      (or (plist-get plist :results) []))
     :total-experiments (or (plist-get plist :total-experiments) 0)
     :started-at (plist-get plist :started-at)
     :checkpoint-at (plist-get plist :checkpoint-at)
     :last-target-at (plist-get plist :last-target-at)
     :experiment-loop-snapshot (plist-get plist :experiment-loop-snapshot)
     :metadata (plist-get plist :metadata))))

(defun gptel-checkpoint--deserialize-result (alist)
  "Deserialize result alist to plist."
  (cl-loop for (key . val) in alist
           collect (intern (concat ":" key)) into result
           and when val
           collect val into result
           finally return result))

;;; ─── Recovery Lock (Advisory) ───

(defun gptel-checkpoint--acquire-lock ()
  "Acquire advisory recovery lock.
Returns non-nil if lock acquired. Prevents multiple daemons from
concurrently recovering the same checkpoint."
  (let ((lock-path (gptel-checkpoint--lock-path))
        (pid (number-to-string (emacs-pid))))
    (make-directory (file-name-directory lock-path) t)
    (condition-case nil
        (progn
          (with-temp-file lock-path
            (insert pid "\n"))
          ;; Verify we still own the lock (another process didn't race)
          (let ((owner (ignore-errors
                         (with-temp-buffer
                           (insert-file-contents lock-path)
                           (string-trim (buffer-string))))))
            (string= owner pid)))
      (error nil))))

(defun gptel-checkpoint--release-lock ()
  "Release advisory recovery lock."
  (let ((lock-path (gptel-checkpoint--lock-path)))
    (when (file-exists-p lock-path)
      (delete-file lock-path))))

(defun gptel-checkpoint--stale-lock-p ()
  "Return non-nil if recovery lock is stale (old process died)."
  (let ((lock-path (gptel-checkpoint--lock-path)))
    (when (file-exists-p lock-path)
      (let* ((mtime (file-attribute-modification-time
                     (file-attributes lock-path)))
             (age-seconds (- (float-time) (float-time mtime))))
        (or (>= age-seconds 300)   ; lock older than 5 minutes
            (let ((owner (ignore-errors
                          (with-temp-buffer
                            (insert-file-contents lock-path)
                            (string-trim (buffer-string)))))
                  (self-pid (number-to-string (emacs-pid))))
              (and owner (not (string= owner self-pid))
                   (not (and (fboundp 'list-system-processes)
                             (member owner (list-system-processes))))))))))

;;; ─── Active Checkpoint ───

(defvar gptel-checkpoint--current nil
  "Current checkpoint data struct, or nil if none active.")

(defvar gptel-checkpoint--dirty nil
  "Non-nil when checkpoint needs saving (changes since last save).")

(defun gptel-checkpoint--mark-dirty ()
  "Mark checkpoint as needing save."
  (setq gptel-checkpoint--dirty t))

(defun gptel-checkpoint--active ()
  "Return current active checkpoint, or nil."
  gptel-checkpoint--current)

(defun gptel-checkpoint--save ()
  "Save current checkpoint to disk if dirty.
Returns non-nil if saved."
  (when (and gptel-checkpoint--dirty gptel-checkpoint--current)
    (let* ((base-dir (gptel-checkpoint--base-dir))
           (active-path (gptel-checkpoint--active-path))
           (tmp-path (concat active-path ".tmp"))
           (timestamp (format-time-string "%Y-%m-%dT%H:%M:%SZ")))
      (setf (gptel-checkpoint-data-checkpoint-at gptel-checkpoint--current)
            timestamp)
      (make-directory base-dir t)
      (condition-case err
          (let ((json (gptel-checkpoint--serialize gptel-checkpoint--current)))
            (with-temp-file tmp-path
              (insert json))
            (rename-file tmp-path active-path 'ok-if-exists)
            (setq gptel-checkpoint--dirty nil)
            (message "[checkpoint] Saved: %s (%d results, target=%s, exp=%d)"
                     (gptel-checkpoint-data-run-id gptel-checkpoint--current)
                     (length (gptel-checkpoint-data-results gptel-checkpoint--current))
                     (or (gptel-checkpoint-data-current-target gptel-checkpoint--current) "none")
                     (gptel-checkpoint-data-current-exp-id gptel-checkpoint--current))
            t)
        (error
         (message "[checkpoint] Save failed: %s" err)
         nil)))))

(defun gptel-checkpoint--load ()
  "Load active checkpoint from disk.
Returns checkpoint-data struct or nil if none exists."
  (let ((active-path (gptel-checkpoint--active-path)))
    (when (file-exists-p active-path)
      (condition-case err
          (with-temp-buffer
            (insert-file-contents active-path)
            (let ((data (gptel-checkpoint--deserialize (buffer-string))))
              (message "[checkpoint] Loaded checkpoint: run=%s state=%s targets=%d results=%d"
                       (gptel-checkpoint-data-run-id data)
                       (gptel-checkpoint-data-state data)
                       (length (gptel-checkpoint-data-targets data))
                       (length (gptel-checkpoint-data-results data)))
              data))
        (error
         (message "[checkpoint] Load failed: %s" err)
         nil)))))

(defun gptel-checkpoint--archive (run-id)
  "Archive current checkpoint to history."
  (let* ((active-path (gptel-checkpoint--active-path))
         (history-dir (gptel-checkpoint--history-dir))
         (archived-path (expand-file-name
                        (format "%s.ckpt" run-id)
                        history-dir)))
    (when (file-exists-p active-path)
      (make-directory history-dir t)
      (rename-file active-path archived-path 'ok-if-exists)
      (message "[checkpoint] Archived checkpoint: %s" run-id))))

;;; ─── Checkpoint Lifecycle ───

(defun gptel-checkpoint-begin (run-id targets &optional project-root metadata)
  "Begin a new workflow checkpoint for RUN-ID with TARGETS.
PROJECT-ROOT defaults to workflow base root.
METADATA is an optional plist of extra data.
Returns the new checkpoint-data struct."
  (gptel-checkpoint--save)  ; save any previous checkpoint first
  (let* ((base-dir (gptel-checkpoint--base-dir))
         (proj-root (or project-root
                       (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                            (ignore-errors (gptel-auto-workflow--worktree-base-root)))
                       user-emacs-directory))
         (data (gptel-checkpoint-data-create
                :version (gptel-checkpoint--current-version)
                :state 'running
                :run-id run-id
                :project-root proj-root
                :targets targets
                :current-target nil
                :targets-done nil
                :targets-failed nil
                :current-exp-id 1
                :current-exp-count 0
                :current-best-score 0.0
                :no-improvement-count 0
                :results nil
                :total-experiments 0
                :started-at (format-time-string "%Y-%m-%dT%H:%M:%SZ")
                :checkpoint-at (format-time-string "%Y-%m-%dT%H:%M:%SZ")
                :last-target-at nil
                :experiment-loop-snapshot nil
                :metadata metadata)))
    (setq gptel-checkpoint--current data)
    (setq gptel-checkpoint--dirty t)
    (gptel-checkpoint--save)
    (message "[checkpoint] Beginning workflow run: %s (%d targets)"
             run-id (length targets))
    data))

(defun gptel-checkpoint-begin-target (target-name)
  "Mark start of processing TARGET-NAME in current workflow."
  (when gptel-checkpoint--current
    (setf (gptel-checkpoint-data-current-target gptel-checkpoint--current) target-name
          (gptel-checkpoint-data-last-target-at gptel-checkpoint--current)
          (format-time-string "%Y-%m-%dT%H:%M:%SZ")
          (gptel-checkpoint-data-current-exp-id gptel-checkpoint--current) 1
          (gptel-checkpoint-data-current-exp-count gptel-checkpoint--current) 0
          (gptel-checkpoint-data-current-best-score gptel-checkpoint--current) 0.0
          (gptel-checkpoint-data-no-improvement-count gptel-checkpoint--current) 0
          (gptel-checkpoint-data-state gptel-checkpoint--current) 'running)
    (gptel-checkpoint--mark-dirty)
    (gptel-checkpoint--save)
    (message "[checkpoint] Beginning target: %s" target-name)))

(defun gptel-checkpoint-record-experiment (experiment-result)
  "Record completed EXPERIMENT-RESULT in checkpoint.
EXPERIMENT-RESULT is a plist with :id :target :kept etc."
  (when gptel-checkpoint--current
    (push experiment-result (gptel-checkpoint-data-results gptel-checkpoint--current))
    (cl-incf (gptel-checkpoint-data-current-exp-count gptel-checkpoint--current))
    (cl-incf (gptel-checkpoint-data-total-experiments gptel-checkpoint--current))
    (let ((score (plist-get experiment-result :score-after))
          (kept (plist-get experiment-result :kept)))
      (when (and score (numberp score))
        (when (> score (gptel-checkpoint-data-current-best-score gptel-checkpoint--current))
          (setf (gptel-checkpoint-data-current-best-score gptel-checkpoint--current)
                score)))
      (when kept
        (setf (gptel-checkpoint-data-no-improvement-count gptel-checkpoint--current) 0))
      (unless kept
        (cl-incf (gptel-checkpoint-data-no-improvement-count
                  gptel-checkpoint--current))))
    (setf (gptel-checkpoint-data-state gptel-checkpoint--current) 'checkpointed)
    (gptel-checkpoint--mark-dirty)
    (gptel-checkpoint--save)))

(defun gptel-checkpoint-end-target (target-name success)
  "Mark TARGET-NAME as complete (SUCCESS=t) or failed (SUCCESS=nil)."
  (when gptel-checkpoint--current
    (if success
        (push target-name (gptel-checkpoint-data-targets-done gptel-checkpoint--current))
      (push target-name (gptel-checkpoint-data-targets-failed gptel-checkpoint--current)))
    (setf (gptel-checkpoint-data-current-target gptel-checkpoint--current) nil
          (gptel-checkpoint-data-state gptel-checkpoint--current) 'checkpointed)
    (gptel-checkpoint--mark-dirty)
    (gptel-checkpoint--save)
    (message "[checkpoint] Target %s %s" target-name (if success "COMPLETED" "FAILED"))))

(defun gptel-checkpoint-complete ()
  "Mark current workflow as complete and archive checkpoint."
  (when gptel-checkpoint--current
    (setf (gptel-checkpoint-data-state gptel-checkpoint--current) 'completed)
    (gptel-checkpoint--save)
    (let ((run-id (gptel-checkpoint-data-run-id gptel-checkpoint--current)))
      (gptel-checkpoint--archive run-id))
    (message "[checkpoint] Workflow COMPLETED: %s (%d experiments)"
             (gptel-checkpoint-data-run-id gptel-checkpoint--current)
             (gptel-checkpoint-data-total-experiments gptel-checkpoint--current))
    (setq gptel-checkpoint--current nil)
    (setq gptel-checkpoint--dirty nil)))

(defun gptel-checkpoint-fail (&optional reason)
  "Mark current workflow as failed with optional REASON."
  (when gptel-checkpoint--current
    (setf (gptel-checkpoint-data-state gptel-checkpoint--current) 'failed
          (gptel-checkpoint-data-metadata gptel-checkpoint--current)
          (plist-put (gptel-checkpoint-data-metadata gptel-checkpoint--current)
                     :failure-reason (or reason "unknown")))
    (gptel-checkpoint--save)
    (message "[checkpoint] Workflow FAILED: %s — %s"
             (gptel-checkpoint-data-run-id gptel-checkpoint--current)
             (or reason "unknown"))
    (setq gptel-checkpoint--current nil)
    (setq gptel-checkpoint--dirty nil)))

(defun gptel-checkpoint-abort ()
  "Abort current workflow (manual stop — not recoverable)."
  (when gptel-checkpoint--current
    (setf (gptel-checkpoint-data-state gptel-checkpoint--current) 'aborted)
    (gptel-checkpoint--save)
    (message "[checkpoint] Workflow ABORTED: %s"
             (gptel-checkpoint-data-run-id gptel-checkpoint--current))
    (let ((run-id (gptel-checkpoint-data-run-id gptel-checkpoint--current)))
      (gptel-checkpoint--archive run-id))
    (setq gptel-checkpoint--current nil)
    (setq gptel-checkpoint--dirty nil)))

;;; ─── Recovery ───

(defun gptel-checkpoint-recoverable-p ()
  "Return non-nil if a recoverable checkpoint exists on disk.
Checks for active checkpoint with RUNNING or CHECKPOINTED state."
  (let ((data (gptel-checkpoint--load)))
    (and data
         (memq (gptel-checkpoint-data-state data)
               '(running checkpointed recovered))
         (gptel-checkpoint-data-run-id data)
         (gptel-checkpoint-data-targets data))))

(defun gptel-checkpoint-recover ()
  "Recover from checkpoint on disk.
Returns recovery context plist:
  (:checkpoint-data :can-recover :resume-targets :resume-exp-id :partial-results)
Returns nil if no recoverable checkpoint.
Uses advisory lock to prevent concurrent recovery race."
  (let* ((data (gptel-checkpoint--load)))
    (unless data
      (message "[checkpoint-recovery] No checkpoint found")
      (return-from gptel-checkpoint-recover nil))
    ;; Try to acquire recovery lock
    (unless (gptel-checkpoint--acquire-lock)
      (message "[checkpoint-recovery] Another process recovering; skipping")
      (return-from gptel-checkpoint-recover nil))
    (unwind-protect
        (progn
          (unless (memq (gptel-checkpoint-data-state data)
                        '(running checkpointed recovered))
            (message "[checkpoint-recovery] Checkpoint state=%s not recoverable"
                     (gptel-checkpoint-data-state data))
            (return-from gptel-checkpoint-recover nil))
          (message "[checkpoint-recovery] Found recoverable checkpoint: run=%s state=%s"
                   (gptel-checkpoint-data-run-id data)
                   (gptel-checkpoint-data-state data))
          ;; Compute resume targets (targets not yet done/failed)
          (let* ((all-targets (gptel-checkpoint-data-targets data))
                 (done (gptel-checkpoint-data-targets-done data))
                 (failed (gptel-checkpoint-data-targets-failed data))
                 (skip-set (append done failed))
                 (resume-targets
                  (if (null skip-set)
                      all-targets
                    (cl-remove-if
                     (lambda (t) (member t skip-set))
                     all-targets))))
            ;; If current target is not done/failed, add it as first resume target
            (let ((current (gptel-checkpoint-data-current-target data)))
              (when (and current
                         (member current resume-targets))
                ;; Move current to front of resume list
                (setq resume-targets
                      (cons current
                            (cl-remove current resume-targets :test #'string=)))))
            (message "[checkpoint-recovery] Targets: total=%d done=%d failed=%d resume=%d"
                     (length all-targets)
                     (length done)
                     (length failed)
                     (length resume-targets))
            (let ((recovery-ctx
                   (list
                    :checkpoint-data data
                    :can-recover (and resume-targets t)
                    :resume-targets resume-targets
                    :resume-exp-id (gptel-checkpoint-data-current-exp-id data)
                    :resume-exp-count (gptel-checkpoint-data-current-exp-count data)
                    :resume-best-score (gptel-checkpoint-data-current-best-score data)
                    :resume-no-improvement-count
                    (gptel-checkpoint-data-no-improvement-count data)
                    :partial-results (gptel-checkpoint-data-results data)
                    :run-id (gptel-checkpoint-data-run-id data)
                    :experiment-loop-snapshot
                    (gptel-checkpoint-data-experiment-loop-snapshot data)
                    :started-at (gptel-checkpoint-data-started-at data))))
              ;; Set current checkpoint to recovered state
              (setf (gptel-checkpoint-data-state data) 'recovered)
              (setq gptel-checkpoint--current data)
              (setq gptel-checkpoint--dirty t)
              (gptel-checkpoint--save)
              recovery-ctx)))
      (gptel-checkpoint--release-lock))))

(defun gptel-checkpoint-snapshot-loop-state ()
  "Capture current experiment loop state into checkpoint.
Call this periodically from the experiment loop."
  (when gptel-checkpoint--current
    (let ((snapshot
           (list
            :exp-id (if (boundp 'gptel-auto-experiment--current-exp-id)
                        gptel-auto-experiment--current-exp-id
                      1)
            :exp-count (if (boundp 'gptel-auto-experiment--current-exp-count)
                           gptel-auto-experiment--current-exp-count
                         0)
            :best-score (or (and (boundp 'gptel-auto-experiment--current-best-score)
                                 gptel-auto-experiment--current-best-score)
                           0.0)
            :no-improvement-count (or
                                    (and (boundp 'gptel-auto-experiment--no-improvement-count)
                                         gptel-auto-experiment--no-improvement-count)
                                    0)
            :consecutive-timeouts 0  ; was incorrectly storing threshold, not the actual per-target count
            :captured-at (format-time-string "%Y-%m-%dT%H:%M:%SZ"))))
      (setf (gptel-checkpoint-data-experiment-loop-snapshot
             gptel-checkpoint--current) snapshot)
      (gptel-checkpoint--mark-dirty));; Auto-save every 5 snapshots to reduce I/O
      (when (and (boundp 'gptel-checkpoint--snapshot-count)
                 (zerop (% (cl-incf gptel-checkpoint--snapshot-count) 5)))
        (gptel-checkpoint--save)))))

(defvar gptel-checkpoint--snapshot-count 0)

;;; ─── Stale Checkpoint Cleanup ───

(defun gptel-checkpoint-cleanup-stale (&optional max-age-hours)
  "Delete checkpoints older than MAX-AGE-HOURS (default: 48).
Also cleans up stale recovery locks."
  (let* ((max-age (or max-age-hours 48))
         (now (float-time))
         (max-age-seconds (* max-age 3600))
         (history-dir (gptel-checkpoint--history-dir))
         (cleaned 0))
    ;; Clean stale locks
    (when (gptel-checkpoint--stale-lock-p)
      (gptel-checkpoint--release-lock)
      (message "[checkpoint] Removed stale recovery lock"))
    ;; Clean old history checkpoints
    (when (file-directory-p history-dir)
      (dolist (file (directory-files history-dir t "\\.ckpt\\'"))
        (let* ((mtime (file-attribute-modification-time (file-attributes file)))
               (age-seconds (- now (float-time mtime))))
          (when (>= age-seconds max-age-seconds)
            (delete-file file)
            (cl-incf cleaned)
            (message "[checkpoint] Removed stale checkpoint: %s (age=%.1fh)"
                     (file-name-nondirectory file)
                     (/ age-seconds 3600.0))))))
    (when (> cleaned 0)
      (message "[checkpoint] Cleaned %d stale checkpoint(s)" cleaned))
    cleaned))

;;; ─── Status ───

(defun gptel-checkpoint-status ()
  "Return status of checkpoint system as plist."
  (let ((data gptel-checkpoint--current))
    (list :active (if data t nil)
          :run-id (and data (gptel-checkpoint-data-run-id data))
          :state (and data (gptel-checkpoint-data-state data))
          :targets (and data (length (gptel-checkpoint-data-targets data)))
          :targets-done (and data (length (gptel-checkpoint-data-targets-done data)))
          :targets-failed (and data (length (gptel-checkpoint-data-targets-failed data)))
          :current-target (and data (gptel-checkpoint-data-current-target data))
          :total-experiments (and data (gptel-checkpoint-data-total-experiments data))
          :results (and data (length (gptel-checkpoint-data-results data)))
          :dirty gptel-checkpoint--dirty
          :checkpoint-file-exists
          (file-exists-p (gptel-checkpoint--active-path)))))

(provide 'gptel-ext-checkpoint)
;;; gptel-ext-checkpoint.el ends here
