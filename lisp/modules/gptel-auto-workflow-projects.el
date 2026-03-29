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

(require 'cl-lib)

;; Forward declarations for functions defined in gptel-tools-agent.el
(declare-function gptel-auto-workflow--project-root "gptel-tools-agent")
(declare-function gptel-auto-workflow-cron-safe "gptel-tools-agent")
(declare-function gptel-auto-workflow-run-async--guarded "gptel-tools-agent")
(declare-function gptel-auto-workflow-run-research "gptel-auto-workflow-strategic")
(declare-function gptel-fsm-info "gptel-fsm")
(declare-function gptel-mementum-weekly-job "gptel-tools-agent")
(declare-function gptel-benchmark-instincts-weekly-job "gptel-benchmark-instincts")

(defvar gptel-auto-workflow-projects
  (list (expand-file-name
         (or (bound-and-true-p minimal-emacs-user-directory)
             "~/.emacs.d")))
  "List of project roots with auto-workflow enabled.
Each project should have .dir-locals.el with workflow configuration.
Customize this variable to add more projects.")

(defvar gptel-auto-workflow--project-buffers (make-hash-table :test 'equal)
  "Hash table mapping project roots to their gptel-agent buffers.")

(defvar gptel-auto-workflow--current-project nil
  "Currently active project root for subagent context.")

(defvar mementum-root nil
  "Root directory for mementum. Set per-project.")

(defvar gptel-auto-workflow--project-root-override)
(defvar gptel-auto-workflow--worktree-state)
(defvar gptel-auto-workflow--research-findings-cache)

(defun gptel-auto-workflow--get-project-buffer (project-root)
  "Get or create a gptel-agent buffer for PROJECT-ROOT.
Each project gets its own isolated buffer for executor overlays."
  (let* ((root (expand-file-name project-root))
         (buf-name (format "*gptel-agent:%s*" (file-name-nondirectory (directory-file-name root))))
         (existing (gethash root gptel-auto-workflow--project-buffers)))
    ;; Check if existing buffer is still live
    (if (and existing (buffer-live-p existing))
        existing
      ;; Create new buffer (or recreate if previous was killed)
      (let ((buf (get-buffer-create buf-name)))
        (with-current-buffer buf
          ;; Set major mode first, then enable gptel
          (unless (derived-mode-p 'text-mode)
            (text-mode))
          (when (and (fboundp 'gptel-mode) (not (bound-and-true-p gptel-mode)))
            (condition-case err
                (gptel-mode)
              (error (message "[auto-workflow] Could not enable gptel-mode: %s" err))))
          ;; Apply nucleus preset for full agent capabilities
          (when (fboundp 'gptel--apply-preset)
            (condition-case err
                (progn
                  (gptel--apply-preset
                   'gptel-agent
                   (lambda (sym val) (set (make-local-variable sym) val)))
                  (message "[auto-workflow] Applied nucleus-gptel-agent preset to %s" buf-name))
              (error (message "[auto-workflow] Could not apply nucleus preset: %s" err))))
          ;; Set project context
          (setq-local default-directory root)
          ;; Load .dir-locals.el for project configuration
          (hack-dir-local-variables-non-file-buffer)
          (when (boundp 'gptel-auto-workflow--project-root-override)
            (setq-local gptel-auto-workflow--project-root-override root)))
        (puthash root buf gptel-auto-workflow--project-buffers)
        buf))))

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
      (let* ((default-directory project-root)
             (project-buf (gptel-auto-workflow--get-project-buffer project-root)))
        (condition-case err
            (progn
              ;; Set current project context for subagents
              (setq gptel-auto-workflow--current-project project-root)
              ;; Clear per-project state
              (when (hash-table-p gptel-auto-workflow--worktree-state)
                (clrhash gptel-auto-workflow--worktree-state))
              
              ;; Run workflow for this project in its dedicated buffer
              (with-current-buffer project-buf
                ;; Ensure .dir-locals.el is loaded for this project
                (hack-dir-local-variables-non-file-buffer)
                (gptel-auto-workflow-cron-safe))
              (push (cons project-root 'success) results)
              (message "[auto-workflow] ✓ Completed: %s" project-root))
          (error
           (push (cons project-root (format "error: %s" err)) results)
           (message "[auto-workflow] ✗ Failed: %s - %s" project-root err)))))
    (setq gptel-auto-workflow--current-project nil)
    (message "[auto-workflow] All projects processed: %s" 
             (mapconcat (lambda (r) (format "%s:%s" (car r) (cdr r)))
                        results ", "))
    results))

;;; Per-Project Subagent Buffer Support

(defvar gptel-auto-workflow--persist-executor-overlays nil
  "When non-nil, executor overlays persist after task completion.")

(defun gptel-auto-workflow--get-project-for-context ()
  "Determine which project context we're in.
Returns (project-root . project-buffer) or nil if can't determine."
  (cond
   ;; Case 1: Explicitly in multi-project mode
   (gptel-auto-workflow--current-project
    (cons gptel-auto-workflow--current-project
          (gptel-auto-workflow--get-project-buffer gptel-auto-workflow--current-project)))
   ;; Case 2: Check gptel-auto-workflow--project-root-override
   ((and (boundp 'gptel-auto-workflow--project-root-override)
         gptel-auto-workflow--project-root-override)
    (cons gptel-auto-workflow--project-root-override
          (gptel-auto-workflow--get-project-buffer gptel-auto-workflow--project-root-override)))
   ;; Case 3: Check if current directory is a configured project
   ((and (boundp 'gptel-auto-workflow-projects)
         (cl-some (lambda (proj)
                    (when (string-prefix-p (expand-file-name proj)
                                          (expand-file-name default-directory))
                      proj))
                  gptel-auto-workflow-projects))
    (let ((proj (cl-some (lambda (p)
                          (when (string-prefix-p (expand-file-name p)
                                                (expand-file-name default-directory))
                            p))
                        gptel-auto-workflow-projects)))
      (cons proj (gptel-auto-workflow--get-project-buffer proj))))
   ;; Case 4: Try to detect project from default-directory
   (t
    (let* ((proj (condition-case nil
                   (gptel-auto-workflow--project-root)
                 (error default-directory)))
           (expanded-proj (expand-file-name proj)))
      (cons expanded-proj (gptel-auto-workflow--get-project-buffer expanded-proj))))))

(defun gptel-auto-workflow--advice-task-override (orig-fun main-cb agent-type description prompt)
  "Advice around subagent task execution to use per-project buffers.
ORIG-FUN is the original task function, other args passed through.
When in auto-workflow context, routes to per-project buffer.
Otherwise, passes through to original function (no error)."
  (if-let* ((proj-context (gptel-auto-workflow--get-project-for-context))
            (project-root (car proj-context))
            (project-buf (cdr proj-context))
            ;; Only route if we're in auto-workflow context (explicitly set)
            (gptel-auto-workflow--current-project)
            ;; Ensure buffer is still live
            (_ (buffer-live-p project-buf)))
      ;; Route to per-project buffer (only in auto-workflow context)
      (let* ((default-directory project-root)
             (parent-fsm (and (boundp 'gptel--fsm-last) gptel--fsm-last))
             (info (and parent-fsm (gptel-fsm-info parent-fsm)))
             ;; Override the buffer in FSM info to use project buffer
             (modified-info (plist-put (copy-sequence info) :buffer project-buf)))
        (cl-letf (((symbol-function 'gptel-fsm-info)
                   (lambda (&optional fsm) (if (eq fsm parent-fsm) modified-info info)))
                  ;; Also set current buffer for overlay creation
                  ((symbol-function 'current-buffer)
                   (lambda () project-buf)))
          ;; For executor tasks, make overlay persist
          (if (and gptel-auto-workflow--persist-executor-overlays
                   (equal agent-type "executor"))
              (cl-letf (((symbol-function 'delete-overlay)
                         (lambda (&rest _) nil)))
                (funcall orig-fun main-cb agent-type description prompt))
            (funcall orig-fun main-cb agent-type description prompt))))
    ;; Not in auto-workflow context - pass through to original
    (funcall orig-fun main-cb agent-type description prompt)))

(defun gptel-auto-workflow-enable-per-project-subagents ()
  "Enable per-project subagent buffer support.
Installs advice on gptel-agent--task to route subagents to per-project buffers."
  (interactive)
  (when (fboundp 'gptel-agent--task)
    (advice-add 'gptel-agent--task :around #'gptel-auto-workflow--advice-task-override))
  (setq gptel-auto-workflow--persist-executor-overlays t)
  (message "[auto-workflow] Per-project subagent buffers enabled"))

(defun gptel-auto-workflow-disable-per-project-subagents ()
  "Disable per-project subagent buffer support."
  (interactive)
  (when (fboundp 'gptel-agent--task)
    (advice-remove 'gptel-agent--task #'gptel-auto-workflow--advice-task-override))
  (setq gptel-auto-workflow--persist-executor-overlays nil)
  (message "[auto-workflow] Per-project subagent buffers disabled"))

;; Auto-enable on load - safe now that pass-through is implemented
(gptel-auto-workflow-enable-per-project-subagents)

;;; Executor Overlay Management

(defun gptel-auto-workflow-clear-executor-overlays (&optional project-root)
  "Clear all persistent executor overlays for PROJECT-ROOT or all projects.
Without PROJECT-ROOT, clears overlays for all projects."
  (interactive)
  (if project-root
      (when-let* ((buf (gethash (expand-file-name project-root)
                                gptel-auto-workflow--project-buffers)))
        (with-current-buffer buf
          (dolist (ov (overlays-in (point-min) (point-max)))
            (when (overlay-get ov 'gptel-agent--task-type)
              (delete-overlay ov))))
        (message "[auto-workflow] Cleared executor overlays for %s" project-root))
    (maphash (lambda (_ buf)
               (when (buffer-live-p buf)
                 (with-current-buffer buf
                   (dolist (ov (overlays-in (point-min) (point-max)))
                     (when (overlay-get ov 'gptel-agent--task-type)
                       (delete-overlay ov))))))
             gptel-auto-workflow--project-buffers)
    (message "[auto-workflow] Cleared all executor overlays")))

(defun gptel-auto-workflow-list-project-buffers ()
  "List all project gptel-agent buffers."
  (interactive)
  (let ((buffers nil))
    (maphash (lambda (root buf)
               (push (format "%s -> %s (%s)"
                             root
                             (buffer-name buf)
                             (if (buffer-live-p buf) "live" "dead"))
                     buffers))
             gptel-auto-workflow--project-buffers)
    (if buffers
        (message "Project buffers:\n%s" (string-join buffers "\n"))
      (message "No project buffers created yet"))))

;;; Researcher Multi-Project Support

(defun gptel-auto-workflow-run-research-for-project (project-root)
  "Run researcher for specific PROJECT-ROOT.
Loads .dir-locals.el from project and runs researcher in that context."
  (interactive "DProject root: ")
  (let* ((root (expand-file-name project-root))
         (project-buf (gptel-auto-workflow--get-project-buffer root)))
    (message "[research] Starting for project: %s" root)
    ;; Ensure gptel-auto-workflow-strategic is loaded
    (unless (featurep 'gptel-auto-workflow-strategic)
      (load-file (expand-file-name "lisp/modules/gptel-auto-workflow-strategic.el" root)))
    ;; Set current project context for subagents
    (setq gptel-auto-workflow--current-project root)
    (with-current-buffer project-buf
      ;; Ensure .dir-locals.el is loaded for this project
      (hack-dir-local-variables-non-file-buffer)
      (gptel-auto-workflow-run-research))
    (setq gptel-auto-workflow--current-project nil)))

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
      (let* ((default-directory project-root)
             (project-buf (gptel-auto-workflow--get-project-buffer project-root)))
        (condition-case err
            (progn
              ;; Set current project context for subagents
              (setq gptel-auto-workflow--current-project project-root)
              (with-current-buffer project-buf
                ;; Ensure .dir-locals.el is loaded for this project
                (hack-dir-local-variables-non-file-buffer)
                (gptel-auto-workflow-run-research))
              (push (cons project-root 'success) results)
              (message "[research] ✓ Completed: %s" project-root))
          (error
           (push (cons project-root (format "error: %s" err)) results)
           (message "[research] ✗ Failed: %s - %s" project-root err))))
      (setq gptel-auto-workflow--current-project nil))
    (message "[research] All projects processed: %s" 
             (mapconcat (lambda (r) (format "%s:%s" (car r) (cdr r)))
                        results ", "))
    results))

;;; Research Cache Management

(defun gptel-auto-workflow-clear-research-cache (&optional project-root)
  "Clear research findings cache for PROJECT-ROOT or all projects.
Without PROJECT-ROOT, clears cache for all projects."
  (interactive)
  (if project-root
      (let ((root (expand-file-name project-root)))
        (remhash root gptel-auto-workflow--research-findings-cache)
        (message "[research] Cleared findings cache for %s" root))
    (clrhash gptel-auto-workflow--research-findings-cache)
    (message "[research] Cleared findings cache for all projects")))

(defun gptel-auto-workflow-research-status-all ()
  "Show research status for all configured projects."
  (interactive)
  (let ((status-lines '()))
    (dolist (project-root gptel-auto-workflow-projects)
      (let* ((findings (gethash project-root gptel-auto-workflow--research-findings-cache ""))
             (cache-file (expand-file-name "var/tmp/research-findings.md" project-root))
             (file-exists (file-exists-p cache-file))
             (file-size (if file-exists
                            (nth 7 (file-attributes cache-file))
                          0)))
        (push (format "  %s:\n    In-memory: %d chars\n    File: %s (%d bytes)"
                      project-root
                      (length findings)
                      (if file-exists "exists" "none")
                      file-size)
              status-lines)))
    (message "Research cache status:\n%s" (string-join (nreverse status-lines) "\n"))))

;;; Mementum Multi-Project Support

(defun gptel-auto-workflow-run-mementum-for-project (project-root)
  "Run mementum weekly job for specific PROJECT-ROOT.
Loads project context and runs mementum maintenance in that context."
  (interactive "DProject root: ")
  (let* ((root (expand-file-name project-root))
         (default-directory root)
         (mementum-root root))
    (message "[mementum] Starting weekly job for project: %s" root)
    ;; Ensure gptel-tools-agent is loaded for mementum functions
    (unless (featurep 'gptel-tools-agent)
      (load-file (expand-file-name "lisp/modules/gptel-tools-agent.el" root)))
    (setq gptel-auto-workflow--current-project root)
    (condition-case err
        (progn
          (gptel-mementum-weekly-job)
          (message "[mementum] ✓ Completed: %s" root))
      (error
       (message "[mementum] ✗ Failed: %s - %s" root err)
       nil))
    (setq gptel-auto-workflow--current-project nil)))

(defun gptel-auto-workflow-run-all-mementum ()
  "Run mementum weekly job for all configured projects.
To be called from cron - runs mementum maintenance for each project."
  (interactive)
  (message "[mementum] Running weekly job for %d projects..."
           (length gptel-auto-workflow-projects))
  (let ((results nil))
    (dolist (project-root gptel-auto-workflow-projects)
      (message "[mementum] Processing project: %s" project-root)
      (condition-case err
          (progn
            (gptel-auto-workflow-run-mementum-for-project project-root)
            (push (cons project-root 'success) results))
        (error
         (push (cons project-root (format "error: %s" err)) results)
         (message "[mementum] ✗ Failed: %s - %s" project-root err))))
    (message "[mementum] All projects processed: %s"
             (mapconcat (lambda (r) (format "%s:%s" (car r) (cdr r)))
                        results ", "))
    results))

;;; Instincts (Benchmark) Multi-Project Support

(defun gptel-auto-workflow-run-instincts-for-project (project-root)
  "Run instincts weekly job for specific PROJECT-ROOT.
Loads project context and runs instincts evolution in that context."
  (interactive "DProject root: ")
  (let* ((root (expand-file-name project-root))
         (default-directory root)
         (mementum-root root))
    (message "[instincts] Starting weekly job for project: %s" root)
    ;; Ensure gptel-benchmark-instincts is loaded
    (unless (featurep 'gptel-benchmark-instincts)
      (load-file (expand-file-name "lisp/modules/gptel-benchmark-instincts.el" root)))
    (setq gptel-auto-workflow--current-project root)
    (condition-case err
        (progn
          (gptel-benchmark-instincts-weekly-job)
          (message "[instincts] ✓ Completed: %s" root))
      (error
       (message "[instincts] ✗ Failed: %s - %s" root err)
       nil))
    (setq gptel-auto-workflow--current-project nil)))

(defun gptel-auto-workflow-run-all-instincts ()
  "Run instincts weekly job for all configured projects.
To be called from cron - runs instincts evolution for each project."
  (interactive)
  (message "[instincts] Running weekly job for %d projects..."
           (length gptel-auto-workflow-projects))
  (let ((results nil))
    (dolist (project-root gptel-auto-workflow-projects)
      (message "[instincts] Processing project: %s" project-root)
      (condition-case err
          (progn
            (gptel-auto-workflow-run-instincts-for-project project-root)
            (push (cons project-root 'success) results))
        (error
         (push (cons project-root (format "error: %s" err)) results)
         (message "[instincts] ✗ Failed: %s - %s" project-root err))))
    (message "[instincts] All projects processed: %s"
             (mapconcat (lambda (r) (format "%s:%s" (car r) (cdr r)))
                        results ", "))
    results))

(provide 'gptel-auto-workflow-projects)
;;; gptel-auto-workflow-projects.el ends here
