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

;; ==============================================================================
;; AUTO-SAVE SETTINGS (Prevent data loss)
;; ==============================================================================

;; Enable auto-save-mode (saves auto-save file every 300 characters or 30 seconds)
(setq auto-save-interval 300)        ; Save every 300 characters typed
(setq auto-save-timeout 30)          ; Save after 30 seconds of idle time
(setq auto-save-default t)           ; Enable auto-save by default

;; Enable auto-save-visited-mode (auto-saves visited files without prompts)
;; This is different from auto-save-mode - it actually saves the file, not just
;; an auto-save backup
(use-package autorevert
  :ensure nil
  :config
  (global-auto-revert-mode 1)
  (setq auto-revert-verbose nil))

;; Auto-save visited files (Emacs 28+)
(auto-save-visited-mode 1)

;; Auto-save location settings
(setq auto-save-file-name-transforms
      '((".*" "~/.emacs.d/auto-save-list/" t)))

;; Create auto-save directory if it doesn't exist
(let ((auto-save-dir (expand-file-name "auto-save-list" user-emacs-directory)))
  (unless (file-directory-p auto-save-dir)
    (make-directory auto-save-dir t)))

;; Backup file settings
(setq make-backup-files t)             ; Enable backup files
(setq backup-by-copying t)             ; Backup by copying (not renaming)
(setq version-control t)               ; Use versioned backups
(setq kept-new-versions 5)             ; Keep 5 newest versions
(setq kept-old-versions 5)             ; Keep 5 oldest versions
(setq delete-old-versions t)           ; Delete excess backups
(setq backup-directory-alist
      '((".*" . "~/.emacs.d/backups/")))  ; Store backups in separate directory

;; Create backup directory if it doesn't exist
(let ((backup-dir (expand-file-name "backups" user-emacs-directory)))
  (unless (file-directory-p backup-dir)
    (make-directory backup-dir t)))

;; ==============================================================================
;; PERSONAL CUSTOMIZATIONS (Add your own below)
;; ==============================================================================

;; Example: Set your preferred theme
;; (load-theme 'doom-one t)

;; Example: Custom key bindings
;; (global-set-key (kbd "C-c w") #'whitespace-mode)

;;; post-init.el ends here
