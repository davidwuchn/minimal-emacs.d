;;; gptel-ext-context.el --- Auto-compact gptel buffers -*- no-byte-compile: t; lexical-binding: t; -*-

;; Author: David Wu
;; Version: 2.0.0
;;
;; Auto-compaction: monitors gptel buffer size and triggers LLM-based
;; summarization when tokens approach the context window threshold.

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
(defvar my/gptel--context-window-cache)

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
The interval check is a secondary safeguard, not the primary control."
  (let* ((chars (buffer-size))
         (text-tokens (my/gptel--estimate-text-tokens chars))
         (image-tokens (or (and (fboundp 'my/gptel--count-context-image-tokens)
                                (my/gptel--count-context-image-tokens))
                           0))
         (tokens (+ text-tokens image-tokens))
         (window (my/gptel--context-window))
         (threshold (* window my/gptel-auto-compact-threshold))
         (needed (and my/gptel-auto-compact-enabled
                      (bound-and-true-p gptel-mode)
                      (>= chars my/gptel-auto-compact-min-chars)
                      (>= tokens threshold))))
    (when (and my/gptel-auto-compact-enabled
               (bound-and-true-p gptel-mode)
               (>= chars my/gptel-auto-compact-min-chars))
      (message "[compact] Check: %d tokens (text:%d + images:%d) vs %d threshold (window: %d, %.0f%%) -> %s"
               (round tokens) (round text-tokens) (round image-tokens)
               (round threshold) window
               (* 100 (/ (float tokens) window))
               (if needed "NEEDED" "skipped")))
    needed))

(defun my/gptel-context-window-show ()
  "Show current model's context window for debugging."
  (interactive)
  (let* ((window (my/gptel--context-window))
         (model gptel-model)
         (model-id (my/gptel--model-id-string model))
         (cached (and model-id (gethash model-id my/gptel--context-window-cache)))
         (threshold (* window my/gptel-auto-compact-threshold))
         (chars (buffer-size))
         (text-tokens (my/gptel--estimate-text-tokens chars))
         (image-tokens (or (and (fboundp 'my/gptel--count-context-image-tokens)
                                (my/gptel--count-context-image-tokens))
                           0))
         (image-count (or (and (fboundp 'my/gptel--context-image-count)
                               (my/gptel--context-image-count))
                          0))
         (tokens (+ text-tokens image-tokens)))
    (message "Context window: %d tokens (threshold: %d, %.0f%%)
Model: %s
Model ID: %s
Cached: %s
Current: %d chars, ~%d tokens (text:%d + images:%d [%d]) (%.0f%% of window)"
             window threshold (* 100 my/gptel-auto-compact-threshold)
             model model-id
             (if cached (format "yes (%d)" cached) "no")
             chars (round tokens) (round text-tokens) (round image-tokens) image-count
             (* 100 (/ (float tokens) window)))))

(defun my/gptel--directive-text (sym)
  "Resolve directive SYM to a string.
Returns nil if directive is missing or invalid, and logs a warning."
  (let ((val (alist-get sym gptel-directives)))
    (cond
     ((functionp val) (funcall val))
     ((stringp val) val)
     (t
      (when my/gptel-auto-compact-enabled
        (message "[compact] Warning: Directive '%s' not found in gptel-directives. Add (compact . \"summary prompt\") to gptel-directives." sym))
      nil))))

;;; Core

(defun my/gptel--do-compact (&optional force-preview)
  "Perform compaction on current gptel buffer.
If FORCE-PREVIEW is non-nil, use preview mode regardless of `my/gptel-auto-compact-preview'.
Returns non-nil if compaction was initiated."
  (let ((system (my/gptel--directive-text 'compact))
        (buf (current-buffer))
        (chars-before (buffer-size))
        (tokens-before (my/gptel--estimate-tokens (buffer-size)))
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
                 (unless (equal my/gptel-auto-compact-request-id request-id)
                   (message "[compact] Skipping stale callback (race condition)")
                   (cl-return))
                 (setq my/gptel-auto-compact-running nil)
                 (setq my/gptel-auto-compact-last-run (current-time))
                 (if (not (stringp response))
                     (message "[compact] Error: No valid response")
                   (cl-incf my/gptel-auto-compact-attempts)
                   (let* ((inhibit-read-only t)
                          (point-before (point))
                          (chars-after (length response))
                          (tokens-after (my/gptel--estimate-tokens chars-after))
                          (backup (buffer-string)))
                     (if use-preview
                         (progn
                           (goto-char (point-max))
                           (insert "\n\n")
                           (insert (propertize "═══════════════════════════════════════════════════════════════\n"
                                               'face '(:foreground "yellow" :weight bold))
                           (insert (propertize (format "COMPACTED: %d -> %d chars (~%d -> %d tokens, %.0f%% reduction)\n"
                                                       chars-before chars-after
                                                       (round tokens-before) (round tokens-after)
                                                       (* 100 (- 1 (/ (float chars-after) chars-before))))
                                               'face '(:foreground "green" :weight bold)))
                           (insert (propertize "═══════════════════════════════════════════════════════════════\n\n"
                                               'face '(:foreground "yellow" :weight bold)))
                           (insert (propertize response 'face '(:foreground "cyan")))
                           (message "[compact] Preview appended (original kept)"))
                       (kill-new backup)
                       (erase-buffer)
                       (insert response)
                       (goto-char (min point-before (point-max)))
                       (message "[compact] Done: %d -> %d chars (~%d -> %d tokens, %.0f%% reduction) [backup in kill-ring]"
                                chars-before chars-after
                                (round tokens-before) (round tokens-after)
                                (* 100 (- 1 (/ (float chars-after) chars-before))))))))
             (error
              (with-current-buffer buf
                (setq my/gptel-auto-compact-running nil))
              (message "[compact] Error: %s" (error-message-string err))))))
t)))))

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

;;; Hook Registration

(add-hook 'gptel-post-response-functions #'my/gptel-auto-compact)

;;; Footer

(provide 'gptel-ext-context)
;;; gptel-ext-context.el ends here