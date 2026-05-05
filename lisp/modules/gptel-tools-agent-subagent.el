;;; gptel-tools-agent-subagent.el --- Subagent caching, context, delegation -*- lexical-binding: t; -*-
;; Part of gptel-tools-agent split

(defun my/gptel--agent-task-note-write-region-activity (_start _end filename &rest _args)
  "Treat direct worktree writes to FILENAME as executor activity."
  (when-let* ((path (and (stringp filename)
                         (ignore-errors (expand-file-name filename)))))
    (my/gptel--agent-task-note-context-activity path nil)))

(while (advice-member-p #'my/gptel--agent-task-note-write-region-activity 'write-region)
  (advice-remove 'write-region #'my/gptel--agent-task-note-write-region-activity))
(advice-add 'write-region :after #'my/gptel--agent-task-note-write-region-activity)

(defun my/gptel--agent-task-note-curl-activity (&rest _args)
  "Ignore curl setup chatter for subagent activity tracking.")

(with-eval-after-load 'gptel-request
  (while (advice-member-p #'my/gptel--agent-task-note-curl-activity
                          'gptel-curl--get-args)
    (advice-remove 'gptel-curl--get-args
                   #'my/gptel--agent-task-note-curl-activity)))

(defun my/gptel--register-agent-task-buffer (buffer)
  "Record BUFFER as the active request buffer for the current subagent task."
  (when (and my/gptel--current-agent-task-id
             (buffer-live-p buffer))
    (when-let* ((state (gethash my/gptel--current-agent-task-id
                                my/gptel--agent-task-state)))
      (let* ((current (plist-get state :request-buf))
             (current-priority (my/gptel--agent-task-buffer-priority state current))
             (new-priority (my/gptel--agent-task-buffer-priority state buffer))
             (updated-state
              (if (or (not (buffer-live-p current))
                      (eq current buffer)
                      (> new-priority current-priority))
                  (plist-put state :request-buf buffer)
                state)))
        (puthash my/gptel--current-agent-task-id
                 updated-state
                 my/gptel--agent-task-state)
        (when (and (not gptel-auto-workflow--defer-subagent-env-persistence)
                   (not (plist-get updated-state :launching))
                   (plist-get updated-state :process-environment)
                   (fboundp 'gptel-auto-workflow--persist-subagent-process-environment))
          (gptel-auto-workflow--persist-subagent-process-environment
           buffer
           (plist-get updated-state :process-environment))))))
  buffer)

(defun my/gptel--reset-agent-task-state ()
  "Abort and clear all tracked subagent task state."
  (when (hash-table-p my/gptel--agent-task-state)
    (let (request-buffers)
      (maphash
       (lambda (_task-id state)
         (when (plistp state)
           (my/gptel--cancel-agent-task-timers state)
           (when-let* ((request-buf (my/gptel--agent-task-request-buffer state)))
             (push request-buf request-buffers))))
       my/gptel--agent-task-state)
      (clrhash my/gptel--agent-task-state)
      (dolist (request-buf (delete-dups request-buffers))
        (when (and (buffer-live-p request-buf)
                   (fboundp 'gptel-abort))
          (condition-case err
              (gptel-abort request-buf)
            (error
             (let ((safe-msg (condition-case nil
                                 (my/gptel--sanitize-for-logging
                                  (error-message-string err) 160)
                               (error "abort-error"))))
               (message "[nucleus] Failed to abort stale subagent buffer %s: %s"
                        (buffer-name request-buf)
                        safe-msg)))))))))

(defun my/gptel--normalize-agent-activity-dir (dir)
  "Return DIR as a canonical directory path with trailing slash, or nil."
  (when (stringp dir)
    (file-name-as-directory (expand-file-name dir))))

(defun my/gptel--agent-task-overlaps-p (state origin-buf activity-dir)
  "Return non-nil when STATE overlaps a new dispatch from ORIGIN-BUF.

ACTIVITY-DIR should be the canonical workflow activity directory for the new
dispatch. Overlap is intentionally conservative during auto-workflow runs:
subagents for one routed experiment buffer/worktree should not survive into a
new analyzer/executor/grader launch on that same buffer or worktree."
  (and (gptel-auto-workflow--state-active-p state)
       (let* ((request-buf (my/gptel--agent-task-request-buffer state))
              (state-origin (plist-get state :origin-buf))
              (state-dir (my/gptel--normalize-agent-activity-dir
                          (plist-get state :activity-dir))))
         (or (and (buffer-live-p origin-buf)
                  (or (eq state-origin origin-buf)
                      (eq request-buf origin-buf)))
             (and activity-dir state-dir
                  (equal activity-dir state-dir))))))

(defun my/gptel--cleanup-overlapping-agent-tasks (origin-buf activity-dir)
  "Abort and clear tracked subagent tasks that overlap a new workflow dispatch.

This prevents stale timers/callbacks from older analyzer/executor work on the
same routed experiment buffer from re-entering a later retry."
  (let ((normalized-dir (my/gptel--normalize-agent-activity-dir activity-dir))
        overlap-ids
        request-buffers)
    (maphash
     (lambda (task-id state)
       (when (my/gptel--agent-task-overlaps-p state origin-buf normalized-dir)
         (my/gptel--cancel-agent-task-timers state)
         (when-let* ((request-buf (my/gptel--agent-task-request-buffer state)))
           (push request-buf request-buffers))
         (push task-id overlap-ids)))
     my/gptel--agent-task-state)
    (dolist (task-id overlap-ids)
      (remhash task-id my/gptel--agent-task-state))
    (dolist (request-buf (delete-dups request-buffers))
      (when (and (buffer-live-p request-buf)
                 (fboundp 'gptel-abort))
        (condition-case err
            (gptel-abort request-buf)
          (error
           (message "[nucleus] Failed to abort overlapping subagent buffer %s: %s"
                    (buffer-name request-buf)
                    (my/gptel--sanitize-for-logging
                     (error-message-string err) 160))))))
    (length overlap-ids)))

(defun my/gptel--call-gptel-agent-task (callback agent-type description prompt)
  "Invoke the active gptel subagent task runner.
In headless auto-workflow runs, bypass `gptel-agent-loop-task' to avoid
its async continuation layer in the worker daemon."
  (require 'gptel-request)
  (let* ((headless-auto-workflow
          (and (bound-and-true-p gptel-auto-workflow--headless)
               (bound-and-true-p gptel-auto-workflow-persistent-headless)
               (bound-and-true-p gptel-auto-workflow--current-project)))
         (isolated-env
          (and headless-auto-workflow
               (gptel-auto-workflow--isolated-state-environment
                "copilot-auto-workflow-subagent-"
                nil
                t)))
         (gptel-auto-workflow--defer-subagent-env-persistence
          (and isolated-env t))
         (gptel-auto-workflow--subagent-process-environment isolated-env)
         (process-environment
          (or isolated-env process-environment))
         (task-runner nil))
    (when (and isolated-env
               my/gptel--current-agent-task-id)
      (when-let* ((state (gethash my/gptel--current-agent-task-id
                                  my/gptel--agent-task-state)))
        (puthash my/gptel--current-agent-task-id
                 (plist-put state :process-environment
                            (copy-sequence isolated-env))
                 my/gptel--agent-task-state)))
    (setq task-runner
          (cond
           ((and headless-auto-workflow
                 (fboundp 'my/gptel-agent--task-override))
            #'my/gptel-agent--task-override)
           ((fboundp 'gptel-agent--task) #'gptel-agent--task)
           ((fboundp 'my/gptel-agent--task-override)
            #'my/gptel-agent--task-override)
           (t
            (error "[nucleus] No gptel-agent task runner available"))))
    (if (and headless-auto-workflow
             (boundp 'gptel-agent-loop--bypass))
        (let ((gptel-agent-loop--bypass t))
          (funcall task-runner callback agent-type description prompt))
      (funcall task-runner callback agent-type description prompt))))

(defun my/gptel--disable-auto-retry-for-fsm (fsm)
  "Mark FSM so global auto-retry advice will not reschedule it."
  (require 'gptel-request)
  (when (and fsm (fboundp 'gptel-fsm-info))
    (let ((info (ignore-errors (gptel-fsm-info fsm))))
      (when (listp info)
        (setf (gptel-fsm-info fsm)
              (plist-put info :disable-auto-retry t)))
      t)))

(defun my/gptel--disable-auto-retry-transform (fsm)
  "Mark FSM as no-retry before request dispatch."
  (my/gptel--disable-auto-retry-for-fsm fsm))

(defun my/gptel--first-existing-directory (&rest dirs)
  "Return the first existing directory in DIRS, normalized with a trailing slash."
  (catch 'found
    (dolist (dir dirs)
      (when (and (stringp dir)
                 (file-directory-p dir))
        (throw 'found (file-name-as-directory (expand-file-name dir)))))
    nil))

(defun my/gptel--prime-curl-buffer-directory (&rest _)
  "Retarget the shared curl buffer to the current workflow root."
  (let ((root (or (my/gptel--first-existing-directory
                   default-directory
                   user-emacs-directory
                   temporary-file-directory)
                  temporary-file-directory)))
    (with-current-buffer (get-buffer-create " *gptel-curl*")
      (setq default-directory root))))

(with-eval-after-load 'gptel-request
  (advice-remove 'gptel-curl-get-response
                 #'my/gptel--prime-curl-buffer-directory)
  (advice-add 'gptel-curl-get-response :before
              #'my/gptel--prime-curl-buffer-directory))

(defun my/gptel--invoke-callback-safely (callback result)
  "Invoke CALLBACK with RESULT from a stable internal buffer.

This prevents `Selecting deleted buffer' errors when callback side effects
delete the request or file buffer that happened to be current when the
subagent callback fired, and avoids reusing a deleted worktree as
`default-directory'."
  (cond ((functionp callback)
         (let* ((safe-buffer (get-buffer-create " *gptel-callback*"))
                (safe-default-directory
                 (or (my/gptel--first-existing-directory
                      default-directory
                      user-emacs-directory
                      temporary-file-directory)
                     temporary-file-directory)))
            (condition-case err
                (with-current-buffer safe-buffer
                  (setq default-directory safe-default-directory)
                  (funcall callback result))
              (error
               (message "[nucleus] Callback error ignored after cleanup: %S" err)
               nil))))
        (t
         (message "[nucleus] Warning: my/gptel--invoke-callback-safely skipped invalid callback: %S"
                  (type-of callback)))))

(defun my/gptel--agent-task-with-timeout (callback agent-type description prompt &optional files include-history include-diff)
  "Wrapper around `gptel-agent--task' that adds a timeout and progress messages.
CALLBACK is called with the result or a timeout error.
Uses hash table keyed by task-id to support parallel execution."
  (let* ((task-id (cl-incf my/gptel--agent-task-counter))
         (start-time (current-time))
         (task-timeout my/gptel-agent-task-timeout)
         (origin-buf (current-buffer))
         (activity-dir (and (stringp default-directory)
                            (expand-file-name default-directory)))
         (parent-fsm-local-p (local-variable-p 'gptel--fsm-last origin-buf))
         (parent-fsm (and parent-fsm-local-p
                          (buffer-local-value 'gptel--fsm-last origin-buf)))
         (child-fsm nil)
         (packaged-prompt
          (my/gptel--build-subagent-context
           prompt files include-history include-diff origin-buf))
         (uses-idle-timeout
          (my/gptel--agent-task-uses-idle-timeout-p agent-type))
         (hard-timeout
          (and uses-idle-timeout
               (integerp my/gptel-agent-task-hard-timeout)
               (> my/gptel-agent-task-hard-timeout 0)
               my/gptel-agent-task-hard-timeout))
         (hard-deadline
          (and hard-timeout
               (time-add start-time (seconds-to-time hard-timeout))))
         (overlap-count
          (and (bound-and-true-p gptel-auto-workflow--running)
               (my/gptel--cleanup-overlapping-agent-tasks
                origin-buf activity-dir)))
         (restore-origin-fsm
          (lambda (&optional expected-fsm)
            (when (buffer-live-p origin-buf)
              (with-current-buffer origin-buf
                (when (or (null expected-fsm)
                          (eq gptel--fsm-last expected-fsm))
                  (if parent-fsm-local-p
                      (setq-local gptel--fsm-last parent-fsm)
                    (kill-local-variable 'gptel--fsm-last)))))))
         (wrapped-cb
          (lambda (result)
            (let* ((state (gethash task-id my/gptel--agent-task-state))
                   (already-done (plist-get state :done)))
              (if (not state)
                  (message "[nucleus] Ignoring stale subagent %s callback after reset"
                           agent-type)
                ;; Atomic test-and-set: mark done before acting to prevent
                ;; double-invocation if gptel-abort fires synchronously in timeout.
                (puthash task-id (plist-put state :done t) my/gptel--agent-task-state)
                (unless already-done
                  (my/gptel--cancel-agent-task-timers state)
                  (message "[nucleus] Subagent %s completed in %.1fs, result-len=%d"
                           agent-type (float-time (time-since start-time))
                           (if (stringp result) (length result) 0))
                  (funcall restore-origin-fsm child-fsm)
                  (unwind-protect
                      (my/gptel--invoke-callback-safely callback result)
                    (remhash task-id my/gptel--agent-task-state))))))))
    (cl-labels
        ((finish-timeout (state timeout-seconds timeout-suffix
                                &optional timeout-kind total-elapsed-seconds)
           (puthash task-id (plist-put state :done t)
                    my/gptel--agent-task-state)
           (my/gptel--cancel-agent-task-timers state)
           (if (eq timeout-kind :idle)
               (message "[nucleus] Subagent %s timed out after %ds idle timeout (%.1fs total runtime), aborting request"
                        agent-type timeout-seconds (or total-elapsed-seconds 0.0))
             (message "[nucleus] Subagent %s timed out after %ds%s, aborting request"
                      agent-type timeout-seconds timeout-suffix))
           (my/gptel--cleanup-agent-request-buffer state)
           (let ((timeout-result
                  (if (eq timeout-kind :idle)
                      (format "Error: Task \"%s\" (%s) timed out after %ds idle timeout (%.1fs total runtime)."
                              description agent-type timeout-seconds (or total-elapsed-seconds 0.0))
                    (format "Error: Task \"%s\" (%s) timed out after %ds%s."
                            description agent-type timeout-seconds timeout-suffix))))
             (funcall restore-origin-fsm child-fsm)
             (unwind-protect
                 (my/gptel--invoke-callback-safely callback timeout-result)
               (remhash task-id my/gptel--agent-task-state))))
         (rearm-timeout (state)
           (when task-timeout
             (when (timerp (plist-get state :timeout-timer))
               (cancel-timer (plist-get state :timeout-timer)))
             (let* ((remaining-hard-seconds
                     (and hard-deadline
                          (max 0
                               (ceiling
                                (float-time
                                 (time-subtract hard-deadline (current-time)))))))
                    (next-delay
                     (if remaining-hard-seconds
                         (min task-timeout remaining-hard-seconds)
                       task-timeout)))
               (setq state
                     (plist-put
                      state :timeout-timer
                      (run-at-time
                       next-delay nil
                       (lambda ()
                         (let* ((state (gethash task-id my/gptel--agent-task-state))
                                (already-done (plist-get state :done))
                                (last-activity (plist-get state :last-activity-time))
                                (idle-seconds
                                 (and last-activity
                                      (float-time (time-since last-activity))))
                                (remaining-hard
                                 (and hard-deadline
                                      (float-time
                                       (time-subtract hard-deadline (current-time)))))
                                (hard-expired (and remaining-hard
                                                   (<= remaining-hard 0)))
                                (total-elapsed
                                 (float-time (time-since start-time)))
                                (timeout-kind
                                 (cond
                                  (hard-expired :hard-runtime)
                                  ((and uses-idle-timeout
                                        idle-seconds
                                        (>= idle-seconds task-timeout))
                                   :idle)
                                  (t :timeout)))
                                (timeout-seconds
                                 (if (eq timeout-kind :hard-runtime)
                                     hard-timeout
                                   task-timeout))
                                (timeout-suffix
                                 (if (eq timeout-kind :hard-runtime)
                                     " total runtime"
                                   "")))
                           (when state
                             (cond
                              (already-done nil)
                              ((and uses-idle-timeout
                                    (not hard-expired)
                                    idle-seconds
                                    (< idle-seconds task-timeout))
                               (rearm-timeout state))
                              (t
                               (finish-timeout
                                state timeout-seconds timeout-suffix
                                timeout-kind total-elapsed)))))))))
               (puthash task-id state my/gptel--agent-task-state)))
           state)
         (note-buffer-activity (state)
           (when uses-idle-timeout
             (when-let* ((request-buf (my/gptel--agent-task-request-buffer state))
                         ((buffer-live-p request-buf)))
               (let* ((current-tick (my/gptel--agent-task-buffer-tick request-buf))
                      (last-tick (plist-get state :last-buffer-tick)))
                 (when (and current-tick (not (equal current-tick last-tick)))
                   (setq state (plist-put state :last-buffer-tick current-tick))
                   (setq state (plist-put state :last-activity-time (current-time)))
                   (setq state (rearm-timeout state))))))
           state))
      (message "[nucleus] Delegating to subagent %s%s..."
               agent-type
               (if task-timeout
                   (format " (%s: %ds%s)"
                           (if uses-idle-timeout "idle timeout" "timeout")
                           task-timeout
                           (if (and hard-timeout (> hard-timeout task-timeout))
                               (format ", max runtime: %ds" hard-timeout)
                             ""))
                 ""))
      (when (and overlap-count (> overlap-count 0))
        (message "[nucleus] Cleared %d overlapping subagent task(s) before launching %s"
                 overlap-count agent-type))
      (let ((progress-timer
             (run-at-time
              my/gptel-subagent-progress-interval
              my/gptel-subagent-progress-interval
              (lambda ()
                (let ((state (gethash task-id my/gptel--agent-task-state)))
                  (when (gptel-auto-workflow--state-active-p state)
                    (setq state (note-buffer-activity state))
                    (let* ((elapsed (float-time (time-since start-time)))
                           (remaining-hard
                            (and hard-deadline
                                 (float-time
                                  (time-subtract hard-deadline (current-time)))))
                           (hard-expired (and remaining-hard
                                              (<= remaining-hard 0))))
                      (if (and task-timeout
                               (or hard-expired
                                   (and (not uses-idle-timeout)
                                        (>= elapsed task-timeout))))
                          (finish-timeout
                           state
                           (if hard-expired hard-timeout task-timeout)
                           (if hard-expired " total runtime" "")
                           (if hard-expired :hard-runtime :timeout)
                           elapsed)
                        (when (or (bound-and-true-p gptel-auto-workflow--running)
                                  (bound-and-true-p gptel-auto-workflow--cron-job-running))
                          (gptel-auto-workflow--update-progress)
                          (gptel-auto-workflow--persist-status))
                        (message "[nucleus] Subagent %s still running... (%.1fs elapsed)"
                                 agent-type elapsed)))))))))
        (puthash task-id (list :done nil
                               :timeout-timer nil
                               :progress-timer progress-timer
                               :origin-buf origin-buf
                               :request-buf nil
                               :launching t
                               :process-environment nil
                               :last-buffer-tick nil
                               :last-activity-time (current-time)
                               :agent-type agent-type
                               :activity-dir activity-dir)
                 my/gptel--agent-task-state)
        (when task-timeout
          (let ((state (gethash task-id my/gptel--agent-task-state)))
            (rearm-timeout state)))
        (let ((my/gptel--current-agent-task-id task-id)
              (my/gptel--subagent-origin-buffer origin-buf))
          (let ((request-started nil)
                (launch-error nil))
            (unwind-protect
                (condition-case err
                    (progn
                      (my/gptel--call-gptel-agent-task
                       wrapped-cb agent-type description packaged-prompt)
                      (setq request-started t)
                      (when-let* ((state (gethash task-id my/gptel--agent-task-state)))
                        (setq state (plist-put state :launching nil))
                        (puthash task-id state my/gptel--agent-task-state)
                        (let ((request-buf (my/gptel--agent-task-request-buffer state)))
                          (when (buffer-live-p request-buf)
                            (when-let* ((task-env (plist-get state :process-environment))
                                        ((fboundp 'gptel-auto-workflow--persist-subagent-process-environment)))
                              (gptel-auto-workflow--persist-subagent-process-environment
                               request-buf task-env))
                            (with-current-buffer request-buf
                              (when (local-variable-p 'gptel--fsm-last)
                                (setq child-fsm gptel--fsm-last)
                                (when (and (boundp 'gptel-tools)
                                           gptel-tools)
                                  (my/gptel--seed-fsm-tools child-fsm gptel-tools))
                                (my/gptel--disable-auto-retry-for-fsm child-fsm)))
                            (let* ((state (gethash task-id my/gptel--agent-task-state))
                                   (tick (my/gptel--agent-task-buffer-tick request-buf)))
                              (when (and state tick)
                                (puthash task-id
                                         (plist-put state :last-buffer-tick tick)
                                         my/gptel--agent-task-state)))))))
                  (error
                   (setq launch-error err)))
              (unless request-started
                (funcall restore-origin-fsm)))
            (when launch-error
              (let ((state (gethash task-id my/gptel--agent-task-state)))
                (when state
                  (my/gptel--cancel-agent-task-timers state)
                  (remhash task-id my/gptel--agent-task-state))
                (funcall restore-origin-fsm child-fsm)
                (my/gptel--cleanup-agent-request-buffer state)
                (message "[nucleus] Subagent %s failed before startup completed: %s"
                         agent-type
                         (my/gptel--sanitize-for-logging
                          (error-message-string launch-error) 160))
                (my/gptel--invoke-callback-safely
                 callback
                 (format "Error: Task runner failed for %s: %s"
                         agent-type
                         (error-message-string launch-error)))))))))))

(cl-defun my/gptel--run-agent-tool (callback &optional agent-name description prompt files include-history include-diff)
  "Run a gptel-agent agent by name.

AGENT-NAME must exist in `gptel-agent--agents`.

INCLUDE-HISTORY defaults to `my/gptel-subagent-include-history-default' when nil."
  (cl-block my/gptel--run-agent-tool
    (unless (and (require 'gptel nil t) (require 'gptel-agent nil t))
      (funcall callback "Error: gptel or gptel-agent is not available")
      (cl-return-from my/gptel--run-agent-tool))
    (unless (and (boundp 'gptel-agent--agents) gptel-agent--agents)
      (ignore-errors (gptel-agent-update)))
    (unless (gptel-auto-workflow--non-empty-string-p agent-name)
      (funcall callback "Error: agent-name is empty")
      (cl-return-from my/gptel--run-agent-tool))
    (unless (gptel-auto-workflow--non-empty-string-p prompt)
      (funcall callback "Error: prompt is empty")
      (cl-return-from my/gptel--run-agent-tool))
    (unless (assoc agent-name gptel-agent--agents)
      (funcall callback
               (format "Error: unknown agent %S. Known agents: %s"
                       agent-name
                       (string-join (sort (mapcar #'car gptel-agent--agents) #'string<) ", ")))
      (cl-return-from my/gptel--run-agent-tool))
    ;; Hard gate: executor is forbidden in Plan mode (read-only preset).
    (when (and (equal agent-name "executor")
               (boundp 'gptel--preset)
               (eq gptel--preset 'gptel-plan))
      (funcall callback
               "Error: executor is not available in Plan mode. Switch to Agent mode first.")
      (cl-return-from my/gptel--run-agent-tool))
    (unless (fboundp 'gptel-agent--task)
      (funcall callback "Error: gptel-agent task runner not available")
      (cl-return-from my/gptel--run-agent-tool))
    ;; Convert string params to booleans at entry point for cleaner internal API
    (let ((include-history-bool (my/gptel--string-to-bool include-history))
          (include-diff-bool (my/gptel--string-to-bool include-diff)))
      ;; Apply defaults only when input is nil, not when explicitly "false"
      ;; (my/gptel--string-to-bool returns nil for both, so check original input)
      (when (null include-history)
        (setq include-history-bool my/gptel-subagent-include-history-default))
      (my/gptel--agent-task-with-timeout callback agent-name description prompt files
                                         include-history-bool include-diff-bool))))

(defun my/gptel--run-agent-tool-with-timeout (timeout callback agent-name description prompt
                                                      &optional files include-history include-diff active-grace)
  "Run `my/gptel--run-agent-tool' with TIMEOUT and optional ACTIVE-GRACE."
  (let ((previous-timeout my/gptel-agent-task-timeout)
        (previous-hard-timeout my/gptel-agent-task-hard-timeout)
        (grace (or active-grace gptel-auto-experiment-active-grace)))
    (unwind-protect
        (progn
          (setq my/gptel-agent-task-timeout timeout)
          (setq my/gptel-agent-task-hard-timeout
                (and (equal agent-name "executor")
                     (integerp timeout) (> timeout 0)
                     (integerp grace) (> grace 0)
                     (+ timeout grace)))
          (my/gptel--run-agent-tool callback agent-name description prompt
                                    files include-history include-diff))
      (setq my/gptel-agent-task-timeout previous-timeout
            my/gptel-agent-task-hard-timeout previous-hard-timeout))))

;;; Tool Registration

(defun gptel-tools-agent-register ()
  "Register RunAgent tool with gptel."
  (when (fboundp 'gptel-make-tool)
    (gptel-make-tool
     :name "RunAgent"
     :description "Run a gptel-agent subagent by name (e.g. explorer, researcher, executor, reviewer)"
     :function #'my/gptel--run-agent-tool
     :args '((:name "agent_name"
                    :type string
                    :description "Agent name (e.g. 'researcher', 'introspector', 'executor', 'explorer', 'reviewer')"
                    :enum ["explorer" "researcher" "introspector" "executor" "reviewer"])
             (:name "description"
                    :type string
                    :description "Short task label")
             (:name "prompt"
                    :type string
                    :description "Full task prompt")
             (:name "files"
                    :type array
                    :items (:type string)
                    :optional t
                    :description "Optional list of file paths to inject into the subagent context.")
             (:name "include_history"
                    :type string
                    :optional t
                    :description "Set to \"false\" to exclude conversation history. Default: history IS included (see my/gptel-subagent-include-history-default).")
             (:name "include_diff"
                    :type string
                    :optional t
                    :description "Set to \"true\" to inject git diff HEAD into subagent context."))
     :category "gptel-agent"
     :async t
     :confirm t
     :include t)))

;;; TodoWrite Overlay Fix for Subagent Context

(defvar gptel-agent--hrule)  ; from gptel-agent-tools

(defvar-local my/gptel--todo-overlay nil
  "Buffer-local cache for TodoWrite overlay.
Avoids scanning entire buffer on each update.")

(defun my/gptel-agent--write-todo-around (orig todos)
  "Advice to fix TodoWrite overlay updates in subagent context.
Uses cached overlay reference for O(1) lookup instead of O(n) buffer scan."
  (setq gptel-agent--todos todos)
  (let* ((info (gptel-fsm-info gptel--fsm-last))
         (pos (or (plist-get info :tracking-marker)
                  (plist-get info :position)))
         (buf (plist-get info :buffer))
         (existing-ov (and buf
                           (buffer-live-p buf)
                           (with-current-buffer buf
                             (or my/gptel--todo-overlay
                                 (setq my/gptel--todo-overlay
                                       (cl-find-if
                                        (lambda (ov) (overlay-get ov 'gptel-agent--todos))
                                        (overlays-in (point-min) (point-max)))))))))
    (if existing-ov
        (let* ((formatted-todos
                (mapconcat
                 (lambda (todo)
                   (pcase (plist-get todo :status)
                     ("completed"
                      (concat "✓ " (propertize (plist-get todo :content)
                                               'face '(:inherit shadow :strike-through t))))
                     ("in_progress"
                      (concat "● " (propertize (plist-get todo :activeForm)
                                               'face '(:inherit (bold warning)))))
                     (_ (concat "○ " (plist-get todo :content)))))
                 todos "\n"))
               (todo-display
                (concat
                 (unless (= (char-before (overlay-end existing-ov)) 10) "\n")
                 gptel-agent--hrule
                 (propertize "Task list: [ "
                             'face '(:inherit (font-lock-comment-face bold)))
                 (propertize "TAB to toggle display ]\n" 'face 'font-lock-comment-face)
                 formatted-todos "\n"
                 gptel-agent--hrule)))
          (overlay-put existing-ov 'after-string todo-display)
          t)
      (funcall orig todos))))

(with-eval-after-load 'gptel-agent-tools
  (advice-add 'gptel-agent--write-todo :around #'my/gptel-agent--write-todo-around))

;;; Auto-Workflow (Semi-Autonomous Overnight Experiments)

(declare-function magit-worktree-branch "magit-worktree")
(declare-function magit-worktree-delete "magit-worktree")
(declare-function magit-git-success "magit-git")
(declare-function gptel-benchmark-analyze "gptel-benchmark-subagent")
(declare-function gptel-benchmark-grade "gptel-benchmark-subagent")
(declare-function gptel-benchmark-compare "gptel-benchmark-subagent")
(declare-function gptel-benchmark-eight-keys-score "gptel-benchmark-principles")
(declare-function gptel-auto-experiment--agent-error-p "gptel-tools-agent")

;;; Configuration

(defcustom gptel-auto-workflow-targets
  '()
  "Static fallback targets when LLM selection disabled or fails.
Empty by default - LLM selects targets dynamically.
Monthly subscription: LLM selection finds best targets each run."
  :type '(repeat string)
  :safe #'always
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-worktree-base "var/tmp/experiments"
  "Base directory for auto-workflow worktrees."
  :type 'directory
  :group 'gptel-tools-agent)

(defcustom gptel-auto-experiment-time-budget 600
  "Time budget per experiment in seconds (default: 10 min)."
  :type 'integer
  :safe #'integerp
  :group 'gptel-tools-agent)

(defcustom gptel-auto-experiment-active-grace 420
  "Extra wall-clock seconds active executor experiments may use beyond budget.

Executor requests still use `gptel-auto-experiment-time-budget' as their idle
timeout, but active runs may exceed it by this grace period before they are
forcibly aborted.  The default keeps the wrapper hard cap above 900s backend
request limits so active calls do not race provider-side timeouts."
  :type 'integer
  :safe #'integerp
  :group 'gptel-tools-agent)

(defcustom gptel-auto-experiment-validation-retry-time-budget 240
  "Timeout budget in seconds for validation-retry executor calls.

Validation retries should repair one known error in the current worktree, so
they use a shorter budget than full experiments while still allowing enough
time to apply and verify a focused fix."
  :type 'integer
  :safe #'integerp
  :group 'gptel-tools-agent)

(defcustom gptel-auto-experiment-validation-retry-active-grace 180
  "Extra wall-clock seconds active validation-retry calls may use beyond budget."
  :type 'integer
  :safe #'integerp
  :group 'gptel-tools-agent)

(defconst gptel-auto-workflow--legacy-validation-retry-active-grace 120
  "Previous default for `gptel-auto-experiment-validation-retry-active-grace'.")

(defconst gptel-auto-workflow--current-validation-retry-active-grace 180
  "Current runtime default for `gptel-auto-experiment-validation-retry-active-grace'.")

(defcustom gptel-auto-experiment-delay-between 3
  "Seconds to wait between experiments to avoid API rate limits."
  :type 'integer
  :safe #'integerp
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-review-time-budget 600
  "Timeout budget in seconds for staging review subagent calls."
  :type 'integer
  :safe #'integerp
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-review-file-context-max-bytes 50000
  "Maximum size in bytes for one changed file attached to reviewer context.

Oversized files are omitted from `gptel-benchmark--subagent-files` and the
reviewer must inspect them via tools when needed."
  :type 'integer
  :safe #'integerp
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-review-file-context-max-total-bytes 120000
  "Maximum cumulative size in bytes for reviewer-attached changed files."
  :type 'integer
  :safe #'integerp
  :group 'gptel-tools-agent)

(defcustom gptel-auto-experiment-max-per-target 5
  "Maximum experiments per target.
Monthly subscription: 5 is optimal (diminishing returns after 3-4)."
  :type 'integer
  :safe #'integerp
  :group 'gptel-tools-agent)

(defcustom gptel-auto-experiment-no-improvement-threshold 2
  "Stop after N consecutive no-improvements.
Monthly subscription: 2 for fail-fast, try more different files."
  :type 'integer
  :safe #'integerp
  :group 'gptel-tools-agent)

(defcustom gptel-auto-experiment-min-quality-gain-on-score-tie 0.02
  "Minimum code-quality gain required to keep a tied benchmark score.

Tied Eight Keys scores should only be kept when code quality improves by at
least this amount and the combined score still improves.

Lowered from 0.03: file-level quality scoring produces small deltas even for
real defensive improvements, especially on already-high-quality files."
  :type 'number
  :safe #'numberp
  :group 'gptel-tools-agent)

(defcustom gptel-auto-experiment-use-subagents t
  "Use analyzer/grader/comparator subagents."
  :type 'boolean
  :group 'gptel-tools-agent)

(defcustom gptel-auto-experiment-auto-push t
  "Automatically push experiment branches to the shared remote after commit.
When non-nil, branches are pushed to the workflow remote for PR review on Forgejo."
  :type 'boolean
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-require-review t
  "When non-nil, require LLM code review before merging to staging.
Reviewer checks for blockers, critical bugs, and security issues.
Changes are only merged if review passes."
  :type 'boolean
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-research-before-fix nil
  "When non-nil, use researcher to find fix approach before executor.
Adds ~30-60s latency per retry but may improve fix quality.
When nil, executor researches and fixes in one pass (faster)."
  :type 'boolean
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-use-staging t
  "When non-nil, use staging branch as integration target.
Staging is NEVER deleted and NEVER auto-merged to main.

Flow:
1. Sync staging from main at workflow start
2. optimize/* changes are merged to staging
3. Tests run on staging (isolated worktree)
4. If tests pass: push staging to the workflow remote
5. Human reviews staging and manually merges to main

IMPORTANT: Auto-workflow NEVER touches main branch.
All merges wait in staging for human review."
  :type 'boolean
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-staging-branch "staging"
  "Name of the staging branch for integration.
This branch is NEVER deleted and NEVER auto-merged to main."
  :type 'string
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-shared-remote nil
  "Canonical remote used for shared auto-workflow refs.
When nil, follow the local `main' branch's configured remote and fall back to
`origin'."
  :type '(choice (const :tag "Follow main's tracking remote" nil)
                 (string :tag "Remote name"))
  :group 'gptel-tools-agent)

;;; State

(defvar gptel-auto-workflow--staging-worktree-dir nil)
(defvar gptel-auto-workflow--review-retry-count 0
  "Retry count for current review cycle.")
(defvar gptel-auto-workflow--review-error-retry-count 0
  "Retry count for transient reviewer transport failures.")
(defvar gptel-auto-workflow--review-max-retries 2
  "Maximum retries when review is blocked. 0 = no retry.")
(defvar gptel-auto-workflow--staging-push-max-retries 2
  "Maximum refresh-and-retry attempts after shared staging advances mid-run.
Counts retry publishes after the initial failed push. 0 disables replay.")

(defvar gptel-auto-workflow--worktree-state (make-hash-table :test 'equal)
  "Hash table for per-target worktree state. Keyed by target.
Values: plist (:worktree-dir :current-branch).")

(defvar gptel-auto-experiment--no-improvement-count 0
  "Count of consecutive experiments with no improvement.")
(defvar gptel-auto-experiment--best-score 0.0
  "Best score achieved in current experiment loop.")

;; Safety: Ensure worktree-state is initialized (handles case where
;; variable was previously bound but not as hash-table)
(unless (hash-table-p gptel-auto-workflow--worktree-state)
  (setq gptel-auto-workflow--worktree-state (make-hash-table :test 'equal)))

(defun gptel-auto-workflow--get-worktree-state (target key)
  "Get value for KEY from worktree state for TARGET.
Helper to reduce duplication in worktree accessor functions.
Returns nil if hash table is invalid or TARGET not found."
  (when (hash-table-p gptel-auto-workflow--worktree-state)
    (plist-get (gethash target gptel-auto-workflow--worktree-state) key)))

(defun gptel-auto-workflow--get-worktree-dir (target)
  "Get worktree-dir for TARGET from hash table.
Returns nil if directory doesn't exist or state is invalid."
  (when-let* ((dir (gptel-auto-workflow--get-worktree-state target :worktree-dir))
              ((stringp dir))
              ((file-directory-p dir)))
    dir))

(defun gptel-auto-workflow--get-current-branch (target)
  "Get current-branch for TARGET from hash table."
  (gptel-auto-workflow--get-worktree-state target :current-branch))

(defun gptel-auto-workflow--clear-worktree-state (target)
  "Clear worktree state for TARGET.
Resets :worktree-dir and :current-branch to nil in hash table.
ASSUMPTION: gptel-auto-workflow--worktree-state is a hash table.
TESTABLE: Can verify state is cleared by checking gethash result."
  (when (hash-table-p gptel-auto-workflow--worktree-state)
    (puthash target (list :worktree-dir nil :current-branch nil)
             gptel-auto-workflow--worktree-state)))

;;; Worktree Management

(defun gptel-auto-workflow--run-branch-token ()
  "Return a short run token for unique optimize branch names.
Uses the trailing time/hash portion of `gptel-auto-workflow--run-id' when available."
  (let ((run-id (and (stringp gptel-auto-workflow--run-id)
                     (downcase gptel-auto-workflow--run-id))))
    (when (and run-id
               (string-match "\\([0-9]\\{6\\}z\\)-\\([a-z0-9]+\\)\\'" run-id))
      (format "r%s%s"
              (match-string 1 run-id)
              (match-string 2 run-id)))))

(defun gptel-auto-workflow--branch-name (target &optional experiment-id)
  "Generate branch name for TARGET with machine hostname.
Format: optimize/{target}-{hostname}[-r{run}]-exp{N}
Base branch is always 'main'.
Multiple machines can optimize same target without conflicts."
  (let* ((basename (file-name-sans-extension (file-name-nondirectory target)))
         (name (car (last (split-string basename "-"))))
         (host (system-name))
         (run-token (and experiment-id
                         (gptel-auto-workflow--run-branch-token))))
    (if experiment-id
        (if run-token
            (format "optimize/%s-%s-%s-exp%d" name host run-token experiment-id)
          (format "optimize/%s-%s-exp%d" name host experiment-id))
      (format "optimize/%s-%s" name host))))

(defun gptel-auto-workflow--branch-worktree-paths (branch &optional proj-root)
  "Return attached worktree paths for BRANCH within PROJ-ROOT.
BRANCH should be the short local branch name, e.g. optimize/foo-exp1."
  (let ((default-directory (or proj-root (gptel-auto-workflow--default-dir)))
        (buffer (generate-new-buffer " *git-worktree-list*"))
        (paths nil)
        (branch-ref (format "refs/heads/%s" branch)))
    (unwind-protect
        (when (= 0 (call-process "git" nil buffer nil "worktree" "list" "--porcelain"))
          (with-current-buffer buffer
            (dolist (entry (split-string (buffer-string) "\n\n+" t))
              (when (string-match-p (format "^branch %s$" (regexp-quote branch-ref))
                                    entry)
                (when (string-match "^worktree \\(.*\\)$" entry)
                  (push (match-string 1 entry) paths))))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))
    (nreverse (delete-dups paths))))

(defun gptel-auto-workflow--optimize-worktrees (&optional proj-root)
  "Return attached optimize worktrees for the current host within PROJ-ROOT.
Each item is a plist with keys :branch and :path."
  (let* ((default-directory (or proj-root (gptel-auto-workflow--default-dir)))
         (buffer (generate-new-buffer " *git-worktree-list*"))
         (entries nil)
         (suffix (gptel-auto-workflow--experiment-suffix))
         (branch-pattern
          (format "\\`optimize/.+-%s\\(?:-r[[:alnum:]]+\\)?-exp[0-9]+\\'"
                  (regexp-quote suffix))))
    (unwind-protect
        (when (= 0 (call-process "git" nil buffer nil "worktree" "list" "--porcelain"))
          (with-current-buffer buffer
            (dolist (entry (split-string (buffer-string) "\n\n+" t))
              (let (path branch)
                (when (string-match "^worktree \\(.*\\)$" entry)
                  (setq path (match-string 1 entry)))
                (when (string-match "^branch refs/heads/\\(optimize/.+\\)$" entry)
                  (setq branch (match-string 1 entry)))
                (when (and path branch
                           (string-match-p branch-pattern branch))
                  (push (list :branch branch :path path) entries))))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))
    (nreverse entries)))

(defun gptel-auto-workflow--optimize-branches (&optional proj-root)
  "Return local optimize branches for the current host within PROJ-ROOT."
  (let* ((default-directory (or proj-root (gptel-auto-workflow--default-dir)))
         (buffer (generate-new-buffer " *git-optimize-branches*"))
         (entries nil)
         (suffix (gptel-auto-workflow--experiment-suffix))
         (branch-pattern
          (format "\\`optimize/.+-%s\\(?:-r[[:alnum:]]+\\)?-exp[0-9]+\\'"
                  (regexp-quote suffix))))
    (unwind-protect
        (when (= 0 (call-process "git" nil buffer nil
                                 "for-each-ref"
                                 "--format=%(refname:short)"
                                 "refs/heads/optimize"))
          (with-current-buffer buffer
            (dolist (branch (split-string (buffer-string) "\n" t))
              (when (string-match-p branch-pattern branch)
                (push branch entries)))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))
    (nreverse entries)))

(defun gptel-auto-workflow--remote-tracking-optimize-branches (&optional proj-root)
  "Return local tracking refs for shared remote optimize branches within PROJ-ROOT."
  (let* ((default-directory (or proj-root (gptel-auto-workflow--default-dir)))
         (remote (gptel-auto-workflow--shared-remote))
         (tracking-prefix (format "refs/remotes/%s/optimize" remote)))
    (if (not (file-directory-p default-directory))
        nil
      (let ((result
             (gptel-auto-workflow--git-result
              (format "git for-each-ref --format=%%(refname:short) %s" tracking-prefix)
              60)))
        (when (= 0 (cdr result))
          (split-string (string-trim-right (or (car result) "")) "\n" t))))))

(provide 'gptel-tools-agent-subagent)
;;; gptel-tools-agent-subagent.el ends here
