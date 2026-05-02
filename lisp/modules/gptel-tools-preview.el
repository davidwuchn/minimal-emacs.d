;;; gptel-tools-preview.el --- Preview tool for gptel -*- no-byte-compile: t; lexical-binding: t; -*-

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

(declare-function my/gptel-make-temp-file "gptel-ext-core")
(declare-function my/gptel-permit-tool "gptel-ext-tool-permits")

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
  :group 'gptel-tools-preview
  :version "3.1.0")

(defvar gptel-tools-preview--never-ask-again nil
  "If non-nil, skip all future preview confirmations this session.

DEPRECATED: Use `my/gptel-permit-tool' instead for explicit per-tool permits.
This variable is kept for backward compatibility.")

(defun gptel-tools-preview-reset-confirmation ()
  "Reset the 'never ask again' flag.
Re-enables preview confirmations for the rest of this session.

DEPRECATED: Use `my/gptel-clear-permits' instead."
  (interactive)
  (setq gptel-tools-preview--never-ask-again nil)
  (when (fboundp 'my/gptel-clear-permits)
    (my/gptel-clear-permits))
  (message "Preview confirmations re-enabled for this session."))

(defcustom gptel-tools-preview-window-height 0.4
  "Height of preview windows as fraction of frame."
  :type 'float
  :group 'gptel-tools-preview
  :version "3.1.0")

(defcustom gptel-tools-preview-max-patch-size 100000
  "Maximum patch size in characters before rejecting.
Prevents DoS via memory exhaustion from extremely large patches.
Set to 0 for unlimited."
  :type 'integer
  :group 'gptel-tools-preview)

(defcustom gptel-tools-preview-max-replacement-size 1000000
  "Maximum replacement content size in characters.
Prevents DoS via memory exhaustion from extremely large replacements.
Set to 0 for unlimited."
  :type 'integer
  :group 'gptel-tools-preview)

;;; Core Preview Functions

;; Forward declaration for headless mode check
(defvar gptel-auto-workflow--headless nil)

(defun my/gptel--preview-bypass-p ()
  "Return non-nil if preview should be bypassed.

Preview is a safety net for mutating operations.  It should normally
ALWAYS show.  Only bypass when:
1. `gptel-tools-preview-enabled' is nil (global disable)
2. `gptel-tools-preview--never-ask-again' is t (deprecated, for backward compat)
3. `gptel-auto-workflow--headless' is t (auto-workflow mode)

Permits are NOT checked here - they control the tool confirm UI,
not the preview.  Preview is the final safety check before applying changes."
  (or (not gptel-tools-preview-enabled)
      gptel-tools-preview--never-ask-again
      (and (boundp 'gptel-auto-workflow--headless)
           gptel-auto-workflow--headless)))

(defun my/gptel--validate-file-path (path)
  "Validate PATH for safety in file operations.
Returns nil if safe, or error message string if unsafe."
  (cond
   ((not (stringp path))
    "Path must be a string")
   ((string-empty-p path)
    "Path cannot be empty")
   ((string-match-p "\\`\\.\\./" path)
    "Path traversal detected (starts with ../)")
   ((string-match-p "/\\.\\./" path)
    "Path traversal detected (contains /../)")
   ((string-match-p "\0" path)
    "Null byte in path")
   (t nil)))

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

(defun my/gptel--prompt-for-preview-action (buffer on-confirm on-abort)
  "Prompt for preview action in BUFFER.

ON-CONFIRM and ON-ABORT are called with no arguments when the user
confirms or aborts respectively.

Confirmation happens via minibuffer prompt, not keybindings.
This keeps the preview buffer focused on the diff content."
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

(defun my/gptel--insert-preview-instructions (&optional buffer)
  "Insert preview instructions at the top of the preview buffer.

BUFFER is the buffer to insert into (defaults to current buffer).
Adds a separator line to make the diff content more readable.
Confirmation happens in the minibuffer, not via keybindings."
  (with-current-buffer (or buffer (current-buffer))
    (let ((inhibit-read-only t))
      (goto-char (point-min))
      (forward-line 1)
      (insert "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n")
      (insert "Diff Preview - Confirm in minibuffer\n")
      (insert "  y = apply    n = abort    ! = permit+apply    q = quit\n")
      (insert "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"))))

(defun my/gptel--run-diff (file1 file2)
  "Run diff between FILE1 and FILE2.

Returns the unified diff output as a string."
  (with-temp-buffer
    (apply #'call-process "diff" nil t nil (list "-u" file1 file2))
    (buffer-string)))

(defun my/gptel--unique-preview-buffer-name (base)
  "Generate a unique buffer name based on BASE.

Uses a timestamp suffix to avoid conflicts when multiple previews
run concurrently.  Format: BASE-HHMMSS."
  (format "%s-%s" base (format-time-string "%H%M%S" (current-time))))

(defun my/gptel--display-preview-buffer (buffer)
  "Display preview BUFFER in a window.

Uses `gptel-tools-preview-window-height' for window height.
Returns the window displaying the buffer."
  (let ((window (display-buffer buffer '(display-buffer-below-selected
                                         (window-height . fit-window-to-buffer)
                                         (body-function . (lambda (_)
                                                            (goto-char (point-min))))))))
    (when window
      (with-selected-window window
        (fit-window-to-buffer nil
                              (truncate (* (frame-height) gptel-tools-preview-window-height)))))
    window))

(defvar my/gptel--preview-tool-name nil
  "Dynamically bound to the tool name that triggered the current preview.")

(defun my/gptel--prompt-for-confirmation (buffer on-confirm on-abort)
  "Prompt user for confirmation in minibuffer.

BUFFER is the preview buffer being shown.
ON-CONFIRM is called if user accepts.
ON-ABORT is called if user rejects.

Prompts in minibuffer: 'Apply changes? (y/n/!/q)'
  y - Yes, apply this change
  n - No, abort this change
  ! - Permit this tool and apply (adds to my/gptel-permitted-tools)
  q - Quit (same as n)

This is a blocking call - user must respond before Emacs continues."
  (if gptel-tools-preview--never-ask-again
      ;; Never-ask-again was set earlier - auto-confirm (backward compat)
      ;; Call callback FIRST, then clean up buffer (callback may reference it)
      (prog2
          (funcall on-confirm)
          (when (buffer-live-p buffer)
            (kill-buffer buffer)))
    ;; Normal flow - prompt user
    (unwind-protect
        (let ((prompt (format "Apply changes? [y=yes, n=no, !=permit+apply, q=quit]: ")))
          (condition-case err
              (let* ((result (read-from-minibuffer prompt))
                     (confirm (member result '("y" "Y" "")))
                     (abort (member result '("n" "N" "q" "Q")))
                     (permit-and-apply (member result '("!" "a" "A"))))
                (cond
                 (permit-and-apply
                  ;; Add tool to permits for future calls
                  (when (and my/gptel--preview-tool-name
                             (fboundp 'my/gptel-permit-tool))
                    (my/gptel-permit-tool my/gptel--preview-tool-name)
                    (message "Tool '%s' permitted for this session. Future calls will skip confirm UI."
                             my/gptel--preview-tool-name))
                  ;; Also set legacy flag for preview
                  (setq gptel-tools-preview--never-ask-again t)
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

Validates PATH for traversal attacks and REPLACEMENT size.
Skips preview when `my/gptel--preview-bypass-p' returns non-nil."
  (let ((path-error (my/gptel--validate-file-path path)))
    (cond
     (path-error
      (funcall callback (format "Error: %s" path-error)))
     ((not (stringp original))
      (funcall callback (format "Error: Original content must be a string, got %s"
                                (type-of original))))
     ((and (> gptel-tools-preview-max-replacement-size 0)
           replacement
           (> (length replacement) gptel-tools-preview-max-replacement-size))
      (funcall callback (format "Error: Replacement too large (%d chars, max %d)"
                                (length replacement) gptel-tools-preview-max-replacement-size)))
     ((my/gptel--preview-bypass-p)
      (funcall callback "Preview disabled, auto-confirmed."))
     (t
      (let (temp1 temp2)
        (condition-case err
            (let* ((wrapped-cb (my/gptel--make-preview-callback buffer callback))
                   (diff-output
                    (progn
                      (setq temp1 (my/gptel-make-temp-file "gptel-preview-orig-"))
                      (setq temp2 (my/gptel-make-temp-file "gptel-preview-new-"))
                      (write-region original nil temp1 nil 'silent)
                      (write-region replacement nil temp2 nil 'silent)
                      (my/gptel--run-diff temp1 temp2))))
              (unwind-protect
                  (let ((diff-buf (my/gptel--create-diff-buffer
                                   (my/gptel--unique-preview-buffer-name "*gptel-preview*")
                                   (format "Preview: %s" path)
                                   diff-output
                                   #'diff-mode)))
                    (my/gptel--insert-preview-instructions diff-buf)
                    (my/gptel--display-preview-buffer diff-buf)
                    (my/gptel--prompt-for-preview-action
                     diff-buf
                     (lambda () (funcall wrapped-cb "Preview confirmed."))
                     (lambda () (funcall wrapped-cb "Preview aborted."))))
                (when (and temp1 (file-exists-p temp1))
                  (delete-file temp1))
                (when (and temp2 (file-exists-p temp2))
                  (delete-file temp2))))
          (error
           (when (and temp1 (file-exists-p temp1))
             (delete-file temp1))
           (when (and temp2 (file-exists-p temp2))
             (delete-file temp2))
           (funcall callback (format "Preview error: %s" (error-message-string err))))))))))

;;; Patch Preview (raw unified diff)

(defun my/gptel--validate-patch-path (path-str)
  "Validate PATH-STR from patch header for safety.
Returns nil if safe, or error message string if unsafe."
  (cond
   ((string-match-p "\\`\\.\\./" path-str)
    "Path traversal detected (starts with ../)")
   ((string-match-p "/\\.\\./" path-str)
    "Path traversal detected (contains /../)")
   ((string-match-p "\\`/" path-str)
    "Absolute paths not allowed in patches")
   ((string-match-p "\0" path-str)
    "Null byte in path")
   (t nil)))

(defun my/gptel--sanitize-patch (patch)
  "Sanitize PATCH content for safe display.
Strips control characters and validates format.
Checks for path traversal in ---/+++ lines.
Returns (SANITIZED-PATCH . WARNING) or (nil . ERROR) if invalid."
  (cond
   ((not (stringp patch))
    (cons nil "Patch must be a string"))
   ((and (stringp patch)
         (> gptel-tools-preview-max-patch-size 0)
         (> (length patch) gptel-tools-preview-max-patch-size))
    (cons nil (format "Patch too large (%d chars, max %d)"
                      (length patch) gptel-tools-preview-max-patch-size)))
   (t
    (let* ((sanitized (replace-regexp-in-string "[\000-\010\013-\037]" "" patch))
           (has-minus-header (string-match-p "^---" sanitized))
           (has-plus-header (string-match-p "^\\+\\+\\+" sanitized))
           (has-hunk (string-match-p "^@@" sanitized))
           (path-error
            (when (string-match "^--- \\([^\t\n]+\\)" sanitized)
              (my/gptel--validate-patch-path (match-string 1 sanitized)))))
      (cond
       (path-error
        (cons nil path-error))
       ((not has-minus-header)
        (cons nil "Patch lacks --- header"))
       ((not has-plus-header)
        (cons nil "Patch lacks +++ header"))
       ((not has-hunk)
        (cons nil "Patch lacks @@ hunk marker"))
       (t
        (cons sanitized nil)))))))

(defun my/gptel--display-patch-preview (patch-content buffer callback header on-confirm on-abort)
  "Display patch preview and prompt for user action.

PATCH-CONTENT is the sanitized patch string.
BUFFER is the originating buffer for FSM restoration.
CALLBACK is called with the result.
HEADER is the title shown in the preview buffer.
ON-CONFIRM and ON-ABORT are called with the wrapped callback
when the user confirms or aborts respectively."
  (let* ((wrapped-cb (my/gptel--make-preview-callback buffer callback))
         (diff-buf (my/gptel--create-diff-buffer
                    (my/gptel--unique-preview-buffer-name "*gptel-patch-preview*")
                    header
                    patch-content
                    #'diff-mode)))
    (my/gptel--insert-preview-instructions diff-buf)
    (my/gptel--display-preview-buffer diff-buf)
    (my/gptel--prompt-for-preview-action
     diff-buf
     (lambda () (funcall on-confirm wrapped-cb))
     (lambda () (funcall on-abort wrapped-cb)))))

(defun my/gptel--preview-patch (patch buffer callback header)
  "Show patch preview.

PATCH is the unified diff content.
BUFFER is the originating buffer.
CALLBACK is called with the result.
HEADER is the prompt to show.

Validates patch size and format before display.
Skips preview when `my/gptel--preview-bypass-p' returns non-nil."
  (if (my/gptel--preview-bypass-p)
      (funcall callback "Preview disabled, auto-confirmed.")
    (let* ((sanitized (my/gptel--sanitize-patch patch))
           (patch-content (car sanitized))
           (warning (cdr sanitized)))
      (if (not patch-content)
          (funcall callback (format "Error: %s" warning))
        (when warning
          (message "[gptel-preview] %s" warning))
        (my/gptel--display-patch-preview
         patch-content buffer callback header
         (lambda (wrapped-cb) (funcall wrapped-cb "Patch confirmed."))
         (lambda (wrapped-cb) (funcall wrapped-cb "Patch aborted.")))))))

(defun my/gptel--preview-patch-async (patch buffer callback on-confirm on-abort header &optional tool-name)
  "Show patch preview asynchronously for ApplyPatch/Edit tool integration.

PATCH is the unified diff content.
BUFFER is the originating buffer.
CALLBACK is called with the result.
ON-CONFIRM is called with wrapped callback when user confirms.
ON-ABORT is called with wrapped callback when user aborts.
HEADER is the prompt to show.
TOOL-NAME is the name of the calling tool (for \"!\" permit action).

Validates patch size and format before display.
Skips preview when `my/gptel--preview-bypass-p' returns non-nil.
When user types \"!\", TOOL-NAME is added to `my/gptel-permitted-tools'."
  (let ((my/gptel--preview-tool-name tool-name))
    (if (my/gptel--preview-bypass-p)
        (funcall on-confirm callback)
      (let* ((sanitized (my/gptel--sanitize-patch patch))
             (patch-content (car sanitized))
             (warning (cdr sanitized)))
        (if (not patch-content)
            (funcall callback (format "Error: %s" warning))
          (when warning
            (message "[gptel-preview] %s" warning))
          (my/gptel--display-patch-preview
           patch-content buffer callback header on-confirm on-abort))))))

;;; Tool Registration

(defvar gptel-tools-preview--registered nil
  "Non-nil when Preview tool has been registered with gptel.")

(defun gptel-tools-preview-register ()
  "Register the unified Preview tool with gptel.

Accepts either:
  - path + replacement (optional original) → generates and shows diff
  - patch (raw unified diff) → shows diff directly

Auto-detects mode from which arguments are provided.
Idempotent - safe to call multiple times."
  (unless gptel-tools-preview--registered
    (when (fboundp 'gptel-make-tool)
      (setq gptel-tools-preview--registered t)
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
                              (concat "Error: Invalid Preview arguments.\n"
                                      "Required one of:\n"
                                      "  1. path + replacement (file change mode)\n"
                                      "  2. patch (unified diff mode)\n"
                                      "Received: "
                                      (cond
                                       ((and path (not replacement))
                                        "path without replacement")
                                       ((and replacement (not path))
                                        "replacement without path")
                                       ((and original (or (not path) (not replacement)))
                                        "original but missing path/replacement")
                                       (t "no valid argument combination")))))))
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
        :confirm t))))

;;; Footer

(provide 'gptel-tools-preview)

;;; gptel-tools-preview.el ends here
