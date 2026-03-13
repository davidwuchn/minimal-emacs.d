;;; gptel-ext-context.el --- Auto-compact gptel buffers -*- lexical-binding: t; -*-

;; Author: David Wu
;; Version: 2.0.0
;;
;; Auto-compaction: monitors gptel buffer size and triggers LLM-based
;; summarization when tokens approach the context window threshold.

;;; Code:

(require 'gptel)
(require 'gptel-request)
(require 'gptel-ext-context-cache)

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

;;; Internal Variables

(defvar-local my/gptel-auto-compact-running nil
  "Non-nil while auto-compaction is in progress for this buffer.")

(defvar-local my/gptel-auto-compact-last-run nil
  "Time of the last auto-compaction for this buffer.")

;;; Helpers

(defun my/gptel--compact-safe-p ()
  "Return non-nil if auto-compact is safe for the current buffer."
  (let ((elapsed (and my/gptel-auto-compact-last-run
                      (float-time (time-subtract (current-time)
                                                 my/gptel-auto-compact-last-run)))))
    (and (not my/gptel-auto-compact-running)
         (or (null elapsed)
             (>= elapsed my/gptel-auto-compact-min-interval)))))

(defun my/gptel--auto-compact-needed-p ()
  "Return non-nil when current buffer should be compacted.

Only returns t when tokens >= threshold% of context window.
The interval check is a secondary safeguard, not the primary control."
  (let* ((chars (buffer-size))
         (tokens (my/gptel--estimate-tokens chars))
         (window (my/gptel--context-window))
         (threshold (* window my/gptel-auto-compact-threshold))
         (needed (and my/gptel-auto-compact-enabled
                      (bound-and-true-p gptel-mode)
                      (>= chars my/gptel-auto-compact-min-chars)
                      (>= tokens threshold))))
    (when (and my/gptel-auto-compact-enabled
               (bound-and-true-p gptel-mode)
               (>= chars my/gptel-auto-compact-min-chars))
      (message "[compact] Check: %d tokens vs %d threshold (window: %d, %.0f%%) → %s"
               (round tokens) (round threshold) window
               (* 100 (/ (float tokens) window))
               (if needed "NEEDED" "skipped")))
    needed))

(defun my/gptel--directive-text (sym)
  "Resolve directive SYM to a string."
  (let ((val (alist-get sym gptel-directives)))
    (cond
     ((functionp val) (funcall val))
     ((stringp val) val)
     (t nil))))

;;; Core

(defun my/gptel-auto-compact (_start _end)
  "Compact current gptel buffer when it grows too large."
  (when (and (my/gptel--compact-safe-p)
              (my/gptel--auto-compact-needed-p))
    (let ((system (my/gptel--directive-text 'compact))
          (buf (current-buffer))
          (chars-before (buffer-size))
          (tokens-before (my/gptel--estimate-tokens (buffer-size)))
          (window (my/gptel--context-window)))
      (when system
        (setq my/gptel-auto-compact-running t)
        (message "[compact] Starting: %d chars, ~%d tokens (window: %d, threshold: %d)"
                 chars-before (round tokens-before) window
                 (round (* window my/gptel-auto-compact-threshold)))
        (gptel-request (buffer-string)
          :system system
          :buffer buf
          :callback
          (lambda (response _info)
            (condition-case err
                (with-current-buffer buf
                  (setq my/gptel-auto-compact-running nil)
                  (setq my/gptel-auto-compact-last-run (current-time))
                  (if (not (stringp response))
                      (message "[compact] Error: No valid response")
                    (let* ((inhibit-read-only t)
                           (point-before (point))
                           (chars-after (length response))
                           (tokens-after (my/gptel--estimate-tokens chars-after)))
                      (erase-buffer)
                      (insert response)
                      (goto-char (min point-before (point-max)))
                      (message "[compact] Done: %d → %d chars (~%d → ~%d tokens, %.0f%% reduction)"
                               chars-before chars-after
                               (round tokens-before) (round tokens-after)
                               (* 100 (- 1 (/ (float chars-after) chars-before)))))))
              (error
               (setq my/gptel-auto-compact-running nil)
               (message "[compact] Error: %s" (error-message-string err))))))))))

;;; Hook Registration

(add-hook 'gptel-post-response-functions #'my/gptel-auto-compact)

;;; Footer

(provide 'gptel-ext-context)
;;; gptel-ext-context.el ends here
