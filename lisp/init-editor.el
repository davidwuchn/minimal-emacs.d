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

;;; init-editor.el ends here
