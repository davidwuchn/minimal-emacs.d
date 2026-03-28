;;; gptel-auto-workflow-projects.el --- Multi-project auto-workflow support -*- lexical-binding: t -*-

;; This file provides multi-project support for auto-workflow.
;; Each project should have .dir-locals.el with workflow configuration.
;;
;; Configuration:
;; (setq gptel-auto-workflow-projects
;;       '("~/projects/project1"
;;         "~/projects/project2"
;;         "~/.emacs.d"))

;;; Code:

(defvar gptel-auto-workflow-projects
  (list (expand-file-name
         (or (bound-and-true-p minimal-emacs-user-directory)
             "~/.emacs.d")))
  "List of project roots with auto-workflow enabled.
Each project should have .dir-locals.el with workflow configuration.
Customize this variable to add more projects.")

(defun gptel-auto-workflow-add-project (project-root)
  "Add PROJECT-ROOT to auto-workflow projects list.
Interactively prompts for directory."
  (interactive "DProject root: ")
  (let ((root (expand-file-name project-root)))
    (unless (file-exists-p (expand-file-name ".dir-locals.el" root))
      (error "No .dir-locals.el found in %s" root))
    (unless (member root gptel-auto-workflow-projects)
      (push root gptel-auto-workflow-projects)
      (customize-save-variable 'gptel-auto-workflow-projects 
                               gptel-auto-workflow-projects))
    (message "Added project: %s" root)))

(defun gptel-auto-workflow-remove-project (project-root)
  "Remove PROJECT-ROOT from auto-workflow projects list."
  (interactive
   (list (completing-read "Remove project: " 
                          gptel-auto-workflow-projects)))
  (setq gptel-auto-workflow-projects 
        (delete (expand-file-name project-root) gptel-auto-workflow-projects))
  (customize-save-variable 'gptel-auto-workflow-projects 
                           gptel-auto-workflow-projects)
  (message "Removed project: %s" project-root))

(defun gptel-auto-workflow-list-projects ()
  "Display list of configured projects."
  (interactive)
  (message "Auto-workflow projects:\n%s"
           (mapconcat (lambda (p) (format "  - %s" p))
                      gptel-auto-workflow-projects
                      "\n")))

(defun gptel-auto-workflow-run-all-projects ()
  "Run auto-workflow for all configured projects.
To be called from cron - visits each project directory (loading .dir-locals.el),
then runs workflow for that project."
  (interactive)
  (message "[auto-workflow] Running for %d projects..." 
           (length gptel-auto-workflow-projects))
  (let ((results nil))
    (dolist (project-root gptel-auto-workflow-projects)
      (message "[auto-workflow] Processing project: %s" project-root)
      (let ((default-directory project-root))
        ;; .dir-locals.el will be loaded when we change to project directory
        (condition-case err
            (progn
              ;; Re-initialize with project context
              (setq gptel-auto-workflow--project-root-override project-root)
              ;; Clear per-project state
              (when (hash-table-p gptel-auto-workflow--worktree-state)
                (clrhash gptel-auto-workflow--worktree-state))
              
              ;; Run workflow for this project
              (gptel-auto-workflow-cron-safe)
              (push (cons project-root 'success) results)
              (message "[auto-workflow] ✓ Completed: %s" project-root))
          (error
           (push (cons project-root (format "error: %s" err)) results)
           (message "[auto-workflow] ✗ Failed: %s - %s" project-root err)))))
    (message "[auto-workflow] All projects processed: %s" 
             (mapconcat (lambda (r) (format "%s:%s" (car r) (cdr r)))
                        results ", "))
    results))

;;; Researcher Multi-Project Support

(defun gptel-auto-workflow-run-research-for-project (project-root)
  "Run researcher for specific PROJECT-ROOT.
Loads .dir-locals.el from project and runs researcher in that context."
  (interactive "DProject root: ")
  (let ((root (expand-file-name project-root))
        (default-directory (expand-file-name project-root)))
    (message "[research] Starting for project: %s" root)
    ;; Ensure gptel-auto-workflow-strategic is loaded
    (unless (featurep 'gptel-auto-workflow-strategic)
      (load-file (expand-file-name "lisp/modules/gptel-auto-workflow-strategic.el" root)))
    ;; Override project root temporarily
    (let ((gptel-auto-workflow--project-root-override root))
      (gptel-auto-workflow-run-research))))

(defun gptel-auto-workflow-run-all-research ()
  "Run researcher for all configured projects.
To be called from cron - visits each project directory (loading .dir-locals.el),
then runs researcher for that project."
  (interactive)
  (message "[research] Running for %d projects..." 
           (length gptel-auto-workflow-projects))
  (let ((results nil))
    (dolist (project-root gptel-auto-workflow-projects)
      (message "[research] Processing project: %s" project-root)
      (let ((default-directory project-root))
        ;; .dir-locals.el will be loaded when we change to project directory
        (condition-case err
            (progn
              ;; Override project root temporarily
              (let ((gptel-auto-workflow--project-root-override project-root))
                (gptel-auto-workflow-run-research))
              (push (cons project-root 'success) results)
              (message "[research] ✓ Completed: %s" project-root))
          (error
           (push (cons project-root (format "error: %s" err)) results)
           (message "[research] ✗ Failed: %s - %s" project-root err)))))
    (message "[research] All projects processed: %s" 
             (mapconcat (lambda (r) (format "%s:%s" (car r) (cdr r)))
                        results ", "))
    results))

(provide 'gptel-auto-workflow-projects)
;;; gptel-auto-workflow-projects.el ends here
