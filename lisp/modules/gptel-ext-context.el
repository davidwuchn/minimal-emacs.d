;;; gptel-ext-context.el --- Auto-compact gptel buffers -*- no-byte-compile: t; lexical-binding: t; -*-

;; Author: David Wu
;; Version: 3.0.0
;;
;; Auto-compaction: monitors gptel buffer size and triggers LLM-based
;; summarization when tokens approach the context window threshold.
;;
;; Auto-delegation: when context exceeds backend-specific limits,
;; automatically delegates to a subagent with clean context.

;;; Commentary:

;; OVERVIEW:
;; This module provides automatic context management for gptel buffers.
;; It monitors token usage and triggers compaction or delegation when
;; thresholds are exceeded to prevent context window overflow.

;; ASSUMPTIONS:
;; 1. gptel-mode is active in the buffer before compaction checks run
;; 2. The 'compact directive exists in gptel-directives for LLM summarization
;; 3. Token estimation is approximate (chars / 4) and may vary by model
;; 4. Backend-specific thresholds account for undocumented server limits
;; 5. Image tokens are counted separately from text tokens

;; GOALS:
;; 1. Prevent context window overflow errors during long conversations
;; 2. Maintain conversation quality through intelligent summarization
;; 3. Minimize user interruption with automatic background compaction
;; 4. Support multiple backends with different token limits
;; 5. Provide fallback delegation when compaction is insufficient

;; RISK MITIGATION:
;; 1. Race conditions prevented with request-id tracking
;; 2. Max attempts limit prevents runaway compaction loops
;; 3. Minimum interval between compactions avoids thrashing
;; 4. Preview mode preserves original content for safety
;; 5. User confirmation option for destructive operations

;; EDGE CASES:
;; 1. Buffer too small: skipped if < my/gptel-auto-compact-min-chars
;; 2. Compaction in progress: skipped to prevent concurrent runs
;; 3. Max attempts reached: auto-compact disabled for buffer session
;; 4. No 'compact directive: operation skipped with warning message
;; 5. Stale callback: ignored if request-id mismatch (race condition)
;; 6. Nested worktrees: handled by parent context management
;; 7. Image-heavy buffers: token count includes image tokens

;; TEST:
;; - M-x my/gptel-context-window-show: displays current token usage
;; - M-x my/gptel-manual-compact: manually trigger compaction
;; - Monitor *Messages* for [compact] and [auto-delegate] logs

;;; Code:

(require 'gptel)
(require 'gptel-request)
(require 'gptel-ext-context-cache)
(require 'gptel-ext-context-images)
(require 'cl-lib)

(declare-function my/gptel--model-id-string "gptel-ext-context-cache")
(declare-function my/gptel--context-window "gptel-ext-context-cache")
(declare-function my/gptel--estimate-text-tokens "gptel-ext-context-cache")
(declare-function my/gptel--count-context-image-tokens "gptel-ext-context-images")
(declare-function my/gptel--context-image-count "gptel-ext-context-images")
(declare-function my/gptel--run-agent-tool "gptel-tools-agent")
(defvar my/gptel--context-window-cache)
(defvar gptel-backend)

;;; Customization

(defgroup my/gptel-auto-compact nil
  "Auto-compact gptel buffers when context grows too large."
  :group 'gptel)

(defcustom my/gptel-auto-compact-enabled t
  "Whether to auto-compact gptel buffers when they grow too large."
  :type 'boolean
  :group 'my/gptel-auto-compact)

(defcustom my/gptel-auto-compact-threshold 0.80
  "Fraction of context window at which to compact.

Default 0.80 means compact when tokens reach 80% of context window.
This leaves 20% headroom for response generation."
  :type 'number
  :group 'my/gptel-auto-compact)

(defcustom my/gptel-auto-compact-min-chars 4000
  "Minimum buffer size (chars) before auto-compacting."
  :type 'integer
  :group 'my/gptel-auto-compact)

(defcustom my/gptel-auto-compact-min-interval 300
  "Minimum seconds between auto-compactions per buffer.
Default is 5 minutes to avoid frequent compaction cycles."
  :type 'integer
  :group 'my/gptel-auto-compact)

(defcustom my/gptel-auto-compact-preview nil
  "When non-nil, keep original content and append compacted version.

The compacted content is appended after a highlighted separator showing
stats. This lets you see both original and compacted versions.

When nil (default), buffer is replaced with compacted content."
  :type 'boolean
  :group 'my/gptel-auto-compact)

(defcustom my/gptel-auto-compact-max-attempts 5
  "Maximum compactions per buffer session before disabling.
Prevents runaway compaction loops. Set to 0 for unlimited."
  :type 'integer
  :group 'my/gptel-auto-compact)

(defcustom my/gptel-auto-compact-confirm nil
  "When non-nil, ask for confirmation before destructive compaction.
Only applies when `my/gptel-auto-compact-preview' is nil.
Preview mode never requires confirmation since original is preserved."
  :type 'boolean
  :group 'my/gptel-auto-compact)

(defcustom my/gptel-auto-compact-threshold-dashscope 0.60
  "Fraction of context window at which to compact for DashScope backends.

DashScope has undocumented server-side timeout limits that cause failures
at high token counts even with long client timeouts. Default 0.60 means
compact at 60% of context window to stay within safe limits."
  :type 'number
  :group 'my/gptel-auto-compact)

(defcustom my/gptel-auto-delegate-enabled t
  "When non-nil, auto-delegate to subagent when context exceeds limits.

This prevents timeout errors on backends with strict server-side limits
by delegating work to a subagent with a clean context."
  :type 'boolean
  :group 'my/gptel-auto-compact)

(defcustom my/gptel-auto-delegate-threshold-absolute nil
  "Absolute token limit for auto-delegation, regardless of context window.

When set, triggers auto-delegation when tokens exceed this value.
Useful for backends with undocumented limits. Set to nil to use
percentage-based threshold only."
  :type '(choice (const :tag "Use percentage threshold" nil) integer)
  :group 'my/gptel-auto-compact)

(defcustom my/gptel-tool-result-truncate-size 4000
  "Maximum characters to keep from each tool result during compaction.
Tool results larger than this are truncated with a marker."
  :type 'integer
  :group 'my/gptel-auto-compact)

;;; Internal Variables

(defvar-local my/gptel-auto-compact-running nil
  "Non-nil while auto-compaction is in progress for this buffer.")

(defvar-local my/gptel-auto-compact-last-run nil
  "Time of the last auto-compaction for this buffer.")

(defvar-local my/gptel-auto-compact-request-id nil
  "Unique ID for current compaction request to prevent race conditions.")

(defvar-local my/gptel-auto-compact-attempts 0
  "Number of compactions performed in this buffer session.")

;;; Helpers

(defun my/gptel--backend-type ()
  "Return backend type keyword for current `gptel-backend'.
Returns :dashscope, :gemini, :openai, :copilot, or :unknown."
  (cond
   ((not (boundp 'gptel-backend)) :unknown)
   ((not gptel-backend) :unknown)
   ((eq gptel-backend (bound-and-true-p gptel--dashscope)) :dashscope)
   ((eq gptel-backend (bound-and-true-p gptel--gemini)) :gemini)
   ((eq gptel-backend (bound-and-true-p gptel--copilot)) :copilot)
   ((eq gptel-backend (bound-and-true-p gptel--deepseek)) :deepseek)
   ((eq gptel-backend (bound-and-true-p gptel--moonshot)) :moonshot)
   ((eq gptel-backend (bound-and-true-p gptel--minimax)) :minimax)
   (t :unknown)))

(defun my/gptel--effective-threshold ()
  "Return effective threshold based on backend type.
DashScope uses lower threshold due to server-side timeout limits."
  (if (eq (my/gptel--backend-type) :dashscope)
      my/gptel-auto-compact-threshold-dashscope
    my/gptel-auto-compact-threshold))

(defun my/gptel--threshold-values ()
  "Return threshold values for current context.
Returns (tokens window threshold-fraction percentage-threshold)."
  (let* ((tokens (my/gptel--current-tokens))
         (window (let ((value (my/gptel--context-window)))
                     (if (and (integerp value) (> value 0))
                         value
                       my/gptel-default-context-window)))
         (threshold-fraction (my/gptel--effective-threshold))
         (percentage-threshold (* window threshold-fraction)))
    (list tokens window threshold-fraction percentage-threshold)))

(defun my/gptel--current-tokens ()
  "Return estimated token count for current buffer."
  (let* ((chars (buffer-size))
         (text-tokens (my/gptel--estimate-text-tokens chars))
         (image-tokens (or (and (fboundp 'my/gptel--count-context-image-tokens)
                                (my/gptel--count-context-image-tokens))
                           0)))
    (+ text-tokens image-tokens)))

(defun my/gptel--compact-safe-p ()
  "Return non-nil if auto-compact is safe for the current buffer."
  (let ((elapsed (and my/gptel-auto-compact-last-run
                      (float-time (time-subtract (current-time)
                                                 my/gptel-auto-compact-last-run))))
        (attempts-ok (or (zerop my/gptel-auto-compact-max-attempts)
                         (< my/gptel-auto-compact-attempts my/gptel-auto-compact-max-attempts))))
    (when (and (not attempts-ok)
               my/gptel-auto-compact-enabled)
      (message "[compact] Max attempts (%d) reached for this buffer" my/gptel-auto-compact-max-attempts))
    (and (not my/gptel-auto-compact-running)
         (or (null elapsed)
             (>= elapsed my/gptel-auto-compact-min-interval))
         attempts-ok)))

(defun my/gptel--auto-compact-needed-p ()
  "Return non-nil when current buffer should be compacted.

Only returns t when tokens >= threshold% of context window.
Uses backend-specific thresholds (lower for DashScope)."
  (let* ((chars (buffer-size))
         (buffer-ready (and my/gptel-auto-compact-enabled
                            (bound-and-true-p gptel-mode)
                            (>= chars my/gptel-auto-compact-min-chars)))
         (threshold-values (my/gptel--threshold-values))
         (tokens (nth 0 threshold-values))
         (window (nth 1 threshold-values))
         (threshold-fraction (nth 2 threshold-values))
         (threshold (nth 3 threshold-values))
         (needed (and buffer-ready (>= tokens threshold))))
    (when buffer-ready
      (message "[compact] Check: %d tokens vs %d threshold (window: %d, %.0f%%, backend: %s) -> %s"
               (round tokens)
               (round threshold) window
               (* 100 threshold-fraction)
               (my/gptel--backend-type)
               (if needed "NEEDED" "skipped")))
    needed))

(defun my/gptel-context-window-show ()
  "Show current model's context window for debugging."
  (interactive)
  (let* ((threshold-values (my/gptel--threshold-values))
         (tokens (nth 0 threshold-values))
         (window (nth 1 threshold-values))
         (threshold-fraction (nth 2 threshold-values))
         (threshold (nth 3 threshold-values))
         (model gptel-model)
         (model-id (my/gptel--model-id-string model))
         (cached (and model-id (gethash model-id my/gptel--context-window-cache)))
         (backend-type (my/gptel--backend-type))
         (chars (buffer-size))
         (text-tokens (my/gptel--estimate-text-tokens chars))
         (image-tokens (- tokens text-tokens))
         (image-count (or (and (fboundp 'my/gptel--context-image-count)
                               (my/gptel--context-image-count))
                          0))
         (delegate-status (if (my/gptel--delegate-threshold-exceeded-p)
                              "EXCEEDED (would auto-delegate)"
                            "OK")))
    (message "Context window: %d tokens (threshold: %d, %.0f%%)
Backend: %s (effective threshold: %.0f%%)
Model: %s
Model ID: %s
Cached: %s
Current: %d chars, ~%d tokens (text:%d + images:%d [%d]) (%.0f%% of window)
Auto-delegate: %s"
             window threshold (* 100 threshold-fraction)
             backend-type (* 100 threshold-fraction)
             model model-id
             (if cached (format "yes (%d)" cached) "no")
             chars (round tokens) (round text-tokens) (round image-tokens) image-count
             (if (zerop window) 0.0 (* 100 (/ (float tokens) window)))
             delegate-status)))

(defun my/gptel--directive-text (sym)
  "Resolve directive SYM to a string.
Returns nil if directive is missing or invalid, and logs a warning."
  (let ((val (and (boundp 'gptel-directives)
                  (alist-get sym gptel-directives))))
    (cond
     ((functionp val) (funcall val))
     ((stringp val) val)
     (t
      (when my/gptel-auto-compact-enabled
        (message "[compact] Warning: Directive '%s' not found in gptel-directives. Add (compact . \"summary prompt\") to gptel-directives." sym))
      nil))))

;;; Core

(defun my/gptel--compaction-reduction-pct (chars-before chars-after)
  "Compute compaction reduction percentage.
Returns 0.0 if CHARS-BEFORE is zero to avoid division by zero."
  ;; ASSUMPTION: chars-before and chars-after are non-negative integers
  ;; BEHAVIOR: Returns percentage reduction, 0.0 if no before chars
  ;; EDGE CASE: chars-before=0 returns 0.0 instead of arith-error
  (if (zerop chars-before)
      0.0
    (* 100 (- 1 (/ (float chars-after) chars-before)))))

(defun my/gptel--format-compaction-stats (chars-before tokens-before)
  "Format and return compaction statistics as a message string.
Computes chars-after and tokens-after from current buffer state."
  (let* ((chars-after (buffer-size))
         (tokens-after (my/gptel--estimate-text-tokens chars-after))
         (reduction (my/gptel--compaction-reduction-pct chars-before chars-after)))
    (format "%d -> %d chars (~%d -> %d tokens, %.0f%% reduction)"
            chars-before chars-after
            (round tokens-before) (round tokens-after)
            reduction)))

(defun my/gptel--do-compact (&optional force-preview)
  "Perform compaction on current gptel buffer.
If FORCE-PREVIEW is non-nil, use preview mode regardless of `my/gptel-auto-compact-preview'.
Returns non-nil if compaction was initiated."
  (let ((system (my/gptel--directive-text 'compact))
        (buf (current-buffer))
        (chars-before (buffer-size))
        (tokens-before (my/gptel--current-tokens))
        (window (my/gptel--context-window))
        (use-preview (or force-preview my/gptel-auto-compact-preview))
        (request-id (format "%s-%d" (buffer-name) (float-time))))
    (cond
     ((not system)
      (message "[compact] No 'compact directive configured")
      nil)
     ((and my/gptel-auto-compact-confirm
           (not use-preview)
           (not (y-or-n-p (format "Compact buffer? %d chars -> ~%d tokens "
                                  chars-before (round tokens-before)))))
      (message "[compact] Skipped by user")
      nil)
     (t
      (setq my/gptel-auto-compact-request-id request-id)
      (setq my/gptel-auto-compact-running t)
      (message "[compact] Starting: %d chars, ~%d tokens (window: %d)"
               chars-before (round tokens-before) window)
      (gptel-request (buffer-string)
        :system system
        :buffer buf
        :callback
        (lambda (response _info)
          (condition-case err
              (with-current-buffer buf
                (cond
                 ((not (equal my/gptel-auto-compact-request-id request-id))
                  (setq my/gptel-auto-compact-running nil)
                  (message "[compact] Skipping stale callback (race condition)"))
                 ((not (stringp response))
                  (setq my/gptel-auto-compact-running nil)
                  (setq my/gptel-auto-compact-last-run (current-time))
                  (message "[compact] Error: No valid response"))
                 (t
                  (setq my/gptel-auto-compact-running nil)
                  (setq my/gptel-auto-compact-last-run (current-time))
                  (cl-incf my/gptel-auto-compact-attempts)
                  (let* ((inhibit-read-only t)
                         (point-before (point))
                         (backup (buffer-string)))
                    (if use-preview
                        (progn
                          (goto-char (point-max))
                          (insert "\n\n")
                          (insert (propertize "═══════════════════════════════════════════════════════════════\n"
                                              'face '(:foreground "yellow" :weight bold)))
                          (insert (propertize response 'face '(:foreground "cyan")))
                          (insert (propertize (format "\nCOMPACTED: %s\n"
                                                      (my/gptel--format-compaction-stats chars-before tokens-before))
                                              'face '(:foreground "green" :weight bold)))
                          (insert (propertize "═══════════════════════════════════════════════════════════════\n"
                                              'face '(:foreground "yellow" :weight bold)))
                          (message "[compact] Preview appended (original kept)"))
                      (kill-new backup)
                      (erase-buffer)
                      (insert response)
                      (goto-char (min point-before (point-max)))
                      (message "[compact] Done: %s [backup in kill-ring]"
                               (my/gptel--format-compaction-stats chars-before tokens-before)))))))
            (error
             (when (buffer-live-p buf)
               (with-current-buffer buf
                 (setq my/gptel-auto-compact-running nil)))
             (message "[compact] Error: %s" (error-message-string err))))))
        t))))

(defun my/gptel-manual-compact (&optional arg)
  "Manually compact current gptel buffer.
With prefix ARG, use preview mode (append instead of replace).
Compaction is done via LLM using the 'compact directive."
  (interactive "P")
  (if (not (bound-and-true-p gptel-mode))
      (message "Not in a gptel buffer")
    (if my/gptel-auto-compact-running
        (message "[compact] Already in progress")
      (my/gptel--do-compact arg))))

(defun my/gptel-auto-compact (_response _info)
  "Compact current gptel buffer when it grows too large.
Hook for `gptel-post-response-functions'."
  (when (and (my/gptel--compact-safe-p)
             (my/gptel--auto-compact-needed-p))
    (my/gptel--do-compact)))

;;; Auto-Delegation

(defun my/gptel--delegate-threshold-exceeded-p ()
  "Return non-nil if context exceeds auto-delegation threshold."
  (when my/gptel-auto-delegate-enabled
    (let* ((threshold-values (my/gptel--threshold-values))
           (tokens (nth 0 threshold-values))
           (window (nth 1 threshold-values))
           (threshold-fraction (nth 2 threshold-values))
           (percentage-threshold (nth 3 threshold-values))
           (absolute-threshold my/gptel-auto-delegate-threshold-absolute))
      (or (and absolute-threshold (>= tokens absolute-threshold))
          (>= tokens percentage-threshold)))))

(defun my/gptel--buffer-lines (buffer-string)
  "Return lines from BUFFER-STRING as a list.
Helper function to avoid duplicate split-string calls."
  (and (stringp buffer-string) (split-string buffer-string "\n")))

(defun my/gptel--extract-last-task-from-lines (lines)
  "Extract the most recent task/request from LINES.
Returns a short description of what the user was asking for."
  (let* ((user-lines (and (listp lines)
                          (cl-remove-if-not
                           (lambda (line)
                             (string-match-p "^\\*\\*You\\*\\*:\\|^User:\\|^> " line))
                           lines)))
         (last-user (car (last user-lines))))
    (if last-user
        (replace-regexp-in-string "^\\*\\*You\\*\\*:\\|^User:\\|^> " "" last-user)
      "Continue the task")))

(defun my/gptel--extract-last-task (buffer-string)
  "Extract the most recent task/request from BUFFER-STRING.
Returns a short description of what the user was asking for."
  (my/gptel--extract-last-task-from-lines (my/gptel--buffer-lines buffer-string)))

(defun my/gptel--smart-delegate-context (buffer-string last-task)
  "Build context for subagent delegation.
BUFFER-STRING is the full conversation. LAST-TASK is the extracted task.
Returns plist with :strategy and :context keys."
  (if (not (stringp buffer-string))
      (list :strategy 'task-only
            :context (or last-task "Continue the task")
            :reason "Empty or invalid buffer")
    (let* ((lines (my/gptel--buffer-lines buffer-string))
           (total-lines (length lines))
           (recent-lines (last lines (min 50 total-lines)))
           (has-tool-results (cl-some
                              (lambda (line)
                                (string-match-p "tool_result\\|tool-result\\|Tool result" line))
                              recent-lines)))
      (cond
       ((and has-tool-results (< total-lines 100))
        (list :strategy 'recent-history
              :context (string-join recent-lines "\n")
              :reason "Task involves recent tool results"))
       ((< total-lines 30)
        (list :strategy 'full-context
              :context buffer-string
              :reason "Short conversation, full context safe"))
       (t
        (list :strategy 'task-only
              :context last-task
              :reason "Large conversation, delegating with task only"))))))

(defun my/gptel--do-auto-delegate (prompt callback &optional buffer)
  "Auto-delegate to subagent when context is too large.
PROMPT is the pending user request. CALLBACK receives the result.
BUFFER is the gptel buffer (default current)."
  (let* ((buf (or buffer (current-buffer)))
         (buffer-string (with-current-buffer buf (buffer-string)))
         (tokens (with-current-buffer buf (my/gptel--current-tokens)))
         (last-task (my/gptel--extract-last-task buffer-string))
         (context-info (my/gptel--smart-delegate-context buffer-string last-task))
         (strategy (plist-get context-info :strategy))
         (context (plist-get context-info :context))
         (reason (plist-get context-info :reason)))
    (message "[auto-delegate] Context at %d tokens, delegating (strategy: %s, %s)"
             (round tokens) strategy reason)
    (if (not (fboundp 'my/gptel--run-agent-tool))
        (progn
          (message "[auto-delegate] Error: RunAgent tool not available")
          (when (functionp callback)
            (funcall callback "Error: Auto-delegation failed - RunAgent tool not available")))
      (my/gptel--run-agent-tool
       callback
       "explorer"
       (format "Auto-delegated task (%d tokens)" (round tokens))
       (format "%s\n\n<context_from_parent>\n%s\n</context_from_parent>"
               (or prompt last-task)
               context)
       nil
       nil
       nil))))

(defvar-local my/gptel--in-auto-delegate-check nil
  "Non-nil while checking auto-delegate to prevent recursion.
Buffer-local to allow concurrent auto-delegation in different gptel buffers.")

(defun my/gptel--maybe-auto-delegate-advice (orig-fn prompt &rest args)
  "Advice around `gptel-request' to check for auto-delegation.
ORIG-FN is `gptel-request'. PROMPT and ARGS are passed through."
  (if my/gptel--in-auto-delegate-check
      (apply orig-fn prompt args)
    (let ((my/gptel--in-auto-delegate-check t))
      (if (and my/gptel-auto-delegate-enabled
               (bound-and-true-p gptel-mode)
               (my/gptel--delegate-threshold-exceeded-p))
          (let* ((tokens (my/gptel--current-tokens))
                 (window (my/gptel--context-window))
                 (callback (plist-get args :callback)))
            (message "[auto-delegate] Threshold exceeded: %d/%d tokens (%.0f%%)"
                     (round tokens) (round window)
                     (if (and (integerp window) (> window 0))
                         (* 100 (/ (float tokens) window))
                       0))
            (my/gptel--do-auto-delegate prompt callback))
        (apply orig-fn prompt args)))))

(defun my/gptel-auto-delegate-enable ()
  "Enable auto-delegation advice."
  (interactive)
  (advice-add 'gptel-request :around #'my/gptel--maybe-auto-delegate-advice)
  (message "[auto-delegate] Enabled"))

(defun my/gptel-auto-delegate-disable ()
  "Disable auto-delegation advice."
  (interactive)
  (advice-remove 'gptel-request #'my/gptel--maybe-auto-delegate-advice)
  (message "[auto-delegate] Disabled"))

;;; Hook Registration

(add-hook 'gptel-post-response-functions #'my/gptel-auto-compact)
(my/gptel-auto-delegate-enable)

;;; Interactive Context Commands

(defun my/gptel-add-project-files ()
  "Select and add project files to gptel context."
  (interactive)
  (if-let* ((proj (project-current))
            (files (project-files proj))
            (selected (completing-read-multiple "Add context files: " files)))
      (progn
        (dolist (f selected)
          (gptel-add-file f))
        (message "Added %d files to gptel context." (length selected)))
    (user-error "Not in a project or no files selected")))

;;; Footer

(provide 'gptel-ext-context)
;;; gptel-ext-context.el ends here
