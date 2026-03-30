;;; gptel-ext-fsm.el --- FSM error recovery workarounds -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Commentary:
;; Defensive workarounds for gptel FSM edge cases.
;; Core FSM fixes are now in gptel-agent-tools.el:
;; - Stuck FSM fix (gptel--fix-stuck-fsm)
;; - Error display fix (gptel-agent--fix-error-display)
;; - Status update handlers (gptel--update-wait, gptel--update-tool-call)

;;; Code:

(require 'gptel)
(require 'gptel-ext-fsm-utils)

(defgroup gptel-fsm nil
  "FSM error recovery workarounds."
  :group 'gptel)

(defvar my/gptel--recovery-count 0
  "Count of FSM recoveries this session.")

;;; --- Log subagent errors loudly but ALWAYS call main-cb ---

(with-eval-after-load 'gptel-agent-tools
  (advice-add 'gptel-agent--task :around
              (lambda (orig main-cb agent-type desc prompt)
                (let* ((new-cb (lambda (result)
                                 (when (and (stringp result)
                                            (string-match-p "^Error: Task" result))
                                   (message "[gptel-fsm] subagent '%s' error: %s"
                                            agent-type result))
                                 (when (functionp main-cb)
                                   (funcall main-cb result)))))
                  (condition-case err
                      (funcall orig new-cb agent-type desc prompt)
                    (error
                     (let ((err-msg (format "Error: Task '%s' failed: %s"
                                            agent-type (error-message-string err))))
                       (message "[gptel-fsm] %s" err-msg)
                       (when (functionp main-cb)
                         (funcall main-cb err-msg)))))))))

;;; --- Recover FSM from error+STOP limbo ---

(defun my/gptel--fsm-needs-recovery-p (fsm info)
  "Return non-nil if FSM needs recovery from error+STOP limbo.

ASSUMPTION: FSM is a valid gptel-fsm struct.
ASSUMPTION: INFO is the plist from (gptel-fsm-info FSM).
BEHAVIOR: Returns t if FSM has error + STOP but is not in DONE state.
BEHAVIOR: Returns nil if any condition is not met.
EDGE CASE: Nil FSM returns nil.
EDGE CASE: Nil INFO returns nil.
EDGE CASE: Missing :buffer plist key returns nil.
EDGE CASE: Dead buffer returns nil.
EDGE CASE: Missing error message returns nil.
EDGE CASE: STOP reason not 'STOP returns nil.
EDGE CASE: FSM already in DONE state returns nil.
TEST: (my/gptel--fsm-needs-recovery-p nil nil) => nil
TEST: (my/gptel--fsm-needs-recovery-p fsm info-with-error+stop+not-done) => t
TEST: (my/gptel--fsm-needs-recovery-p fsm info-without-error) => nil

BUILDS ON DISCOVERY: Extracting validation logic enables reuse
and makes the recovery condition explicit and testable.

ADAPTS TO: Centralizes recovery decision logic for consistency.

PROACTIVE MITIGATION: Prevents recovery attempts on invalid FSMs."
  (when (and fsm info (listp info) (plist-member info :buffer))
    (let* ((fsm-buffer (plist-get info :buffer))
           (error-msg (plist-get info :error))
           (stop-reason (plist-get info :stop-reason))
           (fsm-state (gptel-fsm-state fsm)))
      (and fsm-buffer
           (buffer-live-p fsm-buffer)
           error-msg
           (eq stop-reason 'STOP)
           fsm-state
           (not (eq fsm-state 'DONE))))))

(defun my/gptel--recover-fsm-on-error (_start _end)
  "Force FSM to DONE state if it has error + STOP but is still cycling.
START and END are the response positions (ignored).
Only operates on FSMs with a live buffer."
  (when (boundp 'gptel--fsm-last)
    (let* ((fsm (my/gptel--coerce-fsm gptel--fsm-last))
           (info (and fsm (gptel-fsm-info fsm))))
      (when (my/gptel--fsm-needs-recovery-p fsm info)
        (cl-incf my/gptel--recovery-count)
        (when (> my/gptel--recovery-count 3)
          (message "[gptel-fsm] WARNING: %d FSM recoveries this session"
                   my/gptel--recovery-count))
        (setf (gptel-fsm-state fsm) 'DONE)
        (force-mode-line-update t)))))

(add-hook 'gptel-post-response-functions #'my/gptel--recover-fsm-on-error)

(provide 'gptel-ext-fsm)
;;; gptel-ext-fsm.el ends here
