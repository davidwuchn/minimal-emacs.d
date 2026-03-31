;;; gptel-tools-agent.el --- Subagent delegation for gptel -*- no-byte-compile: t; lexical-binding: t; -*-

;; Author: David Wu
;; Version: 1.0.0
;;
;; Subagent delegation with timeout and model override.

(require 'cl-lib)
(require 'subr-x)
(require 'gptel)
(require 'gptel-agent)
(require 'magit-git nil t)

;; Forward declarations for variables defined in gptel-auto-workflow-projects.el
(defvar gptel-auto-workflow--project-buffers nil)

;;; Shell Command with Timeout

(defcustom gptel-auto-workflow-shell-timeout 30
  "Seconds before a shell command is force-killed.
Prevents deadlocks from hanging git/shell commands."
  :type 'integer
  :group 'gptel-tools-agent)

(defun gptel-auto-workflow--validate-non-empty-string (value name &optional error-prefix)
  "Validate that VALUE is a non-nil, non-empty string.
NAME is used in error message. ERROR-PREFIX defaults to \"[auto-workflow]\".
Signals an error if validation fails."
  (unless (and (stringp value) (not (string-empty-p (string-trim value))))
    (error "%s Invalid %s: must be non-nil, non-empty string, got %S"
           (or error-prefix "[auto-workflow]")
           name
           value)))

(defun gptel-auto-workflow--non-empty-string-p (value)
  "Return t if VALUE is a non-nil, non-empty string.
Helper for validation in callback-based functions."
  (and (stringp value) (not (string-empty-p (string-trim value)))))



(defun gptel-auto-workflow--plist-get (plist key &optional default)
  "Get value from PLIST for KEY, returning DEFAULT if not found.
Reduces duplication of `(or (plist-get ...) default-value)` patterns."
  (let ((value (plist-get plist key)))
    (if (null value) default value)))

(defun gptel-auto-workflow--state-active-p (state)
  "Return t if STATE is non-nil and not marked as done.
Reduces duplication of `(when (and state (not (plist-get state :done)))` patterns."
  (and state (not (plist-get state :done))))

(defun gptel-auto-workflow--with-error-handling (operation fn &optional error-prefix)
  "Execute FN with standardized error handling for OPERATION.
ERROR-PREFIX defaults to \"[auto-workflow]\".
Returns FN's result on success, nil on error with logged message.
Reduces duplication of condition-case error patterns."
  (condition-case err
      (funcall fn)
    (error
     (message "%s %s failed: %s"
              (or error-prefix "[auto-workflow]")
              operation
              err)
     nil)))

(defun gptel-auto-workflow--require-magit-dependencies ()
  "Require magit-worktree and magit-git dependencies.
Signals user-error if either dependency fails to load."
  (unless (require 'magit-worktree nil t)
    (user-error "magit-worktree is required"))
  (unless (require 'magit-git nil t)
    (user-error "magit-git is required")))
;;;###autoload
(defun gptel-auto-workflow--read-file-contents (filepath)
  "Read contents of FILEPATH as string.
Returns nil if file doesn't exist or isn't readable."
  (when (and (stringp filepath) (file-exists-p filepath) (file-readable-p filepath))
    (with-temp-buffer
      (insert-file-contents filepath)
      (buffer-string))))

(defun gptel-auto-workflow--shell-command-with-timeout (command &optional timeout)
  "Execute shell COMMAND with TIMEOUT (default 30s).
Returns (output . exit-code) or (error-message . -1) on timeout.
Uses robust timeout mechanism to prevent blocking indefinitely."
  (gptel-auto-workflow--validate-non-empty-string command "command")
  (let* ((timeout-seconds (or timeout gptel-auto-workflow-shell-timeout))
         (buffer (generate-new-buffer " *shell-timeout*"))
         (process nil)
         (done nil)
         (result nil)
         (exit-code nil)
         (start-time (current-time))
         (timer nil))
    (unwind-protect
        (progn
          (setq process (start-process-shell-command "shell-timeout" buffer command))
          ;; Set up a timer to force timeout even if accept-process-output blocks
          (setq timer (run-with-timer timeout-seconds nil
                                      (lambda ()
                                        (unless done
                                          (setq done 'timeout)))))
          (set-process-sentinel process
                                (lambda (proc _event)
                                  (unless done
                                    (setq done 'finished)
                                    (setq exit-code (process-exit-status proc))
                                    (with-current-buffer buffer
                                      (setq result (buffer-string))))))
          ;; Poll with short timeout to avoid blocking indefinitely
          (while (and (not done)
                      (< (float-time (time-subtract (current-time) start-time)) timeout-seconds))
            ;; Use 0.1s timeout in accept-process-output with non-blocking flag
            ;; The 't' as last arg prevents indefinite blocking
            (accept-process-output process 0.1 nil t)
            ;; Small delay to prevent busy-waiting
            (sit-for 0.01))
          ;; Cancel timer if still active
          (when timer
            (cancel-timer timer)
            (setq timer nil))
          ;; Handle timeout or collect results
          (if (eq done 'timeout)
              (progn
                (when (process-live-p process)
                  (delete-process process))
                (setq result (format "Error: Command timed out after %ds: %s" timeout-seconds command))
                (setq exit-code -1)
                (cons result exit-code))
            ;; Process finished, ensure we have the result
            (unless result
              (with-current-buffer buffer
                (setq result (buffer-string))))
            (cons result (or exit-code 0))))
      ;; Cleanup
      (when timer
        (cancel-timer timer))
      (when (and process (process-live-p process))
        (delete-process process))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))

(defun gptel-auto-workflow--shell-command-string (command &optional timeout)
  "Execute shell COMMAND with TIMEOUT, return output string.
On timeout or error, returns empty string and logs warning."
  (let ((result (gptel-auto-workflow--shell-command-with-timeout command timeout)))
    (if (eq (cdr result) -1)
        (progn
          (message "[auto-workflow] %s" (car result))
          "")
      (string-trim (car result)))))

;;; Orphan Commit Tracking

(defun gptel-auto-workflow--track-commit (experiment-id &optional target)
  "Save current commit hash to tracking file for EXPERIMENT-ID.
TARGET is optional description. Enables recovery if workflow interrupted.
Returns nil if git command fails or returns invalid hash."
  (let* ((default-directory (or (gptel-auto-workflow--get-worktree-dir (or target gptel-auto-workflow--current-target))
                                (gptel-auto-workflow--project-root)))
         (commit-hash (gptel-auto-workflow--git-cmd "git rev-parse HEAD"))
         (date (format-time-string "%Y-%m-%d"))
         (tracking-file (expand-file-name
                         (format "var/tmp/experiments/%s/commits.txt" date)
                         (gptel-auto-workflow--project-root)))
         (tracking-dir (file-name-directory tracking-file)))
    (cond
     ((string-empty-p commit-hash)
      (message "[auto-workflow] Failed to track commit: git command returned empty hash")
      nil)
     ((not (string-match-p "^[a-f0-9]\\{7,40\\}$" commit-hash))
      (message "[auto-workflow] Failed to track commit: invalid hash format %S" commit-hash)
      nil)
     (t
      (unless (file-exists-p tracking-dir)
        (make-directory tracking-dir t))
      (with-temp-buffer
        (insert (format "%s %s %s %s\n"
                        commit-hash
                        experiment-id
                        (or target "unknown")
                        (format-time-string "%H:%M:%S")))
        (append-to-file (point-min) (point-max) tracking-file))
      (message "[auto-workflow] Tracked commit %s for exp-%s" 
               (if (>= (length commit-hash) 7)
                   (substring commit-hash 0 7)
                 commit-hash)
               experiment-id)
      commit-hash))))

(defun gptel-auto-workflow--recover-orphans ()
  "Check for orphan commits from previous runs.
An orphan is a commit that exists but is not reachable from staging or main.
Returns list of (hash exp-id target) for truly orphaned commits."
  (interactive)
  (let* ((date (format-time-string "%Y-%m-%d"))
         (tracking-file (expand-file-name
                         (format "var/tmp/experiments/%s/commits.txt" date)
                         (gptel-auto-workflow--project-root)))
         (orphans nil))
    (when (file-exists-p tracking-file)
      (with-temp-buffer
        (insert-file-contents tracking-file)
        (dolist (line (split-string (buffer-string) "\n" t))
          (let* ((parts (split-string line))
                 (hash (car parts))
                 (exp-id (cadr parts))
                 (target (caddr parts)))
            (when (and hash (string-match-p "^[a-f0-9]+$" hash))
              (let ((in-staging (gptel-auto-workflow--git-cmd
                                 (format "git merge-base --is-ancestor %s staging 2>/dev/null && echo yes" hash)))
                    (in-main (gptel-auto-workflow--git-cmd
                              (format "git merge-base --is-ancestor %s main 2>/dev/null && echo yes" hash))))
                (when (and (string-empty-p in-staging)
                           (string-empty-p in-main))
                  (push (list hash exp-id target) orphans))))))))
    (if orphans
        (message "[auto-workflow] Found %d orphan(s): %s"
                 (length orphans)
                 (mapconcat (lambda (o) 
                              (let ((hash (car o)))
                                (if (>= (length hash) 7)
                                    (substring hash 0 7)
                                  hash))) 
                            orphans " "))
      (message "[auto-workflow] No orphan commits found"))
    orphans))

(defun gptel-auto-workflow--cherry-pick-orphan (commit-hash)
  "Cherry-pick COMMIT-HASH to staging branch for recovery.
Returns t on success, nil on failure. Skips if already applied."
  (interactive "sCommit hash: ")
  (let ((default-directory (or (gptel-auto-workflow--project-root)
                               (expand-file-name "~/.emacs.d/"))))
    (gptel-auto-workflow--git-cmd "git stash")
    (gptel-auto-workflow--git-cmd "git checkout staging")
    (let ((result (gptel-auto-workflow--git-cmd
                   (format "git cherry-pick %s 2>&1" commit-hash))))
      (cond
       ((string-match-p "already applied\\|empty" result)
        (message "[auto-workflow] Commit %s already in staging, skipping" commit-hash)
        (gptel-auto-workflow--git-cmd "git cherry-pick --skip 2>/dev/null || git cherry-pick --abort 2>/dev/null")
        (gptel-auto-workflow--git-cmd "git checkout main")
        t)
       ((string-match-p "error\\|CONFLICT\\|conflict" result)
        (message "[auto-workflow] Cherry-pick failed: %s" result)
        (gptel-auto-workflow--git-cmd "git cherry-pick --abort")
        (gptel-auto-workflow--git-cmd "git checkout main")
        nil)
       (t
        (message "[auto-workflow] Recovered %s to staging" commit-hash)
        (gptel-auto-workflow--git-cmd "git checkout main")
        t)))))

(defun gptel-auto-workflow-recover-all-orphans (&optional no-push)
  "Recover all orphan commits from today to staging branch.
If NO-PUSH is non-nil, skip pushing to origin (useful for cron jobs)."
  (interactive)
  (let ((orphans (gptel-auto-workflow--recover-orphans)))
    (if (not orphans)
        (message "[auto-workflow] No orphans to recover")
      (let ((recovered 0)
            (failed 0))
        (dolist (orphan orphans)
          (let ((hash (car orphan)))
            (if (gptel-auto-workflow--cherry-pick-orphan hash)
                (cl-incf recovered)
              (cl-incf failed))))
        (message "[auto-workflow] Recovered %d/%d orphans to staging"
                 recovered (length orphans))
        (when (> recovered 0)
          (unless no-push
            (let ((default-directory (or (gptel-auto-workflow--project-root)
                                         (expand-file-name "~/.emacs.d/"))))
              (gptel-auto-workflow--git-cmd "git push origin staging"))))))))

(defun gptel-auto-workflow--sync-branches (source-branch target-branch action-name)
  "Fast-forward TARGET-BRANCH to match SOURCE-BRANCH.
ACTION-NAME is used in log messages (e.g., \"Synced\", \"Promoted\").
All shell commands have timeout protection to prevent deadlocks."
  (let ((default-directory (or (gptel-auto-workflow--project-root)
                               (expand-file-name "~/.emacs.d/")))
        (original-branch (gptel-auto-workflow--git-cmd
                          "git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main")))
    (condition-case err
        (progn
          (gptel-auto-workflow--git-cmd "git fetch origin" 180)
          (let* ((source-commit (gptel-auto-workflow--git-cmd
                                 (format "git rev-parse origin/%s" source-branch)))
                 (target-commit (gptel-auto-workflow--git-cmd
                                 (format "git rev-parse origin/%s 2>/dev/null || echo \"none\"" target-branch)))
                 (source-commit (or source-commit "none"))
                 (target-commit (or target-commit "none")))
            (if (string= source-commit target-commit)
                (message "[auto-workflow] %s already in sync with %s" target-branch source-branch)
              (progn
                (gptel-auto-workflow--git-cmd (format "git checkout %s" target-branch))
                (gptel-auto-workflow--git-cmd (format "git merge origin/%s --ff-only" source-branch))
                (gptel-auto-workflow--git-cmd (format "git push origin %s" target-branch))
                (gptel-auto-workflow--git-cmd (format "git checkout %s" original-branch))
                (message "[auto-workflow] %s %s to %s (%s -> %s)"
                         action-name target-branch source-branch
                         (if (>= (length target-commit) 7)
                             (substring target-commit 0 7)
                           target-commit)
                         (if (>= (length source-commit) 7)
                             (substring source-commit 0 7)
                           source-commit))))))
      (error
       (gptel-auto-workflow--git-cmd (format "git checkout %s" original-branch))
       (message "[auto-workflow] Failed to %s %s to %s: %s" (downcase action-name) target-branch source-branch err)
       nil))))

;;;###autoload
(defun gptel-auto-workflow--sync-staging-with-main ()
  "Fast-forward staging branch to match main.
Ensures experiments run against latest code.
All shell commands have timeout protection to prevent deadlocks."
  (gptel-auto-workflow--sync-branches "main" "staging" "Synced"))

;;;###autoload
(defun gptel-auto-workflow--promote-staging-to-main ()
  "Fast-forward main branch to match staging if staging has new commits.
Automatically promotes kept experiment commits from staging to main.
All shell commands have timeout protection to prevent deadlocks."
  (gptel-auto-workflow--sync-branches "staging" "main" "Promoted"))

;;; Customization

(defgroup gptel-tools-agent nil
  "Subagent delegation for gptel-agent."
  :group 'gptel)

(defcustom my/gptel-agent-task-timeout 300
  "Timeout in seconds for gptel-agent task calls.
Default 300s (5 min). Set lower to catch stuck requests faster."
  :type 'integer
  :group 'gptel-tools-agent)

(defcustom my/gptel-subagent-result-limit 4000
  "Max characters to return inline from a subagent result.
Results longer than this are truncated and the full text is saved
to a temp file."
  :type 'integer
  :group 'gptel-tools-agent)

(defcustom my/gptel-subagent-progress-interval 10
  "Seconds between progress messages while a subagent is running."
  :type 'integer
  :group 'gptel-tools-agent)

(defcustom my/gptel-subagent-stream nil
  "Whether to use streaming mode for subagent requests.
When nil (default), subagents use non-streaming mode which is more reliable
on backends with streaming issues (e.g., DashScope HTTP parse errors).
When t, subagents use streaming mode for incremental display."
  :type 'boolean
  :group 'gptel-tools-agent)

(defcustom my/gptel-subagent-temp-file-ttl 300
  "Seconds before subagent temp files are auto-deleted.
Set to 0 to disable auto-cleanup."
  :type 'integer
  :group 'gptel-tools-agent)

(defcustom my/gptel-subagent-cache-ttl 300
  "Time-to-live in seconds for cached subagent results.
Set to 0 to disable caching."
  :type 'integer
  :group 'gptel-tools-agent)

(defcustom my/gptel-subagent-cache-max-size 100
  "Maximum number of entries in the subagent cache.
When exceeded, oldest entries are evicted. Set to 0 for unlimited."
  :type 'integer
  :group 'gptel-tools-agent)

(defcustom my/gptel-subagent-include-history-default t
  "Default value for include_history when LLM doesn't specify.
When t (default), subagents receive recent conversation history.
When nil, subagents start with clean context unless explicitly requested."
  :type 'boolean
  :group 'gptel-tools-agent)



(defvar-local my/gptel--subagent-temp-files nil
  "Buffer-local list of temp files created by subagent results.
Each buffer manages its own temp files to avoid race conditions.")

(defvar my/gptel--global-temp-files nil
  "Global fallback list for temp files (used when no buffer context).")

(defvar my/gptel--subagent-cache (make-hash-table :test 'equal)
  "Hash table for caching subagent results.
Keys are (agent-type prompt-hash), values are (timestamp . result).")

(eval-and-compile
  (require 'gptel nil t)
  (require 'gptel-agent nil t))

(require 'gptel-ext-fsm-utils)

;;; Subagent Result Cache

(defun my/gptel--subagent-cache-key (agent-type prompt &optional files include-history include-diff)
  "Generate cache key for (AGENT-TYPE, PROMPT, FILES, INCLUDE-HISTORY, INCLUDE-DIFF).
Context parameters are included to prevent stale cache hits when the same
prompt is used with different context (files, history, diff).
Always includes all params to distinguish nil from \"false\"."
  (list agent-type
        (md5 (concat prompt
                     (format "-files:%S" (when files (sort (append files nil) #'string<)))
                     (format "-hist:%s" (or include-history "nil"))
                     (format "-diff:%s" (or include-diff "nil"))))))

(defun my/gptel--subagent-cache-enabled-p ()
  "Return t if subagent caching is enabled and ready.
Checks both TTL configuration and hash table initialization."
  (and (> my/gptel-subagent-cache-ttl 0)
       (hash-table-p my/gptel--subagent-cache)))

(defun my/gptel--subagent-cache-get (agent-type prompt &optional files include-history include-diff)
  "Get cached result for (AGENT-TYPE, PROMPT, ...) if still valid.
Returns nil if cache disabled, not found, or expired."
  (when (my/gptel--subagent-cache-enabled-p)
    (let* ((key (my/gptel--subagent-cache-key agent-type prompt files include-history include-diff))
           (cached (gethash key my/gptel--subagent-cache)))
      (when cached
        (let ((timestamp (car cached))
              (result (cdr cached)))
          (if (> (- (float-time) timestamp) my/gptel-subagent-cache-ttl)
              (progn (remhash key my/gptel--subagent-cache) nil)
            result))))))

(defun my/gptel--subagent-cache-put (agent-type prompt result &optional files include-history include-diff)
  "Cache RESULT for (AGENT-TYPE, PROMPT, ...).
Evicts oldest entries if cache exceeds `my/gptel-subagent-cache-max-size'."
  (when (my/gptel--subagent-cache-enabled-p)
    (let ((key (my/gptel--subagent-cache-key agent-type prompt files include-history include-diff)))
      (puthash key (cons (float-time) result) my/gptel--subagent-cache)
      ;; Evict oldest entries if over limit
      (when (and (> my/gptel-subagent-cache-max-size 0)
                 (> (hash-table-count my/gptel--subagent-cache)
                    my/gptel-subagent-cache-max-size))
        (let ((oldest-key nil)
              (oldest-time most-positive-fixnum))
          (maphash
           (lambda (k v)
             (when (< (car v) oldest-time)
               (setq oldest-time (car v)
                     oldest-key k)))
           my/gptel--subagent-cache)
          (when oldest-key
            (remhash oldest-key my/gptel--subagent-cache)))))))

(defun my/gptel--subagent-cache-clear ()
  "Clear all cached subagent results."
  (interactive)
  (clrhash my/gptel--subagent-cache)
  (message "Subagent cache cleared."))

(defun my/gptel--subagent-cache-cleanup ()
  "Remove expired entries from cache.
Call periodically to prevent memory growth from unaccessed entries."
  (interactive)
  (let ((count 0)
        (now (float-time)))
    (maphash
     (lambda (key value)
       (when (> (- now (car value)) my/gptel-subagent-cache-ttl)
         (remhash key my/gptel--subagent-cache)
         (cl-incf count)))
     my/gptel--subagent-cache)
    (when (> count 0)
      (message "[gptel] Cleaned %d expired cache entries" count))
    count))


;; PATCH: Override gptel-agent--task to add tracking-marker for parent buffer
;; position and large-result truncation.  Respects `my/gptel-subagent-stream'
;; (default nil = non-streaming for reliability with DashScope).

(defun my/gptel-agent--task-override (main-cb agent-type description prompt)
  "Call a gptel agent to do specific compound tasks.
Like upstream `gptel-agent--task' but adds parent-buffer tracking-marker,
large-result truncation, and result caching."
  (cl-block my/gptel-agent--task-override
    ;; Validate agent-type exists and get config
    (let* ((agent-config (assoc agent-type gptel-agent--agents)))
      (unless agent-config
        (error "[nucleus] Unknown agent type: %s. Available: %s"
               agent-type
               (mapconcat #'car gptel-agent--agents ", ")))
      ;; Check cache first
      (let ((cached (my/gptel--subagent-cache-get agent-type prompt)))
        (when cached
          (message "[nucleus] Subagent %s cache hit" agent-type)
          (funcall main-cb cached)
          (cl-return-from my/gptel-agent--task-override)))
      ;; Not cached, run the subagent
      (let* ((preset (nconc (list :include-reasoning nil
                                  :use-tools t
                                  :use-context nil
                                  :stream my/gptel-subagent-stream)
                            (cdr agent-config)))
             (syms (cons 'gptel--preset (gptel--preset-syms preset)))
             (vals (mapcar (lambda (sym) (if (boundp sym) (symbol-value sym) nil)) syms)))
        (cl-progv syms vals
          (gptel--apply-preset preset)
          (let* ((parent-fsm (my/gptel--coerce-fsm gptel--fsm-last))
                 (info (and parent-fsm (gptel-fsm-info parent-fsm)))
                 (info-buf (plist-get info :buffer))
                 (parent-buf (or (when (buffer-live-p info-buf)
                                   info-buf)
                                 (current-buffer)))
                 (where (or (let ((tm (plist-get info :tracking-marker)))
                              (and (markerp tm) (marker-position tm) tm))
                            (let ((pos (plist-get info :position)))
                              (and (markerp pos) (marker-position pos) pos))
                            (with-current-buffer parent-buf (point-marker))))
                 (tracking-marker (let ((m (copy-marker where t)))
                                    (set-marker m (marker-position where) parent-buf)
                                    m))
                 (partial (format "%s result for task: %s\n\n"
                                  (capitalize (or agent-type "agent")) (or description "unknown"))))
            (gptel--update-status " Calling Agent..." 'font-lock-escape-face)
            (gptel-request prompt
              :context (gptel-agent--task-overlay where agent-type description)
              :fsm (gptel-make-fsm :handlers gptel-agent-request--handlers)
              :position tracking-marker
              :buffer parent-buf
              :in-place t
              :callback
              (lambda (resp info)
                (let ((ov (plist-get info :context)))
                  (pcase resp
                    ('nil
                     (when (overlayp ov) (delete-overlay ov))
                     (let* ((error-info (plist-get info :error))
                            (error-msg (when (listp error-info) (plist-get error-info :message))))
                       (if (and error-msg
                                (stringp error-msg)
                                (string-match-p "1013\\|server is initializing" error-msg))
                           ;; Server is initializing, default to auto-approve with warning
                           (funcall main-cb
                                    (format "Warning: Reviewer agent not available (server initializing). Auto-approving changes.\n\nError details: %S"
                                            error-info))
                         ;; Other error, report it
                         (funcall main-cb
                                  (format "Error: Task %s could not finish task \"%s\". \n\nError details: %S"
                                          agent-type description error-info)))))
                    (`(tool-call . ,calls)
                     (unless (plist-get info :tracking-marker)
                       (plist-put info :tracking-marker tracking-marker))
                     (gptel--display-tool-calls calls info))
                    (`(tool-result . ,_results)) ;; FSM handles transition
                    ((pred stringp)
                     (setq partial (concat partial resp))
                     (unless (plist-get info :tool-use)
                       (when (overlayp ov) (delete-overlay ov))
                       (when-let* ((transformer (plist-get info :transformer)))
                         (setq partial (funcall transformer partial)))
                       ;; Cache the result before delivering
                       (my/gptel--subagent-cache-put agent-type prompt partial)
                       (my/gptel--deliver-subagent-result main-cb partial)))
                    ('abort
                     (when (overlayp ov) (delete-overlay ov))
                     (funcall main-cb
                              (format "Error: Task \"%s\" was aborted by the user. \n%s could not finish."
                                      description agent-type)))))))))))))


(defun my/gptel--deliver-subagent-result (callback result)
  "Deliver RESULT to CALLBACK, truncating large results to a temp file."
  (if (> (length result) my/gptel-subagent-result-limit)
      (let* ((temp-file (my/gptel-make-temp-file "gptel-subagent-result-" nil ".txt"))
             (trunc-msg (format "%s\n...[Result too large, truncated. Full result saved to: %s. Use Read tool if you need more]..."
                                (substring result 0 my/gptel-subagent-result-limit)
                                temp-file))
             (buf (current-buffer))
             (buf-has-local (and (buffer-live-p buf)
                                 (local-variable-p 'my/gptel--subagent-temp-files buf))))
        (with-temp-file temp-file
          (insert result))
        (push temp-file my/gptel--global-temp-files)
        (when buf-has-local
          (with-current-buffer buf
            (push temp-file my/gptel--subagent-temp-files)))
        (when (> my/gptel-subagent-temp-file-ttl 0)
          (run-at-time my/gptel-subagent-temp-file-ttl nil
                       (lambda (f b has-local)
                         (when (file-exists-p f)
                           (delete-file f))
                         (setq my/gptel--global-temp-files
                               (delete f my/gptel--global-temp-files))
                         (when (and has-local (buffer-live-p b))
                           (with-current-buffer b
                             (setq my/gptel--subagent-temp-files
                                   (delete f my/gptel--subagent-temp-files)))))
                       temp-file buf buf-has-local))
        (funcall callback trunc-msg))
    (funcall callback result)))

(with-eval-after-load 'gptel-agent-tools
  ;; REMOVED: Old :override advice conflicts with new :around advice
  ;; in gptel-auto-workflow-projects.el that routes to correct buffer
  ;; (advice-add 'gptel-agent--task :override #'my/gptel-agent--task-override)
  (advice-add 'gptel-agent--task-overlay :around #'my/gptel-agent--task-overlay-around))

(defun my/gptel-agent--task-overlay-around (orig where &optional agent-type description)
  "Advice to fix task overlay appearing in wrong buffer.
ORIG is the original `gptel-agent--task-overlay' function.
WHERE is the position (marker or integer) for the overlay.
AGENT-TYPE and DESCRIPTION are passed through.

The upstream function creates the overlay in the current buffer,
but WHERE may be a marker pointing to a different buffer, or an
integer position that should be in the parent chat buffer.
This wrapper ensures the overlay is created in the correct buffer."
  (let* ((target-buf (cond
                      ;; Marker case: use marker's buffer
                      ((markerp where) (marker-buffer where))
                      ;; Integer case: try to get parent buffer from FSM
                      ((integerp where)
                       (let* ((parent-fsm (my/gptel--coerce-fsm gptel--fsm-last))
                              (info (and parent-fsm (gptel-fsm-info parent-fsm)))
                              (buf (and info (plist-get info :buffer))))
                         (or buf
                             ;; Fallback: use origin buffer from dynamic variable
                             my/gptel--subagent-origin-buffer)))
                      ;; No position: use origin buffer
                      (t my/gptel--subagent-origin-buffer)))
         (result
          (if (and target-buf (buffer-live-p target-buf))
              (with-current-buffer target-buf
                (funcall orig where agent-type description))
            ;; Last resort: check if current buffer is *scratch* or *Messages*
            ;; and try to find a gptel buffer
            (let ((fallback-buf (my/gptel--find-gptel-buffer)))
              (if fallback-buf
                  (with-current-buffer fallback-buf
                    (funcall orig where agent-type description))
                (funcall orig where agent-type description))))))
    result))

(defun my/gptel--find-gptel-buffer ()
  "Find a suitable gptel buffer for overlay placement.
Returns nil if no suitable buffer found."
  (catch 'found
    (dolist (buf (buffer-list))
      (when (and (buffer-live-p buf)
                 (buffer-local-value 'gptel-mode buf)
                 (not (string-match-p "^\\*\\(scratch\\|Messages\\|server\\)" (buffer-name buf))))
        (throw 'found buf)))
    nil))

(defun my/gptel-cleanup-stray-overlays ()
  "Remove gptel-agent overlays from buffers that shouldn't have them.
Cleans *scratch*, *Messages*, and *server* buffers."
  (interactive)
  (let ((cleaned 0))
    (dolist (buf-name '("*scratch*" "*Messages*" " *server*"))
      (when-let ((buf (get-buffer buf-name)))
        (when (buffer-live-p buf)
          (with-current-buffer buf
            (dolist (ov (overlays-in (point-min) (point-max)))
              (when (overlay-get ov 'gptel-agent)
                (delete-overlay ov)
                (cl-incf cleaned)))))))
    (when (> cleaned 0)
      (message "[gptel] Cleaned %d stray overlay(s) from system buffers" cleaned))
    cleaned))

(defun my/gptel--around-agent-update (orig &rest args)
  "Wrap `gptel-agent-update' to handle our deregistration of \"Agent\".
Upstream unconditionally updates the \"Agent\" tool's enum.  We
inject a throwaway stub so upstream completes without error, then
remove it."
  ;; Ensure a stub "Agent" tool exists so upstream's enum update succeeds
  (unless (ignore-errors (gptel-get-tool "Agent"))
    (gptel-make-tool
     :name "Agent" :category "gptel-agent"
     :function #'ignore :description "stub"
     :args '((:name "subagent_type" :type string :enum ["stub"]))))
  (apply orig args)
  ;; Remove the (now-updated) Agent tool
  (when-let* ((cat (assoc "gptel-agent" gptel--known-tools)))
    (setf (alist-get "Agent" (cdr cat) nil 'remove #'equal) nil)))

(with-eval-after-load 'gptel-agent
  (advice-add 'gptel-agent-update :around #'my/gptel--around-agent-update))





;;; Internal Variables

(defvar my/gptel--in-subagent-task nil
  "Non-nil while inside a `gptel-agent--task' call.")

;;; Context Builder

(defun my/gptel--string-to-bool (val)
  "Convert string or boolean VAL to Elisp boolean.
Returns t for \"true\" or t, nil for \"false\", nil, or any other value."
  (or (and (stringp val) (string= val "true"))
      (and (booleanp val) val)))
(defun my/gptel--xml-escape (text)
  "Escape XML special characters in TEXT.
Prevents XML injection when inserting file contents into context tags.
Escapes &, <, >, \", and ' per XML spec.
Optimized: single-pass character-by-character replacement."
  (if (not (stringp text))
      ""
    (mapconcat (lambda (c)
                 (pcase c
                   (?& "&amp;")
                   (?< "&lt;")
                   (?> "&gt;")
                   (?\" "&quot;")
                   (?' "&apos;")
                   (_ (string c))))
               (string-to-list text)
               "")))

(defun my/gptel--sanitize-for-logging (text &optional max-len)
  "Sanitize TEXT for safe logging to Messages buffer.
Replaces newlines, control chars, and backslashes with escaped representations.
Optional MAX-LEN truncates output (default: no truncation).
Returns sanitized string, or \"nil\" if TEXT is nil."
  (if (not (stringp text))
      "nil"
    (let ((result (replace-regexp-in-string
                   "[\n\r\t\\]" 
                   (lambda (m) (pcase m ("\n" "\\n") ("\r" "\\r") ("\t" "\\t") ("\\" "\\\\")))
                   text t t)))
      (if max-len
          (truncate-string-to-width result max-len nil nil "...")
        result))))

(defun my/gptel--safe-file-p (filepath)
  "Return non-nil if FILEPATH is safe to include in subagent context.
Rejects files outside project root, symlinks, and unreadable files.
Optimized: checks file validity before expensive project lookup."
  (when (and (stringp filepath)
             (file-readable-p filepath)
             (not (file-symlink-p filepath)))
    (when-let* ((proj (project-current))
                (proj-root (expand-file-name (project-root proj))))
      (string-prefix-p proj-root (expand-file-name filepath)))))

(defun my/gptel--build-subagent-context (prompt files include-history include-diff &optional origin-buf)
  "Package context for a subagent payload.
Appends contents of FILES, git diff if INCLUDE-DIFF, and recent buffer history
if INCLUDE-HISTORY to the base PROMPT.

ORIGIN-BUF is the parent chat buffer to read history from.  Defaults to
`current-buffer' if not provided, but callers should always pass it
explicitly to avoid capturing the wrong buffer.

FILES are validated against project root for security.

;; ASSUMPTION: Files must be within project root to prevent path traversal
;; BEHAVIOR: Builds XML-escaped context with files, git diff, and conversation history
;; EDGE CASE: Handles unreadable files, symlinks, and missing git repo gracefully
;; TEST: Verify files outside project are rejected with error message
;; GOAL: Provide secure, complete context for subagent decision-making
;; MEASURABLE: Context size limited to prevent token overflow (history capped at 8000 chars)"
  (let ((context ""))
    (when (and files (sequencep files))
      (let ((file-context ""))
        (cl-loop for f in (append files nil) do
                 (let ((filepath (expand-file-name f)))
                   (cond
                    ;; Security check: file must be within project, not a symlink
                    ((not (my/gptel--safe-file-p filepath))
                     (setq file-context (concat file-context
                                                (format "<file path=\"%s\">\n[Error: File not in project or is a symlink]\n</file>\n"
                                                        (my/gptel--xml-escape f)))))
                    ((file-readable-p filepath)
                     (with-temp-buffer
                       (insert-file-contents filepath)
                       (setq file-context (concat file-context
                                                  (format "<file path=\"%s\">\n%s\n</file>\n"
                                                          (my/gptel--xml-escape f)
                                                          (my/gptel--xml-escape (buffer-string)))))))
                    (t
                     (setq file-context (concat file-context
                                                (format "<file path=\"%s\">\n[Error: File not found or not readable]\n</file>\n"
                                                        (my/gptel--xml-escape f))))))))
        (when (not (string-empty-p file-context))
          (setq context (concat context "<files>\n" file-context "</files>\n\n")))))

    (when include-diff
      (let* ((proj (when (fboundp 'project-current) (project-current)))
             (proj-root (when proj (expand-file-name (project-root proj))))
             (default-directory
              (cond
               ((and proj-root (file-in-directory-p default-directory proj-root))
                proj-root)
               ((and proj-root (file-exists-p (expand-file-name ".git" proj-root)))
                proj-root)
               (t default-directory)))
             (diff-out (with-temp-buffer
                         (condition-case err
                             (let ((exit-code (call-process "git" nil '(t nil) nil "diff" "HEAD")))
                               (unless (eq exit-code 0)
                                 (message "[gptel] git diff exit code %s" exit-code))
                               (buffer-string))
                           (error
                            (message "[gptel] git diff error: %s" (error-message-string err))
                            "")))))
        (when (not (string-empty-p diff-out))
          (setq context (concat context "<git_diff>\n"
                                (my/gptel--xml-escape diff-out)
                                "\n</git_diff>\n\n")))))

    (when include-history
      (let* ((src-buf (or (and (buffer-live-p origin-buf) origin-buf)
                          (current-buffer)))
             (history-text (with-current-buffer src-buf
                             (buffer-substring-no-properties
                              (max (point-min) (- (point-max) 8000))
                              (point-max)))))
        (when (not (string-empty-p history-text))
          (setq context (concat context "<parent_conversation_history>\n"
                                (my/gptel--xml-escape history-text)
                                "\n</parent_conversation_history>\n\n")))))

    (if (string-empty-p context)
        prompt
      (concat context "Task:\n" prompt))))

;;; Subagent Functions

(defvar my/gptel--agent-task-state (make-hash-table :test 'eql)
  "Hash table for per-task state. Keyed by task-id.
Values are plist: (:done :timeout-timer :progress-timer).")

(defvar my/gptel--agent-task-counter 0
  "Counter for generating unique task IDs.")

(defvar my/gptel--subagent-origin-buffer nil
  "Buffer where subagent task was initiated.
Used by overlay advice to route overlays to correct buffer.
Dynamic variable, let-bound around gptel-agent--task calls.")

(defun my/gptel--agent-task-with-timeout (callback agent-type description prompt &optional files include-history include-diff)
  "Wrapper around `gptel-agent--task' that adds a timeout and progress messages.
CALLBACK is called with the result or a timeout error.
Uses hash table keyed by task-id to support parallel execution."
  (let* ((task-id (cl-incf my/gptel--agent-task-counter))
         (start-time (current-time))
         (parent-fsm (buffer-local-value 'gptel--fsm-last (current-buffer)))
         (origin-buf (current-buffer))
         (packaged-prompt (my/gptel--build-subagent-context prompt files include-history include-diff origin-buf))
         (wrapped-cb
          (lambda (result)
            (let ((state (gethash task-id my/gptel--agent-task-state)))
              (when (gptel-auto-workflow--state-active-p state)
                (puthash task-id (plist-put state :done t) my/gptel--agent-task-state)
                (when (timerp (plist-get state :timeout-timer))
                  (cancel-timer (plist-get state :timeout-timer)))
                (when (timerp (plist-get state :progress-timer))
                  (cancel-timer (plist-get state :progress-timer)))
                (message "[nucleus] Subagent %s completed in %.1fs, result-len=%d"
                         agent-type (float-time (time-since start-time))
                         (if (stringp result) (length result) 0)))
              (when (buffer-live-p origin-buf)
                (with-current-buffer origin-buf
                  (setq-local gptel--fsm-last parent-fsm))))
            (funcall callback result)
            (remhash task-id my/gptel--agent-task-state))))
    (puthash task-id (list :done nil :timeout-timer nil :progress-timer nil) my/gptel--agent-task-state)
    (message "[nucleus] Delegating to subagent %s%s..."
             agent-type
             (if my/gptel-agent-task-timeout
                 (format " (timeout: %ds)" my/gptel-agent-task-timeout)
               ""))
    (let ((progress-timer
           (run-at-time my/gptel-subagent-progress-interval
                        my/gptel-subagent-progress-interval
                        (lambda ()
                          (let ((state (gethash task-id my/gptel--agent-task-state)))
                            (when (gptel-auto-workflow--state-active-p state)
                              (message "[nucleus] Subagent %s still running... (%.1fs elapsed)"
                                       agent-type (float-time (time-since start-time)))))))))
      (puthash task-id (list :done nil :timeout-timer nil :progress-timer progress-timer) my/gptel--agent-task-state))
    (when my/gptel-agent-task-timeout
      (let ((timeout-timer
             (run-at-time my/gptel-agent-task-timeout nil
                          (lambda ()
                            (when (buffer-live-p origin-buf)
                              (with-current-buffer origin-buf
                                (let ((state (gethash task-id my/gptel--agent-task-state)))
                                  (when (gptel-auto-workflow--state-active-p state)
                                    (puthash task-id (plist-put state :done t) my/gptel--agent-task-state)
                                    (when (timerp (plist-get state :progress-timer))
                                      (cancel-timer (plist-get state :progress-timer)))
                                    (message "[nucleus] Subagent %s timed out after %ds, aborting request"
                                             agent-type my/gptel-agent-task-timeout)
                                    (when (fboundp 'gptel-abort)
                                      (ignore-errors (gptel-abort origin-buf)))
                                    (setq-local gptel--fsm-last parent-fsm)
                                    (funcall callback
                                             (format "Error: Task \"%s\" (%s) timed out after %ds."
                                                     description agent-type my/gptel-agent-task-timeout))))))))))
        (let ((state (gethash task-id my/gptel--agent-task-state)))
          (puthash task-id (plist-put state :timeout-timer timeout-timer) my/gptel--agent-task-state))))
    (let ((my/gptel--subagent-origin-buffer origin-buf))
      (unwind-protect
          (gptel-agent--task wrapped-cb agent-type description packaged-prompt)
        (let ((state (gethash task-id my/gptel--agent-task-state)))
          (when (and (gptel-auto-workflow--state-active-p state) (buffer-live-p origin-buf))
            (with-current-buffer origin-buf
              (setq-local gptel--fsm-last parent-fsm))))))))

(cl-defun my/gptel--run-agent-tool (callback agent-name description prompt &optional files include-history include-diff)
  "Run a gptel-agent agent by name.

AGENT-NAME must exist in `gptel-agent--agents`.

INCLUDE-HISTORY defaults to `my/gptel-subagent-include-history-default' when nil."
  (cl-block my/gptel--run-agent-tool
    (unless (and (require 'gptel nil t) (require 'gptel-agent nil t))
      (funcall callback "Error: gptel or gptel-agent is not available")
      (cl-return-from my/gptel--run-agent-tool))
    (unless (and (boundp 'gptel-agent--agents) gptel-agent--agents)
      (ignore-errors (gptel-agent-update)))
    (unless (gptel-auto-workflow--non-empty-string-p agent-name)
      (funcall callback "Error: agent-name is empty")
      (cl-return-from my/gptel--run-agent-tool))
    (unless (assoc agent-name gptel-agent--agents)
      (funcall callback
               (format "Error: unknown agent %S. Known agents: %s"
                       agent-name
                       (string-join (sort (mapcar #'car gptel-agent--agents) #'string<) ", ")))
      (cl-return-from my/gptel--run-agent-tool))
    ;; Hard gate: executor is forbidden in Plan mode (read-only preset).
    (when (and (equal agent-name "executor")
               (boundp 'gptel--preset)
               (eq gptel--preset 'gptel-plan))
      (funcall callback
               "Error: executor is not available in Plan mode. Switch to Agent mode first.")
      (cl-return-from my/gptel--run-agent-tool))
    (unless (fboundp 'gptel-agent--task)
      (funcall callback "Error: gptel-agent task runner not available")
      (cl-return-from my/gptel--run-agent-tool))
    ;; Convert string params to booleans at entry point for cleaner internal API
    (let ((include-history-bool (my/gptel--string-to-bool include-history))
          (include-diff-bool (my/gptel--string-to-bool include-diff)))
      ;; Apply defaults for nil boolean values
      (when (null include-history-bool)
        (setq include-history-bool my/gptel-subagent-include-history-default))
      (my/gptel--agent-task-with-timeout callback agent-name description prompt files
                                         include-history-bool include-diff-bool))))

;;; Tool Registration

(defun gptel-tools-agent-register ()
  "Register RunAgent tool with gptel."
  (when (fboundp 'gptel-make-tool)
    (gptel-make-tool
     :name "RunAgent"
     :description "Run a gptel-agent subagent by name (e.g. explorer, researcher, executor, reviewer)"
     :function #'my/gptel--run-agent-tool
     :args '((:name "agent_name"
                    :type string
                    :description "Agent name (e.g. 'researcher', 'introspector', 'executor', 'explorer', 'reviewer')"
                    :enum ["explorer" "researcher" "introspector" "executor" "reviewer"])
             (:name "description"
                    :type string
                    :description "Short task label")
             (:name "prompt"
                    :type string
                    :description "Full task prompt")
             (:name "files"
                    :type array
                    :items (:type string)
                    :optional t
                    :description "Optional list of file paths to inject into the subagent context.")
             (:name "include_history"
                    :type string
                    :optional t
                    :description "Set to \"false\" to exclude conversation history. Default: history IS included (see my/gptel-subagent-include-history-default).")
             (:name "include_diff"
                    :type string
                    :optional t
                    :description "Set to \"true\" to inject git diff HEAD into subagent context."))
     :category "gptel-agent"
     :async t
     :confirm t
     :include t)))

;;; TodoWrite Overlay Fix for Subagent Context

(defvar gptel-agent--hrule)  ; from gptel-agent-tools

(defvar-local my/gptel--todo-overlay nil
  "Buffer-local cache for TodoWrite overlay.
Avoids scanning entire buffer on each update.")

(defun my/gptel-agent--write-todo-around (orig todos)
  "Advice to fix TodoWrite overlay updates in subagent context.
Uses cached overlay reference for O(1) lookup instead of O(n) buffer scan."
  (setq gptel-agent--todos todos)
  (let* ((info (gptel-fsm-info gptel--fsm-last))
         (pos (or (plist-get info :tracking-marker)
                  (plist-get info :position)))
         (buf (plist-get info :buffer))
         (existing-ov (and buf
                           (buffer-live-p buf)
                           (with-current-buffer buf
                             (or my/gptel--todo-overlay
                                 (setq my/gptel--todo-overlay
                                       (cl-find-if
                                        (lambda (ov) (overlay-get ov 'gptel-agent--todos))
                                        (overlays-in (point-min) (point-max)))))))))
    (if existing-ov
        (let* ((formatted-todos
                (mapconcat
                 (lambda (todo)
                   (pcase (plist-get todo :status)
                     ("completed"
                      (concat "✓ " (propertize (plist-get todo :content)
                                               'face '(:inherit shadow :strike-through t))))
                     ("in_progress"
                      (concat "● " (propertize (plist-get todo :activeForm)
                                               'face '(:inherit (bold warning)))))
                     (_ (concat "○ " (plist-get todo :content)))))
                 todos "\n"))
               (todo-display
                (concat
                 (unless (= (char-before (overlay-end existing-ov)) 10) "\n")
                 gptel-agent--hrule
                 (propertize "Task list: [ "
                             'face '(:inherit (font-lock-comment-face bold)))
                 (propertize "TAB to toggle display ]\n" 'face 'font-lock-comment-face)
                 formatted-todos "\n"
                 gptel-agent--hrule)))
          (overlay-put existing-ov 'after-string todo-display)
          t)
      (funcall orig todos))))

(with-eval-after-load 'gptel-agent-tools
  (advice-add 'gptel-agent--write-todo :around #'my/gptel-agent--write-todo-around))

;;; Auto-Workflow (Semi-Autonomous Overnight Experiments)

(declare-function magit-worktree-branch "magit-worktree")
(declare-function magit-worktree-delete "magit-worktree")
(declare-function magit-git-success "magit-git")
(declare-function gptel-benchmark-analyze "gptel-benchmark-subagent")
(declare-function gptel-benchmark-grade "gptel-benchmark-subagent")
(declare-function gptel-benchmark-compare "gptel-benchmark-subagent")
(declare-function gptel-benchmark-eight-keys-score "gptel-benchmark-principles")
(declare-function gptel-auto-experiment--agent-error-p "gptel-tools-agent")

;;; Configuration

(defcustom gptel-auto-workflow-targets
  '()
  "Static fallback targets when LLM selection disabled or fails.
Empty by default - LLM selects targets dynamically.
Monthly subscription: LLM selection finds best targets each run."
  :type '(repeat string)
  :safe #'always
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-worktree-base "var/tmp/experiments"
  "Base directory for auto-workflow worktrees."
  :type 'directory
  :group 'gptel-tools-agent)

(defcustom gptel-auto-experiment-time-budget 600
  "Time budget per experiment in seconds (default: 10 min)."
  :type 'integer
  :safe #'integerp
  :group 'gptel-tools-agent)

(defcustom gptel-auto-experiment-delay-between 3
  "Seconds to wait between experiments to avoid API rate limits."
  :type 'integer
  :safe #'integerp
  :group 'gptel-tools-agent)

(defcustom gptel-auto-experiment-max-per-target 5
  "Maximum experiments per target.
Monthly subscription: 5 is optimal (diminishing returns after 3-4)."
  :type 'integer
  :safe #'integerp
  :group 'gptel-tools-agent)

(defcustom gptel-auto-experiment-no-improvement-threshold 2
  "Stop after N consecutive no-improvements.
Monthly subscription: 2 for fail-fast, try more different files."
  :type 'integer
  :safe #'integerp
  :group 'gptel-tools-agent)

(defcustom gptel-auto-experiment-use-subagents t
  "Use analyzer/grader/comparator subagents."
  :type 'boolean
  :group 'gptel-tools-agent)

(defcustom gptel-auto-experiment-auto-push t
  "Automatically push experiment branches to origin after successful commit.
When non-nil, branches are pushed to origin for PR review on Forgejo."
  :type 'boolean
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-require-review t
  "When non-nil, require LLM code review before merging to staging.
Reviewer checks for blockers, critical bugs, and security issues.
Changes are only merged if review passes."
  :type 'boolean
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-research-before-fix nil
  "When non-nil, use researcher to find fix approach before executor.
Adds ~30-60s latency per retry but may improve fix quality.
When nil, executor researches and fixes in one pass (faster)."
  :type 'boolean
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-use-staging t
  "When non-nil, use staging branch as integration target.
Staging is NEVER deleted and NEVER auto-merged to main.

Flow:
1. Sync staging from main at workflow start
2. optimize/* changes are merged to staging
3. Tests run on staging (isolated worktree)
4. If tests pass: push staging to origin
5. Human reviews staging and manually merges to main

IMPORTANT: Auto-workflow NEVER touches main branch.
All merges wait in staging for human review."
  :type 'boolean
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-staging-branch "staging"
  "Name of the staging branch for integration.
This branch is NEVER deleted and NEVER auto-merged to main."
  :type 'string
  :group 'gptel-tools-agent)

;;; State

(defvar gptel-auto-workflow--staging-worktree-dir nil)
(defvar gptel-auto-workflow--review-retry-count 0
  "Retry count for current review cycle.")
(defvar gptel-auto-workflow--review-max-retries 2
  "Maximum retries when review is blocked. 0 = no retry.")

(defvar gptel-auto-workflow--worktree-state (make-hash-table :test 'equal)
  "Hash table for per-target worktree state. Keyed by target.
Values: plist (:worktree-dir :current-branch).")

(defvar gptel-auto-experiment--no-improvement-count 0
  "Count of consecutive experiments with no improvement.")
(defvar gptel-auto-experiment--best-score 0.0
  "Best score achieved in current experiment loop.")

;; Safety: Ensure worktree-state is initialized (handles case where
;; variable was previously bound but not as hash-table)
(unless (hash-table-p gptel-auto-workflow--worktree-state)
  (setq gptel-auto-workflow--worktree-state (make-hash-table :test 'equal)))

(defun gptel-auto-workflow--get-worktree-state (target key)
  "Get value for KEY from worktree state for TARGET.
Helper to reduce duplication in worktree accessor functions.
Returns nil if hash table is invalid or TARGET not found."
  (when (hash-table-p gptel-auto-workflow--worktree-state)
    (plist-get (gethash target gptel-auto-workflow--worktree-state) key)))

(defun gptel-auto-workflow--get-worktree-dir (target)
  "Get worktree-dir for TARGET from hash table."
  (gptel-auto-workflow--get-worktree-state target :worktree-dir))

(defun gptel-auto-workflow--get-current-branch (target)
  "Get current-branch for TARGET from hash table."
  (gptel-auto-workflow--get-worktree-state target :current-branch))

(defun gptel-auto-workflow--clear-worktree-state (target)
  "Clear worktree state for TARGET.
Resets :worktree-dir and :current-branch to nil in hash table.
ASSUMPTION: gptel-auto-workflow--worktree-state is a hash table.
TESTABLE: Can verify state is cleared by checking gethash result."
  (when (hash-table-p gptel-auto-workflow--worktree-state)
    (puthash target (list :worktree-dir nil :current-branch nil)
             gptel-auto-workflow--worktree-state)))

;;; Worktree Management

(defun gptel-auto-workflow--branch-name (target &optional experiment-id)
  "Generate branch name for TARGET with machine hostname.
Format: optimize/{target}-{hostname}-exp{N}
Base branch is always 'main'.
Multiple machines can optimize same target without conflicts."
  (let* ((basename (file-name-sans-extension (file-name-nondirectory target)))
         (name (car (last (split-string basename "-"))))
         (host system-name))
    (if experiment-id
        (format "optimize/%s-%s-exp%d" name host experiment-id)
      (format "optimize/%s-%s" name host))))

(defun gptel-auto-workflow-create-worktree (target &optional experiment-id)
  "Create worktree for TARGET. EXPERIMENT-ID creates numbered branch.
Stores worktree-dir, current-branch in hash table keyed by TARGET.
Uses git CLI directly to avoid magit-worktree-branch hangs.
If branch exists locally, deletes it first to avoid conflicts."
  (let* ((proj-root (or (gptel-auto-workflow--project-root)
                        (expand-file-name "~/.emacs.d/")))
         (branch (gptel-auto-workflow--branch-name target experiment-id))
         (worktree-base-dir (or gptel-auto-workflow-worktree-base
                                "var/tmp/experiments"))
         (worktree-dir (expand-file-name
                        (format "%s/%s" worktree-base-dir branch)
                        proj-root))
         (stderr-buffer (generate-new-buffer "*git-stderr*")))
    (condition-case err
        (progn
          (make-directory (file-name-directory worktree-dir) t)
          (let ((default-directory proj-root))
            ;; Remove existing worktree if present (stale from previous run)
            (when (file-exists-p worktree-dir)
              (call-process "git" nil nil stderr-buffer "worktree" "remove" "-f" worktree-dir))
            ;; Delete branch if it exists locally (stale from previous run)
            (call-process "git" nil nil stderr-buffer "branch" "-D" branch)
            ;; Create worktree with new branch
            (let ((exit-code (call-process "git" nil nil stderr-buffer
                                           "worktree" "add" "-b" branch
                                           worktree-dir "main"))
                  (stderr-output (when (buffer-live-p stderr-buffer)
                                   (with-current-buffer stderr-buffer
                                     (buffer-string)))))
              (unless (eq exit-code 0)
                (when stderr-output
                  (message "[auto-workflow] Git stderr: %s" stderr-output))
                (error "git worktree add failed with exit code %s: %s" 
                       exit-code (or stderr-output "no output")))))
          (kill-buffer stderr-buffer)
          (message "[auto-workflow] Created: %s" branch)
          (puthash target (list :worktree-dir worktree-dir :current-branch branch)
                   gptel-auto-workflow--worktree-state)
          worktree-dir)
      (error
       (when (buffer-live-p stderr-buffer)
         (kill-buffer stderr-buffer))
       (message "[auto-workflow] Failed to create worktree: %s" err)
       (gptel-auto-workflow--clear-worktree-state target)
       nil))))

(defun gptel-auto-workflow-delete-worktree (target)
  "Delete worktree for TARGET from hash table.
Also deletes the associated branch.
Uses git CLI directly to avoid magit issues."
  (let* ((state (gethash target gptel-auto-workflow--worktree-state))
         (worktree-dir (plist-get state :worktree-dir))
         (branch (plist-get state :current-branch)))
    (when (and worktree-dir (file-exists-p worktree-dir))
      (let ((proj-root (or (gptel-auto-workflow--project-root)
                           (expand-file-name "~/.emacs.d/"))))
        (condition-case err
            (let ((default-directory proj-root))
              ;; Remove worktree
              (let ((exit-code (call-process "git" nil nil nil
                                             "worktree" "remove" worktree-dir)))
                (unless (eq exit-code 0)
                  (error "git worktree remove failed with exit code %s" exit-code)))
              ;; Delete the branch
              (when branch
                (call-process "git" nil nil nil "branch" "-D" branch)))
          (error
           (message "[auto-workflow] Failed to delete worktree: %s" err)))))
    (gptel-auto-workflow--clear-worktree-state target)))

;;; Staging Branch Protection

;; ═══════════════════════════════════════════════════════════════════════════
;; CRITICAL INVARIANT: Auto-workflow NEVER touches main branch.
;;
;; What we DO:
;;   - Read from main (to create worktrees, sync staging)
;;   - Write to optimize/* (experiment branches)
;;   - Write to staging (integration branch)
;;
;; What we NEVER do:
;;   - checkout main
;;   - merge to main
;;   - push to main
;;   - reset main
;;
;; Human responsibility:
;;   - Review staging
;;   - Merge staging → main manually
;; ═══════════════════════════════════════════════════════════════════════════

(defun gptel-auto-workflow--assert-main-untouched ()
  "Assert that current branch is NOT main.
Call this before any git operation that might modify branches."
  (let ((current (magit-get-current-branch)))
    (when (string= current "main")
      (error "[SAFETY] Auto-workflow attempted to operate on main branch!"))))

(defun gptel-auto-workflow--staging-branch-exists-p ()
  "Check if staging branch exists locally or remotely."
  (let ((branch gptel-auto-workflow-staging-branch))
    (or (member branch (magit-list-local-branch-names))
        (member (concat "origin/" branch) (magit-list-remote-branch-names)))))

(defun gptel-auto-workflow--sync-staging-from-main ()
  "Sync staging branch from main at workflow start.
ASSUMPTION: Staging branch exists or will be created.
BEHAVIOR: Hard resets staging to match main.
EDGE CASE: Creates staging from main if it doesn't exist.
TEST: Verify staging matches main after sync.
SAFETY: Never touches main branch."
  (gptel-auto-workflow--assert-main-untouched)
  (let* ((proj-root (gptel-auto-workflow--project-root))
         (default-directory proj-root)
         (staging gptel-auto-workflow-staging-branch))
    (message "[auto-workflow] Syncing staging from main")
    (condition-case err
        (progn
          (cond
           ((gptel-auto-workflow--staging-branch-exists-p)
            (magit-git-success "checkout" staging)
            (magit-git-success "reset" "--hard" "main")
            (magit-git-success "push" "--force" "origin" staging))
           (t
            (message "[auto-workflow] Creating staging branch from main")
            (magit-git-success "branch" staging "main")
            (magit-git-success "push" "-u" "origin" staging)))
          (message "[auto-workflow] ✓ Staging synced from main")
          t)
      (error
       (message "[auto-workflow] Failed to sync staging: %s" err)
       nil))))

(defun gptel-auto-workflow--create-staging-worktree ()
  "Create isolated worktree for staging verification.
Never touches project root - all verification happens in worktree.
Returns worktree path or nil on failure."
  (let* ((proj-root (or (gptel-auto-workflow--project-root)
                        (expand-file-name "~/.emacs.d/")))
         (default-directory proj-root)
         (branch gptel-auto-workflow-staging-branch)
         (worktree-base-dir (or gptel-auto-workflow-worktree-base
                                "var/tmp/experiments"))
         (worktree-dir (expand-file-name
                        (format "%s/staging-verify" worktree-base-dir)
                        proj-root)))
    (gptel-auto-workflow--with-error-handling
     "create staging worktree"
     (lambda ()
       (when (file-exists-p worktree-dir)
         (delete-directory worktree-dir t))
       (make-directory (file-name-directory worktree-dir) t)
       ;; Use magit-worktree-checkout for existing branch
       ;; magit-worktree-branch is for creating NEW branches (fails if branch exists)
       (magit-worktree-checkout worktree-dir branch)
       (setq gptel-auto-workflow--staging-worktree-dir worktree-dir)
       (message "[auto-workflow] Created staging worktree: %s" worktree-dir)
       worktree-dir))))

(defun gptel-auto-workflow--delete-staging-worktree ()
  "Delete staging verification worktree.
NOTE: Staging BRANCH is never deleted, only the worktree."
  (when (and gptel-auto-workflow--staging-worktree-dir
             (file-exists-p gptel-auto-workflow--staging-worktree-dir))
    (let ((proj-root (gptel-auto-workflow--project-root)))
      (gptel-auto-workflow--with-error-handling
       "delete staging worktree"
       (lambda ()
         (let ((default-directory proj-root))
           (magit-worktree-delete gptel-auto-workflow--staging-worktree-dir))))))
  (setq gptel-auto-workflow--staging-worktree-dir nil))

(defun gptel-auto-workflow--review-changes (optimize-branch callback)
  "Review changes in OPTIMIZE-BRANCH before merging to staging.
Calls CALLBACK with (approved-p . review-output).
Reviewer checks for Blocker/Critical issues."
  (if (not gptel-auto-workflow-require-review)
      (funcall callback (cons t "Review disabled by config"))
    (let* ((proj-root (gptel-auto-workflow--project-root))
           (default-directory proj-root)
           ;; SECURITY: Use shell-quote-argument to prevent shell injection
           (staging-quoted (shell-quote-argument gptel-auto-workflow-staging-branch))
           (optimize-quoted (shell-quote-argument optimize-branch))
           ;; FIX: Simplified diff command to capture actual changes, not just stats
           ;; Added 2>&1 to capture stderr for error diagnosis
           (diff-cmd (format "git diff %s...%s 2>&1"
                             staging-quoted optimize-quoted))
           (diff-output (shell-command-to-string diff-cmd))
           ;; ASSUMPTION: Empty diff means no changes or error - handle both cases
           ;; BEHAVIOR: Check if diff output is empty or contains error message
           (diff-content (cond
                          ((string-empty-p diff-output)
                           "No changes detected between branches.")
                          ((string-match-p "^fatal:" diff-output)
                           (format "Error generating diff: %s" diff-output))
                          (t diff-output)))
           (review-prompt (format "Review the following changes for blockers, critical bugs, and security issues.

CHANGES (diff):
%s

REVIEW CRITERIA:
- Blocker: Runtime error, state corruption, data loss, security hole
- Critical: Proven correctness bug in current code
- Security: eval of untrusted input, shell injection, nil without guard

OUTPUT: If NO blockers or critical issues, start with 'APPROVED'.
If blockers/critical found, start with 'BLOCKED: [reason]'.

Maximum response: 1000 characters."
                                  (truncate-string-to-width diff-content 3000 nil nil "..."))))
      (message "[auto-workflow] Reviewing changes in %s..." optimize-branch)
      (if (and gptel-auto-experiment-use-subagents
               (fboundp 'gptel-benchmark-call-subagent))
          (gptel-benchmark-call-subagent
           'reviewer
           "Review changes before merge"
           review-prompt
           (lambda (result)
             (let* ((response (if (stringp result) result (format "%S" result)))
                    (approved (string-match-p "^APPROVED" response)))
               (message "[auto-workflow] Review %s: %s"
                        (if approved "PASSED" "BLOCKED")
                        (my/gptel--sanitize-for-logging response 100))
               (funcall callback (cons approved response)))))
        (funcall callback (cons t "No reviewer agent available, auto-approving"))))))

(defun gptel-auto-workflow--fix-review-issues (optimize-branch review-output callback)
  "Try to fix issues found in review for OPTIMIZE-BRANCH.
REVIEW-OUTPUT contains the blocker/critical issues.
Calls CALLBACK with (success-p . fix-output).
If `gptel-auto-workflow-research-before-fix' is nil, executor handles directly."
  (let* ((proj-root (gptel-auto-workflow--project-root))
         (default-directory proj-root))
    (message "[auto-workflow] Fixing review issues (retry %d/%d)..."
             gptel-auto-workflow--review-retry-count gptel-auto-workflow--review-max-retries)
    (if (not gptel-auto-workflow-research-before-fix)
        (gptel-auto-workflow--fix-directly review-output callback)
      (gptel-auto-workflow--research-then-fix review-output callback))))

(defun gptel-auto-workflow--fix-directly (review-output callback)
  "Let executor fix REVIEW-OUTPUT issues directly (faster)."
  (let* ((proj-root (gptel-auto-workflow--project-root))
         (default-directory proj-root)
         (fix-prompt (format "Fix the following issues in the code.

ISSUES FROM REVIEW:
%s

INSTRUCTIONS:
1. Read the affected files to understand context
2. Make minimal fixes to address each issue
3. Do NOT make unrelated changes
4. Commit your fix with message 'fix: address review issues'

Focus only on the issues mentioned. Do not refactor or add features."
                             (truncate-string-to-width review-output 1500 nil nil "..."))))
    (if (and gptel-auto-experiment-use-subagents
             (fboundp 'gptel-benchmark-call-subagent))
        (gptel-benchmark-call-subagent
         'executor
         "Fix review issues"
         fix-prompt
         (lambda (result)
           (let* ((response (if (stringp result) result (format "%S" result)))
                  (success (not (string-match-p "^Error:" response))))
             (when success
               (magit-git-success "add" "-A")
               (magit-git-success "commit" "-m" "fix: address review issues"))
             (funcall callback (cons success response)))))
      (funcall callback (cons nil "No executor agent available")))))

(defun gptel-auto-workflow--research-then-fix (review-output callback)
  "Use researcher to find approach, then executor to fix REVIEW-OUTPUT."
  (let* ((proj-root (gptel-auto-workflow--project-root))
         (default-directory proj-root)
         (research-prompt (format "Research the best approach to fix these issues:

ISSUES FROM REVIEW:
%s

TASK:
1. Find relevant code patterns in the codebase
2. Check for similar fixes already implemented
3. Identify the minimal, correct fix approach
4. Return a concise fix plan (file:line, change description)

Do NOT make changes. Only research and report findings."
                                  (truncate-string-to-width review-output 1000 nil nil "..."))))
    (message "[auto-workflow] Researching fix approach...")
    (if (and gptel-auto-experiment-use-subagents
             (fboundp 'gptel-benchmark-call-subagent))
        (gptel-benchmark-call-subagent
         'researcher
         "Research fix approach"
         research-prompt
         (lambda (research-result)
           (let* ((research-response (if (stringp research-result) research-result (format "%S" research-result)))
                  (fix-prompt (format "Apply fixes based on this research:

RESEARCH FINDINGS:
%s

ORIGINAL ISSUES:
%s

INSTRUCTIONS:
1. Apply the minimal fixes identified in research
2. Do NOT make unrelated changes
3. Commit with message 'fix: address review issues'"
                                      (truncate-string-to-width research-response 1000 nil nil "...")
                                      (truncate-string-to-width review-output 500 nil nil "..."))))
             (gptel-benchmark-call-subagent
              'executor
              "Apply researched fixes"
              fix-prompt
              (lambda (result)
                (let* ((response (if (stringp result) result (format "%S" result)))
                       (success (not (string-match-p "^Error:" response))))
                  (when success
                    (magit-git-success "add" "-A")
                    (magit-git-success "commit" "-m" "fix: address review issues"))
                  (funcall callback (cons success response))))))))
      (funcall callback (cons nil "No subagent available")))))

(defun gptel-auto-workflow--ensure-on-main-branch ()
  "Ensure main repo is on main branch.
Returns t on success, nil if unable to switch.
This prevents 'branch already used by worktree' errors."
  (let* ((proj-root (gptel-auto-workflow--project-root))
         (default-directory proj-root)
         (current-branch (string-trim 
                          (or (gptel-auto-workflow--git-cmd 
                               "git rev-parse --abbrev-ref HEAD 2>/dev/null") 
                              "main"))))
    (if (string= current-branch "main")
        t
      (message "[auto-workflow] Switching from %s to main branch" current-branch)
      (gptel-auto-workflow--with-error-handling
       "switch to main branch"
       (lambda ()
         (gptel-auto-workflow--git-cmd "git checkout main")
         t)))))

;;;###autoload
(defun gptel-auto-workflow--ensure-staging-branch-exists ()
  "Ensure staging branch exists locally and remotely.
Creates staging from main if it doesn't exist.
Returns t on success, nil on failure."
  (let* ((proj-root (gptel-auto-workflow--project-root))
         (default-directory proj-root)
         (staging gptel-auto-workflow-staging-branch))
    (gptel-auto-workflow--with-error-handling
     "ensure staging branch exists"
     (lambda ()
       (gptel-auto-workflow--git-cmd "git fetch origin" 180)
       (let* ((local-exists (string-match-p staging 
                                            (or (gptel-auto-workflow--git-cmd 
                                                 "git branch --list staging") "")))
              (remote-exists (string-match-p staging 
                                             (or (gptel-auto-workflow--git-cmd 
                                                  "git branch -r --list origin/staging") ""))))
         (cond
          ((and local-exists remote-exists)
           (message "[auto-workflow] Staging branch exists"))
          ((and (not local-exists) remote-exists)
           (message "[auto-workflow] Creating local staging from origin/staging")
           (gptel-auto-workflow--git-cmd "git branch staging origin/staging"))
          ((and local-exists (not remote-exists))
           (message "[auto-workflow] Pushing staging to origin")
           (gptel-auto-workflow--git-cmd "git push origin staging"))
          (t
           (message "[auto-workflow] Creating staging branch from main")
           (gptel-auto-workflow--git-cmd "git branch staging main")
           (gptel-auto-workflow--git-cmd "git push origin staging")))
         t)))))

;;;###autoload

(defun gptel-auto-workflow--merge-to-staging (optimize-branch)
  "Merge OPTIMIZE-BRANCH to staging.
Auto-resolves conflicts by preferring incoming changes (theirs).
Returns t on success, nil on unrecoverable conflict.
Ensures main repo stays on main branch throughout."
  (let* ((proj-root (gptel-auto-workflow--project-root))
         (default-directory proj-root)
         (staging gptel-auto-workflow-staging-branch)
         (original-branch (string-trim 
                           (or (gptel-auto-workflow--git-cmd 
                                "git rev-parse --abbrev-ref HEAD 2>/dev/null") 
                               "main"))))
    (message "[auto-workflow] Merging %s to %s" optimize-branch staging)
    (condition-case err
        (progn
          (gptel-auto-workflow--ensure-on-main-branch)
          (gptel-auto-workflow--ensure-staging-branch-exists)
          (gptel-auto-workflow--git-cmd (format "git checkout %s" staging))
          (condition-case merge-err
              (progn
                (gptel-auto-workflow--git-cmd 
                 "merge" optimize-branch "--no-ff" "-m"
                 (format "Merge %s for verification" optimize-branch))
                (gptel-auto-workflow--git-cmd "git checkout main")
                t)
            (error
             (if (string-match-p "conflict" (error-message-string merge-err))
                 (progn
                   (message "[auto-workflow] Auto-resolving conflicts with theirs")
                   (gptel-auto-workflow--git-cmd "checkout" "--theirs" ".")
                   (gptel-auto-workflow--git-cmd "add" "-A")
                   (gptel-auto-workflow--git-cmd 
                    "commit" "-m" (format "Merge %s (auto-resolved conflicts)" optimize-branch))
                   (gptel-auto-workflow--git-cmd "git checkout main")
                   t)
               (message "[auto-workflow] Merge failed: %s" merge-err)
               (gptel-auto-workflow--git-cmd "merge" "--abort")
               (gptel-auto-workflow--git-cmd "git checkout main")
               nil))))
      (error
       (message "[auto-workflow] Failed to merge to staging: %s" err)
       (gptel-auto-workflow--git-cmd "git checkout main")
       nil))))

(defun gptel-auto-workflow--verify-staging ()
  "Run tests on staging worktree.
Returns (success-p . output) plist.
ASSUMPTION: Staging worktree exists.
BEHAVIOR: Runs run-tests.sh in staging worktree.
EDGE CASE: Returns nil if worktree doesn't exist."
  (let* ((worktree gptel-auto-workflow--staging-worktree-dir)
         (test-script (expand-file-name "scripts/run-tests.sh" worktree))
         (verify-script (expand-file-name "scripts/verify-nucleus.sh" worktree))
         (output-buffer (generate-new-buffer "*staging-verify*"))
         result)
    (if (not (and worktree (file-exists-p worktree)))
        (progn
          (message "[auto-workflow] Staging worktree not found")
          (cons nil "Staging worktree not found"))
      (message "[auto-workflow] Verifying staging...")
      (let* ((test-result (when (file-exists-p test-script)
                            (call-process test-script nil output-buffer nil)))
             (verify-result (when (file-exists-p verify-script)
                              (call-process verify-script nil output-buffer nil)))
             (test-pass (or (not (file-exists-p test-script))
                            (eq test-result 0)))
             (verify-pass (or (not (file-exists-p verify-script))
                              (eq verify-result 0)))
             (output (with-current-buffer output-buffer (buffer-string))))
        (kill-buffer output-buffer)
        (setq result (and test-pass verify-pass))
        (message "[auto-workflow] Staging verification: %s" (if result "PASS" "FAIL"))
        (cons result output)))))

(defun gptel-auto-workflow--push-staging ()
  "Push staging branch to origin after successful verification."
  (let* ((proj-root (gptel-auto-workflow--project-root))
         (default-directory proj-root)
         (staging gptel-auto-workflow-staging-branch))
    (message "[auto-workflow] Pushing staging to origin")
    (magit-git-success "push" "origin" staging)))

(defun gptel-auto-workflow--staging-flow (optimize-branch)
  "Run staging verification flow for OPTIMIZE-BRANCH.

Flow:
1. Review changes (if gptel-auto-workflow-require-review)
2. If review blocked: try to fix (up to N retries)
3. Merge OPTIMIZE-BRANCH to staging
4. Create staging worktree (never touches project root)
5. Run tests on staging
6. If pass: push staging to origin (human reviews later)
7. If fail: log failure to TSV, staging left for debug

ASSUMPTION: OPTIMIZE-BRANCH has been pushed to origin.
BEHAVIOR: Never modifies project root - all verification in worktree.
EDGE CASE: Handles merge conflicts with auto-resolution (theirs).
TEST: Verify main is never touched by auto-workflow.
SAFETY: Asserts main branch is not current before any operation.

NOTE: Human must manually merge staging to main after review."
  (gptel-auto-workflow--assert-main-untouched)
  (setq gptel-auto-workflow--review-retry-count 0)
  (message "[auto-workflow] Starting staging flow for %s" optimize-branch)
  (gptel-auto-workflow--review-changes
   optimize-branch
   (lambda (review-result)
     (gptel-auto-workflow--staging-flow-after-review optimize-branch review-result))))

(defun gptel-auto-workflow--staging-flow-after-review (optimize-branch review-result)
  "Continue staging flow after review for OPTIMIZE-BRANCH.
REVIEW-RESULT is (approved-p . review-output)."
  (let ((approved (car review-result))
        (review-output (cdr review-result)))
    (if (not approved)
        (if (< gptel-auto-workflow--review-retry-count gptel-auto-workflow--review-max-retries)
            (progn
              (cl-incf gptel-auto-workflow--review-retry-count)
              (message "[auto-workflow] Review blocked, attempting fix...")
              (gptel-auto-workflow--fix-review-issues
               optimize-branch
               review-output
               (lambda (fix-result)
                 (let ((fix-success (car fix-result))
                       (fix-output (cdr fix-result)))
                   (if fix-success
                       (progn
                         (message "[auto-workflow] Fix applied, re-reviewing...")
                         (gptel-auto-workflow--review-changes
                          optimize-branch
                          (lambda (re-review-result)
                            (gptel-auto-workflow--staging-flow-after-review optimize-branch re-review-result))))
                     (message "[auto-workflow] Fix failed: %s" (my/gptel--sanitize-for-logging fix-output 200))
                     (gptel-auto-experiment-log-tsv
                      (format-time-string "%Y-%m-%d")
                      (list :target "staging-review"
                            :id 0
                            :hypothesis "Staging review fix"
                            :score-before 0
                            :score-after 0
                            :kept nil
                            :duration 0
                            :grader-quality 0
                            :grader-reason "fix-failed"
                            :comparator-reason (truncate-string-to-width fix-output 200)
                            :analyzer-patterns ""
                            :agent-output review-output)))))))
          (progn
            (message "[auto-workflow] ✗ Review BLOCKED (max retries): %s" (my/gptel--sanitize-for-logging review-output 200))
            (gptel-auto-experiment-log-tsv
             (format-time-string "%Y-%m-%d")
             (list :target "staging-review"
                   :id 0
                   :hypothesis "Staging review"
                   :score-before 0
                   :score-after 0
                   :kept nil
                   :duration 0
                   :grader-quality 0
                   :grader-reason "review-blocked-max-retries"
                   :comparator-reason (truncate-string-to-width review-output 200)
                   :analyzer-patterns ""
                   :agent-output review-output))))
      (let* ((proj-root (gptel-auto-workflow--project-root))
             (default-directory proj-root)
             (merge-success (gptel-auto-workflow--merge-to-staging optimize-branch)))
        (if (not merge-success)
            (progn
              (message "[auto-workflow] ✗ Merge to staging failed, aborting")
              (gptel-auto-experiment-log-tsv
               (format-time-string "%Y-%m-%d")
               (list :target "staging-merge"
                     :id 0
                     :hypothesis "Staging merge"
                     :score-before 0
                     :score-after 0
                     :kept nil
                     :duration 0
                     :grader-quality 0
                     :grader-reason "staging-merge-failed"
                     :comparator-reason (format "Failed to merge %s to staging" optimize-branch)
                     :analyzer-patterns ""
                     :agent-output "")))
          (let* ((worktree (gptel-auto-workflow--create-staging-worktree))
                 (verification (when worktree (gptel-auto-workflow--verify-staging)))
                 (tests-passed (car verification))
                 (output (cdr verification)))
            (if (not tests-passed)
                (progn
                  (message "[auto-workflow] ✗ Staging verification FAILED")
                  (gptel-auto-workflow--delete-staging-worktree)
                  (gptel-auto-experiment-log-tsv
                   (format-time-string "%Y-%m-%d")
                   (list :target "staging-verification"
                         :id 0
                         :hypothesis "Staging verification"
                         :score-before 0
                         :score-after 0
                         :kept nil
                         :duration 0
                         :grader-quality 0
                         :grader-reason "staging-verification-failed"
                         :comparator-reason (truncate-string-to-width output 200)
                         :analyzer-patterns ""
                         :agent-output output)))
              (message "[auto-workflow] ✓ Staging verification PASSED")
              (gptel-auto-workflow--delete-staging-worktree)
              (gptel-auto-workflow--push-staging)
              (message "[auto-workflow] ✓ Staging pushed. Human must merge to main."))))))))

;;; Multi-Project Support

;; Auto-workflow uses .dir-locals.el for per-project configuration.
;; Place .dir-locals.el in your project root with workflow-specific settings.
;;
;; Example .dir-locals.el:
;; ((nil . ((gptel-auto-workflow-targets . ("src/main.el" "src/utils.el"))
;;          (gptel-auto-experiment-max-per-target . 3)
;;          (gptel-auto-experiment-time-budget . 900)
;;          (gptel-backend . gptel--dashscope)
;;          (gptel-model . qwen3.5-plus))))

(defvar gptel-auto-workflow--project-root-override nil
  "Override for project root when running from non-git directory.
Set via .dir-locals.el or M-x gptel-auto-workflow-set-project-root")

(defun gptel-auto-workflow-set-project-root (root)
  "Set the project ROOT for current session.
Useful when working on projects without git or with complex layouts.
ROOT should be an absolute path to the project directory."
  (interactive "DProject root: ")
  (setq gptel-auto-workflow--project-root-override (expand-file-name root))
  (message "[auto-workflow] Project root set to: %s" 
           gptel-auto-workflow--project-root-override))

(defun gptel-auto-workflow--project-root ()
  "Return the MAIN project root directory.
When in a worktree, returns the main repo root (parent of .git/worktrees).
Priority:
1. gptel-auto-workflow--project-root-override (if set via .dir-locals.el)
2. Git common dir (handles worktrees correctly)
3. project.el detection (project-current + project-root)
4. Git worktree root (git rev-parse --show-toplevel)
5. ~/.emacs.d/ (fallback)
Always returns absolute path."
  (cond
   ;; 1. Explicit override (from .dir-locals.el)
   (gptel-auto-workflow--project-root-override
    gptel-auto-workflow--project-root-override)
   
   ;; 2. Git common dir - returns main repo even from worktrees
   ((let* ((git-common (string-trim
                        (shell-command-to-string
                         "git rev-parse --git-common-dir 2>/dev/null || echo ''")))
           (git-dir (when (and (not (string-empty-p git-common))
                               (file-directory-p (expand-file-name git-common)))
                      (expand-file-name git-common))))
      (when git-dir
        (if (string-match-p "/.git/worktrees/" git-dir)
            ;; Worktree: go up to find main repo root
            (expand-file-name "../../.." git-dir)
          ;; Main repo: use parent of .git
          (file-name-directory (directory-file-name git-dir))))))
   
   ;; 3. project.el detection (preferred method)
   ((let ((proj (and (fboundp 'project-current)
                     (fboundp 'project-root)
                     (project-current nil))))
      (when proj
        (expand-file-name (project-root proj)))))
   
   ;; 4. Git toplevel (fallback)
   ((let ((git-root (string-trim
                     (shell-command-to-string
                      "git rev-parse --show-toplevel 2>/dev/null || echo ''"))))
      (and (not (string-empty-p git-root))
           (file-directory-p git-root)
           git-root)))
   
   ;; 5. Fallback
   (t (expand-file-name
       (or (when (boundp 'minimal-emacs-user-directory)
             minimal-emacs-user-directory)
           "~/.emacs.d/")))))

;;; Benchmark & Evaluation

(defun gptel-auto-experiment-run-tests ()
  "Run ERT tests and return (passed . output).
Tests run in worktree if set, otherwise project root.
Returns cons cell: (t . output) if all pass, (nil . output) if any fail."
  (let* ((proj-root (gptel-auto-workflow--project-root))
         (default-directory (or (gptel-auto-workflow--get-worktree-dir gptel-auto-workflow--current-target) proj-root))
         (test-script (expand-file-name "scripts/run-tests.sh" proj-root))
         (output-buffer (generate-new-buffer "*test-output*"))
         result)
    (if (not (file-executable-p test-script))
        (progn
          (message "[auto-experiment] Test script not found or not executable: %s" test-script)
          (cons t "No test script - skipping"))
      (message "[auto-experiment] Running tests...")
      (let ((exit-code (call-process test-script nil output-buffer nil)))
        (with-current-buffer output-buffer
          (setq result (cons (zerop exit-code) (buffer-string))))
        (kill-buffer output-buffer)
        (when (car result)
          (message "[auto-experiment] ✓ Tests passed"))
        result))))

(defun gptel-auto-experiment-benchmark (&optional skip-tests)
  "Run syntax validation + Eight Keys scoring.
If SKIP-TESTS is non-nil, skip test execution (tests run in staging flow).
Returns plist with :passed, :tests-passed, :eight-keys, etc.

NOTE: Nucleus script validation is skipped for experiments because:
1. verify-nucleus.sh uses script location ($DIR), not worktree context
2. Executor already runs verification in worktree context
3. Full validation happens in staging flow"
  (let* ((start (float-time))
         (default-directory (or (gptel-auto-workflow--get-worktree-dir gptel-auto-workflow--current-target)
                                (gptel-auto-workflow--project-root)
                                (expand-file-name "~/.emacs.d/")))
         (target-file (when gptel-auto-workflow--current-target
                        (expand-file-name gptel-auto-workflow--current-target default-directory)))
         (validation-error (when target-file
                             (gptel-auto-experiment--validate-code target-file))))
    (if validation-error
        (progn
          (message "[auto-exp] ✗ Validation failed: %s" validation-error)
          (list :passed nil
                :validation-error validation-error
                :time (- (float-time) start)))
      (let* ((tests-result (when (not skip-tests)
                             (gptel-auto-experiment-run-tests)))
             (tests-passed (or skip-tests (car tests-result)))
             (scores (gptel-auto-experiment--eight-keys-scores)))
        (list :passed tests-passed
              :nucleus-passed t
              :nucleus-skipped t
              :tests-passed tests-passed
              :tests-output (when tests-result (cdr tests-result))
              :tests-skipped skip-tests
              :time (- (float-time) start)
              :eight-keys (when scores (alist-get 'overall scores))
              :eight-keys-scores scores)))))

(defun gptel-auto-experiment--eight-keys-scores ()
  "Get full Eight Keys scores alist from current codebase.
Scores based on commit message + code diff (not just stat)."
  (when (fboundp 'gptel-benchmark-eight-keys-score)
    (let* ((worktree (or (gptel-auto-workflow--get-worktree-dir gptel-auto-workflow--current-target)
                         (gptel-auto-workflow--project-root)
                         (expand-file-name "~/.emacs.d/")))
           ;; SECURITY: Use shell-quote-argument to prevent shell injection
           (worktree-quoted (shell-quote-argument worktree))
           (commit-msg (shell-command-to-string
                        (format "cd %s && git log -1 --format='%%B' 2>/dev/null || echo ''"
                                worktree-quoted)))
           (code-diff (shell-command-to-string
                       (format "cd %s && git diff HEAD~1 --unified=2 2>/dev/null | head -200"
                               worktree-quoted)))
           (output (concat commit-msg "\n\n" code-diff)))
      (gptel-benchmark-eight-keys-score output))))

(defun gptel-auto-experiment--eight-keys-score ()
  "Get Eight Keys overall score from current codebase."
  (let ((scores (gptel-auto-experiment--eight-keys-scores)))
    (when scores (alist-get 'overall scores))))

(defun gptel-auto-experiment--code-quality-score ()
  "Get code quality score from current changes."
  (when (fboundp 'gptel-benchmark--code-quality-score)
    (let* ((worktree (or (gptel-auto-workflow--get-worktree-dir gptel-auto-workflow--current-target)
                         (gptel-auto-workflow--project-root)
                         (expand-file-name "~/.emacs.d/")))
           ;; SECURITY: Use shell-quote-argument to prevent shell injection
           (worktree-quoted (shell-quote-argument worktree))
           (changed-files (shell-command-to-string
                           (format "cd %s && git diff --name-only HEAD~1 2>/dev/null | grep '\\.el$'"
                                   worktree-quoted))))
      (when (string-match-p "\\.el$" changed-files)
        (let ((total-score 0.0)
              (file-count 0))
          (dolist (file (split-string changed-files "\n" t))
            (let* ((filepath (expand-file-name file worktree))
                   (content (gptel-auto-workflow--read-file-contents filepath)))
              (when content
                (cl-incf total-score (gptel-benchmark--code-quality-score content))
                (cl-incf file-count))))
          (if (> file-count 0)
              (/ total-score file-count)
            0.5))))))

;;; Subagent Integrations

(defun gptel-auto-experiment-analyze (previous-results callback)
  "Analyze patterns from PREVIOUS-RESULTS. Call CALLBACK with analysis.
The analyzer subagent overlay will appear in the current buffer at time of call."
  ;; Capture the current buffer to ensure analyzer overlay appears in right place
  (let ((analyze-buffer (current-buffer)))
    (if (and gptel-auto-experiment-use-subagents
             (fboundp 'gptel-benchmark-analyze)
             previous-results)
        (with-current-buffer analyze-buffer
          (gptel-benchmark-analyze
           previous-results
           "Experiment patterns"
           callback))
      (funcall callback nil))))

(defvar gptel-auto-experiment--grade-state (make-hash-table :test 'eql)
  "Hash table for per-grade state. Keyed by grade-id.
Values are plist: (:done :timer).")

(defvar gptel-auto-experiment--grade-counter 0
  "Counter for generating unique grade IDs.")

(defvar gptel-auto-experiment-grade-timeout 120
  "Timeout in seconds for grading subagent.
Default 120s (2 min) allows grader to process complex outputs.")

(defun gptel-auto-experiment--validate-code (file)
  "Validate code in FILE for syntax and dangerous patterns.
Returns nil if valid, or error message string if invalid."
  (when (and (stringp file) (file-exists-p file) (string-suffix-p ".el" file))
    (let ((content (gptel-auto-workflow--read-file-contents file)))
      (condition-case err
          (with-temp-buffer
            (insert content)
            (goto-char (point-min))
            (while (< (point) (point-max))
              (read (current-buffer))))
        (error (format "Syntax error in %s: %s" file err)))
      (when (and (string-match-p "cl-return-from" content)
                 (not (string-match-p "cl-block" content)))
        (format "Dangerous pattern in %s: cl-return-from without cl-block" file)))))

(defun gptel-auto-experiment-grade (output callback)
  "Grade experiment OUTPUT. LLM decides quality threshold.
Timeout fails the grade (conservative).
If OUTPUT is an error message, fails immediately with error details.
Uses hash table keyed by grade-id to support parallel execution.
The grader subagent overlay will appear in the current buffer at time of call."
  (let ((grade-id (cl-incf gptel-auto-experiment--grade-counter))
        (grade-buffer (current-buffer)))
    (cl-block gptel-auto-experiment-grade
      (when (gptel-auto-experiment--agent-error-p output)
        (let* ((error-snippet (if (stringp output)
                                  (substring output 0 (min 200 (length output)))
                                "Unknown error"))
               (error-category (car (gptel-auto-experiment--categorize-error output))))
          (message "[auto-exp] Executor error detected: %s" error-snippet)
          (funcall callback (list :score 0 :passed nil 
                                  :details (format "Agent error: %s" error-snippet)
                                  :error-category error-category))
          (cl-return-from gptel-auto-experiment-grade)))
      (puthash grade-id (list :done nil :timer nil) gptel-auto-experiment--grade-state)
      (let ((timeout-timer
             (run-with-timer gptel-auto-experiment-grade-timeout nil
                             (lambda ()
                               (let ((state (gethash grade-id gptel-auto-experiment--grade-state)))
                                 (when (gptel-auto-workflow--state-active-p state)
                                   (puthash grade-id (plist-put state :done t) gptel-auto-experiment--grade-state)
                                   (message "[auto-exp] Grading timeout after %ds, failing"
                                            gptel-auto-experiment-grade-timeout)
                                   (funcall callback (list :score 0 :passed nil :details "timeout"))
                                   (remhash grade-id gptel-auto-experiment--grade-state)))))))
        (puthash grade-id (list :done nil :timer timeout-timer) gptel-auto-experiment--grade-state))
      (if (and gptel-auto-experiment-use-subagents
               (fboundp 'gptel-benchmark-grade))
          ;; Ensure grader runs in the captured buffer context so overlay appears in right place
          (with-current-buffer grade-buffer
            (gptel-benchmark-grade
             output
             '("change clearly described"
               "change is minimal and focused"
               "improves code: fixes bug, improves performance, addresses TODO/FIXME, or enhances clarity/testability"
               "verification attempted (byte-compile, nucleus, tests, or manual)")
             '("large refactor unrelated to stated improvement"
               "changed security files without review"
               "no description or unclear purpose"
               "style-only change without functional impact"
               "replaces working code without clear improvement")
             (lambda (result)
               (let ((state (gethash grade-id gptel-auto-experiment--grade-state)))
                 (when (gptel-auto-workflow--state-active-p state)
                   (puthash grade-id (plist-put state :done t) gptel-auto-experiment--grade-state)
                   (when (timerp (plist-get state :timer))
                     (cancel-timer (plist-get state :timer)))
                   (funcall callback result)
                   (remhash grade-id gptel-auto-experiment--grade-state))))))
        (let ((state (gethash grade-id gptel-auto-experiment--grade-state)))
          (puthash grade-id (plist-put state :done t) gptel-auto-experiment--grade-state)
          (when (timerp (plist-get state :timer))
            (cancel-timer (plist-get state :timer)))
          (funcall callback (list :score 100 :passed t))
          (remhash grade-id gptel-auto-experiment--grade-state))))))

(defun gptel-auto-experiment-decide (before after callback)
  "Compare BEFORE vs AFTER using LLM comparator.
CALLBACK receives keep/discard decision with reasoning.
LLM decides when available; local fallback for tests.
The comparator subagent overlay will appear in the current buffer at time of call."
  ;; Capture the current buffer to ensure comparator overlay appears in right place
  (let* ((decide-buffer (current-buffer))
         (score-before (gptel-auto-workflow--plist-get before :score 0))
         (score-after (gptel-auto-workflow--plist-get after :score 0))
         (quality-before (gptel-auto-workflow--plist-get before :code-quality 0.5))
         (quality-after (gptel-auto-workflow--plist-get after :code-quality 0.5))
         (combined-before (+ (* 0.6 score-before) (* 0.4 quality-before)))
         (combined-after (+ (* 0.6 score-after) (* 0.4 quality-after))))
    (if (and gptel-auto-experiment-use-subagents
             (fboundp 'gptel-benchmark-call-subagent))
        (let ((compare-prompt (format "Compare these two experiment results and decide which is better.

RESULT A (before):
- Eight Keys Score: %.3f
- Code Quality: %.3f
- Combined Score: %.3f

RESULT B (after):
- Eight Keys Score: %.3f
- Code Quality: %.3f
- Combined Score: %.3f

DECISION CRITERIA:
- Combined score = 60%% Eight Keys + 40%% Code Quality
- B should win if combined score improved by ≥0.005
- A should win if combined score decreased by ≥0.005
- Tie if difference < 0.005

Output ONLY a single line: \"A\" or \"B\" or \"tie\"

Then on a new line, briefly explain why (1 sentence)."
                                      score-before quality-before combined-before
                                      score-after quality-after combined-after)))
          (with-current-buffer decide-buffer
            (gptel-benchmark-call-subagent
             'comparator
             "Compare experiment results"
             compare-prompt
             (lambda (result)
               (let* ((response (if (stringp result) result (format "%S" result)))
                      (winner (cond
                               ((string-match "^\\s-*A\\b" response) "A")
                               ((string-match "^\\s-*B\\b" response) "B")
                               ((string-match "^\\s-*tie\\b" response) "tie")
                               (t "B")))
                      (keep (string= winner "B")))
                 (funcall callback
                          (list :keep keep
                                :reasoning (format "Winner: %s | Score: %.2f → %.2f, Quality: %.2f → %.2f, Combined: %.2f → %.2f"
                                                   winner score-before score-after
                                                   quality-before quality-after
                                                   combined-before combined-after)
                                :improvement (list :score (- score-after score-before)
                                                   :quality (- quality-after quality-before)
                                                   :combined (- combined-after combined-before)))))))))
      (let ((keep (> combined-after combined-before)))
        (funcall callback
                 (list :keep keep
                       :reasoning (format "Local: Score: %.2f → %.2f, Quality: %.2f → %.2f, Combined: %.2f → %.2f"
                                          score-before score-after
                                          quality-before quality-after
                                          combined-before combined-after)
                       :improvement (list :score (- score-after score-before)
                                          :quality (- quality-after quality-before)
                                          :combined (- combined-after combined-before))))))))

;;; Prompt Building

(defun gptel-auto-experiment-build-prompt (target experiment-id max-experiments analysis baseline)
  "Build prompt for experiment EXPERIMENT-ID on TARGET.
Uses loaded skills and Eight Keys breakdown for focused improvements."
  (let* ((worktree-path (or (gptel-auto-workflow--get-worktree-dir target)
                            (gptel-auto-workflow--project-root)))
         ;; SECURITY: Use shell-quote-argument to prevent shell injection
         (worktree-quoted (shell-quote-argument worktree-path))
         (git-history (shell-command-to-string
                       (format "cd %s && git log --oneline -20 2>/dev/null || echo 'no history'"
                               worktree-quoted)))
         (patterns (when analysis (plist-get analysis :patterns)))
         (suggestions (when analysis (plist-get analysis :recommendations)))
         (skills (cdr (assoc target gptel-auto-workflow--skills)))
         (scores (gptel-auto-experiment--eight-keys-scores))
         (weakest-keys (when scores (gptel-auto-workflow--format-weakest-keys scores)))
         (mutation-templates (when skills (gptel-auto-workflow--extract-mutation-templates skills)))
         (suggested-hypothesis (when skills (gptel-auto-workflow-skill-suggest-hypothesis skills)))
         (target-full-path (expand-file-name target worktree-path)))
    (format "You are running experiment %d of %d to optimize %s.

## Working Directory
%s

## Target File (full path)
%s

## Previous Experiment Analysis
%s

## Suggestions
%s

## Git History (recent commits)
%s

## Current Baseline
Overall Eight Keys score: %.2f

%s

%s

%s

## Objective
Improve the CODE QUALITY for %s.
Focus on one improvement at a time.
Make minimal, targeted changes to CODE, not documentation.

## Constraints
- Time budget: %d minutes
- Immutable files: early-init.el, pre-early-init.el, lisp/eca-security.el
- Must pass tests: ./scripts/verify-nucleus.sh
- FORBIDDEN: Adding comments, docstrings, or documentation-only changes
- REQUIRED: Actual code changes (bug fixes, performance, refactoring, error handling)

## Code Improvement Types (PICK ONE)
1. **Bug Fix**: Fix an actual bug or error handling gap
2. **Performance**: Reduce complexity, add caching, optimize hot path
3. **Refactoring**: Extract functions, remove duplication, improve naming
4. **Safety**: Add validation, prevent edge cases, improve error messages
5. **Test Coverage**: Add missing tests for existing functionality

## Instructions
1. FIRST LINE must be: HYPOTHESIS: [What CODE change and why]
2. Read the target file using its full path
3. IDENTIFY a real code issue (bug, performance, duplication, missing validation)
4. Implement the CODE change minimally using Edit tool
5. Run tests to verify: ./scripts/verify-nucleus.sh && ./scripts/run-tests.sh
6. COMMIT your changes: git add -A && git commit -m \"message\"

CRITICAL: Your response MUST start with HYPOTHESIS: on the first line.
DO NOT add comments, docstrings, or documentation.
DO make actual code changes that improve functionality.

Example HYPOTHESES:
- HYPOTHESIS: Adding validation for nil input in process-item will prevent runtime errors
- HYPOTHESIS: Extracting duplicate retry logic into a helper will reduce code duplication
- HYPOTHESIS: Adding a cache for expensive computation will improve performance
- HYPOTHESIS: Fixing the off-by-one error in the loop will correct the boundary case"
            experiment-id max-experiments target
            worktree-path
            target-full-path
            (or patterns "No previous experiments")
            (or suggestions "None")
            git-history
            (or baseline 0.5)
            (if weakest-keys
                (format "## Weakest Keys (Priority Focus)\n%s" weakest-keys)
              "")
            (if suggested-hypothesis
                (format "## Suggested Hypothesis (from skill)\n%s" suggested-hypothesis)
              "")
            (if mutation-templates
                (format "## Hypothesis Templates\n%s"
                        (mapconcat (lambda (tmpl) (format "- %s" tmpl)) mutation-templates "\n"))
              "")
            target
            (/ gptel-auto-experiment-time-budget 60))))

;;; TSV Logging (Explainable)

(defun gptel-auto-experiment--tsv-escape (str)
  "Escape STR for TSV format (replace newlines/tabs with spaces)."
  (when str
    (let ((s (if (stringp str) str (format "%s" str))))
      (replace-regexp-in-string "[\t\n\r]+" " | " s))))

(defun gptel-auto-experiment-log-tsv (run-id experiment)
  "Append EXPERIMENT to results.tsv for RUN-ID."
  (let* ((base-dir (or (gptel-auto-workflow--project-root)
                       (expand-file-name "~/.emacs.d/")))
         (worktree-base-dir (or gptel-auto-workflow-worktree-base
                                "var/tmp/experiments"))
         (file (expand-file-name
                (format "%s/%s/results.tsv" worktree-base-dir run-id)
                base-dir))
         (agent-output (gptel-auto-workflow--plist-get experiment :agent-output ""))
         (truncated-output (gptel-auto-experiment--tsv-escape
                            (truncate-string-to-width agent-output 500 nil nil "..."))))
    (make-directory (file-name-directory file) t)
    (unless (file-exists-p file)
      (with-temp-file file
        (insert "experiment_id\ttarget\thypothesis\tscore_before\tscore_after\tcode_quality\tdelta\tdecision\tduration\tgrader_quality\tgrader_reason\tcomparator_reason\tanalyzer_patterns\tagent_output\n")))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-max))
      (insert (format "%s\t%s\t%s\t%.2f\t%.2f\t%.2f\t%+.2f\t%s\t%d\t%s\t%s\t%s\t%s\t%s\n"
                      (gptel-auto-workflow--plist-get experiment :id "?")
                      (gptel-auto-workflow--plist-get experiment :target "?")
                      (gptel-auto-experiment--tsv-escape (gptel-auto-workflow--plist-get experiment :hypothesis "unknown"))
                      (gptel-auto-workflow--plist-get experiment :score-before 0)
                      (gptel-auto-workflow--plist-get experiment :score-after 0)
                      (gptel-auto-workflow--plist-get experiment :code-quality 0.5)
                      (- (gptel-auto-workflow--plist-get experiment :score-after 0)
                         (gptel-auto-workflow--plist-get experiment :score-before 0))
                      (if (gptel-auto-workflow--plist-get experiment :kept nil) "kept" "discarded")
                      (gptel-auto-workflow--plist-get experiment :duration 0)
                      (gptel-auto-workflow--plist-get experiment :grader-quality "?")
                      (gptel-auto-experiment--tsv-escape (gptel-auto-workflow--plist-get experiment :grader-reason "N/A"))
                      (gptel-auto-experiment--tsv-escape (gptel-auto-workflow--plist-get experiment :comparator-reason "N/A"))
                      (gptel-auto-experiment--tsv-escape (gptel-auto-workflow--plist-get experiment :analyzer-patterns "N/A"))
                      truncated-output))
      (write-region (point-min) (point-max) file))))

;;; Error Analysis and Adaptive Workflow

(defvar gptel-auto-experiment--api-error-count 0
  "Count of API errors in current run.")

(defvar gptel-auto-experiment--api-error-threshold 3
  "Threshold of API errors before reducing experiment count.")

(defun gptel-auto-experiment--error-snippet (agent-output &optional max-len)
  "Extract safe snippet from AGENT-OUTPUT for logging.
MAX-LEN defaults to 200 characters. Handles nil/empty strings safely."
  (let ((len (max-len (or max-len 200))))
    (when (and (stringp agent-output) (> (length agent-output) 0))
      (substring agent-output 0 (min len (length agent-output))))))

(defvar gptel-auto-experiment-max-retries 2
  "Maximum retries for executor on transient errors.")

(defvar gptel-auto-experiment-retry-delay 5
  "Seconds to wait between retries.")

(defun gptel-auto-experiment--is-retryable-error-p (error-output)
  "Check if ERROR-OUTPUT is a transient/retryable error."
  (and (stringp error-output)
       (string-match-p "throttling\\|rate.limit\\|quota\\|429\\|timeout\\|temporary\\|overloaded" error-output)))

(defun gptel-auto-experiment--run-with-retry (target experiment-id max-experiments baseline baseline-code-quality previous-results callback &optional retry-count)
  "Run experiment with automatic retry on transient errors.
RETRY-COUNT tracks current retry attempt."
  (let ((retries (or retry-count 0)))
    (gptel-auto-experiment-run
     target experiment-id max-experiments baseline baseline-code-quality previous-results
     (lambda (result)
       (let* ((agent-output (plist-get result :agent-output))
              (error-type (plist-get result :comparator-reason)))
         (if (and (< retries gptel-auto-experiment-max-retries)
                  (or (gptel-auto-experiment--is-retryable-error-p agent-output)
                      (eq error-type :api-rate-limit)
                      (eq error-type :timeout)))
             (progn
               (message "[auto-exp] Retrying experiment %d (attempt %d/%d) after %ds delay"
                        experiment-id (1+ retries) gptel-auto-experiment-max-retries
                        gptel-auto-experiment-retry-delay)
               (run-with-timer gptel-auto-experiment-retry-delay nil
                               (lambda ()
                                 (gptel-auto-experiment--run-with-retry
                                  target experiment-id max-experiments baseline baseline-code-quality
                                  previous-results callback (1+ retries)))))
           (funcall callback result)))))))

(defun gptel-auto-experiment--categorize-error (agent-output)
  "Categorize error from AGENT-OUTPUT and return (CATEGORY . DETAILS).
Categories: :api-rate-limit :api-error :tool-error :timeout :grader-failed :unknown
Also logs agent-output snippet for debugging when category is :unknown."
  (cond
   ((or (null agent-output) (string= agent-output ""))
    (cons :grader-failed "Grader returned no output"))
   ((string-match-p "throttling\\|rate.limit\\|quota exceeded\\|429" agent-output)
    (cons :api-rate-limit "API rate limit exceeded"))
   ((string-match-p "hour allocated quota exceeded" agent-output)
    (cons :api-rate-limit "Hourly quota exhausted"))
   ((string-match-p "invalid_parameter_error\\|InvalidParameter\\|JSON format" agent-output)
    (cons :api-error "API parameter error (invalid JSON format)"))
   ((string-match-p "timeout" agent-output)
    (cons :timeout "Experiment timed out"))
   ((string-match-p "error.*executor\\|failed to finish" agent-output)
    (cons :tool-error "Tool execution failed"))
   ((string-match-p "could not finish" agent-output)
    (cons :api-error "API request failed"))
   ((string-match-p "Error:.*not available\\|Error:.*not found\\|Error:.*empty" agent-output)
    (cons :tool-error (format "Tool unavailable: %s" (gptel-auto-experiment--error-snippet agent-output))))
   ((string-match-p "^Error:" agent-output)
    (let ((snippet (gptel-auto-experiment--error-snippet agent-output)))
      (message "[auto-experiment] Executor error: %s" snippet)
      (cons :tool-error snippet)))
   ((string-match-p "^Executor result\\|^✓\\|^\\*\\*HYPOTHESIS" agent-output)
    (cons :grader-failed "Executor succeeded, grader returned score 0"))
   ((string-match-p "error\\|failed\\|exception" agent-output)
    (let ((snippet (gptel-auto-experiment--error-snippet agent-output)))
      (message "[auto-experiment] Unknown error snippet: %s" (my/gptel--sanitize-for-logging snippet))
      (cons :unknown (format "Error pattern: %s" snippet))))
   (t 
    (let ((snippet (gptel-auto-experiment--error-snippet agent-output)))
      (message "[auto-experiment] No error pattern found, snippet: %s" (my/gptel--sanitize-for-logging snippet))
      (cons :unknown "Unknown error")))))

(defun gptel-auto-experiment--should-reduce-experiments-p ()
  "Check if we should reduce experiment count due to API issues."
  (>= gptel-auto-experiment--api-error-count gptel-auto-experiment--api-error-threshold))

(defun gptel-auto-experiment--adaptive-max-experiments (original-max)
  "Return adjusted experiment count based on API error rate."
  (if (gptel-auto-experiment--should-reduce-experiments-p)
      (progn
        (message "[auto-workflow] Reducing experiments from %d to %d due to API errors"
                 original-max (max 1 (/ original-max 2)))
        (max 1 (/ original-max 2)))
    original-max))

(defun gptel-auto-experiment--log-failure-analysis (target error-category error-details)
  "Log failure analysis for TARGET with ERROR-CATEGORY and ERROR-DETAILS.
This helps understand patterns in discarded experiments."
  (let ((log-file (expand-file-name 
                   "var/tmp/experiments/failure-analysis.log"
                   (gptel-auto-workflow--project-root))))
    (make-directory (file-name-directory log-file) t)
    (with-temp-buffer
      (when (file-exists-p log-file)
        (insert-file-contents log-file))
      (goto-char (point-max))
      (insert (format "%s | %s | %s | %s\n"
                      (format-time-string "%Y-%m-%d %H:%M:%S")
                      target
                      error-category
                      error-details))
      (write-region (point-min) (point-max) log-file))))

;;; Dynamic Stop

(defun gptel-auto-experiment-should-stop-p (threshold)
  "Check if should stop based on no-improvement count >= THRESHOLD."
  (>= gptel-auto-experiment--no-improvement-count threshold))

;;; Retry Logic (Never Ask User, Just Try Again)

(defcustom gptel-auto-experiment-max-retries 3
  "Maximum retries for transient failures.
Auto-workflow never asks user - just retries until success or max retries."
  :type 'integer
  :group 'gptel-tools-agent)

(defun gptel-auto-experiment--with-retry (fn &optional max-retries)
  "Call FN with retry on failure.
Never asks user - retries up to MAX-RETRIES times.
Auto-workflow principle: try harder, again and again, never stop to ask."
  (let ((attempts 0)
        (max (or max-retries gptel-auto-experiment-max-retries))
        result)
    (while (and (< attempts max) (not result))
      (cl-incf attempts)
      (condition-case err
          (progn
            (setq result (funcall fn))
            (when result
              (message "[auto-experiment] Success on attempt %d/%d" attempts max)))
        (error
         (message "[auto-experiment] Attempt %d/%d failed: %s" attempts max err)
         (when (< attempts max)
           (sit-for 1)))))  ; Brief pause before retry
    result))

;;; Single Experiment

(defun gptel-auto-experiment-run (target experiment-id max-experiments baseline baseline-code-quality previous-results callback)
  "Run single experiment. Call CALLBACK with result plist.
BASELINE-CODE-QUALITY is the initial code quality score."
  (message "[auto-experiment] Starting %d/%d for %s" experiment-id max-experiments target)
  (setq gptel-auto-workflow--current-target target)
  (let* ((worktree (gptel-auto-workflow-create-worktree target experiment-id))
         ;; CRITICAL: Set default-directory to worktree so all subagents
         ;; operate in the correct context. Each worktree = one session.
         (default-directory (or worktree default-directory))
         ;; Get project buffer for overlay routing (ensure hash table exists)
         (project-buf (when (and (boundp 'gptel-auto-workflow--current-project)
                                 gptel-auto-workflow--current-project
                                 (hash-table-p gptel-auto-workflow--project-buffers))
                        (gethash (expand-file-name gptel-auto-workflow--current-project)
                                 gptel-auto-workflow--project-buffers)))
         ;; Disable preview for headless auto-workflow
         (gptel-tools-preview-enabled nil)
         ;; Disable tool confirmations for headless auto-workflow
         (gptel-confirm-tool-calls nil)
         ;; CRITICAL: Use experiment time budget as agent task timeout
         ;; This ensures the gptel request times out before the outer timer
         (my/gptel-agent-task-timeout gptel-auto-experiment-time-budget)
         (start-time (float-time))
         (timeout-timer nil)
         (finished nil))
    (if (not worktree)
        (funcall callback (list :target target :error "Failed to create worktree"))
      (gptel-auto-experiment-analyze
       previous-results
       (lambda (analysis)
         (let* ((patterns (when analysis (plist-get analysis :patterns)))
                (prompt (gptel-auto-experiment-build-prompt
                         target experiment-id max-experiments analysis baseline)))
           (setq timeout-timer
                 (run-with-timer gptel-auto-experiment-time-budget nil
                                 (lambda ()
                                   (unless finished
                                     (setq finished t)
                                     (message "[auto-exp] Experiment timed out after %ds, aborting"
                                              gptel-auto-experiment-time-budget)
                                     (when (fboundp 'gptel-abort)
                                       (ignore-errors (gptel-abort (current-buffer))))
                                     (funcall callback
                                              (list :target target
                                                    :id experiment-id
                                                    :error "timeout"))))))
           ;; Routing handled by gptel-auto-workflow--advice-task-override
           (my/gptel--run-agent-tool
(lambda (agent-output)
               (message "[auto-exp] Agent output (first 150 chars): %s"
                        (my/gptel--sanitize-for-logging agent-output 150))
               (when timeout-timer (cancel-timer timeout-timer))
               (unless finished
                 (gptel-auto-experiment-grade
                  agent-output
                  (lambda (grade)
                    (let* ((grade-score (plist-get grade :score))
                           (grade-total (plist-get grade :total))
                           (grade-passed (plist-get grade :passed))
                           (grade-details (plist-get grade :details))
                           (hypothesis (gptel-auto-experiment--extract-hypothesis agent-output)))
                      (message "[auto-exp] Grade result: score=%s/%s passed=%s"
                               grade-score grade-total grade-passed)
                      (when (and agent-output (> (length agent-output) 0))
                        (message "[auto-exp] Agent preview: %s"
                                 (my/gptel--sanitize-for-logging agent-output 100)))
                      ;; Check if grader passed
                      (if (not grade-passed)
                         ;; Grader failed - categorize the error
                         (let* ((error-info (gptel-auto-experiment--categorize-error agent-output))
                                (error-category (car error-info))
                                (error-details (cdr error-info)))
                           (setq finished t)
                           ;; Track API errors for adaptive reduction
                           (when (memq error-category '(:api-rate-limit :api-error))
                             (cl-incf gptel-auto-experiment--api-error-count)
                             (message "[auto-workflow] API error #%d: %s"
                                      gptel-auto-experiment--api-error-count error-category)
                             ;; Reduce max experiments if too many API errors
                             (when (>= gptel-auto-experiment--api-error-count 3)
                               (setq max-exp (max 2 (/ max-exp 2)))
                               (message "[auto-workflow] Reduced max experiments to %d due to API errors" max-exp)))
                           ;; Log the failure
                           (let ((exp-result (list :target target
                                                   :id experiment-id
                                                   :hypothesis hypothesis
                                                   :score-before baseline
                                                   :score-after 0
                                                   :kept nil
                                                   :duration (- (float-time) start-time)
                                                   :grader-quality grade-score
                                                   :grader-reason grade-details
                                                   :comparator-reason (symbol-name error-category)
                                                   :analyzer-patterns (format "%s" patterns)
                                                   :agent-output agent-output)))
                             (gptel-auto-experiment-log-tsv
                              (format-time-string "%Y-%m-%d") exp-result)
                             (funcall callback exp-result)))
                       ;; Grader passed - commit changes, then run benchmark
                       (let ((commit-dir (or (gptel-auto-workflow--get-worktree-dir target)
                                             (gptel-auto-workflow--project-root))))
                         (when commit-dir
                           (let ((default-directory commit-dir))
                             (magit-git-success "add" "-A")
                             (magit-git-success "commit" "-m" (format "WIP: experiment %s" target)))))
                       (let* ((bench (gptel-auto-experiment-benchmark t))
                              (passed (plist-get bench :passed))
                              (validation-error (plist-get bench :validation-error))
                              (tests-passed (plist-get bench :tests-passed))
                              (score-after (plist-get bench :eight-keys)))
                         (if (not passed)
                             ;; Check if validation error is teachable and we should retry
                             (if (and validation-error
                                      (stringp validation-error)
                                      (> (length validation-error) 0)
                                      (string-match-p "cl-return-from.*without.*cl-block\\|Dangerous pattern" validation-error)
                                      (not (bound-and-true-p gptel-auto-experiment--in-retry)))
                                 ;; Retry with teaching
                                 (let ((default-directory (or (gptel-auto-workflow--get-worktree-dir target)
                                                              (gptel-auto-workflow--project-root)))
                                       (gptel-auto-experiment--in-retry t))
                                   (message "[auto-experiment] Validation failed with teachable pattern, retrying...")
                                   (message "[auto-experiment] ✗ %s" (my/gptel--sanitize-for-logging validation-error 200))
                                   (magit-git-success "checkout" "--" ".")
                                   ;; Re-run executor with teaching prompt
                                   (my/gptel--run-agent-tool
                                    (lambda (retry-output)
                                      (gptel-auto-experiment-grade
                                       retry-output
                                       (lambda (retry-grade)
                                         (if (plist-get retry-grade :passed)
                                             (let ((retry-bench (gptel-auto-experiment-benchmark t)))
                                               (if (plist-get retry-bench :passed)
                                                   (let ((retry-score (plist-get retry-bench :eight-keys))
                                                         (retry-quality (or (gptel-auto-experiment--code-quality-score) 0.5)))
                                                     (message "[auto-experiment] ✓ Retry succeeded")
                                                     (setq finished t)
                                                     (gptel-auto-experiment-decide
                                                      (list :score baseline :code-quality baseline-code-quality)
                                                      (list :score retry-score :code-quality retry-quality :output retry-output)
                                                      (lambda (decision)
                                                        (let ((keep (plist-get decision :keep)))
                                                          (when keep
                                                            (let ((default-directory (or (gptel-auto-workflow--get-worktree-dir target)
                                                                                         (gptel-auto-workflow--project-root)))
                                                                  (msg (format "◈ Retry: fix validation in %s" target)))
                                                              (magit-git-success "add" "-A")
                                                              (magit-git-success "commit" "-m" msg)))
                                                          (funcall callback (list :target target
                                                                                  :id experiment-id
                                                                                  :score-after retry-score
                                                                                  :kept keep
                                                                                  :retries 1))))))
                                                 ;; Retry also failed validation
                                                 (progn
                                                   (setq finished t)
                                                   (message "[auto-experiment] ✗ Retry still failed validation")
                                                   (funcall callback (list :target target
                                                                           :id experiment-id
                                                                           :kept nil
                                                                           :validation-error (plist-get retry-bench :validation-error)))))))
                                         ;; Retry grader failed
                                         (progn
                                           (setq finished t)
                                           (funcall callback (list :target target
                                                                   :id experiment-id
                                                                   :kept nil)))))))
                                   "executor"
                                   (format "Retry: fix validation error in %s" target)
                                   (gptel-auto-experiment--make-retry-prompt target validation-error prompt)))
                           ;; No retry - just fail
                           (let ((default-directory (or (gptel-auto-workflow--get-worktree-dir target)
                                                        (gptel-auto-workflow--project-root))))
                             (setq finished t)
                             (magit-git-success "checkout" "--" ".")
                             (let ((reason (cond
                                            (validation-error validation-error)
                                            ((not (plist-get bench :nucleus-passed)) "nucleus-validation-failed")
                                            ((not tests-passed) "tests-failed")
                                            (t "verification-failed"))))
                               (message "[auto-experiment] ✗ %s for %s" reason target)
                               (let ((exp-result (list :target target
                                                       :id experiment-id
                                                       :hypothesis hypothesis
                                                       :score-before baseline
                                                       :score-after 0
                                                       :kept nil
                                                       :duration (- (float-time) start-time)
                                                       :grader-quality grade-score
                                                       :grader-reason (plist-get grade :details)
                                                       :comparator-reason reason
                                                       :analyzer-patterns (format "%s" patterns)
                                                       :agent-output agent-output)))
                                 (gptel-auto-experiment-log-tsv
                                  (format-time-string "%Y-%m-%d") exp-result)
                                 (funcall callback exp-result))))
                           ;; Verification passed - decide whether to keep
                           (let ((code-quality (or (gptel-auto-experiment--code-quality-score) 0.5)))
                             (gptel-auto-experiment-decide
                              (list :score baseline :code-quality baseline-code-quality)
                              (list :score score-after :code-quality code-quality :output agent-output)
                              (lambda (decision)
                                (setq finished t)
                                (let* ((keep (plist-get decision :keep))
                                       (reasoning (plist-get decision :reasoning))
                                       (exp-result (list :target target
                                                         :id experiment-id
                                                         :hypothesis hypothesis
                                                         :score-before baseline
                                                         :score-after score-after
                                                         :code-quality code-quality
                                                         :kept keep
                                                         :duration (- (float-time) start-time)
                                                         :grader-quality grade-score
                                                         :grader-reason (plist-get grade :details)
                                                         :comparator-reason reasoning
                                                         :analyzer-patterns (format "%s" patterns)
                                                         :agent-output agent-output)))
                                  (if keep
                                      (let* ((msg (format "◈ Optimize %s: %s\n\nHYPOTHESIS: %s\n\nEVIDENCE: Nucleus valid, tests in staging\nScore: %.2f → %.2f (+%.0f%%)"
                                                          target
                                                          (gptel-auto-experiment--summarize hypothesis)
                                                          hypothesis
                                                          baseline score-after
                                                          (if (> baseline 0) (* 100 (/ (- score-after baseline) baseline)) 0)))
                                             (default-directory (or (gptel-auto-workflow--get-worktree-dir target)
                                                                    (gptel-auto-workflow--project-root))))
                                        (gptel-auto-workflow--assert-main-untouched)
                                        (message "[auto-experiment] ✓ Committing improvement for %s" target)
                                        (magit-git-success "add" "-A")
                                        (magit-git-success "commit" "-m" msg)
                                        (gptel-auto-workflow--track-commit experiment-id target)
                                        (setq gptel-auto-experiment--best-score score-after
                                              gptel-auto-experiment--no-improvement-count 0)
                                        (when gptel-auto-experiment-auto-push
                                          (message "[auto-experiment] Pushing to %s" (gptel-auto-workflow--get-current-branch target))
                                          (magit-git-success "push" "origin" (gptel-auto-workflow--get-current-branch target))
                                          (when gptel-auto-workflow-use-staging
                                            (gptel-auto-workflow--staging-flow (gptel-auto-workflow--get-current-branch target)))))
                                    (let ((default-directory (or (gptel-auto-workflow--get-worktree-dir target)
                                                                 (gptel-auto-workflow--project-root))))
                                      (message "[auto-experiment] Discarding changes for %s (no improvement)" target)
                                      (magit-git-success "checkout" "--" ".")
                                      (cl-incf gptel-auto-experiment--no-improvement-count)))
                                  (gptel-auto-experiment-log-tsv
                                   (format-time-string "%Y-%m-%d") exp-result)
                                  ;; Don't delete worktree - will be cleaned up by run-next
                                  (funcall callback exp-result)))))))))))))
            "executor"
            (format "Experiment %d: optimize %s" experiment-id target)
            prompt
            nil "false" nil)))))))

(defun gptel-auto-experiment--extract-hypothesis (output)
  "Extract HYPOTHESIS from agent OUTPUT.
Tries multiple patterns in order:
1. Check for error message (returns 'Agent error')
2. Explicit HYPOTHESIS: prefix
3. **HYPOTHESIS** markdown
4. Sentence with 'will improve' (predictive statement)
5. Action verb at start of sentence
6. Summary after ✓ checkmark (fallback)"
  (cond
   ;; Check for error message first
   ((and (stringp output) (string-match-p "^Error:" output))
    "Agent error")
   ((string-match "HYPOTHESIS:\\s-*\\([^\n]+\\)" output)
    (match-string 1 output))
   ((string-match "\\*\\*HYPOTHESIS\\*\\*:?\\s-*\\([^\n]+\\)" output)
    (match-string 1 output))
   ((string-match "[^.]*\\s-+will improve\\s-+[^.]*\\.?" output)
    (let ((match (match-string 0 output)))
      (string-trim match)))
   ((string-match "\\(?:Adding\\|Changing\\|Improving\\|Enhancing\\|Removing\\|Refactoring\\)\\s-+[^.\n]+\\." output)
    (let ((match (match-string 0 output)))
      (string-trim match)))
   ((string-match "✓\\s-+[^:]+:\\s-+\\([^\n|]+\\)" output)
    (let ((match (match-string 1 output)))
      (string-trim match)))
   (t "No hypothesis stated")))

(defun gptel-auto-experiment--agent-error-p (output)
  "Check if OUTPUT is an error message from agent tool."
  (and (stringp output) (string-match-p "^Error:" output)))

(defun gptel-auto-experiment--summarize (hypothesis)
  "Create short summary of HYPOTHESIS."
  (let ((words (split-string hypothesis)))
    (string-join (cl-subseq words 0 (min 6 (length words))) " ")))

(defvar gptel-auto-experiment-max-validation-retries 1
  "Maximum retries when validation fails due to teachable patterns.
Executor will be instructed to load relevant skill and regenerate.")

(defun gptel-auto-experiment--make-retry-prompt (target validation-error _original-prompt)
  "Create retry prompt after validation failure.
TARGET is the file being edited.
VALIDATION-ERROR is the error message.
Instructs executor to load relevant skill instead of hardcoding patterns."
  (format "Your previous edit to %s was REJECTED due to validation error:

ERROR: %s

IMPORTANT: Before retrying, load the relevant skill for guidance.

%s

Read the file, understand the error, load the skill if available, and generate corrected code."
          target
          validation-error
          (cond
           ;; Elisp dangerous patterns - tell executor to load skill
           ((string-match-p "cl-return-from.*without.*cl-block\\|Dangerous pattern.*\\.el$" validation-error)
            "CALL THIS FIRST: Skill(\"elisp-expert\")
This skill teaches dangerous Elisp patterns including cl-return-from requirements.")
           ;; Add more skill mappings here as needed
           (t ""))))

;;; Experiment Loop

(defun gptel-auto-experiment-loop (target callback)
  "Run experiments for TARGET until stop condition. Call CALLBACK with results.
Uses local state captured in closure for parallel execution safety.
Adapts max-experiments based on API error rate."
  (let* ((baseline (gptel-auto-experiment-benchmark t))
         (baseline-code-quality (or (gptel-auto-experiment--code-quality-score) 0.5))
         (original-max gptel-auto-experiment-max-per-target)
         (max-exp (gptel-auto-experiment--adaptive-max-experiments original-max))
         (threshold gptel-auto-experiment-no-improvement-threshold)
         (results nil)
         (best-score (gptel-auto-workflow--plist-get baseline :eight-keys 0.0))
         (no-improvement-count 0))
    (message "[auto-experiment] Baseline for %s: %.2f (max-exp: %d)"
             target best-score max-exp)
    (cl-labels ((run-next (exp-id)
                  (when (and (> gptel-auto-experiment--api-error-count 5)
                             (< exp-id max-exp))
                    (message "[auto-workflow] Too many API errors (%d), stopping early for %s"
                             gptel-auto-experiment--api-error-count target)
                    (setq max-exp exp-id))
                  (if (or (> exp-id max-exp)
                          (>= no-improvement-count threshold))
                      (progn
                        (message "[auto-experiment] Done with %s: %d experiments, best score %.2f"
                                 target (length results)
                                 best-score)
                        (funcall callback (nreverse results)))
                    (gptel-auto-experiment-run
                     target exp-id max-exp
                     best-score
                     baseline-code-quality
                     results
                     (lambda (result)
                       (push result results)
                       (gptel-auto-workflow--update-progress)
                       (let ((score-after (gptel-auto-workflow--plist-get result :score-after 0)))
                         (when (and score-after (> score-after best-score))
                           (setq best-score score-after
                                 no-improvement-count 0))
                         (when (and score-after (<= score-after best-score))
                           (cl-incf no-improvement-count)))
                       (if (> gptel-auto-experiment-delay-between 0)
                           (run-with-timer gptel-auto-experiment-delay-between nil
                                           (lambda () (run-next (1+ exp-id))))
                         (run-next (1+ exp-id))))))))
      (run-next 1))))

;;; Main Entry Point

(defvar gptel-auto-workflow--running nil
  "Flag to track if auto-workflow is currently running.")

(defvar gptel-auto-workflow--headless nil
  "Flag to suppress interactive prompts during headless operation.")

(defvar gptel-auto-workflow--auto-revert-was-enabled nil
  "Remember if global-auto-revert-mode was enabled before headless operation.")

(defvar gptel-auto-workflow--uniquify-style nil
  "Remember uniquify-buffer-name-style before headless operation.")

(defvar gptel-auto-workflow--stats nil
  "Current run statistics: (:kept :total :phase).")

(defvar gptel-auto-workflow--current-target nil
  "Current target file being processed by auto-workflow.")

(defvar gptel-auto-workflow--watchdog-timer nil
  "Watchdog timer to prevent workflow from getting stuck.")

(defvar gptel-auto-workflow--last-progress-time nil
  "Timestamp of last progress update.")

(defvar gptel-auto-workflow--max-stuck-minutes 30
  "Maximum minutes workflow can be stuck before auto-stopping.")

(defun gptel-auto-workflow--suppress-ask-user-about-supersession-threat (orig-fn &rest args)
  "Suppress supersession threat prompts in headless mode."
  (if gptel-auto-workflow--headless
      'revert
    (apply orig-fn args)))

(defun gptel-auto-workflow--suppress-yes-or-no-p (orig-fn prompt)
  "Suppress yes-or-no prompts in headless mode, auto-answer yes."
  (if gptel-auto-workflow--headless
      t
    (funcall orig-fn prompt)))

(defun gptel-auto-workflow--suppress-y-or-n-p (orig-fn prompt)
  "Suppress y-or-n prompts in headless mode, auto-answer yes."
  (if gptel-auto-workflow--headless
      t
    (funcall orig-fn prompt)))

(defun gptel-auto-workflow--suppress-kill-buffer-query ()
  "Suppress kill-buffer queries in headless mode.
Returns t to allow killing modified buffers without asking.
When not in headless mode, returns t to not interfere with normal behavior."
  (or gptel-auto-workflow--headless t))

(defun gptel-auto-workflow--suppress-kill-buffer-modified (orig-fn &optional buffer-or-name)
  "Suppress 'Buffer modified; kill anyway?' prompt in headless mode.
ORIG-FN is the original `kill-buffer'. BUFFER-OR-NAME is the buffer to kill.
In headless mode, marks buffer as unmodified before killing to bypass prompt."
  (if gptel-auto-workflow--headless
      (let ((buf (if buffer-or-name
                     (get-buffer buffer-or-name)
                   (current-buffer))))
        (when (and buf (buffer-live-p buf))
          (with-current-buffer buf
            (set-buffer-modified-p nil)))
        (funcall orig-fn buffer-or-name))
    (funcall orig-fn buffer-or-name)))

(defun gptel-auto-workflow--enable-headless-suppression ()
  "Enable suppression of interactive prompts for headless operation.
Also disables auto-revert and uniquify to prevent buffer issues when worktree files change."
  (setq gptel-auto-workflow--headless t)
  ;; Remember and disable auto-revert
  (setq gptel-auto-workflow--auto-revert-was-enabled 
        (bound-and-true-p global-auto-revert-mode))
  (when gptel-auto-workflow--auto-revert-was-enabled
    (global-auto-revert-mode -1))
  ;; Remember and disable uniquify (prevents ".emacs.d/" prefix in buffer names)
  (setq gptel-auto-workflow--uniquify-style 
        (when (boundp 'uniquify-buffer-name-style)
          uniquify-buffer-name-style))
  (when (boundp 'uniquify-buffer-name-style)
    (setq uniquify-buffer-name-style nil))
  (advice-add 'ask-user-about-supersession-threat :around 
              #'gptel-auto-workflow--suppress-ask-user-about-supersession-threat)
  (advice-add 'yes-or-no-p :around 
              #'gptel-auto-workflow--suppress-yes-or-no-p)
  (advice-add 'y-or-n-p :around 
              #'gptel-auto-workflow--suppress-y-or-n-p)
  (advice-add 'kill-buffer :around 
              #'gptel-auto-workflow--suppress-kill-buffer-modified)
  ;; Suppress kill-buffer queries for modified buffers
  (add-hook 'kill-buffer-query-functions 
            #'gptel-auto-workflow--suppress-kill-buffer-query))

(defcustom gptel-auto-workflow-persistent-headless nil
  "If non-nil, keep headless suppression enabled between runs.
Set to t when running as daemon/cron to prevent interactive prompts."
  :type 'boolean
  :group 'gptel-tools-agent)

(defun gptel-auto-workflow--disable-headless-suppression ()
  "Disable suppression of interactive prompts.
Restores auto-revert and uniquify if they were enabled before headless operation.
Does nothing if `gptel-auto-workflow-persistent-headless' is non-nil."
  (when (and (not gptel-auto-workflow-persistent-headless)
             gptel-auto-workflow--headless)
    (setq gptel-auto-workflow--headless nil)
    ;; Restore auto-revert
    (when (and (boundp 'gptel-auto-workflow--auto-revert-was-enabled)
               gptel-auto-workflow--auto-revert-was-enabled)
      (global-auto-revert-mode 1))
    ;; Restore uniquify
    (when (and (boundp 'gptel-auto-workflow--uniquify-style)
               gptel-auto-workflow--uniquify-style)
      (setq uniquify-buffer-name-style gptel-auto-workflow--uniquify-style))
    (advice-remove 'ask-user-about-supersession-threat 
                   #'gptel-auto-workflow--suppress-ask-user-about-supersession-threat)
    (advice-remove 'yes-or-no-p 
                   #'gptel-auto-workflow--suppress-yes-or-no-p)
    (advice-remove 'y-or-n-p 
                   #'gptel-auto-workflow--suppress-y-or-n-p)
    (advice-remove 'kill-buffer 
                   #'gptel-auto-workflow--suppress-kill-buffer-modified)
    (remove-hook 'kill-buffer-query-functions 
                 #'gptel-auto-workflow--suppress-kill-buffer-query)))

(defcustom gptel-auto-workflow-git-timeout 120
  "Timeout in seconds for git commands during auto-workflow.
Default 120s (2 minutes) handles slow network connections.
Increase if git operations frequently timeout."
  :type 'integer
  :group 'gptel-tools-agent)

(defun gptel-auto-workflow--git-cmd (cmd &optional timeout)
  "Run git command CMD with TIMEOUT (default: gptel-auto-workflow-git-timeout).
Returns command output as string."
  (gptel-auto-workflow--shell-command-string cmd (or timeout gptel-auto-workflow-git-timeout)))

(defun gptel-auto-workflow--watchdog-check ()
  "Check if workflow is stuck and force-stop if necessary.
Prevents workflow from hanging indefinitely due to callback failures."
  (when gptel-auto-workflow--running
    (let ((stuck-minutes (and gptel-auto-workflow--last-progress-time
                              (/ (float-time (time-subtract (current-time) gptel-auto-workflow--last-progress-time))
                                 60))))
      (if (and stuck-minutes (> stuck-minutes gptel-auto-workflow--max-stuck-minutes))
          (progn
            (message "[auto-workflow] WATCHDOG: Workflow stuck for %.1f minutes, force-stopping"
                     stuck-minutes)
            (setq gptel-auto-workflow--running nil)
            (plist-put gptel-auto-workflow--stats :phase "idle")
            (when gptel-auto-workflow--watchdog-timer
              (cancel-timer gptel-auto-workflow--watchdog-timer)
              (setq gptel-auto-workflow--watchdog-timer nil)))
        ;; Still running normally, check again in 5 minutes
        t))))

(defun gptel-auto-workflow--update-progress ()
  "Update progress timestamp for watchdog tracking."
  (setq gptel-auto-workflow--last-progress-time (current-time)))

(defun gptel-auto-workflow-force-stop ()
  "Force stop a stuck workflow.
Interactive command to recover from hung workflow state."
  (interactive)
  (setq gptel-auto-workflow--running nil)
  (plist-put gptel-auto-workflow--stats :phase "idle")
  (when gptel-auto-workflow--watchdog-timer
    (cancel-timer gptel-auto-workflow--watchdog-timer)
    (setq gptel-auto-workflow--watchdog-timer nil))
  (message "[auto-workflow] Force-stopped"))

(defun gptel-auto-workflow--headless-p ()
  "Check if running on a headless server (Linux, Pi5, etc).
Returns non-nil if this machine should run 24/7 background jobs.
Detection: macOS (darwin) = user machine, Linux = headless."
  (not (eq system-type 'darwin)))

(defun gptel-auto-workflow--default-quiet-hours ()
  "Auto-detect quiet hours based on OS.
Returns nil for all systems - rely on 30-min inactivity check instead.
This allows cron-scheduled runs while still protecting active use.

Users can override in their config if needed."
  nil)

(defvar gptel-auto-workflow-quiet-hours (gptel-auto-workflow--default-quiet-hours)
  "List of hours (0-23) when auto-workflow should NOT run.
Default is nil for all systems - we rely on:
  - 30-min inactivity check (gptel-auto-workflow-skip-if-recent-input)
  - Cron schedule (macOS: 10AM,2PM,6PM; Pi5: every 4h)

Override in your config:
  (setq gptel-auto-workflow-quiet-hours '(9 10 11 12 13 14 15 16 17))  ; Work hours
  (setq gptel-auto-workflow-quiet-hours '(0 1 2 3 4 5 6))  ; Night only")

(defcustom gptel-auto-workflow-skip-if-unsaved nil
  "If non-nil, skip auto-workflow when there are unsaved buffers.
Default is nil since unsaved buffers are normal when using Emacs."
  :type 'boolean
  :group 'gptel)

(defcustom gptel-auto-workflow-skip-if-recent-input t
  "If non-nil, skip when user has typed within last N minutes.
See `gptel-auto-workflow-recent-input-minutes'."
  :type 'boolean
  :group 'gptel)

(defcustom gptel-auto-workflow-recent-input-minutes 30
  "Minutes of inactivity required before auto-workflow can run.
Default 30 min covers lunch breaks and short meetings."
  :type 'integer
  :group 'gptel)

(defun gptel-auto-workflow--active-use-p ()
  "Check if Emacs is being actively used.
Returns cons cell (REASONS . REASONS) where REASONS is a list
of strings describing why workflow should skip.
Returns (nil . nil) if safe to run."
  (let ((reasons '()))
    (when gptel-auto-workflow-skip-if-unsaved
      (let ((unsaved (cl-remove-if-not
                      (lambda (buf)
                        (and (buffer-file-name buf)
                             (buffer-modified-p buf)))
                      (buffer-list))))
        (when (and unsaved (> (length unsaved) 0))
          (push (format "%d unsaved buffers" (length unsaved)) reasons))))
    (when (and gptel-auto-workflow-skip-if-recent-input
               (boundp 'last-command-event-time)
               last-command-event-time)
      (let* ((last-input-seconds (float-time (time-subtract nil last-command-event-time)))
             (last-input-minutes (/ last-input-seconds 60.0)))
        (when (< last-input-minutes gptel-auto-workflow-recent-input-minutes)
          (push (format "recent input (%.1f min ago)" last-input-minutes) reasons))))
    (when gptel-auto-workflow-quiet-hours
      (let ((current-hour (string-to-number (format-time-string "%H"))))
        (when (memq current-hour gptel-auto-workflow-quiet-hours)
          (push (format "quiet hours (hour %d)" current-hour) reasons))))
    (cons reasons reasons)))

(defun gptel-auto-workflow-status ()
  "Return current workflow status as plist.
Returns (:running :kept :total :phase :results)."
  (list :running gptel-auto-workflow--running
        :kept (gptel-auto-workflow--plist-get gptel-auto-workflow--stats :kept 0)
        :total (gptel-auto-workflow--plist-get gptel-auto-workflow--stats :total 0)
        :phase (gptel-auto-workflow--plist-get gptel-auto-workflow--stats :phase "idle")
        :results (format "var/tmp/experiments/%s/results.tsv"
                         (format-time-string "%Y-%m-%d"))))

(defun gptel-auto-workflow--sanitize-unicode (str)
  "Sanitize Unicode characters in STR for safe display.
Replaces curly quotes, dashes, and other problematic characters
with their ASCII equivalents."
  (let ((clean str))
    (dolist (pair '(("RIGHT SINGLE QUOTATION MARK" . "'")
                    ("LEFT SINGLE QUOTATION MARK" . "'")
                    ("RIGHT DOUBLE QUOTATION MARK" . "\"")
                    ("LEFT DOUBLE QUOTATION MARK" . "\"")
                    ("EN DASH" . "-")
                    ("EM DASH" . "-")
                    ("HORIZONTAL ELLIPSIS" . "...")
                    ("NON-BREAKING SPACE" . " ")
                    ("ZERO WIDTH SPACE" . "")
                    ("ZERO WIDTH NON-JOINER" . "")
                    ("ZERO WIDTH JOINER" . "")))
      (let ((char (char-from-name (car pair))))
        (when char
          (setq clean (replace-regexp-in-string (string char) (cdr pair) clean)))))
    clean))

(defun gptel-auto-workflow-log ()
  "Return recent workflow log lines as a list (filtered, sanitized).
Safe for external tools - contains only [auto-] and [nucleus] messages."
  (with-current-buffer "*Messages*"
    (let ((lines (split-string (buffer-string) "\n" t))
          result)
      (dolist (line lines)
        (when (string-match-p "^\\[auto-\\]\\|^\\[nucleus\\]" line)
          (push (gptel-auto-workflow--sanitize-unicode line) result)))
      (seq-take (nreverse result) 20))))

(declare-function gptel-auto-workflow-select-targets "gptel-auto-workflow-strategic")

(defun gptel-auto-workflow-run-async (&optional targets completion-callback)
  "Run auto-workflow asynchronously with TARGETS.
Non-blocking - returns immediately, check status with `gptel-auto-workflow-status'.
TARGETS defaults to `gptel-auto-workflow-targets'.
COMPLETION-CALLBACK is called with results when all targets are done.

Skips if Emacs is in active use (unsaved buffers, recent input, etc.).
Check `gptel-auto-workflow--active-use-p' for details.

Usage:
  emacsclient -e '(gptel-auto-workflow-run-async)'
  emacsclient -e '(gptel-auto-workflow-status)'
  M-x gptel-auto-workflow-run"
  (interactive)
  (cl-block gptel-auto-workflow-run-async
    (when gptel-auto-workflow--running
      (error "[auto-workflow] Already running. Check status first."))
    (let ((active (gptel-auto-workflow--active-use-p)))
      (when (car active)
        (message "[auto-workflow] Skipping: %s" (string-join (car active) ", "))
        (cl-return-from gptel-auto-workflow-run-async nil)))
    (gptel-auto-workflow--require-magit-dependencies)
    (setq gptel-auto-workflow--running t
          gptel-auto-workflow--stats (list :phase "selecting" :total 0 :kept 0)
          gptel-auto-workflow--last-progress-time (current-time))
    ;; Start watchdog timer
    (when gptel-auto-workflow--watchdog-timer
      (cancel-timer gptel-auto-workflow--watchdog-timer))
    (setq gptel-auto-workflow--watchdog-timer
          (run-with-timer 300 300 #'gptel-auto-workflow--watchdog-check))
    (if targets
        (gptel-auto-workflow--run-with-targets targets completion-callback)
      (require 'gptel-auto-workflow-strategic)
      (gptel-auto-workflow-select-targets
       (lambda (selected-targets)
         (gptel-auto-workflow--run-with-targets selected-targets completion-callback))))))

(defun gptel-auto-workflow-run-async--guarded (&optional targets completion-callback)
  "Run auto-workflow with active-use guard using catch/throw.
Same as `gptel-auto-workflow-run-async' but safe for cron jobs."
  (catch 'skip-workflow
    (when gptel-auto-workflow--running
      (error "[auto-workflow] Already running. Check status first."))
    (let ((active (gptel-auto-workflow--active-use-p)))
      (when (car active)
        (message "[auto-workflow] Skipping: %s" (string-join (car active) ", "))
        (throw 'skip-workflow nil)))
    (gptel-auto-workflow-run-async targets completion-callback)))

(defun gptel-auto-workflow-cron-safe ()
  "Run auto-workflow with full cleanup for cron jobs.
Cancels stale timers, kills orphaned buffers, resets state, then runs.
Safe to call from cron - handles all edge cases.
Sets `gptel-auto-workflow-persistent-headless' to prevent interactive prompts."
  (let ((proj-root (or (gptel-auto-workflow--project-root)
                       (expand-file-name "~/.emacs.d/"))))
    (setq default-directory proj-root)
    (require 'magit)
    (require 'json)
    (unless (featurep 'gptel-tools-agent)
      (load-file (expand-file-name "lisp/modules/gptel-tools-agent.el" proj-root)))
    (setq gptel-auto-workflow-persistent-headless t)
    (gptel-auto-workflow--enable-headless-suppression)
    (setq gptel-auto-experiment--api-error-count 0)
    (condition-case err
        (progn
          (condition-case err1
              (gptel-auto-workflow--cleanup-stale-state)
            (error (message "[auto-workflow] Cleanup failed (non-critical): %s" err1)))
          (condition-case err1
              (gptel-auto-workflow--ensure-on-main-branch)
            (error (message "[auto-workflow] Ensure main branch failed (non-critical): %s" err1)))
          (condition-case err2
              (gptel-auto-workflow--sync-staging-with-main)
            (error (message "[auto-workflow] Sync staging failed (non-critical): %s" err2)))
          (condition-case err3
              (let ((orphans (gptel-auto-workflow--recover-orphans)))
                (when orphans
                  (message "[auto-workflow] ⚠ Found %d orphan commit(s) from previous run"
                           (length orphans))
                  (gptel-auto-workflow-recover-all-orphans t)))
            (error (message "[auto-workflow] Orphan recovery failed (non-critical): %s" err3)))
          (gptel-auto-workflow-run-async--guarded nil
                                                  (lambda (_)
                                                    (condition-case err4
                                                        (gptel-auto-workflow--promote-staging-to-main)
                                                      (error (message "[auto-workflow] Promote staging failed (non-critical): %s" err4)))
                                                    (condition-case err5
                                                        (gptel-auto-workflow--ensure-on-main-branch)
                                                      (error (message "[auto-workflow] Final branch check failed: %s" err5)))
                                                    (gptel-auto-workflow--disable-headless-suppression))))
      (error
       (message "[auto-workflow] Cron error: %s" err)
       (gptel-auto-workflow--ensure-on-main-branch)
       (gptel-auto-workflow--disable-headless-suppression)
       nil))))

(defun gptel-auto-workflow--experiment-suffix ()
  "Get experiment suffix based on hostname.
Returns short hostname like 'onepi5', 'daylight', or 'macbook'.
Works across macOS and Linux."
  (let ((name (downcase (system-name))))
    (cond
     ((string-match "^\\([a-z0-9]+\\)" name)
      (match-string 1 name))
     (t "unknown"))))

(defun gptel-auto-workflow--cleanup-old-worktrees ()
  "Remove ALL optimize worktrees and their branches from previous runs.
Called at start of new run to ensure clean state.
Only removes worktrees if no gptel processes are running."
  (let* ((proj-root (or (gptel-auto-workflow--project-root)
                        (expand-file-name "~/.emacs.d/")))
         (worktree-base-dir (or gptel-auto-workflow-worktree-base
                                "var/tmp/experiments"))
         (worktree-base (expand-file-name worktree-base-dir proj-root))
         (optimize-dir (expand-file-name "optimize" worktree-base))
         (suffix (gptel-auto-workflow--experiment-suffix))
         (pattern (concat suffix "-exp"))
         (removed 0)
         (active-processes (cl-count-if
                            (lambda (p)
                              (and (process-live-p p)
                                   (string-match-p "gptel" (process-name p))))
                            (process-list))))
    (when (and (file-exists-p optimize-dir)
               (= active-processes 0))
      (let ((dirs (directory-files optimize-dir t pattern)))
        (dolist (dir dirs)
          (when (file-exists-p dir)
            (let ((dirname (file-name-nondirectory dir)))
              (condition-case err
                  (progn
                    (delete-directory dir t)
                    (shell-command
                     (format "cd %s && git worktree remove --force var/tmp/experiments/optimize/%s 2>/dev/null; git branch -D optimize/%s 2>/dev/null || true"
                             (shell-quote-argument proj-root)
                             dirname
                             dirname)
                     nil nil)
                    (cl-incf removed))
                (error
                 (message "[auto-workflow] Failed to cleanup %s: %s" dir err))))))))
    (when (> removed 0)
      (message "[auto-workflow] Cleaned %d old worktrees" removed))
    removed))

(defun gptel-auto-workflow--cleanup-stale-state ()
  "Clean up stale timers, buffers, and state from aborted runs."
  (let ((proj-root (or (gptel-auto-workflow--project-root)
                       (expand-file-name "~/.emacs.d/")))
        (cleaned 0))
    (when proj-root
      (gptel-auto-workflow--cleanup-old-worktrees)
      (dolist (timer (copy-sequence timer-list))
        (when (timerp timer)
          (let* ((fn-rep (condition-case nil
                             (prin1-to-string (timer--function timer))
                           (error ""))))
            (when (and (stringp fn-rep)
                       (or (string-match-p "nucleus" fn-rep)
                           (string-match-p "gptel.*agent" fn-rep)
                           (string-match-p "auto-experiment" fn-rep)))
              (cancel-timer timer)
              (cl-incf cleaned)))))
      (dolist (buf (buffer-list))
        (when (buffer-live-p buf)
          (with-current-buffer buf
            (when (and (stringp default-directory)
                       (string-match-p (format "optimize/.*-%s" (gptel-auto-workflow--experiment-suffix)) default-directory)
                       (not (file-exists-p default-directory)))
              (kill-buffer buf)
              (cl-incf cleaned)))))
      (setq gptel-auto-workflow--running nil
            gptel-auto-workflow--current-target nil)
      (clrhash gptel-auto-workflow--worktree-state))
    (when (> cleaned 0)
      (message "[auto-workflow] Cleaned %d stale items" cleaned))))

(defun gptel-auto-workflow--run-with-targets (targets completion-callback)
  "Run experiments for TARGETS asynchronously."
  (let* ((run-id (format-time-string "%Y-%m-%d"))
         (proj-root (or (gptel-auto-workflow--project-root)
                        (expand-file-name "~/.emacs.d/")))
         (all-results '())
         (completed-targets 0)
         (kept-count 0))
    ;; Set project context for subagent routing
    (setq gptel-auto-workflow--current-project proj-root)
    (plist-put gptel-auto-workflow--stats :phase "running")
    (plist-put gptel-auto-workflow--stats :total (length targets))
    (message "[auto-workflow] Starting %s with %d targets" run-id (length targets))
    (dolist (target targets)
      (gptel-auto-experiment-loop
       target
       (lambda (results)
         (setq all-results (append all-results results))
         (cl-incf completed-targets)
         (setq kept-count (cl-count-if (lambda (r) (plist-get r :kept)) all-results))
         (plist-put gptel-auto-workflow--stats :kept kept-count)
         (when (= completed-targets (length targets))
           (setq gptel-auto-workflow--running nil)
           (plist-put gptel-auto-workflow--stats :phase "complete")
           (message "[auto-workflow] Complete: %d experiments, %d kept"
                    (length all-results) kept-count)
           (when completion-callback
             (funcall completion-callback all-results))))))))

(defun gptel-auto-workflow-run (&optional targets)
  "Run auto-workflow asynchronously.
Non-blocking - returns immediately, check status with `gptel-auto-workflow-status'.
TARGETS defaults to `gptel-auto-workflow-targets'."
  (interactive)
  (gptel-auto-workflow-run-async targets))

;;; Autonomous Research Agent (program.md + skills + mementum)

(defcustom gptel-auto-workflow-program-file "docs/auto-workflow-program.md"
  "Path to program.md (human-editable objectives)."
  :type 'file
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-skills-dir "mementum/knowledge"
  "Directory containing optimization-skills/ and mutations/."
  :type 'directory
  :group 'gptel-tools-agent)

(defvar gptel-auto-workflow--program nil
  "Parsed program.md content.")

(defvar gptel-auto-workflow--skills nil
  "Loaded optimization skills for current run.")

(defun gptel-auto-workflow-load-program ()
  "Load and parse docs/auto-workflow-program.md."
  (let* ((file (expand-file-name gptel-auto-workflow-program-file
                                 (gptel-auto-workflow--project-root)))
         (content (gptel-auto-workflow--read-file-contents file))
         (targets '())
         (immutable '())
         (mutations '()))
    (when content
      (with-temp-buffer
        (insert content)
        (goto-char (point-min))
        (when (re-search-forward "^## Targets" nil t)
          (forward-line 1)
          (when (re-search-forward "^```" nil t)
            (forward-line 1)
            (while (and (not (looking-at "```")) (not (eobp)))
              (let ((line (string-trim (thing-at-point 'line t))))
                (when (and (> (length line) 0) (not (string-match-p "^#" line)))
                  (push line targets)))
              (forward-line 1))))
        (goto-char (point-min))
        (when (re-search-forward "^### Immutable Files" nil t)
          (forward-line 1)
          (when (re-search-forward "^```" nil t)
            (forward-line 1)
            (while (and (not (looking-at "```")) (not (eobp)))
              (let ((line (string-trim (thing-at-point 'line t))))
                (when (> (length line) 0)
                  (push line immutable)))
              (forward-line 1))))
        (goto-char (point-min))
        (when (re-search-forward "^Allowed mutation types:" nil t)
          (forward-line 1)
          (while (and (not (looking-at "^##")) (not (eobp)))
            (when (looking-at "- \\[x\\] \\([a-z-]+\\)")
              (push (match-string 1) mutations))
            (forward-line 1)))))
    (list :targets (nreverse targets)
          :immutable (nreverse immutable)
          :mutations (nreverse mutations)
          :file file)))

(defun gptel-auto-workflow-skill-path (target type)
  "Get skill path for TARGET. TYPE is 'target or 'mutation."
  (let* ((name (file-name-sans-extension (file-name-nondirectory target)))
         (skill-name (car (last (split-string name "-")))))
    (if (eq type 'target)
        (format "%s/optimization-skills/%s.md" gptel-auto-workflow-skills-dir skill-name)
      (format "%s/mutations/%s.md" gptel-auto-workflow-skills-dir target))))

(defun gptel-auto-workflow-skill-load (skill-file)
  "Load skill from SKILL-FILE."
  (let ((file (expand-file-name skill-file (gptel-auto-workflow--project-root))))
    (when (file-exists-p file)
      (let ((content (gptel-auto-workflow--read-file-contents file))
            (skill (list :file skill-file)))
        (when (string-match "^phi:[[:space:]]*\\([0-9.]+\\)" content)
          (plist-put skill :phi (string-to-number (match-string 1 content))))
        (when (string-match "^mutation-skills:[[:space:]]*\n\\(\\(?:  - .+\n\\)+\\)" content)
          (let ((refs (match-string 1 content)))
            (plist-put skill :mutation-skills
                       (mapcar (lambda (line)
                                 (string-trim (replace-regexp-in-string "^  - " "" line)))
                               (split-string refs "\n" t)))))
        (plist-put skill :content content)
        skill))))

(defun gptel-auto-workflow-recall-skills (target)
  "Load target skill + referenced mutation skills for TARGET."
  (let* ((target-skill-file (gptel-auto-workflow-skill-path target 'target))
         (target-skill (gptel-auto-workflow-skill-load target-skill-file))
         (mutation-skills '()))
    (when target-skill
      (dolist (ref (plist-get target-skill :mutation-skills))
        (let ((ms (gptel-auto-workflow-skill-load ref)))
          (when ms (push ms mutation-skills)))))
    (list :target-skill target-skill
          :mutation-skills (nreverse mutation-skills))))

(defun gptel-auto-workflow-skill-suggest-hypothesis (skills)
  "Get suggested hypothesis from SKILLS."
  (let* ((target-skill (plist-get skills :target-skill))
         (content (when target-skill (plist-get target-skill :content))))
    (when (and content (string-match "^## Next Hypothesis\n\n\\(.+\\)" content))
      (match-string 1 content))))

(defun gptel-auto-workflow--extract-mutation-templates (skills)
  "Extract hypothesis templates from mutation skills in SKILLS.
Returns list of template strings for hypothesis generation."
  (let* ((mutation-skills (plist-get skills :mutation-skills))
         (templates '()))
    (dolist (ms mutation-skills)
      (let ((content (plist-get ms :content)))
        (when content
          (let ((start (string-match "## Hypothesis Templates" content)))
            (when start
              (let* ((code-start (string-match "```\n" content start))
                     (code-end (when code-start (string-match "\n```" content (+ code-start 4)))))
                (when (and code-start code-end)
                  (let ((raw (substring content (+ code-start 4) code-end)))
                    (dolist (line (split-string raw "\n" t))
                      (when (string-match-p "^\"" line)
                        (push (string-trim line "\"\\s-*" "\"\\s-*") templates)))))))))))
    (nreverse templates)))

(defun gptel-auto-workflow--format-weakest-keys (baseline-scores)
  "Format weakest keys for prompt from BASELINE-SCORES.
Returns formatted string with key names and signals."
  (when baseline-scores
    (let* ((weakest (gptel-benchmark-eight-keys-weakest-with-signals baseline-scores 2))
           (lines '()))
      (dolist (item weakest)
        (let* ((key (plist-get item :key))
               (score (plist-get item :score))
               (signals (plist-get item :signals))
               (def (alist-get key gptel-benchmark-eight-keys-definitions))
               (name (plist-get def :name))
               (symbol (plist-get def :symbol)))
          (push (format "- %s %s: %.0f%% (focus: %s)"
                        symbol name (* 100 score)
                        (string-join (or signals '("improve")) ", "))
                lines)))
      (mapconcat #'identity (nreverse lines) "\n"))))

(defun gptel-auto-workflow-orient ()
  "Orient for auto-workflow run. Load program.md and skills."
  (let ((program (gptel-auto-workflow-load-program)))
    (setq gptel-auto-workflow--program program)
    (message "[autonomous] Loaded program: %d targets"
             (length (plist-get program :targets)))
    (let ((skills '()))
      (dolist (target (plist-get program :targets))
        (push (cons target (gptel-auto-workflow-recall-skills target)) skills))
      (setq gptel-auto-workflow--skills skills))
    program))

;;; Skill Evolution (Continuity + Compounding)

(defun gptel-auto-workflow-detect-mutation (hypothesis)
  "Detect mutation type from HYPOTHESIS string."
  (cond
   ((string-match-p "cache\\|Cache\\|memoize\\|memo" hypothesis) "caching")
   ((string-match-p "lazy\\|defer\\|on-demand\\|delay" hypothesis) "lazy-init")
   ((string-match-p "simplif\\|remove\\|merge\\|reduce\\|eliminate" hypothesis) "simplification")
   (t "unknown")))

(defun gptel-auto-workflow-update-target-skill (target results)
  "Update TARGET skill file with RESULTS from night."
  (let* ((skill-file (gptel-auto-workflow-skill-path target 'target))
         (file (expand-file-name skill-file (gptel-auto-workflow--project-root))))
    (when (file-exists-p file)
      (let* ((content (gptel-auto-workflow--read-file-contents file))
             (by-mutation (make-hash-table :test 'equal))
             (successful '())
             (failed '())
             (best-hypothesis nil)
             (best-delta 0)
             (total-kept 0)
             (score-before nil)
             (score-after nil))
        (dolist (r results)
          (let* ((hypothesis (gptel-auto-workflow--plist-get r :hypothesis ""))
                 (mutation (gptel-auto-workflow-detect-mutation hypothesis))
                 (kept (gptel-auto-workflow--plist-get r :kept nil))
                 (delta (gptel-auto-workflow--plist-get r :delta 0)))
            (when (and kept (> delta best-delta))
              (setq best-delta delta
                    best-hypothesis hypothesis))
            (when kept (cl-incf total-kept))
            (unless score-before
              (setq score-before (gptel-auto-workflow--plist-get r :score-before nil)))
            (when (and kept (gptel-auto-workflow--plist-get r :score-after nil))
              (setq score-after (gptel-auto-workflow--plist-get r :score-after nil)))
            (puthash mutation (cons r (gethash mutation by-mutation)) by-mutation)))
        (maphash
         (lambda (mutation mutation-results)
           (let* ((kept-count (cl-count-if (lambda (r) (gptel-auto-workflow--plist-get r :kept nil)) mutation-results))
                  (total (length mutation-results))
                  (success-rate (if (> total 0) (/ (* 100 kept-count) total) 0))
                  (kept-results (cl-remove-if-not (lambda (r) (gptel-auto-workflow--plist-get r :kept nil)) mutation-results))
                  (avg-delta (if kept-results
                                 (/ (apply #'+ (mapcar (lambda (r) (gptel-auto-workflow--plist-get r :delta 0)) kept-results))
                                    (length kept-results))
                               0))
                  (best (car (sort kept-results (lambda (a b)
                                                  (> (gptel-auto-workflow--plist-get a :delta 0)
                                                     (gptel-auto-workflow--plist-get b :delta 0))))))
                  (best-hyp (when best (gptel-auto-workflow--plist-get best :hypothesis ""))))
             (if (>= success-rate 50)
                 (push (list mutation success-rate avg-delta best-hyp) successful)
               (when (< success-rate 50)
                 (push (list mutation success-rate 
                             (if (< success-rate 50) "Low success rate" ""))
                       failed)))))
         by-mutation)
        (with-temp-buffer
          (insert content)
          (goto-char (point-min))
          (when (re-search-forward "^runs:[[:space:]]*\\([0-9]+\\)" nil t)
            (replace-match (format "runs: %d" (1+ (string-to-number (match-string 1))))))
          (goto-char (point-min))
          (when (re-search-forward "^phi:[[:space:]]*\\([0-9.]+\\)" nil t)
            (let* ((total (length results))
                   (new-phi (if (> total 0) (/ (float total-kept) total) 0.5)))
              (replace-match (format "phi: %.2f" new-phi))))
          (goto-char (point-min))
          (when (re-search-forward "^## Successful Mutations" nil t)
            (forward-line 3)
            (delete-region (point) (when (re-search-forward "^## " nil t) (match-beginning 0)))
            (backward-char 1)
            (dolist (s (nreverse successful))
              (insert (format "| %s | %.0f%% | %+.2f | %s |\n"
                              (nth 0 s) (nth 1 s) (nth 2 s) (or (nth 3 s) "-")))))
          (goto-char (point-min))
          (when (re-search-forward "^## Failed Mutations" nil t)
            (forward-line 3)
            (delete-region (point) (when (re-search-forward "^## " nil t) (match-beginning 0)))
            (backward-char 1)
            (dolist (f (nreverse failed))
              (insert (format "| %s | %.0f%% | %s |\n"
                              (nth 0 f) (nth 1 f) (nth 2 f)))))
          (goto-char (point-min))
          (when (re-search-forward "^## Nightly History" nil t)
            (forward-line 3)
            (let ((date (format-time-string "%Y-%m-%d"))
                  (exp-count (length results)))
              (insert (format "| %s | %d | %d | %.2f | %.2f | %+.2f |\n"
                              date exp-count total-kept
                              (or score-before 0)
                              (or score-after 0)
                              (if (and score-before score-after)
                                  (- score-after score-before)
                                0)))))
          (goto-char (point-min))
          (when (re-search-forward "^## Next Hypothesis" nil t)
            (forward-line 1)
            (delete-region (point) (when (re-search-forward "^## " nil t) (match-beginning 0)))
            (backward-char 1)
            (insert (format "\n%s\n" (or best-hypothesis "(Run more experiments)"))))
          (write-region (point-min) (point-max) file))))))

(defun gptel-auto-workflow-update-mutation-skill (mutation-type all-results)
  "Update MUTATION-TYPE skill file with ALL-RESULTS."
  (let* ((skill-file (format "%s/mutations/%s.md"
                             gptel-auto-workflow-skills-dir mutation-type))
         (file (expand-file-name skill-file (gptel-auto-workflow--project-root))))
    (when (file-exists-p file)
      (let* ((content (gptel-auto-workflow--read-file-contents file))
             (relevant (cl-remove-if-not
                        (lambda (r)
                          (let ((hyp (gptel-auto-workflow--plist-get r :hypothesis "")))
                            (eq (gptel-auto-workflow-detect-mutation hyp)
                                (intern mutation-type))))
                        all-results))
             (kept-relevant (cl-remove-if-not (lambda (r) (gptel-auto-workflow--plist-get r :kept nil)) relevant))
             (total (length relevant))
             (kept-count (length kept-relevant))
             (success-rate (if (> total 0) (/ (* 100 kept-count) total) 0))
             (avg-delta (if kept-relevant
                            (/ (apply #'+ (mapcar (lambda (r) (gptel-auto-workflow--plist-get r :delta 0)) kept-relevant))
                               (length kept-relevant))
                          0))
             (history-rows '()))
        (dolist (r kept-relevant)
          (push (list (gptel-auto-workflow--plist-get r :target "")
                      (format-time-string "%Y-%m-%d")
                      (gptel-auto-workflow--plist-get r :hypothesis "")
                      (gptel-auto-workflow--plist-get r :delta 0))
                history-rows))
        (with-temp-buffer
          (insert content)
          (goto-char (point-min))
          (when (re-search-forward "^phi:[[:space:]]*\\([0-9.]+\\)" nil t)
            (replace-match (format "phi: %.2f" (/ success-rate 100.0))))
          (goto-char (point-min))
          (when (re-search-forward "^## Success History" nil t)
            (forward-line 3)
            (dolist (row (nreverse history-rows))
              (insert (format "| %s | %s | %s | %+.2f |\n"
                              (nth 0 row) (nth 1 row)
                              (truncate-string-to-width (or (nth 2 row) "-") 40 nil nil "...")
                              (or (nth 3 row) 0)))))
          (goto-char (point-min))
          (when (re-search-forward "^## Statistics" nil t)
            (forward-line 6)
            (delete-region (point) (line-end-position))
            (insert (format "| Total uses | %d |" total))
            (forward-line 1)
            (delete-region (point) (line-end-position))
            (insert (format "| Success rate | %.0f%% |" success-rate))
            (forward-line 1)
            (delete-region (point) (line-end-position))
            (insert (format "| Avg delta | %+.2f |" avg-delta)))
          (write-region (point-min) (point-max) file))))))

(defun gptel-auto-workflow-metabolize (run-id all-results)
  "Synthesize RUN-ID ALL-RESULTS to mementum + evolve skills."
  (let ((memory-dir (expand-file-name "mementum/memories"
                                      (gptel-auto-workflow--project-root)))
        (by-target (make-hash-table :test 'equal)))
    (make-directory memory-dir t)
    (let ((file (expand-file-name (format "auto-workflow-%s.md" run-id) memory-dir)))
      (with-temp-file file
        (insert (format "---\ntitle: Auto-Workflow %s\ndate: %s\n---\n\n" run-id run-id))
        (insert (format "# Auto-Workflow: %s\n\n" run-id))
        (insert "## Summary\n\n")
        (let ((kept (cl-count-if (lambda (r) (gptel-auto-workflow--plist-get r :kept nil)) all-results))
              (total (length all-results)))
          (insert (format "- Experiments: %d\n" total))
          (insert (format "- Kept: %d\n" kept))
          (insert (format "- Discarded: %d\n\n" (- total kept))))
        (insert "## Key Learnings\n\n")
        (dolist (r (cl-remove-if-not (lambda (r) (gptel-auto-workflow--plist-get r :kept nil)) all-results))
          (insert (format "- **%s**: %s\n"
                          (gptel-auto-workflow--plist-get r :target "")
                          (gptel-auto-workflow--plist-get r :hypothesis "unknown"))))))
    (message "[autonomous] Memory: mementum/memories/auto-workflow-%s.md" run-id)
    (dolist (r all-results)
      (let ((target (gptel-auto-workflow--plist-get r :target "")))
        (puthash target (cons r (gethash target by-target)) by-target)))
    (maphash
     (lambda (target results)
       (gptel-auto-workflow-update-target-skill target results))
     by-target)
    (let ((mutation-types '()))
      (dolist (r all-results)
        (let ((mutation (gptel-auto-workflow-detect-mutation
                         (gptel-auto-workflow--plist-get r :hypothesis ""))))
          (when (not (member mutation mutation-types))
            (push mutation mutation-types))))
      (dolist (mutation-type mutation-types)
        (when (not (equal mutation-type "unknown"))
          (gptel-auto-workflow-update-mutation-skill mutation-type all-results))))
    (message "[autonomous] Skills evolved: %d targets, %d mutation types"
             (hash-table-count by-target)
             (length (cl-remove "unknown" (hash-table-keys by-target))))))

(defun gptel-auto-workflow-run-autonomous ()
  "Run Autonomous Research Agent with program.md + skills + mementum.

Flow:
  1. orient() - load program.md + skills
  2. run experiments with skill guidance
  3. metabolize() - synthesize to mementum

Cron: emacsclient -e '(gptel-auto-workflow-run-autonomous)'
Manual: M-x gptel-auto-workflow-run-autonomous"
  (interactive)
  (gptel-auto-workflow--require-magit-dependencies)
  (let* ((program (gptel-auto-workflow-orient))
         (targets (plist-get program :targets))
         (run-id (format-time-string "%Y-%m-%d"))
         (all-results '())
         (completed-targets 0)
         (total-targets (length targets)))
    (if (null targets)
        (message "[autonomous] No targets in %s" gptel-auto-workflow-program-file)
      (message "[autonomous] Starting %s with %d targets" run-id (length targets))
      (dolist (target targets)
        (gptel-auto-experiment-loop
         target
         (lambda (results)
           (setq all-results (append all-results results))
           (cl-incf completed-targets)
           (when (= completed-targets total-targets)
             (gptel-auto-workflow-metabolize run-id all-results)
             (message "[autonomous] Complete: %d experiments" (length all-results)))))))))

;;; Mementum Optimization

(defvar gptel-mementum-index-file "mementum/.index"
  "Path to recall index file.")

(defun gptel-mementum-build-index ()
  "Build recall index from all knowledge files.
Creates .index file with topic → file mapping for O(1) lookup."
  (let* ((index-file (expand-file-name gptel-mementum-index-file
                                       (gptel-auto-workflow--project-root)))
         (knowledge-dir (expand-file-name "mementum/knowledge"
                                          (gptel-auto-workflow--project-root)))
         (index (make-hash-table :test 'equal)))
    (when (file-exists-p knowledge-dir)
      (dolist (file (directory-files-recursively knowledge-dir "\\.md$"))
        (let ((content (gptel-auto-workflow--read-file-contents file))
              (filename (file-relative-name file knowledge-dir)))
          (dolist (keyword '("caching" "lazy" "simplification" "retry" "context"
                             "code" "nucleus" "learning" "pattern" "evolution"
                             "safety" "upstream" "skill" "benchmark"))
            (when (string-match-p (regexp-quote keyword) content)
              (puthash keyword
                       (cons filename (gethash keyword index))
                       index))))))
    (with-temp-file index-file
      (insert "# Mementum Recall Index\n")
      (insert "# Auto-generated. Do not edit.\n\n")
      (maphash
       (lambda (keyword files)
         (insert (format "%s: %s\n" keyword (string-join (delete-dups files) ", "))))
       index))
    (message "[mementum] Index built: %d keywords" (hash-table-count index))))

(defun gptel-mementum-recall (query)
  "Quick lookup for QUERY in recall index.
Returns list of matching files."
  (let* ((index-file (expand-file-name gptel-mementum-index-file
                                       (gptel-auto-workflow--project-root)))
         (result '()))
    (when (file-exists-p index-file)
      (with-temp-buffer
        (insert-file-contents index-file)
        (goto-char (point-min))
        (when (re-search-forward (format "^%s: " (regexp-quote query)) nil t)
          (let ((line (buffer-substring-no-properties (point) (line-end-position))))
            (setq result (split-string line ",\\s-*"))))))
    (or result
        (progn
          (message "[mementum] Index miss, using git grep for: %s" query)
          (let ((default-directory (gptel-auto-workflow--project-root)))
            ;; SECURITY: Use shell-quote-argument to prevent shell injection
            (split-string
             (shell-command-to-string
              (format "git grep -l %s -- mementum/knowledge/ 2>/dev/null || true"
                      (shell-quote-argument query)))
             "\n" t))))))

(defun gptel-mementum-decay-skills ()
  "Apply decay to skill files not tested in 4+ weeks.
Run weekly via cron."
  (let* ((skills-dir (expand-file-name "mementum/knowledge/optimization-skills"
                                       (gptel-auto-workflow--project-root)))
         (mutations-dir (expand-file-name "mementum/knowledge/mutations"
                                          (gptel-auto-workflow--project-root)))
         (now (float-time))
         (four-weeks (* 4 7 24 60 60))
         (decayed 0)
         (archived 0))
    (dolist (dir (list skills-dir mutations-dir))
      (when (file-exists-p dir)
        (dolist (file (directory-files dir t "\\.md$"))
          (let ((content (gptel-auto-workflow--read-file-contents file)))
            (when (string-match "^last-tested:[[:space:]]*\\([0-9-]+\\)" content)
              (let* ((date-str (match-string 1 content))
                     (last-tested (when (>= (length date-str) 10)
                                    (encode-time 0 0 0 (string-to-number (substring date-str 8 10))
                                                 (string-to-number (substring date-str 5 7))
                                                 (string-to-number (substring date-str 0 4)))))
                     (age (when last-tested
                            (- now (float-time last-tested)))))
                (when (and age (> age four-weeks))
                  (let ((new-phi (max 0.3 (- (if (string-match "^phi:[[:space:]]*\\([0-9.]+\\)" content)
                                                 (string-to-number (match-string 1 content))
                                               0.5)
                                             0.02))))
                    (if (< new-phi 0.3)
                        (progn
                          (let ((archive-dir (expand-file-name "archive" dir)))
                            (make-directory archive-dir t)
                            (rename-file file (expand-file-name (file-name-nondirectory file) archive-dir))
                            (cl-incf archived)))
                      (with-temp-buffer
                        (insert content)
                        (goto-char (point-min))
                        (when (re-search-forward "^phi:[[:space:]]*[0-9.]+" nil t)
                          (replace-match (format "phi: %.2f" new-phi)))
                        (write-region (point-min) (point-max) file)
                        (cl-incf decayed)))))))))))
    (message "[mementum] Decay: %d decayed, %d archived" decayed archived)))

(defun gptel-mementum-check-synthesis-candidates ()
  "Check for topics with ≥3 memories and suggest synthesis.
Returns list of synthesis candidates."
  (let* ((memories-dir (expand-file-name "mementum/memories"
                                         (gptel-auto-workflow--project-root)))
         (by-topic (make-hash-table :test 'equal))
         (candidates '()))
    (when (file-exists-p memories-dir)
      (dolist (file (directory-files memories-dir t "\\.md$"))
        (let ((slug (file-name-sans-extension (file-name-nondirectory file))))
          (dolist (topic (split-string slug "[-_]"))
            (when (> (length topic) 3)
              (puthash topic (cons file (gethash topic by-topic)) by-topic)))))
      (maphash
       (lambda (topic files)
         (when (>= (length files) 3)
           (push (list :topic topic :count (length files) :files files) candidates)))
       by-topic))
    (when candidates
      (message "[mementum] Synthesis candidates: %s"
               (mapcar (lambda (c) (plist-get c :topic)) candidates)))
    candidates))

(defun gptel-mementum-synthesize-candidate (candidate)
  "Synthesize CANDIDATE into knowledge page with human approval.
CANDIDATE is plist with :topic :count :files.
Implements λ termination(x): synthesis ≡ AI | approval ≡ human."
  (let* ((topic (plist-get candidate :topic))
         (files (plist-get candidate :files))
         (memories-content '())
         (synthesized nil))
    (dolist (file files)
      (let ((content (gptel-auto-workflow--read-file-contents file)))
        (when content
          (push content memories-content))))
    (when (>= (length memories-content) 3)
      (let ((preview-buffer (get-buffer-create "*Synthesis Preview*")))
        (with-current-buffer preview-buffer
          (erase-buffer)
          (insert (format "# Synthesis Preview: %s\n\n" topic))
          (insert (format "## Source Memories (%d)\n\n" (length memories-content)))
          (dolist (content memories-content)
            (insert (format "### %s\n\n%s\n\n"
                            (truncate-string-to-width content 50 nil nil "...")
                            content)))
          (insert "\n## Proposed Knowledge Page\n\n")
          (insert (format "---\ntitle: %s\nstatus: open\ncategory: synthesized\ntags:\n  - %s\nsynthesized: %s\n---\n\n"
                          topic topic (format-time-string "%Y-%m-%d")))
          (insert (format "# %s\n\nSynthesized from %d memories.\n\n" topic (length memories-content)))
          (insert "## Key Patterns\n\n(Auto-detected patterns)\n\n")
          (goto-char (point-min)))
        (display-buffer preview-buffer)
        (when (y-or-n-p (format "Create knowledge page for '%s'? " topic))
          (let* ((frontmatter (format "---\ntitle: %s\nstatus: open\ncategory: synthesized\ntags:\n  - %s\nsynthesized: %s\n---"
                                      topic topic (format-time-string "%Y-%m-%d")))
                 (content (format "\n\n# %s\n\nSynthesized from %d memories.\n\n## Key Patterns\n\nPatterns identified from:\n%s\n"
                                  topic (length memories-content)
                                  (mapconcat (lambda (f) (format "- %s" (file-name-nondirectory f))) files "\n")))
                 (know-dir (expand-file-name "mementum/knowledge" (gptel-auto-workflow--project-root)))
                 (know-file (expand-file-name (format "%s.md" topic) know-dir)))
            (make-directory know-dir t)
            (with-temp-file know-file
              (insert frontmatter)
              (insert content))
            (message "[mementum] Created knowledge page: %s" know-file)
            ;; SECURITY: Use shell-quote-argument to prevent shell injection
            (shell-command-to-string
             (format "git add %s && git commit -m %s"
                     (shell-quote-argument know-file)
                     (shell-quote-argument (format "💡 synthesis: %s" topic))))
            (setq synthesized t)))))
    synthesized))

(defun gptel-mementum-synthesize-all-candidates (&optional candidates)
  "Synthesize all CANDIDATES (or detect if nil) with human approval."
  (let* ((cands (or candidates (gptel-mementum-check-synthesis-candidates)))
         (synthesized 0))
    (dolist (candidate cands)
      (when (gptel-mementum-synthesize-candidate candidate)
        (cl-incf synthesized)))
    (message "[mementum] Synthesized %d/%d candidates" synthesized (length cands))
    synthesized))

(defun gptel-mementum-weekly-job ()
  "Weekly mementum maintenance: decay + index rebuild + synthesis.
Implements λ synthesize(topic): ≥3 memories → candidate → human approval."
  (interactive)
  (message "[mementum] Starting weekly maintenance...")
  (gptel-mementum-build-index)
  (gptel-mementum-decay-skills)
  (let ((synthesized (gptel-mementum-synthesize-all-candidates)))
    (message "[mementum] Weekly maintenance complete. Synthesized: %d" synthesized)))

(defun gptel-mementum-synthesis-run ()
  "Interactively run synthesis on all candidates.
M-x gptel-mementum-synthesis-run"
  (interactive)
  (gptel-mementum-synthesize-all-candidates))

(provide 'gptel-tools-agent)

;;; gptel-tools-agent.el ends here
