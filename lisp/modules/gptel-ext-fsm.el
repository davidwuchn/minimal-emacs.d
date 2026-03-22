;;; gptel-ext-fsm.el --- FSM error recovery and agent handler fixes -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Commentary:
;; Workarounds for gptel FSM getting stuck:
;; - Fix FSM stuck in TYPE state when curl fails before headers
;; - Recover FSM from error+STOP limbo state
;; 
;; NOTE: DONE/ERRS/ABRT handlers are now included upstream in gptel-agent-tools.el

;;; Code:

(require 'gptel)
(require 'gptel-ext-fsm-utils)

(defvar gptel-agent-request--handlers) ; defined in gptel-agent-tools.el

;; --- FSM Error Recovery ---
;; Workaround for gptel FSM getting stuck on JSON parsing errors

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
      (message "gptel: Unsticking FSM from TYPE -> next state (curl failed early)")
      (gptel--fsm-transition fsm))))

(advice-add 'gptel-curl--stream-cleanup :around #'my/gptel-fix-fsm-stuck-in-type)

;; --- Log subagent errors loudly but ALWAYS call main-cb ---
;; The old implementation swallowed the callback when the result
;; matched "^Error: Task", leaving the parent tool-call result pending forever
;; and causing the parent FSM to hang.

(with-eval-after-load 'gptel-agent-tools
  (advice-add 'gptel-agent--task :around
              (lambda (orig main-cb agent-type desc prompt)
                (let* ((new-cb (lambda (result)
                                 (when (and (stringp result)
                                            (string-match-p "^Error: Task" result))
                                   (message "[nucleus] subagent '%s' error: %s"
                                            agent-type result))
                                 ;; Always forward to main-cb — the parent FSM
                                 ;; must receive a result to close its tool cycle.
                                 (funcall main-cb result))))
                  (funcall orig new-cb agent-type desc prompt)))))

(defun my/gptel--recover-fsm-on-error (_start _end)
  "Force FSM to DONE state if it has error + STOP but is still cycling.
START and END are the response positions (ignored).
This handles edge cases where FSM gets stuck in limbo after error handling.
Silent by default to avoid duplicate logging with gptel--handle-error."
  (when (boundp 'gptel--fsm-last)
    (let* ((fsm (my/gptel--coerce-fsm gptel--fsm-last))
           (info (and fsm (gptel-fsm-info fsm)))
           (error-msg (plist-get info :error))
           (stop-reason (plist-get info :stop-reason)))
      (when (and error-msg
                 (eq stop-reason 'STOP)
                 (not (eq (gptel-fsm-state fsm) 'DONE)))
        (setf (gptel-fsm-state fsm) 'DONE)
        (force-mode-line-update t)))))

(add-hook 'gptel-post-response-functions #'my/gptel--recover-fsm-on-error)

;; --- Fix Status Not Updating After Tool Results ---
;; When TRET → WAIT transition happens (tool results ready), the status
;; stays as "Calling tool..." because gptel--update-wait is NOT called
;; on TRET → WAIT transitions (only on INIT → WAIT).
;; This advice monitors FSM transitions and updates status when entering WAIT.

(defun my/gptel--update-status-on-wait-entry (orig-fn machine &optional new-state)
  "Update status to 'Waiting...' when FSM transitions to WAIT state.
ORIG-FN is gptel--fsm-transition. MACHINE is the FSM. NEW-STATE is optional.
This is called via :around advice on gptel--fsm-transition."
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

;; Also add to TRET handler for immediate update when tool results are processed
(defun my/gptel--update-status-after-tool-result (fsm)
  "Update status after tool result is processed.
FSM is the state machine. Runs as :after advice on gptel--handle-tool-result."
  (when-let* ((info (gptel-fsm-info fsm))
              (buf (plist-get info :buffer)))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (when (bound-and-true-p gptel-mode)
          ;; Small delay to let the transition complete
          (run-with-timer 0.1 nil
            (lambda (b)
              (when (buffer-live-p b)
                (with-current-buffer b
                  (when (bound-and-true-p gptel-mode)
                    (gptel--update-status " Waiting..." 'warning)))))
            buf))))))

(advice-add 'gptel--handle-tool-result :after #'my/gptel--update-status-after-tool-result)

;; --- Fix Error Display in Header-Line ---
;; gptel--handle-error uses :status (HTTP status line) for header-line display
;; instead of :error (actual error message like "Curl failed with exit code 28").
;; This advice fixes the status display to show the meaningful error.

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
                 (short-error (if (> (length error-str) 50)
                                  (concat (substring error-str 0 47) "...")
                                error-str)))
            (gptel--update-status
             (format " Error: %s" short-error) 'error)))))))

(advice-add 'gptel--handle-error :after #'my/gptel--fix-error-display)

(provide 'gptel-ext-fsm)
;;; gptel-ext-fsm.el ends here
