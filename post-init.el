;;; post-init.el --- User configuration -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Commentary:
;; Personal configuration and overrides. Add your customizations here.
;; This file is loaded after all modular configuration files.

;;; Code:

;; Add the local lisp directory to Emacs' load path using the true root directory
;; (not user-emacs-directory, since we changed that to var/)
(add-to-list 'load-path (expand-file-name "lisp" minimal-emacs-user-directory))

;; Load the modular configuration files
(require 'init-system)
(require 'init-completion)
(require 'init-evil)
(require 'init-dev)
(require 'init-tools)
(require 'init-org)      ; Org mode configuration
(require 'init-ai)

;; Backup and auto-save settings are configured in init-files.el

;; ==============================================================================
;; PERSONAL CUSTOMIZATIONS (Add your own below)
;; ==============================================================================

;; Example: Set your preferred theme
;; (load-theme 'doom-one t)

;; Example: Custom key bindings
;; (global-set-key (kbd "C-c w") #'whitespace-mode)

;; ==============================================================================
;; FIX: Mode-line restoration for buffers created during startup
;; ==============================================================================
;; Upstream early-init.el only restores mode-line for buffers that had
;; minimal-emacs--hidden-mode-line set. Buffers created during startup
;; with nil mode-line are skipped. This fixes that.

(defun my/fix-mode-line-for-all-buffers ()
  "Ensure all buffers have a proper mode-line-format.
Buffers created during startup may have nil mode-line if they
were created after the hiding but before restoration."
  (when (and (boundp 'minimal-emacs-disable-mode-line-during-startup)
             minimal-emacs-disable-mode-line-during-startup)
    (dolist (buf (buffer-list))
      (when (buffer-live-p buf)
        (with-current-buffer buf
          ;; Buffer has nil mode-line as local var - restore to default
          (when (and (local-variable-p 'mode-line-format)
                     (eq mode-line-format nil))
            (kill-local-variable 'mode-line-format)))))))

;; Run after all init is complete
(add-hook 'emacs-startup-hook #'my/fix-mode-line-for-all-buffers 100)



;;; post-init.el ends here

;; ==============================================================================
;; RELOAD THEME-SETTING.EL FOR NEW GUI FRAMES
;; ==============================================================================
(defun my/reload-theme-setting-for-frame (frame)
  "Reload theme-setting.el for FRAME to apply all visual settings."
  (when (display-graphic-p frame)
    (select-frame frame)
    ;; Reload the entire theme configuration file
    (load-file "~/.emacs.d/lisp/theme-setting.el")
    (message "✅ Reloaded theme-setting.el for new frame")))

;; Apply all settings from theme-setting.el to every new GUI frame
(add-hook 'after-make-frame-functions #'my/reload-theme-setting-for-frame)

;; Load theme initially for non-daemon mode
(unless (daemonp)
  (load-file "~/.emacs.d/lisp/theme-setting.el"))
