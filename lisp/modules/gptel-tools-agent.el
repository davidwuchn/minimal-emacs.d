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

(defvar gptel-send--transitions)
(declare-function gptel--transform-add-context "gptel-request" (callback fsm))
(declare-function gptel-benchmark-llm-synthesize-knowledge "gptel-benchmark-llm"
                  (topic memories &optional callback))
(declare-function gptel-benchmark-llm-synthesize-knowledge-sync "gptel-benchmark-llm"
                  (topic memories &optional timeout-seconds))

;; Forward declaration for variable defined in gptel-auto-workflow-projects.el.
;; Do not initialize it here, or later `defvar' initializers in the projects
;; module will be skipped and leave the shared table bound to nil.
(defvar gptel-auto-workflow--project-buffers)
(defvar gptel-auto-workflow--worktree-buffers)
(defvar gptel-auto-workflow--current-project nil)
(defvar gptel-auto-workflow--run-project-root nil)
(defvar gptel-agent-loop--bypass nil)

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

(defun gptel-auto-workflow--make-idempotent-callback (callback)
  "Return a wrapper that invokes CALLBACK at most once."
  (let ((called nil))
    (lambda (&rest args)
      (unless called
        (setq called t)
        (apply callback args)))))

(defun gptel-auto-workflow--truncate-hash (hash &optional length)
  "Truncate HASH to LENGTH characters (default 7) if longer.
Returns original hash if shorter than LENGTH.
Reduces duplication of `(if (>= (length hash) 7) (substring hash 0 7) hash)` patterns."
  (let ((len (or length 7)))
    (if (and (stringp hash) (>= (length hash) len))
        (substring hash 0 len)
      hash)))

(defun gptel-auto-workflow--safe-call (operation fn &optional error-prefix)
  "Execute FN for OPERATION, logging errors but continuing execution.
ERROR-PREFIX defaults to \"[auto-workflow]\".
Returns FN's result on success, nil on error.
Use for non-critical operations that should not halt execution."
  (condition-case err
      (funcall fn)
    (error
     (message "%s %s failed (non-critical): %s"
              (or error-prefix "[auto-workflow]")
              operation
              (my/gptel--sanitize-for-logging (error-message-string err) 160))
     nil)))


(defun gptel-auto-workflow--with-error-handling (operation fn &optional error-prefix)
  "Execute FN for OPERATION, logging any error and returning nil.
ERROR-PREFIX defaults to \"[auto-workflow]\"."
  (condition-case err
      (funcall fn)
    (error
     (message "%s Failed to %s: %s"
              (or error-prefix "[auto-workflow]")
              operation
              (my/gptel--sanitize-for-logging (error-message-string err) 160))
     nil)))


(defun gptel-auto-workflow--require-magit-dependencies ()
  "Require magit-worktree and magit-git dependencies.
Signals user-error if either dependency fails to load."
  (unless (require 'magit-worktree nil t)
    (user-error "magit-worktree is required"))
  (unless (require 'magit-git nil t)
    (user-error "magit-git is required")))

(defun gptel-auto-workflow--default-dir ()
  "Return default directory for git operations.
Uses `gptel-auto-workflow--project-root' if available, falls back to ~/.emacs.d/.
Reduces duplication of `(or (gptel-auto-workflow--project-root) (expand-file-name \"~/.emacs.d/\"))` patterns."
  (or (gptel-auto-workflow--project-root)
      (expand-file-name "~/.emacs.d/")))

(defun gptel-auto-workflow--worktree-base-root ()
  "Return a stable root for workflow-owned worktree artifacts.
Prefer the root captured at workflow start over mutable experiment context."
  (expand-file-name
   (or (and (boundp 'gptel-auto-workflow--run-project-root)
            gptel-auto-workflow--run-project-root)
       (and (boundp 'gptel-auto-workflow--current-project)
            gptel-auto-workflow--current-project)
       (gptel-auto-workflow--default-dir))))

(defun gptel-auto-workflow--resolve-run-root (&optional fallback)
  "Return a stable project root for workflow callbacks.
FALLBACK is used before falling back to the ambient `default-directory'."
  (file-name-as-directory
   (expand-file-name
    (or (and (boundp 'gptel-auto-workflow--run-project-root)
             gptel-auto-workflow--run-project-root)
        (and (boundp 'gptel-auto-workflow--project-root-override)
             gptel-auto-workflow--project-root-override)
        fallback
        (ignore-errors (gptel-auto-workflow--project-root))
        default-directory))))

(defun gptel-auto-workflow--call-in-run-context (run-root fn &optional buffer directory)
  "Call FN with workflow globals rebound to RUN-ROOT.
When BUFFER is live, execute there. DIRECTORY controls `default-directory'
for FN and defaults to RUN-ROOT."
  (let* ((root (gptel-auto-workflow--resolve-run-root run-root))
         (context-dir (if (and (stringp directory) (> (length directory) 0))
                          (file-name-as-directory (expand-file-name directory))
                        root)))
    (if (buffer-live-p buffer)
        (with-current-buffer buffer
          (let ((default-directory context-dir)
                (gptel-auto-workflow--project-root-override root)
                (gptel-auto-workflow--current-project root)
                (gptel-auto-workflow--run-project-root root))
            (funcall fn)))
      (let ((default-directory context-dir)
            (gptel-auto-workflow--project-root-override root)
            (gptel-auto-workflow--current-project root)
            (gptel-auto-workflow--run-project-root root))
        (funcall fn)))))

(defun gptel-auto-workflow--worktree-or-project-dir (&optional target)
  "Return directory for git operations, preferring worktree if available.
Priority: 1) worktree dir for TARGET, 2) project root, 3) ~/.emacs.d/.
Reduces duplication of three-way `or` patterns with worktree fallback."
  (or (gptel-auto-workflow--get-worktree-dir (or target gptel-auto-workflow--current-target))
      (gptel-auto-workflow--project-root)
      (expand-file-name "~/.emacs.d/")))
;;;###autoload
(defun gptel-auto-workflow--read-file-contents (filepath)
  "Read contents of FILEPATH as string.
Returns nil if file doesn't exist or isn't readable."
  (when (and (stringp filepath) (file-exists-p filepath) (file-readable-p filepath))
    (with-temp-buffer
      (insert-file-contents filepath)
      (buffer-string))))

(defun gptel-auto-workflow--process-descendant-pids (pid)
  "Return descendant PIDs for PID."
  (let (descendants)
    (when (and (integerp pid) (fboundp 'list-system-processes))
      (cl-labels ((collect (parent)
                    (dolist (candidate (list-system-processes))
                      (let* ((attrs (ignore-errors (process-attributes candidate)))
                             (ppid (cdr (assq 'ppid attrs))))
                        (when (and (integerp ppid)
                                   (= ppid parent)
                                   (not (memq candidate descendants)))
                          (push candidate descendants)
                          (collect candidate))))))
        (collect pid)))
    descendants))

(defun gptel-auto-workflow--signal-pids (signal pids)
  "Send SIGNAL to PIDS using the system `kill' command."
  (let ((targets (cl-remove-duplicates (delq nil (copy-sequence pids)))))
    (when targets
      (apply #'call-process
             "kill" nil nil nil signal
             (mapcar #'number-to-string targets)))))

(defun gptel-auto-workflow--terminate-process-tree (process)
  "Terminate PROCESS and any descendant shell children it spawned."
  (let* ((pid (ignore-errors (process-id process)))
         (pids (append (gptel-auto-workflow--process-descendant-pids pid)
                       (and (integerp pid) (list pid)))))
    (when pids
      (ignore-errors
        (gptel-auto-workflow--signal-pids "-TERM" pids))
      (when (process-live-p process)
        (accept-process-output process 0.1 nil))
      (sleep-for 0.05)
      (ignore-errors
        (gptel-auto-workflow--signal-pids
         "-KILL"
         (cl-remove-if-not
          (lambda (candidate)
            (ignore-errors (process-attributes candidate)))
          pids))))
    (ignore-errors
      (when (process-live-p process)
        (delete-process process)))))

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
            ;; Use 0.1s timeout in accept-process-output
            (accept-process-output process 0.1 nil)
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
                   (gptel-auto-workflow--terminate-process-tree process))
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
          (message "[auto-workflow] %s"
                   (my/gptel--sanitize-for-logging (car result) 160))
          "")
      (if (stringp (car result))
          (string-trim (car result))
        ""))))

;;; Orphan Commit Tracking

(defvar gptel-auto-workflow--run-id nil
  "Unique identifier for the current auto-workflow run.")

(defun gptel-auto-workflow--make-run-id ()
  "Return a unique identifier for a workflow launch."
  (format "%s-%s"
          (format-time-string "%Y-%m-%dT%H%M%SZ")
          (substring (md5 (format "%s:%s:%s"
                                  (float-time)
                                  (emacs-pid)
                                  (random)))
                     0 4)))

(defun gptel-auto-workflow--current-run-id ()
  "Return the active workflow run identifier."
  (or gptel-auto-workflow--run-id
      (format-time-string "%Y-%m-%d")))

(defun gptel-auto-workflow--run-callback-live-p (run-id)
  "Return non-nil when delayed work for RUN-ID should still execute.
Nil RUN-ID means no active workflow identity was captured, so callbacks remain
allowed for compatibility with isolated tests."
  (or (null run-id)
      (and gptel-auto-workflow--running
           (equal gptel-auto-workflow--run-id run-id))))

(defun gptel-auto-experiment--stale-run-p (run-id)
  "Return non-nil when an experiment callback for RUN-ID is now stale."
  (not (gptel-auto-workflow--run-callback-live-p run-id)))

(defun gptel-auto-experiment--stale-run-result (target experiment-id)
  "Return a sentinel result for stale experiment callbacks."
  (list :target target :id experiment-id :stale-run t))

(defun gptel-auto-workflow--results-relative-path (&optional run-id)
  "Return the relative results path for RUN-ID or the active run."
  (format "var/tmp/experiments/%s/results.tsv"
          (or run-id (gptel-auto-workflow--current-run-id))))

(defun gptel-auto-workflow--tracking-file (&optional run-id)
  "Return orphan commit tracking file path for RUN-ID or the active run."
  (expand-file-name
   (format "var/tmp/experiments/%s/commits.txt"
           (or run-id (gptel-auto-workflow--current-run-id)))
   (gptel-auto-workflow--project-root)))

(defun gptel-auto-workflow--tracking-files ()
  "Return all readable orphan commit tracking ledgers."
  (let ((base-dir (expand-file-name
                   (or gptel-auto-workflow-worktree-base "var/tmp/experiments")
                   (gptel-auto-workflow--worktree-base-root))))
    (when (file-directory-p base-dir)
      (sort (cl-remove-if-not #'file-readable-p
                              (directory-files-recursively base-dir "commits\\.txt\\'"))
            #'string<))))

(defun gptel-auto-workflow--untrack-commit (commit-hash &optional run-id-or-file)
  "Remove COMMIT-HASH from tracking ledgers.
When RUN-ID-OR-FILE is nil, remove the hash from all readable ledgers.
When it is an absolute path, use that ledger directly. Otherwise treat it as a run id.
Returns non-nil when at least one entry was removed."
  (when (gptel-auto-workflow--non-empty-string-p commit-hash)
    (let ((tracking-files
           (cond
            ((null run-id-or-file)
             (gptel-auto-workflow--tracking-files))
            ((file-name-absolute-p run-id-or-file)
             (list run-id-or-file))
            (t
             (list (gptel-auto-workflow--tracking-file run-id-or-file)))))
          removed)
      (dolist (tracking-file tracking-files removed)
        (when (file-exists-p tracking-file)
          (with-temp-buffer
            (insert-file-contents tracking-file)
            (let* ((lines (split-string (buffer-string) "\n" t))
                   (remaining
                    (cl-remove-if
                     (lambda (line)
                       (string-prefix-p (concat commit-hash " ") line))
                     lines)))
              (unless (= (length remaining) (length lines))
                (setq removed t)
                (if remaining
                    (with-temp-file tracking-file
                      (insert (mapconcat #'identity remaining "\n"))
                      (insert "\n"))
                  (delete-file tracking-file))))))))))

(defun gptel-auto-workflow--commit-exists-p (commit-hash)
  "Return non-nil when COMMIT-HASH resolves to an existing commit object."
  (and (gptel-auto-workflow--non-empty-string-p commit-hash)
       (eq 0 (cdr (gptel-auto-workflow--git-result
                   (format "git cat-file -e %s^{commit}"
                           (shell-quote-argument commit-hash))
                   30)))))

(defun gptel-auto-workflow--commit-patch-equivalent-p (commit-hash branch)
  "Return non-nil when COMMIT-HASH's patch is already represented in BRANCH."
  (and (gptel-auto-workflow--non-empty-string-p commit-hash)
       (gptel-auto-workflow--non-empty-string-p branch)
       (string-prefix-p
        "-"
        (gptel-auto-workflow--git-cmd
         (format "git cherry %s %s %s 2>/dev/null"
                 (shell-quote-argument branch)
                 (shell-quote-argument commit-hash)
                 (shell-quote-argument (concat commit-hash "^")))
         60))))

(defun gptel-auto-workflow--track-commit (experiment-id &optional target worktree-dir)
  "Save current commit hash to tracking file for EXPERIMENT-ID.
TARGET is optional description. Enables recovery if workflow interrupted.
Returns nil if git command fails or returns invalid hash."
  (let* ((default-directory (or worktree-dir
                                (gptel-auto-workflow--get-worktree-dir (or target gptel-auto-workflow--current-target))
                                (gptel-auto-workflow--project-root)))
         (commit-hash (gptel-auto-workflow--git-cmd "git rev-parse HEAD"))
         (tracking-file (gptel-auto-workflow--tracking-file))
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
       (if (and (file-exists-p tracking-file)
                (with-temp-buffer
                  (insert-file-contents tracking-file)
                  (re-search-forward
                   (format "^%s " (regexp-quote commit-hash))
                   nil t)))
           (message "[auto-workflow] Commit %s already tracked for exp-%s"
                    (gptel-auto-workflow--truncate-hash commit-hash)
                    experiment-id)
         (with-temp-buffer
           (insert (format "%s %s %s %s\n"
                           commit-hash
                           experiment-id
                           (or target "unknown")
                           (format-time-string "%H:%M:%S")))
           (append-to-file (point-min) (point-max) tracking-file))
         (message "[auto-workflow] Tracked commit %s for exp-%s"
                  (gptel-auto-workflow--truncate-hash commit-hash)
                  experiment-id))
       commit-hash))))

(defun gptel-auto-workflow--recover-orphans ()
  "Check for orphan commits from previous runs.
An orphan is a commit that exists but is not reachable from staging or main.
Returns list of (hash exp-id target) for truly orphaned commits."
  (interactive)
  (let* ((tracking-files (gptel-auto-workflow--tracking-files))
         (orphans nil)
         (seen (make-hash-table :test 'equal))
         (stale-hashes nil))
    (dolist (tracking-file tracking-files)
      (with-temp-buffer
        (insert-file-contents tracking-file)
        (dolist (line (split-string (buffer-string) "\n" t))
          (let* ((parts (split-string line))
                  (hash (car parts))
                  (exp-id (cadr parts))
                  (target (caddr parts)))
            (when (and hash
                       (>= (length parts) 3)
                       (string-match-p "^[a-f0-9]+$" hash)
                       (not (gethash hash seen)))
              (puthash hash t seen)
              (if (not (gptel-auto-workflow--commit-exists-p hash))
                  (push hash stale-hashes)
                (let ((in-staging (gptel-auto-workflow--git-cmd
                                   (format "git merge-base --is-ancestor %s staging 2>/dev/null && echo yes" hash)))
                      (in-main (gptel-auto-workflow--git-cmd
                                (format "git merge-base --is-ancestor %s main 2>/dev/null && echo yes" hash))))
                  (if (or (not (string-empty-p in-staging))
                          (not (string-empty-p in-main))
                          (gptel-auto-workflow--commit-patch-equivalent-p hash "staging")
                          (gptel-auto-workflow--commit-patch-equivalent-p hash "main"))
                      (push hash stale-hashes)
                    (push (list hash exp-id target) orphans)))))))))
    (dolist (hash (delete-dups stale-hashes))
      (when (gptel-auto-workflow--untrack-commit hash)
        (message "[auto-workflow] Removed stale orphan record %s"
                 (gptel-auto-workflow--truncate-hash hash))))
    (if orphans
        (message "[auto-workflow] Found %d orphan(s): %s"
                 (length orphans)
                 (mapconcat (lambda (o)
                              (gptel-auto-workflow--truncate-hash (car o)))
                            orphans " "))
      (message "[auto-workflow] No orphan commits found"))
    orphans))


(defun gptel-auto-workflow--cherry-pick-orphan (commit-hash)
  "Cherry-pick COMMIT-HASH to staging branch for recovery.
Returns t on success, `conflict' on cherry-pick conflicts, nil otherwise.
Uses the staging worktree only."
  (interactive "sCommit hash: ")
  (gptel-auto-workflow--with-staging-worktree
   (lambda ()
     (let* ((result (gptel-auto-workflow--git-result
                     (format "git cherry-pick -X theirs %s"
                             (shell-quote-argument commit-hash))
                     180))
            (output (car result))
            (exit-code (cdr result))
            (cherry-pick-head (unless (eq exit-code 0)
                                (gptel-auto-workflow--git-cmd
                                 "git rev-parse -q --verify CHERRY_PICK_HEAD 2>/dev/null"
                                 30)))
            (unmerged-files (unless (eq exit-code 0)
                              (gptel-auto-workflow--git-cmd
                               "git diff --name-only --diff-filter=U 2>/dev/null"
                               30)))
            (worktree-status (when (and (not (eq exit-code 0))
                                        (gptel-auto-workflow--non-empty-string-p cherry-pick-head))
                               (gptel-auto-workflow--git-cmd
                                "git status --porcelain 2>/dev/null"
                                30))))
        (cond
         ((eq exit-code 0)
          (message "[auto-workflow] %s recovered to %s"
                   (gptel-auto-workflow--truncate-hash commit-hash)
                   gptel-auto-workflow-staging-branch)
          t)
        ((and (gptel-auto-workflow--non-empty-string-p cherry-pick-head)
              (string-empty-p unmerged-files)
              (string-empty-p worktree-status))
         (ignore-errors (gptel-auto-workflow--git-cmd "git cherry-pick --skip" 60))
         (message "[auto-workflow] %s already in %s, skipping"
                  (gptel-auto-workflow--truncate-hash commit-hash)
                  gptel-auto-workflow-staging-branch)
         t)
        ((string-match-p "already applied\\|previous cherry-pick is now empty\\|The previous cherry-pick is now empty"
                         output)
         (ignore-errors (gptel-auto-workflow--git-cmd "git cherry-pick --skip" 60))
         (message "[auto-workflow] %s already in %s, skipping"
                  (gptel-auto-workflow--truncate-hash commit-hash)
                  gptel-auto-workflow-staging-branch)
         t)
        ((or (gptel-auto-workflow--non-empty-string-p unmerged-files)
             (string-match-p "CONFLICT\\|conflict" output))
         (ignore-errors (gptel-auto-workflow--git-cmd "git cherry-pick --abort" 60))
         (gptel-auto-workflow--log-conflict commit-hash output)
         (message "[auto-workflow] %s recovery failed: %s"
                  (gptel-auto-workflow--truncate-hash commit-hash)
                  (my/gptel--sanitize-for-logging output 160))
         'conflict)
        (t
         (ignore-errors (gptel-auto-workflow--git-cmd "git cherry-pick --abort" 60))
         (message "[auto-workflow] %s recovery failed: %s"
                  (gptel-auto-workflow--truncate-hash commit-hash)
                  (my/gptel--sanitize-for-logging output 160))
          nil))))))


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
If NO-PUSH is non-nil, skip pushing to origin (useful for cron jobs)."
  (interactive)
  (let ((orphans (gptel-auto-workflow--recover-orphans)))
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
  (let ((default-directory (gptel-auto-workflow--default-dir))
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
describes."
  (not (and (equal agent-type "executor")
            (or gptel-auto-workflow--current-target
                gptel-auto-workflow--current-project))))

(defun my/gptel--cacheable-subagent-result-p (result)
  "Return non-nil when RESULT is safe to reuse from the subagent cache.
Failure-shaped responses must not be cached, otherwise a transient API
quota error can poison later workflow attempts with immediate cache hits."
  (or (not (stringp result))
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
            result))))

(defun my/gptel--subagent-cache-get (agent-type prompt &optional files include-history include-diff)
  "Get cached result for (AGENT-TYPE, PROMPT, ...) if still valid.
Returns nil if cache disabled, not found, or expired."
  (when (and (my/gptel--subagent-cache-enabled-p)
             (my/gptel--subagent-cache-allowed-p agent-type))
    (let* ((key (my/gptel--subagent-cache-key agent-type prompt files include-history include-diff))
           (cached (gethash key my/gptel--subagent-cache)))
      (when cached
        (let ((timestamp (car cached))
              (result (cdr cached)))
          (if (> (- (float-time) timestamp) my/gptel-subagent-cache-ttl)
              (progn (remhash key my/gptel--subagent-cache) nil)
            (if (my/gptel--cacheable-subagent-result-p result)
                result
              (progn
                (remhash key my/gptel--subagent-cache)
                nil))))))))

(defun my/gptel--subagent-cache-put (agent-type prompt result &optional files include-history include-diff)
  "Cache RESULT for (AGENT-TYPE, PROMPT, ...).
Evicts oldest entries if cache exceeds `my/gptel-subagent-cache-max-size'."
  (when (and (my/gptel--subagent-cache-enabled-p)
             (my/gptel--subagent-cache-allowed-p agent-type)
             (my/gptel--cacheable-subagent-result-p result))
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
          (let* ((request-tools (and gptel-use-tools (copy-sequence gptel-tools)))
                 (parent-fsm (my/gptel--coerce-fsm gptel--fsm-last))
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
                 (child-fsm (gptel-make-fsm :table gptel-send--transitions
                                            :handlers gptel-agent-request--handlers))
                  (previous-fsm-local-p (local-variable-p 'gptel--fsm-last parent-buf))
                  (previous-fsm (and previous-fsm-local-p
                                     (buffer-local-value 'gptel--fsm-last parent-buf)))
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
                                                 (plist-get error-info :message))))
                               (if (and error-msg
                                        (stringp error-msg)
                                        (string-match-p "1013\\|server is initializing" error-msg))
                                   (funcall
                                    main-cb
                                    (format "Warning: Reviewer agent not available (server initializing). Auto-approving changes.\n\nError details: %S"
                                            error-info))
                                 (funcall
                                  main-cb
                                  (format "Error: Task %s could not finish task \"%s\". \n\nError details: %S"
                                          agent-type description error-info)))))
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
                               (my/gptel--subagent-cache-put agent-type prompt partial)
                               (my/gptel--deliver-subagent-result main-cb partial)))
                            ('abort
                             (when (overlayp ov) (delete-overlay ov))
                             (funcall
                              main-cb
                              (format "Error: Task \"%s\" was aborted by the user. \n%s could not finish."
                                      description agent-type)))))))
                    (my/gptel--seed-fsm-tools child-fsm request-tools)
                    (my/gptel--disable-auto-retry-for-fsm child-fsm)
                    (setq request-started t))
                (unless request-started
                  (with-current-buffer parent-buf
                    (if previous-fsm-local-p
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
         temp-file)
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

(with-eval-after-load 'gptel-agent-tools
  ;; REMOVED: Old :override advice conflicts with new :around advice
  ;; in gptel-auto-workflow-projects.el that routes to correct buffer
  ;; (advice-add 'gptel-agent--task :override #'my/gptel-agent--task-override)
  (advice-add 'gptel-agent--task-overlay :around #'my/gptel-agent--task-overlay-around)
  (advice-add 'gptel-agent--truncate-buffer :around #'my/gptel-agent--truncate-buffer-around))

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
  (let ((tracked
         (delete-dups
          (delq nil
                (list (and (boundp 'gptel-auto-workflow--worktree-buffers)
                           (hash-table-p gptel-auto-workflow--worktree-buffers)
                           (gethash root gptel-auto-workflow--worktree-buffers))
                      (and (boundp 'gptel-auto-workflow--project-buffers)
                           (hash-table-p gptel-auto-workflow--project-buffers)
                           (gethash root gptel-auto-workflow--project-buffers)))))))
    (or (memq buffer tracked)
        (string-prefix-p "*gptel-agent:" (buffer-name buffer)))))

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
  "Abort STATE's live request buffer and discard stale worktree buffers when possible."
  (when-let* ((request-buf (my/gptel--agent-task-request-buffer state)))
    (if-let ((worktree-dir (my/gptel--agent-task-request-worktree-dir state)))
        (gptel-auto-workflow--discard-worktree-buffers worktree-dir)
      (when (and (buffer-live-p request-buf)
                 (fboundp 'gptel-abort))
        (ignore-errors (gptel-abort request-buf))))))

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

(defun my/gptel--agent-task-note-message-activity (&rest _args)
  "Treat worktree-context messages as executor activity."
  (my/gptel--agent-task-note-context-activity))

(unless (advice-member-p 'message #'my/gptel--agent-task-note-message-activity)
  (advice-add 'message :before #'my/gptel--agent-task-note-message-activity))

(defun my/gptel--agent-task-note-curl-activity (&rest _args)
  "Treat gptel curl request setup as active subagent progress."
  (my/gptel--agent-task-note-active-activity))

(with-eval-after-load 'gptel-request
  (unless (advice-member-p 'gptel-curl--get-args #'my/gptel--agent-task-note-curl-activity)
    (advice-add 'gptel-curl--get-args :before
                #'my/gptel--agent-task-note-curl-activity)))

(defun my/gptel--register-agent-task-buffer (buffer)
  "Record BUFFER as the active request buffer for the current subagent task."
  (when (and my/gptel--current-agent-task-id
             (buffer-live-p buffer))
    (when-let* ((state (gethash my/gptel--current-agent-task-id
                                my/gptel--agent-task-state)))
      (puthash my/gptel--current-agent-task-id
               (plist-put state :request-buf buffer)
               my/gptel--agent-task-state)))
  buffer)

(defun my/gptel--reset-agent-task-state ()
  "Abort and clear all tracked subagent task state."
  (let (request-buffers)
    (maphash
     (lambda (_task-id state)
       (when (timerp (plist-get state :timeout-timer))
          (cancel-timer (plist-get state :timeout-timer)))
       (when (timerp (plist-get state :progress-timer))
          (cancel-timer (plist-get state :progress-timer)))
       (when-let* ((request-buf (my/gptel--agent-task-request-buffer state)))
         (push request-buf request-buffers)))
     my/gptel--agent-task-state)
     ;; Clear state before aborting so synchronous abort callbacks are treated
     ;; as stale and cannot mutate workflow state. Abort the live request
     ;; buffer so stale tool writes stop too.
     (clrhash my/gptel--agent-task-state)
     (dolist (request-buf (delete-dups request-buffers))
       (when (and (buffer-live-p request-buf)
                  (fboundp 'gptel-abort))
         (condition-case err
             (gptel-abort request-buf)
           (error
            (message "[nucleus] Failed to abort stale subagent buffer %s: %s"
                     (buffer-name request-buf)
                     (my/gptel--sanitize-for-logging
                      (error-message-string err) 160))))))))

(defun my/gptel--call-gptel-agent-task (callback agent-type description prompt)
  "Invoke the active gptel subagent task runner.
In headless auto-workflow runs, bypass `gptel-agent-loop-task' to avoid
its async continuation layer in the worker daemon."
  (let ((headless-auto-workflow
         (and (bound-and-true-p gptel-auto-workflow--headless)
              (bound-and-true-p gptel-auto-workflow-persistent-headless)
              (bound-and-true-p gptel-auto-workflow--current-project)))
        (task-runner nil))
    (setq task-runner
          (cond
           ((and headless-auto-workflow
                 (fboundp 'my/gptel-agent--task-override))
            #'my/gptel-agent--task-override)
           ((fboundp 'gptel-agent--task) #'gptel-agent--task)
           ((fboundp 'my/gptel-agent--task-override)
            #'my/gptel-agent--task-override)
           (t
            (error "[nucleus] No gptel-agent task runner available"))))
    (if (and headless-auto-workflow
             (boundp 'gptel-agent-loop--bypass))
        (let ((gptel-agent-loop--bypass t))
          (funcall task-runner callback agent-type description prompt))
      (funcall task-runner callback agent-type description prompt))))

(defun my/gptel--disable-auto-retry-for-fsm (fsm)
  "Mark FSM so global auto-retry advice will not reschedule it."
  (when (and fsm (fboundp 'gptel-fsm-info))
    (when-let* ((info (ignore-errors (gptel-fsm-info fsm)))
                ((listp info)))
      (plist-put info :disable-auto-retry t)
      t)))

(defun my/gptel--disable-auto-retry-transform (fsm)
  "Mark FSM as no-retry before request dispatch."
  (my/gptel--disable-auto-retry-for-fsm fsm))

(defun my/gptel--agent-task-with-timeout (callback agent-type description prompt &optional files include-history include-diff)
  "Wrapper around `gptel-agent--task' that adds a timeout and progress messages.
CALLBACK is called with the result or a timeout error.
Uses hash table keyed by task-id to support parallel execution."
  (let* ((task-id (cl-incf my/gptel--agent-task-counter))
         (start-time (current-time))
         (task-timeout my/gptel-agent-task-timeout)
         (origin-buf (current-buffer))
         (parent-fsm-local-p (local-variable-p 'gptel--fsm-last origin-buf))
         (parent-fsm (and parent-fsm-local-p
                          (buffer-local-value 'gptel--fsm-last origin-buf)))
         (child-fsm nil)
         (packaged-prompt
          (my/gptel--build-subagent-context
           prompt files include-history include-diff origin-buf))
         (restore-origin-fsm
          (lambda (&optional expected-fsm)
            (when (buffer-live-p origin-buf)
              (with-current-buffer origin-buf
                (when (or (null expected-fsm)
                          (eq gptel--fsm-last expected-fsm))
                  (if parent-fsm-local-p
                      (setq-local gptel--fsm-last parent-fsm)
                    (kill-local-variable 'gptel--fsm-last)))))))
         (wrapped-cb
          (lambda (result)
            (let* ((state (gethash task-id my/gptel--agent-task-state))
                   (already-done (plist-get state :done)))
              (if (not state)
                  (message "[nucleus] Ignoring stale subagent %s callback after reset"
                           agent-type)
                ;; Atomic test-and-set: mark done before acting to prevent
                ;; double-invocation if gptel-abort fires synchronously in timeout.
                (puthash task-id (plist-put state :done t) my/gptel--agent-task-state)
                (unless already-done
                  (when (timerp (plist-get state :timeout-timer))
                    (cancel-timer (plist-get state :timeout-timer)))
                  (when (timerp (plist-get state :progress-timer))
                    (cancel-timer (plist-get state :progress-timer)))
                  (message "[nucleus] Subagent %s completed in %.1fs, result-len=%d"
                           agent-type (float-time (time-since start-time))
                           (if (stringp result) (length result) 0))
                  (funcall restore-origin-fsm child-fsm)
                  (unwind-protect
                      (funcall callback result)
                    (remhash task-id my/gptel--agent-task-state))))))))
    (let* ((uses-idle-timeout
            (my/gptel--agent-task-uses-idle-timeout-p agent-type))
           (hard-timeout
            (and uses-idle-timeout
                 (integerp my/gptel-agent-task-hard-timeout)
                 (> my/gptel-agent-task-hard-timeout 0)
                 my/gptel-agent-task-hard-timeout))
           (hard-deadline
            (and hard-timeout
                 (time-add start-time (seconds-to-time hard-timeout))))
           rearm-timeout note-buffer-activity)
      (setq rearm-timeout
            (lambda (state)
              (when task-timeout
                (when (timerp (plist-get state :timeout-timer))
                  (cancel-timer (plist-get state :timeout-timer)))
                (let* ((remaining-hard-seconds
                        (and hard-deadline
                             (max 0
                                  (ceiling
                                   (float-time
                                    (time-subtract hard-deadline (current-time)))))))
                       (next-delay (if remaining-hard-seconds
                                       (min task-timeout remaining-hard-seconds)
                                     task-timeout)))
                  (setq state
                        (plist-put
                         state :timeout-timer
                         (run-at-time
                          next-delay nil
                          (lambda ()
                            (let* ((state (gethash task-id my/gptel--agent-task-state))
                                   (already-done (plist-get state :done))
                                   (last-activity (plist-get state :last-activity-time))
                                   (idle-seconds (and last-activity
                                                      (float-time (time-since last-activity))))
                                   (remaining-hard
                                    (and hard-deadline
                                         (float-time
                                          (time-subtract hard-deadline (current-time)))))
                                   (hard-expired (and remaining-hard
                                                      (<= remaining-hard 0)))
                                   (timeout-seconds (if hard-expired
                                                        hard-timeout
                                                      task-timeout))
                                   (timeout-suffix (if hard-expired
                                                       " total runtime"
                                                     "")))
                              (when state
                                (cond
                                 (already-done nil)
                                 ((and uses-idle-timeout
                                       (not hard-expired)
                                       idle-seconds
                                       (< idle-seconds task-timeout))
                                  (funcall rearm-timeout state))
                                  (t
                                   (puthash task-id (plist-put state :done t)
                                            my/gptel--agent-task-state)
                                   (when (timerp (plist-get state :progress-timer))
                                     (cancel-timer (plist-get state :progress-timer)))
                                   (message "[nucleus] Subagent %s timed out after %ds%s, aborting request"
                                            agent-type timeout-seconds timeout-suffix)
                                   (my/gptel--cleanup-agent-request-buffer state)
                                   (let ((timeout-result
                                          (format "Error: Task \"%s\" (%s) timed out after %ds%s."
                                                  description agent-type timeout-seconds timeout-suffix)))
                                     (funcall restore-origin-fsm child-fsm)
                                     (if (buffer-live-p origin-buf)
                                        (with-current-buffer origin-buf
                                          (unwind-protect
                                              (funcall callback timeout-result)
                                            (remhash task-id my/gptel--agent-task-state)))
                                      (unwind-protect
                                          (funcall callback timeout-result)
                                        (remhash task-id my/gptel--agent-task-state)))))))))))))
                  (puthash task-id state my/gptel--agent-task-state))
                state))
      (setq note-buffer-activity
            (lambda (state)
              (when uses-idle-timeout
                (when-let* ((request-buf (my/gptel--agent-task-request-buffer state))
                            ((buffer-live-p request-buf)))
                  (let* ((current-tick (my/gptel--agent-task-buffer-tick request-buf))
                         (last-tick (plist-get state :last-buffer-tick)))
                    (when (and current-tick (not (equal current-tick last-tick)))
                      (setq state (plist-put state :last-buffer-tick current-tick))
                      (setq state (plist-put state :last-activity-time (current-time)))
                      (setq state (funcall rearm-timeout state))))))
              state))
      (message "[nucleus] Delegating to subagent %s%s..."
               agent-type
               (if task-timeout
                   (format " (%s: %ds%s)"
                           (if uses-idle-timeout "idle timeout" "timeout")
                           task-timeout
                           (if (and hard-timeout (> hard-timeout task-timeout))
                               (format ", max runtime: %ds" hard-timeout)
                             ""))
                 ""))
      (let ((progress-timer
             (run-at-time my/gptel-subagent-progress-interval
                          my/gptel-subagent-progress-interval
                          (lambda ()
                            (let ((state (gethash task-id my/gptel--agent-task-state)))
                              (when (gptel-auto-workflow--state-active-p state)
                                (funcall note-buffer-activity state)
                                (message "[nucleus] Subagent %s still running... (%.1fs elapsed)"
                                         agent-type (float-time (time-since start-time)))))))))
        (puthash task-id (list :done nil
                               :timeout-timer nil
                               :progress-timer progress-timer
                               :origin-buf origin-buf
                               :request-buf nil
                               :last-buffer-tick nil
                               :last-activity-time (current-time)
                               :agent-type agent-type
                               :activity-dir (and (stringp default-directory)
                                                  (expand-file-name default-directory)))
                 my/gptel--agent-task-state)
        (when task-timeout
          (let ((state (gethash task-id my/gptel--agent-task-state)))
            (funcall rearm-timeout state)))
        (let ((my/gptel--current-agent-task-id task-id)
              (my/gptel--subagent-origin-buffer origin-buf))
          (let ((request-started nil)
                (launch-error nil))
            (unwind-protect
                (condition-case err
                    (progn
                      (my/gptel--call-gptel-agent-task
                       wrapped-cb agent-type description packaged-prompt)
                      (setq request-started t)
                       (when-let* ((state (gethash task-id my/gptel--agent-task-state))
                                   (request-buf (my/gptel--agent-task-request-buffer state))
                                   ((buffer-live-p request-buf)))
                         (with-current-buffer request-buf
                           (when (local-variable-p 'gptel--fsm-last)
                             (setq child-fsm gptel--fsm-last)
                             (when (and (boundp 'gptel-tools)
                                        gptel-tools)
                               (my/gptel--seed-fsm-tools child-fsm gptel-tools))
                             (my/gptel--disable-auto-retry-for-fsm child-fsm)))
                         (let* ((state (gethash task-id my/gptel--agent-task-state))
                                (tick (my/gptel--agent-task-buffer-tick request-buf)))
                           (when (and state tick)
                            (puthash task-id
                                     (plist-put state :last-buffer-tick tick)
                                     my/gptel--agent-task-state)))))
                  (error
                   (setq launch-error err)))
              (unless request-started
                (funcall restore-origin-fsm)))
            (when launch-error
              (let* ((state (gethash task-id my/gptel--agent-task-state))
                     (timeout-timer (and state (plist-get state :timeout-timer)))
                     (progress-timer (and state (plist-get state :progress-timer)))
                     (request-buf (and state
                                       (my/gptel--agent-task-request-buffer state))))
                   (when state
                     (when (timerp timeout-timer)
                       (cancel-timer timeout-timer))
                     (when (timerp progress-timer)
                       (cancel-timer progress-timer))
                     (remhash task-id my/gptel--agent-task-state))
                 (funcall restore-origin-fsm child-fsm)
                 (my/gptel--cleanup-agent-request-buffer state)
                 (message "[nucleus] Subagent %s failed before startup completed: %s"
                          agent-type
                          (my/gptel--sanitize-for-logging
                           (error-message-string launch-error) 160))
                 (funcall callback
                         (format "Error: Task runner failed for %s: %s"
                                 agent-type
                                 (error-message-string launch-error)))))))))))

(cl-defun my/gptel--run-agent-tool (callback &optional agent-name description prompt files include-history include-diff)
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
    (unless (gptel-auto-workflow--non-empty-string-p prompt)
      (funcall callback "Error: prompt is empty")
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
      ;; Apply defaults only when input is nil, not when explicitly "false"
      ;; (my/gptel--string-to-bool returns nil for both, so check original input)
      (when (null include-history)
        (setq include-history-bool my/gptel-subagent-include-history-default))
      (my/gptel--agent-task-with-timeout callback agent-name description prompt files
                                         include-history-bool include-diff-bool))))

(defun my/gptel--run-agent-tool-with-timeout (timeout callback agent-name description prompt
                                                      &optional files include-history include-diff)
  "Run `my/gptel--run-agent-tool' with TIMEOUT forced for this one dispatch."
  (let ((previous-timeout my/gptel-agent-task-timeout)
        (previous-hard-timeout my/gptel-agent-task-hard-timeout))
    (unwind-protect
        (progn
          (setq my/gptel-agent-task-timeout timeout)
          (setq my/gptel-agent-task-hard-timeout
                (and (equal agent-name "executor")
                     (integerp timeout)
                     (> timeout 0)
                     (integerp gptel-auto-experiment-active-grace)
                     (> gptel-auto-experiment-active-grace 0)
                     (+ timeout gptel-auto-experiment-active-grace)))
          (my/gptel--run-agent-tool callback agent-name description prompt
                                    files include-history include-diff))
      (setq my/gptel-agent-task-timeout previous-timeout
            my/gptel-agent-task-hard-timeout previous-hard-timeout))))

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

(defcustom gptel-auto-experiment-active-grace 300
  "Extra wall-clock seconds active executor experiments may use beyond budget.

Executor requests still use `gptel-auto-experiment-time-budget' as their idle
timeout, but active runs may exceed it by this grace period before they are
forcibly aborted."
  :type 'integer
  :safe #'integerp
  :group 'gptel-tools-agent)

(defcustom gptel-auto-experiment-validation-retry-time-budget 180
  "Timeout budget in seconds for validation-retry executor calls.

Validation retries should repair one known error in the current worktree, so
they use a shorter budget than full experiments."
  :type 'integer
  :safe #'integerp
  :group 'gptel-tools-agent)

(defcustom gptel-auto-experiment-validation-retry-active-grace 60
  "Extra wall-clock seconds active validation-retry calls may use beyond budget."
  :type 'integer
  :safe #'integerp
  :group 'gptel-tools-agent)

(defcustom gptel-auto-experiment-delay-between 3
  "Seconds to wait between experiments to avoid API rate limits."
  :type 'integer
  :safe #'integerp
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-review-time-budget 600
  "Timeout budget in seconds for staging review subagent calls."
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
(defvar gptel-auto-workflow--review-error-retry-count 0
  "Retry count for transient reviewer transport failures.")
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
  "Get worktree-dir for TARGET from hash table.
Returns nil if directory doesn't exist or state is invalid."
  (when-let* ((dir (gptel-auto-workflow--get-worktree-state target :worktree-dir))
              ((stringp dir))
              ((file-directory-p dir)))
    dir))

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
         (host (system-name)))
    (if experiment-id
        (format "optimize/%s-%s-exp%d" name host experiment-id)
      (format "optimize/%s-%s" name host))))

(defun gptel-auto-workflow--branch-worktree-paths (branch &optional proj-root)
  "Return attached worktree paths for BRANCH within PROJ-ROOT.
BRANCH should be the short local branch name, e.g. optimize/foo-exp1."
  (let ((default-directory (or proj-root (gptel-auto-workflow--default-dir)))
        (buffer (generate-new-buffer " *git-worktree-list*"))
        (paths nil)
        (branch-ref (format "refs/heads/%s" branch)))
    (unwind-protect
        (when (eq 0 (call-process "git" nil buffer nil "worktree" "list" "--porcelain"))
          (with-current-buffer buffer
            (dolist (entry (split-string (buffer-string) "\n\n+" t))
              (when (string-match-p (format "^branch %s$" (regexp-quote branch-ref))
                                    entry)
                (when (string-match "^worktree \\(.*\\)$" entry)
                  (push (match-string 1 entry) paths))))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))
    (nreverse (delete-dups paths))))

(defun gptel-auto-workflow--optimize-worktrees (&optional proj-root)
  "Return attached optimize worktrees for the current host within PROJ-ROOT.
Each item is a plist with keys :branch and :path."
  (let* ((default-directory (or proj-root (gptel-auto-workflow--default-dir)))
         (buffer (generate-new-buffer " *git-worktree-list*"))
         (entries nil)
         (suffix (concat (gptel-auto-workflow--experiment-suffix) "-exp"))
         (branch-pattern (format "\\`optimize/.+-%s[0-9]+\\'"
                                 (regexp-quote suffix))))
    (unwind-protect
        (when (eq 0 (call-process "git" nil buffer nil "worktree" "list" "--porcelain"))
          (with-current-buffer buffer
            (dolist (entry (split-string (buffer-string) "\n\n+" t))
              (let (path branch)
                (when (string-match "^worktree \\(.*\\)$" entry)
                  (setq path (match-string 1 entry)))
                (when (string-match "^branch refs/heads/\\(optimize/.+\\)$" entry)
                  (setq branch (match-string 1 entry)))
                (when (and path branch
                           (string-match-p branch-pattern branch))
                  (push (list :branch branch :path path) entries))))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))
    (nreverse entries)))

(defun gptel-auto-workflow--discard-worktree-buffers (worktree-dir)
  "Abort, kill, and unregister live gptel buffers rooted at WORKTREE-DIR."
  (when (and (stringp worktree-dir)
             (> (length worktree-dir) 0))
    (let* ((root (file-name-as-directory (expand-file-name worktree-dir)))
            (tracked
             (delete-dups
              (delq nil
                    (list (and (boundp 'gptel-auto-workflow--worktree-buffers)
                               (hash-table-p gptel-auto-workflow--worktree-buffers)
                               (gethash root gptel-auto-workflow--worktree-buffers))
                          (and (boundp 'gptel-auto-workflow--project-buffers)
                               (hash-table-p gptel-auto-workflow--project-buffers)
                               (gethash root gptel-auto-workflow--project-buffers))))))
            (killed 0))
      (dolist (buf (delete-dups (append tracked (buffer-list))))
        (when (buffer-live-p buf)
          (with-current-buffer buf
            (let ((buf-dir
                   (and (stringp default-directory)
                        (file-name-as-directory
                         (expand-file-name default-directory)))))
              (when (and buf-dir
                         (string-prefix-p root buf-dir)
                         (or (memq buf tracked)
                             (string-prefix-p "*gptel-agent:" (buffer-name buf))))
                (when (fboundp 'gptel-abort)
                  (ignore-errors (gptel-abort buf)))
                (let ((kill-buffer-query-functions nil))
                  (kill-buffer buf))
                (cl-incf killed))))))
      (when (and (boundp 'gptel-auto-workflow--worktree-buffers)
                 (hash-table-p gptel-auto-workflow--worktree-buffers))
        (remhash root gptel-auto-workflow--worktree-buffers))
      (when (and (boundp 'gptel-auto-workflow--project-buffers)
                 (hash-table-p gptel-auto-workflow--project-buffers))
        (remhash root gptel-auto-workflow--project-buffers))
      killed)))

(defun gptel-auto-workflow-create-worktree (target &optional experiment-id)
  "Create worktree for TARGET. EXPERIMENT-ID creates numbered branch.
Stores worktree-dir, current-branch in hash table keyed by TARGET.
Uses git CLI directly to avoid magit-worktree-branch hangs.
If branch exists locally, deletes it first to avoid conflicts."
  (let* ((proj-root (gptel-auto-workflow--worktree-base-root))
         (branch (gptel-auto-workflow--branch-name target experiment-id))
         (base-ref nil)
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
            (setq base-ref (gptel-auto-workflow--staging-main-ref))
            (unless base-ref
              (error "missing main ref for experiment worktree"))
            (gptel-auto-workflow--discard-worktree-buffers worktree-dir)
            (call-process "git" nil stderr-buffer nil "worktree" "prune")
            (dolist (existing-worktree
                     (gptel-auto-workflow--branch-worktree-paths branch proj-root))
              (gptel-auto-workflow--discard-worktree-buffers existing-worktree)
              (message "[auto-workflow] Removing stale worktree for %s: %s"
                       branch existing-worktree)
              (call-process "git" nil stderr-buffer nil
                            "worktree" "remove" "-f" existing-worktree)
              (when (file-exists-p existing-worktree)
                (delete-directory existing-worktree t)))
            ;; Remove existing worktree if present (stale from previous run)
            (when (file-exists-p worktree-dir)
              (gptel-auto-workflow--discard-worktree-buffers worktree-dir)
              (call-process "git" nil stderr-buffer nil "worktree" "remove" "-f" worktree-dir)
              ;; Stale nested bug fallout can leave a plain directory here even
              ;; when Git no longer considers it an attached worktree.
              (when (file-exists-p worktree-dir)
                (delete-directory worktree-dir t)))
            ;; Delete branch if it exists locally (stale from previous run)
            (call-process "git" nil stderr-buffer nil "branch" "-D" branch)
            (when (buffer-live-p stderr-buffer)
              (with-current-buffer stderr-buffer
                (erase-buffer)))
            ;; Create worktree with new branch
            (let* ((exit-code (call-process "git" nil stderr-buffer nil
                                            "worktree" "add" "-b" branch
                                            worktree-dir base-ref))
                   (stderr-output (when (buffer-live-p stderr-buffer)
                                    (with-current-buffer stderr-buffer
                                      (buffer-string))))
                    (stderr-preview (my/gptel--sanitize-for-logging stderr-output 200)))
              (unless (eq exit-code 0)
                (when stderr-output
                  (message "[auto-workflow] Git stderr: %s" stderr-preview))
                (error "git worktree add failed with exit code %s: %s"
                       exit-code (or stderr-preview "no output")))))
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
    (when worktree-dir
      (gptel-auto-workflow--discard-worktree-buffers worktree-dir)
      (when (file-exists-p worktree-dir)
        (let ((proj-root (gptel-auto-workflow--worktree-base-root)))
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
             (message "[auto-workflow] Failed to delete worktree: %s" err))))))
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

(defun gptel-auto-workflow--staging-main-ref ()
  "Return the safe main ref staging and experiments should mirror.
Prefer local `main' when it either matches `origin/main' or is a clean
ahead-only tip. Otherwise use `origin/main' so dirty or diverged local
state does not leak into workflow branches."
  (let ((default-directory (gptel-auto-workflow--default-dir)))
    (let* ((main-result (gptel-auto-workflow--git-result
                         "git rev-parse --verify main"
                         60))
           (origin-result (gptel-auto-workflow--git-result
                           "git rev-parse --verify origin/main"
                           60))
           (have-main (= 0 (cdr main-result)))
           (have-origin (= 0 (cdr origin-result)))
           (main-hash (and have-main (string-trim (car main-result))))
           (origin-hash (and have-origin (string-trim (car origin-result)))))
      (cond
       ((and have-main have-origin)
        (if (string= main-hash origin-hash)
            "main"
          (let* ((status-result (gptel-auto-workflow--git-result
                                 "git status --porcelain"
                                 60))
                 (clean-main (and (= 0 (cdr status-result))
                                  (string-empty-p (string-trim (car status-result)))))
                 (ahead-result (and clean-main
                                    (gptel-auto-workflow--git-result
                                     "git rev-list --left-right --count origin/main...main"
                                     60)))
                 (ahead-counts (and ahead-result
                                    (= 0 (cdr ahead-result))
                                    (split-string (string-trim (car ahead-result))
                                                  "[[:space:]]+" t)))
                 (behind-count (and (= (length ahead-counts) 2)
                                    (string-to-number (nth 0 ahead-counts))))
                 (ahead-count (and (= (length ahead-counts) 2)
                                   (string-to-number (nth 1 ahead-counts)))))
            (if (and clean-main
                     (numberp behind-count)
                     (numberp ahead-count)
                     (= behind-count 0)
                     (> ahead-count 0))
                (progn
                  (message "[auto-workflow] Local main is clean and ahead of origin/main; using main as workflow base")
                  "main")
              (message "[auto-workflow] Local main differs from origin/main; using origin/main as workflow base")
              "origin/main"))))
       (have-origin
        "origin/main")
       (have-main
        "main")
       (t
        (message "[auto-workflow] Missing main ref for staging sync")
        nil)))))


(defun gptel-auto-workflow--sync-staging-from-main ()
  "Sync staging branch from main at workflow start.
Creates a fresh staging worktree and never checks out staging in the root repo."
  (let* ((proj-root (gptel-auto-workflow--project-root))
         (default-directory proj-root)
         (staging gptel-auto-workflow-staging-branch)
         (main-ref nil))
    (message "[auto-workflow] Syncing staging from main")
    (if (not (gptel-auto-workflow--ensure-staging-branch-exists))
        nil
      (setq main-ref (gptel-auto-workflow--staging-main-ref))
      (if (not main-ref)
          nil
        (let ((worktree (gptel-auto-workflow--create-staging-worktree)))
          (if (not worktree)
            nil
            (let ((default-directory worktree))
              (let* ((results (list
                               (gptel-auto-workflow--git-result
                                (format "git checkout %s" (shell-quote-argument staging))
                                60)
                               (gptel-auto-workflow--git-result
                                (format "git reset --hard %s"
                                        (shell-quote-argument main-ref))
                                180)))
                     (failed (cl-find-if (lambda (item) (/= 0 (cdr item))) results)))
                (if failed
                    (progn
                      (message "[auto-workflow] Failed to sync staging: %s"
                               (my/gptel--sanitize-for-logging (car failed) 160))
                      nil)
                  (message "[auto-workflow] ✓ Staging synced from main")
                  t)))))))))



(defun gptel-auto-workflow--create-staging-worktree ()
  "Create isolated worktree for staging verification.
Never touches project root - all verification happens in the worktree.
Returns worktree path or nil on failure."
  (let* ((proj-root (gptel-auto-workflow--worktree-base-root))
         (default-directory proj-root)
         (branch gptel-auto-workflow-staging-branch)
         (worktree-base-dir (or gptel-auto-workflow-worktree-base
                                "var/tmp/experiments"))
         (worktree-dir (expand-file-name
                        (format "%s/staging-verify" worktree-base-dir)
                        proj-root))
         (worktree-q (shell-quote-argument worktree-dir))
         (branch-q (shell-quote-argument branch)))
    (gptel-auto-workflow--with-error-handling
     "create staging worktree"
     (lambda ()
        (unless (gptel-auto-workflow--ensure-staging-branch-exists)
          (error "staging branch %s is unavailable" branch))
        (gptel-auto-workflow--discard-worktree-buffers worktree-dir)
        (when (or (file-exists-p worktree-dir)
                  (string-match-p (regexp-quote worktree-dir)
                                  (gptel-auto-workflow--git-cmd "git worktree list" 60)))
          (gptel-auto-workflow--cleanup-staging-submodule-worktrees worktree-dir)
          (ignore-errors
            (gptel-auto-workflow--git-cmd
             (format "git worktree remove --force %s" worktree-q)
             180))
          (ignore-errors (delete-directory worktree-dir t)))
       (make-directory (file-name-directory worktree-dir) t)
        (let ((add-result
               (gptel-auto-workflow--git-result
                (format "git worktree add --force %s %s" worktree-q branch-q)
                180)))
          (unless (= 0 (cdr add-result))
            (error "git worktree add failed: %s" (car add-result))))
        (setq gptel-auto-workflow--staging-worktree-dir worktree-dir)
        (message "[auto-workflow] Created staging worktree: %s" worktree-dir)
        worktree-dir))))



(defun gptel-auto-workflow--delete-staging-worktree ()
  "Delete staging verification worktree.
NOTE: Staging branch is never deleted, only the worktree."
  (when gptel-auto-workflow--staging-worktree-dir
    (let* ((proj-root (gptel-auto-workflow--project-root))
           (default-directory proj-root)
            (worktree gptel-auto-workflow--staging-worktree-dir))
      (gptel-auto-workflow--with-error-handling
       "delete staging worktree"
       (lambda ()
          (gptel-auto-workflow--discard-worktree-buffers worktree)
          (gptel-auto-workflow--cleanup-staging-submodule-worktrees worktree)
          (ignore-errors
             (gptel-auto-workflow--git-cmd
              (format "git worktree remove --force %s"
                      (shell-quote-argument worktree))
             180))
         (when (file-exists-p worktree)
           (ignore-errors (delete-directory worktree t))))))
    (setq gptel-auto-workflow--staging-worktree-dir nil)))

(defun gptel-auto-workflow--staging-submodule-paths (&optional worktree)
  "Return top-level submodule paths declared in WORKTREE."
  (let* ((root (or worktree gptel-auto-workflow--staging-worktree-dir))
         (gitmodules (and root (expand-file-name ".gitmodules" root)))
         paths)
    (when (and gitmodules (file-readable-p gitmodules))
      (with-temp-buffer
        (insert-file-contents gitmodules)
        (goto-char (point-min))
        (while (re-search-forward "^[[:space:]]*path = \\(.+\\)$" nil t)
          (push (string-trim (match-string 1)) paths))))
    (nreverse paths)))

(defun gptel-auto-workflow--staging-submodule-gitlink-revision (worktree path)
  "Return the gitlink revision for PATH in WORKTREE, or nil."
  (let* ((default-directory worktree)
         (result (gptel-auto-workflow--git-result
                  (format "git ls-tree HEAD -- %s" (shell-quote-argument path))
                  60))
         (output (car result)))
    (when (and (= 0 (cdr result))
               (string-match "160000 commit \\([0-9a-f]\\{40\\}\\)\t" output))
      (match-string 1 output))))

(defun gptel-auto-workflow--submodule-checkout-git-dir (path)
  "Return the absolute git-common-dir for the root checkout of submodule PATH."
  (let* ((proj-root (gptel-auto-workflow--default-dir))
         (checkout (expand-file-name path proj-root)))
    (when (file-directory-p checkout)
      (let* ((git-common-result
              (gptel-auto-workflow--git-result
               (format "git -C %s rev-parse --git-common-dir"
                       (shell-quote-argument checkout))
               60))
             (git-common (string-trim (car git-common-result))))
        (when (and (= 0 (cdr git-common-result))
                   (not (string-empty-p git-common)))
          (expand-file-name git-common checkout))))))

(defun gptel-auto-workflow--git-dir-has-commit-p (git-dir commit)
  "Return non-nil when GIT-DIR contains COMMIT.
When COMMIT is nil, only check that GIT-DIR exists."
  (and (file-directory-p git-dir)
       (or (not commit)
           (= 0 (cdr (gptel-auto-workflow--git-result
                      (format "git --git-dir=%s cat-file -e %s^{commit}"
                              (shell-quote-argument git-dir)
                              (shell-quote-argument commit))
                      60))))))

(defun gptel-auto-workflow--shared-submodule-git-dir (path &optional commit)
  "Return a local git dir for submodule PATH that can materialize COMMIT.
Prefer the current checkout when it is a standalone repo, then fall back to the
superproject-managed `.git/modules/...` store."
  (let* ((proj-root (gptel-auto-workflow--default-dir))
         (checkout-git-dir (gptel-auto-workflow--submodule-checkout-git-dir path))
         (module-git-dir (expand-file-name (format ".git/modules/%s" path) proj-root))
         (candidates (cl-remove-duplicates
                      (delq nil (list checkout-git-dir module-git-dir))
                      :test #'string=)))
    (cl-find-if (lambda (git-dir)
                  (gptel-auto-workflow--git-dir-has-commit-p git-dir commit))
                candidates)))

(defun gptel-auto-workflow--cleanup-staging-submodule-worktree (worktree path)
  "Remove any staged submodule worktree for PATH under WORKTREE."
  (let* ((shared-git-dir (gptel-auto-workflow--shared-submodule-git-dir path))
         (target (expand-file-name path worktree)))
    (when (file-directory-p shared-git-dir)
      (ignore-errors
        (gptel-auto-workflow--git-result
         (format "git --git-dir=%s worktree prune --expire now"
                 (shell-quote-argument shared-git-dir))
         60))
      (ignore-errors
        (gptel-auto-workflow--git-result
         (format "git --git-dir=%s worktree remove --force %s"
                 (shell-quote-argument shared-git-dir)
                 (shell-quote-argument target))
         60)))
    (cond
     ((file-directory-p target)
      (ignore-errors (delete-directory target t)))
     ((file-exists-p target)
      (ignore-errors (delete-file target))))))

(defun gptel-auto-workflow--cleanup-staging-submodule-worktrees (&optional worktree)
  "Remove staged top-level submodule worktrees from WORKTREE."
  (let ((root (or worktree gptel-auto-workflow--staging-worktree-dir)))
    (when (and root (file-exists-p root))
      (dolist (path (gptel-auto-workflow--staging-submodule-paths root))
        (gptel-auto-workflow--cleanup-staging-submodule-worktree root path)))))

(defun gptel-auto-workflow--strip-ansi-escapes (text)
  "Return TEXT with ANSI color escape sequences removed."
  (if (not (stringp text))
      ""
    (replace-regexp-in-string "\x1b\\[[0-9;]*[[:alpha:]]" "" text t t)))

(defun gptel-auto-workflow--extract-failed-tests (output)
  "Return unique verification failure signatures parsed from OUTPUT."
  (let (failed)
    (when (stringp output)
      (with-temp-buffer
        (insert (gptel-auto-workflow--strip-ansi-escapes output))
        (goto-char (point-min))
        (while (re-search-forward
                "^   FAILED[[:space:]]+[0-9]+/[0-9]+[[:space:]]+\\([^[:space:]\n]+\\)"
                nil t)
          (push (match-string 1) failed))
        (goto-char (point-min))
        (while (re-search-forward
                "^[[:space:]]*✗[[:space:]]+\\(.+\\)$"
                nil t)
          (push (format "summary:%s" (string-trim (match-string 1))) failed))
        (goto-char (point-min))
        (while (re-search-forward
                "^ERROR:[[:space:]]+\\(.+\\)$"
                nil t)
          (push (format "error:%s" (string-trim (match-string 1))) failed))))
    (nreverse (cl-remove-duplicates failed :test #'string=))))

(defun gptel-auto-workflow--temporary-worktree-path (slug)
  "Return a temporary worktree path for SLUG under the workflow worktree base."
  (let* ((proj-root (gptel-auto-workflow--worktree-base-root))
         (worktree-base-dir (or gptel-auto-workflow-worktree-base
                                "var/tmp/experiments")))
    (expand-file-name (format "%s/%s-%d" worktree-base-dir slug (emacs-pid))
                      proj-root)))

(defun gptel-auto-workflow--with-temporary-worktree (slug ref fn)
  "Create a detached temporary worktree for REF, call FN with its path, then clean up."
  (let* ((proj-root (gptel-auto-workflow--default-dir))
         (default-directory proj-root)
         (worktree-dir (gptel-auto-workflow--temporary-worktree-path slug))
         (worktree-q (shell-quote-argument worktree-dir))
         (ref-q (shell-quote-argument ref)))
    (gptel-auto-workflow--with-error-handling
     (format "create %s worktree" slug)
     (lambda ()
       (when (or (file-exists-p worktree-dir)
                 (string-match-p (regexp-quote worktree-dir)
                                 (gptel-auto-workflow--git-cmd "git worktree list" 60)))
         (gptel-auto-workflow--cleanup-staging-submodule-worktrees worktree-dir)
         (ignore-errors
           (gptel-auto-workflow--git-cmd
            (format "git worktree remove --force %s" worktree-q)
            180))
         (ignore-errors (delete-directory worktree-dir t)))
       (make-directory (file-name-directory worktree-dir) t)
       (let ((add-result
              (gptel-auto-workflow--git-result
               (format "git worktree add --force --detach %s %s" worktree-q ref-q)
               180)))
         (unless (= 0 (cdr add-result))
           (error "git worktree add failed: %s" (car add-result))))
       (unwind-protect
           (funcall fn worktree-dir)
         (gptel-auto-workflow--cleanup-staging-submodule-worktrees worktree-dir)
         (ignore-errors
           (gptel-auto-workflow--git-cmd
            (format "git worktree remove --force %s" worktree-q)
            180))
         (when (file-exists-p worktree-dir)
           (ignore-errors (delete-directory worktree-dir t))))))))

(defun gptel-auto-workflow--main-baseline-test-results ()
  "Return plist describing verification failures for the current staging baseline ref."
  (let ((main-ref (gptel-auto-workflow--staging-main-ref)))
    (cond
     ((not main-ref)
      (list :error "Missing main ref for baseline comparison"))
     (t
      (or
       (gptel-auto-workflow--with-temporary-worktree
        "main-baseline"
        main-ref
        (lambda (worktree)
          (let* ((test-script (expand-file-name "scripts/run-tests.sh" worktree))
                 (verify-script (expand-file-name "scripts/verify-nucleus.sh" worktree))
                 (hydrate (gptel-auto-workflow--hydrate-staging-submodules worktree)))
            (cond
             ((/= 0 (cdr hydrate))
              (list :ref main-ref
                    :error (format "Failed to hydrate %s baseline: %s"
                                   main-ref
                                   (car hydrate))))
             ((not (file-exists-p test-script))
              (list :ref main-ref
                    :error (format "Missing test script in %s baseline worktree" main-ref)))
             (t
              (let* ((buffer (generate-new-buffer "*main-baseline-verify*"))
                     exit-code
                     verify-exit-code
                     output
                     failed-tests)
                 (unwind-protect
                     (let ((default-directory worktree))
                       (setq exit-code
                             (if (file-exists-p test-script)
                                 (call-process "bash" nil buffer nil test-script "unit")
                               0))
                       (setq verify-exit-code
                             (if (file-exists-p verify-script)
                                 (call-process "bash" nil buffer nil verify-script)
                               0))
                       (setq output (with-current-buffer buffer (buffer-string)))
                       (setq failed-tests (gptel-auto-workflow--extract-failed-tests output))
                       (cond
                        ((and (eq exit-code 0) (eq verify-exit-code 0))
                         (list :ref main-ref
                               :exit-code 0
                               :failed-tests nil
                               :output output))
                        (failed-tests
                         (list :ref main-ref
                               :exit-code (or (and (/= exit-code 0) exit-code)
                                              (and (/= verify-exit-code 0) verify-exit-code)
                                              1)
                               :failed-tests failed-tests
                               :output output))
                        (t
                         (list :ref main-ref
                               :exit-code (or (and (/= exit-code 0) exit-code)
                                              (and (/= verify-exit-code 0) verify-exit-code)
                                              1)
                               :error (format "Failed to parse %s baseline test failures"
                                              main-ref)
                               :output output))))
                   (when (buffer-live-p buffer)
                    (kill-buffer buffer)))))))))
       (list :ref main-ref
             :error (format "Failed to create %s baseline worktree" main-ref)))))))

(defun gptel-auto-workflow--staging-tests-match-main-baseline-p (staging-output)
  "Return (PASS-P . NOTE) comparing STAGING-OUTPUT verification failures against main baseline."
  (let ((staging-failures (gptel-auto-workflow--extract-failed-tests staging-output)))
    (cond
     ((null staging-failures)
      (cons t "Staging tests passed: no failures detected"))
     (t
       (let* ((baseline (gptel-auto-workflow--main-baseline-test-results))
              (baseline-error (plist-get baseline :error))
              (baseline-ref (or (plist-get baseline :ref) "main"))
              (baseline-failures (plist-get baseline :failed-tests))
             (new-failures (cl-set-difference staging-failures baseline-failures
                                              :test #'string=)))
        (cond
         (baseline-error
          (cons nil (format "Failed to determine %s baseline: %s"
                            baseline-ref baseline-error)))
         (new-failures
          (cons nil (format "New staging verification failures vs %s: %s"
                            baseline-ref
                            (mapconcat #'identity new-failures ", "))))
          (t
           (cons t (format "No new staging verification failures vs %s baseline%s"
                           baseline-ref
                           (if baseline-failures
                               (format " (%s)"
                                       (mapconcat #'identity baseline-failures ", "))
                             ""))))))))))

(defun gptel-auto-workflow--hydrate-staging-submodules (&optional worktree)
  "Materialize top-level submodules in WORKTREE from shared module repos.
This avoids broken linked-worktree submodule metadata under `.git/worktrees/.../modules'."
  (let* ((root (or worktree gptel-auto-workflow--staging-worktree-dir))
         (paths (gptel-auto-workflow--staging-submodule-paths root))
         (hydrated nil)
         failure)
    (if (not (and root (file-directory-p root)))
        (cons "Staging worktree not found" 1)
      (dolist (path paths nil)
        (unless failure
          (let* ((commit (gptel-auto-workflow--staging-submodule-gitlink-revision root path))
                 (shared-git-dir (gptel-auto-workflow--shared-submodule-git-dir path commit))
                 (target (expand-file-name path root))
                 add-result)
            (cond
             ((not commit)
              (setq failure (format "Missing gitlink revision for submodule %s" path)))
             ((not (file-directory-p shared-git-dir))
              (setq failure
                    (format "Missing shared submodule repo for %s: %s"
                            path shared-git-dir)))
             (t
              (gptel-auto-workflow--cleanup-staging-submodule-worktree root path)
              (make-directory (file-name-directory target) t)
              (setq add-result
                    (gptel-auto-workflow--git-result
                     (format "git --git-dir=%s worktree add --detach --force %s %s"
                             (shell-quote-argument shared-git-dir)
                             (shell-quote-argument target)
                             (shell-quote-argument commit))
                     180))
              (if (= 0 (cdr add-result))
                  (push (format "%s=%s" path (gptel-auto-workflow--truncate-hash commit))
                        hydrated)
                (setq failure
                      (format "Failed to hydrate %s: %s" path (car add-result)))))))))
      (if failure
          (cons failure 1)
        (cons (if hydrated
                  (format "Hydrated submodules: %s"
                          (mapconcat #'identity (nreverse hydrated) ", "))
                "")
              0)))))


(defun gptel-auto-workflow--review-changes (optimize-branch callback)
  "Review changes in OPTIMIZE-BRANCH before merging to staging.
Calls CALLBACK with (approved-p . review-output).
Reviewer checks for Blocker/Critical issues."
  (if (not gptel-auto-workflow-require-review)
      (funcall callback (cons t "Review disabled by config"))
    (let* ((proj-root (gptel-auto-workflow--project-root))
           (default-directory proj-root)
           (review-timeout (max my/gptel-agent-task-timeout
                                gptel-auto-workflow-review-time-budget))
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

REVIEW METHOD:
- If the diff introduces a call to an existing helper/function, inspect that helper's
  current definition before blocking on unknown behavior.
- Do not block solely because a referenced helper is outside the diff when you can
  verify it from the current file/repo.

OUTPUT: First line must be exactly 'APPROVED' or 'BLOCKED: [reason]'.
You may include structured markdown after that verdict line.

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
                    (approved (gptel-auto-workflow--review-approved-p response)))
               (message "[auto-workflow] Review %s: %s"
                        (if approved "PASSED" "BLOCKED")
                        (my/gptel--sanitize-for-logging response 100))
               (funcall callback (cons approved response))))
           review-timeout)
        (funcall callback (cons t "No reviewer agent available, auto-approving"))))))

(defun gptel-auto-workflow--review-approved-p (response)
  "Return non-nil when RESPONSE approves a staging review.

Accept explicit APPROVED/BLOCKED markers, blocker-free reviewer markdown,
and analysis-only reviewer summaries that cite current lines without
surfacing blocking markers or issue details."
  (when (stringp response)
    (let* ((normalized (replace-regexp-in-string "|" "\n" response))
         (case-fold-search t)
         (approved (string-match
                    (rx (or line-start "\n")
                        (* blank)
                        (? (+ "#") (* blank))
                        "APPROVED" word-end)
                    normalized))
         (blocked (string-match
                   (rx (or line-start "\n")
                       (* blank)
                       (? (+ "#") (* blank))
                       "BLOCKED" word-end)
                   normalized))
         (no-blockers (string-match-p
                       (rx (or line-start "\n")
                           (* blank)
                           (? (+ "#") (* blank))
                           "No blockers"
                           (* nonl))
                       normalized))
         (non-blocking-section (string-match-p
                                (rx (or line-start "\n")
                                    (* blank)
                                    (+ "#") (+ blank)
                                    (or "No Issue"
                                        "Praise"
                                        "Defensive Hardening"
                                        "Style-Only Suggestions")
                                    word-end)
                                normalized))
         (bug-section (string-match-p
                       (rx (or line-start "\n")
                           (* blank)
                           (+ "#") (+ blank)
                           "Proven Correctness Bugs"
                           word-end)
                       normalized))
         (analysis-summary (string-match-p
                            (rx (or "Based on my analysis"
                                    "Overall assessment"
                                    "After reviewing"
                                    "After examining"
                                    "I reviewed"
                                    "I examined"))
                            normalized))
         (analysis-line-reference (string-match-p
                                   (rx (or (seq ".el:" (+ digit))
                                           (seq "line " (+ digit))))
                                   normalized))
         (issue-label (string-match-p
                       (rx (or line-start "\n")
                           (* blank)
                           (? "-")
                           (* blank)
                           "Issue:"
                           (+ blank))
                       normalized))
         (action-items (string-match-p
                        (rx (or line-start "\n")
                            (* blank)
                            "- [ ]")
                        normalized))
         (unverified (string-match-p
                      (rx (or line-start "\n")
                          (* blank)
                          "UNVERIFIED")
                      normalized))
         (blocking-summary (string-match-p
                            (rx (or "introduces a correctness bug"
                                    "introduces a runtime error"
                                    "introduces a security"
                                    "can signal"
                                    "can crash"
                                    "can fail"
                                    "will signal"
                                    "will crash"
                                    "will fail"
                                    "logic failure"
                                    "state corruption"))
                            normalized)))
    (cond
     ((and blocked
           (or (not approved)
               (< blocked approved)))
      nil)
     (approved t)
     ((and (or no-blockers non-blocking-section)
           (not bug-section)
           (not issue-label)
           (not action-items)
           (not unverified))
      t)
     ((and analysis-summary
           analysis-line-reference
           (not bug-section)
           (not issue-label)
           (not action-items)
           (not unverified)
           (not blocking-summary))
      t)
     (t nil)))))

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

(defun gptel-auto-workflow--review-retryable-error-p (review-output)
  "Return non-nil when REVIEW-OUTPUT reflects a transient reviewer failure."
  (when (stringp review-output)
    (memq (car (gptel-auto-experiment--categorize-error review-output))
          '(:api-rate-limit :api-error :timeout))))

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
                  (success (not (string-match-p "^Error:" response)))
                  (git-success (when success
                                 (and (magit-git-success "add" "-A")
                                      (magit-git-success "commit" "-m" "fix: address review issues")))))
             (funcall callback (cons (and success git-success) response)))))
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
                       (success (not (string-match-p "^Error:" response)))
                       (git-success (when success
                                      (and (magit-git-success "add" "-A")
                                           (magit-git-success "commit" "-m" "fix: address review issues")))))
                   (funcall callback (cons (and success git-success) response))))))))
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
;;;###autoload

(defun gptel-auto-workflow--ensure-staging-branch-exists ()
  "Ensure the staging branch exists locally.
If it is missing locally, recover it from `origin/staging' or create it from
the preferred main ref. Remote pushes are deferred until verification passes."
  (let* ((proj-root (gptel-auto-workflow--project-root))
         (default-directory proj-root)
         (staging gptel-auto-workflow-staging-branch)
         (staging-q (shell-quote-argument staging))
         (remote-staging (format "refs/remotes/origin/%s" staging))
         (remote-staging-q (shell-quote-argument remote-staging))
         (remote-staging-refspec
          (format "+refs/heads/%s:refs/remotes/origin/%s" staging staging))
         (remote-staging-refspec-q (shell-quote-argument remote-staging-refspec)))
    (gptel-auto-workflow--with-error-handling
     "ensure staging branch exists"
     (lambda ()
        (let ((local-exists
               (= 0 (cdr (gptel-auto-workflow--git-result
                          (format "git rev-parse --verify %s" staging-q)
                          60)))))
          (cond
           (local-exists
            (message "[auto-workflow] %s branch exists locally" staging)
            t)
           ((= 0 (cdr (gptel-auto-workflow--git-result
                       (format "git ls-remote --exit-code --heads origin %s"
                               staging-q)
                       60)))
            (message "[auto-workflow] Creating local %s from origin/%s" staging staging)
            (and (= 0 (cdr (gptel-auto-workflow--git-result
                            (format "git fetch origin %s" remote-staging-refspec-q)
                            180)))
                 (= 0 (cdr (gptel-auto-workflow--git-result
                            (format "git branch %s %s" staging-q remote-staging-q)
                            180)))))
           (t
            (let ((main-ref (gptel-auto-workflow--staging-main-ref)))
              (if (not main-ref)
                  nil
                (message "[auto-workflow] Creating %s branch from %s" staging main-ref)
                (let ((create-result
                       (gptel-auto-workflow--git-result
                        (format "git branch %s %s"
                                staging-q
                                (shell-quote-argument main-ref))
                        180)))
                  (= 0 (cdr create-result))))))))))))

(defun gptel-auto-workflow--ensure-merge-source-ref (branch)
  "Return a mergeable ref for BRANCH, fetching it narrowly if needed.
Prefers the local branch when present so workflows keep working in repos that
do not fetch every remote head into `refs/remotes/origin/*'."
  (let* ((proj-root (gptel-auto-workflow--project-root))
         (default-directory proj-root)
         (branch-q (shell-quote-argument branch))
         (remote-ref (format "refs/remotes/origin/%s" branch))
         (remote-ref-q (shell-quote-argument remote-ref))
         (remote-refspec (format "+refs/heads/%s:%s" branch remote-ref))
         (remote-refspec-q (shell-quote-argument remote-refspec)))
    (cond
     ((= 0 (cdr (gptel-auto-workflow--git-result
                 (format "git rev-parse --verify %s" branch-q)
                 60)))
      branch)
     ((= 0 (cdr (gptel-auto-workflow--git-result
                 (format "git rev-parse --verify %s" remote-ref-q)
                 60)))
      remote-ref)
     ((and (= 0 (cdr (gptel-auto-workflow--git-result
                      (format "git ls-remote --exit-code --heads origin %s" branch-q)
                      60)))
           (= 0 (cdr (gptel-auto-workflow--git-result
                      (format "git fetch origin %s" remote-refspec-q)
                      180))))
      remote-ref)
     (t nil))))


;;;###autoload


(defun gptel-auto-workflow--prepare-staging-merge-base (reset-target)
  "Reset the staging worktree to RESET-TARGET.
Returns non-nil on success, nil on failure."
  (let* ((staging-q (shell-quote-argument gptel-auto-workflow-staging-branch))
         (reset-q (shell-quote-argument reset-target))
         (setup-results (list
                         (gptel-auto-workflow--git-result
                          (format "git checkout %s" staging-q)
                          60)
                         (gptel-auto-workflow--git-result
                          (format "git reset --hard %s" reset-q)
                          180)))
         (failed-setup (cl-find-if (lambda (item) (/= 0 (cdr item)))
                                   setup-results)))
    (if failed-setup
        (progn
          (message "[auto-workflow] Failed to prepare staging merge: %s"
                   (my/gptel--sanitize-for-logging (car failed-setup) 160))
          nil)
      t)))

(defun gptel-auto-workflow--empty-cherry-pick-state-p (&optional output allow-missing-head)
  "Return non-nil when the current worktree reflects an already-applied cherry-pick.
When ALLOW-MISSING-HEAD is non-nil, also treat a clean worktree plus localized
empty-pick OUTPUT as already applied even if `CHERRY_PICK_HEAD' is absent."
  (let ((cherry-pick-head
         (ignore-errors
           (gptel-auto-workflow--git-cmd
            "git rev-parse -q --verify CHERRY_PICK_HEAD 2>/dev/null"
            30)))
        (unmerged-files
         (or (ignore-errors
               (gptel-auto-workflow--git-cmd
                "git diff --name-only --diff-filter=U 2>/dev/null"
                30))
             ""))
        (worktree-status
         (or (ignore-errors
               (gptel-auto-workflow--git-cmd
               "git status --porcelain 2>/dev/null"
                30))
             "")))
    (and (or (gptel-auto-workflow--non-empty-string-p cherry-pick-head)
             (and allow-missing-head
                  (stringp output)
                  (string-match-p
                   "already applied\\|previous cherry-pick is now empty\\|The previous cherry-pick is now empty\\|nothing to commit\\|working tree clean\\|无文件要提交\\|工作区干净"
                   output)))
         (string-empty-p unmerged-files)
         (string-empty-p worktree-status))))

(defun gptel-auto-workflow--merge-to-staging (optimize-branch)
  "Merge OPTIMIZE-BRANCH to staging using cherry-pick.
Cherry-pick the tip commit of OPTIMIZE-BRANCH onto staging.
Returns t on success, nil on failure.
Uses the staging worktree instead of switching branches in the root repo."
  (let* ((staging gptel-auto-workflow-staging-branch)
         (optimize-ref (gptel-auto-workflow--ensure-merge-source-ref optimize-branch))
         (merge-message (format "Merge %s for verification" optimize-branch)))
    (message "[auto-workflow] Cherry-picking %s to %s" optimize-branch staging)
    (if (not (gptel-auto-workflow--ensure-staging-branch-exists))
        nil
      (if (not optimize-ref)
          (progn
            (message "[auto-workflow] Missing merge source branch: %s" optimize-branch)
            nil)
        (gptel-auto-workflow--with-staging-worktree
         (lambda ()
           (let* ((remote-staging (format "origin/%s" staging))
                  (reset-target (if (= 0 (cdr (gptel-auto-workflow--git-result
                                                (format "git rev-parse --verify %s"
                                                        (shell-quote-argument remote-staging))
                                                60)))
                                    remote-staging
                                  staging)))
             (if (not (gptel-auto-workflow--prepare-staging-merge-base reset-target))
                 nil
                (let* ((commit-hash (string-trim
                                     (car (gptel-auto-workflow--git-result
                                           (format "git rev-parse %s"
                                                   (shell-quote-argument optimize-ref))
                                           60))))
                      (cherry-result
                       (gptel-auto-workflow--git-result
                        (format "git cherry-pick --no-commit %s"
                                (shell-quote-argument commit-hash))
                        180))
                      (cherry-output (car cherry-result)))
                  (cond
                   ((eq 0 (cdr cherry-result))
                    (let ((commit-result
                           (gptel-auto-workflow--git-result
                            (format "git commit -m %s" (shell-quote-argument merge-message))
                            60)))
                      (cond
                       ((eq 0 (cdr commit-result))
                        t)
                       ((gptel-auto-workflow--empty-cherry-pick-state-p (car commit-result) t)
                        (ignore-errors (gptel-auto-workflow--git-cmd "git cherry-pick --skip" 60))
                        (message "[auto-workflow] Cherry-pick empty after apply (already in staging)")
                        t)
                       (t
                        (message "[auto-workflow] Commit failed after cherry-pick: %s"
                                 (my/gptel--sanitize-for-logging (car commit-result) 160))
                        nil))))
                   ((or (gptel-auto-workflow--empty-cherry-pick-state-p cherry-output t)
                        (string-match-p "already applied\\|previous cherry-pick is now empty\\|The previous cherry-pick is now empty"
                                        cherry-output))
                    (message "[auto-workflow] Cherry-pick empty (already in staging)")
                    (ignore-errors (gptel-auto-workflow--git-cmd "git cherry-pick --abort" 60))
                    t)
                  (t
                    (ignore-errors (gptel-auto-workflow--git-cmd "git cherry-pick --abort" 60))
                    (message "[auto-workflow] Cherry-pick failed, falling back to merge: %s"
                             (my/gptel--sanitize-for-logging cherry-output 160))
                    (if (not (gptel-auto-workflow--prepare-staging-merge-base reset-target))
                        nil
                      (let* ((merge-result
                              (gptel-auto-workflow--git-result
                               (format "git merge -X theirs %s --no-ff -m %s"
                                       (shell-quote-argument optimize-ref)
                                       (shell-quote-argument merge-message))
                               180))
                             (merge-output (car merge-result)))
                        (cond
                         ((eq 0 (cdr merge-result)) t)
                         ((string-match-p "Already up[ -]to[- ]date" merge-output) t)
                         (t
                          (ignore-errors (gptel-auto-workflow--git-cmd "git merge --abort" 60))
                          (ignore-errors (gptel-auto-workflow--git-cmd "git cherry-pick --abort" 60))
                          (gptel-auto-workflow--prepare-staging-merge-base reset-target)
                          (message "[auto-workflow] Merge also failed: %s"
                                   (my/gptel--sanitize-for-logging merge-output 160))
                          nil)))))))))))))))



(defun gptel-auto-workflow--check-el-syntax (directory output-buffer)
  "Check syntax of all .el files in DIRECTORY.
Writes errors to OUTPUT-BUFFER.
Returns t if all files pass syntax check, nil otherwise."
  (let ((errors nil)
        (files (directory-files-recursively directory "\\.el\\'")))
    (dolist (file files)
      (when (file-readable-p file)
        (with-temp-buffer
          (insert-file-contents file)
          (emacs-lisp-mode)  ; Enable proper syntax parsing for comments
          (goto-char (point-min))
          (condition-case err
              (progn
                (while (not (eobp)) (forward-sexp)))
            (error
             (let ((msg (format "SYNTAX ERROR: %s: %s"
                                (file-relative-name file directory)
                                (error-message-string err))))
               (push msg errors)
               (with-current-buffer output-buffer
                 (insert msg "\n"))))))))
    (null errors)))

(defun gptel-auto-workflow--verify-staging ()
  "Run verification in the staging worktree.
Returns (success-p . output)."
  (let* ((worktree gptel-auto-workflow--staging-worktree-dir)
         (test-script (and worktree (expand-file-name "scripts/run-tests.sh" worktree)))
         (verify-script (and worktree (expand-file-name "scripts/verify-nucleus.sh" worktree)))
         (output-buffer (generate-new-buffer "*staging-verify*"))
         result)
    (if (not (and worktree (file-exists-p worktree)))
        (progn
          (message "[auto-workflow] Staging worktree not found")
          (cons nil "Staging worktree not found"))
      (message "[auto-workflow] Verifying staging...")
      (let* ((default-directory worktree)
             (syntax-pass (gptel-auto-workflow--check-el-syntax worktree output-buffer))
             (submodules (when syntax-pass (gptel-auto-workflow--hydrate-staging-submodules worktree)))
             (submodule-pass (and syntax-pass (= 0 (cdr submodules))))
              (_ (unless submodule-pass
                    (with-current-buffer output-buffer
                      (insert (car submodules) "\n"))))
              (test-result (when (and submodule-pass test-script (file-exists-p test-script))
                             (call-process "bash" nil output-buffer nil test-script "unit")))
              (verify-result (when (and submodule-pass verify-script (file-exists-p verify-script))
                               (call-process "bash" nil output-buffer nil verify-script)))
              (test-pass (and submodule-pass
                              (or (not (and test-script (file-exists-p test-script)))
                                  (eq test-result 0))))
              (verify-pass (and submodule-pass
                                (or (not (and verify-script (file-exists-p verify-script)))
                                    (eq verify-result 0))))
              (checks-pass (and test-pass verify-pass))
              (output (with-current-buffer output-buffer (buffer-string))))
        (when (and submodule-pass
                   (not checks-pass))
          (let ((baseline-check
                 (gptel-auto-workflow--staging-tests-match-main-baseline-p output)))
            (setq checks-pass (car baseline-check))
            (with-current-buffer output-buffer
              (goto-char (point-max))
              (unless (bolp)
                (insert "\n"))
              (insert "\n" (cdr baseline-check) "\n"))
            (setq output (with-current-buffer output-buffer (buffer-string)))))
        (kill-buffer output-buffer)
        (setq result (and syntax-pass submodule-pass checks-pass))
        (message "[auto-workflow] Staging verification: %s" (if result "PASS" "FAIL"))
        (cons result output)))))



(defun gptel-auto-workflow--push-staging ()
  "Push staging branch to origin after successful verification.
Uses `--force-with-lease' when remote staging already exists because the local
staging branch is regenerated from `main' at the start of each workflow run."
  (let ((staging gptel-auto-workflow-staging-branch))
    (message "[auto-workflow] Pushing staging to origin")
    (gptel-auto-workflow--with-staging-worktree
     (lambda ()
        (cl-labels
            ((parse-remote-head (output)
               (let ((pattern (format "^\\([0-9a-f]\\{40\\}\\)\trefs/heads/%s$"
                                      (regexp-quote staging)))
                     head)
                 (dolist (line (split-string (or output "") "\n" t) head)
                   (when (and (null head)
                              (string-match pattern line))
                     (setq head (match-string 1 line)))))))
          (let* ((staging-q (shell-quote-argument staging))
               (remote-result
                (gptel-auto-workflow--git-result
                 (format "git ls-remote --exit-code --heads origin %s" staging-q)
                 60))
               (remote-head
                (and (= 0 (cdr remote-result))
                     (parse-remote-head (car remote-result))))
               (push-command
                (if remote-head
                    (format "git push %s origin %s"
                            (shell-quote-argument
                            (format "--force-with-lease=%s:%s"
                                    staging
                                    remote-head))
                           staging-q)
                 (format "git push origin %s" staging-q)))
              (push-result
               (gptel-auto-workflow--git-result
                push-command
                180)))
           (if (= 0 (cdr push-result))
               t
             (message "[auto-workflow] Failed to push staging: %s"
                      (my/gptel--sanitize-for-logging (car push-result) 160))
             nil)))))))


(defun gptel-auto-workflow--current-staging-head ()
  "Return the current commit at the staging branch head, or nil if unavailable."
  (let* ((proj-root (gptel-auto-workflow--project-root))
         (default-directory proj-root)
         (staging-q (shell-quote-argument gptel-auto-workflow-staging-branch)))
    (when (gptel-auto-workflow--ensure-staging-branch-exists)
      (let ((head-result
             (gptel-auto-workflow--git-result
              (format "git rev-parse --verify %s" staging-q)
              60)))
        (when (= 0 (cdr head-result))
          (string-trim (car head-result)))))))

(defun gptel-auto-workflow--restore-staging-ref (base-ref)
  "Restore the staging branch and worktree to BASE-REF.
Returns non-nil on success."
  (let* ((proj-root (gptel-auto-workflow--project-root))
         (default-directory proj-root)
         (staging gptel-auto-workflow-staging-branch)
         (staging-q (shell-quote-argument staging))
         (base-q (shell-quote-argument base-ref)))
    (when (and base-ref (gptel-auto-workflow--ensure-staging-branch-exists))
      (gptel-auto-workflow--delete-staging-worktree)
      (let ((worktree (gptel-auto-workflow--create-staging-worktree)))
        (when worktree
          (let ((default-directory worktree))
            (let* ((results (list
                             (gptel-auto-workflow--git-result
                              (format "git checkout %s" staging-q)
                              60)
                             (gptel-auto-workflow--git-result
                              (format "git reset --hard %s" base-q)
                              180)))
                   (failed (cl-find-if (lambda (item) (/= 0 (cdr item))) results)))
              (if failed
                  (progn
                    (message "[auto-workflow] Failed to restore staging baseline: %s"
                             (my/gptel--sanitize-for-logging (car failed) 160))
                    nil)
                t))))))))

(defun gptel-auto-workflow--reset-staging-after-failure (&optional base-ref)
  "Restore staging after a failed staging step.
When BASE-REF is non-nil, prefer restoring the last known-good staging state.
Falls back to rebuilding staging from the workflow base if BASE-REF cannot be
restored."
  (cond
   ((and base-ref
         (gptel-auto-workflow--restore-staging-ref base-ref))
    (message "[auto-workflow] Restored staging to last good baseline after failure")
    t)
   ((gptel-auto-workflow--sync-staging-from-main)
    (if base-ref
        (message "[auto-workflow] Fell back to workflow base after staging restore failure")
      (message "[auto-workflow] Reset staging to workflow base after failure"))
    t)
   (t
    (message "[auto-workflow] Failed to reset staging after failure")
    nil)))

(defun gptel-auto-workflow--staging-flow (optimize-branch &optional completion-callback)
  "Run staging verification flow for OPTIMIZE-BRANCH.

Flow:
1. Review changes (if gptel-auto-workflow-require-review)
2. If review blocked: try to fix (up to N retries)
3. Merge OPTIMIZE-BRANCH to staging
4. Create staging worktree (never touches project root)
5. Run tests on staging
6. If pass: push staging to origin (human reviews later)
7. If fail: log failure to TSV, then restore staging to the last good baseline

ASSUMPTION: OPTIMIZE-BRANCH has been pushed to origin.
BEHAVIOR: Never modifies project root - all verification in worktree.
EDGE CASE: Handles merge conflicts with auto-resolution (theirs).
TEST: Verify main is never touched by auto-workflow.
SAFETY: Asserts main branch is not current before any operation.

NOTE: Human must manually merge staging to main after review."
  (let ((completion-callback
         (when completion-callback
           (gptel-auto-workflow--make-idempotent-callback completion-callback))))
    (gptel-auto-workflow--assert-main-untouched)
    (setq gptel-auto-workflow--review-retry-count 0)
    (setq gptel-auto-workflow--review-error-retry-count 0)
    (message "[auto-workflow] Starting staging flow for %s" optimize-branch)
    (gptel-auto-workflow--review-changes
     optimize-branch
     (lambda (review-result)
       (gptel-auto-workflow--staging-flow-after-review
        optimize-branch
        review-result
        completion-callback)))))


(defun gptel-auto-workflow--staging-flow-after-review (optimize-branch review-result &optional completion-callback)
  "Continue staging flow after review for OPTIMIZE-BRANCH.
REVIEW-RESULT is (approved-p . review-output).
When COMPLETION-CALLBACK is non-nil, call it with non-nil on success."
  (let* ((approved (car review-result))
         (review-output (cdr review-result))
         (review-error (and (not approved)
                            (gptel-auto-workflow--review-retryable-error-p review-output)))
         (run-id (gptel-auto-workflow--current-run-id))
         (finish (gptel-auto-workflow--make-idempotent-callback
                  (lambda (success)
                    (when completion-callback
                      (funcall completion-callback success))))))
    (cond
     (review-error
      (if (< gptel-auto-workflow--review-error-retry-count
             gptel-auto-workflow--review-max-retries)
          (progn
            (cl-incf gptel-auto-workflow--review-error-retry-count)
            (message "[auto-workflow] Review failed transiently, retrying review (%d/%d)..."
                     gptel-auto-workflow--review-error-retry-count
                     gptel-auto-workflow--review-max-retries)
            (run-with-timer
             gptel-auto-experiment-retry-delay nil
             (lambda ()
               (if (gptel-auto-workflow--run-callback-live-p run-id)
                   (gptel-auto-workflow--review-changes
                    optimize-branch
                    (lambda (retry-review-result)
                      (gptel-auto-workflow--staging-flow-after-review
                       optimize-branch
                       retry-review-result
                       completion-callback)))
                 (message "[auto-workflow] Skipping stale review retry for %s; run %s is no longer active"
                          optimize-branch run-id)))))
        (message "[auto-workflow] ✗ Review failed (max retries): %s"
                 (my/gptel--sanitize-for-logging review-output 200))
        (gptel-auto-experiment-log-tsv
         (gptel-auto-workflow--current-run-id)
         (list :target "staging-review"
               :id 0
               :hypothesis "Staging review"
               :score-before 0
               :score-after 0
               :kept nil
               :duration 0
               :grader-quality 0
               :grader-reason "review-failed-max-retries"
               :comparator-reason (truncate-string-to-width review-output 200)
               :analyzer-patterns ""
               :agent-output review-output))
        (funcall finish nil)))
     ((not approved)
      (if (< gptel-auto-workflow--review-retry-count
             gptel-auto-workflow--review-max-retries)
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
                          (gptel-auto-workflow--staging-flow-after-review
                           optimize-branch
                           re-review-result
                           completion-callback))))
                   (message "[auto-workflow] Fix failed: %s"
                            (my/gptel--sanitize-for-logging fix-output 200))
                   (gptel-auto-experiment-log-tsv
                    (gptel-auto-workflow--current-run-id)
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
                          :agent-output review-output))
                   (funcall finish nil))))))
        (message "[auto-workflow] ✗ Review BLOCKED (max retries): %s"
                 (my/gptel--sanitize-for-logging review-output 200))
        (gptel-auto-experiment-log-tsv
         (gptel-auto-workflow--current-run-id)
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
               :agent-output review-output))
        (funcall finish nil)))
     (t
      (let* ((scope-check (gptel-auto-experiment--check-scope))
             (scope-ok (car scope-check))
             (changed-files (cdr scope-check)))
        (if (not scope-ok)
            (progn
              (message "[auto-workflow] ✗ Scope creep BLOCKED merge: %d files (max: %d)"
                       (length changed-files) gptel-auto-experiment-max-changed-files)
              (gptel-auto-experiment-log-tsv
               (gptel-auto-workflow--current-run-id)
               (list :target "staging-scope"
                     :id 0
                     :hypothesis "Staging scope check"
                     :score-before 0
                     :score-after 0
                     :kept nil
                     :duration 0
                     :grader-quality 0
                     :grader-reason "scope-creep-blocked"
                     :comparator-reason
                     (format "Too many files: %s" (mapconcat #'identity changed-files ", "))
                     :analyzer-patterns ""
                     :agent-output ""))
              (funcall finish nil))
          (let* ((staging-base (gptel-auto-workflow--current-staging-head))
                 (merge-success
                  (gptel-auto-workflow--merge-to-staging optimize-branch)))
            (if (not merge-success)
                (progn
                  (message "[auto-workflow] ✗ Merge to staging failed, aborting")
                  (gptel-auto-experiment-log-tsv
                   (gptel-auto-workflow--current-run-id)
                   (list :target "staging-merge"
                         :id 0
                         :hypothesis "Staging merge"
                         :score-before 0
                         :score-after 0
                         :kept nil
                         :duration 0
                         :grader-quality 0
                         :grader-reason "staging-merge-failed"
                         :comparator-reason
                         (format "Failed to merge %s to staging" optimize-branch)
                         :analyzer-patterns ""
                         :agent-output ""))
                  (funcall finish nil))
              (let ((worktree (or gptel-auto-workflow--staging-worktree-dir
                                  (gptel-auto-workflow--create-staging-worktree))))
                (if (not worktree)
                    (progn
                      (message "[auto-workflow] ✗ Failed to create staging worktree")
                      (gptel-auto-experiment-log-tsv
                       (gptel-auto-workflow--current-run-id)
                       (list :target "staging-worktree"
                             :id 0
                             :hypothesis "Staging worktree"
                             :score-before 0
                             :score-after 0
                             :kept nil
                             :duration 0
                             :grader-quality 0
                             :grader-reason "staging-worktree-failed"
                             :comparator-reason "Failed to create staging worktree"
                             :analyzer-patterns ""
                             :agent-output ""))
                      (gptel-auto-workflow--reset-staging-after-failure staging-base)
                      (funcall finish nil))
                  (let* ((verification (gptel-auto-workflow--verify-staging))
                         (tests-passed (car verification))
                         (output (or (cdr verification) "")))
                    (if (not tests-passed)
                        (progn
                          (message "[auto-workflow] ✗ Staging verification FAILED")
                          (gptel-auto-experiment-log-tsv
                           (gptel-auto-workflow--current-run-id)
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
                                 :agent-output output))
                          (gptel-auto-workflow--reset-staging-after-failure staging-base)
                          (funcall finish nil))
                      (message "[auto-workflow] ✓ Staging verification PASSED")
                      (if (gptel-auto-workflow--push-staging)
                          (progn
                            (gptel-auto-workflow--delete-staging-worktree)
                            (message "[auto-workflow] ✓ Staging pushed. Human must merge to main.")
                            (funcall finish t))
                        (message "[auto-workflow] ✗ Staging push FAILED")
                        (gptel-auto-experiment-log-tsv
                         (gptel-auto-workflow--current-run-id)
                         (list :target "staging-push"
                               :id 0
                               :hypothesis "Staging push"
                               :score-before 0
                               :score-after 0
                               :kept nil
                               :duration 0
                               :grader-quality 0
                               :grader-reason "staging-push-failed"
                               :comparator-reason "Failed to push staging"
                               :analyzer-patterns ""
                               :agent-output output))
                        (gptel-auto-workflow--reset-staging-after-failure staging-base)
                        (funcall finish nil))))))))))))))


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

   ;; 2. Stable workflow run root (captured before entering worktrees)
   ((and (boundp 'gptel-auto-workflow--run-project-root)
         gptel-auto-workflow--run-project-root)
    (expand-file-name gptel-auto-workflow--run-project-root))
    
    ;; 3. Git common dir - returns main repo even from worktrees
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
    
    ;; 4. project.el detection (preferred method)
    ((let ((proj (and (fboundp 'project-current)
                      (fboundp 'project-root)
                      (project-current nil))))
       (when proj
         (expand-file-name (project-root proj)))))
    
    ;; 5. Git toplevel (fallback)
    ((let ((git-root (string-trim
                      (shell-command-to-string
                       "git rev-parse --show-toplevel 2>/dev/null || echo ''"))))
       (and (not (string-empty-p git-root))
            (file-directory-p git-root)
            git-root)))
    
    ;; 6. Fallback
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
         (worktree (or (gptel-auto-workflow--get-worktree-dir gptel-auto-workflow--current-target)
                       proj-root))
         (hydrate-submodules-p (and proj-root worktree
                                    (not (file-equal-p proj-root worktree))))
         (default-directory worktree)
         (isolated-status-file (let ((path (make-temp-file "auto-workflow-status-" nil ".sexp")))
                                 (delete-file path)
                                 path))
         (process-environment
          (cons (format "AUTO_WORKFLOW_STATUS_FILE=%s" isolated-status-file)
                process-environment))
         (test-script (expand-file-name "scripts/run-tests.sh" worktree))
         (output-buffer (generate-new-buffer "*test-output*"))
         result)
     (unwind-protect
         (if (not (file-executable-p test-script))
             (progn
               (message "[auto-experiment] Test script not found or not executable: %s" test-script)
               (cons t "No test script - skipping"))
           (let* (;; Linked worktrees need the same shared-repo hydration that
                  ;; staging uses; otherwise package submodules stay empty and
                  ;; `require' fails before any ERT cases even run.
                  (hydrate-result (when hydrate-submodules-p
                                    (gptel-auto-workflow--hydrate-staging-submodules worktree)))
                  (hydrate-pass (or (not hydrate-submodules-p)
                                    (= 0 (cdr hydrate-result)))))
             (if (not hydrate-pass)
                 (progn
                   (with-current-buffer output-buffer
                     (insert (car hydrate-result) "\n"))
                   (message "[auto-experiment] ✗ Submodule hydration failed: %s"
                            (my/gptel--sanitize-for-logging (car hydrate-result) 200))
                   (cons nil (with-current-buffer output-buffer (buffer-string))))
               (message "[auto-experiment] Running tests...")
               (let ((exit-code (call-process test-script nil output-buffer nil "unit")))
                 (with-current-buffer output-buffer
                   (setq result (cons (zerop exit-code) (buffer-string))))
                 (when (car result)
                   (message "[auto-experiment] ✓ Tests passed"))
                 result))))
       (when (buffer-live-p output-buffer)
         (kill-buffer output-buffer))
       (when (file-exists-p isolated-status-file)
         (delete-file isolated-status-file)))))

(defcustom gptel-auto-experiment-require-tests t
  "When non-nil, require tests to pass before merging experiment to staging.
This catches bugs that the grader might miss (e.g., CL idioms that don't work in ELisp).
Set to nil to disable (only for emergency situations)."
  :type 'boolean
  :group 'gptel-auto-workflow)

(defcustom gptel-auto-experiment-max-changed-files 3
  "Maximum number of files an experiment can change.
Prevents scope creep where executor touches many unrelated files.
Set to 0 to disable the check."
  :type 'integer
  :group 'gptel-auto-workflow)

(defun gptel-auto-experiment--check-scope ()
  "Return (ok-p . changed-files) for current experiment.
Checks that the number of changed files is within limits."
  (let* ((worktree (gptel-auto-workflow--worktree-or-project-dir))
         (changed-files (shell-command-to-string
                         (format "cd %s && git diff --name-only HEAD~1 2>/dev/null"
                                 (shell-quote-argument worktree))))
         (files (split-string changed-files "\n" t))
         (count (length files)))
    (if (and (> gptel-auto-experiment-max-changed-files 0)
             (> count gptel-auto-experiment-max-changed-files))
        (progn
          (message "[auto-exp] ⚠ Scope creep detected: %d files changed (max: %d)"
                   count gptel-auto-experiment-max-changed-files)
          (cons nil files))
      (cons t files))))

(defun gptel-auto-experiment-benchmark (&optional skip-tests)
  "Run syntax validation + Eight Keys scoring.
If SKIP-TESTS is non-nil, skip test execution (tests run in staging flow).
Returns plist with :passed, :tests-passed, :eight-keys, etc.

NOTE: Nucleus script validation is skipped for experiments because:
1. verify-nucleus.sh uses script location ($DIR), not worktree context
2. Executor already runs verification in worktree context
3. Full validation happens in staging flow

IMPORTANT: When `gptel-auto-experiment-require-tests' is non-nil (default),
tests are run BEFORE the experiment is considered passed, even if skip-tests
is t. This catches bugs like using CL idioms (multiple-value-bind) that don't
work correctly in Emacs Lisp."
(let* ((start (float-time))
          (default-directory (gptel-auto-workflow--worktree-or-project-dir))
          (target-file (when gptel-auto-workflow--current-target
                         (expand-file-name gptel-auto-workflow--current-target default-directory)))
          (validation-error (when target-file
                              (gptel-auto-experiment--validate-code target-file))))
    (if validation-error
        (progn
          (message "[auto-exp] ✗ Validation failed: %s"
                   (my/gptel--sanitize-for-logging validation-error 200))
          (list :passed nil
                :validation-error validation-error
                :time (- (float-time) start)))
      (let* ((should-run-tests (or (not skip-tests)
                                    gptel-auto-experiment-require-tests))
             (tests-result (when should-run-tests
                             (gptel-auto-experiment-run-tests)))
             (raw-tests-passed (and tests-result (car tests-result)))
             (tests-output (when tests-result (cdr tests-result)))
             ;; Allow test failures that match main baseline
             (baseline-check (when (and should-run-tests (not raw-tests-passed))
                               (gptel-auto-workflow--staging-tests-match-main-baseline-p tests-output)))
             (tests-passed (or (and skip-tests (not gptel-auto-experiment-require-tests))
                               raw-tests-passed
                               (and baseline-check (car baseline-check))))
             (final-tests-output (or (and baseline-check (cdr baseline-check))
                                     tests-output))
             (scores (gptel-auto-experiment--eight-keys-scores)))
        (when (and skip-tests gptel-auto-experiment-require-tests)
          (message "[auto-exp] Tests required before staging merge: %s"
                   (if tests-passed "PASS" "FAIL")))
        (list :passed tests-passed
              :nucleus-passed t
              :nucleus-skipped t
              :tests-passed tests-passed
              :tests-output final-tests-output
              :tests-skipped (and skip-tests (not gptel-auto-experiment-require-tests))
              :time (- (float-time) start)
              :eight-keys (when scores (alist-get 'overall scores))
              :eight-keys-scores scores)))))

(defun gptel-auto-experiment--eight-keys-scores ()
  "Get full Eight Keys scores alist from current codebase.
Scores based on commit message + code diff (not just stat)."
  (when (fboundp 'gptel-benchmark-eight-keys-score)
    (let* ((worktree (gptel-auto-workflow--worktree-or-project-dir))
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
    (let* ((worktree (gptel-auto-workflow--worktree-or-project-dir))
           ;; SECURITY: Use shell-quote-argument to prevent shell injection
           (worktree-quoted (shell-quote-argument worktree))
           (changed-files (shell-command-to-string
                           (format "cd %s && git diff --name-only HEAD~1 2>/dev/null | grep '\\.el$'"
                                   worktree-quoted))))
      (when (string-match-p "\\.el$" (string-trim-right changed-files))
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

(defun gptel-auto-experiment--call-in-context (buffer directory fn)
  "Call FN in BUFFER with DIRECTORY bound as `default-directory'."
  (gptel-auto-workflow--call-in-run-context
   nil fn buffer directory))

(defmacro gptel-auto-experiment--with-context (buffer directory &rest body)
  "Run BODY in BUFFER with DIRECTORY bound as `default-directory'."
  (declare (indent 2) (debug t))
  `(gptel-auto-experiment--call-in-context
    ,buffer ,directory
    (lambda ()
      ,@body)))

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

(defvar gptel-auto-experiment--grading-target nil
  "Dynamically bound target file for the current grade request.")

(defvar gptel-auto-experiment--grading-worktree nil
  "Dynamically bound experiment worktree for the current grade request.")

(defvar gptel-auto-experiment-grade-timeout 120
  "Timeout in seconds for grading subagent.
Default 120s (2 min) allows grader to process complex outputs.")

(defun gptel-auto-experiment--reset-grade-state ()
  "Cancel and clear all pending grade callbacks."
  (maphash
   (lambda (_grade-id state)
     (when (timerp (plist-get state :timer))
       (cancel-timer (plist-get state :timer))))
   gptel-auto-experiment--grade-state)
  (clrhash gptel-auto-experiment--grade-state))

(defun gptel-auto-experiment--invalid-cl-return-target-in-forms (forms &optional blocks)
  "Return the first invalid `cl-return-from' target in FORMS.
BLOCKS is the list of block names currently in scope."
  (cond
   ((null forms) nil)
   ((listp forms)
    (cl-some (lambda (form)
               (gptel-auto-experiment--invalid-cl-return-target form blocks))
             forms))
   (t
    (gptel-auto-experiment--invalid-cl-return-target forms blocks))))

(defun gptel-auto-experiment--invalid-cl-return-target (form &optional blocks)
  "Return the first invalid `cl-return-from' target in FORM.
BLOCKS is the list of block names currently in scope."
  (cond
   ((atom form) nil)
   ((not (listp form)) nil)
   (t
    (pcase (car form)
      ((or 'quote 'quasiquote 'backquote) nil)
      ('cl-return-from
       (let ((target (nth 1 form)))
         (or (and (symbolp target)
                  (not (memq target blocks))
                  target)
             (gptel-auto-experiment--invalid-cl-return-target-in-forms
              (nthcdr 2 form) blocks))))
      ('cl-block
       (let ((name (nth 1 form)))
         (gptel-auto-experiment--invalid-cl-return-target-in-forms
          (nthcdr 2 form)
          (if (symbolp name) (cons name blocks) blocks))))
      ((or 'cl-defun 'cl-defmacro 'cl-defsubst)
       (let ((name (nth 1 form))
             (body (nthcdr 3 form)))
         (gptel-auto-experiment--invalid-cl-return-target-in-forms
          body
          (if (symbolp name) (cons name blocks) blocks))))
      ((or 'cl-labels 'cl-flet)
       (let ((bindings (nth 1 form))
             (body (nthcdr 2 form)))
         (or (cl-some
              (lambda (binding)
                (when (and (consp binding) (symbolp (car binding)))
                  (let ((name (car binding))
                        (fbody (cddr binding)))
                    (gptel-auto-experiment--invalid-cl-return-target-in-forms
                     fbody
                     (cons name blocks)))))
              bindings)
             (gptel-auto-experiment--invalid-cl-return-target-in-forms
              body blocks))))
      (_
       (or (gptel-auto-experiment--invalid-cl-return-target (car form) blocks)
           (gptel-auto-experiment--invalid-cl-return-target-in-forms
            (cdr form) blocks)))))))

(defun gptel-auto-experiment--validate-code (file)
  "Validate code in FILE for syntax and dangerous patterns.
Returns nil if valid, or error message string if invalid."
  (when (and (stringp file) (string-suffix-p ".el" file))
    (if (not (file-exists-p file))
        (format "Missing target file: %s" file)
      (let ((content (gptel-auto-workflow--read-file-contents file))
            forms)
        (or (condition-case err
                (with-temp-buffer
                  (insert content)
                  (set-syntax-table emacs-lisp-mode-syntax-table)
                  (goto-char (point-min))
                  (while (progn
                           (forward-comment (point-max))
                           (< (point) (point-max)))
                    (push (read (current-buffer)) forms))
                  nil)
              (error (format "Syntax error in %s: %s" file err)))
            (when (gptel-auto-experiment--invalid-cl-return-target-in-forms
                   (nreverse forms))
              (format "Dangerous pattern in %s: cl-return-from without cl-block" file)))))))

(defun gptel-auto-experiment--finish-grade (grade-id callback result
                                                     &optional cancel-timer)
  "Finalize GRADE-ID with RESULT, always cleaning grade state.
CALLBACK receives RESULT.  When CANCEL-TIMER is non-nil, cancel the
stored timeout timer before invoking CALLBACK."
  (let ((state (gethash grade-id gptel-auto-experiment--grade-state)))
    (when (gptel-auto-workflow--state-active-p state)
      (puthash grade-id (plist-put state :done t)
               gptel-auto-experiment--grade-state)
      (when (and cancel-timer
                 (timerp (plist-get state :timer)))
        (cancel-timer (plist-get state :timer)))
      (unwind-protect
          (funcall callback result)
        (remhash grade-id gptel-auto-experiment--grade-state))
      t)))

(defun gptel-auto-experiment--build-grading-output (output &optional target worktree)
  "Augment OUTPUT with concrete worktree evidence for grading.
When TARGET and WORKTREE are available, include git status and a diff excerpt
so the grader can inspect the actual edit instead of relying only on the
executor's prose summary."
  (let* ((base-output (if (stringp output) output (format "%s" output)))
         (resolved-target (or target gptel-auto-experiment--grading-target))
         (resolved-worktree (or worktree gptel-auto-experiment--grading-worktree)))
    (if (or (not (gptel-auto-workflow--non-empty-string-p resolved-target))
            (not (gptel-auto-workflow--non-empty-string-p resolved-worktree))
            (not (file-directory-p resolved-worktree)))
        base-output
      (let* ((default-directory resolved-worktree)
             (target-q (shell-quote-argument resolved-target))
             (status-result
              (gptel-auto-workflow--git-result
               (format "git status --short -- %s" target-q) 30))
             (diff-result
              (gptel-auto-workflow--git-result
               (format "git diff --unified=2 -- %s" target-q) 30))
             (status-output (string-trim (car status-result)))
             (diff-output (string-trim (car diff-result)))
             (status-text
              (if (and (= (cdr status-result) 0)
                       (not (string-empty-p status-output)))
                  status-output
                "No pending git status for target"))
             (diff-text
              (cond
               ((/= (cdr diff-result) 0)
                (format "git diff failed: %s"
                        (my/gptel--sanitize-for-logging (car diff-result) 200)))
               ((string-empty-p diff-output)
                "No diff captured for target")
               ((> (length diff-output) 3000)
                (concat (substring diff-output 0 3000) "\n...[truncated]"))
               (t diff-output))))
        (format "%s\n\nWORKTREE EVIDENCE:\n- Target: %s\n- Git status:\n%s\n- Diff excerpt:\n%s"
                base-output
                resolved-target
                status-text
                diff-text)))))

(defun gptel-auto-experiment-grade (output callback &optional target worktree)
  "Grade experiment OUTPUT. LLM decides quality threshold.
Timeout fails the grade (conservative).
If OUTPUT is an error message, fails immediately with error details.
Uses hash table keyed by grade-id to support parallel execution.
The grader subagent overlay will appear in the current buffer at time of call.
TARGET and WORKTREE let the grader inspect concrete git evidence."
  (let ((grade-id (cl-incf gptel-auto-experiment--grade-counter))
        (grade-buffer (current-buffer)))
    (cl-block gptel-auto-experiment-grade
      (when (gptel-auto-experiment--agent-error-p output)
        (let* ((error-snippet (if (stringp output)
                                  (my/gptel--sanitize-for-logging output 200)
                                "Unknown error"))
               (error-category (car (gptel-auto-experiment--categorize-error output))))
          (message "[auto-exp] Executor error detected: %s" error-snippet)
          (funcall callback (list :score 0 :passed nil
                                  :details (format "Agent error: %s" error-snippet)
                                  :error-category error-category))
          (cl-return-from gptel-auto-experiment-grade)))
      (puthash grade-id (list :done nil :timer nil)
               gptel-auto-experiment--grade-state)
      (let ((timeout-timer
             (run-with-timer
              gptel-auto-experiment-grade-timeout nil
              (lambda ()
                (let ((state (gethash grade-id
                                      gptel-auto-experiment--grade-state)))
                  (when (gptel-auto-workflow--state-active-p state)
                    (message "[auto-exp] Grading timeout after %ds, failing"
                             gptel-auto-experiment-grade-timeout)
                    (gptel-auto-experiment--finish-grade
                     grade-id callback
                     (list :score 0 :passed nil :details "timeout"))))))))
        (puthash grade-id (list :done nil :timer timeout-timer)
                 gptel-auto-experiment--grade-state))
      (if (and gptel-auto-experiment-use-subagents
               (fboundp 'gptel-benchmark-grade))
          ;; Ensure grader runs in the captured buffer context so overlay appears in right place
          (with-current-buffer grade-buffer
            (gptel-benchmark-grade
             (gptel-auto-experiment--build-grading-output output target worktree)
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
                (gptel-auto-experiment--finish-grade
                 grade-id callback result t))
              gptel-auto-experiment-grade-timeout))
         (gptel-auto-experiment--finish-grade
          grade-id callback (list :score 100 :passed t) t)))))

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
2. Use Code_Map or Grep to find the relevant function/section in the target file first
3. Read only focused line ranges from the target file using its full path; avoid reading the entire file unless absolutely necessary
4. IDENTIFY a real code issue (bug, performance, duplication, missing validation)
5. Implement the CODE change minimally using Edit tool
6. Run tests to verify: ./scripts/verify-nucleus.sh && ./scripts/run-tests.sh
7. DO NOT run git add, git commit, git push, or stage changes yourself.
   Leave edits uncommitted in the worktree; the auto-workflow controller
   handles grading, commit creation, review, and staging.
8. FINAL RESPONSE must include:
   - CHANGED: exact file path(s) and function/variable names touched
   - EVIDENCE: 1-2 concrete code snippets or diff hunks showing the real edit
   - VERIFY: exact command(s) run and whether they passed or failed
   - COMMIT: always \"not committed\" (workflow controller handles commits)
9. End the final response with: Task completed
10. NEVER reply with only \"Done\", only a commit message, or a vague success claim

CRITICAL: Your response MUST start with HYPOTHESIS: on the first line.
DO NOT add comments, docstrings, or documentation.
DO make actual code changes that improve functionality.
DO include concrete evidence of what changed so the grader can inspect it.

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

(defun gptel-auto-workflow--kept-target-count-from-results-file (file)
  "Return the number of distinct kept targets recorded in TSV FILE."
  (if (not (file-exists-p file))
      0
    (with-temp-buffer
      (insert-file-contents file)
      (forward-line 1)
      (let ((seen (make-hash-table :test 'equal))
            (count 0))
        (while (not (eobp))
          (let* ((fields (split-string
                          (buffer-substring-no-properties
                           (line-beginning-position)
                           (line-end-position))
                          "\t"))
                 (target (nth 1 fields))
                 (decision (nth 7 fields)))
            (when (and (equal decision "kept")
                       (stringp target)
                       (not (string-empty-p target))
                       (not (gethash target seen)))
              (puthash target t seen)
              (cl-incf count)))
          (forward-line 1))
        count))))

(defun gptel-auto-workflow--sync-live-kept-count (run-id results-file)
  "Refresh live workflow kept count from RESULTS-FILE for active RUN-ID."
  (when (and gptel-auto-workflow--running
             (stringp run-id)
             (equal run-id (gptel-auto-workflow--current-run-id)))
    (setq gptel-auto-workflow--stats
          (plist-put
           gptel-auto-workflow--stats
           :kept
           (gptel-auto-workflow--kept-target-count-from-results-file
            results-file)))
    (gptel-auto-workflow--persist-status)))

(defun gptel-auto-experiment-log-tsv (run-id experiment)
  "Append EXPERIMENT to results.tsv for RUN-ID."
  (let* ((base-dir (gptel-auto-workflow--worktree-base-root))
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
      (write-region (point-min) (point-max) file))
    (gptel-auto-workflow--sync-live-kept-count run-id file)))

;;; Error Analysis and Adaptive Workflow

(defvar gptel-auto-experiment--api-error-count 0
  "Count of API errors in current run.")

(defvar gptel-auto-experiment--api-error-threshold 3
  "Threshold of API errors before reducing experiment count.")

(defvar gptel-auto-experiment--quota-exhausted nil
  "Non-nil when provider quota exhaustion should stop the current workflow.")

(defun gptel-auto-experiment--error-snippet (agent-output &optional max-len)
  "Extract safe snippet from AGENT-OUTPUT for logging.
MAX-LEN defaults to 200 characters. Handles nil/empty strings safely."
  (when (and (stringp agent-output) (> (length agent-output) 0))
    (my/gptel--sanitize-for-logging agent-output (or max-len 200))))

(defvar gptel-auto-experiment-max-retries 2
  "Maximum retries for executor on transient errors.")

(defvar gptel-auto-experiment-retry-delay 5
  "Seconds to wait between retries.")

(defun gptel-auto-experiment--is-retryable-error-p (error-output)
  "Check if ERROR-OUTPUT is a transient/retryable error."
  (and (stringp error-output)
       (let ((case-fold-search t))
         (string-match-p
          "throttling\\|rate.limit\\|quota\\|429\\|timeout\\|timed out\\|temporary\\|overloaded\\|curl failed with exit code 28\\|curl failed with exit code 56\\|operation timed out"
          error-output))))

(defun gptel-auto-experiment--grade-failure-error-output (grade-details agent-output)
  "Return retryable/error-shaped output for a failed grade.
Prefer GRADE-DETAILS when the grader itself failed transiently; otherwise
fall back to an error-shaped AGENT-OUTPUT."
  (cond
   ((and (stringp grade-details)
         (or (gptel-auto-experiment--agent-error-p grade-details)
             (gptel-auto-experiment--is-retryable-error-p grade-details)
             (gptel-auto-experiment--quota-exhausted-p grade-details)))
    grade-details)
   ((gptel-auto-experiment--agent-error-p agent-output)
    agent-output)))

(defun gptel-auto-experiment--hard-timeout-p (error-output)
  "Return non-nil when ERROR-OUTPUT reports a hard wall-clock timeout."
  (and (stringp error-output)
       (string-match-p "timed out after [0-9]+s total runtime" error-output)))

(defun gptel-auto-experiment--result-hard-timeout-p (result)
  "Return non-nil when RESULT failed due to a hard executor timeout."
  (and (not (plist-get result :validation-retry))
       (gptel-auto-experiment--hard-timeout-p
        (or (plist-get result :error)
            (plist-get result :agent-output)
            (plist-get result :grader-reason)))))

(defun gptel-auto-experiment--quota-exhausted-p (agent-output)
  "Return non-nil when AGENT-OUTPUT shows provider quota exhaustion."
  (and (stringp agent-output)
       (let ((case-fold-search t))
         (string-match-p
          "allocated quota exceeded\\|usage limit exceeded\\|insufficient_quota\\|insufficient balance\\|billing_hard_limit_reached\\|hard limit reached"
          agent-output))))

(defun gptel-auto-experiment--run-with-retry (target experiment-id max-experiments baseline baseline-code-quality previous-results callback &optional retry-count)
  "Run experiment with automatic retry on transient errors.
RETRY-COUNT tracks current retry attempt."
  (let ((retries (or retry-count 0))
        (workflow-root (gptel-auto-workflow--resolve-run-root))
        (retry-buffer (current-buffer))
        (run-id gptel-auto-workflow--run-id))
    (gptel-auto-experiment-run
     target experiment-id max-experiments baseline baseline-code-quality previous-results
         (lambda (result)
           (let* ((agent-output (plist-get result :agent-output))
                  (raw-error (or (plist-get result :error)
                                 (and (gptel-auto-experiment--agent-error-p agent-output)
                                      agent-output)))
                 (error-type (plist-get result :comparator-reason))
                 (hard-timeout
                  (gptel-auto-experiment--hard-timeout-p raw-error))
                 (quota-exhausted
                  (or gptel-auto-experiment--quota-exhausted
                      (gptel-auto-experiment--quota-exhausted-p agent-output)))
                  (api-rate-limit-category
                   (memq error-type '(:api-rate-limit)))
                  (timeout-category
                   (memq error-type '(:timeout)))
                  (retryable-category
                   (or api-rate-limit-category
                       (and (not hard-timeout)
                            timeout-category)))
                  (retryable-failure
                   (or retryable-category
                       (and raw-error
                            (not hard-timeout)
                            (gptel-auto-experiment--is-retryable-error-p raw-error)))))
             (when quota-exhausted
               (setq gptel-auto-experiment--quota-exhausted t))
             (if (and (not quota-exhausted)
                      (< retries gptel-auto-experiment-max-retries)
                      retryable-failure)
                (progn
                   (message "[auto-exp] Retrying experiment %d (attempt %d/%d) after %ds delay"
                            experiment-id (1+ retries) gptel-auto-experiment-max-retries
                            gptel-auto-experiment-retry-delay)
                   (run-with-timer gptel-auto-experiment-retry-delay nil
                                   (lambda ()
                                     (if (gptel-auto-workflow--run-callback-live-p run-id)
                                         (gptel-auto-workflow--call-in-run-context
                                          workflow-root
                                          (lambda ()
                                            (gptel-auto-experiment--run-with-retry
                                             target experiment-id max-experiments baseline baseline-code-quality
                                             previous-results callback (1+ retries)))
                                          retry-buffer
                                          workflow-root)
                                       (progn
                                          (message "[auto-exp] Skipping stale retry for experiment %d; run %s is no longer active"
                                                   experiment-id run-id)
                                          (funcall callback
                                                   (list :target target
                                                         :id experiment-id
                                                         :stale-run t)))))))
                (when hard-timeout
                  (message "[auto-exp] Hard executor timeout during experiment %d; skipping retries"
                           experiment-id))
               (when quota-exhausted
                 (message "[auto-exp] Quota exhausted during experiment %d; skipping retries"
                          experiment-id))
               (funcall callback result)))))))
(defun gptel-auto-experiment--categorize-error (agent-output)
  "Categorize error from AGENT-OUTPUT and return (CATEGORY . DETAILS).
Categories: :api-rate-limit :api-error :tool-error :timeout :grader-failed :unknown
Also logs agent-output snippet for debugging when category is :unknown."
   (cond
    ((or (null agent-output) (string= agent-output ""))
     (cons :grader-failed "Grader returned no output"))
    ((string-match-p "hour allocated quota exceeded" agent-output)
     (cons :api-rate-limit "Hourly quota exhausted"))
    ((string-match-p "week allocated quota exceeded" agent-output)
     (cons :api-rate-limit "Weekly quota exhausted"))
    ((string-match-p "throttling\\|rate.limit\\|quota exceeded\\|429" agent-output)
     (cons :api-rate-limit "API rate limit exceeded"))
    ((string-match-p "invalid_parameter_error\\|InvalidParameter\\|JSON format" agent-output)
     (cons :api-error "API parameter error (invalid JSON format)"))
    ((let ((case-fold-search t))
       (string-match-p "timeout\\|timed out\\|curl failed with exit code 28\\|curl failed with exit code 56\\|operation timed out"
                       agent-output))
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
      (let ((halved (max 1 (ash original-max -1))))
        (message "[auto-workflow] Reducing experiments from %d to %d due to API errors"
                 original-max halved)
        halved)
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
         (message "[auto-experiment] Attempt %d/%d failed: %s"
                  attempts max
                  (my/gptel--sanitize-for-logging (error-message-string err) 160))
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
          (experiment-worktree (or worktree default-directory))
          (experiment-buffer (and worktree
                                  (fboundp 'gptel-auto-workflow--get-worktree-buffer)
                                  (ignore-errors
                                    (gptel-auto-workflow--get-worktree-buffer
                                     experiment-worktree))))
          (experiment-branch (or (gptel-auto-workflow--get-current-branch target)
                                 (gptel-auto-workflow--branch-name target experiment-id)))
          ;; CRITICAL: Set default-directory to worktree so all subagents
          ;; operate in the correct context. Each worktree = one session.
          (default-directory experiment-worktree)
         ;; Get project buffer for overlay routing (ensure hash table exists)
         (project-buf (when (and (boundp 'gptel-auto-workflow--current-project)
                                 gptel-auto-workflow--current-project
                                 (boundp 'gptel-auto-workflow--project-buffers)
                                 (hash-table-p gptel-auto-workflow--project-buffers))
                        (gethash (expand-file-name gptel-auto-workflow--current-project)
                                 gptel-auto-workflow--project-buffers)))
         ;; Disable preview for headless auto-workflow
         (gptel-tools-preview-enabled nil)
         ;; Disable tool confirmations for headless auto-workflow
         (gptel-confirm-tool-calls nil)
          ;; Capture the experiment timeout lexically because later analyzer
          ;; callbacks run after this outer let frame exits.
          (experiment-timeout gptel-auto-experiment-time-budget)
          (run-id gptel-auto-workflow--run-id)
          ;; The subagent timeout wrapper owns executor timeout/abort behavior.
          (my/gptel-agent-task-timeout experiment-timeout)
          (start-time (float-time))
          (finished nil)
          (executor-prompt nil))
    (if (not worktree)
        (funcall callback (list :target target :error "Failed to create worktree"))
      (gptel-auto-experiment--with-context experiment-buffer experiment-worktree
        (gptel-auto-experiment-analyze
         previous-results
         (lambda (analysis)
           (gptel-auto-experiment--with-context experiment-buffer experiment-worktree
             (let* ((patterns (when analysis (plist-get analysis :patterns)))
                    (prompt (gptel-auto-experiment-build-prompt
                             target experiment-id max-experiments analysis baseline)))
               (setq executor-prompt prompt)
                ;; Routing handled by gptel-auto-workflow--advice-task-override
                (my/gptel--run-agent-tool-with-timeout
                 experiment-timeout
                 (lambda (agent-output)
                  (gptel-auto-experiment--with-context experiment-buffer experiment-worktree
                    (if (gptel-auto-experiment--stale-run-p run-id)
                        (unless finished
                          (setq finished t)
                          (message "[auto-experiment] Ignoring stale executor callback for %s experiment %d; run %s is no longer active"
                                   target experiment-id run-id)
                          (funcall callback
                                   (gptel-auto-experiment--stale-run-result
                                    target experiment-id)))
                      (progn
                        (message "[auto-exp] Agent output (first 150 chars): %s"
                                 (my/gptel--sanitize-for-logging agent-output 150))
                        (unless finished
                      (let ((gptel-auto-experiment--grading-target target)
                            (gptel-auto-experiment--grading-worktree experiment-worktree))
                        (gptel-auto-experiment-grade
                         agent-output
                         (lambda (grade)
                          (gptel-auto-experiment--with-context experiment-buffer experiment-worktree
                           (if (gptel-auto-experiment--stale-run-p run-id)
                               (unless finished
                                 (setq finished t)
                                 (message "[auto-experiment] Ignoring stale grader callback for %s experiment %d; run %s is no longer active"
                                          target experiment-id run-id)
                                 (funcall callback
                                          (gptel-auto-experiment--stale-run-result
                                           target experiment-id)))
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
                          ;; Grader failures should classify from grader details when
                          ;; they carry the real transient/API error instead of the
                          ;; executor's normal success output.
                          (let* ((grade-error-output
                                  (gptel-auto-experiment--grade-failure-error-output
                                   grade-details agent-output))
                                 (error-source (or grade-error-output agent-output))
                                 (error-info (gptel-auto-experiment--categorize-error
                                              error-source))
                                 (error-category (car error-info))
                                 (error-details (cdr error-info)))
                            (setq finished t)
                            ;; Track API errors for adaptive reduction
                            (when (memq error-category '(:api-rate-limit :api-error))
                             (cl-incf gptel-auto-experiment--api-error-count)
                             (message "[auto-workflow] API error #%d: %s"
                                      gptel-auto-experiment--api-error-count error-category)
                              (when (gptel-auto-experiment--quota-exhausted-p error-source)
                                (setq gptel-auto-experiment--quota-exhausted t)
                                (message "[auto-workflow] Provider quota exhausted; stopping remaining work for this run"))
                              ;; The outer experiment loop owns max-exp and will
                              ;; adapt or stop early based on the shared error count.
                              (when (>= gptel-auto-experiment--api-error-count 3)
                               (message "[auto-workflow] API pressure detected; reducing future experiments for %s"
                                        target)))
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
                             (when grade-error-output
                               (setq exp-result
                                     (plist-put exp-result :error grade-error-output)))
                             (gptel-auto-experiment-log-tsv
                              run-id exp-result)
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
                         (if passed
    (let
	((code-quality
	  (or (gptel-auto-experiment--code-quality-score) 0.5)))
      (gptel-auto-experiment-decide
       (list :score baseline :code-quality baseline-code-quality)
       (list :score score-after :code-quality code-quality :output
	     agent-output)
       (lambda (decision)
	 (unless finished
	   (setq finished t)
	   (let*
	       ((keep (plist-get decision :keep))
		(reasoning (plist-get decision :reasoning))
		(exp-result
		 (list :target target :id experiment-id :hypothesis
		       hypothesis :score-before baseline :score-after
		       score-after :code-quality code-quality :kept
		       keep :duration (- (float-time) start-time)
		       :grader-quality grade-score :grader-reason
		       (plist-get grade :details) :comparator-reason
		       reasoning :analyzer-patterns
		       (format "%s" patterns) :agent-output
		       agent-output)))
	     (if keep
		 (let* ((msg
			 (format
			  "◈ Optimize %s: %s\n\nHYPOTHESIS: %s\n\nEVIDENCE: Nucleus valid, tests in staging\nScore: %.2f → %.2f (+%.0f%%)"
			  target
			  (gptel-auto-experiment--summarize hypothesis)
			  hypothesis baseline score-after
			  (if (> baseline 0)
			      (* 100
				 (/ (- score-after baseline) baseline))
			    0)))
			(default-directory experiment-worktree)
			(finalize
			 (gptel-auto-workflow--make-idempotent-callback
			  (lambda (&rest _)
			    (gptel-auto-experiment-log-tsv
			     run-id exp-result)
			    (funcall callback exp-result)))))
		   (gptel-auto-workflow--assert-main-untouched)
		   (message "[auto-experiment] ✓ Committing improvement for %s" target)
		   (magit-git-success "add" "-A")
		   (magit-git-success "commit" "-m" msg)
		   (gptel-auto-workflow--track-commit experiment-id
						      target
						      experiment-worktree)
		   (setq gptel-auto-experiment--best-score score-after
			 gptel-auto-experiment--no-improvement-count 0)
		   (if gptel-auto-experiment-auto-push
		       (progn
			 (message "[auto-experiment] Pushing to %s" experiment-branch)
			 (magit-git-success "push" "origin" experiment-branch)
			 (if gptel-auto-workflow-use-staging
			     (gptel-auto-workflow--staging-flow
			      experiment-branch
			      finalize)
			   (funcall finalize)))
		     (funcall finalize)))
	       (let ((default-directory experiment-worktree))
		 (message "[auto-experiment] Discarding changes for %s (no improvement)" target)
		 (magit-git-success "checkout" "--" ".")
		 (cl-incf gptel-auto-experiment--no-improvement-count)
		 (gptel-auto-experiment-log-tsv
		  run-id exp-result)
		 (funcall callback exp-result))))))))
                          (if (and (gptel-auto-experiment--teachable-validation-error-p
                                    target validation-error)
                                   (not (bound-and-true-p gptel-auto-experiment--in-retry)))
                              (let ((default-directory experiment-worktree)
                                    (gptel-auto-experiment--in-retry t))
                                (message "[auto-experiment] Validation failed with teachable pattern, retrying...")
                                (message "[auto-experiment] ✗ %s"
                                         (my/gptel--sanitize-for-logging validation-error 200))
                                (magit-git-success "checkout" "--" ".")
                                (let ((gptel-auto-experiment-active-grace
                                       gptel-auto-experiment-validation-retry-active-grace))
                                  (my/gptel--run-agent-tool-with-timeout
                                   gptel-auto-experiment-validation-retry-time-budget
                                   (lambda (retry-output)
                                     (let ((gptel-auto-experiment--grading-target target)
                                           (gptel-auto-experiment--grading-worktree experiment-worktree))
                                       (gptel-auto-experiment-grade
                                        retry-output
                                       (lambda (retry-grade)
                                         (if (plist-get retry-grade :passed)
                                             (let ((retry-bench (gptel-auto-experiment-benchmark t)))
                                               (if (plist-get retry-bench :passed)
                                                    (let* ((retry-score (plist-get retry-bench :eight-keys))
                                                          (retry-quality
                                                           (or (gptel-auto-experiment--code-quality-score) 0.5))
                                                          (retry-hypothesis
                                                           (gptel-auto-experiment--extract-hypothesis retry-output)))
                                                     (message "[auto-experiment] ✓ Retry succeeded")
                                                     (gptel-auto-experiment-decide
                                                      (list :score baseline
                                                            :code-quality baseline-code-quality)
                                                      (list :score retry-score
                                                            :code-quality retry-quality
                                                            :output retry-output)
                                                      (lambda (decision)
                                                        (unless finished
                                                          (setq finished t)
                                                          (let* ((keep (plist-get decision :keep))
                                                                 (reasoning (plist-get decision :reasoning))
                                                                 (exp-result
                                                                  (list :target target
                                                                        :id experiment-id
                                                                        :hypothesis retry-hypothesis
                                                                        :score-before baseline
                                                                        :score-after retry-score
                                                                        :code-quality retry-quality
                                                                        :validation-retry t
                                                                        :kept keep
                                                                        :duration (- (float-time) start-time)
                                                                        :grader-quality (plist-get retry-grade :score)
                                                                        :grader-reason (plist-get retry-grade :details)
                                                                        :comparator-reason reasoning
                                                                        :analyzer-patterns (format "%s" patterns)
                                                                        :agent-output retry-output
                                                                        :retries 1)))
                                                            (if keep
                                                                (let* ((msg (format "◈ Retry: fix validation in %s"
                                                                                    target))
                                                                       (default-directory experiment-worktree)
                                                                       (finalize
                                                                        (gptel-auto-workflow--make-idempotent-callback
                                                                         (lambda (&rest _)
                                                                          (gptel-auto-experiment-log-tsv
                                                                           run-id exp-result)
                                                                           (funcall callback exp-result)))))
                                                                  (gptel-auto-workflow--assert-main-untouched)
                                                                  (magit-git-success "add" "-A")
                                                                  (magit-git-success "commit" "-m" msg)
                                                                  (gptel-auto-workflow--track-commit experiment-id
                                                                                                     target
                                                                                                     experiment-worktree)
                                                                  (setq gptel-auto-experiment--best-score retry-score
                                                                        gptel-auto-experiment--no-improvement-count 0)
                                                                  (if gptel-auto-experiment-auto-push
                                                                      (progn
                                                                        (message "[auto-experiment] Pushing to %s" experiment-branch)
                                                                        (magit-git-success "push" "origin" experiment-branch)
                                                                        (if gptel-auto-workflow-use-staging
                                                                            (gptel-auto-workflow--staging-flow
                                                                             experiment-branch
                                                                             finalize)
                                                                          (funcall finalize)))
                                                                    (funcall finalize)))
                                                              (let ((default-directory experiment-worktree))
                                                                (message "[auto-experiment] Discarding changes for %s (no improvement)" target)
                                                                (magit-git-success "checkout" "--" ".")
                                                                (cl-incf gptel-auto-experiment--no-improvement-count)
                                                                (gptel-auto-experiment-log-tsv
                                                                 run-id exp-result)
                                                                (funcall callback exp-result))))))))
                                                 (setq finished t)
                                                  (message "[auto-experiment] ✗ Retry still failed validation")
                                                  (let* ((retry-hypothesis
                                                          (gptel-auto-experiment--extract-hypothesis retry-output))
                                                         (retry-validation-error
                                                          (plist-get retry-bench :validation-error))
                                                         (retry-tests-passed
                                                          (plist-get retry-bench :tests-passed))
                                                         (reason
                                                          (cond
                                                           (retry-validation-error retry-validation-error)
                                                           ((not (plist-get retry-bench :nucleus-passed))
                                                            "nucleus-validation-failed")
                                                           ((not retry-tests-passed)
                                                            "tests-failed")
                                                           (t "verification-failed")))
                                                          (exp-result
                                                           (list :target target
                                                                 :id experiment-id
                                                                 :hypothesis retry-hypothesis
                                                                 :score-before baseline
                                                                 :score-after 0
                                                                 :validation-retry t
                                                                 :kept nil
                                                                 :duration (- (float-time) start-time)
                                                                 :grader-quality (plist-get retry-grade :score)
                                                                 :grader-reason (plist-get retry-grade :details)
                                                                 :comparator-reason reason
                                                                :analyzer-patterns (format "%s" patterns)
                                                                :agent-output retry-output
                                                                :retries 1
                                                                :validation-error retry-validation-error)))
                                                    (gptel-auto-experiment-log-tsv
                                                     run-id exp-result)
                                                    (funcall callback exp-result))))
                                            (setq finished t)
                                            (let* ((retry-hypothesis
                                                    (gptel-auto-experiment--extract-hypothesis retry-output))
                                                    (exp-result
                                                     (list :target target
                                                           :id experiment-id
                                                           :hypothesis retry-hypothesis
                                                           :score-before baseline
                                                           :score-after 0
                                                           :validation-retry t
                                                           :kept nil
                                                           :duration (- (float-time) start-time)
                                                           :grader-quality (plist-get retry-grade :score)
                                                           :grader-reason (plist-get retry-grade :details)
                                                           :comparator-reason "retry-grade-failed"
                                                          :analyzer-patterns (format "%s" patterns)
                                                          :agent-output retry-output
                                                          :retries 1)))
                                              (gptel-auto-experiment-log-tsv
                                               run-id exp-result)
                                               (funcall callback exp-result)))))))
                                   "executor"
                                   (format "Retry: fix validation error in %s" target)
                                   (gptel-auto-experiment--make-retry-prompt
                                    target validation-error executor-prompt))))
                            (let ((default-directory experiment-worktree))
                              (setq finished t)
                              (magit-git-success "checkout" "--" ".")
                              (let* ((reason
                                      (cond (validation-error validation-error)
                                            ((not (plist-get bench :nucleus-passed))
                                             "nucleus-validation-failed")
                                            ((not tests-passed) "tests-failed")
                                            (t "verification-failed")))
                                     (exp-result
                                      (list :target target
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
                                (message "[auto-experiment] ✗ %s for %s" reason target)
                                (gptel-auto-experiment-log-tsv
                                 run-id exp-result)
                                (funcall callback exp-result))))))
))))))))))))
                   "executor"
                   (format "Experiment %d: optimize %s" experiment-id target)
                   executor-prompt
                   nil "false" nil))))))))
    )





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
   ;; Guard against non-string input
   ((not (stringp output))
    "No hypothesis stated")
   ;; Check for error message first
   ((string-match-p "^Error:" output)
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

(defun gptel-auto-experiment--teachable-validation-error-p (target validation-error)
  "Return non-nil when VALIDATION-ERROR should trigger an immediate retry.
TARGET is the file currently being optimized."
  (and (stringp validation-error)
       (> (length validation-error) 0)
       (not
        (null
         (or (string-match-p
              "cl-return-from.*without.*cl-block\\|Dangerous pattern"
              validation-error)
             (and (stringp target)
                  (string-suffix-p ".el" target)
                  (string-match-p "\\`Syntax error in " validation-error)))))))

(defun gptel-auto-experiment--make-retry-prompt (target validation-error original-prompt)
  "Create retry prompt after validation failure.
TARGET is the file being edited.
VALIDATION-ERROR is the error message.
Instructs executor to load relevant skill instead of hardcoding patterns."
  (let ((skill-guidance
         (cond
          ;; Elisp syntax and dangerous patterns - tell executor to load skill
          ((and (stringp target)
                (string-suffix-p ".el" target)
                (or (string-match-p
                     "cl-return-from.*without.*cl-block\\|Dangerous pattern"
                     validation-error)
                    (string-match-p "\\`Syntax error in " validation-error)))
           "CALL THIS FIRST: Skill(\"elisp-expert\")
This skill teaches syntax-safe Elisp edits and dangerous patterns including cl-return-from requirements.")
          ;; Add more skill mappings here as needed
          (t "")))
        (original-contract
         (if (and (stringp original-prompt)
                  (> (length original-prompt) 0))
             original-prompt
           (concat
            "FINAL RESPONSE must include:\n"
            "- CHANGED: exact file path(s) and function/variable names touched\n"
            "- EVIDENCE: 1-2 concrete code snippets or diff hunks showing the real edit\n"
            "- VERIFY: exact command(s) run and whether they passed or failed\n"
            "- COMMIT: always \"not committed\"\n"
            "End the final response with: Task completed"))))
    (format "Your previous edit to %s was REJECTED due to validation error:

ERROR: %s

IMPORTANT:
1. This is a focused repair retry, not a fresh experiment.
2. Fix ONLY the reported validation issue in %s with the smallest possible edit.
3. Keep the earlier improvement if it still makes sense after the repair; do not broaden the change.
4. Prefer focused reads near the reported failure instead of rereading large files.
5. Do not run broad repo tests or compile unrelated files until the validation issue is fixed.
6. For Elisp syntax errors, repair the parse error first and confirm the file reads or byte-compiles before broader verification.
7. Reuse the original experiment contract and final response format below.

Before retrying, load the relevant skill for guidance.

%s

ORIGINAL TASK:
%s"
            target
            validation-error
            target
            skill-guidance
            original-contract)))

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
         (run-id gptel-auto-workflow--run-id)
         (workflow-root (gptel-auto-workflow--resolve-run-root))
         (loop-buffer (current-buffer))
         (results nil)
         (best-score (gptel-auto-workflow--plist-get baseline :eight-keys 0.0))
         (no-improvement-count 0))
    (message "[auto-experiment] Baseline for %s: %.2f (max-exp: %d)"
             target best-score max-exp)
    (cl-labels ((run-next (exp-id)
                  (when gptel-auto-experiment--quota-exhausted
                    (message "[auto-workflow] Provider quota exhausted; stopping early for %s"
                             target)
                    (setq max-exp (min max-exp (1- exp-id))))
                  (when (and (> gptel-auto-experiment--api-error-count 5)
                             (< exp-id max-exp))
                    (message "[auto-workflow] Too many API errors (%d), stopping early for %s"
                             gptel-auto-experiment--api-error-count target)
                    (setq max-exp (1- exp-id)))
                   (if (or (> exp-id max-exp)
                           (>= no-improvement-count threshold))
                       (progn
                         (message "[auto-experiment] Done with %s: %d experiments, best score %.2f"
                                  target (length results)
                                  best-score)
                         (funcall callback (nreverse results)))
                    (gptel-auto-experiment--run-with-retry
                      target exp-id max-exp
                      best-score
                      baseline-code-quality
                      results
                     (lambda (result)
                       (push result results)
                       (gptel-auto-workflow--update-progress)
                         (let* ((score-after (gptel-auto-workflow--plist-get result :score-after 0))
                                (hard-timeout
                                 (gptel-auto-experiment--result-hard-timeout-p result))
                                (next-exp-id (if hard-timeout
                                                 (1+ max-exp)
                                               (1+ exp-id))))
                           (when (and score-after (> score-after best-score))
                             (setq best-score score-after
                                   no-improvement-count 0))
                           (when (and score-after (< score-after best-score))
                             (cl-incf no-improvement-count))
                            (when hard-timeout
                              (message "[auto-experiment] Hard timeout for %s in experiment %d; stopping remaining experiments for this target"
                                       target exp-id))
                             (let ((continue
                                  (lambda ()
                                    (if (gptel-auto-workflow--run-callback-live-p run-id)
                                        (gptel-auto-workflow--call-in-run-context
                                         workflow-root
                                         (lambda () (run-next next-exp-id))
                                         loop-buffer
                                         workflow-root)
                                      (progn
                                        (message "[auto-experiment] Run %s no longer active; returning accumulated results for %s"
                                                 run-id target)
                                        (funcall callback (nreverse results)))))))
                               (if (> gptel-auto-experiment-delay-between 0)
                                   (run-with-timer gptel-auto-experiment-delay-between nil
                                                   continue)
                                (funcall continue)))))))))
      (gptel-auto-workflow--call-in-run-context
       workflow-root
       (lambda () (run-next 1))
       loop-buffer
       workflow-root))))

;;; Main Entry Point

(defvar gptel-auto-workflow--running nil
  "Flag to track if auto-workflow is currently running.")

(defvar gptel-auto-workflow--headless nil
  "Flag to suppress interactive prompts during headless operation.")

(defvar gptel-auto-workflow--auto-revert-was-enabled nil
  "Remember if global-auto-revert-mode was enabled before headless operation.")

(defvar gptel-auto-workflow--uniquify-style nil
  "Remember uniquify-buffer-name-style before headless operation.")

(defvar gptel-auto-workflow--create-lockfiles-value t
  "Remember `create-lockfiles' before headless operation.")

(defvar gptel-auto-workflow--stats nil
  "Current run statistics: (:kept :total :phase).")

(defvar gptel-auto-workflow--current-target nil
  "Current target file being processed by auto-workflow.")

(defvar gptel-auto-workflow--cron-job-running nil
  "Non-nil while a queued cron job is executing.")

(defvar gptel-auto-workflow--watchdog-timer nil
  "Watchdog timer to prevent workflow from getting stuck.")

(defvar gptel-auto-workflow--last-progress-time nil
  "Timestamp of last progress update.")

(defvar gptel-auto-workflow--max-stuck-minutes 30
  "Maximum minutes workflow can be stuck before auto-stopping.")

(defcustom gptel-auto-workflow-status-file "var/tmp/cron/auto-workflow-status.sexp"
  "Path to the persisted auto-workflow status snapshot.
Relative paths are resolved from the project root."
  :type 'file
  :group 'gptel)

(defun gptel-auto-workflow--status-file ()
  "Return absolute path to the persisted workflow status snapshot."
  (let* ((configured-file gptel-auto-workflow-status-file)
         (default-file "var/tmp/cron/auto-workflow-status.sexp")
         (env-file (getenv "AUTO_WORKFLOW_STATUS_FILE")))
    (cond
     ((not (equal configured-file default-file))
      (if (file-name-absolute-p configured-file)
          configured-file
        (expand-file-name configured-file
                          (gptel-auto-workflow--default-dir))))
     ((and (stringp env-file)
           (not (string-empty-p env-file)))
      env-file)
     ((file-name-absolute-p configured-file)
      configured-file)
     (t
      (expand-file-name configured-file
                        (gptel-auto-workflow--default-dir))))))

(defun gptel-auto-workflow--status-plist ()
  "Return current workflow status as a plist."
  (let ((run-id (gptel-auto-workflow--current-run-id)))
    (list :running (or gptel-auto-workflow--running
                       (bound-and-true-p gptel-auto-workflow--cron-job-running))
          :kept (gptel-auto-workflow--plist-get gptel-auto-workflow--stats :kept 0)
          :total (gptel-auto-workflow--plist-get gptel-auto-workflow--stats :total 0)
          :phase (gptel-auto-workflow--plist-get gptel-auto-workflow--stats :phase "idle")
          :run-id run-id
          :results (gptel-auto-workflow--results-relative-path run-id))))

(defun gptel-auto-workflow--status-active-p (status)
  "Return non-nil when STATUS reflects an active workflow snapshot."
  (and (listp status)
       (or (plist-get status :running)
           (let ((phase (plist-get status :phase)))
             (and (stringp phase)
                  (not (member phase '("idle" "complete" "skipped"))))))))

(defun gptel-auto-workflow--status-placeholder-p (status)
  "Return non-nil when STATUS is only an idle placeholder snapshot."
  (and (listp status)
       (not (plist-get status :running))
       (equal (plist-get status :phase) "idle")
       (zerop (or (plist-get status :kept) 0))
       (zerop (or (plist-get status :total) 0))))

(defun gptel-auto-workflow--persist-status ()
  "Persist current workflow status for non-blocking cron health checks."
  (let* ((file (gptel-auto-workflow--status-file))
         (dir (file-name-directory file))
         (status (gptel-auto-workflow--status-plist)))
    (when dir
      (make-directory dir t))
    (with-temp-file file
      (let ((print-length nil)
            (print-level nil))
        (prin1 status (current-buffer))
        (insert "\n")))))

(defun gptel-auto-workflow-read-persisted-status ()
  "Read the persisted workflow status snapshot, or nil if unavailable."
  (let ((file (gptel-auto-workflow--status-file)))
    (when (file-readable-p file)
      (condition-case err
          (with-temp-buffer
            (insert-file-contents file)
            (goto-char (point-min))
            (read (current-buffer)))
        (error
         (message "[auto-workflow] Failed to read status snapshot: %s" err)
         nil)))))

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

(defun gptel-auto-workflow--suppress-ask-user-about-lock (orig-fn file opponent)
  "Suppress lock prompts in headless mode by grabbing the lock.
FILE and OPPONENT match `ask-user-about-lock'."
  (if gptel-auto-workflow--headless
      t
    (funcall orig-fn file opponent)))

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
  ;; Disable lockfiles so repeated experiment/worktree reuse does not prompt.
  (setq gptel-auto-workflow--create-lockfiles-value create-lockfiles
        create-lockfiles nil)
  ;; Remember and disable uniquify (prevents ".emacs.d/" prefix in buffer names)
  (setq gptel-auto-workflow--uniquify-style 
        (when (boundp 'uniquify-buffer-name-style)
          uniquify-buffer-name-style))
  (when (boundp 'uniquify-buffer-name-style)
    (setq uniquify-buffer-name-style nil))
  (advice-add 'ask-user-about-lock :around
              #'gptel-auto-workflow--suppress-ask-user-about-lock)
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
    ;; Restore lockfile behavior
    (setq create-lockfiles gptel-auto-workflow--create-lockfiles-value)
    ;; Restore uniquify
    (when (and (boundp 'gptel-auto-workflow--uniquify-style)
               gptel-auto-workflow--uniquify-style)
      (setq uniquify-buffer-name-style gptel-auto-workflow--uniquify-style))
    (advice-remove 'ask-user-about-lock
                   #'gptel-auto-workflow--suppress-ask-user-about-lock)
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
Returns command output as string.
Automatically adds --no-pager to prevent blocking on pager output."
  (gptel-auto-workflow--validate-non-empty-string cmd "command")
  (let ((git-cmd (if (string-match-p "^git " cmd)
                     (concat "git --no-pager " (substring cmd 4))
                   cmd)))
    (gptel-auto-workflow--shell-command-string git-cmd (or timeout gptel-auto-workflow-git-timeout))))


(defun gptel-auto-workflow--git-result (cmd &optional timeout)
  "Run git command CMD with TIMEOUT and return (OUTPUT . EXIT-CODE).
Automatically adds --no-pager to prevent blocking on pager output."
  (gptel-auto-workflow--validate-non-empty-string cmd "command")
  (let ((git-cmd (if (string-match-p "^git " cmd)
                     (concat "git --no-pager " (substring cmd 4))
                   cmd)))
    (gptel-auto-workflow--shell-command-with-timeout
     git-cmd
     (or timeout gptel-auto-workflow-git-timeout))))

(defun gptel-auto-workflow--with-staging-worktree (fn)
  "Run FN with `default-directory' bound to the staging worktree.
Creates the worktree on demand and returns nil if unavailable."
  (let ((worktree (or gptel-auto-workflow--staging-worktree-dir
                      (gptel-auto-workflow--create-staging-worktree))))
    (when (and worktree (file-exists-p worktree))
      (let ((default-directory worktree))
        (funcall fn)))))


(defun gptel-auto-workflow--watchdog-check ()
  "Check if workflow is stuck and force-stop if necessary.
Prevents workflow from hanging indefinitely due to callback failures."
  (when gptel-auto-workflow--running
    (let ((stuck-minutes (and gptel-auto-workflow--last-progress-time
                              (/ (float-time (time-subtract (current-time) gptel-auto-workflow--last-progress-time))
                                 60))))
      (cond
       ((null stuck-minutes)
        (message "[auto-workflow] WATCHDOG: No progress time recorded, force-stopping")
        (setq gptel-auto-workflow--running nil
              gptel-auto-workflow--cron-job-running nil
              gptel-auto-workflow--run-project-root nil
              gptel-auto-workflow--current-project nil
              gptel-auto-workflow--current-target nil)
        (setq gptel-auto-workflow--stats
              (plist-put gptel-auto-workflow--stats :phase "idle"))
        (gptel-auto-workflow--persist-status)
        (when gptel-auto-workflow--watchdog-timer
          (cancel-timer gptel-auto-workflow--watchdog-timer)
          (setq gptel-auto-workflow--watchdog-timer nil))
        nil)
       ((> stuck-minutes gptel-auto-workflow--max-stuck-minutes)
        (message "[auto-workflow] WATCHDOG: Workflow stuck for %.1f minutes, force-stopping"
                 stuck-minutes)
        (setq gptel-auto-workflow--running nil
              gptel-auto-workflow--cron-job-running nil
              gptel-auto-workflow--run-project-root nil
              gptel-auto-workflow--current-project nil
              gptel-auto-workflow--current-target nil)
        (setq gptel-auto-workflow--stats
              (plist-put gptel-auto-workflow--stats :phase "idle"))
        (gptel-auto-workflow--persist-status)
        (when gptel-auto-workflow--watchdog-timer
          (cancel-timer gptel-auto-workflow--watchdog-timer)
          (setq gptel-auto-workflow--watchdog-timer nil))
        nil)
       (t
        ;; Still running normally, check again in 5 minutes
        t)))))

(defun gptel-auto-workflow--update-progress ()
  "Update progress timestamp for watchdog tracking."
  (setq gptel-auto-workflow--last-progress-time (current-time)))

(defun gptel-auto-workflow-force-stop ()
  "Force stop a stuck workflow.
Interactive command to recover from hung workflow state."
  (interactive)
  (my/gptel--reset-agent-task-state)
  (gptel-mementum--reset-synthesis-state)
  (gptel-auto-experiment--reset-grade-state)
  (setq gptel-auto-workflow--running nil
        gptel-auto-workflow--cron-job-running nil
        gptel-auto-workflow--run-project-root nil
        gptel-auto-workflow--current-project nil
        gptel-auto-workflow--current-target nil)
  (setq gptel-auto-workflow--stats
        (plist-put gptel-auto-workflow--stats :phase "idle"))
  (gptel-auto-workflow--persist-status)
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
  (let* ((local-status
          (and (or gptel-auto-workflow--running
                   (bound-and-true-p gptel-auto-workflow--cron-job-running)
                   gptel-auto-workflow--stats)
               (gptel-auto-workflow--status-plist)))
         (persisted-status (gptel-auto-workflow-read-persisted-status)))
    (cond
     ((and (gptel-auto-workflow--status-placeholder-p local-status)
           (gptel-auto-workflow--status-active-p persisted-status))
      persisted-status)
     (local-status)
     (persisted-status)
     (t
      (gptel-auto-workflow--status-plist)))))


(defun gptel-auto-workflow--sanitize-unicode (str)
  "Sanitize Unicode characters in STR for safe display.
Replaces curly quotes, dashes, and zero-width characters with ASCII equivalents.
Returns empty string if STR is nil or not a string."
  (if (not (stringp str))
      ""
    (let ((clean str))
      (setq clean (replace-regexp-in-string
                   (regexp-opt (mapcar #'char-to-string '(?\u2018 ?\u2019 ?\u0060)))
                   "'"
                   clean))
      (setq clean (replace-regexp-in-string
                   (regexp-opt (mapcar #'char-to-string '(?\u201C ?\u201D)))
                   "\""
                   clean))
      (setq clean (replace-regexp-in-string
                   (regexp-opt (mapcar #'char-to-string '(?\u2013 ?\u2014)))
                   "-"
                   clean))
      (setq clean (replace-regexp-in-string (string ?\u2026) "..." clean))
      (setq clean (replace-regexp-in-string (string ?\u00A0) " " clean))
      (setq clean (replace-regexp-in-string
                   (regexp-opt (mapcar #'char-to-string '(?\u200B ?\u200C ?\u200D)))
                   ""
                   clean))
      clean)))


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
        (setq gptel-auto-workflow--stats
              (list :phase "skipped" :total 0 :kept 0))
        (gptel-auto-workflow--persist-status)
        (message "[auto-workflow] Skipping: %s" (string-join (car active) ", "))
        (cl-return-from gptel-auto-workflow-run-async nil)))
    (gptel-auto-workflow--require-magit-dependencies)
    (setq gptel-auto-workflow--current-project (gptel-auto-workflow--default-dir)
          gptel-auto-workflow--run-project-root (gptel-auto-workflow--default-dir)
          gptel-auto-workflow--run-id (or gptel-auto-workflow--run-id
                                          (gptel-auto-workflow--make-run-id))
          gptel-auto-experiment--api-error-count 0
          gptel-auto-experiment--quota-exhausted nil
          gptel-auto-workflow--running t
          gptel-auto-workflow--stats (list :phase "selecting" :total 0 :kept 0)
          gptel-auto-workflow--last-progress-time (current-time))
    (gptel-auto-workflow--persist-status)
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
         (gptel-auto-workflow--run-with-targets selected-targets completion-callback))))
    'started))

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


(defun gptel-auto-workflow-cron-safe (&optional completion-callback)
  "Run auto-workflow with full cleanup for cron jobs.
Cancels stale timers, kills orphaned buffers, resets state, then runs.
Safe to call from cron - handles all edge cases.
Sets `gptel-auto-workflow-persistent_headless' to prevent interactive prompts.
When COMPLETION-CALLBACK is non-nil, call it after the workflow finishes."
  (let* ((proj-root (gptel-auto-workflow--default-dir))
         (finish
          (gptel-auto-workflow--make-idempotent-callback
           (lambda (&optional results)
             (gptel-auto-workflow--disable-headless-suppression)
             (when completion-callback
               (funcall completion-callback results))))))
    (setq default-directory proj-root)
    (require 'magit)
    (require 'json)
    (unless (featurep 'gptel-tools-agent)
      (load-file (expand-file-name "lisp/modules/gptel-tools-agent.el" proj-root)))
    (setq gptel-auto-workflow-persistent-headless t)
    (gptel-auto-workflow--enable-headless-suppression)
    (if gptel-auto-workflow--running
        (progn
          (message "[auto-workflow] Job already running; skipping new request")
          (funcall finish nil)
          nil)
      (setq gptel-auto-experiment--api-error-count 0)
      (condition-case err
          (progn
            (gptel-auto-workflow--safe-call "Cleanup" #'gptel-auto-workflow--cleanup-stale-state)
            (gptel-auto-workflow--safe-call "Sync staging" #'gptel-auto-workflow--sync-staging-with-main)
            (gptel-auto-workflow--safe-call
             "Orphan scan"
             (lambda ()
               (let ((orphans (gptel-auto-workflow--recover-orphans)))
                 (when orphans
                   (message
                    "[auto-workflow] ⚠ Found %d orphan commit(s) from previous run; leaving them tracked for manual recovery"
                    (length orphans))))))
            (let ((started
                   (let ((gptel-auto-workflow-skip-if-recent-input nil))
                     (gptel-auto-workflow-run-async--guarded
                      nil
                      finish))))
              (unless started
                (funcall finish nil))
              started))
        (error
         (message "[auto-workflow] Cron error: %s"
                  (my/gptel--sanitize-for-logging (error-message-string err) 160))
         (setq gptel-auto-workflow--stats
               (list :phase "error" :total 0 :kept 0))
         (gptel-auto-workflow--persist-status)
         (funcall finish nil)
         nil)))))


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
  (let* ((proj-root (gptel-auto-workflow--worktree-base-root))
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
    (when (= active-processes 0)
      (let ((default-directory proj-root))
        (call-process "git" nil nil nil "worktree" "prune"))
        (let ((attached-worktrees
               (sort (copy-sequence (gptel-auto-workflow--optimize-worktrees proj-root))
                     (lambda (a b)
                       (> (length (plist-get a :path))
                          (length (plist-get b :path)))))))
        (dolist (entry attached-worktrees)
          (let ((path (plist-get entry :path))
                (branch (plist-get entry :branch)))
            (condition-case err
                (progn
                  (gptel-auto-workflow--discard-worktree-buffers path)
                  (call-process "git" nil nil nil "worktree" "remove" "-f" path)
                  (when (file-exists-p path)
                    (delete-directory path t))
                  (call-process "git" nil nil nil "branch" "-D" branch)
                  (cl-incf removed))
              (error
               (message "[auto-workflow] Failed to cleanup %s: %s" path err))))))
      (when (file-exists-p optimize-dir)
        (let ((dirs (directory-files optimize-dir t pattern)))
          (dolist (dir dirs)
            (when (file-exists-p dir)
              (condition-case err
                  (progn
                    (gptel-auto-workflow--discard-worktree-buffers dir)
                    (delete-directory dir t)
                    (cl-incf removed))
                (error
                 (message "[auto-workflow] Failed to cleanup %s: %s" dir err))))))))
    (when (> removed 0)
      (message "[auto-workflow] Cleaned %d old worktrees" removed))
    removed))

(defun gptel-auto-workflow--cleanup-stale-state ()
  "Clean up stale timers, buffers, and state from aborted runs."
  (let ((proj-root (gptel-auto-workflow--default-dir))
        (cleaned 0))
    (when proj-root
      (my/gptel--reset-agent-task-state)
      (gptel-mementum--reset-synthesis-state)
      (gptel-auto-experiment--reset-grade-state)
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
      (setq gptel-auto-workflow--stats
            (plist-put gptel-auto-workflow--stats
                       :phase (if (bound-and-true-p gptel-auto-workflow--cron-job-running)
                                  (or (plist-get gptel-auto-workflow--stats :phase)
                                      "queued")
                                "idle")))
      (gptel-auto-workflow--persist-status)
      (clrhash gptel-auto-workflow--worktree-state))
    (when (> cleaned 0)
      (message "[auto-workflow] Cleaned %d stale items" cleaned))))

(defun gptel-auto-workflow--kept-target-count (results)
  "Return the number of distinct targets with kept results in RESULTS."
  (let ((seen (make-hash-table :test 'equal))
        (count 0))
    (dolist (result results count)
      (let ((target (plist-get result :target)))
        (when (and (plist-get result :kept)
                   (stringp target)
                   (not (gethash target seen)))
          (puthash target t seen)
          (cl-incf count))))))

(defun gptel-auto-workflow--run-with-targets (targets completion-callback)
  "Run experiments for TARGETS sequentially."
  (let* ((run-id (gptel-auto-workflow--current-run-id))
         (callback-run-id (and gptel-auto-workflow--running
                               gptel-auto-workflow--run-id))
         (proj-root (gptel-auto-workflow--default-dir))
         (run-buffer (current-buffer))
         (all-results '())
         (kept-count 0)
         (finish
          (gptel-auto-workflow--make-idempotent-callback
           (lambda ()
              (let ((final-phase (if gptel-auto-experiment--quota-exhausted
                                     "quota-exhausted"
                                   "complete")))
                (setq gptel-auto-workflow--running nil
                      gptel-auto-workflow--run-project-root nil
                      gptel-auto-workflow--current-target nil
                      gptel-auto-workflow--current-project nil)
                (setq gptel-auto-workflow--stats
                      (plist-put gptel-auto-workflow--stats :phase final-phase))
                (gptel-auto-workflow--persist-status)
                (message "[auto-workflow] Complete: %d experiments, %d targets improved"
                         (length all-results) kept-count)
                (when completion-callback
                  (funcall completion-callback all-results)))))))
    ;; Set project context for subagent routing
    (setq gptel-auto-workflow--current-project proj-root
          gptel-auto-workflow--run-project-root proj-root)
    (setq gptel-auto-workflow--stats
          (plist-put gptel-auto-workflow--stats :phase "running"))
    (setq gptel-auto-workflow--stats
          (plist-put gptel-auto-workflow--stats :total (length targets)))
    (setq gptel-auto-workflow--stats
          (plist-put gptel-auto-workflow--stats :kept 0))
    (gptel-auto-workflow--persist-status)
    (message "[auto-workflow] Starting %s with %d targets" run-id (length targets))
    (cl-labels
        ((finish-run ()
           (funcall finish))
         (run-next (remaining-targets)
           (if (null remaining-targets)
               (finish-run)
              (let ((target (car remaining-targets)))
                (setq gptel-auto-workflow--current-target target)
                (let ((target-complete
                       (gptel-auto-workflow--make-idempotent-callback
                        (lambda (results)
                          (if (not (gptel-auto-workflow--run-callback-live-p callback-run-id))
                              (message "[auto-workflow] Ignoring stale target completion for %s; run %s is no longer active"
                                       target run-id)
                            (setq all-results (append all-results results))
                            (setq kept-count
                                  (gptel-auto-workflow--kept-target-count all-results))
                            (setq gptel-auto-workflow--stats
                                  (plist-put gptel-auto-workflow--stats :kept kept-count))
                            (gptel-auto-workflow--persist-status)
                            (if gptel-auto-experiment--quota-exhausted
                                (progn
                                  (message "[auto-workflow] Provider quota exhausted; stopping remaining targets")
                                  (finish-run))
                              (if (buffer-live-p run-buffer)
                                  (with-current-buffer run-buffer
                                    (let ((default-directory proj-root)
                                          (gptel-auto-workflow--project-root-override proj-root)
                                          (gptel-auto-workflow--current-project proj-root)
                                          (gptel-auto-workflow--run-project-root proj-root))
                                      (run-next (cdr remaining-targets))))
                                (let ((default-directory proj-root)
                                      (gptel-auto-workflow--project-root-override proj-root)
                                      (gptel-auto-workflow--current-project proj-root)
                                      (gptel-auto-workflow--run-project-root proj-root))
                                  (run-next (cdr remaining-targets))))))))))
                  (gptel-auto-experiment-loop target target-complete))))))
      (if (buffer-live-p run-buffer)
          (with-current-buffer run-buffer
            (let ((default-directory proj-root)
                  (gptel-auto-workflow--project-root-override proj-root)
                  (gptel-auto-workflow--current-project proj-root)
                  (gptel-auto-workflow--run-project-root proj-root))
              (run-next targets)))
        (let ((default-directory proj-root)
              (gptel-auto-workflow--project-root-override proj-root)
              (gptel-auto-workflow--current-project proj-root)
              (gptel-auto-workflow--run-project-root proj-root))
          (run-next targets))))))

(defun gptel-auto-workflow-run (&optional targets)
  "Run auto-workflow asynchronously.
Non-blocking - returns immediately, check status with `gptel-auto-workflow-status'.
TARGETS defaults to `gptel-auto-workflow-targets'."
  (interactive)
  (gptel-auto-workflow-run-async targets))

;;; Autonomous Research Agent (directive.md + skills + mementum)

(defcustom gptel-auto-workflow-program-file "docs/directive.md"
  "Path to directive.md (human-editable objectives)."
  :type 'file
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-skills-dir "mementum/knowledge"
  "Directory containing optimization-skills/ and mutations/."
  :type 'directory
  :group 'gptel-tools-agent)

(defvar gptel-auto-workflow--program nil
  "Parsed directive.md content.")

(defvar gptel-auto-workflow--skills nil
  "Loaded optimization skills for current run.")

(defun gptel-auto-workflow-load-program ()
  "Load and parse docs/directive.md."
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
  (let* ((target-name (if (gptel-auto-workflow--non-empty-string-p target)
                          target
                        "unknown"))
         (name (file-name-sans-extension (file-name-nondirectory target-name)))
         (parts (if (> (length name) 0) (split-string name "-") (list name)))
         (skill-name-candidate (car (last parts)))
         (skill-name (if (gptel-auto-workflow--non-empty-string-p skill-name-candidate)
                         skill-name-candidate
                       "unknown")))
    (if (eq type 'target)
        (format "%s/optimization-skills/%s.md" gptel-auto-workflow-skills-dir skill-name)
      (format "%s/mutations/%s.md" gptel-auto-workflow-skills-dir target-name))))

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
               (name (if def (plist-get def :name) "Unknown"))
               (symbol (if def (plist-get def :symbol) "?")))
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
            (when (and (stringp content)
                       (string-match "^last-tested:[[:space:]]*\\([0-9-]+\\)" content))
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

(defvar gptel-mementum--pending-llm-buffers nil
  "Buffers with active direct-LLM mementum synthesis requests.")

(defun gptel-mementum--track-llm-request-buffer (buffer)
  "Remember BUFFER as hosting an active direct-LLM synthesis request."
  (when (buffer-live-p buffer)
    (cl-pushnew buffer gptel-mementum--pending-llm-buffers)))

(defun gptel-mementum--untrack-llm-request-buffer (buffer)
  "Forget BUFFER from active direct-LLM synthesis tracking."
  (setq gptel-mementum--pending-llm-buffers
        (delq buffer gptel-mementum--pending-llm-buffers)))

(defun gptel-mementum--reset-synthesis-state ()
  "Abort and clear tracked direct-LLM synthesis requests."
  (dolist (buffer (delete-dups (delq nil gptel-mementum--pending-llm-buffers)))
    (when (and (buffer-live-p buffer)
               (fboundp 'gptel-abort))
      (ignore-errors (gptel-abort buffer))))
  (setq gptel-mementum--pending-llm-buffers nil))

(defun gptel-mementum--deliver-synthesis-result (project-root headless topic files result
                                                              &optional run-id request-buffer)
  "Handle synthesis RESULT for TOPIC/FILES inside PROJECT-ROOT context.
When RUN-ID is stale, ignore RESULT instead of writing new knowledge pages.
REQUEST-BUFFER is removed from direct-LLM tracking after delivery."
  (unwind-protect
      (if (not (gptel-auto-workflow--run-callback-live-p run-id))
          (message "[mementum] Ignoring stale synthesis for '%s'; run %s is no longer active"
                   topic run-id)
        (let ((default-directory project-root)
              (gptel-auto-workflow--current-project project-root)
              (gptel-auto-workflow--project-root-override project-root)
              (gptel-auto-workflow--run-project-root project-root)
              (gptel-auto-workflow--headless headless))
          (gptel-mementum--handle-synthesis-result topic files result)
          t))
    (when request-buffer
      (gptel-mementum--untrack-llm-request-buffer request-buffer))))

(defun gptel-mementum--synthesis-agent ()
  "Return the preferred agent symbol for mementum synthesis, or nil."
  (when (and (boundp 'gptel-agent--agents)
             gptel-agent--agents)
    (cond
     ((assoc "researcher" gptel-agent--agents) 'researcher)
     ((assoc "executor" gptel-agent--agents) 'executor)
     (t nil))))

(defun gptel-mementum--synthesis-backend ()
  "Return the preferred synthesis backend for mementum, or nil."
  (cond
   ((and (fboundp 'gptel-benchmark-llm-synthesize-knowledge)
         (fboundp 'gptel-request))
    'llm)
   (t
    (gptel-mementum--synthesis-agent))))

(defun gptel-mementum-synthesize-candidate (candidate &optional synchronous synthesis-backend callback-run-id)
  "Synthesize CANDIDATE into knowledge page with human approval.
CANDIDATE is plist with :topic :count :files.
Implements λ termination(x): synthesis ≡ AI | approval ≡ human.
Returns t if synthesis was initiated, nil otherwise.

CALLBACK-RUN-ID freezes the owning workflow identity for stale-callback checks.

Note: Call `gptel-mementum-ensure-agents' first for batch processing."
  (let* ((topic (plist-get candidate :topic))
          (files (plist-get candidate :files))
          (project-root (gptel-auto-workflow--project-root))
          (headless (bound-and-true-p gptel-auto-workflow--headless))
          (memories-content '()))
    (dolist (file files)
      (let ((content (gptel-auto-workflow--read-file-contents file)))
        (when content
          (push content memories-content))))
    (if (< (length memories-content) 3)
        (progn
          (message "[mementum] Skip synthesis: only %d memories for '%s'" (length memories-content) topic)
          nil)
        (let ((synthesis-prompt (gptel-mementum--build-synthesis-prompt topic memories-content)))
          (message "[mementum] Synthesizing %d memories for topic: %s" (length memories-content) topic)
          (let ((backend (or synthesis-backend
                             (gptel-mementum--synthesis-backend)))
                (captured-run-id (or callback-run-id
                                     (and gptel-auto-workflow--running
                                          (gptel-auto-workflow--current-run-id)))))
            (pcase backend
             ('llm
              (let ((request-buffer (current-buffer)))
                (when captured-run-id
                  (gptel-mementum--track-llm-request-buffer request-buffer))
                (if synchronous
                    (gptel-mementum--deliver-synthesis-result
                     project-root headless topic files
                     (gptel-benchmark-llm-synthesize-knowledge-sync
                      topic memories-content 300)
                     captured-run-id request-buffer)
                  (gptel-benchmark-llm-synthesize-knowledge
                   topic memories-content
                   (lambda (result &rest _)
                     (gptel-mementum--deliver-synthesis-result
                      project-root headless topic files result
                      captured-run-id request-buffer))))))
              ((pred symbolp)
               (if (and (fboundp 'gptel-benchmark-call-subagent)
                        (fboundp 'gptel-agent--task))
                   (if (and synchronous
                            (fboundp 'gptel-benchmark-call-subagent-sync))
                       (gptel-mementum--deliver-synthesis-result
                        project-root headless topic files
                        (gptel-benchmark-call-subagent-sync
                         backend
                         (format "Synthesize knowledge: %s" topic)
                         synthesis-prompt
                         300)
                        captured-run-id)
                     (gptel-benchmark-call-subagent
                      backend
                      (format "Synthesize knowledge: %s" topic)
                      synthesis-prompt
                      (lambda (result)
                        (gptel-mementum--deliver-synthesis-result
                         project-root headless topic files result captured-run-id))
                      300))
                 (message "[mementum] Skip '%s': no synthesis subagent available" topic)))
            (_
              (message "[mementum] Skip '%s': no synthesis backend available" topic))))
          t))))

(defun gptel-mementum-ensure-agents ()
  "Ensure a synthesis backend is available for mementum.
Returns `llm' when direct `gptel-request' synthesis is available, otherwise a
fallback subagent symbol such as `researcher' or `executor'."
  (let ((base-dir (or (bound-and-true-p user-emacs-directory)
                      (expand-file-name "~/.emacs.d"))))
    ;; Prefer direct, no-tool synthesis first.
    (unless (or (fboundp 'gptel-benchmark-llm-synthesize-knowledge)
                (featurep 'gptel-benchmark-llm))
      (load-file (expand-file-name "lisp/modules/gptel-benchmark-llm.el" base-dir)))
    (or (gptel-mementum--synthesis-backend)
        (progn
          ;; Ensure gptel-agent is loaded for subagent fallback.
          (unless (featurep 'gptel-agent)
            (let* ((elpa-dir (expand-file-name "var/elpa/" base-dir))
                   (yaml-dir (car (directory-files elpa-dir t "\\`yaml-"))))
              (when (and yaml-dir (file-directory-p yaml-dir))
                (add-to-list 'load-path yaml-dir)))
            (require 'gptel-agent nil t))
          (unless (fboundp 'gptel-benchmark-call-subagent)
            (load-file (expand-file-name "lisp/modules/gptel-benchmark-subagent.el" base-dir)))
          (when (fboundp 'gptel-agent--update-agents)
            (unless (and (boundp 'gptel-agent-dirs) gptel-agent-dirs)
              (let ((pkg-agents (expand-file-name "packages/gptel-agent/agents/" base-dir)))
                (setq gptel-agent-dirs
                      (cl-remove-if-not #'file-directory-p (list pkg-agents)))))
            (when (and (boundp 'gptel-agent-dirs) gptel-agent-dirs)
              (or (and (boundp 'gptel-agent--agents) gptel-agent--agents)
                  (gptel-agent--update-agents))))
          (gptel-mementum--synthesis-backend)))))

(defun gptel-mementum-synthesize-all-candidates (&optional candidates synchronous)
  "Synthesize all CANDIDATES (or detect if nil) with human approval.
Ensures agents are loaded once before processing batch."
  (let* ((cands (or candidates (gptel-mementum-check-synthesis-candidates)))
         (synthesized 0)
         (backend (gptel-mementum-ensure-agents))
         (batch-run-id (and gptel-auto-workflow--running
                            (gptel-auto-workflow--current-run-id)))
         (stopped nil))
    ;; Setup agents once for entire batch (not per-candidate)
    (if backend
        (progn
          (message "[mementum] %s available, processing %d candidates"
                   (pcase backend
                      ('llm "Direct LLM")
                      (_ (capitalize (symbol-name backend))))
                   (length cands))
          (dolist (candidate cands)
            (unless stopped
              (if (and batch-run-id
                       (not (gptel-auto-workflow--run-callback-live-p batch-run-id)))
                  (progn
                    (setq stopped t)
                    (message "[mementum] Stopping stale synthesis batch; run %s is no longer active"
                             batch-run-id))
                (when (gptel-mementum-synthesize-candidate
                       candidate synchronous backend batch-run-id)
                  (cl-incf synthesized))))))
      (message "[mementum] No synthesis backend available, skipping synthesis"))
    (message "[mementum] %s %d/%d candidates"
             (if synchronous "Synthesized" "Queued")
             synthesized
             (length cands))
    synthesized))

(defun gptel-mementum--handle-synthesis-result (topic files result)
  "Handle LLM synthesis RESULT for TOPIC from FILES.
Shows preview and asks for human approval before saving."
  (condition-case err
      (let* ((extracted (gptel-mementum--extract-content result))
             (line-count (with-temp-buffer (insert extracted) (count-lines 1 (point-max))))
             (preview-buffer (get-buffer-create "*Synthesis Preview*")))
        (if (< line-count 50)
            (message "[mementum] Skip '%s': only %d lines (need ≥50)" topic line-count)
          (with-current-buffer preview-buffer
            (erase-buffer)
            (insert (format "# Synthesis Preview: %s\n\n" topic))
            (insert (format "Generated: %d lines\n\n" line-count))
            (insert "## Generated Knowledge Page\n\n")
            (insert extracted)
            (goto-char (point-min)))
          (display-buffer preview-buffer)
          (when (y-or-n-p (format "Create knowledge page for '%s'? (%d lines) " topic line-count))
            (gptel-mementum--save-knowledge-page topic files extracted))))
    (error
     (message "[mementum] Error handling synthesis for '%s': %s" topic err))))

(defun gptel-mementum--build-synthesis-prompt (topic memories)
  "Build prompt for LLM to synthesize MEMORIES into knowledge page for TOPIC."
  (format "Synthesize the following memories into a knowledge page.

TOPIC: %s

REQUIREMENTS:
1. Minimum 50 lines of actual content
2. Concrete examples (code, tables, commands)
3. Actionable patterns (not just descriptions)
4. Cross-references to related topics
5. Return the full markdown page directly in your final response

IMPORTANT:
- Do not write files or edit the repository
- Do not use tools when the memories below already contain enough context
- Return the complete knowledge page inline, not a summary of what you wrote

OUTPUT FORMAT:
---
title: [Title]
status: active
category: knowledge
tags: [tag1, tag2]
---

# [Title]

## [Section 1]

[Content with examples]

## [Section 2]

[Content with patterns]

## Related

- [Related topics]

---

MEMORIES TO SYNTHESIZE:

%s

---

Generate the complete knowledge page now. Start with the frontmatter and include ALL content. Do not truncate or summarize - provide the full synthesis."
          topic
          (mapconcat #'identity memories "\n\n---\n\n")))

(defun gptel-mementum--extract-content (llm-result)
  "Extract knowledge page content from LLM-RESULT.
Returns the content between the first --- and end, or the whole result."
  (let* ((result (if (stringp llm-result) llm-result (format "%s" llm-result)))
         (start (string-match "---\n" result)))
    (if start
        (substring result start)
      result)))

(defun gptel-mementum--save-knowledge-page (topic files content)
  "Save synthesized CONTENT as knowledge page for TOPIC from FILES."
  (let* ((know-dir (expand-file-name "mementum/knowledge" (gptel-auto-workflow--project-root)))
         (know-file (expand-file-name (format "%s.md" topic) know-dir)))
    (make-directory know-dir t)
    (with-temp-file know-file
      (insert content))
    (message "[mementum] Created knowledge page: %s (%d lines)" 
             know-file 
             (with-temp-buffer (insert content) (count-lines 1 (point-max))))
    (shell-command-to-string
     (format "cd %s && git add %s && git commit -m %s"
             (shell-quote-argument (gptel-auto-workflow--project-root))
             (shell-quote-argument know-file)
             (shell-quote-argument (format "💡 synthesis: %s (AI-generated)" topic))))))



(defun gptel-mementum-weekly-job ()
  "Weekly mementum maintenance: decay + index rebuild + synthesis.
Implements λ synthesize(topic): ≥3 memories → candidate → human approval."
  (interactive)
  (message "[mementum] Starting weekly maintenance...")
  (gptel-mementum-build-index)
  (gptel-mementum-decay-skills)
  (let ((synthesized (gptel-mementum-synthesize-all-candidates nil t)))
    (message "[mementum] Weekly maintenance complete. Synthesized: %d" synthesized)))

(defun gptel-mementum-synthesis-run ()
  "Interactively run synthesis on all candidates.
M-x gptel-mementum-synthesis-run"
  (interactive)
  (gptel-mementum-synthesize-all-candidates))

(provide 'gptel-tools-agent)

;;; gptel-tools-agent.el ends here
