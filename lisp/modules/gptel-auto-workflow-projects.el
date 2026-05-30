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

;; HARDEN: Prevent void-variable errors when native-comp closure captures
;; fail to resolve lexically-bound parameters on arm64 Emacs 30.1.
;; Intentionally unprefixed — these names match closure variable names
;; that native-comp expects to find dynamically bound.
(defvar gptel-auto-workflow--async nil)
(defvar gptel-auto-workflow--process nil)

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
(declare-function gptel-auto-workflow--run-autotts-evolution "gptel-auto-workflow-research-benchmark")
(declare-function gptel-auto-workflow--reorder-fallbacks-by-ontology "gptel-auto-workflow-ontology-router")
(declare-function gptel-auto-workflow--run-research-champion-league "gptel-auto-workflow-research-integration")
(declare-function gptel-auto-workflow--run-strategy-evolution "gptel-auto-workflow-strategic")

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
(defvar gptel-auto-workflow--defer-subagent-env-persistence nil)

(defvar mementum-root nil
  "Root directory for mementum. Set per-project.")

(defvar gptel-auto-workflow--project-root-override)
(defvar gptel-auto-workflow--research-findings-cache
  (make-hash-table :test 'equal)
  "Hash table caching research findings per project root.")

(defvar gptel-auto-workflow--worktree-buffers (make-hash-table :test 'equal)
  "Hash table of gptel-agent buffers per worktree.
Key: worktree directory, Value: buffer.
Each worktree gets its own isolated buffer for subagent overlays.")

(defvar gptel-auto-workflow--normalized-projects-cache nil
  "Cached normalized projects list with timestamp for invalidation.")
(defvar gptel-auto-workflow--normalized-projects-hash nil
  "Hash table mapping current-dir prefixes to project roots for O(1) lookup.")

(defun gptel-auto-workflow--ensure-buffer-tables ()
  "Ensure shared project/worktree buffer tables are initialized."
  (unless (hash-table-p gptel-auto-workflow--project-buffers)
    (setq gptel-auto-workflow--project-buffers (make-hash-table :test 'equal)))
  (unless (hash-table-p gptel-auto-workflow--worktree-buffers)
    (setq gptel-auto-workflow--worktree-buffers (make-hash-table :test 'equal)))
  (unless (hash-table-p gptel-auto-workflow--research-findings-cache)
    (setq gptel-auto-workflow--research-findings-cache (make-hash-table :test 'equal)))
  (unless (hash-table-p gptel-auto-workflow--normalized-projects-hash)
    (setq gptel-auto-workflow--normalized-projects-hash (make-hash-table :test 'equal))))

(defun gptel-auto-workflow--normalized-projects ()
  "Return configured project roots as unique expanded directory names.
Results are cached until `gptel-auto-workflow-projects' changes."
  (gptel-auto-workflow--ensure-buffer-tables)
  (let ((cached (and (consp gptel-auto-workflow--normalized-projects-cache)
                     (eq (car gptel-auto-workflow--normalized-projects-cache)
                         gptel-auto-workflow-projects)
                     (cdr gptel-auto-workflow--normalized-projects-cache))))
    (or cached
        (let ((normalized (delq nil
                                (delete-dups
                                 (mapcar (lambda (project-root)
                                           (and (stringp project-root)
                                                (> (length project-root) 0)
                                                (file-name-as-directory (expand-file-name project-root))))
                                         gptel-auto-workflow-projects)))))
          (setq gptel-auto-workflow--normalized-projects-cache
                (cons gptel-auto-workflow-projects normalized))
          normalized))))

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
  (let ((updated-info (cond
                       ((proper-list-p info) (copy-sequence info))
                       ((null info) '())
                       (t (error "gptel-auto-workflow--routed-fsm-info: INFO must be a proper list, got: %S" info)))))
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
         (worktree-name (and root (file-name-nondirectory (directory-file-name root))))
         (buf-name (and root worktree-name
                        (format "*gptel-agent:%s@%s*"
                                worktree-name
                                (substring (md5 root) 0 8))))
         (existing (and root (gethash root gptel-auto-workflow--worktree-buffers))))
    ;; Guard against nil root from failed normalization
    (unless root (error "WORKTREE-DIR could not be normalized to a valid directory path: %s" worktree-dir))
    ;; Check if existing buffer is still live
    (if (and existing (buffer-live-p existing))
        (progn
          (with-current-buffer existing
            (setq-local default-directory root)
            ;; Ensure dir-locals are propagated even for reused buffers
                          (dolist (sym '(gptel-auto-workflow-targets
                                          gptel-auto-experiment-max-per-target
                                          gptel-auto-experiment-time-budget
                                          gptel-auto-experiment-no-improvement-threshold
                                          gptel-model))
                             (when (local-variable-p sym)
                               (setq-default sym (buffer-local-value sym (current-buffer))))))
          (puthash root existing gptel-auto-workflow--worktree-buffers)
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
          ;; Propagate dir-local workflow config to global scope
          ;; so subagent buffers inherit project settings
           (dolist (sym '(gptel-auto-workflow-targets
                          gptel-auto-experiment-max-per-target
                          gptel-auto-experiment-time-budget
                          gptel-auto-experiment-no-improvement-threshold
                          gptel-model))
             (when (local-variable-p sym)
               (setq-default sym (buffer-local-value sym (current-buffer)))))
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
  (unless (and (stringp project-root)
               (> (length project-root) 0))
    (error "PROJECT-ROOT must be a non-empty string, got: %S" project-root))
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
      (gptel-auto-workflow--ensure-buffer-tables)
      (remhash root gptel-auto-workflow--project-buffers)
      (remhash root gptel-auto-workflow--worktree-buffers)
      (remhash root gptel-auto-workflow--research-findings-cache)
      (setq gptel-auto-workflow--normalized-projects-cache nil)
      (clrhash gptel-auto-workflow--normalized-projects-hash))
    (message "Added project: %s" root)))

(defun gptel-auto-workflow-remove-project (project-root)
  "Remove PROJECT-ROOT from auto-workflow projects list."
  (interactive
   (let ((projects (gptel-auto-workflow--normalized-projects)))
     (unless projects
       (user-error "No projects configured to remove"))
     (list (completing-read "Remove project: " projects))))
  (let* ((root (file-name-as-directory (expand-file-name project-root)))
         (was-present (member root gptel-auto-workflow-projects)))
    (setq gptel-auto-workflow-projects
          (delete root gptel-auto-workflow-projects))
    (when was-present
      (customize-save-variable 'gptel-auto-workflow-projects
                               gptel-auto-workflow-projects)
      (gptel-auto-workflow--ensure-buffer-tables)
      (remhash root gptel-auto-workflow--project-buffers)
      (remhash root gptel-auto-workflow--worktree-buffers)
      (remhash root gptel-auto-workflow--research-findings-cache)
      (setq gptel-auto-workflow--normalized-projects-cache nil)
      (clrhash gptel-auto-workflow--normalized-projects-hash))
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
  ;; Prime gpg-agent cache by decrypting authinfo once. Subsequent gpg
  ;; --batch calls in my/gptel-api-key reuse the cached passphrase.
  (ignore-errors
    (call-process "gpg" nil nil nil "--batch" "--quiet" "--decrypt"
                  (expand-file-name "~/.authinfo.gpg")))
  ;; Ensure Moonshot is excluded from the fallback chain — its content_filter
  ;; blocks code generation, and the onto-router keeps preferring it because it
  ;; returns error messages (looking more responsive than silently-failing peers).
  ;; Override the static fallback with DeepSeek + MiniMax only.
  (when (boundp 'gptel-auto-workflow-executor-rate-limit-fallbacks)
    (setq gptel-auto-workflow-executor-rate-limit-fallbacks
          '(("DeepSeek" . "deepseek-v4-flash")
            ("MiniMax" . "minimax-m2.7-highspeed"))))
  (when (boundp 'gptel-auto-workflow-headless-subagent-fallbacks)
    (setq gptel-auto-workflow-headless-subagent-fallbacks
          '(("DeepSeek" . "deepseek-v4-flash")
            ("MiniMax" . "minimax-m2.7-highspeed"))))
  ;; Ensure gptel-agent-dirs includes our custom agent directory so
  ;; --update-agents registers all agent types (grader, analyzer, etc.).
  (let ((agents-dir (expand-file-name "assistant/agents"
                                      (or (bound-and-true-p minimal-emacs-user-directory)
                                          user-emacs-directory))))
    (when (and (file-directory-p agents-dir)
               (boundp 'gptel-agent-dirs))
      (cl-pushnew agents-dir gptel-agent-dirs :test #'string=)))
  (ignore-errors (gptel-agent--update-agents))
  (gptel-auto-workflow--ensure-buffer-tables)
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
                           (setq-local enable-local-variables t)
                           (hack-dir-local-variables-non-file-buffer)
                           ;; Re-propagate dir-local after hack so the global
                          ;; value is used by cron-safe (which checks
                          ;; gptel-auto-workflow-targets in this buffer).
                          (dolist (sym '(gptel-auto-workflow-targets
                                         gptel-auto-experiment-max-per-target
                                         gptel-auto-experiment-time-budget
                                         gptel-auto-experiment-no-improvement-threshold
                                         gptel-model))
                            (when (local-variable-p sym)
                              (set sym (buffer-local-value sym (current-buffer)))))
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
               (not (bound-and-true-p gptel-auto-workflow--running)))
      (cond
       ((member phase (list label (format "%s-queued" label) "selecting" "running"))
        (setq gptel-auto-workflow--stats
              (plist-put gptel-auto-workflow--stats :phase "complete")))
       ((not (member phase '("complete" "quota-exhausted" "error" "idle")))
        (setq gptel-auto-workflow--stats
              (plist-put gptel-auto-workflow--stats :phase "idle"))))))
  (when (fboundp 'gptel-auto-workflow--persist-status)
    (gptel-auto-workflow--persist-status)))

(defun gptel-auto-workflow--queue-cron-job (label fn &optional use-async &rest options)
  "Queue FN for LABEL and return immediately.
This keeps `emacsclient --eval' callers from monopolizing the daemon.
When USE-ASYNC is non-nil, FN must accept a completion callback
and invoke it when the queued job actually finishes."
  (setq use-async (or use-async (plist-get options :async)))
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
                             (if use-async
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
   t))

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
         (stringp gptel-auto-workflow--project-root-override)
         (> (length gptel-auto-workflow--project-root-override) 0))
    (cons gptel-auto-workflow--project-root-override
          (gptel-auto-workflow--get-project-buffer gptel-auto-workflow--project-root-override)))
   ;; Case 3: Check if current directory is a configured project
   ((and (boundp 'gptel-auto-workflow-projects)
         (proper-list-p gptel-auto-workflow-projects)
         gptel-auto-workflow-projects)
    (let ((current-dir (and (stringp default-directory)
                            (file-name-as-directory (expand-file-name default-directory))))
          proj)
      (when current-dir
        (setq proj (cl-loop for p in (gptel-auto-workflow--normalized-projects)
                            when (and (stringp p)
                                      (string-prefix-p p current-dir))
                            return p)))
      (when (and proj (stringp proj))
        (cons proj (gptel-auto-workflow--get-project-buffer proj)))))
   ;; Case 4: Try to detect project from default-directory
   (t
    (let* ((default-dir (and (boundp 'default-directory)
                             (stringp default-directory)
                             (directory-file-name default-directory)))
           (proj (or (and default-dir
                          (condition-case nil
                              (gptel-auto-workflow--project-root)
                            (error default-dir)))
                     default-dir
                     gptel-auto-workflow-worktree-base
                     (expand-file-name "~/.emacs.d")))
           (expanded-proj (and (stringp proj) (> (length proj) 0)
                               (expand-file-name proj))))
      (when expanded-proj
        (cons expanded-proj (gptel-auto-workflow--get-project-buffer expanded-proj)))))))

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
                    (when (and (not gptel-auto-workflow--defer-subagent-env-persistence)
                               (fboundp 'gptel-auto-workflow--persist-subagent-process-environment))
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
                           (parent-fsm
                            (and (boundp 'gptel--fsm-last)
                                 (if (fboundp 'my/gptel--coerce-fsm)
                                     (my/gptel--coerce-fsm gptel--fsm-last)
                                   gptel--fsm-last)))
                           (orig-gptel-fsm-info (symbol-function 'gptel-fsm-info))
                           (info (or (and parent-fsm
                                          (ignore-errors
                                            (gptel-fsm-info parent-fsm)))
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
                                   (let* ((active-fsm
                                           (or fsm
                                               (and (boundp 'gptel--fsm-last)
                                                    gptel--fsm-last)))
                                          (coerced-fsm
                                           (if (fboundp 'my/gptel--coerce-fsm)
                                               (my/gptel--coerce-fsm active-fsm)
                                             active-fsm)))
                                     (cond
                                      ((and coerced-fsm parent-fsm
                                            (eq coerced-fsm parent-fsm))
                                       modified-info)
                                      (coerced-fsm
                                       (funcall orig-gptel-fsm-info coerced-fsm))
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
      (ignore))
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
         (valid-info (and (proper-list-p info) info))
         (target-buf (and valid-info (plist-get valid-info :buffer))))
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

(defun gptel-auto-workflow--iterate-project-buffers (fn)
  "Iterate FN over each live buffer in `gptel-auto-workflow--project-buffers'.
FN is called with (ROOT BUFFER) for each entry where BUFFER is live.
ASSUMPTION: Caller ensures buffer tables are initialized via
`gptel-auto-workflow--ensure-buffer-tables'."
  (when (hash-table-p gptel-auto-workflow--project-buffers)
    (maphash (lambda (root buf)
               (when (buffer-live-p buf)
                 (funcall fn root buf)))
             gptel-auto-workflow--project-buffers)))

(defun gptel-auto-workflow-clear-executor-overlays (&optional project-root)
  "Clear all persistent executor overlays for PROJECT-ROOT or all projects.
Without PROJECT-ROOT, clears overlays for all projects."
  (interactive)
  (gptel-auto-workflow--ensure-buffer-tables)
  (if project-root
      (when-let* ((buf (gethash (expand-file-name project-root)
                                gptel-auto-workflow--project-buffers)))
        (with-current-buffer buf
          (dolist (ov (overlays-in (point-min) (point-max)))
            (when (overlay-get ov 'gptel-agent--task-type)
              (delete-overlay ov))))
        (message "[auto-workflow] Cleared executor overlays for %s" project-root))
    (gptel-auto-workflow--iterate-project-buffers
     (lambda (_ buf)
       (with-current-buffer buf
         (dolist (ov (overlays-in (point-min) (point-max)))
           (when (overlay-get ov 'gptel-agent--task-type)
             (delete-overlay ov))))))
    (message "[auto-workflow] Cleared all executor overlays")))

(defun gptel-auto-workflow-list-project-buffers ()
  "List all project gptel-agent buffers."
  (interactive)
  (gptel-auto-workflow--ensure-buffer-tables)
  (let ((buffers nil))
    (gptel-auto-workflow--iterate-project-buffers
     (lambda (root buf)
       (let ((mode (with-current-buffer buf
                     (format-mode-line mode-name))))
         (push (format "%s -> %s [%s]"
                       root
                       (buffer-name buf)
                       (or mode "unknown"))
               buffers))))
    (if buffers
        (let ((sorted (sort buffers #'string<)))
          (message "Project buffers (%d):\n%s"
                   (length sorted)
                   (string-join sorted "\n")))
      (message "No project buffers created yet"))))

;;; Researcher Multi-Project Support

(defun gptel-auto-workflow-run-research-for-project (project-root &optional completion-callback)
  "Run researcher for specific PROJECT-ROOT.
Loads .dir-locals.el from project and runs researcher in that context.
When COMPLETION-CALLBACK is non-nil, call it after research completes."
  (interactive "DProject root: ")
  (unless (and (stringp project-root)
               (> (length project-root) 0))
    (error "PROJECT-ROOT must be a non-empty string, got: %S" project-root))
  (let* ((root (expand-file-name project-root))
         (project-buf (gptel-auto-workflow--get-project-buffer root)))
    (message "[research] Starting for project: %s" root)
    ;; Ensure bottleneck-report + other critical functions are available.
    ;; The feature may be provided but definitions missed due to load ordering.
    (unless (and (fboundp 'gptel-auto-workflow--current-bottleneck-report)
                 (fboundp 'gptel-auto-workflow--research-champion-report))
      (load-file (expand-file-name "lisp/modules/gptel-auto-workflow-strategic.el" root)))
    ;; Set current project context for subagents
    (setq gptel-auto-workflow--current-project root)
    (with-current-buffer project-buf
      ;; Ensure .dir-locals.el is loaded for this project
      (hack-dir-local-variables-non-file-buffer)
      (gptel-auto-workflow-run-research
       (lambda (&rest args)
         (setq gptel-auto-workflow--current-project nil)
         (when completion-callback
           (apply completion-callback args)))))))

(defun gptel-auto-workflow-run-all-research (&optional completion-callback)
  "Run researcher for all configured projects.
To be called from cron - visits each project directory (loading .dir-locals.el),
then runs researcher for that project.
When COMPLETION-CALLBACK is non-nil, call it after all projects finish."
  (interactive)
  ;; Ensure agent types are registered (researcher, executor, etc.)
  (let ((agents-dir (expand-file-name "assistant/agents"
                                      (or (bound-and-true-p minimal-emacs-user-directory)
                                          user-emacs-directory))))
    (when (and (file-directory-p agents-dir)
               (boundp 'gptel-agent-dirs))
      (cl-pushnew agents-dir gptel-agent-dirs :test #'string=)))
  (ignore-errors (gptel-agent--update-agents))
  ;; Load full workflow stack when running in researcher daemon context
  (condition-case err
      (progn
        (when (fboundp 'gptel-auto-workflow--reload-live-support)
          (gptel-auto-workflow--reload-live-support))
        ;; Prevent gptel-mode hooks from defaulting to MiniMax and ensure
        ;; headless-provider-override-active-p returns t so the fallback
        ;; chain (DeepSeek etc.) is consulted for research subagent calls.
        (setq gptel-auto-workflow-persistent-headless t)
        ;; Clear stale rate-limited backends from previous research attempts so
        ;; the fallback chain starts fresh with Moonshot.
        (when (fboundp 'gptel-auto-workflow--clear-rate-limited-backends)
          (gptel-auto-workflow--clear-rate-limited-backends)))
    (error
     (let ((bt (with-output-to-string (backtrace))))
       (with-temp-file "/tmp/research-init-backtrace.txt"
         (insert (format "Error: %S\n\nBacktrace:\n%s\n" err bt)))
       (message "[research] Init error: %S — backtrace written to /tmp/research-init-backtrace.txt" err))))
  (let ((projects (gptel-auto-workflow--normalized-projects)))
    (message "[research] Running for %d projects..." (length projects))
    (let ((results nil)
          (remaining projects))
      (cl-labels
          ((finish ()
             (let ((final-results (nreverse results)))
               (setq gptel-auto-workflow--current-project nil)
               (message "[research] All projects processed: %s"
                        (mapconcat (lambda (r) (format "%s:%s" (car r) (cdr r)))
                                   final-results ", "))
               (when completion-callback
                 (funcall completion-callback final-results))
               final-results))
           (run-next ()
             (if (null remaining)
                 (finish)
               (let* ((project-root (car remaining))
                      (default-directory project-root)
                      (project-buf (gptel-auto-workflow--get-project-buffer project-root)))
                 (setq remaining (cdr remaining))
                 (message "[research] Processing project: %s" project-root)
                 (condition-case err
                     (progn
                       ;; Set current project context for subagents.
                       (setq gptel-auto-workflow--current-project project-root)
                       (with-current-buffer project-buf
                         (hack-dir-local-variables-non-file-buffer)
                         (gptel-auto-workflow-run-research
                          (lambda (&rest _args)
                            (push (cons project-root 'success) results)
                            (message "[research] ✓ Completed: %s" project-root)
                            (setq gptel-auto-workflow--current-project nil)
                            (run-next)))))
                   (error
                    (let ((err-msg (format "%s" err))
                          (bt (with-output-to-string (backtrace))))
                      (when (string-match "void-variable total" err-msg)
                        (message "[research] DEBUG void-variable total backtrace:")
                        (message "%s" bt)
                        (with-temp-file (expand-file-name "var/tmp/research-total-backtrace.txt"
                                                          (gptel-auto-workflow--worktree-base-root))
                          (insert bt))))
                    (push (cons project-root (format "error: %s" err)) results)
                    (message "[research] ✗ Failed: %s - %s" project-root err)
                    (setq gptel-auto-workflow--current-project nil)
                    (run-next)))))))
        (run-next)))))

(defun gptel-auto-workflow--shutdown-researcher-daemon-after-job (&rest _args)
  "Mark researcher daemon as complete and keep it alive.
The researcher daemon stays running so the pipeline can detect its
phase as 'complete' or 'idle'. Previously shut down via kill-emacs
which caused the pipeline to misdiagnose a crash."
  (when (equal (or (daemonp) "") "ov5-researcher")
    (message "[research] Research job complete — daemon staying alive")
    ;; Mark phase as complete so pipeline detects it
    (when (boundp 'gptel-auto-workflow--stats)
      (setq gptel-auto-workflow--stats
            (plist-put gptel-auto-workflow--stats :phase "complete")))))

(defun gptel-auto-workflow--research-self-evolve ()
  "Run self-evolution systems after research findings are saved.
Triggers AutoTTS controller evolution, ontology backend reordering,
AutoGo champion league, and meta-harness strategy evolution.
Each system is guarded by fboundp and internal data-sufficiency checks
so calling this with no fresh data is a safe no-op."
  (message "[research] Starting self-evolution after research...")
  (let ((root (file-name-as-directory
               (expand-file-name
                (or (and (fboundp 'gptel-auto-workflow--default-dir)
                         (gptel-auto-workflow--default-dir))
                    default-directory)))))
    ;; Ensure evolution modules are loaded.  The research daemon bootstrap
    ;; may not load these modules unless the evolution cycle has already run.
    (dolist (mod '("gptel-auto-workflow-ontology-router.el"
                   "gptel-auto-workflow-research-integration.el"
                   "gptel-auto-workflow-evolution.el"))
      (let ((path (expand-file-name (concat "lisp/modules/" mod) root)))
        (when (file-readable-p path)
          (condition-case nil
              (load-file path)
            (error (message "[research] Could not load %s for self-evolution" mod))))))
    ;; 0b. Load git-tracked backend preference (shared across machines).
    (when (fboundp 'gptel-auto-workflow--ensure-backend-preference-loaded)
      (condition-case nil
          (gptel-auto-workflow--ensure-backend-preference-loaded)
        (error nil)))
    ;; 1. AutoTTS: evolve multi-turn controller from fresh traces.
    ;;    Internally gated: skips when no traces or convergence detected.
    (when (fboundp 'gptel-auto-workflow--run-autotts-evolution)
      (condition-case err
          (progn
            (message "[research] AutoTTS: evolving controller from traces...")
            (gptel-auto-workflow--run-autotts-evolution)
            (message "[research] AutoTTS: controller evolution complete"))
        (error
         (message "[research] AutoTTS evolution skipped: %s"
                  (error-message-string err)))))
    ;; 2. Ontology: reorder backend fallbacks based on performance data.
    ;;    Uses experiment keep-rates; safe to call even with empty history.
    (when (fboundp 'gptel-auto-workflow--reorder-fallbacks-by-ontology)
      (condition-case err
          (progn
            (message "[research] Ontology: reordering backend fallbacks...")
            (gptel-auto-workflow--reorder-fallbacks-by-ontology)
            (message "[research] Ontology: backend reorder complete"))
        (error
         (message "[research] Ontology reorder skipped: %s"
                  (error-message-string err)))))
    ;; 2b. Auto-evolve per-axis backend preference from historical keep-rates.
    (when (fboundp 'gptel-auto-workflow--evolve-backend-preference)
      (condition-case err
          (gptel-auto-workflow--evolve-backend-preference)
        (error
         (message "[preference] Evolution skipped: %s"
                  (error-message-string err)))))
    ;; 3. AutoGo: champion league for proposed research strategies.
    ;;    Internally gated: skips when no proposed strategies pending.
    (when (fboundp 'gptel-auto-workflow--run-research-champion-league)
      (condition-case err
          (progn
            (message "[research] AutoGo: running champion league...")
            (gptel-auto-workflow--run-research-champion-league)
            (message "[research] AutoGo: champion league complete"))
        (error
         (message "[research] AutoGo champion league skipped: %s"
                  (error-message-string err)))))
    ;; 4. Meta-harness: evolve research strategies.
    ;;    Internally delegates to AutoTTS evolution so shares its gates.
    (when (fboundp 'gptel-auto-workflow--run-strategy-evolution)
      (condition-case err
          (progn
            (message "[research] Meta-harness: evolving strategies...")
            (gptel-auto-workflow--run-strategy-evolution)
            (message "[research] Meta-harness: strategy evolution complete"))
        (error
         (message "[research] Meta-harness evolution skipped: %s"
                  (error-message-string err)))))
    (message "[research] Self-evolution complete")))

(defun gptel-auto-workflow-queue-all-research (&optional shutdown-after-completion)
  "Queue `gptel-auto-workflow-run-all-research' and return immediately."
  (interactive)
  (gptel-auto-workflow--queue-cron-job
   "research"
   (lambda (completion-callback)
     (gptel-auto-workflow-run-all-research
      (lambda (&rest args)
        (gptel-auto-workflow--research-self-evolve)
        (funcall completion-callback)
        (when shutdown-after-completion
          (apply #'gptel-auto-workflow--shutdown-researcher-daemon-after-job args)))))
   t))

;;; Research Cache Management

(defvar gptel-auto-workflow--research-status-cache nil
  "Cache for research status with timestamp for TTL control.")

(defun gptel-auto-workflow-clear-research-cache (&optional project-root)
  "Clear research findings cache for PROJECT-ROOT or all projects.
Without PROJECT-ROOT, clears cache for all projects."
  (interactive)
  (setq gptel-auto-workflow--research-status-cache nil)
  (gptel-auto-workflow--ensure-buffer-tables)
  (if project-root
      (let ((root (expand-file-name project-root)))
        (remhash root gptel-auto-workflow--research-findings-cache)
        (message "[research] Cleared findings cache for %s" root))
    (when (hash-table-p gptel-auto-workflow--research-findings-cache)
      (clrhash gptel-auto-workflow--research-findings-cache))
    (message "[research] Cleared findings cache for all projects")))

(defvar gptel-auto-workflow--research-status-ttl-seconds 5
  "Time-to-live in seconds for the research status cache.")

(defun gptel-auto-workflow--research-cache-get (project-root)
  "Return cached research findings for PROJECT-ROOT.
Returns nil if PROJECT-ROOT is nil or not found in cache."
  (when (and project-root
             (stringp project-root)
             (> (length project-root) 0))
    (or (gethash project-root gptel-auto-workflow--research-findings-cache)
        (gethash (directory-file-name project-root)
                 gptel-auto-workflow--research-findings-cache)
        (gethash (file-name-as-directory project-root)
                 gptel-auto-workflow--research-findings-cache))))

(defun gptel-auto-workflow-research-status-all ()
  "Show research status for all configured projects."
  (interactive)
  (let* ((now (float-time))
         (cache gptel-auto-workflow--research-status-cache)
         (cached-at (and (consp cache)
                         (numberp (car cache))
                         (car cache)))
         (cached-result (and (consp cache)
                             (stringp (cdr cache))
                             (cdr cache))))
    (if (and cached-at
             cached-result
             (< (- now cached-at)
                gptel-auto-workflow--research-status-ttl-seconds))
        (message "Research cache status:\n%s"
                 cached-result)
      (let ((status-lines '()))
        (dolist (project-root (gptel-auto-workflow--normalized-projects))
          ;; ASSUMPTION: project-root must be a non-empty string for file operations
          (when (and (stringp project-root) (> (length project-root) 0))
            (let* ((findings (gptel-auto-workflow--research-cache-get project-root))
                   (cache-file (expand-file-name "var/tmp/research-findings.md" project-root))
                   (attrs (file-attributes cache-file))
                   (file-size (or (nth 7 attrs) 0)))
              (push (format "  %s:\n    In-memory: %d chars\n    File: %s (%d bytes)"
                            project-root
                            (length (or findings ""))
                            (if attrs "exists" "none")
                            file-size)
                    status-lines))))
        (let ((result (string-join (nreverse status-lines) "\n")))
          (setq gptel-auto-workflow--research-status-cache
                (cons now result))
          (message "Research cache status:\n%s" result))))))

;;; Weekly Job Runner (shared by mementum and instincts)

(defun gptel-auto-workflow--run-weekly-job-for-project
    (project-root prefix feature-name file-path job-fn)
  "Run a weekly job for PROJECT-ROOT.
Uses PREFIX, FEATURE-NAME, FILE-PATH, and JOB-FN.
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
  (when (or (null per-project-fn)
            (not (functionp per-project-fn)))
    (signal 'wrong-type-argument (list #'functionp per-project-fn)))
  (let* ((projects (gptel-auto-workflow--normalized-projects))
         (results nil)
         (log-prefix (if (stringp prefix) prefix "weekly")))
    (message "[%s] Running weekly job for %d projects..."
             log-prefix (length projects))
    (dolist (project-root projects)
      (message "[%s] Processing project: %s" log-prefix project-root)
      (condition-case err
          (if (funcall per-project-fn project-root)
              (push (cons (directory-file-name project-root) 'success) results)
            (push (cons (directory-file-name project-root) 'error) results))
        (error
         (push (cons (directory-file-name project-root) (format "error: %s" err)) results)
         (message "[%s] ✗ Failed: %s - %s" log-prefix project-root err))))
    (message "[%s] All projects processed: %s"
             log-prefix
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
   #'gptel-auto-workflow-run-all-mementum
   nil))

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
   #'gptel-auto-workflow-run-all-instincts
   nil))

(provide 'gptel-auto-workflow-projects)
;;; gptel-auto-workflow-projects.el ends here
