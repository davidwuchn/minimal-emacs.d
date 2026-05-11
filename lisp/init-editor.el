;;; init-editor.el --- Editor quality-of-life enhancements -*- no-byte-compile: t; lexical-binding: t; -*-

(provide 'init-editor)

;; ==============================================================================
;; HELP & INTROSPECTION
;; ==============================================================================

(use-package simple
  :ensure nil
  :hook ((text-mode . visual-line-mode)))

(use-package helpful
  :ensure t
  :bind
  ([remap describe-command] . helpful-command)
  ([remap describe-function] . helpful-callable)
  ([remap describe-key] . helpful-key)
  ([remap describe-variable] . helpful-variable)
  ([remap describe-symbol] . helpful-symbol))

;; ==============================================================================
;; QUALITY OF LIFE
;; ==============================================================================

;; which-key: Show available keybindings after prefix keys
(use-package which-key
  :ensure nil  ; built-in Emacs 29+
  :hook (after-init . which-key-mode)
  :custom
  (which-key-idle-delay 1.0)
  (which-key-idle-secondary-delay 0.25))

;; winner-mode: Undo/redo window configurations (C-c <left>/<right>)
(use-package winner
  :ensure nil
  :hook (after-init . winner-mode)
  :custom
  (winner-boring-buffers '("*Completions*"
                           "*Minibuf-0*" "*Minibuf-1*"
                           "*Compile-Log*"
                           "*Help*" "*Apropos*")))

;; gold-ratio: Auto-resize windows to golden ratio (active window larger)
;; Source: https://github.com/roman/golden-ratio.el
(use-package golden-ratio
  :ensure t
  :hook (after-init . golden-ratio-mode)
  :custom
  (golden-ratio-auto-scale t)
  (golden-ratio-exclude-modes '("ediff-mode" "calendar-mode" "dired-mode")))

;; indent-bars: Vertical indentation guide lines (tree-sitter powered)
;; Source: https://github.com/jdtsmith/indent-bars
(use-package indent-bars
  :ensure t
  :hook ((prog-mode text-mode) . indent-bars-mode)
  :custom
  (indent-bars-treesit-support t)
  (indent-bars-width-func '(indent-bars-width-detect)))

;;; init-editor.el ends here
