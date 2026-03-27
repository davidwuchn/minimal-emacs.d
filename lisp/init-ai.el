;;; init-ai.el --- AI assistant configuration -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Commentary:
;; Configuration for AI assistants: gptel, gptel-agent, nucleus, and ECA.
;; This separates AI tooling from general-purpose tools like Magit and Dirvish.

;;; ==============================================================================
;;; AI ASSISTANT (gptel + nucleus)
;;; ==============================================================================

;; Add gptel and gptel-agent to load-path (installed via git clone)
;; See: scripts/setup-packages.sh for installation instructions
(let ((packages-dir (expand-file-name "packages" minimal-emacs-user-directory)))
  (add-to-list 'load-path (expand-file-name "gptel" packages-dir))
  (add-to-list 'load-path (expand-file-name "gptel-agent" packages-dir))
  ;; Load autoloads for git-cloned packages
  (let ((gptel-autoloads (expand-file-name "gptel/gptel-autoloads.el" packages-dir))
        (agent-autoloads (expand-file-name "gptel-agent/gptel-agent-autoloads.el" packages-dir)))
    (when (file-exists-p gptel-autoloads)
      (load gptel-autoloads nil t))
    (when (file-exists-p agent-autoloads)
      (load agent-autoloads nil t))))

(use-package gptel
  :ensure nil
  :commands (gptel gptel-send gptel-menu gptel-other-frame)
  :defer t)

(use-package gptel-agent
  :ensure nil
  :commands (gptel-agent gptel-agent-read-file gptel-agent-update)
  :after gptel)

;; After they are installed, load the custom configurations
(with-eval-after-load 'gptel
  (require 'gptel-config)
  (require 'nucleus-config)
  (require 'gptel-agent-loop)
  (gptel-agent-loop-enable)
  (require 'ai-code-behaviors))

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

;;; ==============================================================================
;;; AI CODE (with ECA backend support)
;;; ==============================================================================

;; VC-installed packages need manual load-path addition
(let ((ai-code-dir (expand-file-name "packages/ai-code" minimal-emacs-user-directory)))
  (when (file-directory-p ai-code-dir)
    (add-to-list 'load-path ai-code-dir)
    ;; Load autoloads
    (let ((autoloads (expand-file-name "ai-code-autoloads.el" ai-code-dir)))
      (when (file-exists-p autoloads)
        (load autoloads nil t)))))

(use-package ai-code
  :ensure nil
  :defer t
  :commands (ai-code-menu ai-code-set-backend)
  :custom
  (ai-code-backends-infra-terminal-backend 'vterm)
  (ai-code-backends-infra-use-side-window nil)
  (ai-code-use-gptel-headline t)
  (ai-code-use-gptel-classify-prompt nil)
  (ai-code-auto-test-type 'ask-me)
  (ai-code-notes-use-gptel-headline t)
  (ai-code-task-use-gptel-filename t)
  (ai-code-behaviors-auto-enable t)
  :bind ("C-c a" . ai-code-menu)
  :config
  (require 'ai-code-eca)
  (ai-code-set-backend 'eca)
  (advice-add 'ai-code-call-gptel-sync :around #'my/ai-code--ensure-gptel-helper-model))

(use-package buttercup
  :ensure t
  :defer t)

;;; ==============================================================================
;;; AGENT-SHELL (OpenCode backend)
;;; ==============================================================================

;; Ensure Unicode symbols render (busy indicators, icons)
(set-fontset-font t 'unicode "DejaVuSansM Nerd Font" nil 'prepend)

;; Custom separator for header (replace default "➤" with "|")
(defvar my/agent-shell-header-separator " | "
  "Separator between header elements.")

(defun my/agent-shell--header-text-separator (orig-fn state &rest args)
  "Advice to customize header separator."
  (let ((result (apply orig-fn state args)))
    (when (stringp result)
      (replace-regexp-in-string " ➤ " my/agent-shell-header-separator result))))

(with-eval-after-load 'agent-shell
  (advice-add 'agent-shell--make-header :around #'my/agent-shell--header-text-separator)
  ;; Keybindings for session mode switching
  (define-key agent-shell-mode-map (kbd "C-c m") #'agent-shell-set-session-mode)
  (define-key agent-shell-mode-map (kbd "C-c M") #'agent-shell-cycle-session-mode)
  ;; Keybinding for preset selection
  (define-key agent-shell-mode-map (kbd "C-c p") #'ai-code-behaviors-preset)
  ;; Keybinding to show injected context
  (define-key agent-shell-mode-map (kbd "C-c P") #'ai-code-behaviors-show-last-prompt))

(use-package agent-shell
  :ensure t
  :defer t
  :custom
  ;; OpenCode as default backend, latest session
  (agent-shell-preferred-agent-config 'opencode)
  (agent-shell-session-strategy 'latest)
  (agent-shell-opencode-authentication
   (agent-shell-opencode-make-authentication :none t))
  ;; Default model for new sessions (when no existing session)
  (agent-shell-opencode-default-model-id "alibaba-coding-plan-cn/glm-5")
  ;; UI styling
  (agent-shell-header-style 'text)
  (agent-shell-show-config-icons t)
  (agent-shell-show-busy-indicator t)
  (agent-shell-busy-indicator-frames 'wave)
  (agent-shell-highlight-blocks t)
  (agent-shell-thought-process-expand-by-default nil)
  (agent-shell-tool-use-expand-by-default nil)
  (agent-shell-user-message-expand-by-default nil)
  ;; Use background tint style for status labels
  (agent-shell-status-kind-label-function
   #'agent-shell--background-tint-status-kind-label)
  ;; Disable auto-context injection
  (agent-shell-context-sources nil)
  ;; Context usage display
  (agent-shell-show-context-usage-indicator 'detailed)
  :config
  ;; Enable ai-code-behaviors integration
  (ai-code-behaviors-agent-shell-setup))

;; Load ECA security utilities
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

;;; ==============================================================================
;;; BENCHMARK & φ EVOLUTION
;;; ==============================================================================

;; Load benchmark modules for skill/workflow testing and φ evolution
(let ((modules-dir (expand-file-name "lisp/modules" minimal-emacs-user-directory)))
  (when (file-directory-p modules-dir)
    (add-to-list 'load-path modules-dir)))

;; Defer benchmark daily setup until after init
(with-eval-after-load 'gptel-benchmark-daily
  (gptel-benchmark-daily-setup))

(provide 'init-ai)

;;; init-ai.el ends here