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
(require 'gptel-tools-agent)

;; External variables from gptel-tools-agent.el
(defvar gptel-auto-workflow--worktree-state nil)
(defvar gptel-auto-workflow-worktree-base nil)
(defvar gptel-auto-workflow--current-target nil)

;; Forward declarations for functions defined in gptel-tools-agent.el
(declare-function gptel-auto-workflow--project-root "gptel-tools-agent")
(declare-function gptel-auto-workflow--get-worktree-dir "gptel-tools-agent")
(declare-function gptel-auto-workflow--mark-messages-start "gptel-tools-agent")
(declare-function gptel-auto-workflow--persist-status "gptel-tools-agent")
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

(defvar gptel-auto-workflow--run-project-root nil
  "Stable project root captured for the active workflow run.")

(defvar gptel-auto-workflow--cron-job-running nil
  "Non-nil while a queued cron job is executing.")

;; Forward declarations for variables defined in gptel-tools-agent.el
(defvar gptel-auto-workflow--stats nil)
(defvar gptel-auto-workflow--running nil)
(defvar gptel-auto-workflow--cron-job-timer nil)

(defvar mementum-root nil
  "Root directory for mementum. Set per-project.")

(defvar gptel-auto-workflow--project-root-override)
(defvar gptel-auto-workflow--research-findings-cache (make-hash-table :test 'equal)
  "Hash table caching research findings per project root.")

(defvar gptel-auto-workflow--worktree-buffers (make-hash-table :test 'equal)
  "Hash table of gptel-agent buffers per worktree.
Key: worktree directory, Value: buffer.
Each worktree gets its own isolated buffer for subagent overlays.")

(defun gptel-auto-workflow--ensure-buffer-tables ()
  "Ensure shared project/worktree buffer tables are initialized."
  (unless (hash-table-p gptel-auto-workflow--project-buffers)
    (setq gptel-auto-workflow--project-buffers (make-hash-table :test 'equal)))
  (unless (hash-table-p gptel-auto-workflow--worktree-buffers)
    (setq gptel-auto-workflow--worktree-buffers (make-hash-table :test 'equal))))

(defun gptel-auto-workflow--normalized-projects ()
  "Return configured project roots as unique expanded directory names."
  (delete-dups
   (mapcar (lambda (project-root)
             (file-name-as-directory (expand-file-name project-root)))
           gptel-auto-workflow-projects)))

(defun gptel-auto-workflow--normalize-worktree-dir (worktree-dir &optional project-root)
  "Return WORKTREE-DIR as an absolute directory name.
Relative worktree paths are anchored to PROJECT-ROOT or the active workflow
project instead of the current buffer's `default-directory'."
  (when (and (stringp worktree-dir)
             (> (length worktree-dir) 0))
    (file-name-as-directory
     (expand-file-name
      worktree-dir
      (or project-root
          gptel-auto-workflow--current-project
          (and (boundp 'gptel-auto-workflow--project-root-override)
               gptel-auto-workflow--project-root-override)
          (ignore-errors (gptel-auto-workflow--project-root))
          default-directory)))))

(defun gptel-auto-workflow--buffer-tool-snapshot (&optional buffer)
  "Return BUFFER's active tool snapshot, or nil when tools are disabled."
  (when-let* ((buf (or (and (buffer-live-p buffer) buffer)
                       (current-buffer))))
    (with-current-buffer buf
      (and (boundp 'gptel-use-tools)
           gptel-use-tools
           (boundp 'gptel-tools)
           gptel-tools
           (copy-sequence gptel-tools)))))

(defun gptel-auto-workflow--routed-fsm-info (info target-buf target-marker)
  "Return FSM INFO rewritten for TARGET-BUF and TARGET-MARKER.
Preserves routed buffer tool snapshots so early tool calls do not see a
placeholder FSM with an empty `:tools' list."
  (let ((updated-info (copy-sequence (or info '()))))
    (setq updated-info (plist-put updated-info :buffer target-buf))
    (setq updated-info (plist-put updated-info :position target-marker))
    (setq updated-info (plist-put updated-info :tracking-marker target-marker))
    (if-let ((buffer-tools (gptel-auto-workflow--buffer-tool-snapshot target-buf)))
        (plist-put updated-info :tools buffer-tools)
      updated-info)))

(defun gptel-auto-workflow--get-worktree-buffer (worktree-dir)
  "Get or create a gptel-agent buffer for WORKTREE-DIR.
Each worktree gets its own isolated buffer for subagent overlays."
  (unless worktree-dir (error "WORKTREE-DIR cannot be nil"))
  (gptel-auto-workflow--ensure-buffer-tables)
  (let* ((root (gptel-auto-workflow--normalize-worktree-dir worktree-dir))
         (worktree-name (file-name-nondirectory (directory-file-name root)))
         (buf-name (format "*gptel-agent:%s@%s*"
                           worktree-name
                           (substring (md5 root) 0 8)))
         (existing (gethash root gptel-auto-workflow--worktree-buffers)))
    ;; Check if existing buffer is still live
    (if (and existing (buffer-live-p existing))
        (progn
          (with-current-buffer existing
            (setq-local default-directory root))
          existing)
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
          ;; Set worktree context
          (setq-local default-directory root)
          ;; Load .dir-locals.el for project configuration
          (hack-dir-local-variables-non-file-buffer)
          ;; Create initial FSM for agent tasks
          ;; This prevents "Wrong type argument: gptel-fsm, nil" error
          ;; when gptel-agent--task tries to access gptel--fsm-last
          (when (fboundp 'gptel-make-fsm)
            ;; Ensure FSM-related variables are defined
            (require 'gptel-request nil t)
            (require 'gptel-agent-tools nil t)
            ;; Create FSM with proper table and handlers
            (setq-local gptel--fsm-last
                        (gptel-make-fsm
                         :table (when (boundp 'gptel-send--transitions)
                                  gptel-send--transitions)
                         :handlers (when (boundp 'gptel-agent-request--handlers)
                                     gptel-agent-request--handlers)
                         :info (list :buffer buf
                                     :position (point-max-marker)
                                     :tracking-marker (point-max-marker))))
            (message "[auto-workflow] Created FSM in %s" buf-name))
          ;; Protect buffer from being killed during experiments
          (setq-local kill-buffer-query-functions
                      (cons (lambda ()
                              (when (and (boundp 'gptel-auto-workflow--running)
                                         gptel-auto-workflow--running)
                                (message "[auto-workflow] Blocking kill of worktree buffer during run")
                                nil))
                            kill-buffer-query-functions)))
        (puthash root buf gptel-auto-workflow--worktree-buffers)
        (puthash root buf gptel-auto-workflow--project-buffers)
        buf))))

(defun gptel-auto-workflow--get-project-buffer (project-root)
  "Get or create a gptel-agent buffer for PROJECT-ROOT.
Legacy function - routes to worktree buffer for backward compatibility."
  (gptel-auto-workflow--get-worktree-buffer project-root))

(defun gptel-auto-workflow-add-project (project-root)
  "Add PROJECT-ROOT to auto-workflow projects list.
Interactively prompts for directory."
  (interactive "DProject root: ")
  (let ((root (file-name-as-directory (expand-file-name project-root))))
    (unless (file-exists-p (expand-file-name ".dir-locals.el" root))
      (error "No .dir-locals.el found in %s" root))
    (unless (member root gptel-auto-workflow-projects)
      (push root gptel-auto-workflow-projects)
      (customize-save-variable 'gptel-auto-workflow-projects 
                               gptel-auto-workflow-projects)
      (remhash root gptel-auto-workflow--project-buffers)
      (remhash root gptel-auto-workflow--worktree-buffers)
      (remhash root gptel-auto-workflow--research-findings-cache))
    (message "Added project: %s" root)))

(defun gptel-auto-workflow-remove-project (project-root)
  "Remove PROJECT-ROOT from auto-workflow projects list."
  (interactive
   (list (completing-read "Remove project: " 
                          gptel-auto-workflow-projects)))
  (let ((root (file-name-as-directory (expand-file-name project-root))))
    (setq gptel-auto-workflow-projects 
          (delete root gptel-auto-workflow-projects))
    (customize-save-variable 'gptel-auto-workflow-projects 
                             gptel-auto-workflow-projects)
    (remhash root gptel-auto-workflow--project-buffers)
    (remhash root gptel-auto-workflow--worktree-buffers)
    (remhash root gptel-auto-workflow--research-findings-cache)
    (message "Removed project: %s" root)))

(defun gptel-auto-workflow-list-projects ()
  "Display list of configured projects."
  (interactive)
  (message "Auto-workflow projects:\n%s"
           (mapconcat (lambda (p) (format "  - %s" p))
                      (gptel-auto-workflow--normalized-projects)
                      "\n")))

(defun gptel-auto-workflow-run-all-projects (&optional completion-callback)
  "Run auto-workflow for all configured projects.
To be called from cron - visits each project directory (loading .dir-locals.el),
then runs workflow for that project.
When COMPLETION-CALLBACK is non-nil, call it after all project workflows
finish."
  (interactive)
  (let ((projects (gptel-auto-workflow--normalized-projects)))
    (message "[auto-workflow] Running for %d projects..."
             (length projects))
    (let* ((results nil)
           (remaining projects)
           (finish
            (gptel-auto-workflow--make-idempotent-callback
             (lambda ()
               (let ((final-results (nreverse results)))
                 (setq gptel-auto-workflow--run-project-root nil)
                 (setq gptel-auto-workflow--current-project nil)
                 (message "[auto-workflow] All projects processed: %s"
                          (mapconcat (lambda (r) (format "%s:%s" (car r) (cdr r)))
                                     final-results ", "))
                 (when completion-callback
                   (funcall completion-callback final-results))
                 final-results)))))
      (cl-labels
          ((run-next ()
             (if (null remaining)
                 (funcall finish)
               (let* ((project-root (car remaining))
                      (default-directory project-root)
                      (project-buf (gptel-auto-workflow--get-project-buffer project-root)))
                 (setq remaining (cdr remaining))
                 (message "[auto-workflow] Processing project: %s" project-root)
                 (condition-case err
                     (progn
                       (setq gptel-auto-workflow--current-project project-root)
                       (setq gptel-auto-workflow--run-project-root project-root)
                       (when (hash-table-p gptel-auto-workflow--worktree-state)
                         (clrhash gptel-auto-workflow--worktree-state))
                       (with-current-buffer project-buf
                         (hack-dir-local-variables-non-file-buffer)
                         (let ((mark-project
                                (gptel-auto-workflow--make-idempotent-callback
                                 (lambda (status log-line)
                                   (push (cons project-root status) results)
                                   (message "%s" log-line)
                                   (run-next))))
                               (project-completion
                                (lambda ()
                                  (cond
                                   (gptel-auto-experiment--quota-exhausted
                                    (cons 'quota-exhausted
                                          (format "[auto-workflow] ! Quota exhausted: %s"
                                                  project-root)))
                                   ((equal (plist-get gptel-auto-workflow--stats :phase) "error")
                                    (cons 'error
                                          (format "[auto-workflow] ✗ Failed: %s"
                                                  project-root)))
                                   (t
                                    (cons 'success
                                          (format "[auto-workflow] ✓ Completed: %s"
                                                  project-root)))))))
                           (let ((started
                                  (gptel-auto-workflow-cron-safe
                                   (lambda (&rest _workflow-results)
                                     (pcase-let ((`(,status . ,log-line)
                                                  (funcall project-completion)))
                                       (funcall mark-project status log-line))))))
                             (unless started
                               (funcall mark-project
                                        'skipped
                                        (format "[auto-workflow] - Skipped: %s"
                                                project-root)))))))
                   (error
                    (push (cons project-root (format "error: %s" err)) results)
                    (message "[auto-workflow] ✗ Failed: %s - %s" project-root err)
                    (run-next)))))))
        (run-next)))))

(defun gptel-auto-workflow--finish-queued-cron-job (label &optional errored)
  "Clear queued cron state after LABEL completes.
When ERRORED is non-nil, preserve the existing error phase."
  (setq gptel-auto-workflow--cron-job-running nil
        gptel-auto-workflow--cron-job-timer nil)
  (let ((phase (plist-get gptel-auto-workflow--stats :phase)))
    (when (and (not errored)
               (not (bound-and-true-p gptel-auto-workflow--running))
               (member phase (list label
                                   (format "%s-queued" label)
                                   "selecting"
                                   "running")))
      (setq gptel-auto-workflow--stats
            (plist-put gptel-auto-workflow--stats :phase "idle"))))
  (when (fboundp 'gptel-auto-workflow--persist-status)
    (gptel-auto-workflow--persist-status)))

(cl-defun gptel-auto-workflow--queue-cron-job (label fn &key async)
  "Queue FN for LABEL and return immediately.
This keeps `emacsclient --eval' callers from monopolizing the daemon.
When ASYNC is non-nil, FN must accept a completion callback and invoke it when
the queued job actually finishes."
  (if (or gptel-auto-workflow--cron-job-running
          (bound-and-true-p gptel-auto-workflow--running))
      (progn
        (message "[%s] Job already running; skipping new request" label)
        (when (fboundp 'gptel-auto-workflow--persist-status)
          (gptel-auto-workflow--persist-status))
        'already-running)
    (setq gptel-auto-workflow--cron-job-running t)
    (when (fboundp 'gptel-auto-workflow--make-run-id)
      (setq gptel-auto-workflow--run-id
            (gptel-auto-workflow--make-run-id)
            gptel-auto-workflow--status-run-id
            gptel-auto-workflow--run-id))
    (when (fboundp 'gptel-auto-workflow--mark-messages-start)
      (gptel-auto-workflow--mark-messages-start))
    (setq gptel-auto-workflow--stats
          (list :phase (format "%s-queued" label)
                :total 0
                :kept 0))
    (message "[%s] Queued background job" label)
    (when (fboundp 'gptel-auto-workflow--persist-status)
      (gptel-auto-workflow--persist-status))
    (let (timer)
      (setq gptel-auto-workflow--cron-job-timer
            (setq timer
                  (run-at-time
                   0 nil
                   (lambda ()
                     (when (and gptel-auto-workflow--cron-job-running
                                (eq gptel-auto-workflow--cron-job-timer timer))
                       (setq gptel-auto-workflow--cron-job-timer nil)
                       (let ((finish-job
                              (gptel-auto-workflow--make-idempotent-callback
                               (lambda (&optional errored)
                                 (gptel-auto-workflow--finish-queued-cron-job label errored)))))
                         (setq gptel-auto-workflow--stats
                               (plist-put gptel-auto-workflow--stats :phase label))
                         (when (fboundp 'gptel-auto-workflow--persist-status)
                           (gptel-auto-workflow--persist-status))
                         (condition-case err
                             (if async
                                 (funcall fn finish-job)
                               (progn
                                 (funcall fn)
                                 (funcall finish-job)))
                           (error
                            (setq gptel-auto-workflow--stats
                                  (plist-put gptel-auto-workflow--stats :phase "error"))
                            (message "[%s] Job failed: %s" label err)
                            (funcall finish-job err)))))))))
      'queued)))

(defun gptel-auto-workflow-queue-all-projects ()
  "Queue `gptel-auto-workflow-run-all-projects' and return immediately."
  (interactive)
  (gptel-auto-workflow--queue-cron-job
   "auto-workflow"
   (lambda (completion-callback)
     (gptel-auto-workflow-run-all-projects completion-callback))
   :async t))

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
         gptel-auto-workflow-projects)
    (let ((current-dir (expand-file-name default-directory))
          proj)
      (setq proj (cl-loop for p in gptel-auto-workflow-projects
                          when (string-prefix-p (expand-file-name p) current-dir)
                          return p))
      (when proj
        (cons proj (gptel-auto-workflow--get-project-buffer proj)))))
   ;; Case 4: Try to detect project from default-directory
   (t
    (let* ((proj (or (condition-case nil
                         (gptel-auto-workflow--project-root)
                       (error default-directory))
                     default-directory))
           (expanded-proj (expand-file-name proj)))
      (cons expanded-proj (gptel-auto-workflow--get-project-buffer expanded-proj))))))

(defun gptel-auto-workflow--advice-task-override (orig-fun main-cb agent-type description prompt)
  "Advice around subagent task execution to use per-project buffers.
ORIG-FUN is the original task function, other args passed through.
When in auto-workflow context, routes to per-project buffer.
Otherwise, passes through to original function (no error).
NEVER allows overlays in *Messages* buffer.
Also handles caching and result truncation from old advice."
  ;; Check cache first (from old my/gptel-agent--task-override)
  (let ((cached (and (fboundp 'my/gptel--subagent-cache-get)
                     (my/gptel--subagent-cache-get agent-type prompt))))
    (if cached
        (progn
          (message "[nucleus] Subagent %s cache hit" agent-type)
          (funcall main-cb cached))
      ;; Not cached - determine routing
      (let* ((in-auto-workflow gptel-auto-workflow--current-project)
             (proj-context (gptel-auto-workflow--get-project-for-context))
             (project-root
              (file-name-as-directory
               (expand-file-name
                (or (car proj-context)
                    (if (bound-and-true-p minimal-emacs-user-directory)
                        minimal-emacs-user-directory
                      "~/.emacs.d")))))
             (worktree-base-expanded
              (expand-file-name (or gptel-auto-workflow-worktree-base
                                    "var/tmp/experiments")
                                project-root))
             (target-worktree-dir
              (when (and in-auto-workflow
                         gptel-auto-workflow--current-target
                         (fboundp 'gptel-auto-workflow--get-worktree-dir))
                (gptel-auto-workflow--normalize-worktree-dir
                 (gptel-auto-workflow--get-worktree-dir
                  gptel-auto-workflow--current-target)
                 project-root)))
             (current-dir (file-name-as-directory (expand-file-name default-directory)))
             (worktree-base-dir (file-name-as-directory worktree-base-expanded))
             (worktree-dir (or target-worktree-dir
                               (when (and in-auto-workflow
                                          (string-prefix-p worktree-base-dir current-dir))
                                 current-dir)))
             (missing-executor-worktree
              (and in-auto-workflow
                   (equal agent-type "executor")
                   (not worktree-dir)))
             (target-buf (if worktree-dir
                             (gptel-auto-workflow--get-worktree-buffer worktree-dir)
                           (or (cdr proj-context)
                               (gptel-auto-workflow--get-worktree-buffer project-root)))))
        ;; CRITICAL: Validate worktree exists before proceeding
        (if missing-executor-worktree
            (progn
              (message "[auto-workflow] Missing executor worktree context, aborting: %s"
                       (or gptel-auto-workflow--current-target project-root))
              (funcall main-cb
                       (format "Error: Missing worktree context for executor task: %s"
                               (or description "unknown task"))))
          (if (and worktree-dir (not (file-exists-p worktree-dir)))
              (progn
                (message "[auto-workflow] Worktree deleted, aborting: %s" worktree-dir)
                (funcall main-cb (format "Error: Worktree no longer exists: %s" worktree-dir)))
            (if (and target-buf 
                     (buffer-live-p target-buf)
                     (not (string= (buffer-name target-buf) "*Messages*")))
                (progn
                  (when (fboundp 'my/gptel--register-agent-task-buffer)
                    (my/gptel--register-agent-task-buffer target-buf))
                  (with-current-buffer target-buf
                    (when (fboundp 'gptel-auto-workflow--persist-subagent-process-environment)
                      (gptel-auto-workflow--persist-subagent-process-environment
                       target-buf))
                    ;; Ensure FSM exists for agent task
                    (unless (and (boundp 'gptel--fsm-last) gptel--fsm-last)
                      ;; Create minimal FSM for agent context
                      (when (fboundp 'gptel-make-fsm)
                        (setq-local gptel--fsm-last
                                    (gptel-make-fsm
                                     :table (when (boundp 'gptel-send--transitions) gptel-send--transitions)
                                     :handlers nil
                                     :info (gptel-auto-workflow--routed-fsm-info
                                            nil target-buf (point-marker))))))
                    (let* ((default-directory (or worktree-dir project-root))
                           (target-marker (point-marker))
                           (parent-fsm (and (boundp 'gptel--fsm-last) gptel--fsm-last))
                           (orig-gptel-fsm-info (symbol-function 'gptel-fsm-info))
                           (info (or (and parent-fsm (gptel-fsm-info parent-fsm))
                                     (list :buffer target-buf :position target-marker)))
                           (modified-info (gptel-auto-workflow--routed-fsm-info
                                           info target-buf target-marker))
                           ;; Wrap callback to cache results
                           (wrapped-cb (lambda (result)
                                         (when (and (stringp result)
                                                    (fboundp 'my/gptel--subagent-cache-put))
                                           (my/gptel--subagent-cache-put agent-type prompt result))
                                         (funcall main-cb result)))
                           (task-runner (if (fboundp 'my/gptel-agent--task-override)
                                            #'my/gptel-agent--task-override
                                          orig-fun)))
                      (cl-letf (((symbol-function 'gptel-fsm-info)
                                 (lambda (&optional fsm)
                                   (let ((active-fsm
                                          (or fsm
                                              (and (boundp 'gptel--fsm-last)
                                                   gptel--fsm-last))))
                                     (cond
                                      ((eq active-fsm parent-fsm)
                                       modified-info)
                                      (active-fsm
                                       (funcall orig-gptel-fsm-info active-fsm))
                                      (t nil))))))
                        (if (and gptel-auto-workflow--persist-executor-overlays
                                 (equal agent-type "executor"))
                            (cl-letf (((symbol-function 'delete-overlay)
                                       (lambda (&rest _) nil)))
                              (funcall task-runner wrapped-cb agent-type description prompt))
                          (funcall task-runner wrapped-cb agent-type description prompt))))))
              ;; SAFETY: Never execute in *Messages* buffer - find safe fallback
              (let ((safe-buffer (cond
                                  ((not (string= (buffer-name) "*Messages*"))
                                   (current-buffer))
                                  ((get-buffer "*gptel*")
                                   (get-buffer "*gptel*"))
                                  ((get-buffer "*scratch*")  
                                   (get-buffer "*scratch*"))
                                  (t
                                   (get-buffer-create "*gptel-safe-fallback*")))))
                (when (fboundp 'my/gptel--register-agent-task-buffer)
                  (my/gptel--register-agent-task-buffer safe-buffer))
                (with-current-buffer safe-buffer
                  (funcall orig-fun main-cb agent-type description prompt))))))))))

(defun gptel-auto-workflow-enable-per-project-subagents ()
  "Enable per-project subagent buffer support.
Installs advice on gptel-agent--task to route subagents to per-project buffers.
Also removes old conflicting :override advice if present."
  (interactive)
  (when (fboundp 'gptel-agent--task)
    ;; Remove old conflicting :override advice if present
    (condition-case nil
        (advice-remove 'gptel-agent--task #'my/gptel-agent--task-override)
      (error nil))
    ;; Install new :around advice for buffer routing
    (advice-add 'gptel-agent--task :around #'gptel-auto-workflow--advice-task-override))
  ;; Install overlay buffer routing advice
  (gptel-auto-workflow--enable-overlay-buffer-advice)
  (setq gptel-auto-workflow--persist-executor-overlays t)
  (message "[auto-workflow] Per-project subagent buffers enabled"))

(defun gptel-auto-workflow-disable-per-project-subagents ()
  "Disable per-project subagent buffer support."
  (interactive)
  (when (fboundp 'gptel-agent--task)
    (advice-remove 'gptel-agent--task #'gptel-auto-workflow--advice-task-override))
  (when (fboundp 'gptel-agent--task-overlay)
    (advice-remove 'gptel-agent--task-overlay #'gptel-auto-workflow--advice-task-overlay-buffer))
  (setq gptel-auto-workflow--persist-executor-overlays nil)
  (message "[auto-workflow] Per-project subagent buffers disabled"))

;;; Advice for overlay buffer routing

(defun gptel-auto-workflow--advice-task-overlay-buffer (orig-fun where &optional agent-type description)
  "Ensure overlay is created in the correct buffer.
ORIG-FUN is the original function. WHERE is position/marker.
Gets target buffer from gptel-fsm-info and creates overlay there."
  (let* ((fsm (and (boundp 'gptel--fsm-last) gptel--fsm-last))
         (info (and fsm (fboundp 'gptel-fsm-info) (gptel-fsm-info fsm)))
         (target-buf (and info (plist-get info :buffer))))
    (if (and target-buf (buffer-live-p target-buf))
        (with-current-buffer target-buf
          (funcall orig-fun where agent-type description))
      (funcall orig-fun where agent-type description))))

(defun gptel-auto-workflow--enable-overlay-buffer-advice ()
  "Enable advice to route overlays to correct buffer."
  (when (fboundp 'gptel-agent--task-overlay)
    (advice-add 'gptel-agent--task-overlay :around 
                #'gptel-auto-workflow--advice-task-overlay-buffer)))

;; Auto-enable on load - safe now that pass-through is implemented
(gptel-auto-workflow-enable-per-project-subagents)
(gptel-auto-workflow--enable-overlay-buffer-advice)

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

(defun gptel-auto-workflow-queue-all-research ()
  "Queue `gptel-auto-workflow-run-all-research' and return immediately."
  (interactive)
  (gptel-auto-workflow--queue-cron-job
   "research"
   #'gptel-auto-workflow-run-all-research))

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

;;; Weekly Job Runner (shared by mementum and instincts)

(defun gptel-auto-workflow--run-weekly-job-for-project
    (project-root prefix feature-name file-path job-fn)
  "Run a weekly job for PROJECT-ROOT with given PREFIX, FEATURE-NAME, FILE-PATH, and JOB-FN.
Loads the feature if needed, enables headless suppression, runs JOB-FN,
and restores headless state. Returns t on success, nil on failure."
  (let* ((root (expand-file-name project-root))
         (default-directory root)
         (mementum-root root)
         (headless-was-enabled (bound-and-true-p gptel-auto-workflow--headless)))
    (message "[%s] Starting weekly job for project: %s" prefix root)
    (unless (featurep feature-name)
      (load-file (expand-file-name file-path root)))
    (unless headless-was-enabled
      (when (fboundp 'gptel-auto-workflow--enable-headless-suppression)
        (gptel-auto-workflow--enable-headless-suppression)))
    (unwind-protect
        (let ((gptel-auto-workflow--current-project root)
              (gptel-auto-workflow--project-root-override root)
              (gptel-auto-workflow--run-project-root root))
          (condition-case err
              (progn
                (funcall job-fn)
                (message "[%s] ✓ Completed: %s" prefix root)
                t)
            (error
             (message "[%s] ✗ Failed: %s - %s" prefix root err)
             nil)))
      (unless headless-was-enabled
        (when (fboundp 'gptel-auto-workflow--disable-headless-suppression)
          (gptel-auto-workflow--disable-headless-suppression)))
      (setq gptel-auto-workflow--current-project nil))))

(defun gptel-auto-workflow--run-all-weekly-jobs (prefix per-project-fn)
  "Run a weekly job for all projects using PREFIX and PER-PROJECT-FN.
PER-PROJECT-FN should accept a project root and return t/nil for success."
  (message "[%s] Running weekly job for %d projects..."
           prefix (length gptel-auto-workflow-projects))
  (let ((results nil))
    (dolist (project-root gptel-auto-workflow-projects)
      (message "[%s] Processing project: %s" prefix project-root)
      (condition-case err
          (if (funcall per-project-fn project-root)
              (push (cons project-root 'success) results)
            (push (cons project-root 'error) results))
        (error
         (push (cons project-root (format "error: %s" err)) results)
         (message "[%s] ✗ Failed: %s - %s" prefix project-root err))))
    (message "[%s] All projects processed: %s"
             prefix
             (mapconcat (lambda (r) (format "%s:%s" (car r) (cdr r)))
                        results ", "))
    results))

;;; Mementum Multi-Project Support

(defun gptel-auto-workflow-run-mementum-for-project (project-root)
  "Run mementum weekly job for specific PROJECT-ROOT."
  (interactive "DProject root: ")
  (gptel-auto-workflow--run-weekly-job-for-project
   project-root "mementum" 'gptel-tools-agent
   "lisp/modules/gptel-tools-agent.el"
   #'gptel-mementum-weekly-job))

(defun gptel-auto-workflow-run-all-mementum ()
  "Run mementum weekly job for all configured projects."
  (interactive)
  (gptel-auto-workflow--run-all-weekly-jobs
   "mementum" #'gptel-auto-workflow-run-mementum-for-project))

(defun gptel-auto-workflow-queue-all-mementum ()
  "Queue `gptel-auto-workflow-run-all-mementum' and return immediately."
  (interactive)
  (gptel-auto-workflow--queue-cron-job
   "mementum"
   #'gptel-auto-workflow-run-all-mementum))

;;; Instincts (Benchmark) Multi-Project Support

(defun gptel-auto-workflow-run-instincts-for-project (project-root)
  "Run instincts weekly job for specific PROJECT-ROOT."
  (interactive "DProject root: ")
  (gptel-auto-workflow--run-weekly-job-for-project
   project-root "instincts" 'gptel-benchmark-instincts
   "lisp/modules/gptel-benchmark-instincts.el"
   #'gptel-benchmark-instincts-weekly-job))

(defun gptel-auto-workflow-run-all-instincts ()
  "Run instincts weekly job for all configured projects."
  (interactive)
  (gptel-auto-workflow--run-all-weekly-jobs
   "instincts" #'gptel-auto-workflow-run-instincts-for-project))

(defun gptel-auto-workflow-queue-all-instincts ()
  "Queue `gptel-auto-workflow-run-all-instincts' and return immediately."
  (interactive)
  (gptel-auto-workflow--queue-cron-job
   "instincts"
   #'gptel-auto-workflow-run-all-instincts))

(provide 'gptel-auto-workflow-projects)
;;; gptel-auto-workflow-projects.el ends here
