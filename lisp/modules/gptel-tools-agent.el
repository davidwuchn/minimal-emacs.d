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

(defcustom my/gptel-subagent-model 'glm-4.7
  "Model to use for delegated subagents.
Should be a non-reasoning model to avoid streaming parse failures.
qwen3.5-plus and glm-5 always emit thinking tokens that break the stream
parser; glm-4.7 on DashScope is a plain completion model without reasoning."
  :type '(choice (const :tag "Same as parent" nil) symbol)
  :group 'gptel-tools-agent)

(defcustom my/gptel-subagent-backend 'gptel--dashscope
  "Backend for delegated subagents."
  :type '(choice (const :tag "Same as parent" nil) variable)
  :group 'gptel-tools-agent)

;;; Internal Variables

(defvar my/gptel--in-subagent-task nil
  "Non-nil while inside a `gptel-agent--task' call.")

;;; Context Builder

(defun my/gptel--build-subagent-context (prompt files include-history include-diff &optional origin-buf)
  "Package context for a subagent payload.
Appends contents of FILES, git diff if INCLUDE-DIFF, and recent buffer history
if INCLUDE-HISTORY to the base PROMPT.

ORIGIN-BUF is the parent chat buffer to read history from.  Defaults to
`current-buffer' if not provided, but callers should always pass it
explicitly to avoid capturing the wrong buffer."
  (let ((context ""))
    (when (and files (sequencep files))
      (let ((file-context ""))
        (cl-loop for f in (append files nil) do
                 (let ((filepath (expand-file-name f)))
                   (if (file-readable-p filepath)
                       (with-temp-buffer
                         (insert-file-contents filepath)
                         (setq file-context (concat file-context (format "<file path=\"%s\">\n%s\n</file>\n" f (buffer-string)))))
                     (setq file-context (concat file-context (format "<file path=\"%s\">\n[Error: File not found or not readable]\n</file>\n" f))))))
        (when (not (string-empty-p file-context))
          (setq context (concat context "<files>\n" file-context "</files>\n\n")))))

    (when include-diff
      (let* ((default-directory (or (and (fboundp 'project-current)
                                         (project-current)
                                         (project-root (project-current)))
                                    default-directory))
             (diff-out (with-temp-buffer
                         (call-process "git" nil t nil "diff" "HEAD")
                         (buffer-string))))
        (when (not (string-empty-p diff-out))
          (setq context (concat context "<git_diff>\n" diff-out "\n</git_diff>\n\n")))))

    (when include-history
      (let* ((src-buf (or (and (buffer-live-p origin-buf) origin-buf)
                          (current-buffer)))
             (history-text (with-current-buffer src-buf
                             (buffer-substring-no-properties
                              (max (point-min) (- (point-max) 8000))
                              (point-max)))))
        (when (not (string-empty-p history-text))
          (setq context (concat context "<parent_conversation_history>\n" history-text "\n</parent_conversation_history>\n\n")))))

    (if (string-empty-p context)
        prompt
      (concat context "Task:\n" prompt))))

;;; Subagent Functions

(defun my/gptel--agent-task-with-timeout (callback agent-type description prompt &optional files include-history include-diff)
  "Wrapper around `gptel-agent--task' that adds a timeout and progress messages.

CALLBACK is called with the result or a timeout error."
  (let* ((done nil)
         (timeout-timer nil)
         (progress-timer nil)
         (start-time (current-time))
         (parent-fsm (buffer-local-value 'gptel--fsm-last (current-buffer)))
         (origin-buf (current-buffer))
         (packaged-prompt (my/gptel--build-subagent-context prompt files include-history include-diff origin-buf))
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
               ;; Restore parent FSM reference so the parent buffer is still usable.
               ;; Do NOT call my/gptel-abort-here here — that would kill the parent's
               ;; own curl process, aborting the parent request that is waiting on us.
               ;; The subagent's curl process will clean up on its own via its sentinel.
               (when (buffer-live-p origin-buf)
                 (with-current-buffer origin-buf
                   (setq-local gptel--fsm-last parent-fsm)))
               (funcall callback
                        (format "Error: Task \"%s\" (%s) timed out after %ds."
                                description agent-type my/gptel-agent-task-timeout))))))
    (gptel-agent--task wrapped-cb agent-type description packaged-prompt)))

(cl-defun my/gptel--run-agent-tool (callback agent-name description prompt &optional files include-history include-diff)
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
  (my/gptel--agent-task-with-timeout callback agent-name description prompt files include-history include-diff))

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
              :optional t
              :description "Optional list of file paths to inject into the subagent context.")
             (:name "include_history"
              :type boolean
              :optional t
              :description "If true, injects recent conversation history into subagent context.")
             (:name "include_diff"
              :type boolean
              :optional t
              :description "If true, injects git diff HEAD into subagent context."))
     :category "gptel-agent"
     :async t
     :confirm t
     :include t)))

;;; Footer

(provide 'gptel-tools-agent)

;;; gptel-tools-agent.el ends here
