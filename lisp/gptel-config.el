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

;; Load split tool modules (replaces gptel-ext-tools.el)
(require 'gptel-tools)
(gptel-tools-setup)


;; Load tool verification (checks all declared tools are registered)
(require 'nucleus-tools-verify)

;; Load tool signature validation (validates prompt args match registration)
(require 'nucleus-tools-validate)

;; Load tool permit system (auto / confirm-all + per-tool permits)
(require 'gptel-ext-tool-permits)

;; --- Configuration Defaults ---
(setq gptel-backend gptel--dashscope
      gptel-model 'qwen3-coder-next)

;; Subagent model/backend: DEPRECATED
;; Subagents now use their YAML model: field. See assistant/agents/*.md

;; Enable media/image attachment support (required for vision models)
(setq gptel-track-media t)

;; Tool confirmation: auto (default) / confirm-all (kill switch).
;; Use M-x my/gptel-toggle-confirm to switch modes.
;; Per-tool permits remembered for the session (M-x my/gptel-show-permits).

(provide 'gptel-config)

;;; gptel-config.el ends here
