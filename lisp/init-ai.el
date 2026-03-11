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

(defun my/ai-code--ensure-gptel-loaded (orig question)
  "Load ai-code's gptel bridge on demand before calling ORIG with QUESTION."
  (unless (fboundp 'ai-code-call-gptel-sync)
    (require 'ai-code-prompt-mode nil t))
  (unless (featurep 'gptel)
    (unless (require 'gptel nil t)
      (user-error "GPTel package is required for AI command generation")))
  (funcall orig question))

(defun my/ai-code--shell-command-fallback-input (orig &optional initial-input)
  "Let `ai-code-shell-cmd' use `default-directory' from ordinary buffers.
When INITIAL-INPUT is nil and the current buffer is neither Dired nor a shell,
pass an empty string so ai-code still prompts, but uses the current
`default-directory' as the working directory.  This preserves `:' prompts so
GPTel can generate the actual shell command."
  (if (or initial-input
          (derived-mode-p 'dired-mode)
          (memq major-mode '(shell-mode eshell-mode)))
      (funcall orig initial-input)
    (funcall orig "")))

(defun my/ai-code--prefer-shell-command-from-non-file-buffers (orig &rest args)
  "Fallback to `ai-code-shell-cmd' when no current file is available.
This keeps the `!` ai-code action useful in scratch, prompt, and other
directory-backed buffers, where users still expect `:' input to route through
GPTel shell-command generation instead of erroring on a missing file."
  (if (or (derived-mode-p 'dired-mode)
          (memq major-mode '(shell-mode eshell-mode))
          (use-region-p)
          (buffer-file-name))
      (apply orig args)
    (ai-code-shell-cmd "")))

(with-eval-after-load 'ai-code-file
  (unless (fboundp 'ai-code-call-gptel-sync)
    (require 'ai-code-prompt-mode nil t))
  (advice-add 'ai-code-shell-cmd :around #'my/ai-code--shell-command-fallback-input)
  (advice-add 'ai-code-run-current-file-or-shell-cmd :around
              #'my/ai-code--prefer-shell-command-from-non-file-buffers))

(with-eval-after-load 'ai-code-prompt-mode
  (advice-add 'ai-code-call-gptel-sync :around #'my/ai-code--ensure-gptel-loaded))

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
