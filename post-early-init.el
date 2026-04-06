;;; post-early-init.el --- Post Early Init -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Commentary:
;; This file is loaded after early-init.el but before init.el.
;; Use it for early configuration that must be set before packages are loaded.

;;; Code:

;; ═══════════════════════════════════════════════════════════════════════════
;; Prevent multiple Emacs daemons
;; ═══════════════════════════════════════════════════════════════════════════
;; Check if another daemon is already running before this one fully starts.
;; This prevents the "server did not start correctly" error and resource waste.
(when (daemonp)
  (require 'server)
  (when (server-running-p)
    (message "[daemon] Another Emacs daemon is already running, exiting this one")
    (kill-emacs 0)))

;; Set tree-sitter grammar directory early, before any tree-sitter modes are loaded
;; Note: user-emacs-directory is already set to var/ by pre-early-init.el
(setq treesit-extra-load-path
      (list (expand-file-name "tree-sitter" user-emacs-directory)))

;; ═══════════════════════════════════════════════════════════════════════════
;; AUTO-WORKFLOW: Mark all project variables as safe
;; ═══════════════════════════════════════════════════════════════════════════

;; These variables are used by auto-workflow in .dir-locals.el files
;; Marking them as safe prevents the prompt when opening project files
;; NOTE: For complex types (lists), we must explicitly mark the EXACT values
(add-to-list 'safe-local-variable-values
             '(gptel-auto-workflow-targets
               "lisp/modules/gptel-tools-agent.el"
               "lisp/modules/gptel-auto-workflow-strategic.el"
               "lisp/modules/gptel-benchmark-core.el"))
(add-to-list 'safe-local-variable-values
             '(gptel-auto-experiment-max-per-target . 5))
(add-to-list 'safe-local-variable-values
             '(gptel-auto-experiment-time-budget . 1200))
(add-to-list 'safe-local-variable-values
             '(gptel-auto-experiment-no-improvement-threshold . 3))
(add-to-list 'safe-local-variable-values
             '(gptel-model . qwen3.5-plus))

;; Mark variable names as safe (for future flexibility)
(dolist (var '(gptel-auto-workflow-projects
                gptel-auto-workflow--project-root-override))
  (add-to-list 'safe-local-variable-values (cons var t)))

(provide 'post-early-init)

;;; post-early-init.el ends here
