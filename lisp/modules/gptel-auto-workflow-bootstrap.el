;;; gptel-auto-workflow-bootstrap.el --- Headless bootstrap for workflow wrapper -*- lexical-binding: t; -*-

;;; Commentary:

;; Keep the cron wrapper's `emacsclient --eval` payload short and stable.  The
;; wrapper only needs to seed repo-local module paths, reload the workflow
;; modules from the requested worktree, and queue the chosen action.

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

(defun gptel-auto-workflow-bootstrap--known-gptel-load-error-p (err)
  "Return non-nil when ERR matches the fresh-daemon Gptel read error."
  (eq (car-safe err) 'invalid-read-syntax))

(defun gptel-auto-workflow-bootstrap--gptel-ready-p ()
  "Return non-nil when the core Gptel entrypoints are available."
  (and (featurep 'gptel)
       (fboundp 'gptel-send)
       (fboundp 'gptel-request)))

(defun gptel-auto-workflow-bootstrap--load-gptel-core (root)
  "Load the core Gptel stack from ROOT in a fresh worker daemon."
  (let ((load-prefer-newer nil))
    (require 'xdg)
    (condition-case err
        (require 'gptel)
      (error
       (condition-case load-err
           (load-file (expand-file-name "packages/gptel/gptel.elc" root))
         (error
          (unless (and (gptel-auto-workflow-bootstrap--known-gptel-load-error-p load-err)
                       (gptel-auto-workflow-bootstrap--gptel-ready-p))
            (signal (car load-err) (cdr load-err)))))
       (unless (gptel-auto-workflow-bootstrap--gptel-ready-p)
         (signal (car err) (cdr err)))))
    (require 'gptel-request)
    (require 'gptel-agent)
    (require 'gptel-agent-tools)))

(defun gptel-auto-workflow-bootstrap-run (root action)
  "Bootstrap headless workflow execution from ROOT for ACTION."
  (gptel-auto-workflow-bootstrap--seed-load-path root)
  (defvar gptel--tool-preview-alist nil)
  (load-file (expand-file-name "lisp/modules/nucleus-tools.el" root))
  (load-file (expand-file-name "lisp/modules/nucleus-prompts.el" root))
  (load-file (expand-file-name "lisp/modules/nucleus-presets.el" root))
  (gptel-auto-workflow-bootstrap--load-gptel-core root)
  (unless (fboundp 'gptel--format-tool-call)
    (defun gptel--format-tool-call (name arg-values)
      (format "(%s %s)\n"
              (propertize (or name "unknown") 'font-lock-face 'font-lock-keyword-face)
              (propertize (format "%s" arg-values) 'font-lock-face 'font-lock-string-face))))
  (load-file (expand-file-name "lisp/modules/gptel-ext-backends.el" root))
  (setq gptel-backend gptel--minimax
        gptel-model 'minimax-m2.7-highspeed)
  (load-file (expand-file-name "lisp/modules/gptel-tools.el" root))
  (when (fboundp 'gptel-tools-setup)
    (gptel-tools-setup))
  (load-file (expand-file-name "lisp/modules/gptel-tools-agent.el" root))
  (if (fboundp 'nucleus-presets-setup-agents)
      (progn
        ;; Reuse the normal preset refresh path so fresh worker daemons have
        ;; live agent dirs, presets, and tool contracts before worktree
        ;; buffers try to apply the agent preset.
        (nucleus-presets-setup-agents)
        (if (fboundp 'nucleus--after-agent-update)
            (nucleus--after-agent-update)
          (when (fboundp 'nucleus--register-gptel-directives)
            (nucleus--register-gptel-directives))
          (when (fboundp 'nucleus--override-gptel-agent-presets)
            (nucleus--override-gptel-agent-presets))))
    (when (fboundp 'nucleus--register-gptel-directives)
      (nucleus--register-gptel-directives))
    (when (fboundp 'nucleus--override-gptel-agent-presets)
      (nucleus--override-gptel-agent-presets)))
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
