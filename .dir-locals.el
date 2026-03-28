;;; .dir-locals.el --- Project-local variables for auto-workflow -*- lexical-binding: t -*-

;; This file is automatically loaded by Emacs when visiting files in this directory.
;; It configures project-specific settings for auto-workflow.

;; ═══════════════════════════════════════════════════════════════════════════
;; AUTO-WORKFLOW CONFIGURATION
;; ═══════════════════════════════════════════════════════════════════════════

((nil
  . (;; Target files to optimize (if not specified, analyzer will select)
     (gptel-auto-workflow-targets
      . ("lisp/modules/gptel-tools-agent.el"
         "lisp/modules/gptel-auto-workflow-strategic.el"
         "lisp/modules/gptel-benchmark-core.el"))
     
     ;; Maximum experiments per target
     (gptel-auto-experiment-max-per-target . 5)
     
     ;; Timeout per experiment (seconds)
     (gptel-auto-experiment-time-budget . 1200)
     
     ;; No-improvement threshold (stop after N consecutive failures)
     (gptel-auto-experiment-no-improvement-threshold . 3)
     
     ;; Backend and model (uncomment to override)
     ;; (gptel-backend . gptel--dashscope)
     ;; (gptel-model . qwen3.5-plus)
     )))

;; ═══════════════════════════════════════════════════════════════════════════
;; HOW TO USE
;; ═══════════════════════════════════════════════════════════════════════════

;; 1. Copy this file to your project root as ".dir-locals.el"
;; 2. Customize the values above for your project
;; 3. Emacs will automatically load these when visiting any file in the project
;; 4. Run auto-workflow: M-x gptel-auto-workflow-cron-safe
;;    Or wait for cron job to trigger

;; Note: For non-git projects, set gptel-auto-workflow--project-root-override
;; to the absolute path of your project root.

;; For multiple projects, create .dir-locals.el in each project with appropriate
;; targets and settings.

;;; .dir-locals.el ends here
