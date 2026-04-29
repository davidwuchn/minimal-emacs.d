;;; init-tools.el --- Magit, UI tools, and miscellany -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Commentary:
;; General-purpose tools: Magit, UI enhancements, Dirvish, EAT terminal.
;; AI assistants (gptel, ECA) are configured separately in `init-ai.el'.

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
  :hook (after-init . doom-modeline-mode))

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
  :init
  (with-eval-after-load 'dirvish
    (setq dirvish-emacs-bin (concat invocation-directory invocation-name)))
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
;; ENHANCEMENTS (Optional but recommended)
;; ==============================================================================

;; Git diff highlights in margin (complements Magit)
(use-package diff-hl
  :ensure t
  :hook (after-init . global-diff-hl-mode)
  :config
  (setq diff-hl-draw-borders nil))

;; Tree-sitter based code folding
(use-package treesit-fold
  :ensure t
  :hook (prog-mode . treesit-fold-mode)
  :bind (:map global-map
              ("C-c f t" . treesit-fold-toggle)
              ("C-c f o" . treesit-fold-open)
              ("C-c f c" . treesit-fold-close)))

;; Navigate to last changes (Evil integration: g;, g,)
(use-package goto-chg
  :ensure t
  :after evil
  :bind (:map evil-normal-state-map
              ("g;" . goto-last-change)
              ("g," . goto-last-change-reverse)))

;; ==============================================================================
;; OPTIONAL ENHANCEMENTS (Recommended but not essential)
;; ==============================================================================

;; Vim-style tab bar (integrates with Evil mode)
;; DISABLED: Use M-x vim-tab-bar-mode to enable manually if needed
;; (use-package vim-tab-bar
;;   :ensure t
;;   :hook (after-init . vim-tab-bar-mode)
;;   :config
;;   (setq vim-tab-bar-show-tabs 2)  ; Always show tab bar
;;   (setq vim-tab-bar-width 15))    ; Tab width

;; Surround text with pairs (cs"', ds', ysW, etc.)
(use-package evil-surround
  :ensure t
  :after evil
  :config
  (global-evil-surround-mode 1))

;; Session management (save/restore windows, buffers, desktop)
;; Disabled: auto-save timer causes errors with AI-generated buffer content
(use-package easysession
  :ensure t
  :config
  (setq easysession-directory (locate-user-emacs-file "session"))
  ;; Manual save only: M-x easysession-save-session
  (setq easysession-save-interval nil))

;; Auto-update packages on startup
;; Disabled by default to prevent network hangs on startup.
;; Run M-x auto-package-update-now manually when ready.
(use-package auto-package-update
  :ensure t
  :config
  (setq auto-package-update-delete-old-versions t)
  (setq auto-package-update-hide-results t)
  ;; Don't auto-update on startup - can cause network hangs
  ;; (auto-package-update-maybe)
  )

;; Auto-kill unused buffers to save memory
(use-package buffer-terminator
  :ensure t
  :hook (after-init . buffer-terminator-mode)
  :config
  (setq buffer-terminator-idle-seconds 300)  ; Kill after 5 minutes idle
  (setq buffer-terminator-ignored-modes
        '(dired-mode magit-mode term-mode vterm-mode)))

;;; init-tools.el ends here

