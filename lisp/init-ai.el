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

(defcustom my/ai-code-gptel-helper-backend 'gptel--dashscope
  "Backend used for ai-code's synchronous gptel helper requests."
  :type 'symbol
  :group 'gptel)

(defcustom my/ai-code-gptel-helper-model 'qwen3-coder-next
  "Fast non-reasoning model used for ai-code helper requests."
  :type 'symbol
  :group 'gptel)

(defun my/ai-code--helper-backend-value ()
  "Return the backend value configured for ai-code helper requests."
  (and my/ai-code-gptel-helper-backend
       (boundp my/ai-code-gptel-helper-backend)
       (symbol-value my/ai-code-gptel-helper-backend)))

(defun my/ai-code--ensure-gptel-helper-model (orig question)
  "Run ai-code gptel helper calls with a fast local backend/model." 
  (unless (featurep 'gptel)
    (unless (require 'gptel nil t)
      (user-error "GPTel package is required for AI helper generation")))
  (let ((gptel-backend (or (my/ai-code--helper-backend-value) gptel-backend))
        (gptel-model (or my/ai-code-gptel-helper-model gptel-model)))
    (funcall orig question)))

(with-eval-after-load 'ai-code-prompt-mode
  (advice-add 'ai-code-call-gptel-sync :around #'my/ai-code--ensure-gptel-helper-model))

;;; ==============================================================================
;;; AI CODE (with ECA backend support)
;;; ==============================================================================

;; TODO: After PR #232 is merged, change branch back to "main" and URL to tninja
;; PR: https://github.com/tninja/ai-code-interface.el/pull/232
(use-package ai-code
  :ensure t
  :vc (:url "https://github.com/davidwuchn/ai-code-interface.el"
       :branch "fix/transient-menu-keys")
  :demand t
  :custom
  (ai-code-backends-infra-terminal-backend 'vterm)
  (ai-code-backends-infra-use-side-window nil)
  (ai-code-use-gptel-headline t)
  (ai-code-use-gptel-classify-prompt t)
  (ai-code-auto-test-type 'ask-me)
  (ai-code-notes-use-gptel-headline t)
  (ai-code-task-use-gptel-filename t)
  :config
  (require 'ai-code-eca)
  (ai-code-set-backend 'opencode)
  (global-set-key (kbd "C-c a") #'ai-code-menu))

(use-package buttercup
  :ensure t
  :defer t)

;; Load ECA security/config early
(require 'eca-security)

(use-package eca
  :ensure t
  :custom
  (eca-completion-idle-delay 0.5)
  (eca-chat-use-side-window nil)
  (eca-chat-custom-behavior nil)
  (eca-chat-parent-mode 'markdown-mode)
  (eca-api-response-timeout 15)
  (eca-extra-args '("--log-level" "warn"))
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