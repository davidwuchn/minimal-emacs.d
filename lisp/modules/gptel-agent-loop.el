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
;; Unlike the earlier wrapper, this module implements its own subagent request
;; callback so it can see tool-call events directly.  That keeps it compatible
;; with the local `gptel-agent--task' override in gptel-tools-agent.el.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(declare-function gptel--apply-preset "gptel")
(declare-function gptel--display-tool-calls "gptel")
(declare-function gptel--preset-syms "gptel")
(declare-function gptel--update-status "gptel")
(declare-function gptel-agent--task "gptel-agent-tools")
(declare-function gptel-agent--task-overlay "gptel-agent-tools")
(declare-function gptel-fsm-info "gptel")
(declare-function gptel-make-fsm "gptel")
(declare-function gptel-request "gptel")

(declare-function my/gptel--coerce-fsm "gptel-ext-fsm-utils")
(declare-function my/gptel--deliver-subagent-result "gptel-tools-agent")
(declare-function my/gptel--subagent-cache-get "gptel-tools-agent")
(declare-function my/gptel--subagent-cache-put "gptel-tools-agent")

(defvar gptel--fsm-last nil)
(defvar gptel-agent--agents)
(defvar gptel-agent-request--handlers nil)
(defvar gptel--preset nil)

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
  "When non-nil, auto-continue incomplete RunAgent tasks."
  :type 'boolean
  :group 'gptel-agent-loop)

(defconst gptel-agent-loop--continuation-prompt
  "Task list not empty. Continue with the next tool call immediately.
Do NOT output text unless the work is complete. Call the next tool NOW."
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
  "Prompt injected when max steps is reached.")

(cl-defstruct (gptel-agent-loop--task
               (:constructor gptel-agent-loop--task-create))
  id
  agent-type
  description
  prompt
  main-cb
  step-count
  retries
  aborted
  timeout-timer
  max-steps
  max-steps-reached
  summary-requested
  accumulated-output
  tracking-marker
  parent-buffer
  finished)

(defvar gptel-agent-loop--state nil
  "Most recently created RunAgent task state.")

(defvar gptel-agent-loop--active-tasks (make-hash-table :test 'eq)
  "Active RunAgent task states keyed by task id.")

(defvar gptel-agent-loop--original-task-fn nil
  "Stores original `gptel-agent--task' before advice.")

(defun gptel-agent-loop--remember-state (state)
  "Track STATE globally for debugging and tests."
  (setq gptel-agent-loop--state state)
  (puthash (gptel-agent-loop--task-id state) state gptel-agent-loop--active-tasks)
  state)

(defun gptel-agent-loop--cleanup-state (state)
  "Remove STATE from active task bookkeeping."
  (when (timerp (gptel-agent-loop--task-timeout-timer state))
    (cancel-timer (gptel-agent-loop--task-timeout-timer state)))
  (remhash (gptel-agent-loop--task-id state) gptel-agent-loop--active-tasks)
  (when (eq gptel-agent-loop--state state)
    (setq gptel-agent-loop--state nil)))

(defun gptel-agent-loop--append-output (state text)
  "Append TEXT to STATE's accumulated output."
  (setf (gptel-agent-loop--task-accumulated-output state)
        (concat (or (gptel-agent-loop--task-accumulated-output state) "")
                text
                (unless (string-suffix-p "\n" text) "\n"))))

(defun gptel-agent-loop--result-prefix (state)
  "Return the standard result prefix for STATE."
  (format "%s result for task: %s\n\n"
          (capitalize (gptel-agent-loop--task-agent-type state))
          (gptel-agent-loop--task-description state)))

(defun gptel-agent-loop--build-final-result (state tail)
  "Build final response text for STATE ending with TAIL."
  (concat (gptel-agent-loop--result-prefix state)
          (or (gptel-agent-loop--task-accumulated-output state) "")
          tail))

(defun gptel-agent-loop--transient-error-p (error-data)
  "Check if ERROR-DATA represents a transient/retryable error."
  (when error-data
    (let ((msg (if (stringp error-data) error-data
                 (plist-get error-data :message))))
      (and msg
           (string-match-p
            "overloaded\\|timeout\\|rate limit\\|temporarily unavailable\\|503\\|502\\|429\\|invalidparameter"
            (downcase msg))))))

(defun gptel-agent-loop--maybe-cache-get (agent-type prompt)
  "Return cached subagent result for AGENT-TYPE and PROMPT if available."
  (when (fboundp 'my/gptel--subagent-cache-get)
    (my/gptel--subagent-cache-get agent-type prompt)))

(defun gptel-agent-loop--maybe-cache-put (state result)
  "Cache RESULT for STATE if the helper exists."
  (when (fboundp 'my/gptel--subagent-cache-put)
    (my/gptel--subagent-cache-put
     (gptel-agent-loop--task-agent-type state)
     (gptel-agent-loop--task-prompt state)
     result)))

(defun gptel-agent-loop--deliver-result (state result &optional cache-result)
  "Deliver RESULT for STATE.
When CACHE-RESULT is non-nil, cache the delivered string first."
  (unless (gptel-agent-loop--task-finished state)
    (setf (gptel-agent-loop--task-finished state) t)
    (gptel-agent-loop--cleanup-state state)
    (when cache-result
      (gptel-agent-loop--maybe-cache-put state result))
    (if (fboundp 'my/gptel--deliver-subagent-result)
        (my/gptel--deliver-subagent-result
         (gptel-agent-loop--task-main-cb state) result)
      (funcall (gptel-agent-loop--task-main-cb state) result))))

(defun gptel-agent-loop--deliver-aborted (state)
  "Deliver timeout/abort result for STATE once."
  (gptel-agent-loop--deliver-result
   state
   (format "Aborted: %s task '%s' was cancelled or timed out."
           (gptel-agent-loop--task-agent-type state)
           (gptel-agent-loop--task-description state))))

(defun gptel-agent-loop--continuation-prompt-for (state)
  "Build continuation prompt for STATE."
  (format "%s\n\n[CONTINUATION - Previous work done]\n\n%s"
          gptel-agent-loop--continuation-prompt
          (or (gptel-agent-loop--task-accumulated-output state) "")))

(defun gptel-agent-loop--summary-prompt-for (state)
  "Build max-steps summary prompt for STATE."
  (format "%s\n\nOriginal task:\n%s\n\nWork completed so far:\n%s"
          gptel-agent-loop--max-steps-prompt
          (gptel-agent-loop--task-prompt state)
          (or (gptel-agent-loop--task-accumulated-output state) "")))

(defun gptel-agent-loop--seems-complete-p (resp)
  "Return non-nil when RESP looks like a completion message."
  (let ((lower-resp (downcase resp)))
    (or (string-match-p "all tasks.*complete" lower-resp)
        (string-match-p "task.*done" lower-resp)
        (string-match-p "completed successfully" lower-resp)
        (string-match-p "finished.*tasks" lower-resp)
        (string-match-p "all tasks completed successfully" lower-resp)
        (string-match-p "task completed" lower-resp)
        (string-match-p "^done\\." lower-resp)
        (string-match-p "✓.*complete" lower-resp))))

(defun gptel-agent-loop--turn-skipped-p (resp)
  "Return non-nil when RESP matches malformed-tool skip output."
  (let ((lower-resp (downcase resp)))
    (string-match-p "gptel: turn skipped\\|all tool calls.*malformed" lower-resp)))

(defun gptel-agent-loop--continuation-needed-p (state resp)
  "Return non-nil when STATE should continue after RESP."
  (and gptel-agent-loop-force-completion
       (not (gptel-agent-loop--seems-complete-p resp))
       (not (gptel-agent-loop--task-max-steps-reached state))
       (or (gptel-agent-loop--turn-skipped-p resp)
           (> (gptel-agent-loop--task-step-count state) 0))))

(defun gptel-agent-loop--schedule (delay fn)
  "Run FN after DELAY seconds."
  (run-with-timer delay nil fn))

(defun gptel-agent-loop--make-callback (state request-prompt use-tools)
  "Build request callback for STATE.
REQUEST-PROMPT and USE-TOOLS are reused on retries."
  (lambda (resp info)
    (let ((ov (plist-get info :context))
          (error-data (plist-get info :error)))
      (cond
       ((gptel-agent-loop--task-finished state)
        (when (overlayp ov)
          (delete-overlay ov)))

       ((eq resp nil)
        (cond
         ((gptel-agent-loop--task-aborted state)
          (when (overlayp ov) (delete-overlay ov))
          (gptel-agent-loop--deliver-aborted state))
         ((and (gptel-agent-loop--transient-error-p error-data)
               (< (gptel-agent-loop--task-retries state)
                  gptel-agent-loop-max-retries))
          (setf (gptel-agent-loop--task-retries state)
                (1+ (gptel-agent-loop--task-retries state)))
          (message "[RunAgent] Retrying %s task '%s' (attempt %d/%d)"
                   (gptel-agent-loop--task-agent-type state)
                   (gptel-agent-loop--task-description state)
                   (gptel-agent-loop--task-retries state)
                   gptel-agent-loop-max-retries)
          (gptel-agent-loop--schedule
           2.0
           (lambda ()
             (gptel-agent-loop--request state request-prompt use-tools nil))))
         (t
          (when (overlayp ov) (delete-overlay ov))
          (gptel-agent-loop--deliver-result
           state
           (format "Error: %s task '%s' failed after %d retries.\nDetails: %S"
                   (gptel-agent-loop--task-agent-type state)
                   (gptel-agent-loop--task-description state)
                   (gptel-agent-loop--task-retries state)
                   error-data)))))

       ((and (consp resp) (eq (car resp) 'tool-call))
        (let ((calls (cdr resp)))
          (setf (gptel-agent-loop--task-step-count state)
                (+ (gptel-agent-loop--task-step-count state)
                   (length calls)))
          (let ((max-steps (gptel-agent-loop--task-max-steps state)))
            (when (and max-steps
                       (>= (gptel-agent-loop--task-step-count state) max-steps))
              (setf (gptel-agent-loop--task-max-steps-reached state) t)
              (message "[RunAgent] Max steps (%d) reached for task '%s'"
                       max-steps
                       (gptel-agent-loop--task-description state))))
          (unless (plist-get info :tracking-marker)
            (plist-put info :tracking-marker
                       (gptel-agent-loop--task-tracking-marker state)))
          (gptel--display-tool-calls calls info)))

       ((and (consp resp) (eq (car resp) 'tool-result))
        nil)

       ((stringp resp)
        (if (gptel-agent-loop--task-aborted state)
            (progn
              (when (overlayp ov) (delete-overlay ov))
              (gptel-agent-loop--deliver-aborted state))
          (let ((final-turn (not (plist-get info :tool-use))))
            (when final-turn
              (when (overlayp ov) (delete-overlay ov))
              (cond
               ((and (gptel-agent-loop--task-max-steps-reached state)
                     (not (gptel-agent-loop--task-summary-requested state)))
                (gptel-agent-loop--append-output state resp)
                (setf (gptel-agent-loop--task-summary-requested state) t)
                (if gptel-agent-loop-hard-loop
                    (gptel-agent-loop--schedule
                     0.1
                     (lambda ()
                       (gptel-agent-loop--request
                        state
                        (gptel-agent-loop--summary-prompt-for state)
                        nil
                        nil)))
                  (gptel-agent-loop--deliver-result
                   state
                   (format "%s\n\n[RUNAGENT_INCOMPLETE:%d steps]"
                           (gptel-agent-loop--build-final-result state "")
                           (gptel-agent-loop--task-step-count state)))))

               ((and (gptel-agent-loop--task-summary-requested state)
                     (not use-tools))
                (gptel-agent-loop--deliver-result
                 state
                 (gptel-agent-loop--build-final-result state resp)
                 t))

               ((gptel-agent-loop--continuation-needed-p state resp)
                (if gptel-agent-loop-hard-loop
                    (progn
                      (message "[RunAgent] Auto-continuing after %d steps..."
                               (gptel-agent-loop--task-step-count state))
                      (gptel-agent-loop--append-output state resp)
                      (gptel-agent-loop--schedule
                       0.1
                       (lambda ()
                         (gptel-agent-loop--request
                          state
                          (gptel-agent-loop--continuation-prompt-for state)
                          t
                          nil))))
                  (gptel-agent-loop--deliver-result
                   state
                   (format "%s\n\n[RUNAGENT_INCOMPLETE:%d steps]"
                           (gptel-agent-loop--build-final-result state resp)
                           (gptel-agent-loop--task-step-count state)))))

               (t
                (gptel-agent-loop--deliver-result
                 state
                 (gptel-agent-loop--build-final-result state resp)
                 t)))))))

       ((eq resp 'abort)
        (when (overlayp ov) (delete-overlay ov))
        (setf (gptel-agent-loop--task-aborted state) t)
        (gptel-agent-loop--deliver-aborted state))))))

(defun gptel-agent-loop--request (state prompt use-tools allow-cache)
  "Start or continue a subagent request for STATE.
PROMPT is the prompt to send.  When USE-TOOLS is nil, force a text-only
summary turn.  When ALLOW-CACHE is non-nil, reuse cached results."
  (unless (gptel-agent-loop--task-finished state)
    (let* ((agent-type (gptel-agent-loop--task-agent-type state))
           (description (gptel-agent-loop--task-description state))
           (cached (and allow-cache
                        (gptel-agent-loop--maybe-cache-get agent-type prompt))))
      (if cached
          (progn
            (message "[nucleus] Subagent '%s' cache hit" agent-type)
            (gptel-agent-loop--deliver-result state cached nil))
        (let* ((preset (nconc (list :include-reasoning nil
                                    :use-tools use-tools
                                    :use-context nil
                                    :stream nil)
                              (cdr (assoc agent-type gptel-agent--agents))))
               (syms (cons 'gptel--preset (gptel--preset-syms preset)))
               (vals (mapcar (lambda (sym)
                               (if (boundp sym) (symbol-value sym) nil))
                             syms)))
          (cl-progv syms vals
            (gptel--apply-preset preset)
            (let* ((parent-fsm (and (fboundp 'my/gptel--coerce-fsm)
                                    (my/gptel--coerce-fsm gptel--fsm-last)))
                   (fsm-info (ignore-errors
                               (and parent-fsm (gptel-fsm-info parent-fsm))))
                   (parent-buf (or (gptel-agent-loop--task-parent-buffer state)
                                   (plist-get fsm-info :buffer)
                                   (current-buffer)))
                   (where (or (gptel-agent-loop--task-tracking-marker state)
                              (plist-get fsm-info :tracking-marker)
                              (plist-get fsm-info :position)
                              (with-current-buffer parent-buf (point-marker))))
                   (tracking-marker
                    (or (gptel-agent-loop--task-tracking-marker state)
                        (let ((m (copy-marker where)))
                          (set-marker-insertion-type m t)
                          (set-marker m (marker-position where) parent-buf)
                          m)))
                   (callback (gptel-agent-loop--make-callback state prompt use-tools)))
              (setf (gptel-agent-loop--task-parent-buffer state) parent-buf
                    (gptel-agent-loop--task-tracking-marker state) tracking-marker)
              (gptel--update-status " Calling Agent..." 'font-lock-escape-face)
              (gptel-request prompt
                :context (gptel-agent--task-overlay tracking-marker agent-type description)
                :fsm (gptel-make-fsm :handlers gptel-agent-request--handlers)
                :position tracking-marker
                :buffer parent-buf
                :in-place t
                :callback callback))))))))

(defun gptel-agent-loop--make-timeout-timer (state)
  "Create timeout timer for STATE."
  (when gptel-agent-loop-timeout
    (run-with-timer
     gptel-agent-loop-timeout nil
     (lambda ()
       (unless (gptel-agent-loop--task-finished state)
         (setf (gptel-agent-loop--task-aborted state) t)
         (message "[RunAgent] Task '%s' timed out after %ds"
                  (gptel-agent-loop--task-description state)
                  gptel-agent-loop-timeout))))))

(defun gptel-agent-loop-task (main-cb agent-type description prompt)
  "Call a RunAgent task with timeout, retry, and step limits.

MAIN-CB is the callback for results.
AGENT-TYPE is the subagent name.
DESCRIPTION is a short task description.
PROMPT is the full task instructions.

This mirrors OpenCode SessionPrompt.loop behavior.
Reads `steps' from agent YAML to set max-steps per agent."
  (let* ((agent-config (cdr (assoc agent-type gptel-agent--agents)))
         (agent-steps (plist-get agent-config :steps))
         (effective-max-steps (or agent-steps gptel-agent-loop-max-steps))
         (state (gptel-agent-loop--remember-state
                 (gptel-agent-loop--task-create
                  :id (gensym "gptel-agent-loop-")
                  :agent-type agent-type
                  :description description
                  :prompt prompt
                  :main-cb main-cb
                  :step-count 0
                  :retries 0
                  :aborted nil
                  :timeout-timer nil
                  :max-steps effective-max-steps
                  :max-steps-reached nil
                  :summary-requested nil
                  :accumulated-output nil
                  :tracking-marker nil
                  :parent-buffer nil
                  :finished nil))))
    (setf (gptel-agent-loop--task-timeout-timer state)
          (gptel-agent-loop--make-timeout-timer state))
    (gptel-agent-loop--request state prompt t t)))

(defun gptel-agent-loop-enable ()
  "Enable RunAgent loop control by advising `gptel-agent--task'."
  (interactive)
  (unless gptel-agent-loop--original-task-fn
    (setq gptel-agent-loop--original-task-fn
          (symbol-function 'gptel-agent--task)))
  (advice-remove 'gptel-agent--task #'gptel-agent-loop-task)
  (advice-add 'gptel-agent--task :override #'gptel-agent-loop-task)
  (message "[RunAgent] Loop mode enabled (timeout=%ss, max-steps=%s, max-retries=%d)"
           (or gptel-agent-loop-timeout "none")
           (or gptel-agent-loop-max-steps "unlimited")
           gptel-agent-loop-max-retries))

(defun gptel-agent-loop-disable ()
  "Disable RunAgent loop control, restore original behavior."
  (interactive)
  (advice-remove 'gptel-agent--task #'gptel-agent-loop-task)
  (maphash (lambda (_id state)
             (setf (gptel-agent-loop--task-finished state) t)
             (gptel-agent-loop--cleanup-state state))
           gptel-agent-loop--active-tasks)
  (clrhash gptel-agent-loop--active-tasks)
  (setq gptel-agent-loop--state nil)
  (setq gptel-agent-loop--original-task-fn nil)
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
