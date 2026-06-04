;;; .dir-locals.el --- Project-local variables for auto-workflow -*- lexical-binding: t -*-

;; This file is automatically loaded by Emacs when visiting files in this directory.
;; It configures project-specific settings for auto-workflow.

;; ═══════════════════════════════════════════════════════════════════════════
;; AUTO-WORKFLOW CONFIGURATION
;; ═══════════════════════════════════════════════════════════════════════════

((nil
  . ((gptel-auto-workflow-targets
       . ("lisp/modules/gptel-auto-workflow-projects.el"
          "lisp/modules/gptel-auto-workflow-strategic.el"
          "lisp/modules/gptel-tools-agent-prompt-build.el"
          "lisp/modules/gptel-tools-agent-error.el"
          "lisp/modules/gptel-benchmark-subagent.el"))
      (gptel-auto-experiment-max-per-target . 2)
      (gptel-auto-experiment-time-budget . 1200)
      (gptel-auto-experiment-no-improvement-threshold . 3))))

;;; .dir-locals.el ends here
