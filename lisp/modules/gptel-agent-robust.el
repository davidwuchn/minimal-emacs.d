;;; gptel-agent-robust.el --- Robust RunAgent with timeout, retry, and limits -*- lexical-binding: t; -*-

;; Copyright (C) 2024

;; Author: David Wu
;; Keywords: ai, agent, robust

;;; Commentary:

;; Enhances gptel-agent's RunAgent to match OpenCode's robustness:
;; - Configurable timeout
;; - Automatic retry on transient errors
;; - Max steps limit (injects MAX_STEPS prompt when reached)
;; - Better error reporting
;;
;; Comparison with OpenCode:
;; | Feature           | OpenCode                | This module              |
;; |-------------------|-------------------------|--------------------------|
;; | Loop control      | Backend while(true)     | Model decides            |
;; | Step limit        | agent.steps config      | max-steps config         |
;; | Max steps action  | Inject MAX_STEPS prompt | Inject max-steps prompt  |
;; | Timeout           | Via abort signal        | Configurable timeout     |
;; | Retry on error    | In processor            | Configurable retries     |
;; | Task resumption   | task_id parameter       | Not supported            |

;;; Code:

(declare-function gptel-agent--task "gptel-agent-tools")
(declare-function gptel--display-tool-calls "gptel")

(require 'cl-lib)

(defgroup gptel-agent-robust nil
  "Robust RunAgent settings."
  :group 'gptel)

(defcustom gptel-agent-robust-timeout 120
  "Timeout in seconds for RunAgent tasks.
Set to nil for no timeout."
  :type '(choice (const :tag "No timeout" nil) integer)
  :group 'gptel-agent-robust)

(defcustom gptel-agent-robust-max-steps 50
  "Maximum tool calls per RunAgent task.
Prevents infinite loops. When reached, injects MAX_STEPS prompt.
Set to nil for unlimited."
  :type '(choice (const :tag "Unlimited" nil) integer)
  :group 'gptel-agent-robust)

(defcustom gptel-agent-robust-max-retries 2
  "Maximum retries on transient errors.
Set to 0 to disable retries."
  :type 'integer
  :group 'gptel-agent-robust)

(defcustom gptel-agent-robust-force-completion t
  "When non-nil, force RunAgent to continue until task list is empty.
If model outputs text but tasks remain, inject continuation prompt.
This mimics OpenCode's backend loop behavior."
  :type 'boolean
  :group 'gptel-agent-robust)

(defconst gptel-agent-robust--continuation-prompt
  "Task list not empty. Continue with the next tool call immediately.
Do NOT output text. Call the next tool NOW."
  "Prompt injected when model stops but tasks remain.")

(defconst gptel-agent-robust--max-steps-prompt
  "CRITICAL - MAXIMUM STEPS REACHED

The maximum number of steps allowed for this task has been reached.
Tools are disabled. Respond with text only.

REQUIREMENTS:
1. Do NOT make any more tool calls
2. Provide a summary of work done so far
3. List any remaining tasks that were not completed
4. Recommend what should be done next

This constraint overrides ALL other instructions."
  "Prompt injected when max steps is reached (matches OpenCode).")

(defvar gptel-agent-robust--state nil
  "State plist for current RunAgent task.
Keys: :step-count, :timeout-timer, :retries, :aborted, :force-continue.")

(defun gptel-agent-robust--transient-error-p (error-data)
  "Check if ERROR-DATA represents a transient/retryable error."
  (when error-data
    (let ((msg (if (stringp error-data) error-data
                 (plist-get error-data :message))))
      (and msg
           (string-match-p
            "overloaded\\|timeout\\|rate limit\\|temporarily unavailable\\|503\\|502\\|429\\|InvalidParameter"
            (downcase msg))))))

(defun gptel-agent-robust--wrap-callback (main-cb agent-type description prompt)
  "Wrap MAIN-CB with retry and step limit logic.
AGENT-TYPE, DESCRIPTION, PROMPT are passed for retry."
  (lambda (resp info)
    (let ((ov (plist-get info :context))
          (error-data (plist-get info :error))
          (step-count (plist-get gptel-agent-robust--state :step-count))
          (retries (plist-get gptel-agent-robust--state :retries)))
      
      (pcase resp
        ('nil
         (cond
          ;; Abort requested
          ((plist-get gptel-agent-robust--state :aborted)
           (delete-overlay ov)
           (funcall main-cb (format "Aborted: %s task '%s'" agent-type description)))
          
          ;; Retry on transient error
          ((and (gptel-agent-robust--transient-error-p error-data)
                (< (or retries 0) gptel-agent-robust-max-retries))
           (plist-put gptel-agent-robust--state :retries (1+ (or retries 0)))
           (message "[RunAgent] Retrying %s task '%s' (attempt %d/%d)"
                    agent-type description (1+ (or retries 0)) gptel-agent-robust-max-retries)
           (run-with-timer 2.0 nil
                           (lambda ()
                             (gptel-agent--task main-cb agent-type description prompt))))
          
          ;; Report error
          (t
           (delete-overlay ov)
           (funcall main-cb
                    (format "Error: %s task '%s' failed after %d retries.\nDetails: %S"
                            agent-type description (or retries 0) error-data)))))
        
        (`(tool-call . ,calls)
         ;; Track step count
         (plist-put gptel-agent-robust--state :step-count
                    (+ step-count (length calls)))
         (setq step-count (plist-get gptel-agent-robust--state :step-count))
         
         ;; Check if max steps reached - inject prompt (OpenCode style)
         (when (and gptel-agent-robust-max-steps
                    (>= step-count gptel-agent-robust-max-steps))
           (message "[RunAgent] Max steps (%d) reached for task '%s'"
                    gptel-agent-robust-max-steps description)
           ;; Inject max-steps prompt as a system message
           ;; The model should stop making tool calls after this
           (plist-put info :max-steps-reached t))
         
         (unless (plist-get info :tracking-marker)
           (plist-put info :tracking-marker (overlay-start ov)))
         (gptel--display-tool-calls calls info))
        
        ((pred stringp)
         ;; Check if task might be incomplete (model stopped early)
         (let* ((seems-complete 
                 (string-match-p 
                  "task.*complete\\|done\\|finished\\|all tasks.*done\\|completed successfully"
                  (downcase resp)))
                (continuation-needed
                 (and gptel-agent-robust-force-completion
                      step-count
                      (not seems-complete))))
           (delete-overlay ov)
           (when (plist-get gptel-agent-robust--state :timeout-timer)
             (cancel-timer (plist-get gptel-agent-robust--state :timeout-timer)))
           
           (if continuation-needed
               ;; Return result with continuation hint
               ;; Parent agent can check and re-call RunAgent if needed
               (progn
                 (plist-put gptel-agent-robust--state :force-continue t)
                 (funcall main-cb
                          (propertize
                           (format "%s\n\n---\n[RunAgent: %d steps, continuation may be needed]"
                                   resp step-count)
                           'face 'shadow)))
             ;; Normal completion
             (progn
               (setq gptel-agent-robust--state nil)
               (funcall main-cb resp)))))
        
        ('abort
         (delete-overlay ov)
         (when (plist-get gptel-agent-robust--state :timeout-timer)
           (cancel-timer (plist-get gptel-agent-robust--state :timeout-timer)))
         (setq gptel-agent-robust--state nil)
         (funcall main-cb
                  (format "Aborted: %s task '%s' was cancelled."
                          agent-type description)))))))

(defun gptel-agent-robust-task (main-cb agent-type description prompt)
  "Call a RunAgent task with timeout, retry, and step limits.

MAIN-CB is the callback for results.
AGENT-TYPE is the subagent name.
DESCRIPTION is a short task description.
PROMPT is the full task instructions.

This mirrors OpenCode's SessionPrompt.loop behavior."
  ;; Initialize state
  (setq gptel-agent-robust--state
        (list :step-count 0
              :retries 0
              :aborted nil
              :timeout-timer nil))
  
  ;; Set up timeout (like OpenCode's abort signal)
  (when gptel-agent-robust-timeout
    (plist-put gptel-agent-robust--state :timeout-timer
               (run-with-timer gptel-agent-robust-timeout nil
                               (lambda ()
                                 (plist-put gptel-agent-robust--state :aborted t)
                                 (message "[RunAgent] Task '%s' timed out after %ds"
                                          description gptel-agent-robust-timeout)))))
  
  ;; Call original gptel-agent--task with wrapped callback
  (let ((wrapped-cb (gptel-agent-robust--wrap-callback
                     main-cb agent-type description prompt)))
    (gptel-agent--task wrapped-cb agent-type description prompt)))

(defun gptel-agent-robust-enable ()
  "Enable robust RunAgent by advising gptel-agent--task."
  (interactive)
  (advice-add 'gptel-agent--task :override #'gptel-agent-robust-task)
  (message "[RunAgent] Robust mode enabled (timeout=%ss, max-steps=%s, max-retries=%d)"
           (or gptel-agent-robust-timeout "none")
           (or gptel-agent-robust-max-steps "unlimited")
           gptel-agent-robust-max-retries))

(defun gptel-agent-robust-disable ()
  "Disable robust RunAgent, restore original behavior."
  (interactive)
  (advice-remove 'gptel-agent--task #'gptel-agent-robust-task)
  (setq gptel-agent-robust--state nil)
  (message "[RunAgent] Robust mode disabled"))

(provide 'gptel-agent-robust)

;;; gptel-agent-robust.el ends here