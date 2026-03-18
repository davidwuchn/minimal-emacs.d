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
;; (backup-directory-alist, auto-save-file-name-transforms, etc.)

;; Enable auto-save-visited-mode for automatic buffer saving
(auto-save-visited-mode 1)

;; ==============================================================================
;; PERSONAL CUSTOMIZATIONS (Add your own below)
;; ==============================================================================

;; Example: Set your preferred theme
;; (load-theme 'doom-one t)

;; Example: Custom key bindings
;; (global-set-key (kbd "C-c w") #'whitespace-mode)

;;; post-init.el ends here
