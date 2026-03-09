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

(defcustom gptel-tools-preview-window-height 0.4
  "Height of preview windows as fraction of frame."
  :type 'float
  :group 'gptel-tools-preview)

(defcustom gptel-tools-preview-timeout 300
  "Seconds before an unattended preview auto-aborts.
Set to nil to disable the timeout."
  :type '(choice integer (const nil))
  :group 'gptel-tools-preview)

;;; Core Preview Functions

(defun my/gptel--make-preview-callback (buffer callback)
  "Wrap CALLBACK as an idempotent, FSM-restoring preview callback.

Saves the current `gptel--fsm-last' from BUFFER and returns a function
that, on first invocation only, restores the FSM state and calls CALLBACK
with its argument.  Subsequent calls are no-ops."
  (let ((parent-fsm (my/gptel--coerce-fsm
                     (buffer-local-value 'gptel--fsm-last buffer)))
        (cb-called nil))
    (lambda (result)
      (unless cb-called
        (setq cb-called t)
        (when (buffer-live-p buffer)
          (with-current-buffer buffer
            (setq-local gptel--fsm-last parent-fsm)))
        (funcall callback result)))))

(defun my/gptel--setup-preview-keys (buffer on-confirm on-abort)
  "Set up local keys in preview BUFFER for confirmation.

ON-CONFIRM and ON-ABORT are called with no arguments when the user
presses n/y or q respectively."
  (with-current-buffer buffer
    (let ((map (make-sparse-keymap)))
      (set-keymap-parent map (current-local-map))
      (define-key map (kbd "n") (lambda () (interactive) (funcall on-confirm) (kill-buffer buffer)))
      (define-key map (kbd "y") (lambda () (interactive) (funcall on-confirm) (kill-buffer buffer)))
      (define-key map (kbd "q") (lambda () (interactive) (funcall on-abort) (kill-buffer buffer)))
      (use-local-map map))))

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

(defun my/gptel--display-preview-buffer (buffer &optional height)
  "Display BUFFER with HEIGHT as fraction of frame.

Returns the window displaying the buffer."
  (display-buffer buffer
                  `(display-buffer-reuse-window
                    display-buffer-below-selected
                    (window-height . ,(or height gptel-tools-preview-window-height)))))

(defun my/gptel--preview-start-timeout (buffer)
  "Start a timeout timer for preview BUFFER.

After `gptel-tools-preview-timeout' seconds, kills BUFFER which
triggers the kill-buffer-hook abort path.  Returns the timer, or
nil if timeouts are disabled.

The timer is stored as a buffer-local variable and cancelled
automatically on buffer kill via kill-buffer-hook."
  (when gptel-tools-preview-timeout
    (let ((timer (run-at-time
                  gptel-tools-preview-timeout nil
                  (lambda ()
                    (when (buffer-live-p buffer)
                      (message "[gptel-preview] Timeout after %ds, aborting preview"
                               gptel-tools-preview-timeout)
                      (kill-buffer buffer))))))
      (with-current-buffer buffer
        (setq-local my/gptel--preview-timer timer)
        (add-hook 'kill-buffer-hook
                  (lambda ()
                    (when (timerp my/gptel--preview-timer)
                      (cancel-timer my/gptel--preview-timer)))
                  nil t))
      timer)))

(defun my/gptel--run-diff (temp1 temp2)
  "Run diff between TEMP1 and TEMP2 files.

Returns the diff output string."
  (with-temp-buffer
    (apply #'call-process "diff" nil t nil (list "-u" temp1 temp2))
    (buffer-string)))

;;; File Change Preview (path + original + replacement → diff)

(defun my/gptel--preview-file-change (buffer path original replacement callback)
  "Preview file change for BUFFER.

Shows diff between ORIGINAL and REPLACEMENT for PATH.
CALLBACK is called when user confirms or aborts."
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
          (add-hook 'kill-buffer-hook
                    (lambda () (funcall wrapped-cb "Preview aborted."))
                    nil t)
          (my/gptel--display-preview-buffer diff-buf)
          (my/gptel--preview-start-timeout diff-buf)
          (my/gptel--setup-preview-keys
           diff-buf
           (lambda () (funcall wrapped-cb "Preview confirmed."))
           (lambda () (funcall wrapped-cb "Preview aborted."))))
      (delete-file temp1)
      (delete-file temp2))))

;;; Patch Preview (raw unified diff)

(defun my/gptel--preview-patch (patch buffer callback header)
  "Show patch preview.

PATCH is the unified diff content.
BUFFER is the originating buffer.
CALLBACK is called with the result.
HEADER is the prompt to show."
  (let* ((wrapped-cb (my/gptel--make-preview-callback buffer callback))
         (diff-buf (my/gptel--create-diff-buffer
                    "*gptel-patch-preview*"
                    header
                    patch
                    #'diff-mode)))
    (add-hook 'kill-buffer-hook
              (lambda () (funcall wrapped-cb "Preview aborted."))
              nil t)
    (my/gptel--display-preview-buffer diff-buf)
    (my/gptel--preview-start-timeout diff-buf)
    (my/gptel--setup-preview-keys
     diff-buf
     (lambda () (funcall wrapped-cb "Patch reviewed. Not applied."))
     (lambda () (funcall wrapped-cb "Patch preview aborted.")))))

(defun my/gptel--preview-patch-async (patch buffer callback on-confirm on-abort header)
  "Show patch preview asynchronously for ApplyPatch/Edit tool integration.

PATCH is the unified diff content.
BUFFER is the originating buffer.
CALLBACK is called with the result.
ON-CONFIRM is called with wrapped callback when user confirms.
ON-ABORT is called with wrapped callback when user aborts.
HEADER is the prompt to show."
  (let* ((wrapped-cb (my/gptel--make-preview-callback buffer callback))
         (diff-buf (my/gptel--create-diff-buffer
                    "*gptel-patch-preview*"
                    header
                    patch
                    #'diff-mode)))
    (with-current-buffer diff-buf
      (add-hook 'kill-buffer-hook
                (lambda () (funcall on-abort wrapped-cb))
                nil t))
    (my/gptel--display-preview-buffer diff-buf)
    (my/gptel--preview-start-timeout diff-buf)
    (my/gptel--setup-preview-keys
     diff-buf
     (lambda () (funcall on-confirm wrapped-cb))
     (lambda () (funcall on-abort wrapped-cb)))))

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
