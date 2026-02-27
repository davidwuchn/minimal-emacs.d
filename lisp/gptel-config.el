;;; gptel-config.el --- Clean, modular gptel configuration -*- lexical-binding: t; -*-

(eval-and-compile
  (let ((dir (or (and (boundp 'load-file-name) load-file-name)
                 (and (boundp 'byte-compile-current-file) byte-compile-current-file)
                 buffer-file-name
                 (expand-file-name "lisp/gptel-config.el" user-emacs-directory))))
    (add-to-list 'load-path (expand-file-name "modules" (file-name-directory dir)))))

(require 'gptel-ext-core)
(require 'gptel-ext-backends)
(require 'gptel-ext-context)
(require 'gptel-ext-learning)
(require 'gptel-ext-patch)
(require 'gptel-ext-security)

;; Load new split tool modules (replaces gptel-ext-tools.el)
(require 'gptel-tools)

;; Load nucleus tools (consolidated tool definitions)
(require 'nucleus-tools)
;; --- Configuration Defaults ---
(setq gptel-backend gptel--moonshot
      gptel-model 'kimi-k2.5)

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
