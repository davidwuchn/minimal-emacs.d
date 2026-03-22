;;; nucleus-config.el --- Nucleus configuration facade -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Commentary:
;; Backward-compatibility facade that loads nucleus modules.
;; All functionality has been split into focused modules:
;; - nucleus-tools.el: Tool definitions and sanity checking
;; - nucleus-prompts.el: Prompt loading and directives
;; - nucleus-presets.el: Preset management (plan/agent toggle)
;; - nucleus-header-line.el: Header-line components

(provide 'nucleus-config)

;;; Load Split Modules
;;; Note: Order matters! nucleus-header-line must load before nucleus-presets
;;; because nucleus-presets.el calls nucleus--header-line-apply-preset-label.

(require 'nucleus-tools)
(require 'nucleus-prompts)
(require 'nucleus-header-line)
(require 'nucleus-presets)

;;; Deferred Initialization

;; Phase 1: Register directives and hooks (needs gptel-config only)
(with-eval-after-load 'gptel-config
  (nucleus--register-gptel-directives)

  (add-hook 'gptel-mode-hook #'nucleus-sync-tool-profile)
  (add-hook 'gptel-mode-hook #'nucleus-tool-sanity-check)
  (add-hook 'gptel-mode-hook #'nucleus--header-line-apply-preset-label))

;; Phase 2: Override presets and wire advice (needs gptel-agent loaded)
(with-eval-after-load 'gptel-agent
  (nucleus-presets-setup))

;;; nucleus-config.el ends here
