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

(use-package dirvish
  :ensure t
  :hook (after-init . dirvish-override-dired-mode)
  :bind (:map dired-mode-map
              ("TAB" . dirvish-toggle-subtree)
              ("SPC" . dirvish-show-history)
              ("f"   . dirvish-file-info-menu)))

;; ==============================================================================
;; TERMINAL
;; ==============================================================================

(use-package eat
  :ensure t
  :defer t
  :custom
  (eat-term-name "xterm-256color")
  :config
  (eat-eshell-mode)
  (eat-eshell-visual-command-mode))

;; ==============================================================================
;; AI ASSISTANT (gptel + nucleus)
;; ==============================================================================

;; Ensure the packages are downloaded and installed
(use-package gptel
  :ensure t)

(use-package gptel-agent
  :ensure t
  :after gptel)

;; After they are installed, load the custom configurations
(with-eval-after-load 'gptel
  (require 'nucleus-config)
  (require 'gptel-config)
  (require 'eca-security))
