;;; post-early-init.el --- Post Early Init -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Commentary:
;; This file is loaded after early-init.el but before init.el.
;; Use it for early configuration that must be set before packages are loaded.

;;; Code:

;; Set tree-sitter grammar directory early, before any tree-sitter modes are loaded
;; Note: user-emacs-directory is already set to var/ by pre-early-init.el
(setq treesit-extra-load-path
      (list (expand-file-name "tree-sitter" user-emacs-directory)))

;; ═══════════════════════════════════════════════════════════════════════════
;; AUTO-WORKFLOW: Mark all project variables as safe
;; ═══════════════════════════════════════════════════════════════════════════

;; These variables are used by auto-workflow in .dir-locals.el files
;; Marking them as safe prevents the prompt when opening project files
(dolist (var '(gptel-auto-workflow-targets
                gptel-auto-experiment-max-per-target
                gptel-auto-experiment-time-budget
                gptel-auto-experiment-no-improvement-threshold
                gptel-auto-workflow-projects
                gptel-auto-workflow--project-root-override
                gptel-backend
                gptel-model))
  (add-to-list 'safe-local-variable-values (cons var t)))

(provide 'post-early-init)

;;; post-early-init.el ends here
