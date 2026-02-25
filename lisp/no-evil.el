;;; no-evil.el --- Disable evil in selected modes  -*- lexical-binding: t; -*-

;;; Commentary:
;; Keep a couple of modes in Emacs state even when evil is enabled.

;;; Code:

(with-eval-after-load 'evil
  (evil-set-initial-state 'vterm-mode 'emacs)
  (evil-set-initial-state 'eca-chat-mode 'emacs))

(provide 'no-evil)
;;; no-evil.el ends here
