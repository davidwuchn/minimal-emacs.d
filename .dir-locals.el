;;; .dir-locals.el --- Project-local variables for auto-workflow -*- lexical-binding: t -*-

;; This file is automatically loaded by Emacs when visiting files in this directory.
;; It configures project-specific settings for auto-workflow.

;; ═══════════════════════════════════════════════════════════════════════════
;; AUTO-WORKFLOW CONFIGURATION
;; ═══════════════════════════════════════════════════════════════════════════

((nil
  . ((gptel-auto-workflow-targets
       . ("lisp/modules/gptel-tools-agent.el"
          "lisp/modules/gptel-auto-workflow-strategic.el"
          "lisp/modules/gptel-benchmark-core.el"))
      (gptel-auto-experiment-max-per-target . 5)
      (gptel-auto-experiment-time-budget . 1200)
      (gptel-auto-experiment-no-improvement-threshold . 3)
      (gptel-model . minimax-m2.7-highspeed))))

;;; .dir-locals.el ends here
