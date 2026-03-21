;;; gptel-config.el --- Clean, modular gptel configuration -*- no-byte-compile: t; lexical-binding: t; -*-

;; ==============================================================================
;; PATCH: Fix gptel preview handle bug (gptel.el:2156,2178)
;; ==============================================================================
;; Bug: (apply func-to-handle) fails when func-to-handle is a 1-element list
;; Error: "Wrong number of arguments: #[(_fsm) ...], 0"
;; Fix: Use funcall with explicit car/cadr

(with-eval-after-load 'gptel
  ;; Override gptel--accept-tool-calls with fixed version
  (defun my/gptel--accept-tool-calls (&optional tool-calls ov)
    "Run pending tool-calls. Fixed version with correct preview handle calling.
TOOL-CALLS is the edited tool call list, OV is the tool call dispatch
overlay in the query buffer."
    (interactive (pcase-let ((`(,resp . ,o) (get-char-property-and-overlay
                                             (point) 'gptel-tool)))
                   (list resp o)))
    (when (overlayp ov)
      (with-current-buffer (overlay-buffer ov)
        (gptel--update-status " Calling tool..." 'mode-line-emphasis)))
    (message "Continuing query...")
    (cl-loop for (tool-spec arg-plist process-tool-result) in tool-calls
             for arg-values = (gptel--map-tool-args tool-spec arg-plist)
             do
             (if (gptel-tool-async tool-spec)
                 (apply (gptel-tool-function tool-spec)
                        process-tool-result arg-values)
               (let ((result
                      (condition-case errdata
                          (apply (gptel-tool-function tool-spec) arg-values)
                        (error (mapconcat #'gptel--to-string errdata " ")))))
                 (funcall process-tool-result result))))
    (when (and (overlayp ov) (overlay-buffer ov))
      (with-current-buffer (overlay-buffer ov)
        (when-let* ((preview-handles (overlay-get ov 'previews)))
          (dolist (func-to-handle preview-handles)
            ;; FIX: Use funcall instead of apply
            (when (and (consp func-to-handle) (car func-to-handle))
              (funcall (car func-to-handle) (cadr func-to-handle)))))
        (dolist (prompt-ov (overlay-get ov 'prompt))
          (when-let* (((overlay-buffer prompt-ov))
                      (inhibit-read-only t))
            (delete-region (overlay-start prompt-ov)
                           (overlay-end prompt-ov)))))
      (delete-overlay ov)))
  
  ;; Override gptel--reject-tool-calls with fixed version
  (defun my/gptel--reject-tool-calls (&optional _tool-calls ov)
    "Cancel pending tool-calls. Fixed version with correct preview handle calling.
OV is the tool call dispatch overlay."
    (interactive (pcase-let ((`(,resp . ,o) (get-char-property-and-overlay
                                             (point) 'gptel-tool)))
                   (list resp o)))
    (gptel--update-status " Tools cancelled" 'error)
    (message (substitute-command-keys
              "Tool calls canceled.  \\[gptel-menu] to continue them!"))
    (when (and (overlayp ov) (overlay-buffer ov))
      (with-current-buffer (overlay-buffer ov)
        (when-let* ((preview-handles (overlay-get ov 'previews)))
          (dolist (func-to-handle preview-handles)
            ;; FIX: Use funcall instead of apply
            (when (and (consp func-to-handle) (car func-to-handle))
              (funcall (car func-to-handle) (cadr func-to-handle)))))
        (dolist (prompt-ov (overlay-get ov 'prompt))
          (when-let* (((overlay-buffer prompt-ov))
                      (inhibit-read-only t))
            (delete-region (overlay-start prompt-ov)
                           (overlay-end prompt-ov)))))
      (delete-overlay ov)))
  
  ;; Install the fixes
  (advice-add 'gptel--accept-tool-calls :override #'my/gptel--accept-tool-calls)
  (advice-add 'gptel--reject-tool-calls :override #'my/gptel--reject-tool-calls))

(eval-and-compile
  (let* ((base-dir (if (boundp 'minimal-emacs-user-directory)
                       minimal-emacs-user-directory
                     "~/.emacs.d/"))
         (modules-dir (expand-file-name "lisp/modules" base-dir)))
    (add-to-list 'load-path (file-truename modules-dir))))

(require 'gptel-ext-core)
(require 'gptel-ext-streaming)
(require 'gptel-ext-fsm-utils)
(require 'gptel-ext-tool-sanitize)
(require 'gptel-ext-reasoning)
(require 'gptel-ext-context-images)
(require 'gptel-ext-retry)
(require 'gptel-ext-transient)
(require 'gptel-ext-abort)
(require 'gptel-ext-tool-confirm)
(require 'gptel-ext-fsm)
(require 'gptel-ext-backends)
(require 'gptel-ext-context)
(require 'gptel-ext-context-cache)
(require 'gptel-ext-security)

;; Load split tool modules (replaces gptel-ext-tools.el)
(require 'gptel-tools)
(gptel-tools-setup)


;; Load tool verification (checks all declared tools are registered)
(require 'nucleus-tools-verify)

;; Load tool signature validation (validates prompt args match registration)
(require 'nucleus-tools-validate)

;; Load tool permit system (auto / confirm-all + per-tool permits)
(require 'gptel-ext-tool-permits)

;; Load benchmark framework (Eight Keys + Wu Xing + Evolution)
(require 'gptel-benchmark-principles)
(require 'gptel-benchmark-core)
(require 'gptel-benchmark-subagent)
(require 'gptel-benchmark-memory)
(require 'gptel-benchmark-evolution)
(require 'gptel-benchmark-auto-improve)
(require 'gptel-benchmark-integrate)
(require 'gptel-benchmark-daily)

;; Enable daily benchmark integration (auto-collect metrics on skill/workflow runs)
(gptel-benchmark-daily-setup)

;; --- Configuration Defaults ---
(setq gptel-backend gptel--dashscope
      gptel-model 'qwen3-coder-next)

;; Subagent model/backend: DEPRECATED
;; Subagents now use their YAML model: field. See assistant/agents/*.md

;; Enable media/image attachment support (required for vision models)
(setq gptel-track-media t)

;; Tool confirmation: auto (default) / confirm-all (kill switch).
;; Use M-x my/gptel-toggle-confirm to switch modes.
;; Per-tool permits remembered for the session (M-x my/gptel-show-permits).

(provide 'gptel-config)

;;; gptel-config.el ends here
