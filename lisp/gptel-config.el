;;; gptel-config.el --- Clean, modular gptel configuration -*- lexical-binding: t; -*-

(add-to-list 'load-path
             (expand-file-name "modules"
                               (file-name-directory (or load-file-name
                                                        buffer-file-name
                                                        (locate-library "gptel-config")
                                                        (expand-file-name "lisp/gptel-config.el" user-emacs-directory)))))

(require 'gptel-ext-core)
(require 'gptel-ext-backends)
(require 'gptel-ext-context)
(require 'gptel-ext-learning)
(require 'gptel-ext-patch)
(require 'gptel-ext-tools)
(require 'gptel-ext-security)

;; --- Configuration Defaults ---
;; gptel-agent buffers use DashScope + qwen3.5-plus (set via preset).
;; Plain gptel buffers use Moonshot + kimi-k2.5 (set via mode hook).
;; The global default drives both the gptel-agent preset resolution and
;; the buffer-name prompt in M-x gptel.  Set it to Moonshot so the prompt
;; shows *Moonshot* instead of *OpenRouter*.
(setq gptel-backend gptel--moonshot
      gptel-model 'kimi-k2.5)

;; Control tool confirmation:
;; 'auto -> respect the `:confirm t` flag on individual tools
;; nil   -> auto-execute ALL tools without prompting
;; t     -> always prompt for ALL tools
;;
;; Default: never ask (matches `C-c C-a` "never ask again").
(setq gptel-confirm-tool-calls 'auto)
(setq-default gptel-confirm-tool-calls 'auto)



;; --- Keybindings & UI Helpers ---
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

(defun my/gptel-tool-confirmation-never ()
  "Disable tool call confirmation everywhere.

Sets `gptel-confirm-tool-calls' to nil globally (and for existing gptel
buffers) so tool calls never pause for confirmation." 
  (interactive)
  (setq gptel-confirm-tool-calls nil)
  (setq-default gptel-confirm-tool-calls nil)
  (dolist (b (buffer-list))
    (with-current-buffer b
      (when (derived-mode-p 'gptel-mode)
        (setq-local gptel-confirm-tool-calls nil))))
  (message "gptel Tool Confirmation: OFF (Auto-executes everything)"))

(defun my/gptel-tool-confirmation-auto ()
  "Restore default tool call confirmation behavior.

Sets `gptel-confirm-tool-calls' to 'auto globally (and for existing gptel
buffers) so each tool's :confirm flag decides." 
  (interactive)
  (setq gptel-confirm-tool-calls 'auto)
  (setq-default gptel-confirm-tool-calls 'auto)
  (dolist (b (buffer-list))
    (with-current-buffer b
      (when (derived-mode-p 'gptel-mode)
        (setq-local gptel-confirm-tool-calls 'auto))))
  (message "gptel Tool Confirmation: AUTO (Respects tool flags)"))


(provide 'gptel-config)
;;; gptel-config.el ends here

(provide 'gptel-config)
;;; gptel-config.el ends here
