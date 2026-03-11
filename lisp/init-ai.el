;;; init-ai.el --- AI assistant configuration -*- lexical-binding: t; -*-

;;; Commentary:
;; Configuration for AI assistants: gptel, gptel-agent, nucleus, and ECA.
;; This separates AI tooling from general-purpose tools like Magit and Dirvish.

(provide 'init-ai)

;;; ==============================================================================
;;; AI ASSISTANT (gptel + nucleus)
;;; ==============================================================================

;; Defer gptel loading until explicitly invoked
(use-package gptel
  :ensure t
  :commands (gptel gptel-send gptel-menu gptel-other-frame)
  :defer t)

(use-package gptel-agent
  :ensure t
  :after gptel)

;; After they are installed, load the custom configurations
(with-eval-after-load 'gptel
  (require 'gptel-config)
  (require 'nucleus-config))

;;; ============================================================================== 
;;; EDITOR CODE ASSISTANT (ECA)
;;; ============================================================================== 

(use-package ai-code
  :ensure t
  :commands (ai-code-menu
             ai-code-send-command
             ai-code-cli-switch-to-buffer-or-hide
             ai-code-select-backend)
  :custom
  (ai-code-use-gptel-headline t)
  (ai-code-use-gptel-classify-prompt t)
  (ai-code-auto-test-type 'ask-me)
  (ai-code-notes-use-gptel-headline t)
  (ai-code-task-use-gptel-filename t)
  :config
  (ai-code-set-backend 'opencode)
  (global-set-key (kbd "C-c a") #'ai-code-menu))

(use-package buttercup
  :ensure t
  :defer t)

;; Load ECA security/config early — all code inside is guarded by
;; eval-after-load so nothing runs until eca/eca-process actually load.
(require 'eca-security)

(use-package eca
  :ensure t
  :vc (:url "https://github.com/editor-code-assistant/eca-emacs"
       :rev :newest)
  :custom
  (eca-completion-idle-delay 0.5)
  (eca-chat-use-side-window nil)
  (eca-chat-custom-behavior nil)
  (eca-chat-parent-mode 'markdown-mode)
  (eca-api-response-timeout 15)
  (eca-extra-args '("--log-level" "debug"))
  :config
  ;; Disable markup hiding in ECA chat buffers
  (defun my/eca-chat-disable-markup-hiding-h ()
    "Ensure markup hiding is disabled in `eca-chat-mode' buffers."
    (when (boundp 'markdown-hide-markup)
      (setq-local markdown-hide-markup nil)
      (when (fboundp 'font-lock-flush)
        (font-lock-flush))))
  (add-hook 'eca-chat-mode-hook #'my/eca-chat-disable-markup-hiding-h)
  ;; Enable inline ghost-text code completion in programming modes
  (add-hook 'prog-mode-hook #'eca-completion-mode))

;;; init-ai.el ends here
