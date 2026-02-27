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

(use-package eca
  :ensure t
  ;; Enable inline ghost-text code completion in programming modes
  :hook (prog-mode . eca-completion-mode)
  :custom
  ;; Delay before triggering inline completion (in seconds)
  (eca-completion-idle-delay 0.5)
  :config
  (require 'eca-security))

;;; init-ai.el ends here
