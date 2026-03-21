;;; gptel-ext-fsm.el --- FSM error recovery and agent handler fixes -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Commentary:
;; Workarounds for gptel FSM getting stuck:
;; - Fix FSM stuck in TYPE state when curl fails before headers
;; - Add missing DONE/ERRS/ABRT handlers to gptel-agent-request--handlers
;; - Recover FSM from error+STOP limbo state

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

;; --- Fix gptel-agent Missing FSM Handlers ---
;; `gptel-agent` defines its own handlers for background tasks but forgets to
;; include DONE, ERRS, and ABRT! This causes background agents to hang forever
;; on errors or completion because the cleanup callback is never called.

(with-eval-after-load 'gptel-agent-tools
  (add-to-list 'gptel-agent-request--handlers '(DONE gptel--handle-post-insert gptel--fsm-last))
  (add-to-list 'gptel-agent-request--handlers '(ERRS gptel--handle-error gptel--fsm-last))
  (add-to-list 'gptel-agent-request--handlers '(ABRT gptel--handle-abort gptel--fsm-last))

  ;; Log subagent errors loudly but ALWAYS call main-cb so the parent FSM can
  ;; continue.  The old implementation swallowed the callback when the result
  ;; matched "^Error: Task", leaving the parent tool-call result pending forever
  ;; and causing the parent FSM to hang.
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
;; stays as "Calling tool..." because there's no handler to update it.
;; This advice updates status to " Waiting..." after tool results are processed.

(defun my/gptel--update-status-after-tool-result (fsm)
  "Update status to 'Waiting...' after tool results are processed.
FSM is the state machine."
  (when-let* ((info (gptel-fsm-info fsm))
              (buf (plist-get info :buffer)))
    (when (buffer-live-p buf)
      (with-current-buffer buf
        (when (bound-and-true-p gptel-mode)
          (gptel--update-status " Waiting..." 'warning))))))

(advice-add 'gptel--handle-tool-result :after #'my/gptel--update-status-after-tool-result)

(provide 'gptel-ext-fsm)
;;; gptel-ext-fsm.el ends here
