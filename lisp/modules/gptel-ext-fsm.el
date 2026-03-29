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

(defun my/gptel--recover-fsm-on-error (_start _end)
  "Force FSM to DONE state if it has error + STOP but is still cycling.
START and END are the response positions (ignored).
Only operates on FSMs with a live buffer."
  (when (boundp 'gptel--fsm-last)
    (let* ((fsm (my/gptel--coerce-fsm gptel--fsm-last))
           (info (and fsm (gptel-fsm-info fsm))))
      (when (and info (listp info))
        (let* ((fsm-buffer (plist-get info :buffer))
               (error-msg (plist-get info :error))
               (stop-reason (plist-get info :stop-reason)))
          (when (and fsm-buffer
                     (buffer-live-p fsm-buffer)
                     error-msg
                     (eq stop-reason 'STOP)
                     (not (eq (gptel-fsm-state fsm) 'DONE)))
            (cl-incf my/gptel--recovery-count)
            (when (> my/gptel--recovery-count 3)
              (message "[gptel-fsm] WARNING: %d FSM recoveries this session"
                       my/gptel--recovery-count))
            (setf (gptel-fsm-state fsm) 'DONE)
            (force-mode-line-update t)))))))

(add-hook 'gptel-post-response-functions #'my/gptel--recover-fsm-on-error)

(provide 'gptel-ext-fsm)
;;; gptel-ext-fsm.el ends here
