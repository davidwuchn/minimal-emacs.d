;;; gptel-ext-fsm.el --- FSM error recovery and agent handler fixes -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Commentary:
;; Workarounds for gptel FSM getting stuck:
;; - Fix FSM stuck in TYPE state when curl fails before headers
;; - Recover FSM from error+STOP limbo state
;; 
;; NOTE: DONE/ERRS/ABRT handlers are now included upstream in gptel-agent-tools.el
;; Requires: gptel-agent-tools >= 0.3.0 (for handler support)

;;; Code:

(require 'gptel)
(require 'gptel-ext-fsm-utils)

(defvar gptel-agent-request--handlers)

;;; Customization

(defgroup gptel-fsm nil
  "FSM error recovery and status display."
  :group 'gptel)

(defcustom my/gptel-fsm-status-update-delay 0.1
  "Delay in seconds before updating status after tool result.
Allows FSM transition to complete before UI update."
  :type 'number
  :group 'gptel-fsm)

(defcustom my/gptel-error-display-max-length 50
  "Maximum characters to display in error status.
Longer messages are truncated with '...'."
  :type 'integer
  :group 'gptel-fsm)

;;; State Tracking

(defvar my/gptel--recovery-count 0
  "Count of FSM recoveries this session.")

(defvar-local my/gptel--status-timer nil
  "Buffer-local timer for status updates.")

(defun my/gptel--cancel-status-timer ()
  "Cancel any pending status update timer."
  (when my/gptel--status-timer
    (cancel-timer my/gptel--status-timer)
    (setq my/gptel--status-timer nil)))

;;; --- FSM Error Recovery ---

(defun my/gptel-fix-fsm-stuck-in-type (orig-fn process status)
  "Fix gptel streaming FSM getting stuck when curl fails before headers.
If curl exits before sending HTTP headers, `gptel-curl--stream-filter`
never transitions the FSM from WAIT to TYPE. Then the cleanup sentinel
transitions it from WAIT to TYPE, leaving it stuck in TYPE forever.
This advice forces the final transition."
  (let* ((fsm (car (alist-get process (bound-and-true-p gptel--request-alist))))
         (state-before (and fsm (gptel-fsm-state fsm))))
    (funcall orig-fn process status)
    (when (and fsm
               (eq (gptel-fsm-state fsm) 'TYPE)
               (not (eq state-before 'TYPE)))
      (message "[gptel-fsm] Unsticking FSM from TYPE -> next state (curl failed early)")
      (gptel--fsm-transition fsm))))

(advice-add 'gptel-curl--stream-cleanup :around #'my/gptel-fix-fsm-stuck-in-type)

;;; --- Log subagent errors loudly but ALWAYS call main-cb ---

(with-eval-after-load 'gptel-agent-tools
  (advice-add 'gptel-agent--task :around
              (lambda (orig main-cb agent-type desc prompt)
                (let* ((new-cb (lambda (result)
                                 (when (and (stringp result)
                                            (string-match-p "^Error: Task" result))
                                   (message "[gptel-fsm] subagent '%s' error: %s"
                                            agent-type result))
                                 (funcall main-cb result))))
                  (condition-case err
                      (funcall orig new-cb agent-type desc prompt)
                    (error
                     (let ((err-msg (format "Error: Task '%s' failed: %s"
                                            agent-type (error-message-string err))))
                       (message "[gptel-fsm] %s" err-msg)
                       (funcall main-cb err-msg))))))))

;;; --- Recover FSM from error+STOP limbo ---

(defun my/gptel--recover-fsm-on-error (_start _end)
  "Force FSM to DONE state if it has error + STOP but is still cycling.
START and END are the response positions (ignored).
Only operates on FSMs belonging to the current buffer."
  (when (boundp 'gptel--fsm-last)
    (let* ((fsm (my/gptel--coerce-fsm gptel--fsm-last))
           (info (and fsm (gptel-fsm-info fsm)))
           (fsm-buffer (plist-get info :buffer))
           (error-msg (plist-get info :error))
           (stop-reason (plist-get info :stop-reason)))
      (when (and fsm-buffer
                 (buffer-live-p fsm-buffer)
                 (eq (current-buffer) fsm-buffer)
                 error-msg
                 (eq stop-reason 'STOP)
                 (not (eq (gptel-fsm-state fsm) 'DONE)))
        (cl-incf my/gptel--recovery-count)
        (when (> my/gptel--recovery-count 3)
          (message "[gptel-fsm] WARNING: %d FSM recoveries this session — possible systemic issue"
                   my/gptel--recovery-count))
        (setf (gptel-fsm-state fsm) 'DONE)
        (force-mode-line-update t)))))

(add-hook 'gptel-post-response-functions #'my/gptel--recover-fsm-on-error)

;;; --- Fix Status Not Updating After Tool Results ---

(defun my/gptel--update-status-on-wait-entry (orig-fn machine &optional new-state)
  "Update status to 'Waiting...' when FSM transitions to WAIT state.
ORIG-FN is gptel--fsm-transition. MACHINE is the FSM. NEW-STATE is optional."
  (funcall orig-fn machine new-state)
  (let ((target-state (or new-state (gptel-fsm-state machine))))
    (when (eq target-state 'WAIT)
      (when-let* ((info (gptel-fsm-info machine))
                  (buf (plist-get info :buffer)))
        (when (buffer-live-p buf)
          (with-current-buffer buf
            (when (bound-and-true-p gptel-mode)
              (gptel--update-status " Waiting..." 'warning))))))))

(advice-add 'gptel--fsm-transition :around #'my/gptel--update-status-on-wait-entry)

(defun my/gptel--update-status-after-tool-result (fsm)
  "Update status after tool result is processed.
FSM is the state machine. Runs as :after advice on gptel--handle-tool-result.
Cancels any previous timer to prevent memory leaks from killed buffers."
  (when-let* ((info (gptel-fsm-info fsm))
              (buf (plist-get info :buffer)))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (when (bound-and-true-p gptel-mode)
          (my/gptel--cancel-status-timer)
          (setq my/gptel--status-timer
                (run-with-timer my/gptel-fsm-status-update-delay nil
                  (lambda (b)
                    (when (buffer-live-p b)
                      (with-current-buffer b
                        (when (bound-and-true-p gptel-mode)
                          (gptel--update-status " Waiting..." 'warning)))))
                  buf)))))))

(advice-add 'gptel--handle-tool-result :after #'my/gptel--update-status-after-tool-result)

;;; --- Fix Error Display in Header-Line ---

(defun my/gptel--fix-error-display (fsm)
  "Fix header-line to show actual error instead of HTTP status.
FSM is the state machine. Called after gptel--handle-error."
  (when-let* ((info (gptel-fsm-info fsm))
              (error-data (plist-get info :error))
              (gptel-buffer (plist-get info :buffer)))
    (when (and error-data (buffer-live-p gptel-buffer))
      (with-current-buffer gptel-buffer
        (when (bound-and-true-p gptel-mode)
          (let* ((error-str (if (stringp error-data)
                                (string-trim error-data)
                              (or (plist-get error-data :message)
                                  (plist-get error-data :type)
                                  "Unknown error")))
                 (max-len my/gptel-error-display-max-length)
                 (short-error (if (> (length error-str) max-len)
                                  (concat (substring error-str 0 (- max-len 3)) "...")
                                error-str)))
            (gptel--update-status
             (format " Error: %s" short-error) 'error)))))))

(advice-add 'gptel--handle-error :after #'my/gptel--fix-error-display)

;;; --- Cleanup on Buffer Kill ---

(add-hook 'kill-buffer-hook #'my/gptel--cancel-status-timer)

(provide 'gptel-ext-fsm)
;;; gptel-ext-fsm.el ends here