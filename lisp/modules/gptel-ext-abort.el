;;; gptel-ext-abort.el --- Request abort, curl timeouts, and keyboard-quit -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Commentary:
;; Two layers for always-interruptable requests:
;; 1) Make curl fail fast on network stalls (fast curl timeouts).
;; 2) Provide a single key (C-g) that aborts the active gptel request in gptel
;;    buffers, instead of only quitting UI state.

;;; Code:

(require 'cl-lib)
(require 'gptel)
(require 'gptel-ext-fsm-utils)

;; --- Always-Interruptable Requests ---

(defgroup my/gptel-interrupt nil
  "Fast interruption and timeouts for gptel requests."
  :group 'gptel)

(defcustom my/gptel-curl-connect-timeout 20
  "Seconds to wait for curl to connect."
  :type 'integer
  :group 'my/gptel-interrupt)

(defcustom my/gptel-curl-max-time 300
  "Maximum seconds for a single gptel curl request.
Increased from 180 to 300 because executor subagent code-generation
prompts (20-30KB) routinely exceed 180s on DashScope and DeepSeek.
Analyzer/grader/comparator are smaller (30-60s)."
  :type 'integer
  :group 'my/gptel-interrupt)

(defcustom my/gptel-curl-low-speed-time 15
  "Seconds of low-speed allowed before curl aborts."
  :type 'integer
  :group 'my/gptel-interrupt)

(defcustom my/gptel-curl-low-speed-limit 50
  "Bytes/sec threshold for curl's low-speed detection."
  :type 'integer
  :group 'my/gptel-interrupt)

(defun my/gptel--install-fast-curl-timeouts ()
  "Set `gptel-curl-extra-args' for fast failure on stalls.
NOTE: Low-speed timeout (-y/-Y) removed - caused false positives for subagents.
Backend-specific timeouts (DashScope 900s, Moonshot 900s) handle long-running calls."
  (setq gptel-curl-extra-args
        (list
         "--connect-timeout" (number-to-string my/gptel-curl-connect-timeout)
         "--max-time" (number-to-string my/gptel-curl-max-time)
         ;; NOTE: -y/-Y (low-speed timeout) intentionally REMOVED.
         ;; These caused curl exit 28 during subagent calls when LLM thinks
         ;; for >15s without streaming output. Backend :curl-args override
         ;; max-time but low-speed detection is independent.
         ;; NOTE: --http1.1 is intentionally NOT set here globally.
         ;; It caused DashScope (and other HTTP/2-capable backends) to fail on
         ;; large request bodies (e.g. subagent 3rd turn with full file content).
         ;; Moonshot backend already declares --http1.1 in its own :curl-args slot,
         ;; so it still gets the workaround it needs.
         ;; Make curl stream output as it arrives.
         "--no-buffer")))

(with-eval-after-load 'gptel-request
  (my/gptel--install-fast-curl-timeouts))



;; Used to cancel async tool callbacks after abort.
(defvar-local my/gptel--abort-generation 0
  "Monotonic counter incremented when aborting gptel activity in this buffer.")

;; Prompt marker helpers (shared with gptel-ext-core.el post-response hook)
(defvar my/gptel-prompt-marker "### "
  "Prompt marker inserted at end of a gptel buffer.")

(defun my/gptel--prompt-marker-value ()
  "Return the prompt marker string if valid, or nil."
  (when (and (boundp 'my/gptel-prompt-marker)
             (stringp my/gptel-prompt-marker)
             (not (string-empty-p my/gptel-prompt-marker)))
    my/gptel-prompt-marker))

(defun my/gptel--prompt-marker-regexp ()
  "Return compiled regexp for prompt marker line, or nil if marker is invalid."
  (when-let ((marker (my/gptel--prompt-marker-value)))
    (concat "^" (regexp-quote marker))))

(defun my/gptel--prompt-marker-present-at-eob-p ()
  "Return non-nil if the last non-blank line at EOB is a prompt marker."
  (when-let ((regexp (my/gptel--prompt-marker-regexp)))
    (save-excursion
      (goto-char (point-max))
      (skip-chars-backward " \t\n")
      (beginning-of-line)
      (looking-at-p regexp))))

(defun my/gptel--insert-prompt-marker-at-eob ()
  "Insert a single prompt marker at end of buffer."
  (when-let ((marker (my/gptel--prompt-marker-value)))
    (unless (my/gptel--prompt-marker-present-at-eob-p)
      (goto-char (point-max))
      ;; Keep exactly one marker line; no extra blank line.
      (unless (bolp) (insert "\n"))
      (insert marker))))

(defun my/gptel--goto-prompt-marker-end ()
  "Move point to end of prompt marker at EOB if present."
  (when-let ((regexp (my/gptel--prompt-marker-regexp)))
    (goto-char (point-max))
    (skip-chars-backward " \t\n")
    (beginning-of-line)
    (when (looking-at-p regexp)
      (goto-char (match-end 0)))))



(defun my/gptel-keyboard-quit ()
  "In gptel buffers, abort the request then quit.

This makes C-g reliably stop long-hanging tool calls / curl stalls."
  (interactive)
  (my/gptel-abort-here)
  (keyboard-quit))

(defun my/gptel-abort-here ()
  "Abort any active gptel request for the current buffer.

This wraps `gptel-abort' and also kills any agent sub-processes or
introspector tasks that may be running. Safe to call even when no
request is active."
  (interactive)
  ;; Bump generation so async tool sentinels can self-cancel.
  (when (boundp 'my/gptel--abort-generation)
    (setq-local my/gptel--abort-generation (1+ my/gptel--abort-generation)))

  ;; Abort main gptel request
  (when-let ((buf (current-buffer)))
    (when (and (fboundp 'gptel-abort)
               (buffer-live-p buf))
      (ignore-errors (gptel-abort buf))))
  ;; Kill all gptel-related sub-processes.
  ;; Prefer the explicit tag `my/gptel-managed`, but also catch gptel's own curl
  ;; process (buffer is typically named " *gptel-curl*" with a leading space).
  ;; This prevents accidentally killing unrelated curl/rg processes.
  (let ((killed 0))
    (dolist (proc (process-list))
      (when (and (process-live-p proc)
                 (or (process-get proc 'my/gptel-managed)
                     ;; gptel's internal curl process is named "gptel-curl".
                     (let ((proc-name (process-name proc)))
                       (and proc-name
                            (or (string= proc-name "gptel-curl")
                                ;; Generic catch: gptel tool processes we create are named gptel-...
                                (string-prefix-p "gptel-" proc-name))))
                     ;; Also match by process buffer name.
                     (let ((proc-buf (process-buffer proc)))
                       (and proc-buf
                            (stringp (buffer-name proc-buf))
                            (string-match-p "gptel-curl" (buffer-name proc-buf))))))
        (cl-incf killed)
        (message "Killing gptel/subagent process: %s" (process-name proc))
        ;; Prevent sentinels/filters from writing into buffers after abort.
        (ignore-errors (set-process-filter proc #'ignore))
        (ignore-errors (set-process-sentinel proc #'ignore))
        (delete-process proc)))
    ;; Restore header-line: first reset to gptel's stock format, then re-inject
    ;; the nucleus [Plan]/[Agent] toggle on top.  Calling gptel-use-header-line
    ;; alone blows away the toggle; nucleus--header-line-apply-preset-label
    ;; alone doesn't work if header-line-format was wiped by gptel internals.
    (let ((gptel-mode-val (bound-and-true-p gptel-mode))
          (gptel-use-hl (bound-and-true-p gptel-use-header-line)))
      (when (and gptel-mode-val gptel-use-hl)
        (when (fboundp 'gptel-use-header-line)
          (gptel-use-header-line))
        (when (fboundp 'nucleus--header-line-apply-preset-label)
          (nucleus--header-line-apply-preset-label)))
      ;; Add prompt marker and position cursor for next input
      (when gptel-mode-val
        (let ((inhibit-read-only t))
          (goto-char (point-max))
          (my/gptel--insert-prompt-marker-at-eob)
          ;; Position cursor after marker
          (my/gptel--goto-prompt-marker-end))))
    (message "Aborted gptel activity (%d process%s killed) - ready for next prompt"
             killed (if (= killed 1) "" "es"))))

;; --- Prompt Marker After Response ---
;; When gptel-agent finishes, add ### marker and position cursor for next prompt

(defun my/gptel--has-fsm-error-p ()
  "Return non-nil if current buffer's FSM has an error.
Returns nil if no FSM, not a proper plist, or no error."
  (when (boundp 'gptel--fsm-last)
    (let* ((fsm-val (buffer-local-value 'gptel--fsm-last (current-buffer)))
           (fsm (and fsm-val (my/gptel--coerce-fsm fsm-val)))
           (info (and fsm
                      (fboundp 'gptel-fsm-info)
                      (gptel-fsm-info fsm))))
      (and (proper-list-p info) (plist-get info :error)))))
(defun my/gptel--valid-position-p (pos)
  "Return non-nil if POS is a valid buffer position for `goto-char`.
A valid position is a positive integer <= (point-max) in current buffer.
Returns nil for nil or out-of-bounds values."
  (when (and (integerp pos) (> pos 0))
    (<= pos (point-max))))

(defun my/gptel--validate-end-for-goto (end)
  "Return END if valid for `goto-char`, or fallback to (point-max).
This prevents crashes when END is nil or out-of-bounds."
  (if (my/gptel--valid-position-p end) end (point-max)))

(defun my/gptel-add-prompt-marker (_start end)
  "Add a prompt marker after the response and move point there.

START and END are the response region positions passed by
`gptel-post-response-functions'."
  (when (and gptel-mode
             (not (my/gptel--has-fsm-error-p))
             (my/gptel--valid-position-p end))
    (save-excursion
      (goto-char end)
      ;; Only add marker if not already present at EOB
      (my/gptel--insert-prompt-marker-at-eob))
    ;; Move cursor to end for immediate typing
    (my/gptel--goto-prompt-marker-end)))

;; --- Keybindings & Hooks ---
(with-eval-after-load 'gptel
  (add-hook 'gptel-post-response-functions #'my/gptel-add-prompt-marker)
  (when (boundp 'gptel-mode-map)
    ;; C-g in gptel buffers: abort the active request, then quit normally.
    (define-key gptel-mode-map [remap keyboard-quit] #'my/gptel-keyboard-quit)
    ;; A dedicated abort binding (muscle memory from terminal "Ctrl-C").
    (define-key gptel-mode-map (kbd "C-c C-k") #'my/gptel-abort-here)))

(provide 'gptel-ext-abort)
;;; gptel-ext-abort.el ends here
