;;; nucleus-config.el --- Nucleus configuration facade -*- lexical-binding: t; -*-

;;; Commentary:
;; Backward-compatibility facade that loads nucleus modules.
;; All functionality has been split into focused modules:
;; - nucleus-tools.el: Tool definitions and sanity checking
;; - nucleus-prompts.el: Prompt loading and directives
;; - nucleus-presets.el: Preset management (plan/agent toggle)
;; - nucleus-ui.el: Header-line and UI components

(provide 'nucleus-config)

;;; Load Split Modules
;;; Note: Order matters! nucleus-ui must load before nucleus-presets
;;; because nucleus-presets.el calls nucleus--header-line-apply-preset-label.

(require 'nucleus-tools)
(require 'nucleus-prompts)
(require 'nucleus-ui)
(require 'nucleus-presets)
(require 'nucleus-mode-switch)

;;; Deferred Initialization

(with-eval-after-load 'gptel-config
  (nucleus--register-gptel-directives)
  (nucleus--override-gptel-agent-presets)
  (nucleus-mode-switch-setup)
  
  (add-hook 'gptel-mode-hook #'nucleus-sync-tool-profile)
  (add-hook 'gptel-mode-hook #'nucleus-tool-sanity-check)
  (add-hook 'gptel-mode-hook #'nucleus--header-line-apply-preset-label)
  
  (when (fboundp 'gptel--apply-preset)
    (advice-add 'gptel--apply-preset :around #'nucleus--around-apply-preset)
    (advice-add 'gptel--apply-preset :after  #'nucleus--after-apply-preset)))

(with-eval-after-load 'gptel-agent
  (advice-add 'gptel-agent :around #'nucleus--agent-around)
  (advice-add 'gptel-agent-update :after #'nucleus--after-agent-update))

;;; nucleus-config.el ends here
