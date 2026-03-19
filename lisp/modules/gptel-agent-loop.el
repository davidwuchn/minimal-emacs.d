;;; gptel-agent-loop.el --- RunAgent loop control with timeout, retry, and limits -*- lexical-binding: t; -*-

;; Copyright (C) 2024

;; Author: David Wu
;; Keywords: ai, agent, loop

;;; Commentary:

;; RunAgent loop control to match OpenCode's SessionPrompt.loop:
;; - Configurable timeout
;; - Automatic retry on transient errors
;; - Max steps limit (reads from agent YAML: steps: N)
;; - Force continuation until task complete
;;
;; Comparison with OpenCode:
;; | Feature           | OpenCode                | This module              |
;; |-------------------|-------------------------|--------------------------|
;; | Loop control      | Backend while(true)     | Continuation marker      |
;; | Step limit        | agent.steps config      | max-steps config         |
;; | Max steps action  | Inject MAX_STEPS prompt | Mark incomplete          |
;; | Timeout           | Via abort signal        | Configurable timeout     |
;; | Retry on error    | In processor            | Configurable retries     |
;; | Task resumption   | task_id parameter       | Re-call with marker      |

;;; Code:

(declare-function gptel-agent--task "gptel-agent-tools")
(declare-function gptel--display-tool-calls "gptel")

(defvar gptel-agent--agents)  ; Defined in gptel-agent

(require 'cl-lib)

(defgroup gptel-agent-loop nil
  "RunAgent loop control settings."
  :group 'gptel)

(defcustom gptel-agent-loop-timeout 120
  "Timeout in seconds for RunAgent tasks.
Set to nil for no timeout."
  :type '(choice (const :tag "No timeout" nil) integer)
  :group 'gptel-agent-loop)

(defcustom gptel-agent-loop-max-steps 50
  "Maximum tool calls per RunAgent task.
Prevents infinite loops. Set to nil for unlimited.
Can be overridden per-agent via YAML `steps' field."
  :type '(choice (const :tag "Unlimited" nil) integer)
  :group 'gptel-agent-loop)

(defcustom gptel-agent-loop-max-retries 2
  "Maximum retries on transient errors.
Set to 0 to disable retries."
  :type 'integer
  :group 'gptel-agent-loop)

(defcustom gptel-agent-loop-force-completion t
  "When non-nil, force RunAgent to continue until task complete.
If model outputs text but task seems incomplete, auto-invoke continuation.
This mimics OpenCode's backend while(true) loop behavior."
  :type 'boolean
  :group 'gptel-agent-loop)

(defcustom gptel-agent-loop-hard-loop t
  "When non-nil, implement hard loop that auto-continues on incomplete tasks.
Unlike force-completion (which just marks incomplete), this actually
makes another request automatically to continue the task.
This matches OpenCode's backend loop behavior."
  :type 'boolean
  :group 'gptel-agent-loop)

(defconst gptel-agent-loop--continuation-prompt
  "Task list not empty. Continue with the next tool call immediately.
Do NOT output text. Call the next tool NOW."
  "Prompt injected when model stops but tasks remain.")

(defconst gptel-agent-loop--max-steps-prompt
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

(defvar gptel-agent-loop--state nil
  "State plist for current RunAgent task.
Keys: :step-count, :timeout-timer, :retries, :aborted, :max-steps,
:accumulated-output, :agent-type, :description, :main-cb.")

(defun gptel-agent-loop--transient-error-p (error-data)
  "Check if ERROR-DATA represents a transient/retryable error."
  (when error-data
    (let ((msg (if (stringp error-data) error-data
                 (plist-get error-data :message))))
      (and msg
           (string-match-p
            "overloaded\\|timeout\\|rate limit\\|temporarily unavailable\\|503\\|502\\|429\\|InvalidParameter"
            (downcase msg))))))

(defun gptel-agent-loop--wrap-callback (main-cb agent-type description prompt)
  "Wrap MAIN-CB with retry and step limit logic.
AGENT-TYPE, DESCRIPTION, PROMPT are passed for retry."
  (lambda (resp info)
    (let ((ov (plist-get info :context))
          (error-data (plist-get info :error))
          (step-count (plist-get gptel-agent-loop--state :step-count))
          (retries (plist-get gptel-agent-loop--state :retries)))
      
      (pcase resp
        ('nil
         (cond
          ;; Abort requested
          ((plist-get gptel-agent-loop--state :aborted)
           (delete-overlay ov)
           (funcall main-cb (format "Aborted: %s task '%s'" agent-type description)))
          
          ;; Retry on transient error
          ((and (gptel-agent-loop--transient-error-p error-data)
                (< (or retries 0) gptel-agent-loop-max-retries))
           (plist-put gptel-agent-loop--state :retries (1+ (or retries 0)))
           (message "[RunAgent] Retrying %s task '%s' (attempt %d/%d)"
                    agent-type description (1+ (or retries 0)) gptel-agent-loop-max-retries)
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
         (plist-put gptel-agent-loop--state :step-count
                    (+ step-count (length calls)))
         (setq step-count (plist-get gptel-agent-loop--state :step-count))
         
         ;; Check if max steps reached (OpenCode style)
         (let ((max-steps (plist-get gptel-agent-loop--state :max-steps)))
           (when (and max-steps (>= step-count max-steps))
             (message "[RunAgent] Max steps (%d) reached for task '%s'"
                      max-steps description)
             (plist-put info :max-steps-reached t)))
         
         (unless (plist-get info :tracking-marker)
           (plist-put info :tracking-marker (overlay-start ov)))
         (gptel--display-tool-calls calls info))
        
        ((pred stringp)
         ;; Check if task might be incomplete (model stopped early)
         ;; Look for explicit completion signals
         (let* ((lower-resp (downcase resp))
                (seems-complete 
                 (or (string-match-p "all tasks.*complete" lower-resp)
                     (string-match-p "task.*done" lower-resp)
                     (string-match-p "completed successfully" lower-resp)
                     (string-match-p "finished.*tasks" lower-resp)
                     (string-match-p "✓.*complete" lower-resp)))
                (has-completion-signal
                 (or (string-match-p "all tasks completed successfully" lower-resp)
                     (string-match-p "task completed" lower-resp)
                     (string-match-p "^done\\." lower-resp)))
                (is-complete (or seems-complete has-completion-signal))
                (max-steps (plist-get gptel-agent-loop--state :max-steps))
                (at-max-steps (and max-steps (>= step-count max-steps)))
                (continuation-needed
                 (and gptel-agent-loop-force-completion
                      step-count
                      (not is-complete)
                      (not at-max-steps))))
           
           (if (and continuation-needed gptel-agent-loop-hard-loop)
               ;; HARD LOOP: Auto-continue (OpenCode style)
               (progn
                 (message "[RunAgent] Auto-continuing after %d steps..." step-count)
                 ;; Accumulate output
                 (plist-put gptel-agent-loop--state :accumulated-output
                            (concat (or (plist-get gptel-agent-loop--state :accumulated-output) "")
                                    resp "\n"))
                 ;; Increment step to track continuation
                 (plist-put gptel-agent-loop--state :step-count (1+ step-count))
                 ;; Schedule continuation
                 (run-with-timer 0.1 nil
                                 (lambda ()
                                   (gptel-agent-loop--continue))))
             
             ;; Either complete or at max steps - return result
             (progn
               (delete-overlay ov)
               (when (plist-get gptel-agent-loop--state :timeout-timer)
                 (cancel-timer (plist-get gptel-agent-loop--state :timeout-timer)))
               
               (if continuation-needed
                   ;; Return with continuation marker (soft mode)
                   (let ((result (format "%s\n\n[RUNAGENT_INCOMPLETE:%d steps]"
                                         resp step-count)))
                     (setq gptel-agent-loop--state nil)
                     (funcall main-cb result))
                 ;; Normal completion
                 (let ((final-result
                        (concat (or (plist-get gptel-agent-loop--state :accumulated-output) "")
                                resp)))
                   (setq gptel-agent-loop--state nil)
                   (funcall main-cb final-result)))))))
        
        ('abort
         (delete-overlay ov)
         (when (plist-get gptel-agent-loop--state :timeout-timer)
           (cancel-timer (plist-get gptel-agent-loop--state :timeout-timer)))
         (setq gptel-agent-loop--state nil)
         (funcall main-cb
                  (format "Aborted: %s task '%s' was cancelled."
                          agent-type description)))))))

(defun gptel-agent-loop--continue ()
  "Continue a RunAgent task after model stopped early.
Makes another request with continuation prompt to keep working.
This implements the hard loop (OpenCode style)."
  (when gptel-agent-loop--state
    (let* ((agent-type (plist-get gptel-agent-loop--state :agent-type))
           (description (plist-get gptel-agent-loop--state :description))
           (accumulated (plist-get gptel-agent-loop--state :accumulated-output))
           (main-cb (plist-get gptel-agent-loop--state :main-cb))
           (continuation-prompt
            (format "%s\n\n[CONTINUATION - Previous work done, continue with remaining tasks]\n\n%s"
                    gptel-agent-loop--continuation-prompt
                    (or accumulated ""))))
      (when (and agent-type main-cb)
        (message "[RunAgent] Continuing task '%s'..." description)
        ;; Make another request
        (gptel-agent--task main-cb agent-type description continuation-prompt)))))

(defun gptel-agent-loop-task (main-cb agent-type description prompt)
  "Call a RunAgent task with timeout, retry, and step limits.

MAIN-CB is the callback for results.
AGENT-TYPE is the subagent name.
DESCRIPTION is a short task description.
PROMPT is the full task instructions.

This mirrors OpenCode SessionPrompt.loop behavior.
Reads `steps' from agent YAML to set max-steps per agent."
  ;; Get agent-specific max-steps from YAML (OpenCode: agent.steps)
  (let* ((agent-config (cdr (assoc agent-type gptel-agent--agents)))
         (agent-steps (plist-get agent-config :steps))
         (effective-max-steps (or agent-steps gptel-agent-loop-max-steps)))
    ;; Initialize state (store all needed for hard-loop continuation)
    (setq gptel-agent-loop--state
          (list :step-count 0
                :retries 0
                :aborted nil
                :timeout-timer nil
                :max-steps effective-max-steps
                :accumulated-output nil
                :agent-type agent-type
                :description description
                :main-cb main-cb))
    
    ;; Set up timeout (like OpenCode's abort signal)
    (when gptel-agent-loop-timeout
      (plist-put gptel-agent-loop--state :timeout-timer
                 (run-with-timer gptel-agent-loop-timeout nil
                                 (lambda ()
                                   (plist-put gptel-agent-loop--state :aborted t)
                                   (message "[RunAgent] Task '%s' timed out after %ds"
                                            description gptel-agent-loop-timeout)))))
    
    ;; Call original gptel-agent--task with wrapped callback
    (let ((wrapped-cb (gptel-agent-loop--wrap-callback
                       main-cb agent-type description prompt)))
      (gptel-agent--task wrapped-cb agent-type description prompt))))

(defun gptel-agent-loop-enable ()
  "Enable RunAgent loop control by advising gptel-agent--task."
  (interactive)
  (advice-add 'gptel-agent--task :override #'gptel-agent-loop-task)
  (message "[RunAgent] Loop mode enabled (timeout=%ss, max-steps=%s, max-retries=%d)"
           (or gptel-agent-loop-timeout "none")
           (or gptel-agent-loop-max-steps "unlimited")
           gptel-agent-loop-max-retries))

(defun gptel-agent-loop-disable ()
  "Disable RunAgent loop control, restore original behavior."
  (interactive)
  (advice-remove 'gptel-agent--task #'gptel-agent-loop-task)
  (setq gptel-agent-loop--state nil)
  (message "[RunAgent] Loop mode disabled"))

(defun gptel-agent-loop-needs-continuation-p (result)
  "Check if RESULT from RunAgent indicates incomplete task.
Returns (STEPS . CLEANED-RESULT) if continuation needed, nil otherwise.
Use this in the main agent to decide whether to re-call RunAgent."
  (when (stringp result)
    (when (string-match "\\[RUNAGENT_INCOMPLETE:\\([0-9]+\\) steps\\]" result)
      (let ((steps (string-to-number (match-string 1 result)))
            (cleaned (replace-match "" nil nil result)))
        (cons steps cleaned)))))

(defun gptel-agent-loop-extract-result (result)
  "Extract clean result from RunAgent output, removing continuation markers."
  (if (stringp result)
      (replace-regexp-in-string "\\[RUNAGENT_INCOMPLETE:[0-9]+ steps\\]\\s-*" "" result)
    result))

(provide 'gptel-agent-loop)

;;; gptel-agent-loop.el ends here