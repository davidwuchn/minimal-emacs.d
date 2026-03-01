;;; gptel-config.el --- Clean, modular gptel configuration -*- lexical-binding: t -*-

(eval-and-compile
  (let* ((base-dir (if (boundp 'minimal-emacs-user-directory)
                       minimal-emacs-user-directory
                     "~/.emacs.d/"))
         (modules-dir (expand-file-name "lisp/modules" base-dir)))
    (add-to-list 'load-path (file-truename modules-dir))))

(require 'gptel-ext-core)
(require 'gptel-ext-backends)
(require 'gptel-ext-context)
(require 'gptel-ext-learning)
(require 'gptel-ext-security)

;; Load split tool modules (replaces gptel-ext-tools.el)
(require 'gptel-tools)
(gptel-tools-setup)



;; Load tool usage analytics
(require 'nucleus-analytics)

;; Load tool verification (checks all declared tools are registered)
(require 'nucleus-tools-verify)

;; Load tool signature validation (validates prompt args match registration)
(require 'nucleus-tools-validate)

;; Load enhanced tool UI (patches keymap AFTER gptel loads)
(require 'gptel-tool-ui)

;; --- Configuration Defaults ---
(setq gptel-backend gptel--dashscope
      gptel-model 'qwen3.5-plus)

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
  "Disable tool call confirmation everywhere."
  (interactive)
  (setq gptel-confirm-tool-calls nil)
  (setq-default gptel-confirm-tool-calls nil)
  (dolist (b (buffer-list))
    (with-current-buffer b
      (when (derived-mode-p 'gptel-mode)
        (setq-local gptel-confirm-tool-calls nil))))
  (message "gptel Tool Confirmation: OFF (Auto-executes everything)"))

(defun my/gptel-tool-confirmation-auto ()
  "Restore default tool call confirmation behavior."
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

