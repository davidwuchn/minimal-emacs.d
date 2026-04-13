;;; gptel-auto-workflow-bootstrap.el --- Headless bootstrap for workflow wrapper -*- lexical-binding: t; -*-

;;; Commentary:

;; Keeps the cron wrapper's `emacsclient --eval` payload short and stable by
;; moving the larger workflow bootstrap into a normal Elisp file.

;;; Code:

(defun gptel-auto-workflow-bootstrap--seed-load-path (root)
  "Add repo-local workflow paths under ROOT to `load-path'."
  (dolist (dir (list (expand-file-name "lisp" root)
                     (expand-file-name "lisp/modules" root)
                     (expand-file-name "packages/gptel" root)
                     (expand-file-name "packages/gptel-agent" root)
                     (expand-file-name "packages/ai-code" root)))
    (when (file-directory-p dir)
      (add-to-list 'load-path dir))))

(defun gptel-auto-workflow-bootstrap-run (root action)
  "Bootstrap headless workflow execution from ROOT for ACTION."
  (gptel-auto-workflow-bootstrap--seed-load-path root)
  (defvar gptel--tool-preview-alist nil)
  (load-file (expand-file-name "lisp/modules/nucleus-tools.el" root))
  (load-file (expand-file-name "lisp/modules/nucleus-prompts.el" root))
  (load-file (expand-file-name "lisp/modules/nucleus-presets.el" root))
  (when (fboundp 'nucleus--register-gptel-directives)
    (nucleus--register-gptel-directives))
  (when (fboundp 'nucleus--override-gptel-agent-presets)
    (nucleus--override-gptel-agent-presets))
  (require 'gptel)
  (unless (fboundp 'gptel--format-tool-call)
    (defun gptel--format-tool-call (name arg-values)
      (format "(%s %s)\n"
              (propertize (or name "unknown") 'font-lock-face 'font-lock-keyword-face)
              (propertize (format "%s" arg-values) 'font-lock-face 'font-lock-string-face))))
  (require 'gptel-request)
  (require 'gptel-agent-tools)
  (load-file (expand-file-name "lisp/modules/gptel-ext-backends.el" root))
  (setq gptel-backend gptel--minimax
        gptel-model 'minimax-m2.7-highspeed)
  (load-file (expand-file-name "lisp/modules/gptel-tools-agent.el" root))
  (load-file (expand-file-name "lisp/modules/gptel-auto-workflow-strategic.el" root))
  (load-file (expand-file-name "lisp/modules/gptel-auto-workflow-projects.el" root))
  (cond
   ((string= action "auto-workflow")
    (gptel-auto-workflow-queue-all-projects))
   ((string= action "research")
    (gptel-auto-workflow-queue-all-research))
   ((string= action "mementum")
    (gptel-auto-workflow-queue-all-mementum))
   ((string= action "instincts")
    (gptel-auto-workflow-queue-all-instincts))
   (t
    (error "Unknown workflow bootstrap action: %s" action))))

(provide 'gptel-auto-workflow-bootstrap)
;;; gptel-auto-workflow-bootstrap.el ends here
