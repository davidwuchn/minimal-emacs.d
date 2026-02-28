;;; gptel-tools-agent.el --- Subagent delegation for gptel -*- lexical-binding: t; -*-

;; Author: David Wu
;; Version: 1.0.0
;;
;; Subagent delegation with timeout and model override.

(require 'cl-lib)
(require 'subr-x)

;;; Customization

(defgroup gptel-tools-agent nil
  "Subagent delegation for gptel-agent."
  :group 'gptel)

(defcustom my/gptel-agent-task-timeout 120
  "Seconds before a delegated Agent/RunAgent task is force-stopped."
  :type 'integer
  :group 'gptel-tools-agent)

(defcustom my/gptel-subagent-model 'kimi-k2.5
  "Model to use for delegated subagents.
When non-nil, subagent requests use this model instead of the parent's."
  :type '(choice (const :tag "Same as parent" nil) symbol)
  :group 'gptel-tools-agent)

(defcustom my/gptel-subagent-backend 'gptel--moonshot
  "Backend for delegated subagents."
  :type '(choice (const :tag "Gemini (default)" nil) variable)
  :group 'gptel-tools-agent)

;;; Internal Variables

(defvar my/gptel--in-subagent-task nil
  "Non-nil while inside a `gptel-agent--task' call.")

;;; Subagent Functions

(defun my/gptel--agent-task-override-model (orig &rest args)
  "Around-advice for `gptel-agent--task': override model/backend for subagents."
  (let* ((my/gptel--in-subagent-task t)
         (gptel-model (if my/gptel-subagent-model
                          (if (stringp my/gptel-subagent-model)
                              (intern my/gptel-subagent-model)
                            my/gptel-subagent-model)
                        gptel-model))
         (gptel-backend (if my/gptel-subagent-model
                            (let ((b my/gptel-subagent-backend))
                              (or (and (symbolp b) (boundp b) (symbol-value b))
                                  b
                                  (and (boundp 'gptel--minimax) gptel--minimax)
                                  gptel-backend))
                          gptel-backend)))
    (when my/gptel-subagent-model
      (message "gptel subagent: using %s/%s"
               (gptel-backend-name gptel-backend) gptel-model))
    (apply orig args)))

(defun my/gptel--agent-task-with-timeout (callback agent-type description prompt)
  "Wrapper around `gptel-agent--task' that adds a timeout and progress messages.

CALLBACK is called with the result or a timeout error."
  (let* ((done nil)
         (timeout-timer nil)
         (progress-timer nil)
         (start-time (current-time))
         (parent-fsm (buffer-local-value 'gptel--fsm-last (current-buffer)))
         (origin-buf (current-buffer))
         (wrapped-cb
          (lambda (result)
            (unless done
              (setq done t)
              (when (timerp timeout-timer) (cancel-timer timeout-timer))
              (when (timerp progress-timer) (cancel-timer progress-timer))
              (message "[nucleus] Subagent '%s' completed in %.1fs"
                       agent-type (float-time (time-since start-time)))
              (when (buffer-live-p origin-buf)
                (with-current-buffer origin-buf
                  (setq-local gptel--fsm-last parent-fsm))
                (setq-local gptel--fsm-last parent-fsm))
              (funcall callback result)))))

    (message "[nucleus] Delegating to subagent '%s' (timeout: %ds)..."
             agent-type my/gptel-agent-task-timeout)

    (setq progress-timer
          (run-at-time 10 10
           (lambda ()
             (unless done
               (message "[nucleus] Subagent '%s' still running... (%.1fs elapsed)"
                        agent-type (float-time (time-since start-time)))))))

    (setq timeout-timer
          (run-at-time
           my/gptel-agent-task-timeout nil
           (lambda ()
             (unless done
               (setq done t)
               (when (timerp progress-timer) (cancel-timer progress-timer))
               (message "[nucleus] Subagent '%s' timed out after %ds"
                        agent-type my/gptel-agent-task-timeout)
               (when (buffer-live-p origin-buf)
                 (with-current-buffer origin-buf
                   (let ((my/gptel--abort-generation (1+ my/gptel--abort-generation)))
                     (my/gptel-abort-here))
                   (setq-local gptel--fsm-last parent-fsm))
                 (setq-local gptel--fsm-last parent-fsm))
               (funcall callback
                        (format "Error: Agent task \"%s\" (%s) timed out after %ds."
                                description agent-type my/gptel-agent-task-timeout))))))
    (gptel-agent--task wrapped-cb agent-type description prompt)))

(defun my/gptel--run-agent-tool (callback agent-name description prompt)
  "Run a gptel-agent agent by name.

AGENT-NAME must exist in `gptel-agent--agents`."
  (unless (require 'gptel-agent nil t)
    (funcall callback "Error: gptel-agent is not available")
    (cl-return-from my/gptel--run-agent-tool))
  (unless (and (boundp 'gptel-agent--agents) gptel-agent--agents)
    (ignore-errors (gptel-agent-update)))
  (unless (and (stringp agent-name) (not (string-empty-p (string-trim agent-name))))
    (funcall callback "Error: agent-name is empty")
    (cl-return-from my/gptel--run-agent-tool))
  (unless (assoc agent-name gptel-agent--agents)
    (funcall callback
             (format "Error: unknown agent %S. Known agents: %s"
                     agent-name
                     (string-join (sort (mapcar #'car gptel-agent--agents) #'string<) ", ")))
    (cl-return-from my/gptel--run-agent-tool))
  (unless (fboundp 'gptel-agent--task)
    (funcall callback "Error: gptel-agent task runner not available")
    (cl-return-from my/gptel--run-agent-tool))
  (my/gptel--agent-task-with-timeout callback agent-name description prompt))

;;; Tool Registration

(defun gptel-tools-agent-register ()
  "Register Agent and RunAgent tools with gptel."
  (when (fboundp 'gptel-make-tool)
    ;; Agent tool (delegates to gptel-agent--task)
    (gptel-make-tool
     :name "Agent"
     :description "Run a delegated subagent task."
     :function #'my/gptel--agent-task-with-timeout
     :args '((:name "subagent_type"
              :type string
              :enum ["researcher" "introspector"])
            (:name "description"
              :type string)
            (:name "prompt"
              :type "string"))
     :category "gptel-agent"
     :async t
     :confirm t
     :include t)
    ;; RunAgent tool (run any agent by name)
    (gptel-make-tool
     :name "RunAgent"
     :description "Run a gptel-agent agent by name (e.g. explorer)"
     :function #'my/gptel--run-agent-tool
     :args '((:name "agent-name"
              :type string
              :description "Agent name (from gptel-agent--agents)")
            (:name "description"
              :type string
              :description "Short task label")
            (:name "prompt"
              :type string
              :description "Full task prompt"))
     :category "gptel-agent"
     :async t
     :confirm t
     :include t)))

;;; Footer

(provide 'gptel-tools-agent)

;;; gptel-tools-agent.el ends here
