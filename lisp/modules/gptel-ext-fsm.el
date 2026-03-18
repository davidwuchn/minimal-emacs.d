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
  (add-to-list 'gptel-agent-request--handlers '(DONE . (gptel--handle-post)))
  (add-to-list 'gptel-agent-request--handlers '(ERRS . (gptel--handle-post)))
  (add-to-list 'gptel-agent-request--handlers '(ABRT . (gptel--handle-post)))
  ;; TRET handler for tool result (gptel-agent compatibility)
  (unless (assoc 'TRET gptel-agent-request--handlers)
    (add-to-list 'gptel-agent-request--handlers 
                 '(TRET . (gptel--handle-post-tool gptel--handle-tool-result))))

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
This handles the case where malformed JSON leaves FSM in limbo."
  (when (boundp 'gptel--fsm-last)
    (let* ((fsm (my/gptel--coerce-fsm gptel--fsm-last))
           (info (and fsm (gptel-fsm-info fsm)))
           (error-msg (plist-get info :error))
           (stop-reason (plist-get info :stop-reason)))
      (when (and error-msg
                 (eq stop-reason 'STOP)
                 (not (eq (gptel-fsm-state fsm) 'DONE)))
        (message "gptel: Recovering FSM from error state: %s" error-msg)
        ;; Force state to DONE to unstick the UI
        (setf (gptel-fsm-state fsm) 'DONE)
        ;; Clear the in-progress indicator
        (force-mode-line-update t)))))

(add-hook 'gptel-post-response-functions #'my/gptel--recover-fsm-on-error)

(provide 'gptel-ext-fsm)
;;; gptel-ext-fsm.el ends here
