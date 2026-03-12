;;; init-evil.el --- Vim bindings and ergonomics -*- lexical-binding: t; -*-

(provide 'init-evil)

(use-package undo-fu
  :ensure t
  :config
  (global-unset-key (kbd "C-z"))
  (global-set-key (kbd "C-z") 'undo-fu-only-undo)
  (global-set-key (kbd "C-S-z") 'undo-fu-only-redo))

(use-package undo-fu-session
  :ensure t
  :hook (after-init . undo-fu-session-global-mode))

(use-package vundo
  :ensure t
  :bind (("C-x u" . vundo))
  :config
  (setq vundo-glyph-alist vundo-unicode-symbols)
  (setq vundo-roll-back-on-quit nil))

(use-package evil
  :ensure t
  :hook (after-init . evil-mode)
  :init
  (setq evil-want-integration t)
  (setq evil-want-keybinding nil)
  (setq evil-undo-system 'undo-fu)
  :custom
  (evil-ex-visual-char-range t)
  (evil-ex-search-vim-style-regexp t)
  (evil-split-window-below t)
  (evil-vsplit-window-right t)
  (evil-echo-state nil)
  (evil-move-cursor-back nil)
  (evil-v$-excludes-newline t)
  (evil-want-C-h-delete t)
  (evil-want-C-u-delete t)
  (evil-want-fine-undo t)
  (evil-move-beyond-eol t)
  (evil-search-wrap nil)
  (evil-want-Y-yank-to-eol t))

;; Only set up evil-collection if it's actually installed.
;; use-package :after evil registers eval-after-load immediately —
;; if evil-collection is missing when evil loads (e.g. via eca-chat),
;; the hard (require 'evil-collection nil nil) crashes init.
(when (locate-library "evil-collection")
  (use-package evil-collection
    :after evil
    :ensure t
    :init
    (setq evil-collection-setup-minibuffer t)
    :config
    (evil-collection-init)))

(use-package evil-surround
  :after evil
  :ensure t
  :hook (after-init . global-evil-surround-mode))

(with-eval-after-load "evil"
  (evil-define-operator my-evil-comment-or-uncomment (beg end)
    "Toggle comment for the region between BEG and END."
    (interactive "<r>")
    (comment-or-uncomment-region beg end))
  (evil-define-key 'normal 'global (kbd "gc") 'my-evil-comment-or-uncomment))

;; ==============================================================================
;; NAVIGATION & ERGONOMICS
;; ==============================================================================

(use-package avy
  :ensure t
  :bind (("C-c j" . avy-goto-line)
         ("C-:"   . avy-goto-char-timer))
  :custom
  (avy-timeout-seconds 0.3))

(use-package evil-visualstar
  :ensure t
  :after evil
  :config
  (global-evil-visualstar-mode))

;; Clear search highlights when pressing ESC (like Vim's :nohlsearch)
(defun my-evil-force-normal-state ()
  "Clear search highlights and return to normal state."
  (interactive)
  (evil-ex-nohighlight)
  (evil-force-normal-state))

(with-eval-after-load 'evil
  (define-key evil-normal-state-map [remap evil-force-normal-state] #'my-evil-force-normal-state)

  ;; Keep a couple of modes in Emacs state even when evil is enabled.
  (evil-set-initial-state 'vterm-mode 'emacs)
  (evil-set-initial-state 'eca-chat-mode 'emacs))

;; ==============================================================================
;; VTERM
;; ==============================================================================

(use-package vterm
  :ensure t
  :defer t
  :custom
  (vterm-max-scrollback 100000))

(defun my-vterm-evil-ensure-emacs-state ()
  "Force `vterm-mode' buffers back into Emacs state after Evil initializes."
  (when (and (derived-mode-p 'vterm-mode)
             (fboundp 'evil-emacs-state)
             (bound-and-true-p evil-local-mode))
    (evil-emacs-state)))

(defun my-vterm-evil-ensure-emacs-state-later (&optional buffer)
  "Force `vterm-mode' BUFFER into Emacs state on the next event loop turn."
  (run-at-time
   0 nil
   (lambda (buf)
     (when (buffer-live-p buf)
       (with-current-buffer buf
         (my-vterm-evil-ensure-emacs-state))))
   (or buffer (current-buffer))))

;; Keep vterm in Emacs state and let ESC reach the terminal unchanged.
(defun my-vterm-evil-setup ()
  "Keep `vterm' in Emacs state and do not let Evil intercept ESC."
  (setq-local evil-inhibit-esc t)
  (setq-local evil-move-cursor-back nil)
  (my-vterm-evil-ensure-emacs-state)
  (my-vterm-evil-ensure-emacs-state-later))

(with-eval-after-load 'evil
  (add-hook 'evil-local-mode-hook #'my-vterm-evil-ensure-emacs-state-later))

(with-eval-after-load 'vterm
  (add-hook 'vterm-mode-hook #'my-vterm-evil-setup))

(with-eval-after-load 'evil-collection-vterm
  (evil-set-initial-state 'vterm-mode 'emacs))
