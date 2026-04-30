;;; gptel-config.el --- Clean, modular gptel configuration -*- no-byte-compile: t; lexical-binding: t; -*-

(eval-and-compile
  (let* ((base-dir (if (boundp 'minimal-emacs-user-directory)
                       minimal-emacs-user-directory
                     "~/.emacs.d/"))
         (modules-dir (expand-file-name "lisp/modules" base-dir)))
    (add-to-list 'load-path (file-truename modules-dir))))

(require 'gptel-ext-core)
(require 'gptel-ext-streaming)
(require 'gptel-ext-fsm-utils)
(require 'gptel-ext-tool-sanitize)
(require 'gptel-ext-reasoning)
(require 'gptel-ext-context-images)
(require 'gptel-ext-retry)
(require 'gptel-ext-transient)
(require 'gptel-ext-abort)
(require 'gptel-ext-tool-confirm)
(require 'gptel-ext-fsm)
(require 'gptel-ext-backends)
(require 'gptel-ext-context)
(require 'gptel-ext-context-cache)
(require 'gptel-ext-security)

;; Load tool-contract advice before registering any tools so local-only schema
;; metadata like :normalize never leaks into provider-facing JSON schemas.
(require 'nucleus-tools)

;; Load split tool modules (replaces gptel-ext-tools.el)
(require 'gptel-tools)
(gptel-tools-setup)


;; Load tool verification (checks all declared tools are registered)
(require 'nucleus-tools-verify)

;; Load tool signature validation (validates prompt args match registration)
(require 'nucleus-tools-validate)

;; Load tool permit system (auto / confirm-all + per-tool permits)
(require 'gptel-ext-tool-permits)

;; Load benchmark framework (Eight Keys + Wu Xing + Evolution)
(require 'gptel-benchmark-principles)
(require 'gptel-benchmark-core)
(require 'gptel-benchmark-subagent)
(require 'gptel-benchmark-memory)
(require 'gptel-benchmark-evolution)
(require 'gptel-benchmark-auto-improve)
(require 'gptel-benchmark-integrate)
(require 'gptel-benchmark-daily)
(require 'gptel-benchmark-instincts)
(require 'gptel-workflow-benchmark)
(require 'gptel-skill-benchmark)

;; Load self-evolution system (mementum + git facts → knowledge injection)
;; Ensure tools-agent loads first (evolution modules depend on it)
(require 'gptel-tools-agent)
(require 'gptel-auto-workflow-git-learning)
(require 'gptel-auto-workflow-evolution)
(require 'gptel-auto-workflow-mementum)
(require 'gptel-auto-workflow-production)

;; Enable daily benchmark integration (auto-collect metrics on skill/workflow runs)
(gptel-benchmark-daily-setup)

;; --- Configuration Defaults ---
;; Use setq-default to set the global default values
(setq-default gptel-backend gptel--minimax
              gptel-model 'minimax-m2.7-highspeed)
;; Also set current values for this buffer
(setq gptel-backend gptel--minimax
      gptel-model 'minimax-m2.7-highspeed)

;; Safety: Ensure gptel-model is never nil (falls back to default)
(defun my/gptel--ensure-model-not-nil (orig-fun &rest args)
  "Ensure `gptel-model' is not nil before calling ORIG-FUN."
  (unless gptel-model
    (setq-local gptel-model 'minimax-m2.7-highspeed))
  (apply orig-fun args))

(with-eval-after-load 'gptel
  (advice-add 'gptel-request :around #'my/gptel--ensure-model-not-nil))

;; Subagent model/backend: DEPRECATED
;; Subagents now use their YAML model: field. See assistant/agents/*.md

;; Enable media/image attachment support (required for vision models)
(setq gptel-track-media t)

;; Tool confirmation: auto (default) / confirm-all (kill switch).
;; Use M-x my/gptel-toggle-confirm to switch modes.
;; Per-tool permits remembered for the session (M-x my/gptel-show-permits).

(provide 'gptel-config)

;;; gptel-config.el ends here
