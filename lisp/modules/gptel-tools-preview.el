;;; gptel-tools-preview.el --- Preview tool for gptel -*- lexical-binding: t; -*-

;; Author: David Wu
;; Version: 3.0.0
;;
;; Unified Preview tool for file changes and patches.
;; Also provides `my/gptel--preview-patch-async' for ApplyPatch/Edit integration.

;;; Code:

(require 'cl-lib)
(require 'subr-x)
(require 'diff-mode)
(require 'gptel-ext-fsm-utils)

;;; Customization

(defgroup gptel-tools-preview nil
  "Preview tool for gptel-agent."
  :group 'gptel)

(defcustom gptel-tools-preview-enabled t
  "Whether to show preview before applying changes.

When non-nil (default), shows a diff preview and prompts for confirmation.
When nil, applies changes immediately without preview or confirmation.

Set to nil for:
  - Trusted environments (local development)
  - CI/CD pipelines
  - Power users who prefer speed over safety
  - Batch operations where preview is tedious

Warning: Disabling preview means changes are applied immediately
without user confirmation. Use with caution in production environments."
  :type 'boolean
  :group 'gptel-tools-preview)

(defvar gptel-tools-preview--never-ask-again nil
  "If non-nil, skip all future preview confirmations this session.

Set to t when user answers 'N' (never ask again) to a preview prompt.
Resets to nil when Emacs restarts or when user manually resets via
`gptel-tools-preview-reset-confirmation'.

See also `gptel-tools-preview-enabled' for permanent disable.")

(defun gptel-tools-preview-reset-confirmation ()
  "Reset the 'never ask again' flag.
Re-enables preview confirmations for the rest of this session."
  (interactive)
  (setq gptel-tools-preview--never-ask-again nil)
  (message "Preview confirmations re-enabled for this session."))

(defcustom gptel-tools-preview-window-height 0.4
  "Height of preview windows as fraction of frame."
  :type 'float
  :group 'gptel-tools-preview)

;;; Core Preview Functions

(defun my/gptel--make-preview-callback (buffer callback)
  "Wrap CALLBACK as an idempotent, FSM-restoring preview callback.

Saves the current `gptel--fsm-last' from BUFFER and returns a function
that, on first invocation only, restores the FSM state and calls CALLBACK
with its argument in the buffer context.  Subsequent calls are no-ops."
  (let ((parent-fsm (my/gptel--coerce-fsm
                     (buffer-local-value 'gptel--fsm-last buffer)))
        (cb-called nil))
    (lambda (result)
      (unless cb-called
        (setq cb-called t)
        (if (buffer-live-p buffer)
            (with-current-buffer buffer
              (setq-local gptel--fsm-last parent-fsm)
              (funcall callback result))
          (funcall callback result))))))

(defun my/gptel--setup-preview-keys (buffer on-confirm on-abort)
  "Set up confirmation for preview BUFFER.

ON-CONFIRM and ON-ABORT are called with no arguments when the user
confirms or aborts respectively.

Confirmation happens via minibuffer prompt, not keybindings.
This keeps the preview buffer focused on the diff content."
  ;; Display the buffer first, then prompt
  (my/gptel--prompt-for-confirmation buffer on-confirm on-abort))

(defun my/gptel--create-diff-buffer (name header &optional content mode)
  "Create a diff buffer named NAME with HEADER and CONTENT.

MODE is the major mode to activate (defaults to diff-mode).
Returns the buffer."
  (let ((buf (get-buffer-create name)))
    (with-current-buffer buf
      (erase-buffer)
      (insert header "\n\n")
      (when content
        (insert content))
      (when mode
        (funcall mode))
      (setq-local buffer-read-only t))
    buf))

(defun my/gptel--insert-preview-instructions ()
  "Insert preview instructions at the top of the preview buffer.

Adds a separator line to make the diff content more readable.
Confirmation happens in the minibuffer, not via keybindings."
  (let ((inhibit-read-only t))
    (goto-char (point-min))
    (forward-line 1)
    (insert "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
    (insert "Diff Preview - Confirm in minibuffer\n")
    (insert "  y = apply    n = abort    ! = apply all    q = quit\n")
    (insert "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n")))

(defun my/gptel--prompt-for-confirmation (buffer on-confirm on-abort)
  "Prompt user for confirmation in minibuffer.

BUFFER is the preview buffer being shown.
ON-CONFIRM is called if user accepts.
ON-ABORT is called if user rejects.

Prompts in minibuffer: 'Apply changes? (y/n/!/q)'
  y - Yes, apply this change
  n - No, abort this change
  ! - Apply all (never ask again this session)
  q - Quit (same as n)

This is a blocking call - user must respond before Emacs continues."
  (if gptel-tools-preview--never-ask-again
      ;; Never-ask-again was set earlier - auto-confirm
      (progn
        (when (buffer-live-p buffer)
          (kill-buffer buffer))
        (funcall on-confirm))
    ;; Normal flow - prompt user
    (unwind-protect
        (let ((prompt (format "Apply changes? [y=yes, n=no, !=all, q=quit]: ")))
          (condition-case err
              (let* ((result (read-from-minibuffer prompt))
                     (confirm (member result '("y" "Y" "")))
                     (abort (member result '("n" "N" "q" "Q")))
                     (apply-all (member result '("!" "a" "A"))))
                (cond
                 (apply-all
                  (setq gptel-tools-preview--never-ask-again t)
                  (message "Preview confirmations disabled for this session. M-x gptel-tools-preview-reset-confirmation to re-enable.")
                  (funcall on-confirm))
                 (confirm
                  (funcall on-confirm))
                 (abort
                  (funcall on-abort))
                 (t
                  (funcall on-abort))))
            (quit
             (funcall on-abort))
            (error
             (funcall on-abort))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

;;; File Change Preview (path + original + replacement → diff)

(defun my/gptel--preview-file-change (buffer path original replacement callback)
  "Preview file change for BUFFER.

Shows diff between ORIGINAL and REPLACEMENT for PATH.
CALLBACK is called when user confirms or aborts.

When `gptel-tools-preview-enabled' is nil, or when
`gptel-tools-preview--never-ask-again' is t, skips preview and
confirms immediately (use with caution)."
  (if (or (not gptel-tools-preview-enabled)
           gptel-tools-preview--never-ask-again)
      ;; Preview disabled - auto-confirm
      (funcall callback "Preview disabled, auto-confirmed.")
    ;; Preview enabled - show diff and prompt
    (condition-case err
        (let* ((wrapped-cb (my/gptel--make-preview-callback buffer callback))
               (temp1 (my/gptel-make-temp-file "orig"))
               (temp2 (my/gptel-make-temp-file "new"))
               (diff-output
                (progn
                  (write-region original nil temp1 nil 'silent)
                  (write-region replacement nil temp2 nil 'silent)
                  (my/gptel--run-diff temp1 temp2))))
          (unwind-protect
              (let ((diff-buf (my/gptel--create-diff-buffer
                               "*gptel-preview*"
                               (format "Preview: %s" path)
                               diff-output
                               #'diff-mode)))
                (my/gptel--insert-preview-instructions)
                (my/gptel--display-preview-buffer diff-buf)
                (my/gptel--setup-preview-keys
                 diff-buf
                 (lambda () (funcall wrapped-cb "Preview confirmed."))
                 (lambda () (funcall wrapped-cb "Preview aborted."))))
            (delete-file temp1)
            (delete-file temp2)))
      (error
       (funcall callback (format "Preview error: %s" (error-message-string err)))))))

;;; Patch Preview (raw unified diff)

(defun my/gptel--preview-patch (patch buffer callback header)
  "Show patch preview.

PATCH is the unified diff content.
BUFFER is the originating buffer.
CALLBACK is called with the result.
HEADER is the prompt to show.

When `gptel-tools-preview-enabled' is nil, or when
`gptel-tools-preview--never-ask-again' is t, skips preview and
confirms immediately (use with caution)."
  (if (or (not gptel-tools-preview-enabled)
           gptel-tools-preview--never-ask-again)
      ;; Preview disabled - auto-confirm
      (funcall callback "Preview disabled, auto-confirmed.")
    ;; Preview enabled
    (let* ((wrapped-cb (my/gptel--make-preview-callback buffer callback))
           (diff-buf (my/gptel--create-diff-buffer
                      "*gptel-patch-preview*"
                      header
                      patch
                      #'diff-mode)))
      (my/gptel--insert-preview-instructions)
      (my/gptel--display-preview-buffer diff-buf)
      (my/gptel--setup-preview-keys
       diff-buf
       (lambda () (funcall wrapped-cb "Patch confirmed."))
       (lambda () (funcall wrapped-cb "Patch aborted."))))))

(defun my/gptel--preview-patch-async (patch buffer callback on-confirm on-abort header)
  "Show patch preview asynchronously for ApplyPatch/Edit tool integration.

PATCH is the unified diff content.
BUFFER is the originating buffer.
CALLBACK is called with the result.
ON-CONFIRM is called with wrapped callback when user confirms.
ON-ABORT is called with wrapped callback when user aborts.
HEADER is the prompt to show.

When `gptel-tools-preview-enabled' is nil, or when
`gptel-tools-preview--never-ask-again' is t, skips preview and calls
ON-CONFIRM immediately (use with caution)."
  (if (or (not gptel-tools-preview-enabled)
           gptel-tools-preview--never-ask-again)
      ;; Preview disabled - auto-confirm
      (funcall on-confirm callback)
    ;; Preview enabled
    (let* ((wrapped-cb (my/gptel--make-preview-callback buffer callback))
           (diff-buf (my/gptel--create-diff-buffer
                      "*gptel-patch-preview*"
                      header
                      patch
                      #'diff-mode)))
      (my/gptel--insert-preview-instructions)
      (my/gptel--display-preview-buffer diff-buf)
      (my/gptel--setup-preview-keys
       diff-buf
       (lambda () (funcall on-confirm wrapped-cb))
       (lambda () (funcall on-abort wrapped-cb))))))

;;; Tool Registration

(defun gptel-tools-preview-register ()
  "Register the unified Preview tool with gptel.

Accepts either:
  - path + replacement (optional original) → generates and shows diff
  - patch (raw unified diff) → shows diff directly

Auto-detects mode from which arguments are provided."
  (when (fboundp 'gptel-make-tool)
    (gptel-make-tool
     :name "Preview"
     :async t
     :category "gptel-agent"
     :function (lambda (callback &optional path original replacement patch)
                 (cond
                  ;; Mode 1: raw patch (unified diff)
                  ((and patch (stringp patch) (not (string-empty-p patch)))
                   (my/gptel--preview-patch
                    patch
                    (current-buffer)
                    callback
                    (format "Preview: %s — n reviewed    q abort"
                            (or path "patch"))))

                  ;; Mode 2: path + replacement → generate diff
                  ((and path replacement)
                   (let* ((full-path (expand-file-name path))
                          (orig (or original
                                    (when (file-readable-p full-path)
                                      (with-temp-buffer
                                        (insert-file-contents full-path)
                                        (buffer-string)))))
                          (new (or replacement "")))
                     (if (not orig)
                         (funcall callback
                                  (format "Error: Cannot read original content for %s" path))
                       (my/gptel--preview-file-change
                        (current-buffer) path orig new callback))))

                  ;; Error: insufficient arguments
                  (t
                   (funcall callback
                            "Error: Preview requires either (path + replacement) or (patch)."))))
     :description "Preview file changes or patches with diff view. Provide either path+replacement or a unified diff patch."
     :args '((:name "path"
              :type string
              :description "Target file path (for file change mode)"
              :optional t)
             (:name "original"
              :type string
              :description "Original content (auto-read from file if omitted)"
              :optional t)
             (:name "replacement"
              :type string
              :description "Replacement content (for file change mode)"
              :optional t)
             (:name "patch"
              :type string
              :description "Unified diff content (for patch mode)"
              :optional t))
     :confirm t)))

;;; Footer

(provide 'gptel-tools-preview)

;;; gptel-tools-preview.el ends here
