;;; gptel-tools-agent-base.el --- Base utilities, validation, shell commands -*- lexical-binding: t; -*-
;; Part of gptel-tools-agent split

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
(declare-function my/gptel--transient-error-p "gptel-ext-retry" (error-data http-status))
(declare-function gptel-auto-workflow--evolution-get-knowledge "gptel-auto-workflow-evolution" ())

;; Ensure evolution production module is loaded for timer and hook variables
(require 'gptel-auto-workflow-production nil t)

;; Forward declaration for variable defined in gptel-auto-workflow-projects.el.
;; Do not initialize it here, or later `defvar' initializers in the projects
;; module will be skipped and leave the shared table bound to nil.
(defvar gptel-auto-workflow--project-buffers)
(defvar gptel-auto-workflow--worktree-buffers)
(defvar gptel-auto-workflow--current-project nil)
(defvar gptel-auto-workflow--run-project-root nil)
(defvar gptel-auto-workflow--project-root-override)
(defvar gptel-agent-loop--bypass nil)
(defvar gptel-benchmark--subagent-files nil)

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
  (unless (gptel-auto-workflow--non-empty-string-p value)
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
  (if (listp plist)
      (if (plist-member plist key)
          (plist-get plist key)
        default)
    default))

(defun gptel-auto-workflow--state-active-p (state)
  "Return t if STATE is non-nil and not marked as done.
Reduces duplication of `(when (and state (not (plist-get state :done)))` patterns."
  (and state (not (plist-get state :done))))

(defun gptel-auto-workflow--hash-get-bound (var-sym key)
  "Get KEY from hash table bound to VAR-SYM, or nil if unbound/not a hash."
  (when (and (boundp var-sym)
             (hash-table-p (symbol-value var-sym)))
    (gethash key (symbol-value var-sym))))

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

(defun gptel-auto-workflow--call-with-error-logging (operation fn error-prefix error-message-format)
  "Internal helper: call FN with error logging.
OPERATION is the operation name for logging.
FN is the function to call.
ERROR-PREFIX is the prefix for error messages.
ERROR-MESSAGE-FORMAT is the format string for the error message.
Returns FN's result on success, nil on error."
  (condition-case err
      (funcall fn)
    (error
     (message "%s %s: %s"
              error-prefix
              (format error-message-format operation)
              (my/gptel--sanitize-for-logging (error-message-string err) 160))
     nil)))

(defun gptel-auto-workflow--safe-call (operation fn &optional error-prefix)
  "Execute FN for OPERATION, logging errors but continuing execution.
ERROR-PREFIX defaults to \"[auto-workflow]\".
Returns FN's result on success, nil on error.
Use for non-critical operations that should not halt execution."
  (gptel-auto-workflow--call-with-error-logging
   operation
   fn
   (or error-prefix "[auto-workflow]")
   "%s failed (non-critical)"))


(defun gptel-auto-workflow--with-error-handling (operation fn &optional error-prefix)
  "Execute FN for OPERATION, logging any error and returning nil.
ERROR-PREFIX defaults to \"[auto-workflow]\"."
  (gptel-auto-workflow--call-with-error-logging
   operation
   fn
   (or error-prefix "[auto-workflow]")
   "Failed to %s"))


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

(defun gptel-auto-workflow--elpa-package-dir (proj-root package)
  "Return the repo-local ELPA directory for PACKAGE under PROJ-ROOT, or nil."
  (let* ((root (file-name-as-directory (expand-file-name proj-root)))
         (elpa-dir (expand-file-name "var/elpa" root))
         (pattern (format "\\`%s-[0-9]" (regexp-quote package)))
         (candidates
          (and (file-directory-p elpa-dir)
               (seq-filter
                #'file-directory-p
                (directory-files elpa-dir t pattern)))))
    (car (sort candidates #'string>))))

(defun gptel-auto-workflow--cleanup-broken-elpa-entries (proj-root package)
  "Delete broken ELPA symlinks for PACKAGE under PROJ-ROOT."
  (let* ((root (file-name-as-directory (expand-file-name proj-root)))
         (elpa-dir (expand-file-name "var/elpa" root))
         (pattern (format "\\`%s-[0-9]" (regexp-quote package))))
    (when (file-directory-p elpa-dir)
      (dolist (entry (directory-files elpa-dir t pattern))
        (when (and (file-symlink-p entry)
                   (not (file-exists-p entry)))
          (delete-file entry))))))

(defun gptel-auto-workflow--install-elpa-package (proj-root package)
  "Install PACKAGE into PROJ-ROOT's repo-local ELPA cache when missing."
  (let* ((root (file-name-as-directory (expand-file-name proj-root)))
         (bootstrap (expand-file-name "lisp/modules/gptel-auto-workflow-bootstrap.el" root))
         (descs nil))
    (gptel-auto-workflow--cleanup-broken-elpa-entries root (symbol-name package))
    (when (file-readable-p bootstrap)
      (load-file bootstrap)
      (when (fboundp 'gptel-auto-workflow-bootstrap--configure-package-system)
        (gptel-auto-workflow-bootstrap--configure-package-system root))
      (when (fboundp 'gptel-auto-workflow-bootstrap--seed-load-path)
        (gptel-auto-workflow-bootstrap--seed-load-path root))
      (when (fboundp 'gptel-auto-workflow-bootstrap--load-package-archive-cache)
        (gptel-auto-workflow-bootstrap--load-package-archive-cache root))
      (unless (assq package package-archive-contents)
        (package-refresh-contents))
      (setq descs (cdr (assq package package-archive-contents)))
      (when descs
        (package-install
         (car (sort (copy-sequence descs)
                    (lambda (a b)
                      (version-list-< (package-desc-version b)
                                      (package-desc-version a))))))
        (package-initialize))
      (gptel-auto-workflow--elpa-package-dir root (symbol-name package)))))

(defun gptel-auto-workflow--prefer-elpa-transient (&optional proj-root)
  "Ensure repo-local ELPA transient shadows the built-in library.
When the live worker inherits Emacs's built-in transient, newer Magit or
evil-collection packages can fail on missing internals like
`transient--set-layout'.  Prefer the repo-local ELPA transient package and load
it when the current transient implementation is too old."
  (let* ((root (file-name-as-directory
                (expand-file-name
                 (or proj-root
                     (gptel-auto-workflow--default-dir)))))
         (dir (or (gptel-auto-workflow--elpa-package-dir root "transient")
                  (when (not (fboundp 'transient--set-layout))
                    (gptel-auto-workflow--install-elpa-package root 'transient)))))
    (when-let* ((dir dir)
                (lib (cl-find-if #'file-readable-p
                                 (list (expand-file-name "transient.elc" dir)
                                       (expand-file-name "transient.el" dir)))))
      (setq load-path (cons dir (delete dir load-path)))
      (when (or (not (fboundp 'transient--set-layout))
                (let ((current-lib (locate-library "transient")))
                  (and current-lib
                       (not (string-prefix-p dir current-lib)))))
        (load (file-name-sans-extension lib) nil 'nomessage))
      dir)))

(defun gptel-auto-workflow--seed-live-root-load-path (&optional proj-root)
  "Prepend repo-local load paths for PROJ-ROOT to `load-path'."
  (let* ((root (file-name-as-directory
                (expand-file-name
                 (or proj-root
                     (gptel-auto-workflow--default-dir)))))
         (bootstrap (expand-file-name "lisp/modules/gptel-auto-workflow-bootstrap.el" root))
         (dirs nil))
    (when (file-readable-p bootstrap)
      (load-file bootstrap)
      (when (fboundp 'gptel-auto-workflow-bootstrap--seed-load-path)
        (gptel-auto-workflow-bootstrap--seed-load-path root)))
    (setq dirs
          (append
           (list (expand-file-name "lisp/modules" root)
                 (expand-file-name "lisp" root)
                 (expand-file-name "packages/gptel" root)
                 (expand-file-name "packages/gptel-agent" root)
                 (expand-file-name "packages/ai-code" root))
           (when (fboundp 'gptel-auto-workflow-bootstrap--elpa-dirs)
             (gptel-auto-workflow-bootstrap--elpa-dirs root))))
    (dolist (dir (reverse dirs))
      (when (file-directory-p dir)
        (setq load-path (cons dir (delete dir load-path)))))
    dirs))

(defun my/gptel--retarget-live-buffer-directory (buffer-or-name dir)
  "Set BUFFER-OR-NAME `default-directory' to DIR when both are live."
  (when (and (stringp dir)
             (file-directory-p dir))
    (when-let ((buf (get-buffer buffer-or-name)))
      (with-current-buffer buf
        (setq default-directory (file-name-as-directory (expand-file-name dir))))
      buf)))

(defun gptel-auto-workflow--retarget-shared-process-buffers (proj-root)
  "Retarget shared curl/bash helper buffers to PROJ-ROOT.
Reset the persistent bash process when it still points at a different or
deleted directory."
  (let* ((root (file-name-as-directory (expand-file-name proj-root)))
         (bash-buf (get-buffer " *gptel-persistent-bash*"))
         (bash-dir (when (buffer-live-p bash-buf)
                     (with-current-buffer bash-buf default-directory)))
         (bash-process-live-p
          (and (boundp 'my/gptel--persistent-bash-process)
               (process-live-p my/gptel--persistent-bash-process)))
         (bash-needs-reset
          (and bash-process-live-p
               (or (not (and (stringp bash-dir)
                             (file-directory-p bash-dir)))
                   (not (equal (file-name-as-directory (expand-file-name bash-dir))
                               root))))))
    (my/gptel--retarget-live-buffer-directory " *gptel-curl*" root)
    (my/gptel--retarget-live-buffer-directory " *gptel-persistent-bash*" root)
    (when (and bash-needs-reset
               (fboundp 'my/gptel--reset-persistent-bash))
      (my/gptel--reset-persistent-bash))
    root))

(defun gptel-auto-workflow--activate-live-root (proj-root)
  "Retarget the live daemon to PROJ-ROOT for queued workflow actions."
  (let ((root (file-name-as-directory (expand-file-name proj-root))))
    (when (fboundp 'gptel-auto-workflow--discard-missing-worktree-buffers)
      (gptel-auto-workflow--discard-missing-worktree-buffers))
    (setq default-directory root
          user-emacs-directory root
          gptel-auto-workflow--project-root-override root
          gptel-auto-workflow--current-project nil
          gptel-auto-workflow--run-project-root nil)
    (when (boundp 'minimal-emacs-user-directory)
      (setq minimal-emacs-user-directory root))
    (when (boundp 'gptel-auto-workflow-projects)
      (setq gptel-auto-workflow-projects (list root)))
    (gptel-auto-workflow--retarget-shared-process-buffers root)
    (gptel-auto-workflow--seed-live-root-load-path root)
    (gptel-auto-workflow--prefer-elpa-transient root)
    root))

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

(defun gptel-auto-workflow--restore-live-target-file (target &optional proj-root)
  "Reload TARGET from PROJ-ROOT into the live worker after an experiment attempt.
This clears partial definitions leaked from optimize worktrees after tools or
executor self-checks load candidate Elisp files into the daemon."
  (when (and (gptel-auto-workflow--non-empty-string-p target)
             (string-match-p "\\.el\\'" target))
    (let* ((root (file-name-as-directory
                  (expand-file-name
                   (or proj-root
                       (gptel-auto-workflow--resolve-run-root)
                       (gptel-auto-workflow--project-root)
                       default-directory))))
           (target-file (expand-file-name target root)))
      (when (file-readable-p target-file)
        (condition-case err
            (let ((default-directory root)
                  (message-log-max nil)
                  (inhibit-message t))
              (load target-file nil t t)
              t)
          (error
           (message "[auto-workflow] Failed to restore live target %s: %s"
                    target
                    (my/gptel--sanitize-for-logging
                     (error-message-string err) 200))
           nil))))))
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

(defvar gptel-auto-workflow--active-shell-processes (make-hash-table :test 'eq)
  "Shell processes currently owned by auto-workflow helpers.")

(defun gptel-auto-workflow--register-shell-process (process)
  "Track PROCESS so force-stop can terminate it."
  (when (processp process)
    (puthash process t gptel-auto-workflow--active-shell-processes))
  process)

(defun gptel-auto-workflow--unregister-shell-process (process)
  "Stop tracking PROCESS."
  (when (and (processp process)
             (hash-table-p gptel-auto-workflow--active-shell-processes))
    (remhash process gptel-auto-workflow--active-shell-processes))
  process)

(defun gptel-auto-workflow--terminate-active-shell-processes ()
  "Terminate all shell processes currently tracked by auto-workflow."
  (when (hash-table-p gptel-auto-workflow--active-shell-processes)
    (let (processes)
      (maphash (lambda (process _)
                 (push process processes))
               gptel-auto-workflow--active-shell-processes)
      (clrhash gptel-auto-workflow--active-shell-processes)
      (dolist (process processes)
        (when (processp process)
          (ignore-errors
            (when (process-live-p process)
              (gptel-auto-workflow--terminate-process-tree process))))))))

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
          (setq process (gptel-auto-workflow--register-shell-process
                         (start-process-shell-command "shell-timeout" buffer command)))
          ;; Set up a timer to force timeout even if accept-process-output blocks
          (setq timer (run-with-timer timeout-seconds nil
                                      (lambda ()
                                        (unless done
                                          (setq done 'timeout)))))
          (set-process-sentinel process
                                (lambda (proc _event)
                                  (when (and (not done)
                                             (not (process-live-p proc)))
                                    (gptel-auto-workflow--unregister-shell-process proc)
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
          (when (timerp timer)
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
      (when (timerp timer)
        (cancel-timer timer))
      (when process
        (gptel-auto-workflow--unregister-shell-process process))
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

(defvar gptel-auto-workflow--status-run-id nil
  "Last run id that should remain visible in persisted workflow status.")

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

(defconst gptel-auto-workflow--results-tsv-header
  "experiment_id\ttarget\thypothesis\tscore_before\tscore_after\tcode_quality\tdelta\tdecision\tduration\tgrader_quality\tgrader_reason\tcomparator_reason\tanalyzer_patterns\tagent_output\n"
  "Header row written to auto-workflow results.tsv artifacts.")

(defun gptel-auto-workflow--results-file-path (&optional run-id)
  "Return the absolute results.tsv path for RUN-ID or the active run."
  (expand-file-name
   (gptel-auto-workflow--results-relative-path run-id)
   (gptel-auto-workflow--worktree-base-root)))

(defun gptel-auto-workflow--ensure-results-file (&optional run-id)
  "Ensure results.tsv exists for RUN-ID and return its absolute path."
  (let ((file (gptel-auto-workflow--results-file-path run-id)))
    (make-directory (file-name-directory file) t)
    (unless (file-exists-p file)
      (with-temp-file file
        (insert gptel-auto-workflow--results-tsv-header)))
    file))

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

(defun gptel-auto-workflow--tracking-ref (commit-hash)
  "Return the archival ref used to preserve tracked COMMIT-HASH."
  (format "refs/auto-workflow/kept/%s" commit-hash))

(defun gptel-auto-workflow--tracked-commit-pinned-p (commit-hash)
  "Return non-nil when COMMIT-HASH is preserved under an auto-workflow ref."
  (and (gptel-auto-workflow--non-empty-string-p commit-hash)
       (= 0 (cdr (gptel-auto-workflow--git-result
                  (format "git show-ref --verify --quiet %s"
                          (shell-quote-argument
                           (gptel-auto-workflow--tracking-ref commit-hash)))
                  30)))))

(defun gptel-auto-workflow--pin-tracked-commit (commit-hash)
  "Preserve COMMIT-HASH under a private auto-workflow ref.
Returns non-nil when the ref exists after the call."
  (and (gptel-auto-workflow--non-empty-string-p commit-hash)
       (gptel-auto-workflow--commit-exists-p commit-hash)
       (= 0 (cdr (gptel-auto-workflow--git-result
                  (format "git update-ref %s %s"
                          (shell-quote-argument
                           (gptel-auto-workflow--tracking-ref commit-hash))
                          (shell-quote-argument commit-hash))
                  30)))))

(defun gptel-auto-workflow--commit-tracked-in-ledgers-p (commit-hash)
  "Return non-nil when COMMIT-HASH still appears in any readable tracking ledger."
  (when (gptel-auto-workflow--non-empty-string-p commit-hash)
    (catch 'tracked
      (dolist (tracking-file (gptel-auto-workflow--tracking-files))
        (when (file-exists-p tracking-file)
          (with-temp-buffer
            (insert-file-contents tracking-file)
            (when (re-search-forward
                   (format "^%s " (regexp-quote commit-hash))
                   nil t)
              (throw 'tracked t)))))
      nil)))

(defun gptel-auto-workflow--delete-tracked-commit-ref (commit-hash)
  "Delete COMMIT-HASH's archival ref if it exists."
  (when (and (gptel-auto-workflow--non-empty-string-p commit-hash)
             (gptel-auto-workflow--tracked-commit-pinned-p commit-hash))
    (= 0 (cdr (gptel-auto-workflow--git-result
               (format "git update-ref -d %s"
                       (shell-quote-argument
                        (gptel-auto-workflow--tracking-ref commit-hash)))
               30)))))

(defun gptel-auto-workflow--tracked-entries ()
  "Return unique tracked commit entries from all readable ledgers."
  (let ((entries nil)
        (seen (make-hash-table :test 'equal)))
    (dolist (tracking-file (gptel-auto-workflow--tracking-files))
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
              (push (list hash exp-id target) entries))))))
    (nreverse entries)))

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
      (dolist (tracking-file tracking-files)
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
                  (delete-file tracking-file)))))))
      (when (and removed
                 (not (gptel-auto-workflow--commit-tracked-in-ledgers-p commit-hash)))
        (gptel-auto-workflow--delete-tracked-commit-ref commit-hash))
      removed)))

(defun gptel-auto-workflow--commit-exists-p (commit-hash)
  "Return non-nil when COMMIT-HASH resolves to an existing commit object."
  (and (gptel-auto-workflow--non-empty-string-p commit-hash)
       (= 0 (cdr (gptel-auto-workflow--git-result
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

(defun gptel-auto-workflow--commit-integrated-p (commit-hash)
  "Return non-nil when COMMIT-HASH is already represented in staging or main.
Checks both local and remote refs because cron resets the local staging branch to
the workflow base before scanning tracked ledgers."
  (when (gptel-auto-workflow--non-empty-string-p commit-hash)
    (let* ((remote-main (gptel-auto-workflow--shared-remote-branch "main"))
           (remote-staging
            (and (gptel-auto-workflow--non-empty-string-p
                  gptel-auto-workflow-staging-branch)
                 (gptel-auto-workflow--shared-remote-branch
                  gptel-auto-workflow-staging-branch)))
           (refs (delete-dups
                  (delq nil
                        (list gptel-auto-workflow-staging-branch
                              remote-staging
                              "main"
                              remote-main))))
           integrated)
      (dolist (ref refs integrated)
        (let ((ancestor-check
               (gptel-auto-workflow--git-cmd
                (format "git merge-base --is-ancestor %s %s 2>/dev/null && echo yes"
                        (shell-quote-argument commit-hash)
                        (shell-quote-argument ref)))))
          (when (or (not (string-empty-p ancestor-check))
                    (gptel-auto-workflow--commit-patch-equivalent-p commit-hash ref))
            (setq integrated t)))))))

(defun gptel-auto-workflow--resolve-ref-commit-hash (ref)
  "Return normalized commit hash for REF, or nil when REF cannot be resolved."
  (when (gptel-auto-workflow--non-empty-string-p ref)
    (let* ((rev-result
            (gptel-auto-workflow--git-result
             (format "git rev-parse %s"
                     (shell-quote-argument ref))
             60))
           (commit-hash (string-trim (car rev-result))))
      (and (= 0 (cdr rev-result))
           (string-match-p "^[a-f0-9]\\{7,40\\}$" commit-hash)
           commit-hash))))

(defun gptel-auto-workflow--optimize-branch-integrated-p (optimize-branch)
  "Return non-nil when OPTIMIZE-BRANCH tip is already represented in staging or main."
  (let* ((optimize-ref (gptel-auto-workflow--ensure-merge-source-ref optimize-branch))
         (commit-hash (gptel-auto-workflow--resolve-ref-commit-hash optimize-ref)))
    (and commit-hash
         (gptel-auto-workflow--commit-integrated-p commit-hash))))

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
      (unless (or (gptel-auto-workflow--tracked-commit-pinned-p commit-hash)
                  (gptel-auto-workflow--pin-tracked-commit commit-hash))
        (message "[auto-workflow] Failed to preserve tracked commit %s under recovery refs"
                 (gptel-auto-workflow--truncate-hash commit-hash)))
      commit-hash))))

(defun gptel-auto-workflow--recoverable-tracked-commits ()
  "Return tracked commits that still exist and are not already integrated.
Stale or already-integrated hashes are compacted out of the ledgers."
  (let ((recoverable nil)
        (stale-hashes nil))
    (dolist (entry (gptel-auto-workflow--tracked-entries))
      (pcase-let ((`(,hash ,_exp-id ,_target) entry))
        (cond
         ((not (gptel-auto-workflow--commit-exists-p hash))
          (push hash stale-hashes))
         ((gptel-auto-workflow--commit-integrated-p hash)
          (push hash stale-hashes))
         (t
          (push entry recoverable)))))
    (dolist (hash (delete-dups stale-hashes))
      (when (gptel-auto-workflow--untrack-commit hash)
        (message "[auto-workflow] Removed stale orphan record %s"
                 (gptel-auto-workflow--truncate-hash hash))))
    (nreverse recoverable)))

(defun gptel-auto-workflow--recover-orphans ()
  "Check for tracked commits that are not yet preserved by recovery refs.
An orphan is a tracked commit that exists, is not already integrated, and could
not be pinned under a private `refs/auto-workflow/kept/*' ref.
Returns list of (hash exp-id target) for truly unpreserved commits."
  (interactive)
  (let ((orphans nil)
        (pinned-count 0))
    (dolist (entry (gptel-auto-workflow--recoverable-tracked-commits))
      (let ((hash (car entry)))
        (cond
         ((gptel-auto-workflow--tracked-commit-pinned-p hash))
         ((gptel-auto-workflow--pin-tracked-commit hash)
          (cl-incf pinned-count))
         (t
          (push entry orphans)))))
    (when (> pinned-count 0)
      (message "[auto-workflow] Preserved %d tracked commit(s) under recovery refs"
               pinned-count))
    (if orphans
        (message "[auto-workflow] Found %d orphan(s): %s"
                 (length orphans)
                 (mapconcat (lambda (o)
                              (gptel-auto-workflow--truncate-hash (car o)))
                            orphans " "))
      (message "[auto-workflow] No orphan commits found"))
    (nreverse orphans)))


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

(provide 'gptel-tools-agent-base)
;;; gptel-tools-agent-base.el ends here
