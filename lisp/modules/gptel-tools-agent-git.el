;;; gptel-tools-agent-git.el --- Git operations, orphan tracking, branch sync -*- lexical-binding: t; -*-
;; Part of gptel-tools-agent split

(defun gptel-auto-workflow--log-conflict (commit-hash conflict-output)
  "Log CONFLICT-OUTPUT for COMMIT-HASH to file for later review."
  (let ((log-file (expand-file-name "var/log/cherry-pick-conflicts.log"
                                    (or (gptel-auto-workflow--project-root)
                                        (expand-file-name "~/.emacs.d/"))))
        (timestamp (format-time-string "%Y-%m-%d %H:%M:%S"))
        (msg (if (and (stringp conflict-output)
                      (> (length conflict-output) 0))
                 (substring conflict-output 0 (min 400 (length conflict-output)))
               "")))
    (make-directory (file-name-directory log-file) t)
    (with-temp-buffer
      (insert (format "[%s] %s\n%s\n\n" timestamp commit-hash msg))
      (append-to-file (point-min) (point-max) log-file))))

(defun gptel-auto-workflow-recover-all-orphans (&optional no-push)
  "Recover all orphan commits from tracked ledgers to staging branch.
If NO-PUSH is non-nil, skip pushing to the workflow remote (useful for cron
jobs)."
  (interactive)
  (let ((orphans (gptel-auto-workflow--recoverable-tracked-commits)))
    (if (not orphans)
        (message "[auto-workflow] No orphans to recover")
      (let ((recovered 0)
            (conflicted 0)
            (failed 0))
        (dolist (orphan orphans)
          (let ((hash (car orphan)))
            (pcase (gptel-auto-workflow--cherry-pick-orphan hash)
              ('conflict
               (gptel-auto-workflow--untrack-commit hash)
               (cl-incf conflicted))
              ((pred identity)
               (gptel-auto-workflow--untrack-commit hash)
               (cl-incf recovered))
              (_
               (cl-incf failed)))))
        (message "[auto-workflow] Recovered %d/%d orphans to staging"
                 recovered (length orphans))
        (when (> conflicted 0)
          (message "[auto-workflow] Untracked %d conflicted orphan(s); see cherry-pick conflict log"
                   conflicted))
        (when (> failed 0)
          (message "[auto-workflow] Left %d orphan(s) tracked for retry"
                   failed))
        (when (and (> recovered 0) (not no-push))
          (gptel-auto-workflow--push-staging))))))


(defun gptel-auto-workflow--sync-branches (source-branch target-branch action-name)
  "Fast-forward TARGET-BRANCH to match SOURCE-BRANCH.
ACTION-NAME is used in log messages (e.g., \"Synced\", \"Promoted\").
All shell commands have timeout protection to prevent deadlocks."
  (unless (and (gptel-auto-workflow--non-empty-string-p source-branch)
               (gptel-auto-workflow--non-empty-string-p target-branch)
               (gptel-auto-workflow--non-empty-string-p action-name))
    (error "[auto-workflow] sync-branches: source-branch, target-branch, and action-name must be non-empty strings"))
  (let* ((default-directory (gptel-auto-workflow--default-dir))
         (remote (gptel-auto-workflow--shared-remote))
         (remote-source (format "%s/%s" remote source-branch))
         (remote-target (format "%s/%s" remote target-branch))
         (original-branch (gptel-auto-workflow--git-cmd
                           "git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main")))
    (condition-case err
        (progn
          (gptel-auto-workflow--git-cmd (format "git fetch %s" remote) 180)
          (let* ((source-commit (gptel-auto-workflow--git-cmd
                                 (format "git rev-parse %s" remote-source)))
                 (target-commit (gptel-auto-workflow--git-cmd
                                 (format "git rev-parse %s 2>/dev/null || echo \"none\"" remote-target)))
                 (source-commit (or source-commit "none"))
                 (target-commit (or target-commit "none")))
            (if (string= source-commit target-commit)
                (message "[auto-workflow] %s already in sync with %s" target-branch source-branch)
              (progn
                (gptel-auto-workflow--git-cmd (format "git checkout %s" target-branch))
                (gptel-auto-workflow--git-cmd (format "git merge %s --ff-only" remote-source))
                (gptel-auto-workflow--with-skipped-submodule-sync
                 (lambda ()
                   (gptel-auto-workflow--git-cmd (format "git push %s %s" remote target-branch))))
                (gptel-auto-workflow--git-cmd (format "git checkout %s" original-branch))
                (message "[auto-workflow] %s %s to %s (%s -> %s)"
                         action-name target-branch source-branch
                         (gptel-auto-workflow--truncate-hash target-commit)
                         (gptel-auto-workflow--truncate-hash source-commit))))))
      (error
       (gptel-auto-workflow--git-cmd (format "git checkout %s" original-branch))
       (message "[auto-workflow] Failed to %s %s to %s: %s" (downcase action-name) target-branch source-branch err)
       nil))))

;;;###autoload

(defun gptel-auto-workflow--sync-staging-with-main ()
  "Fast-forward staging branch to match main.
Ensures experiments run against latest code without touching the root worktree."
  (gptel-auto-workflow--sync-staging-from-main))


;;;###autoload

(defun gptel-auto-workflow--promote-staging-to-main ()
  "Leave staging promotion to a human reviewer."
  (message "[auto-workflow] Auto-promotion to main is disabled; merge staging manually")
  nil)


;;; Customization

(defgroup gptel-tools-agent nil
  "Subagent delegation for gptel-agent."
  :group 'gptel)

(defcustom my/gptel-agent-task-timeout 300
  "Timeout in seconds for gptel-agent task calls.
Default 300s (5 min). Set lower to catch stuck requests faster."
  :type 'integer
  :group 'gptel-tools-agent)

(defvar my/gptel-agent-task-hard-timeout nil
  "Optional hard wall-clock timeout in seconds for the current subagent task.

When non-nil, inactivity-based timeouts may still rearm on progress, but the
task cannot exceed this total runtime.")

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
        (md5 (concat (or prompt "")
                     (format "-files:%S" (when files (sort (append files nil) #'string<)))
                     (format "-hist:%s" (or include-history "nil"))
                     (format "-diff:%s" (or include-diff "nil"))))))

(defun my/gptel--subagent-cache-enabled-p ()
  "Return t if subagent caching is enabled and ready.
Checks both TTL configuration and hash table initialization."
  (and (> my/gptel-subagent-cache-ttl 0)
       (hash-table-p my/gptel--subagent-cache)))

(defun my/gptel--subagent-cache-allowed-p (agent-type)
  "Return non-nil when AGENT-TYPE is safe to serve from the subagent cache.
Executor results are side-effectful during auto-workflow: reusing cached prose
after a worktree is recreated would skip reapplying the file edits that prose
describes.
Returns nil for nil or empty agent-type to prevent invalid cache lookups."
  (and (stringp agent-type)
       (not (string-empty-p agent-type))
       (not (and (equal agent-type "executor")
                 (or gptel-auto-workflow--current-target
                     gptel-auto-workflow--current-project)))))

(defun my/gptel--cacheable-subagent-result-p (result &optional agent-type)
  "Return non-nil when RESULT is safe to reuse from the subagent cache.
AGENT-TYPE can further restrict cacheability for agent-specific failures.
Failure-shaped responses must not be cached, otherwise transient transport
or reviewer-contract failures can poison later workflow attempts with
immediate cache hits."
  (or (not (stringp result))
      (and (not (string-empty-p result))
           (not (string-match-p
                 (concat
                  "\\`Error:"
                  "\\|\\`Warning:.*not available"
                  "\\|throttling"
                  "\\|rate.limit"
                  "\\|quota exceeded"
                  "\\|HTTP 429"
                  "\\|hour allocated quota exceeded"
                  "\\|failed to finish"
                  "\\|could not finish")
                 result))
           (not (and (equal agent-type "reviewer")
                     (gptel-auto-workflow--review-retryable-error-p result))))))

(defun my/gptel--subagent-cache-get (agent-type prompt &optional files include-history include-diff)
  "Get cached result for (AGENT-TYPE, PROMPT, ...) if still valid.
Returns nil if cache disabled, not found, or expired."
  (when (and (stringp agent-type)
             (not (string-empty-p agent-type))
             (my/gptel--subagent-cache-enabled-p)
             (my/gptel--subagent-cache-allowed-p agent-type))
    (let* ((key (my/gptel--subagent-cache-key agent-type prompt files include-history include-diff))
           (cached (gethash key my/gptel--subagent-cache)))
      (when cached
        (let ((timestamp (car cached))
              (result (cdr cached)))
          (if (> (- (float-time) timestamp) my/gptel-subagent-cache-ttl)
              (progn (remhash key my/gptel--subagent-cache) nil)
            (if (my/gptel--cacheable-subagent-result-p result agent-type)
                result
              (progn
                (remhash key my/gptel--subagent-cache)
                nil))))))))

(defun my/gptel--subagent-cache-put (agent-type prompt result &optional files include-history include-diff)
  "Cache RESULT for (AGENT-TYPE, PROMPT, ...).
Evicts oldest entries if cache exceeds `my/gptel-subagent-cache-max-size'.
Returns nil if cache disabled, agent-type invalid, or result not cacheable."
  (when (and (stringp agent-type)
             (not (string-empty-p agent-type))
             (my/gptel--subagent-cache-enabled-p)
             (my/gptel--subagent-cache-allowed-p agent-type)
             (my/gptel--cacheable-subagent-result-p result agent-type))
    (let ((key (my/gptel--subagent-cache-key agent-type prompt files include-history include-diff)))
      (puthash key (cons (float-time) result) my/gptel--subagent-cache)
      ;; Evict oldest entries if over limit
      (when (and (> my/gptel-subagent-cache-max-size 0)
                 (> (hash-table-count my/gptel--subagent-cache)
                    my/gptel-subagent-cache-max-size))
        (let* ((entries nil)
               (excess (- (hash-table-count my/gptel--subagent-cache)
                          my/gptel-subagent-cache-max-size)))
          (maphash
           (lambda (k v)
             (push (cons (car v) k) entries))
           my/gptel--subagent-cache)
          (setq entries (sort entries (lambda (a b) (< (car a) (car b)))))
          (let ((to-evict (cl-subseq entries 0 (min excess (length entries)))))
            (dolist (entry to-evict)
              (remhash (cdr entry) my/gptel--subagent-cache))))))))

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

(defun my/gptel--seed-fsm-tools (fsm tools)
  "Seed FSM dispatch tools from TOOLS.
Subagent requests can carry the full tool payload in `:data' while
`gptel-fsm-info' keeps an underspecified `:tools' list.  Refresh the
FSM-local snapshot so later tool dispatch matches the request payload."
  (when (and (gptel-fsm-p fsm) tools)
    (let ((info (gptel-fsm-info fsm)))
      (setf (gptel-fsm-info fsm)
            (plist-put info :tools (copy-sequence tools))))))


;; PATCH: Override gptel-agent--task to add tracking-marker for parent buffer
;; position and large-result truncation.  Respects `my/gptel-subagent-stream'
;; (default nil = non-streaming for reliability with DashScope).

(defvar gptel-auto-workflow--defer-subagent-env-persistence nil
  "When non-nil, defer buffer-local subagent env persistence until launch ends.")

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
      (let* ((preset
              (gptel-auto-workflow--maybe-override-subagent-provider
               agent-type
               (or (gptel-auto-workflow--agent-base-preset agent-type)
                   (nconc (list :include-reasoning nil
                                :use-tools t
                                :use-context nil
                                :stream my/gptel-subagent-stream)
                          (cdr agent-config)))))
             (syms (cons 'gptel--preset (gptel--preset-syms preset)))
             (vals (mapcar (lambda (sym) (if (boundp sym) (symbol-value sym) nil)) syms)))
        (cl-progv syms vals
          (gptel--apply-preset preset)
          (let* ((request-tools (and gptel-use-tools (copy-sequence gptel-tools)))
                 (parent-fsm
                  (and (boundp 'gptel--fsm-last)
                       (fboundp 'my/gptel--coerce-fsm)
                       (my/gptel--coerce-fsm gptel--fsm-last)))
                 (info (and parent-fsm
                            (ignore-errors (gptel-fsm-info parent-fsm))))
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
                 (child-fsm (gptel-make-fsm :table gptel-send--transitions
                                            :handlers gptel-agent-request--handlers))
                 (previous-fsm-local-p (local-variable-p 'gptel--fsm-last parent-buf))
                 (previous-fsm (and previous-fsm-local-p
                                    (buffer-local-value 'gptel--fsm-last parent-buf)))
                 (previous-fsm-valid-p
                  (and previous-fsm
                       (or (not (fboundp 'my/gptel--coerce-fsm))
                           (my/gptel--coerce-fsm previous-fsm))))
                 (partial (format "%s result for task: %s\n\n"
                                  (capitalize (or agent-type "agent"))
                                  (or description "unknown"))))
            (my/gptel--register-agent-task-buffer parent-buf)
            (gptel--update-status " Calling Agent..." 'font-lock-escape-face)
            (with-current-buffer parent-buf
              (setq-local gptel--fsm-last child-fsm))
            (let ((request-started nil))
              (unwind-protect
                  (progn
                    (gptel-request prompt
                      :context (gptel-agent--task-overlay where agent-type description)
                      :fsm child-fsm
                      :transforms (list #'my/gptel--disable-auto-retry-transform
                                        #'gptel--transform-add-context)
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
                                    (error-msg (when (listp error-info)
                                                 (plist-get error-info :message)))
                                    (result
                                     (if (and error-msg
                                              (stringp error-msg)
                                              (string-match-p "1013\\|server is initializing" error-msg))
                                         (format "Warning: Reviewer agent not available (server initializing). Auto-approving changes.\n\nError details: %S"
                                                 error-info)
                                       (format "Error: Task %s could not finish task \"%s\". \n\nError details: %S"
                                               agent-type description error-info))))
                               (gptel-auto-workflow--maybe-activate-rate-limit-failover
                                agent-type preset result)
                               (funcall main-cb result)))
                            (`(tool-call . ,calls)
                             (unless (plist-get info :tracking-marker)
                               (plist-put info :tracking-marker tracking-marker))
                             (gptel--display-tool-calls calls info))
                            (`(tool-result . ,_results))
                            ((pred stringp)
                             (setq partial (concat partial resp))
                             (unless (plist-get info :tool-use)
                               (when (overlayp ov) (delete-overlay ov))
                               (when-let* ((transformer (plist-get info :transformer)))
                                 (setq partial (funcall transformer partial)))
                               (gptel-auto-workflow--maybe-activate-rate-limit-failover
                                agent-type preset partial)
                               (my/gptel--subagent-cache-put agent-type prompt partial)
                               (my/gptel--deliver-subagent-result main-cb partial)))
                            ('abort
                             (when (overlayp ov) (delete-overlay ov))
                             (let* ((error-info (plist-get info :error))
                                    (error-msg
                                     (cond
                                      ((stringp error-info) error-info)
                                      ((and (listp error-info)
                                            (stringp (plist-get error-info :message)))
                                       (plist-get error-info :message)))))
                               (funcall
                                main-cb
                                (if (and (stringp error-msg)
                                         (not (string-empty-p error-msg)))
                                    error-msg
                                  (format "Error: Task \"%s\" was aborted by the user. \n%s could not finish."
                                          description agent-type)))))))))
                    (my/gptel--seed-fsm-tools child-fsm request-tools)
                    (my/gptel--disable-auto-retry-for-fsm child-fsm)
                    (setq request-started t))
                (unless request-started
                  (with-current-buffer parent-buf
                    (if (and previous-fsm-local-p previous-fsm-valid-p)
                        (setq-local gptel--fsm-last previous-fsm)
                      (kill-local-variable 'gptel--fsm-last))))))))))))


(defun my/gptel--deliver-subagent-result (callback result)
  "Deliver RESULT to CALLBACK, truncating large results to a temp file."
  (cl-block my/gptel--deliver-subagent-result
    (unless callback
      (cl-return-from my/gptel--deliver-subagent-result))
    (unless (stringp result)
      (funcall callback (or result ""))
      (cl-return-from my/gptel--deliver-subagent-result))
    (if (> (length result) my/gptel-subagent-result-limit)
        (let* ((temp-file (if (fboundp 'my/gptel-make-temp-file)
                              (my/gptel-make-temp-file "gptel-subagent-result-" nil ".txt")
                            (make-temp-file "gptel-subagent-result-" nil ".txt")))
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
      (funcall callback result))))

(defun my/gptel-agent--truncate-buffer-around (orig prefix &optional max-lines)
  "Prevent temp artifacts from starting with a raw Emacs modeline.
ORIG is `gptel-agent--truncate-buffer'. PREFIX and MAX-LINES are passed through."
  (let* ((starts-with-modeline
          (and (> (buffer-size) 20000)
               (save-excursion
                 (goto-char (point-min))
                 (re-search-forward "-\\*-" (line-end-position) t))))
         (temp-dir (and (> (buffer-size) 20000)
                        (expand-file-name "gptel-agent-temp"
                                          (temporary-file-directory))))
         temp-file)
    (when temp-dir
      (make-directory temp-dir t))
    (funcall orig prefix max-lines)
    (when starts-with-modeline
      (save-excursion
        (goto-char (point-min))
        (when (re-search-forward "^Stored in: \\(.*\\)$" nil t)
          (setq temp-file (match-string 1))))
      (when (and (stringp temp-file) (file-exists-p temp-file))
        (with-temp-buffer
          (insert-file-contents temp-file)
          (unless (looking-at-p "Temporary gptel-agent artifact\\.")
            (let ((content (buffer-string)))
              (erase-buffer)
              (insert "Temporary gptel-agent artifact. Original content begins below.\n\n")
              (insert content)
              (write-region nil nil temp-file nil 'silent))))))))

(defun my/gptel-agent--write-file-around (orig path filename content)
  "Create missing parent directories before `gptel-agent--write-file' saves.
ORIG is `gptel-agent--write-file'. PATH, FILENAME, and CONTENT are passed
through unchanged after the destination directory exists."
  (when (and (stringp path) (stringp filename))
    (let ((parent (file-name-directory (expand-file-name filename path))))
      (when parent
        (make-directory parent t))))
  (funcall orig path filename content))

(with-eval-after-load 'gptel-agent-tools
  ;; REMOVED: Old :override advice conflicts with new :around advice
  ;; in gptel-auto-workflow-projects.el that routes to correct buffer
  ;; (advice-add 'gptel-agent--task :override #'my/gptel-agent--task-override)
  (advice-add 'gptel-agent--task-overlay :around #'my/gptel-agent--task-overlay-around)
  (advice-add 'gptel-agent--truncate-buffer :around #'my/gptel-agent--truncate-buffer-around)
  (advice-add 'gptel-agent--write-file :around #'my/gptel-agent--write-file-around))

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
Replaces newlines and control chars with visible tokens.
Optional MAX-LEN truncates output (default: 100 chars).
Returns sanitized string, or \"nil\" if TEXT is nil."
  (if (not (stringp text))
      "nil"
    (let ((result (replace-regexp-in-string
                   "[\n\r\t]" 
                   (lambda (m) (pcase m ("\n" " ") ("\r" " ") ("\t" " ")))
                   text t t)))
      (truncate-string-to-width result (or max-len 100) nil nil "..."))))

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
;; ASSUMPTION: Git diff requires a valid repository at default-directory
;; BEHAVIOR: Builds XML-escaped context with files, git diff, and conversation history
;; EDGE CASE: Handles unreadable files, symlinks, and missing git repo gracefully
;; EDGE CASE: Skips git diff entirely when no repository is detected
;; TEST: Verify files outside project are rejected with error message
;; TEST: Verify git diff is skipped in non-git directories
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
             (git-dir (cond
                       ((and proj-root (file-exists-p (expand-file-name ".git" proj-root)))
                        proj-root)
                       ((file-exists-p (expand-file-name ".git" default-directory))
                        default-directory)
                       (t nil)))
             (default-directory (or git-dir default-directory)))
        (when git-dir
          (let ((diff-out (with-temp-buffer
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
                                    "\n</git_diff>\n\n")))))))

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
Values are plist: (:done :timeout-timer :progress-timer :origin-buf :request-buf).")

(defvar my/gptel--agent-task-counter 0
  "Counter for generating unique task IDs.")

(defvar my/gptel--current-agent-task-id nil
  "Dynamic task id used while subagent runners register request buffers.")

(defvar my/gptel--subagent-origin-buffer nil
  "Buffer where subagent task was initiated.
Used by overlay advice to route overlays to correct buffer.
Dynamic variable, let-bound around gptel-agent--task calls.")

(defun my/gptel--agent-task-request-buffer (state)
  "Return the live request buffer tracked in STATE."
  (let ((request-buf (plist-get state :request-buf))
        (origin-buf (plist-get state :origin-buf)))
    (cond
     ((buffer-live-p request-buf) request-buf)
     ((buffer-live-p origin-buf) origin-buf))))

(defun my/gptel--cancel-agent-task-timers (state)
  "Cancel any active timeout and progress timers in STATE."
  (when (timerp (plist-get state :timeout-timer))
    (cancel-timer (plist-get state :timeout-timer)))
  (when (timerp (plist-get state :progress-timer))
    (cancel-timer (plist-get state :progress-timer))))

(defun my/gptel--agent-task-buffer-priority (state buffer)
  "Return a relative priority for tracking BUFFER in STATE.
Routed worktree agent buffers outrank generic fallback buffers like
`*scratch*' so later low-fidelity registrations cannot clobber the real
request buffer for an active workflow task."
  (if (not (buffer-live-p buffer))
      0
    (let* ((buffer-name (buffer-name buffer))
           (activity-dir (plist-get state :activity-dir))
           (buffer-dir (with-current-buffer buffer
                         (and (stringp default-directory)
                              (expand-file-name default-directory))))
           (in-activity-dir (and (stringp activity-dir)
                                 (stringp buffer-dir)
                                 (my/gptel--path-within-directory-p
                                  buffer-dir activity-dir)))
           (agent-buffer-p (string-prefix-p "*gptel-agent:" buffer-name)))
      (cond
       ((and agent-buffer-p in-activity-dir) 4)
       (in-activity-dir 3)
       (agent-buffer-p 2)
       (t 1)))))

(defun my/gptel--workflow-owned-worktree-root (dir)
  "Return the known workflow-owned worktree root containing DIR, or nil."
  (when (stringp dir)
    (let ((expanded-dir (expand-file-name dir))
          found)
      (cond
       ((and (stringp gptel-auto-workflow--staging-worktree-dir)
             (my/gptel--path-within-directory-p expanded-dir
                                                gptel-auto-workflow--staging-worktree-dir))
        (file-name-as-directory
         (expand-file-name gptel-auto-workflow--staging-worktree-dir)))
       ((hash-table-p gptel-auto-workflow--worktree-state)
        (maphash
         (lambda (_target state)
           (let ((candidate (plist-get state :worktree-dir)))
             (when (and (null found)
                        (stringp candidate)
                        (my/gptel--path-within-directory-p expanded-dir candidate))
               (setq found (file-name-as-directory (expand-file-name candidate))))))
         gptel-auto-workflow--worktree-state)
        found)))))

(defun my/gptel--workflow-routed-worktree-buffer-p (buffer root)
  "Return non-nil when BUFFER is a routed workflow buffer rooted at ROOT."
  (when (bufferp buffer)
    (let ((tracked
           (delete-dups
            (list (gptel-auto-workflow--hash-get-bound 'gptel-auto-workflow--worktree-buffers root)
                  (gptel-auto-workflow--hash-get-bound 'gptel-auto-workflow--project-buffers root)))))
      (or (memq buffer tracked)
          (string-prefix-p "*gptel-agent:" (buffer-name buffer))))))

(defun my/gptel--agent-task-request-worktree-dir (state)
  "Return STATE request buffer's workflow-owned worktree dir when available."
  (when-let* ((request-buf (my/gptel--agent-task-request-buffer state))
              ((buffer-live-p request-buf)))
    (with-current-buffer request-buf
      (let* ((dir (and (stringp default-directory)
                       (file-name-as-directory
                        (expand-file-name default-directory))))
             (root (and dir (my/gptel--workflow-owned-worktree-root dir))))
        (when (and root
                   (my/gptel--workflow-routed-worktree-buffer-p request-buf root))
          root)))))

(defun my/gptel--cleanup-agent-request-buffer (state)
  "Abort STATE's live request buffer.
Do not kill routed worktree buffers here: gptel process sentinels may still
need the buffer to exist briefly after `gptel-abort'. Worktree lifecycle
helpers handle explicit stale-buffer discards during recreate/delete flows."
  (when-let* ((request-buf (my/gptel--agent-task-request-buffer state))
              ((buffer-live-p request-buf))
              ((fboundp 'gptel-abort)))
    (ignore-errors (gptel-abort request-buf))))

(defun my/gptel--agent-task-buffer-tick (buffer)
  "Return BUFFER's current modification tick when BUFFER is live."
  (when (buffer-live-p buffer)
    (with-current-buffer buffer
      (buffer-chars-modified-tick))))

(defun my/gptel--agent-task-note-activity (task-id &optional timestamp)
  "Record fresh activity for TASK-ID at TIMESTAMP or now."
  (when-let* ((state (gethash task-id my/gptel--agent-task-state)))
    (let ((activity-time (or timestamp (current-time))))
      (puthash task-id
               (plist-put state :last-activity-time activity-time)
               my/gptel--agent-task-state)
      (when gptel-auto-workflow--running
        (setq gptel-auto-workflow--last-progress-time activity-time)))))

(defun my/gptel--agent-task-uses-idle-timeout-p (agent-type)
  "Return non-nil when AGENT-TYPE should use inactivity-based timeout extension."
  (equal agent-type "executor"))

(defun my/gptel--agent-task-note-active-activity (&optional agent-type timestamp)
  "Record fresh activity for active idle-timeout tasks matching AGENT-TYPE.

When AGENT-TYPE is nil, note activity for every active idle-timeout task."
  (let ((activity-time (or timestamp (current-time))))
    (when (> (hash-table-count my/gptel--agent-task-state) 0)
      (maphash
       (lambda (task-id state)
         (when (and (not (plist-get state :done))
                    (my/gptel--agent-task-uses-idle-timeout-p
                     (plist-get state :agent-type))
                    (or (null agent-type)
                        (equal (plist-get state :agent-type) agent-type)))
           (my/gptel--agent-task-note-activity task-id activity-time)))
       my/gptel--agent-task-state))))

(defun my/gptel--path-within-directory-p (path directory)
  "Return non-nil when PATH is DIRECTORY itself or lives beneath it."
  (when (and (stringp path) (stringp directory))
    (let* ((path (expand-file-name path))
           (directory (expand-file-name directory)))
      (or (equal path directory)
          (equal (file-name-as-directory path)
                 (file-name-as-directory directory))
          (ignore-errors
            (file-in-directory-p path directory))))))

(defun my/gptel--agent-task-note-context-activity (&optional directory buffer timestamp)
  "Record activity for executor tasks active in DIRECTORY or BUFFER.

TIMESTAMP defaults to `current-time'."
  (let* ((activity-time (or timestamp (current-time)))
         (dir (and (stringp directory) (expand-file-name directory)))
         (dir (or dir
                  (and (stringp default-directory)
                       (expand-file-name default-directory))))
         (buf (or buffer (current-buffer)))
         (file (and (buffer-live-p buf) (buffer-file-name buf))))
    (when (> (hash-table-count my/gptel--agent-task-state) 0)
      (maphash
       (lambda (task-id state)
         (let ((activity-dir (plist-get state :activity-dir)))
           (when (and (equal (plist-get state :agent-type) "executor")
                      (stringp activity-dir)
                      (or (and dir
                               (my/gptel--path-within-directory-p dir activity-dir))
                          (and file
                               (my/gptel--path-within-directory-p file activity-dir))))
             (my/gptel--agent-task-note-activity task-id activity-time))))
       my/gptel--agent-task-state))))

(defun my/gptel--ignore-agent-activity-message-p (text)
  "Return non-nil when TEXT is unrelated chatter for executor activity."
  (or (and (stringp text)
           (string-match-p
            "\\`Cleaning up the recentf list\\(?:\\.\\.\\.\\(?:done.*\\)?\\)?\\'"
            text))
      (and (stringp text)
           (string-match-p
            "\\`File .+ removed from the recentf list\\'"
            text))
      (and (stringp text)
           (string-match "\\`Wrote \\(.+\\)\\'" text)
           (string-prefix-p "gptel-curl-data"
                            (file-name-nondirectory (match-string 1 text))))))

(defun my/gptel--agent-task-message-activity-path (text)
  "Return an absolute work path from TEXT when it denotes real file output."
  (when (and (stringp text)
             (string-match "\\`Wrote \\(.+\\)\\'" text))
    (let ((path (match-string 1 text)))
      (when (file-name-absolute-p path)
        path))))

(defun my/gptel--agent-task-note-message-activity (format-string &rest args)
  "Treat worktree-context messages as executor activity."
  (let ((text (and (stringp format-string)
                   (condition-case nil
                       (apply #'format format-string args)
                     (error format-string))))
        (activity-path nil))
    (setq activity-path (my/gptel--agent-task-message-activity-path text))
    (unless (my/gptel--ignore-agent-activity-message-p text)
      (if activity-path
          (my/gptel--agent-task-note-context-activity activity-path nil)
        (my/gptel--agent-task-note-context-activity)))))

(while (advice-member-p #'my/gptel--agent-task-note-message-activity 'message)
  (advice-remove 'message #'my/gptel--agent-task-note-message-activity))
(advice-add 'message :before #'my/gptel--agent-task-note-message-activity)

(provide 'gptel-tools-agent-git)
;;; gptel-tools-agent-git.el ends here
