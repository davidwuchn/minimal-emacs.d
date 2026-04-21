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
(declare-function my/gptel--seed-fsm-tools "gptel-tools-agent" (fsm tools))
(declare-function my/gptel-agent--task-override "gptel-tools-agent"
                  (main-cb agent-type description prompt))
(declare-function my/gptel--subagent-cache-get "gptel-tools-agent")
(declare-function my/gptel--subagent-cache-put "gptel-tools-agent")
(declare-function my/gptel--transient-error-p "gptel-ext-retry")

(defvar my/gptel-subagent-stream nil
  "Whether to use streaming mode for subagent requests.
Defined in gptel-tools-agent.el.")

(defvar gptel--fsm-last nil)
(defvar gptel-agent--agents)
(defvar gptel-agent-request--handlers)
(defvar gptel-agent-loop--bypass nil
  "When non-nil, bypass loop control and call the safe task override directly.")
(defvar gptel--preset nil)

(defgroup gptel-agent-loop nil
  "RunAgent loop control settings."
  :group 'gptel)

(defcustom gptel-agent-loop-timeout nil
  "Timeout in seconds for RunAgent tasks.
Set to nil for no timeout (default)."
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

(defcustom gptel-agent-loop-max-continuations 5
  "Maximum auto-continuations before forcing stop.
Prevents infinite loops when model outputs planning text without tool calls."
  :type 'integer
  :group 'gptel-agent-loop)

(defcustom gptel-agent-loop-continuation-context-limit 3000
  "Maximum characters of accumulated output to include in continuation prompts.
Prevents prompt bloat for long-running tasks. Set to nil for unlimited."
  :type '(choice (const :tag "Unlimited" nil) integer)
  :group 'gptel-agent-loop)

(defcustom gptel-agent-loop-continuation-prompt
  "CRITICAL: You must CALL TOOLS, not write text.

Previous response contained planning text but NO TOOL CALLS.
This is incorrect. You MUST call tools to do actual work.

IMMEDIATELY call the next tool. Do NOT:
- Write more planning text
- Say 'Let me...' without calling a tool
- Output reasoning blocks without tool calls

Call a tool NOW."
  "Prompt injected when model stops but tasks remain.
Customize this to adjust the urgency or style of the continuation prompt."
  :type 'string
  :group 'gptel-agent-loop)

(defcustom gptel-agent-loop-max-steps-prompt
  "CRITICAL - MAXIMUM STEPS REACHED

The maximum number of steps allowed for this task has been reached.
Tools are disabled. Respond with text only.

REQUIREMENTS:
1. Do NOT make any more tool calls
2. Provide a summary of work done so far
3. List any remaining tasks that were not completed
4. Recommend what should be done next

This constraint overrides ALL other instructions."
  "Prompt injected when max steps is reached."
  :type 'string
  :group 'gptel-agent-loop)

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
  finished
  continuation-count)

(defvar gptel-agent-loop--state nil
  "Most recently created RunAgent task state.")

(defvar gptel-agent-loop--active-tasks (make-hash-table :test 'eq)
  "Active RunAgent task states keyed by task id.")

(defcustom gptel-agent-loop-max-active-tasks 100
  "Maximum entries in active tasks table before cleanup."
  :type 'integer
  :group 'gptel-agent-loop)

(defun gptel-agent-loop--cleanup-stale-tasks ()
  "Remove finished tasks from active table.
Called when table exceeds `gptel-agent-loop-max-active-tasks'."
  (when (> (hash-table-count gptel-agent-loop--active-tasks)
           gptel-agent-loop-max-active-tasks)
    (maphash (lambda (id state)
               (when (gptel-agent-loop--task-finished state)
                 (remhash id gptel-agent-loop--active-tasks)))
             gptel-agent-loop--active-tasks)))

(defun gptel-agent-loop-cleanup-all ()
  "Force cleanup of all finished tasks from active table.
Also cancels any orphaned timeout timers. Use this to reclaim
memory after long sessions or if tasks appear stuck."
  (interactive)
  (let ((count 0))
    (maphash
     (lambda (id state)
       (when (gptel-agent-loop--task-finished state)
         ;; Cancel any lingering timer
         (when (timerp (gptel-agent-loop--task-timeout-timer state))
           (cancel-timer (gptel-agent-loop--task-timeout-timer state)))
         (remhash id gptel-agent-loop--active-tasks)
         (cl-incf count)))
     gptel-agent-loop--active-tasks)
    (when (> (hash-table-count gptel-agent-loop--active-tasks) 0)
      (message "[RunAgent] Cleanup: removed %d finished tasks, %d active remain"
               count (hash-table-count gptel-agent-loop--active-tasks)))
    count))

(defun gptel-agent-loop-list-active ()
  "List all active RunAgent tasks. For debugging."
  (interactive)
  (let ((tasks nil))
    (maphash
     (lambda (_id state)
       (push (list (gptel-agent-loop--task-agent-type state)
                   (gptel-agent-loop--task-description state)
                   :steps (gptel-agent-loop--task-step-count state)
                   :finished (gptel-agent-loop--task-finished state))
             tasks))
     gptel-agent-loop--active-tasks)
    (if tasks
        (message "[RunAgent] Active tasks:\n%s"
                 (mapconcat (lambda (task) (format "  %s: %s" (car task) (cadr task))) tasks "\n"))
      (message "[RunAgent] No active tasks"))))

(defvar gptel-agent-loop--original-task-fn nil
  "Stores original `gptel-agent--task' before advice.")

(defun gptel-agent-loop--remember-state (state)
  "Track STATE globally for debugging and tests."
  (gptel-agent-loop--cleanup-stale-tasks)
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
          (capitalize (or (gptel-agent-loop--task-agent-type state) "agent"))
          (or (gptel-agent-loop--task-description state) "unknown")))

(defun gptel-agent-loop--build-final-result (state tail)
  "Build final response text for STATE ending with TAIL."
  (concat (gptel-agent-loop--result-prefix state)
          (or (gptel-agent-loop--task-accumulated-output state) "")
          tail))

(defun gptel-agent-loop--transient-error-p (error-data)
  "Check if ERROR-DATA represents a transient/retryable error.
Delegates to `my/gptel--transient-error-p' for consistent error detection.
Extracts :code/:status from error-data to enable HTTP status checks."
  (when (and error-data (fboundp 'my/gptel--transient-error-p))
    (let ((http-status (or (when (listp error-data)
                             (or (plist-get error-data :code)
                                 (plist-get error-data :status)))
                           (and (numberp error-data) error-data))))
      (my/gptel--transient-error-p error-data http-status))))

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
When CACHE-RESULT is non-nil, cache the delivered string first.

Guards against delivering to a killed parent buffer by checking
`gptel-agent-loop--task-parent-buffer' and
`gptel-agent-loop--task-tracking-marker'."
  (cl-block gptel-agent-loop--deliver-result
    (unless (and state result (stringp result) (gptel-agent-loop--task-main-cb state))
      (message "[RunAgent] Error: Invalid args to deliver-result, dropping: %s"
               (if (stringp result)
                   (substring result 0 (min 50 (length result)))
                 result))
      (cl-return-from gptel-agent-loop--deliver-result))
    (let ((parent-buf (gptel-agent-loop--task-parent-buffer state)))
      (when (and parent-buf (not (buffer-live-p parent-buf)))
        (message "[RunAgent] Warning: parent buffer killed for task '%s', dropping result"
                 (gptel-agent-loop--task-description state))
        (setf (gptel-agent-loop--task-finished state) t)
        (gptel-agent-loop--cleanup-state state)
        (cl-return-from gptel-agent-loop--deliver-result)))
    (let ((main-cb (gptel-agent-loop--task-main-cb state)))
      (unless (functionp main-cb)
        (message "[RunAgent] Error: main callback is not a function for task '%s', dropping result"
                 (gptel-agent-loop--task-description state))
        (setf (gptel-agent-loop--task-finished state) t)
        (gptel-agent-loop--cleanup-state state)
        (cl-return-from gptel-agent-loop--deliver-result))
      (unless (gptel-agent-loop--task-finished state)
        (setf (gptel-agent-loop--task-finished state) t)
        (gptel-agent-loop--cleanup-state state)
        (let ((marker (gptel-agent-loop--task-tracking-marker state)))
          (when (and marker (markerp marker))
            (if (marker-buffer marker)
                (set-marker marker nil)
              (message "[RunAgent] Warning: tracking marker no longer live"))
            (setf (gptel-agent-loop--task-tracking-marker state) nil)))
        (when cache-result
          (gptel-agent-loop--maybe-cache-put state result))
        (if (fboundp 'my/gptel--deliver-subagent-result)
            (my/gptel--deliver-subagent-result main-cb result)
          (funcall main-cb result))))))

(defun gptel-agent-loop--deliver-aborted (state)
  "Deliver timeout/abort result for STATE once."
  (gptel-agent-loop--deliver-result
   state
   (format "Aborted: %s task '%s' was cancelled or timed out."
           (gptel-agent-loop--task-agent-type state)
           (gptel-agent-loop--task-description state))))

(defun gptel-agent-loop--continuation-prompt-for (state)
  "Build continuation prompt for STATE.
Truncates accumulated output to last
`gptel-agent-loop-continuation-context-limit' chars."
  (let* ((output (or (gptel-agent-loop--task-accumulated-output state) ""))
         (limit gptel-agent-loop-continuation-context-limit)
         (len (length output))
         (truncated (if (and (integerp limit) (> limit 0) (> len limit))
                        (concat "...[earlier output truncated]\n"
                                (substring output (- limit)))
                      output)))
    (format "%s\n\n[CONTINUATION - Recent work completed]\n\n%s"
            gptel-agent-loop-continuation-prompt
            truncated)))

(defun gptel-agent-loop--summary-prompt-for (state)
  "Build max-steps summary prompt for STATE."
  (format "%s\n\nOriginal task:\n%s\n\nWork completed so far:\n%s"
          gptel-agent-loop-max-steps-prompt
          (gptel-agent-loop--task-prompt state)
          (or (gptel-agent-loop--task-accumulated-output state) "")))

(defconst gptel-agent-loop--completion-patterns
  '("all tasks.*complete"
    "^task done\\|task completed"
    "completed successfully"
    "finished.*tasks"
    "all tasks completed successfully"
    "^done\\."
    "✓.*complete")
  "Regex patterns that indicate task completion.
Used by `gptel-agent-loop--seems-complete-p' to detect when
a RunAgent task has finished successfully.")

(defvar gptel-agent-loop--completion-patterns-compiled nil
  "Pre-compiled completion patterns for performance.")

(defun gptel-agent-loop--compile-patterns (patterns)
  "Compile PATTERNS list into a single combined regex string.
Returns nil if patterns list is empty or contains non-string elements."
  (when (and patterns (cl-every #'stringp patterns))
    (mapconcat (lambda (p) (concat "\\(" p "\\)")) patterns "\\|")))

(defun gptel-agent-loop--ensure-patterns-compiled ()
  "Ensure all pattern variables are compiled for performance.
Call once after definitions to pre-compile regex patterns."
  (setq gptel-agent-loop--completion-patterns-compiled
        (gptel-agent-loop--compile-patterns gptel-agent-loop--completion-patterns))
  (setq gptel-agent-loop--turn-skipped-pattern-compiled
        (gptel-agent-loop--compile-patterns (list gptel-agent-loop--turn-skipped-pattern)))
  (setq gptel-agent-loop--planning-patterns-compiled
        (gptel-agent-loop--compile-patterns gptel-agent-loop--planning-patterns))
  (setq gptel-agent-loop--finishing-patterns-compiled
        (gptel-agent-loop--compile-patterns gptel-agent-loop--finishing-patterns)))

(defun gptel-agent-loop--matches-any-pattern (text patterns)
  "Return non-nil when TEXT matches any string in PATTERNS.
Returns nil if TEXT is not a string or PATTERNS is not a list of strings.
Patterns are matched case-insensitively."
  (and (stringp text)
       (cl-every #'stringp patterns)
       (cl-some (lambda (pattern)
                  (let ((case-fold-search t))
                    (string-match-p pattern text)))
                patterns)))

(defun gptel-agent-loop--seems-complete-p (resp)
  "Return non-nil when RESP looks like a completion message.
Uses pre-compiled pattern for performance on hot path."
  (and (stringp resp)
       (let ((case-fold-search t))
         (if gptel-agent-loop--completion-patterns-compiled
             (string-match-p gptel-agent-loop--completion-patterns-compiled resp)
           (gptel-agent-loop--matches-any-pattern resp gptel-agent-loop--completion-patterns)))))

(defconst gptel-agent-loop--turn-skipped-pattern
  "gptel: turn skipped\\|all tool calls.*malformed"
  "Regex pattern for malformed tool call skip output.
Used by `gptel-agent-loop--turn-skipped-p' to detect when
gptel skipped a turn due to malformed tool calls.")

(defvar gptel-agent-loop--turn-skipped-pattern-compiled nil
  "Pre-compiled turn-skipped pattern for performance.")

(defun gptel-agent-loop--turn-skipped-p (resp)
  "Return non-nil when RESP matches malformed-tool skip output.
Uses pre-compiled pattern for performance on hot path."
  (and (stringp resp)
       (let ((case-fold-search t))
         (if gptel-agent-loop--turn-skipped-pattern-compiled
             (string-match-p gptel-agent-loop--turn-skipped-pattern-compiled resp)
           (string-match-p gptel-agent-loop--turn-skipped-pattern resp)))))

(defconst gptel-agent-loop--planning-patterns
  '("\\blet me\\b"
    "\\bi will\\b"
    "\\bi need to\\b"
    "\\bnow i need\\b"
    "\\bgoing to\\b"
    "\\bfirst,\\b"
    "\\bstep 1\\b"
    "\\btodo\\b"
    "\\bchecklist\\b")
  "Regex patterns that indicate planning text without action.
Used by `gptel-agent-loop--looks-like-planning-p' to detect
when the model is talking about doing work but hasn't called tools.")

(defvar gptel-agent-loop--planning-patterns-compiled nil
  "Pre-compiled planning patterns for performance.")

(defun gptel-agent-loop--looks-like-planning-p (resp)
  "Return non-nil when RESP looks like planning text without tool calls.
Detects common patterns where model talks about doing work
but didn't call tools. Uses pre-compiled pattern for performance on hot path."
  (and (stringp resp)
       (>= (length resp) 30)
       (let ((case-fold-search t))
         (if gptel-agent-loop--planning-patterns-compiled
             (string-match-p gptel-agent-loop--planning-patterns-compiled resp)
           (gptel-agent-loop--matches-any-pattern resp gptel-agent-loop--planning-patterns)))))

(defconst gptel-agent-loop--finishing-patterns
  '("summariz\\|conclude\\|conclusion\\|finish\\|wrap up\\|that's all\\|in summary\\|to summarize\\|final\\|overall"
    "here's the \\(result\\|answer\\|output\\)"
    "here is the \\(result\\|answer\\|output\\)"
    "here's \\(result\\|answer\\|output\\)"
    "here is \\(result\\|answer\\|output\\)")
  "Regex patterns that indicate model is wrapping up.
Used by `gptel-agent-loop--looks-like-finishing-p' to detect
when the model is concluding rather than planning more work.")

(defvar gptel-agent-loop--finishing-patterns-compiled nil
  "Pre-compiled finishing patterns for performance.")

(defun gptel-agent-loop--looks-like-finishing-p (resp)
  "Return non-nil when RESP looks like model is about to finish.
Detects patterns indicating the model is wrapping up,
not planning more work. Uses pre-compiled pattern for performance on hot path."
  (and (stringp resp)
       (let ((case-fold-search t))
         (if gptel-agent-loop--finishing-patterns-compiled
             (string-match-p gptel-agent-loop--finishing-patterns-compiled resp)
           (gptel-agent-loop--matches-any-pattern resp gptel-agent-loop--finishing-patterns)))))

(defun gptel-agent-loop--continuation-count (state)
  "Return continuation count for STATE, defaulting to 0 if nil."
  (or (gptel-agent-loop--task-continuation-count state) 0))

(defun gptel-agent-loop--increment-continuation-count (state)
  "Increment and return the new continuation count for STATE.
Assumes STATE is a valid task structure."
  (setf (gptel-agent-loop--task-continuation-count state)
        (1+ (gptel-agent-loop--continuation-count state))))

(defun gptel-agent-loop--continuation-needed-p (state resp)
  "Return non-nil when STATE should continue after RESP.
Only continues if tools were called AND model seems to be
planning without action.  Also checks continuation count
limit for early exit."
  (when (and (gptel-agent-loop--task-p state)
             (numberp (gptel-agent-loop--task-continuation-count state)))
    (unless (stringp resp)
      (setq resp ""))
    (and gptel-agent-loop-force-completion
         (< (gptel-agent-loop--continuation-count state)
            gptel-agent-loop-max-continuations)
         (not (gptel-agent-loop--seems-complete-p resp))
         (not (gptel-agent-loop--looks-like-finishing-p resp))
         (not (gptel-agent-loop--task-max-steps-reached state))
         (or (gptel-agent-loop--turn-skipped-p resp)
             (gptel-agent-loop--looks-like-planning-p resp)))))

(defun gptel-agent-loop--schedule (delay fn)
  "Run FN after DELAY seconds."
  (run-with-timer delay nil fn))

(defun gptel-agent-loop--schedule-request (state prompt use-tools &optional delay)
  "Schedule a request for STATE with PROMPT.
USE-TOOLS determines tool usage.  DELAY defaults to 0.1 seconds.
Extracted from duplicate scheduling patterns."
  (gptel-agent-loop--schedule (or delay 0.1)
                              (lambda ()
                                (gptel-agent-loop--request state prompt use-tools nil))))

(defun gptel-agent-loop--check-aborted (state ov)
  "Check if STATE is aborted and deliver abort result.
Cleans up overlay OV if present.  Returns non-nil if aborted."
  (when (gptel-agent-loop--task-aborted state)
    (gptel-agent-loop--handle-aborted-state state ov)
    t))

(defun gptel-agent-loop--cleanup-overlay (ov)
  "Delete overlay OV if it is a valid overlay.
Extracted to reduce duplication in callback cleanup paths."
  (when (overlayp ov)
    (delete-overlay ov)))

(defun gptel-agent-loop--handle-aborted-state (state ov &optional set-aborted)
  "Handle aborted STATE, cleaning up overlay OV.
When SET-ABORTED is non-nil, also mark state as aborted.
Extracted from duplicate abort handling patterns."
  (when set-aborted
    (setf (gptel-agent-loop--task-aborted state) t))
  (gptel-agent-loop--cleanup-overlay ov)
  (gptel-agent-loop--deliver-aborted state))

(defun gptel-agent-loop--should-retry-p (state error-data)
  "Return non-nil when STATE should retry after ERROR-DATA.
Retries when error is transient and retry budget remains."
  (and (gptel-agent-loop--transient-error-p error-data)
       (< (gptel-agent-loop--task-retries state)
          gptel-agent-loop-max-retries)))

(defun gptel-agent-loop--make-callback (state request-prompt use-tools)
  "Build request callback for STATE.
REQUEST-PROMPT and USE-TOOLS are reused on retries."
  (lambda (resp info)
    (let ((ov (plist-get info :context))
          (error-data (plist-get info :error)))
      (cond
       ((gptel-agent-loop--task-finished state)
        (gptel-agent-loop--cleanup-overlay ov))

       ((eq resp nil)
        (if (gptel-agent-loop--task-aborted state)
            (gptel-agent-loop--handle-aborted-state state ov)
          (cond
           ((gptel-agent-loop--should-retry-p state error-data)
            (setf (gptel-agent-loop--task-retries state)
                  (1+ (gptel-agent-loop--task-retries state)))
            (message "[RunAgent] Retrying %s task '%s' (attempt %d/%d)"
                     (gptel-agent-loop--task-agent-type state)
                     (gptel-agent-loop--task-description state)
                     (gptel-agent-loop--task-retries state)
                     gptel-agent-loop-max-retries)
            (when (timerp (gptel-agent-loop--task-timeout-timer state))
              (cancel-timer (gptel-agent-loop--task-timeout-timer state)))
            (setf (gptel-agent-loop--task-timeout-timer state)
                  (gptel-agent-loop--make-timeout-timer state))
            (gptel-agent-loop--schedule-request state request-prompt use-tools 2.0))
           (t
            (gptel-agent-loop--cleanup-overlay ov)
            (gptel-agent-loop--deliver-result
             state
             (format "Error: %s task '%s' failed after %d retries.\nDetails: %S"
                     (gptel-agent-loop--task-agent-type state)
                     (gptel-agent-loop--task-description state)
                     (gptel-agent-loop--task-retries state)
                     error-data))))))

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
            (setf (plist-get info :tracking-marker)
                  (gptel-agent-loop--task-tracking-marker state)))
          (gptel--display-tool-calls calls info)))

       ((and (consp resp) (eq (car resp) 'tool-result))
        (gptel-agent-loop--cleanup-overlay ov)
        nil)

       ((stringp resp)
        (unless (gptel-agent-loop--check-aborted state ov)
          (gptel-agent-loop--append-output state resp)
          (let ((final-turn (not (plist-get info :tool-use))))
            (when final-turn
              (gptel-agent-loop--cleanup-overlay ov)
              (gptel-agent-loop--handle-string-response state resp use-tools)))))

       ((eq resp 'abort)
        (gptel-agent-loop--handle-aborted-state state ov t))))))

(defun gptel-agent-loop--handle-empty-response (state resp)
  "Handle empty string RESP for STATE.
Returns non-nil if result was delivered."
  (when (and (stringp resp) (string-blank-p resp))
    (if (= (gptel-agent-loop--task-step-count state) 0)
        (gptel-agent-loop--deliver-result
         state
         (format "Error: %s task '%s' returned empty response with no tool calls."
                 (gptel-agent-loop--task-agent-type state)
                 (gptel-agent-loop--task-description state)))
      (gptel-agent-loop--deliver-result
       state
       (gptel-agent-loop--build-final-result state "[empty response]")))
    t))

(defun gptel-agent-loop--handle-max-steps-reached (state _resp)
  "Handle STATE when max steps were reached and RESP is final turn.
Returns non-nil if result was delivered."
  (when (and (gptel-agent-loop--task-max-steps-reached state)
             (not (gptel-agent-loop--task-summary-requested state)))
    (setf (gptel-agent-loop--task-summary-requested state) t)
    (if gptel-agent-loop-hard-loop
        (gptel-agent-loop--schedule-request state (gptel-agent-loop--summary-prompt-for state) nil)
      (gptel-agent-loop--deliver-result
       state
       (format "%s\n\n[RUNAGENT_INCOMPLETE:%d steps]"
               (gptel-agent-loop--build-final-result state "")
               (gptel-agent-loop--task-step-count state))))
    t))

(defun gptel-agent-loop--handle-summary-turn (state _resp use-tools)
  "Handle STATE when summary was requested and RESP is summary turn.
USE-TOOLS indicates whether tools were requested.
Returns non-nil if result was delivered."
  (when (and (gptel-agent-loop--task-summary-requested state)
             (not use-tools))
    (gptel-agent-loop--deliver-result
     state
     (gptel-agent-loop--build-final-result state "")
     t)
    t))

(defun gptel-agent-loop--handle-continuation (state resp)
  "Handle STATE when continuation is needed after RESP.
Returns non-nil if result was delivered."
  (when (and (gptel-agent-loop--continuation-needed-p state resp)
             gptel-agent-loop-hard-loop)
    (gptel-agent-loop--increment-continuation-count state)
    (message "[RunAgent] Auto-continuing after %d steps (continuation %d/%d)..."
             (gptel-agent-loop--task-step-count state)
             (gptel-agent-loop--continuation-count state)
             gptel-agent-loop-max-continuations)
    (gptel-agent-loop--schedule-request state (gptel-agent-loop--continuation-prompt-for state) t)
    t))

(defun gptel-agent-loop--handle-final-response (state _resp)
  "Handle STATE when RESP is a final response to deliver.
Returns non-nil if result was delivered."
  (gptel-agent-loop--deliver-result
   state
   (gptel-agent-loop--build-final-result state "")
   t)
  t)

(defun gptel-agent-loop--handle-string-response (state resp use-tools)
  "Handle string response RESP for STATE.
USE-TOOLS indicates whether tools were requested on this turn.
Returns non-nil if result was delivered."
  (or (gptel-agent-loop--handle-max-steps-reached state resp)
      (gptel-agent-loop--handle-summary-turn state resp use-tools)
      (gptel-agent-loop--handle-empty-response state resp)
      (gptel-agent-loop--handle-continuation state resp)
      (gptel-agent-loop--handle-final-response state resp)))

(defun gptel-agent-loop--request (state prompt use-tools allow-cache)
  "Start or continue a subagent request for STATE.
PROMPT is the prompt to send.  When USE-TOOLS is nil, force a text-only
summary turn.  When ALLOW-CACHE is non-nil, reuse cached results.

Cache behavior:
- Initial requests (from `gptel-agent-loop-task') pass ALLOW-CACHE t
- Continuation and summary prompts pass ALLOW-CACHE nil intentionally
  because each continuation prompt is unique and should not reuse
  cached results from previous runs."
  (unless (gptel-agent-loop--task-finished state)
    (let* ((agent-type (gptel-agent-loop--task-agent-type state))
           (description (gptel-agent-loop--task-description state))
           (cached (and allow-cache
                        (gptel-agent-loop--maybe-cache-get agent-type prompt))))
      (if cached
          (progn
            (message "[nucleus] Subagent '%s' cache hit" agent-type)
            (gptel-agent-loop--deliver-result state cached nil))
        (let* ((preset (append (list :include-reasoning nil
                                     :use-tools use-tools
                                     :use-context nil
                                     :stream my/gptel-subagent-stream)
                               (cdr (assoc agent-type gptel-agent--agents))))
               (syms (cons 'gptel--preset (gptel--preset-syms preset)))
               (vals (mapcar (lambda (sym)
                               (if (boundp sym) (symbol-value sym) nil))
                             syms)))
          (cl-progv syms vals
            (gptel--apply-preset preset)
            (let* ((request-tools (and gptel-use-tools (copy-sequence gptel-tools)))
                   (parent-fsm (and (fboundp 'my/gptel--coerce-fsm)
                                    (my/gptel--coerce-fsm gptel--fsm-last)))
                   (fsm-info (ignore-errors
                               (and parent-fsm (gptel-fsm-info parent-fsm))))
                   (parent-buf (or (let ((buf (gptel-agent-loop--task-parent-buffer state)))
                                     (and (buffer-live-p buf) buf))
                                   (let ((buf (plist-get fsm-info :buffer)))
                                     (and (buffer-live-p buf) buf))
                                   (current-buffer)))
                   (where (or
                           (let ((tm (gptel-agent-loop--task-tracking-marker state)))
                             (when (and (markerp tm) (numberp (marker-position tm))) tm))
                           (let ((tm (plist-get fsm-info :tracking-marker)))
                             (when (and (markerp tm) (numberp (marker-position tm))) tm))
                           (let ((pos (plist-get fsm-info :position)))
                             (when (and (markerp pos) (numberp (marker-position pos))) pos))
                           (with-current-buffer parent-buf (point-marker))))
                   (tracking-marker
                    (or (gptel-agent-loop--task-tracking-marker state)
                        ;; If where is already in parent-buf, use it directly.
                        ;; If it's from a foreign buffer (fsm-info), don't copy
                        ;; its position across buffers — create a fresh marker instead.
                        (if (and where (eq (marker-buffer where) parent-buf))
                            where
                          (with-current-buffer parent-buf (point-marker)))))
                   (callback (gptel-agent-loop--make-callback state prompt use-tools))
                   (child-fsm (gptel-make-fsm :handlers gptel-agent-request--handlers)))
              (setf (gptel-agent-loop--task-parent-buffer state) parent-buf
                    (gptel-agent-loop--task-tracking-marker state) tracking-marker)
              (gptel--update-status " Calling Agent..." 'font-lock-escape-face)
              (gptel-request prompt
                :context (if (fboundp 'gptel-agent--task-overlay)
                             (gptel-agent--task-overlay tracking-marker agent-type description)
                           nil)
                :fsm child-fsm
                :position tracking-marker
                :buffer parent-buf
                :in-place t
                :callback callback)
              (when (fboundp 'my/gptel--seed-fsm-tools)
                (my/gptel--seed-fsm-tools child-fsm request-tools)))))))))

(defun gptel-agent-loop--make-timeout-timer (state)
  "Create timeout timer for STATE."
  (when gptel-agent-loop-timeout
    (let ((timeout gptel-agent-loop-timeout))
      (run-with-timer
       timeout nil
       (lambda ()
         (unless (gptel-agent-loop--task-finished state)
           (setf (gptel-agent-loop--task-aborted state) t)
           (message "[RunAgent] Task '%s' timed out after %ds"
                    (gptel-agent-loop--task-description state)
                    timeout)
           (gptel-agent-loop--deliver-aborted state)))))))

(defun gptel-agent-loop-task (main-cb agent-type description prompt)
  "Call a RunAgent task with timeout, retry, and step limits.

MAIN-CB is the callback for results.
AGENT-TYPE is the subagent name.
DESCRIPTION is a short task description.
PROMPT is the full task instructions.

This mirrors OpenCode SessionPrompt.loop behavior.
Reads `steps' from agent YAML to set max-steps per agent."
  (if (and gptel-agent-loop--bypass
           (fboundp 'my/gptel-agent--task-override))
      (my/gptel-agent--task-override main-cb agent-type description prompt)
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
                    :finished nil
                    :continuation-count 0))))
      (setf (gptel-agent-loop--task-timeout-timer state)
            (gptel-agent-loop--make-timeout-timer state))
      (gptel-agent-loop--request state prompt t t))))

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
             (let ((marker (gptel-agent-loop--task-tracking-marker state)))
               (when (and marker (markerp marker) (marker-buffer marker))
                 (set-marker marker nil)))
             (setf (gptel-agent-loop--task-tracking-marker state) nil
                   (gptel-agent-loop--task-finished state) t)
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
    (when (string-match "\\[RUNAGENT_INCOMPLETE:\\([0-9]+\\) steps\\(?:, [0-9]+ continuations\\)?\\]" result)
      (let ((steps (string-to-number (match-string 1 result)))
            (cleaned (replace-match "" nil nil result)))
        (cons steps cleaned)))))

(defun gptel-agent-loop-extract-result (result)
  "Extract clean result from RunAgent output, removing continuation markers."
  (if (stringp result)
      (replace-regexp-in-string "\\[RUNAGENT_INCOMPLETE:[0-9]+ steps\\(?:, [0-9]+ continuations\\)?\\]\\s-*" "" result)
    result))

(gptel-agent-loop--ensure-patterns-compiled)

(provide 'gptel-agent-loop)

;;; gptel-agent-loop.el ends here
