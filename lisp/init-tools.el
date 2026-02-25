;;; init-tools.el --- Magit, UI tools, AI, and miscellany -*- lexical-binding: t; -*-

(provide 'init-tools)

;; ==============================================================================
;; GIT & UI 
;; ==============================================================================

(use-package magit
  :ensure t
  :bind (("C-x g" . magit-status)))

(use-package nerd-icons
  :ensure t)

(use-package doom-modeline
  :ensure t
  :after nerd-icons
  :init (doom-modeline-mode 1))

(use-package nerd-icons-completion
  :ensure t
  :after marginalia
  :config
  (nerd-icons-completion-mode)
  (add-hook 'marginalia-mode-hook #'nerd-icons-completion-marginalia-setup))

(use-package nerd-icons-corfu
  :ensure t
  :after corfu
  :config
  (add-to-list 'corfu-margin-formatters #'nerd-icons-corfu-formatter))

(use-package nerd-icons-dired
  :ensure t
  :hook (dired-mode . nerd-icons-dired-mode))

;; ==============================================================================
;; AI ASSISTANT (gptel + nucleus)
;; ==============================================================================

;; Load the custom AI assistant configuration provided in the lisp directory
(require 'nucleus-config)
(require 'gptel-config)
(require 'eca-security)
