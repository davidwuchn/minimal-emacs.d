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

;; Forward declaration for variable defined in gptel-auto-workflow-projects.el.
;; Do not initialize it here, or later `defvar' initializers in the projects
;; module will be skipped and leave the shared table bound to nil.
(defvar gptel-auto-workflow--project-buffers)
(defvar gptel-auto-workflow--worktree-buffers)
(defvar gptel-auto-workflow--current-project nil)
(defvar gptel-auto-workflow--run-project-root nil)
(defvar gptel-auto-workflow--project-root-override)
(defvar gptel--request-alist)
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
(defun gptel-auto-workflow--activate-live-root (proj-root)
  "Retarget the live daemon to PROJ-ROOT for queued workflow actions."
  (let ((root (file-name-as-directory (expand-file-name proj-root))))
    (setq default-directory root
          user-emacs-directory root
          gptel-auto-workflow--project-root-override root
          gptel-auto-workflow--current-project nil
          gptel-auto-workflow--run-project-root nil)
    (when (boundp 'minimal-emacs-user-directory)
      (setq minimal-emacs-user-directory root))
    (when (boundp 'gptel-auto-workflow-projects)
      (setq gptel-auto-workflow-projects (list root)))
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
  "Run identifier to expose in terminal workflow status snapshots.")

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
    (let ((refs (delete-dups
                 (delq nil
                       (list gptel-auto-workflow-staging-branch
                             (and (gptel-auto-workflow--non-empty-string-p
                                   gptel-auto-workflow-staging-branch)
                                  (format "origin/%s"
                                          gptel-auto-workflow-staging-branch))
                             "main"
                             "origin/main"))))
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
                (gptel-auto-workflow--with-skipped-submodule-sync
                 (lambda ()
                   (gptel-auto-workflow--git-cmd (format "git push origin %s" target-branch))))
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

(defun my/gptel--cacheable-subagent-result-p (result &optional agent-type)
  "Return non-nil when RESULT is safe to reuse from the subagent cache.
AGENT-TYPE can further restrict cacheability for agent-specific failures.
Failure-shaped responses must not be cached, otherwise transient transport
or reviewer-contract failures can poison later workflow attempts with
immediate cache hits."
  (or (not (stringp result))
      (and (not (string-match-p
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
  (when (and (my/gptel--subagent-cache-enabled-p)
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
Evicts oldest entries if cache exceeds `my/gptel-subagent-cache-max-size'."
  (when (and (my/gptel--subagent-cache-enabled-p)
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

(defvar gptel-auto-workflow--pending-subagent-process-environment nil
  "Isolated env prepared for the current subagent launch before buffer persistence.")

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
  (let ((tracked
         (delete-dups
          (list (gptel-auto-workflow--hash-get-bound 'gptel-auto-workflow--worktree-buffers root)
                (gptel-auto-workflow--hash-get-bound 'gptel-auto-workflow--project-buffers root)))))
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

(defconst my/gptel--agent-task-nonactivity-message-formats
  '("gptel: sanitizing nil :content on %s message"
     "gptel: sanitizing :null :content on %s message"
     "gptel: converting non-string :content on %s message: %S"
     "[LSP] Waiting for server... (%d retries left)"
     "[LSP] Connection error, retrying... (%d left)")
  "Message format strings that should not count as executor progress.")

(defun my/gptel--agent-task-note-message-activity (format-string &rest _args)
  "Treat worktree-context messages as executor activity unless they are noise."
  (unless (and (stringp format-string)
               (member format-string
                       my/gptel--agent-task-nonactivity-message-formats))
    (my/gptel--agent-task-note-context-activity)))

(unless (advice-member-p 'message #'my/gptel--agent-task-note-message-activity)
  (advice-add 'message :before #'my/gptel--agent-task-note-message-activity))

(defun my/gptel--agent-task-note-curl-activity (&rest _args)
  "Treat gptel curl request setup as active subagent progress."
  (my/gptel--agent-task-note-active-activity))

(with-eval-after-load 'gptel-request
  (unless (advice-member-p 'gptel-curl--get-args #'my/gptel--agent-task-note-curl-activity)
    (advice-add 'gptel-curl--get-args :before
                #'my/gptel--agent-task-note-curl-activity)))

(defun my/gptel--request-entry-fsm (process)
  "Return the request FSM associated with PROCESS, unwrapping local entry shapes."
  (when (bound-and-true-p gptel--request-alist)
    (let ((entry (alist-get process gptel--request-alist)))
      (or (and (fboundp 'my/gptel--coerce-fsm)
               (my/gptel--coerce-fsm entry))
          (car-safe entry)
          entry))))

(defun my/gptel--handle-deleted-process-buffer (process stage)
  "Clean up PROCESS after STAGE finds its process buffer already deleted."
  (let* ((fsm (my/gptel--request-entry-fsm process))
         (proc-info (and fsm (ignore-errors (gptel-fsm-info fsm)))))
    (when (listp proc-info)
      (plist-put proc-info :error
                 (format "Request buffer was deleted before %s completed." stage))
      (plist-put proc-info :status "Request buffer deleted")
      (with-demoted-errors "gptel callback error: %S"
        (when-let ((proc-callback (plist-get proc-info :callback)))
          (funcall proc-callback nil proc-info))))
    (when (bound-and-true-p gptel--request-alist)
      (setf (alist-get process gptel--request-alist nil 'remove) nil))
    (when (process-live-p process)
      (ignore-errors (delete-process process)))))

(defun my/gptel-curl--sentinel (orig-fun process status)
  "Around advice for `gptel-curl--sentinel' guarding deleted process buffers."
  (let ((proc-buf (ignore-errors (process-buffer process))))
    (if (buffer-live-p proc-buf)
        (funcall orig-fun process status)
      (my/gptel--handle-deleted-process-buffer process "curl sentinel"))))

(defun my/gptel-curl--stream-cleanup (orig-fun process status)
  "Around advice for `gptel-curl--stream-cleanup' guarding deleted buffers."
  (let ((proc-buf (ignore-errors (process-buffer process))))
    (if (buffer-live-p proc-buf)
        (funcall orig-fun process status)
      (my/gptel--handle-deleted-process-buffer process "curl stream cleanup"))))

(defun my/gptel--install-request-entry-fixes ()
  "Install local guards around gptel curl request cleanup."
  (when (featurep 'gptel-request)
    (unless (advice-member-p #'my/gptel-curl--sentinel 'gptel-curl--sentinel)
      (advice-add 'gptel-curl--sentinel :around #'my/gptel-curl--sentinel))
    (unless (advice-member-p #'my/gptel-curl--stream-cleanup 'gptel-curl--stream-cleanup)
      (advice-add 'gptel-curl--stream-cleanup :around #'my/gptel-curl--stream-cleanup))))

(with-eval-after-load 'gptel-request
  (my/gptel--install-request-entry-fixes))
(when (featurep 'gptel-request)
  (my/gptel--install-request-entry-fixes))

(defun my/gptel--register-agent-task-buffer (buffer)
  "Record BUFFER as the active request buffer for the current subagent task."
  (when (and my/gptel--current-agent-task-id
             (buffer-live-p buffer))
    (when-let* ((state (gethash my/gptel--current-agent-task-id
                                my/gptel--agent-task-state)))
      (let* ((current (plist-get state :request-buf))
             (current-priority (my/gptel--agent-task-buffer-priority state current))
             (new-priority (my/gptel--agent-task-buffer-priority state buffer))
             (updated-state
              (if (or (not (buffer-live-p current))
                      (eq current buffer)
                      (> new-priority current-priority))
                  (plist-put state :request-buf buffer)
                state)))
        (puthash my/gptel--current-agent-task-id
                 updated-state
                 my/gptel--agent-task-state)
        (when (and (not (plist-get updated-state :launching))
                   (not gptel-auto-workflow--defer-subagent-env-persistence)
                   (plist-get updated-state :process-environment)
                   (fboundp 'gptel-auto-workflow--persist-subagent-process-environment))
          (gptel-auto-workflow--persist-subagent-process-environment
           buffer
           (plist-get updated-state :process-environment))))))
  buffer)

(defun my/gptel--reset-agent-task-state ()
  "Abort and clear all tracked subagent task state."
  (when (hash-table-p my/gptel--agent-task-state)
    (let (request-buffers)
      (maphash
       (lambda (_task-id state)
         (when (plistp state)
           (my/gptel--cancel-agent-task-timers state)
           (when-let* ((request-buf (my/gptel--agent-task-request-buffer state)))
             (push request-buf request-buffers))))
       my/gptel--agent-task-state)
      (clrhash my/gptel--agent-task-state)
      (dolist (request-buf (delete-dups request-buffers))
        (when (and (buffer-live-p request-buf)
                   (fboundp 'gptel-abort))
          (condition-case err
              (gptel-abort request-buf)
            (error
             (let ((safe-msg (or (ignore-errors
                                   (my/gptel--sanitize-for-logging
                                    (error-message-string err) 160))
                                 "[unavailable]")))
               (when (buffer-live-p request-buf)
                 (message "[nucleus] Failed to abort stale subagent buffer %s: %s"
                          (buffer-name request-buf)
                          safe-msg))))))))))

(defun my/gptel--normalize-agent-activity-dir (dir)
  "Return DIR as a canonical directory path with trailing slash, or nil."
  (when (stringp dir)
    (file-name-as-directory (expand-file-name dir))))

(defun my/gptel--agent-task-overlaps-p (state origin-buf activity-dir)
  "Return non-nil when STATE overlaps a new dispatch from ORIGIN-BUF.

ACTIVITY-DIR should be the canonical workflow activity directory for the new
dispatch. Overlap is intentionally conservative during auto-workflow runs:
subagents for one routed experiment buffer/worktree should not survive into a
new analyzer/executor/grader launch on that same buffer or worktree."
  (and (gptel-auto-workflow--state-active-p state)
       (let* ((request-buf (my/gptel--agent-task-request-buffer state))
              (state-origin (plist-get state :origin-buf))
              (state-dir (my/gptel--normalize-agent-activity-dir
                          (plist-get state :activity-dir))))
         (or (and (buffer-live-p origin-buf)
                  (or (eq state-origin origin-buf)
                      (eq request-buf origin-buf)))
             (and activity-dir state-dir
                  (equal activity-dir state-dir))))))

(defun my/gptel--cleanup-overlapping-agent-tasks (origin-buf activity-dir)
  "Abort and clear tracked subagent tasks that overlap a new workflow dispatch.

This prevents stale timers/callbacks from older analyzer/executor work on the
same routed experiment buffer from re-entering a later retry."
  (let ((normalized-dir (my/gptel--normalize-agent-activity-dir activity-dir))
        overlap-ids
        request-buffers)
    (maphash
     (lambda (task-id state)
       (when (my/gptel--agent-task-overlaps-p state origin-buf normalized-dir)
         (my/gptel--cancel-agent-task-timers state)
         (when-let* ((request-buf (my/gptel--agent-task-request-buffer state)))
           (push request-buf request-buffers))
         (push task-id overlap-ids)))
     my/gptel--agent-task-state)
    (dolist (task-id overlap-ids)
      (remhash task-id my/gptel--agent-task-state))
     (dolist (request-buf (delete-dups request-buffers))
       (when (and (buffer-live-p request-buf)
                  (fboundp 'gptel-abort))
          (condition-case err
              (gptel-abort request-buf)
            (error
             (message "[nucleus] Failed to abort overlapping subagent buffer %s: %s"
                      (buffer-name request-buf)
                      (my/gptel--sanitize-for-logging
                       (error-message-string err) 160))))))
    (length overlap-ids)))

(defun my/gptel--call-gptel-agent-task (callback agent-type description prompt)
  "Invoke the active gptel subagent task runner.
In headless auto-workflow runs, bypass `gptel-agent-loop-task' to avoid
its async continuation layer in the worker daemon."
  (let* ((headless-auto-workflow
          (and (bound-and-true-p gptel-auto-workflow--headless)
               (bound-and-true-p gptel-auto-workflow-persistent-headless)
               (bound-and-true-p gptel-auto-workflow--current-project)))
         (isolated-env
          (and headless-auto-workflow
               (gptel-auto-workflow--isolated-state-environment
                "copilot-auto-workflow-subagent-"
                nil
                t)))
         (gptel-auto-workflow--defer-subagent-env-persistence
          (and isolated-env t))
         (gptel-auto-workflow--pending-subagent-process-environment isolated-env)
         (task-runner nil))
    (when (and isolated-env
               my/gptel--current-agent-task-id)
      (when-let* ((state (gethash my/gptel--current-agent-task-id
                                  my/gptel--agent-task-state)))
        (puthash my/gptel--current-agent-task-id
                 (plist-put state :process-environment
                            (copy-sequence isolated-env))
                 my/gptel--agent-task-state)))
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
    (let ((info (ignore-errors (gptel-fsm-info fsm))))
      (when (listp info)
        (setf (gptel-fsm-info fsm)
              (plist-put info :disable-auto-retry t)))
      t)))

(defun my/gptel--disable-auto-retry-transform (fsm)
  "Mark FSM as no-retry before request dispatch."
  (my/gptel--disable-auto-retry-for-fsm fsm))

(defun my/gptel--first-existing-directory (&rest dirs)
  "Return the first existing directory in DIRS, normalized with a trailing slash."
  (catch 'found
    (dolist (dir dirs)
      (when (and (stringp dir)
                 (file-directory-p dir))
        (throw 'found (file-name-as-directory (expand-file-name dir)))))
    nil))

(defun my/gptel--invoke-callback-safely (callback result)
  "Invoke CALLBACK with RESULT from a stable internal buffer.

This prevents `Selecting deleted buffer' errors when callback side effects
delete the request or file buffer that happened to be current when the
subagent callback fired, and avoids reusing a deleted worktree as
`default-directory'."
  (unless (functionp callback)
    (signal 'wrong-type-argument (list 'functionp callback)))
  (when (and result
             (or (consp result)
                 (listp result))
             (eq result (car result)))
    (signal 'wrong-type-argument (list '(not (eq result (car result))) result)))
  (let* ((caller-default-directory (or default-directory temporary-file-directory))
         (safe-buffer (get-buffer-create " *gptel-callback*"))
         (safe-default-directory
          (or (my/gptel--first-existing-directory
               caller-default-directory
               (and (buffer-live-p safe-buffer)
                    (condition-case err
                        (buffer-local-value 'default-directory safe-buffer)
                      (error nil)))
               user-emacs-directory
               temporary-file-directory)
              temporary-file-directory)))
    (with-current-buffer safe-buffer
      (setq default-directory safe-default-directory)
      (condition-case err
          (funcall callback result)
        (error
         (let ((err-data (cons callback (cons result (cdr err)))))
           (signal (car err) err-data)))))))

(defun my/gptel--agent-task-with-timeout (callback agent-type description prompt &optional files include-history include-diff)
  "Wrapper around `gptel-agent--task' that adds a timeout and progress messages.
CALLBACK is called with the result or a timeout error.
Uses hash table keyed by task-id to support parallel execution."
  (let* ((task-id (cl-incf my/gptel--agent-task-counter))
         (start-time (current-time))
         (task-timeout my/gptel-agent-task-timeout)
         (origin-buf (current-buffer))
         (activity-dir (and (stringp default-directory)
                            (expand-file-name default-directory)))
         (parent-fsm-local-p (local-variable-p 'gptel--fsm-last origin-buf))
         (parent-fsm (and parent-fsm-local-p
                          (buffer-local-value 'gptel--fsm-last origin-buf)))
         (child-fsm nil)
         (packaged-prompt
          (my/gptel--build-subagent-context
           prompt files include-history include-diff origin-buf))
         (uses-idle-timeout
          (my/gptel--agent-task-uses-idle-timeout-p agent-type))
         (hard-timeout
          (and uses-idle-timeout
               (integerp my/gptel-agent-task-hard-timeout)
               (> my/gptel-agent-task-hard-timeout 0)
               my/gptel-agent-task-hard-timeout))
         (hard-deadline
          (and hard-timeout
               (time-add start-time (seconds-to-time hard-timeout))))
         (overlap-count
          (and (bound-and-true-p gptel-auto-workflow--running)
               (my/gptel--cleanup-overlapping-agent-tasks
                origin-buf activity-dir)))
         (restore-origin-fsm
          (lambda (&optional expected-fsm)
            (when (buffer-live-p origin-buf)
              (let ((default-directory
                      (or (my/gptel--first-existing-directory
                           (and (buffer-live-p origin-buf)
                                (buffer-local-value 'default-directory origin-buf))
                           user-emacs-directory
                           temporary-file-directory)
                          temporary-file-directory)))
                (condition-case err
                    (with-current-buffer origin-buf
                      (when (or (null expected-fsm)
                                (eq gptel--fsm-last expected-fsm))
                        (if parent-fsm-local-p
                            (setq-local gptel--fsm-last parent-fsm)
                          (kill-local-variable 'gptel--fsm-last))))
                  (file-missing
                   (message "[nucleus] Skipping FSM restore for %s after origin directory vanished: %s"
                            agent-type
                            (error-message-string err))))))))
         (wrapped-cb
          (lambda (result)
            (let* ((state (gethash task-id my/gptel--agent-task-state)))
              (if (not state)
                  (message "[nucleus] Ignoring stale subagent %s callback after reset"
                           agent-type)
                (let ((already-done (plist-get state :done)))
                 ;; Atomic test-and-set: mark done before acting to prevent
                 ;; double-invocation if gptel-abort fires synchronously in timeout.
                 (puthash task-id (plist-put state :done t) my/gptel--agent-task-state)
                 (unless already-done
                   (my/gptel--cancel-agent-task-timers state)
                   (message "[nucleus] Subagent %s completed in %.1fs, result-len=%d"
                            agent-type (float-time (time-since start-time))
                            (if (stringp result) (length result) 0))
                   (funcall restore-origin-fsm child-fsm)
                   (unwind-protect
                       (my/gptel--invoke-callback-safely callback result)
                     (remhash task-id my/gptel--agent-task-state)))))))))
    (cl-labels
         ((finish-timeout (state timeout-seconds timeout-suffix
                                 &optional timeout-kind total-elapsed-seconds)
            (puthash task-id (plist-put state :done t)
                     my/gptel--agent-task-state)
            (my/gptel--cancel-agent-task-timers state)
            (if (eq timeout-kind :idle)
                (message "[nucleus] Subagent %s timed out after %ds idle timeout (%.1fs total runtime), aborting request"
                         agent-type timeout-seconds (or total-elapsed-seconds 0.0))
              (message "[nucleus] Subagent %s timed out after %ds%s, aborting request"
                       agent-type timeout-seconds timeout-suffix))
           (my/gptel--cleanup-agent-request-buffer state)
           (let ((timeout-result
                  (if (eq timeout-kind :idle)
                      (format "Error: Task \"%s\" (%s) timed out after %ds idle timeout (%.1fs total runtime)."
                              description agent-type timeout-seconds (or total-elapsed-seconds 0.0))
                    (format "Error: Task \"%s\" (%s) timed out after %ds%s."
                            description agent-type timeout-seconds timeout-suffix))))
              (funcall restore-origin-fsm child-fsm)
              (unwind-protect
                  (my/gptel--invoke-callback-safely callback timeout-result)
                (remhash task-id my/gptel--agent-task-state))))
         (rearm-timeout (state)
           (when task-timeout
             (when (timerp (plist-get state :timeout-timer))
               (cancel-timer (plist-get state :timeout-timer)))
             (let* ((remaining-hard-seconds
                     (and hard-deadline
                          (max 0
                               (ceiling
                                (float-time
                                 (time-subtract hard-deadline (current-time)))))))
                    (next-delay
                     (if remaining-hard-seconds
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
                                (idle-seconds
                                 (and last-activity
                                      (float-time (time-since last-activity))))
                                (remaining-hard
                                 (and hard-deadline
                                      (float-time
                                       (time-subtract hard-deadline (current-time)))))
                                (hard-expired (and remaining-hard
                                                   (<= remaining-hard 0)))
                                (total-elapsed
                                 (float-time (time-since start-time)))
                                (timeout-kind
                                 (cond
                                  (hard-expired :hard-runtime)
                                  ((and uses-idle-timeout
                                        idle-seconds
                                        (>= idle-seconds task-timeout))
                                   :idle)
                                  (t :timeout)))
                                (timeout-seconds
                                 (if (eq timeout-kind :hard-runtime)
                                     hard-timeout
                                   task-timeout))
                                (timeout-suffix
                                 (if (eq timeout-kind :hard-runtime)
                                     " total runtime"
                                   "")))
                           (when state
                             (cond
                              (already-done nil)
                              ((and uses-idle-timeout
                                    (not hard-expired)
                                    idle-seconds
                                    (< idle-seconds task-timeout))
                               (rearm-timeout state))
                              (t
                               (finish-timeout
                                state timeout-seconds timeout-suffix
                                timeout-kind total-elapsed)))))))))
                (puthash task-id state my/gptel--agent-task-state)))
            state)
         (note-buffer-activity (state)
           (when uses-idle-timeout
             (when-let* ((request-buf (my/gptel--agent-task-request-buffer state))
                         ((buffer-live-p request-buf)))
               (let* ((current-tick (my/gptel--agent-task-buffer-tick request-buf))
                      (last-tick (plist-get state :last-buffer-tick)))
                 (when (and current-tick (not (equal current-tick last-tick)))
                   (setq state (plist-put state :last-buffer-tick current-tick))
                   (setq state (plist-put state :last-activity-time (current-time)))
                   (setq state (rearm-timeout state))))))
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
      (when (and overlap-count (> overlap-count 0))
        (message "[nucleus] Cleared %d overlapping subagent task(s) before launching %s"
                 overlap-count agent-type))
      (let ((progress-timer
             (run-at-time
              my/gptel-subagent-progress-interval
              my/gptel-subagent-progress-interval
              (lambda ()
                (let ((state (gethash task-id my/gptel--agent-task-state)))
                  (when (gptel-auto-workflow--state-active-p state)
                    (setq state (note-buffer-activity state))
                    (let* ((elapsed (float-time (time-since start-time)))
                           (remaining-hard
                            (and hard-deadline
                                 (float-time
                                  (time-subtract hard-deadline (current-time)))))
                           (hard-expired (and remaining-hard
                                              (<= remaining-hard 0))))
                       (if (and task-timeout
                                (or hard-expired
                                    (and (not uses-idle-timeout)
                                         (>= elapsed task-timeout))))
                           (finish-timeout
                            state
                            (if hard-expired hard-timeout task-timeout)
                            (if hard-expired " total runtime" "")
                            (if hard-expired :hard-runtime :timeout)
                            elapsed)
                         (when (or (bound-and-true-p gptel-auto-workflow--running)
                                   (bound-and-true-p gptel-auto-workflow--cron-job-running))
                           (gptel-auto-workflow--update-progress)
                           (gptel-auto-workflow--persist-status))
                         (message "[nucleus] Subagent %s still running... (%.1fs elapsed)"
                                 agent-type elapsed)))))))))
        (puthash task-id (list :done nil
                               :timeout-timer nil
                               :progress-timer progress-timer
                               :origin-buf origin-buf
                               :request-buf nil
                               :launching t
                               :process-environment nil
                               :last-buffer-tick nil
                               :last-activity-time (current-time)
                               :agent-type agent-type
                               :activity-dir activity-dir)
                   my/gptel--agent-task-state)
        (when task-timeout
          (let ((state (gethash task-id my/gptel--agent-task-state)))
            (rearm-timeout state)))
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
                      (when-let* ((state (gethash task-id my/gptel--agent-task-state)))
                        (setq state (plist-put state :launching nil))
                        (puthash task-id state my/gptel--agent-task-state)
                        (let ((request-buf (my/gptel--agent-task-request-buffer state)))
                          (when (buffer-live-p request-buf)
                           (when-let* ((task-env (plist-get state :process-environment))
                                       ((fboundp 'gptel-auto-workflow--persist-subagent-process-environment)))
                             (gptel-auto-workflow--persist-subagent-process-environment
                              request-buf task-env))
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
                                         my/gptel--agent-task-state)))))))
                  (error
                   (setq launch-error err)))
              (unless request-started
                 (funcall restore-origin-fsm)))
             (when launch-error
               (let ((state (gethash task-id my/gptel--agent-task-state)))
                 (when state
                   (my/gptel--cancel-agent-task-timers state)
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

(defcustom gptel-auto-experiment-active-grace 420
  "Extra wall-clock seconds active executor experiments may use beyond budget.

Executor requests still use `gptel-auto-experiment-time-budget' as their idle
timeout, but active runs may exceed it by this grace period before they are
forcibly aborted.  The default keeps the wrapper hard cap above 900s backend
request limits so active calls do not race provider-side timeouts."
  :type 'integer
  :safe #'integerp
  :group 'gptel-tools-agent)

(defcustom gptel-auto-experiment-validation-retry-time-budget 240
  "Timeout budget in seconds for validation-retry executor calls.

Validation retries should repair one known error in the current worktree, so
they use a shorter budget than full experiments while still allowing enough
time to apply and verify a focused fix."
  :type 'integer
  :safe #'integerp
  :group 'gptel-tools-agent)

(defcustom gptel-auto-experiment-validation-retry-active-grace 360
  "Extra wall-clock seconds active validation-retry calls may use beyond budget.

This leaves focused repair retries below full-experiment limits while giving
large-file fixes enough active headroom to finish after they have already
started producing edits."
  :type 'integer
  :safe #'integerp
  :group 'gptel-tools-agent)

(defconst gptel-auto-workflow--legacy-validation-retry-active-grace 120
  "Previous default for `gptel-auto-experiment-validation-retry-active-grace'.")

(defconst gptel-auto-workflow--current-validation-retry-active-grace 360
  "Current runtime default for `gptel-auto-experiment-validation-retry-active-grace'.")

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

(defcustom gptel-auto-workflow-review-file-context-max-bytes 50000
  "Maximum size in bytes for one changed file attached to reviewer context.

Oversized files are omitted from `gptel-benchmark--subagent-files` and the
reviewer must inspect them via tools when needed."
  :type 'integer
  :safe #'integerp
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-review-file-context-max-total-bytes 120000
  "Maximum cumulative size in bytes for reviewer-attached changed files."
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

(defcustom gptel-auto-experiment-min-quality-gain-on-score-tie 0.10
  "Minimum code-quality gain required to keep a tied benchmark score.

Tied Eight Keys scores should only be kept when code quality improves by at
least this amount and the combined score still improves."
  :type 'number
  :safe #'numberp
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
(defvar gptel-auto-workflow--staging-push-max-retries 2
  "Maximum refresh-and-retry attempts after shared staging advances mid-run.
Counts retry publishes after the initial failed push. 0 disables replay.")

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

(defun gptel-auto-workflow--run-branch-token ()
  "Return a short run token for unique optimize branch names.
Uses the trailing time/hash portion of `gptel-auto-workflow--run-id' when available."
  (let ((run-id (and (stringp gptel-auto-workflow--run-id)
                     (downcase gptel-auto-workflow--run-id))))
    (when (and run-id
               (string-match "\\([0-9]\\{6\\}z\\)-\\([a-z0-9]+\\)\\'" run-id))
      (format "r%s%s"
              (match-string 1 run-id)
              (match-string 2 run-id)))))

(defun gptel-auto-workflow--branch-name (target &optional experiment-id)
  "Generate branch name for TARGET with machine hostname.
Format: optimize/{target}-{hostname}[-r{run}]-exp{N}
Base branch is always 'main'.
Multiple machines can optimize same target without conflicts."
  (let* ((basename (file-name-sans-extension (file-name-nondirectory target)))
         (name (car (last (split-string basename "-"))))
         (host (system-name))
         (run-token (and experiment-id
                         (gptel-auto-workflow--run-branch-token))))
    (if experiment-id
        (if run-token
            (format "optimize/%s-%s-%s-exp%d" name host run-token experiment-id)
          (format "optimize/%s-%s-exp%d" name host experiment-id))
      (format "optimize/%s-%s" name host))))

(defun gptel-auto-workflow--branch-worktree-paths (branch &optional proj-root)
  "Return attached worktree paths for BRANCH within PROJ-ROOT.
BRANCH should be the short local branch name, e.g. optimize/foo-exp1."
  (let ((default-directory (or proj-root (gptel-auto-workflow--default-dir)))
        (buffer (generate-new-buffer " *git-worktree-list*"))
        (paths nil)
        (branch-ref (format "refs/heads/%s" branch)))
    (unwind-protect
        (when (= 0 (call-process "git" nil buffer nil "worktree" "list" "--porcelain"))
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
         (suffix (gptel-auto-workflow--experiment-suffix))
         (branch-pattern
          (format "\\`optimize/.+-%s\\(?:-r[[:alnum:]]+\\)?-exp[0-9]+\\'"
                  (regexp-quote suffix))))
    (unwind-protect
        (when (= 0 (call-process "git" nil buffer nil "worktree" "list" "--porcelain"))
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

(defun gptel-auto-workflow--optimize-branches (&optional proj-root)
  "Return local optimize branches for the current host within PROJ-ROOT."
  (let* ((default-directory (or proj-root (gptel-auto-workflow--default-dir)))
         (buffer (generate-new-buffer " *git-optimize-branches*"))
         (entries nil)
         (suffix (gptel-auto-workflow--experiment-suffix))
         (branch-pattern
          (format "\\`optimize/.+-%s\\(?:-r[[:alnum:]]+\\)?-exp[0-9]+\\'"
                  (regexp-quote suffix))))
    (unwind-protect
        (when (= 0 (call-process "git" nil buffer nil
                                 "for-each-ref"
                                 "--format=%(refname:short)"
                                 "refs/heads/optimize"))
          (with-current-buffer buffer
            (dolist (branch (split-string (buffer-string) "\n" t))
              (when (string-match-p branch-pattern branch)
                (push branch entries)))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))
    (nreverse entries)))

(defun gptel-auto-workflow--remote-tracking-optimize-branches (&optional proj-root)
  "Return local `origin/optimize/*' tracking refs within PROJ-ROOT."
  (let ((default-directory (or proj-root (gptel-auto-workflow--default-dir))))
    (if (not (file-directory-p default-directory))
        nil
      (let ((result
             (gptel-auto-workflow--git-result
              "git for-each-ref --format=%(refname:short) refs/remotes/origin/optimize"
              60)))
        (when (= 0 (cdr result))
          (split-string (string-trim-right (or (car result) "")) "\n" t))))))

(defun gptel-auto-workflow--remote-optimize-branches (&optional proj-root)
  "Return remote optimize branches within PROJ-ROOT.

Each entry is a plist with `:branch' and `:head'. SSH noise is ignored."
  (let ((default-directory (or proj-root (gptel-auto-workflow--default-dir)))
        (entries nil))
    (if (not (file-directory-p default-directory))
        nil
      (let ((result
             (gptel-auto-workflow--git-result
              (format "git ls-remote --heads origin %s"
                      (shell-quote-argument "refs/heads/optimize/*"))
              180)))
        (when (= 0 (cdr result))
          (dolist (line (split-string (or (car result) "") "\n" t))
            (when (string-match
                   "^\\([0-9a-f]\\{40\\}\\)\trefs/heads/\\(optimize/.+\\)$"
                   line)
              (push (list :branch (match-string 2 line)
                          :head (match-string 1 line))
                    entries))))
        (nreverse entries)))))

(defun gptel-auto-workflow--discard-worktree-buffers (worktree-dir)
  "Abort, kill, and unregister live gptel buffers rooted at WORKTREE-DIR."
  (when (and (stringp worktree-dir)
             (> (length worktree-dir) 0))
    (let* ((root (file-name-as-directory (expand-file-name worktree-dir)))
           (tracked
            (delete-dups
             (list (gptel-auto-workflow--hash-get-bound 'gptel-auto-workflow--worktree-buffers root)
                   (gptel-auto-workflow--hash-get-bound 'gptel-auto-workflow--project-buffers root))))
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
                       exit-code (or stderr-preview "no output")))
              (when (gptel-auto-workflow--worktree-needs-submodule-hydration-p worktree-dir)
                (unless (gptel-auto-workflow--ensure-staging-submodules-ready worktree-dir)
                  (error "failed to hydrate experiment submodules in %s" worktree-dir))))
          (kill-buffer stderr-buffer)
          (message "[auto-workflow] Created: %s" branch)
          (puthash target (list :worktree-dir worktree-dir :current-branch branch)
                   gptel-auto-workflow--worktree-state)
          worktree-dir))
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
  (let* ((state (or (gethash target gptel-auto-workflow--worktree-state)
                    (list)))
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

(defun gptel-auto-workflow--configured-staging-branch ()
  "Return the configured staging branch when it is a non-empty string."
  (let ((branch gptel-auto-workflow-staging-branch))
    (and (gptel-auto-workflow--non-empty-string-p branch)
         branch)))

(defun gptel-auto-workflow--require-staging-branch ()
  "Return the configured staging branch, logging when it is invalid."
  (or (gptel-auto-workflow--configured-staging-branch)
      (message "[auto-workflow] Missing staging branch configuration")
      nil))

(defun gptel-auto-workflow--staging-branch-exists-p ()
  "Check if staging branch exists locally or remotely."
  (let ((branch (gptel-auto-workflow--configured-staging-branch)))
    (and branch
         (or (member branch (magit-list-local-branch-names))
             (member (concat "origin/" branch)
                     (magit-list-remote-branch-names))))))

(defun gptel-auto-workflow--autonomous-maintenance-commit-subject-p (subject)
  "Return non-nil when SUBJECT is an autonomous maintenance commit."
  (and (stringp subject)
       (or (string-match-p "\\`💡 synthesis: .+ (AI-generated)\\'" subject)
           (string-match-p
            "\\`instincts evolution: weekly batch update"
            subject))))

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
                                    (string-to-number (nth 1 ahead-counts))))
                  (ahead-only-main (and clean-main
                                        (numberp behind-count)
                                        (numberp ahead-count)
                                        (= behind-count 0)
                                        (> ahead-count 0)))
                  (subject-result (and ahead-only-main
                                       (gptel-auto-workflow--git-result
                                        "git log --format=%s origin/main..main"
                                        60)))
                  (ahead-subjects (and subject-result
                                       (= 0 (cdr subject-result))
                                       (split-string (string-trim-right (car subject-result))
                                                     "\n"
                                                     t))))
             (if ahead-only-main
                 (if (and (consp ahead-subjects)
                          (cl-every
                           #'gptel-auto-workflow--autonomous-maintenance-commit-subject-p
                           ahead-subjects))
                     (progn
                       (message "[auto-workflow] Local main only contains autonomous maintenance commits; using origin/main as workflow base")
                       "origin/main")
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

(defun gptel-auto-workflow--staging-sync-ref ()
  "Return the ref staging should sync from at workflow start.
Prefer `origin/staging' when it exists so concurrent hosts append to the
shared integration branch instead of rebuilding it from `main'. Callers may
still need to refresh that base with `gptel-auto-workflow--staging-main-ref'
when remote staging lags behind the selected main ref. Fall back to
`gptel-auto-workflow--staging-main-ref' only when the remote staging branch is
absent."
  (let* ((proj-root (gptel-auto-workflow--project-root))
         (default-directory proj-root)
         (staging (gptel-auto-workflow--require-staging-branch)))
    (when staging
      (let* ((staging-q (shell-quote-argument staging))
             (remote-staging (format "refs/remotes/origin/%s" staging))
             (remote-staging-refspec
              (format "+refs/heads/%s:%s" staging remote-staging))
             (remote-probe
              (gptel-auto-workflow--git-result
               (format "git ls-remote --exit-code --heads origin %s" staging-q)
               60)))
        (cond
         ((= 0 (cdr remote-probe))
          (let ((fetch-result
                 (gptel-auto-workflow--git-result
                  (format "git fetch origin %s"
                          (shell-quote-argument remote-staging-refspec))
                  180)))
            (if (= 0 (cdr fetch-result))
                remote-staging
              (message "[auto-workflow] Failed to fetch origin/%s for staging sync: %s"
                       staging
                       (my/gptel--sanitize-for-logging (car fetch-result) 160))
              nil)))
         ((= 2 (cdr remote-probe))
          (gptel-auto-workflow--staging-main-ref))
         (t
          (message "[auto-workflow] Failed to probe origin/%s for staging sync: %s"
                   staging
                   (my/gptel--sanitize-for-logging (car remote-probe) 160))
          nil))))))

(defun gptel-auto-workflow--ref-ancestor-p (ancestor descendant)
  "Return non-nil when ANCESTOR is already contained in DESCENDANT."
  (and (gptel-auto-workflow--non-empty-string-p ancestor)
       (gptel-auto-workflow--non-empty-string-p descendant)
       (= 0
          (cdr (gptel-auto-workflow--git-result
                (format "git merge-base --is-ancestor %s %s"
                        (shell-quote-argument ancestor)
                        (shell-quote-argument descendant))
                60)))))

(defun gptel-auto-workflow--refresh-staging-base-with-main (main-ref)
  "Bring the current staging worktree up to MAIN-REF without dropping staging commits.
Do not require the pre-merge staging checkout to hydrate cleanly: MAIN-REF may
be the source of truth that repairs stale submodule gitlinks from origin/staging."
  (let ((worktree default-directory))
    (let* ((main-q (shell-quote-argument main-ref))
           (ff-result
            (gptel-auto-workflow--git-result
             (format "git merge --ff-only %s" main-q)
             180))
           (ff-output (car ff-result)))
       (cond
       ((= 0 (cdr ff-result))
        (gptel-auto-workflow--finalize-refreshed-staging-submodules worktree main-ref))
       ((string-match-p "Already up[ -]to[- ]date" ff-output)
        (gptel-auto-workflow--finalize-refreshed-staging-submodules worktree main-ref))
       (t
        (let* ((merge-result
                (gptel-auto-workflow--git-result
                 (format "git merge -X theirs %s --no-ff -m %s"
                         main-q
                         (shell-quote-argument
                          (format "Sync staging with %s" main-ref)))
                 180))
               (merge-output (car merge-result)))
          (cond
           ((= 0 (cdr merge-result))
            (gptel-auto-workflow--finalize-refreshed-staging-submodules worktree main-ref))
           ((string-match-p "Already up[ -]to[- ]date" merge-output)
            (gptel-auto-workflow--finalize-refreshed-staging-submodules worktree main-ref))
           ((gptel-auto-workflow--resolve-ancestor-submodule-merge-conflicts worktree)
            (if (not (gptel-auto-workflow--ensure-staging-submodules-ready worktree))
                (progn
                  (ignore-errors
                    (gptel-auto-workflow--git-cmd "git merge --abort" 60))
                  nil)
              (let ((commit-result
                     (gptel-auto-workflow--git-result
                      (format "%s git commit --no-edit"
                              gptel-auto-workflow--skip-submodule-sync-env)
                      180)))
                (if (= 0 (cdr commit-result))
                    t
                  (ignore-errors
                    (gptel-auto-workflow--git-cmd "git merge --abort" 60))
                  (message "[auto-workflow] Failed to finalize staging refresh with %s: %s"
                           main-ref
                           (my/gptel--sanitize-for-logging (car commit-result) 160))
                  nil))))
           (t
            (ignore-errors
              (gptel-auto-workflow--git-cmd "git merge --abort" 60))
            (message "[auto-workflow] Failed to refresh staging with %s: %s"
                     main-ref
                     (my/gptel--sanitize-for-logging merge-output 160))
            nil))))))))


(defun gptel-auto-workflow--sync-staging-from-main ()
  "Sync staging from current upstream state at workflow start.
Prefer `origin/staging' when available so shared staging keeps remote results.
Otherwise reset staging to the selected main ref. When remote staging exists
but lags behind the selected main ref, merge the selected main ref into the
local staging base before verification. Never checks out staging in the root
repo."
  (let* ((proj-root (gptel-auto-workflow--project-root))
         (default-directory proj-root)
         (main-ref nil)
         (sync-ref nil))
    (message "[auto-workflow] Syncing staging")
    (cond
     ((not (gptel-auto-workflow--ensure-staging-branch-exists))
      nil)
     ((progn
        (setq sync-ref (gptel-auto-workflow--staging-sync-ref))
        (setq main-ref (gptel-auto-workflow--staging-main-ref))
        (not sync-ref))
      nil)
     (t
      (let ((worktree (gptel-auto-workflow--create-staging-worktree)))
        (if (not worktree)
            nil
          (let* ((staging (gptel-auto-workflow--configured-staging-branch))
                 (remote-staging (format "refs/remotes/origin/%s" staging))
                 (default-directory worktree))
            (let* ((results (list
                             (gptel-auto-workflow--git-result
                              (format "git checkout %s" (shell-quote-argument staging))
                              60)
                             (gptel-auto-workflow--git-result
                              (format "git reset --hard %s"
                                      (shell-quote-argument sync-ref))
                              180)))
                   (failed (cl-find-if (lambda (item) (/= 0 (cdr item))) results)))
              (cond
               (failed
                (message "[auto-workflow] Failed to sync staging: %s"
                         (my/gptel--sanitize-for-logging (car failed) 160))
                nil)
               ((and (equal sync-ref remote-staging)
                     (gptel-auto-workflow--non-empty-string-p main-ref)
                     (not (gptel-auto-workflow--ref-ancestor-p main-ref sync-ref)))
                (when (gptel-auto-workflow--refresh-staging-base-with-main main-ref)
                  (message "[auto-workflow] ✓ Staging synced from %s plus %s"
                           sync-ref main-ref)
                  t))
               ((and (equal sync-ref remote-staging)
                     (gptel-auto-workflow--non-empty-string-p main-ref))
                (when (gptel-auto-workflow--finalize-refreshed-staging-submodules worktree main-ref)
                  (message "[auto-workflow] ✓ Staging synced from %s" sync-ref)
                  t))
               (t
                (message "[auto-workflow] ✓ Staging synced from %s" sync-ref)
                t))))))))))



(defun gptel-auto-workflow--create-staging-worktree ()
  "Create isolated worktree for staging verification.
Never touches project root - all verification happens in the worktree.
Returns worktree path or nil on failure."
  (let* ((proj-root (gptel-auto-workflow--worktree-base-root))
         (default-directory proj-root)
         (worktree-base-dir (or gptel-auto-workflow-worktree-base
                                 "var/tmp/experiments"))
         (worktree-dir (expand-file-name
                        (format "%s/staging-verify" worktree-base-dir)
                        proj-root))
         (worktree-q (shell-quote-argument worktree-dir)))
    (gptel-auto-workflow--with-error-handling
     "create staging worktree"
     (lambda ()
       (when (gptel-auto-workflow--ensure-staging-branch-exists)
         (let* ((branch (gptel-auto-workflow--configured-staging-branch))
                (branch-q (shell-quote-argument branch)))
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
           worktree-dir))))))



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

(defun gptel-auto-workflow--worktree-needs-submodule-hydration-p (&optional worktree)
  "Return non-nil when WORKTREE declares missing or empty top-level submodules."
  (let ((root (or worktree gptel-auto-workflow--staging-worktree-dir)))
    (and (stringp root)
         (file-directory-p root)
         (cl-some
          (lambda (path)
            (let ((target (expand-file-name path root)))
              (or (not (file-directory-p target))
                  (null (directory-files target nil directory-files-no-dot-files-regexp t)))))
          (gptel-auto-workflow--staging-submodule-paths root)))))

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

(defun gptel-auto-workflow--staging-submodule-gitlink-revision-at-ref (worktree ref path)
  "Return the gitlink revision for PATH at REF in WORKTREE, or nil."
  (let* ((default-directory worktree)
         (result (gptel-auto-workflow--git-result
                  (format "git ls-tree %s -- %s"
                          (shell-quote-argument ref)
                          (shell-quote-argument path))
                  60))
         (output (car result)))
    (when (and (= 0 (cdr result))
               (string-match "160000 commit \\([0-9a-f]\\{40\\}\\)\t" output))
      (match-string 1 output))))

(defun gptel-auto-workflow--worktree-base-repo-root ()
  "Return the canonical superproject root for the stable workflow root."
  (let* ((git-common-dir (gptel-auto-workflow--worktree-base-git-common-dir))
         (repo-root (and git-common-dir
                         (string-match "\\(.+/\\.git\\)\\(?:/worktrees/[^/]+\\)?\\'"
                                       (directory-file-name git-common-dir))
                         (file-name-directory (match-string 1
                                                            (directory-file-name git-common-dir))))))
    (or repo-root
        (gptel-auto-workflow--worktree-base-root))))

(defun gptel-auto-workflow--checkout-git-common-dir-from-marker (checkout)
  "Return CHECKOUT's git-common-dir by reading its `.git' marker directly."
  (when (stringp checkout)
    (let ((git-marker (expand-file-name ".git" checkout)))
      (cond
       ((file-directory-p git-marker)
        git-marker)
       ((file-regular-p git-marker)
        (let ((git-dir
               (with-temp-buffer
                 (insert-file-contents git-marker)
                 (goto-char (point-min))
                 (when (re-search-forward "^gitdir: \\(.+\\)$" nil t)
                   (expand-file-name (string-trim (match-string 1)) checkout)))))
          (when git-dir
            (let ((commondir-file (expand-file-name "commondir" git-dir)))
              (if (file-regular-p commondir-file)
                  (with-temp-buffer
                    (insert-file-contents commondir-file)
                    (expand-file-name (string-trim (buffer-string)) git-dir))
                git-dir)))))
       (t nil)))))

(defun gptel-auto-workflow--submodule-checkout-git-dir-at-root (root path)
  "Return the absolute git-common-dir for submodule PATH checked out under ROOT."
  (let ((checkout (and root (expand-file-name path root))))
    (when (file-directory-p checkout)
      (or (gptel-auto-workflow--checkout-git-common-dir-from-marker checkout)
          (let* ((git-common-result
                  (gptel-auto-workflow--git-result
                   (format "git -C %s rev-parse --git-common-dir"
                           (shell-quote-argument checkout))
                   60))
                 (git-common (string-trim (car git-common-result))))
            (when (and (= 0 (cdr git-common-result))
                       (not (string-empty-p git-common)))
              (expand-file-name git-common checkout)))))))

(defun gptel-auto-workflow--submodule-checkout-git-dirs (path)
  "Return candidate checked-out git dirs for submodule PATH.

Search both the stable workflow worktree root and the canonical main checkout
root, since one may have a fresher submodule checkout than the other."
  (let* ((roots (cl-remove-duplicates
                 (delq nil
                       (list (gptel-auto-workflow--worktree-base-root)
                             (gptel-auto-workflow--worktree-base-repo-root)))
                 :test #'string=))
          (git-dirs
           (mapcar (lambda (root)
                     (gptel-auto-workflow--submodule-checkout-git-dir-at-root root path))
                   roots)))
    (cl-remove-duplicates (delq nil git-dirs) :test #'string=)))

(defun gptel-auto-workflow--normalize-shared-submodule-core-worktree (path git-dir)
  "Re-anchor shared submodule GIT-DIR for PATH to the canonical checkout."
  (let* ((repo-root (or (gptel-auto-workflow--worktree-base-repo-root)
                        (gptel-auto-workflow--worktree-base-root)))
         (checkout (and repo-root (expand-file-name path repo-root)))
         (canonical-git-dir
          (and (stringp checkout)
               (file-directory-p checkout)
               (gptel-auto-workflow--checkout-git-common-dir-from-marker checkout))))
    (when (and (stringp git-dir)
               (file-directory-p git-dir)
               (stringp checkout)
               (file-directory-p checkout)
               (stringp canonical-git-dir)
               (file-directory-p canonical-git-dir)
               (string=
                (directory-file-name (expand-file-name git-dir))
                (directory-file-name (expand-file-name canonical-git-dir))))
      (pcase-let ((`(,output . ,exit-code)
                   (gptel-auto-workflow--git-result
                    (format "git config --file %s core.worktree %s"
                            (shell-quote-argument (expand-file-name "config" git-dir))
                            (shell-quote-argument (directory-file-name checkout)))
                    60)))
        (unless (= exit-code 0)
          (message "[auto-workflow] Failed to normalize shared submodule worktree for %s: %s"
                   path
                   (my/gptel--sanitize-for-logging output 200)))))
    git-dir))

(defun gptel-auto-workflow--worktree-base-git-common-dir ()
  "Return the git-common-dir for the stable workflow root."
  (let* ((proj-root (gptel-auto-workflow--worktree-base-root))
         (git-common-result
          (and proj-root
               (gptel-auto-workflow--git-result
                (format "git -C %s rev-parse --git-common-dir"
                        (shell-quote-argument proj-root))
                60)))
         (git-common (and git-common-result
                          (string-trim (car git-common-result)))))
    (when (and git-common-result
               (= 0 (cdr git-common-result))
               (not (string-empty-p git-common)))
      (expand-file-name git-common proj-root))))

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
  (let* ((checkout-git-dirs (gptel-auto-workflow--submodule-checkout-git-dirs path))
         (repo-git-dir (gptel-auto-workflow--worktree-base-git-common-dir))
         (module-git-dir (and repo-git-dir
                              (expand-file-name (format "modules/%s" path) repo-git-dir)))
          (candidates (cl-remove-duplicates
                       (append checkout-git-dirs (delq nil (list module-git-dir)))
                       :test #'string=)))
    (cl-find-if (lambda (git-dir)
                  (gptel-auto-workflow--git-dir-has-commit-p
                   (gptel-auto-workflow--normalize-shared-submodule-core-worktree
                    path git-dir)
                   commit))
                candidates)))

(defun gptel-auto-workflow--finalize-refreshed-staging-submodules (worktree main-ref)
  "Ensure refreshed staging WORKTREE uses materializable top-level submodule gitlinks.
If refreshed staging cannot hydrate a top-level submodule gitlink locally, try to
repair just that gitlink from MAIN-REF, then rehydrate and commit the repair."
  (let* ((default-directory worktree)
         (starting-head (string-trim
                         (gptel-auto-workflow--git-cmd "git rev-parse HEAD" 60)))
         (hydrate-result (gptel-auto-workflow--hydrate-staging-submodules worktree)))
    (if (= 0 (cdr hydrate-result))
        t
      (let ((repaired nil)
            (failure nil))
        (dolist (path (gptel-auto-workflow--staging-submodule-paths worktree))
          (unless failure
            (let* ((current-commit
                    (gptel-auto-workflow--staging-submodule-gitlink-revision worktree path))
                   (current-git-dir
                    (and current-commit
                         (gptel-auto-workflow--shared-submodule-git-dir path current-commit))))
              (when (and current-commit (not current-git-dir))
                (let* ((main-commit
                        (and (gptel-auto-workflow--non-empty-string-p main-ref)
                             (gptel-auto-workflow--staging-submodule-gitlink-revision-at-ref
                              worktree main-ref path)))
                       (main-git-dir
                        (and main-commit
                             (gptel-auto-workflow--shared-submodule-git-dir path main-commit))))
                  (cond
                   ((and main-commit
                         main-git-dir
                         (not (equal current-commit main-commit)))
                    (pcase-let ((`(,output . ,exit-code)
                                 (gptel-auto-workflow--git-result
                                  (format "git update-index --cacheinfo 160000 %s %s"
                                          (shell-quote-argument main-commit)
                                          (shell-quote-argument path))
                                  60)))
                      (if (= exit-code 0)
                          (push (format "%s=%s"
                                        path
                                        (gptel-auto-workflow--truncate-hash main-commit))
                                repaired)
                        (setq failure
                              (format "Failed to repair %s from %s: %s"
                                      path
                                      main-ref
                                      output)))))
                   (t
                    (setq failure
                          (format "Missing materializable fallback for %s (current=%s, main=%s)"
                                  path
                                  (or current-commit "nil")
                                  (or main-commit "nil"))))))))))
        (cond
         (failure
          (ignore-errors
            (let ((default-directory worktree))
              (gptel-auto-workflow--git-cmd "git reset --hard HEAD" 60)))
          (message "[auto-workflow] Failed to repair refreshed staging submodules from %s: %s"
                   main-ref
                   (my/gptel--sanitize-for-logging failure 200))
          nil)
         ((null repaired)
          (message "[auto-workflow] Failed to hydrate refreshed staging submodules: %s"
                   (my/gptel--sanitize-for-logging (car hydrate-result) 200))
          nil)
         (t
          (let* ((repair-message
                  (format "Repair staging submodule gitlinks from %s" main-ref))
                 (commit-command
                  (format "%s git commit -m %s"
                          gptel-auto-workflow--skip-submodule-sync-env
                          (shell-quote-argument repair-message))))
            (if (not (gptel-auto-workflow--commit-step-success-p
                      commit-command
                      "Repair staging submodule gitlinks"
                      180))
                (progn
                  (ignore-errors
                    (gptel-auto-workflow--git-cmd "git reset --hard HEAD" 60))
                  nil)
              (setq hydrate-result
                    (gptel-auto-workflow--hydrate-staging-submodules worktree))
              (if (/= 0 (cdr hydrate-result))
                  (progn
                    (ignore-errors
                      (gptel-auto-workflow--git-cmd
                       (format "git reset --hard %s"
                               (shell-quote-argument starting-head))
                       60))
                    (message "[auto-workflow] Failed to hydrate repaired staging submodules from %s: %s"
                             main-ref
                             (my/gptel--sanitize-for-logging (car hydrate-result) 200))
                    nil)
                (message "[auto-workflow] Repaired stale staging submodule gitlinks from %s: %s"
                         main-ref
                         (mapconcat #'identity (nreverse repaired) ", "))
                t)))))))))

(defun gptel-auto-workflow--cleanup-staging-submodule-worktree (worktree path)
  "Remove any staged submodule worktree for PATH under WORKTREE.
Return nil on success, or an error string if the stale path could not be removed."
  (let* ((shared-git-dir (gptel-auto-workflow--shared-submodule-git-dir path))
         (target (expand-file-name path worktree)))
    (when (file-directory-p shared-git-dir)
      (gptel-auto-workflow--normalize-shared-submodule-core-worktree path shared-git-dir)
      (unwind-protect
          (progn
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
        (gptel-auto-workflow--normalize-shared-submodule-core-worktree path shared-git-dir)))
    (let ((delete-by-moving-to-trash nil))
      (cond
       ((file-symlink-p target)
        (ignore-errors (delete-file target)))
       ((file-directory-p target)
        (ignore-errors (delete-directory target t)))
       ((file-exists-p target)
        (ignore-errors (delete-file target)))))
    (when (file-exists-p target)
      (format "Failed to remove stale submodule path %s" path))))

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
                                (gptel-auto-workflow--call-process-with-watchdog
                                 "bash" nil buffer nil test-script "unit")
                              0))
                      (setq verify-exit-code
                            (if (file-exists-p verify-script)
                                (let ((process-environment
                                       (cons "VERIFY_NUCLEUS_SKIP_SUBMODULE_SYNC=1"
                                             process-environment)))
                                  (gptel-auto-workflow--call-process-with-watchdog
                                   "bash" nil buffer nil verify-script))
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
             ((not (and shared-git-dir
                        (file-directory-p shared-git-dir)))
              (setq failure
                    (format "Missing shared submodule repo for %s: %s"
                            path shared-git-dir)))
              (t
                (let ((cleanup-error
                       (gptel-auto-workflow--cleanup-staging-submodule-worktree root path)))
                  (if cleanup-error
                      (setq failure cleanup-error)
                    (make-directory (file-name-directory target) t)
                    (gptel-auto-workflow--normalize-shared-submodule-core-worktree
                     path shared-git-dir)
                    (setq add-result
                          (unwind-protect
                              (gptel-auto-workflow--git-result
                               (format "git --git-dir=%s worktree add --detach --force %s %s"
                                       (shell-quote-argument shared-git-dir)
                                       (shell-quote-argument target)
                                       (shell-quote-argument commit))
                               180)
                            (gptel-auto-workflow--normalize-shared-submodule-core-worktree
                             path shared-git-dir)))
                    (if (= 0 (cdr add-result))
                        (push (format "%s=%s" path (gptel-auto-workflow--truncate-hash commit))
                              hydrated)
                      (setq failure
                           (format "Failed to hydrate %s: %s" path (car add-result)))))))))))
      (if failure
          (cons failure 1)
        (cons (if hydrated
                  (format "Hydrated submodules: %s"
                          (mapconcat #'identity (nreverse hydrated) ", "))
                "")
              0)))))

(defun gptel-auto-workflow--ensure-staging-submodules-ready (&optional worktree)
  "Hydrate staging submodules in WORKTREE before hook-driven git commits run.
This is a no-op when WORKTREE is nil or missing, which keeps unit tests that
stub away linked worktrees lightweight."
  (if (not (and (stringp worktree)
                (file-directory-p worktree)))
      t
    (let ((hydrate (gptel-auto-workflow--hydrate-staging-submodules worktree)))
      (if (= 0 (cdr hydrate))
          t
        (message "[auto-workflow] Failed to hydrate staging submodules: %s"
                 (my/gptel--sanitize-for-logging (car hydrate) 200))
        nil))))

(defun gptel-auto-workflow--staging-submodule-conflict-commits (path)
  "Return conflicted gitlink revisions for submodule PATH in the current worktree."
  (let* ((conflict-result
          (gptel-auto-workflow--git-result
           (format "git ls-files -u -- %s" (shell-quote-argument path))
           60))
         (output (car conflict-result))
         commits)
    (when (= 0 (cdr conflict-result))
      (dolist (line (split-string (or output "") "\n" t))
        (when (string-match
               (format "^160000 \\([0-9a-f]\\{40\\}\\) \\([123]\\)\t%s$"
                       (regexp-quote path))
               line)
          (setq commits
                (plist-put commits
                           (pcase (match-string 2 line)
                             ("1" :base)
                             ("2" :ours)
                             ("3" :theirs))
                           (match-string 1 line))))))
    commits))

(defun gptel-auto-workflow--submodule-commit-ancestor-p (git-dir ancestor descendant)
  "Return non-nil when ANCESTOR is contained in DESCENDANT within GIT-DIR."
  (and (stringp git-dir)
       (file-directory-p git-dir)
       (gptel-auto-workflow--non-empty-string-p ancestor)
       (gptel-auto-workflow--non-empty-string-p descendant)
       (= 0
          (cdr (gptel-auto-workflow--git-result
                (format "git --git-dir=%s merge-base --is-ancestor %s %s"
                        (shell-quote-argument git-dir)
                        (shell-quote-argument ancestor)
                        (shell-quote-argument descendant))
                60)))))

(defun gptel-auto-workflow--resolve-ancestor-submodule-merge-conflicts (&optional worktree)
  "Resolve unmerged top-level submodule conflicts in WORKTREE when ancestry is clear.
If every unmerged path is a declared top-level submodule and one side's gitlink is
an ancestor of the other, record the descendant gitlink in the index and return
non-nil. Otherwise leave the merge unresolved and return nil."
  (let* ((root (or worktree default-directory))
         (default-directory root)
         (submodule-paths (gptel-auto-workflow--staging-submodule-paths root))
         (unmerged-result
          (gptel-auto-workflow--git-result
           "git diff --name-only --diff-filter=U"
           30))
         (unmerged-paths
          (when (= 0 (cdr unmerged-result))
            (split-string (string-trim (car unmerged-result)) "\n" t)))
         (resolved nil)
         (all-resolved t))
    (when (and unmerged-paths
               (cl-every (lambda (path) (member path submodule-paths)) unmerged-paths))
      (dolist (path unmerged-paths)
        (let* ((conflict (gptel-auto-workflow--staging-submodule-conflict-commits path))
               (ours (plist-get conflict :ours))
               (theirs (plist-get conflict :theirs))
               (git-dir (or (gptel-auto-workflow--shared-submodule-git-dir path ours)
                            (gptel-auto-workflow--shared-submodule-git-dir path theirs)))
               (chosen
                (cond
                 ((gptel-auto-workflow--submodule-commit-ancestor-p git-dir ours theirs)
                  theirs)
                 ((gptel-auto-workflow--submodule-commit-ancestor-p git-dir theirs ours)
                  ours)
                 ((gptel-auto-workflow--non-empty-string-p ours)
                  ours)
                 ((gptel-auto-workflow--non-empty-string-p theirs)
                  theirs)
                 (t nil))))
          (if (not chosen)
              (setq all-resolved nil)
            (let ((update-result
                   (gptel-auto-workflow--git-result
                    (format "git update-index --cacheinfo 160000 %s %s"
                            (shell-quote-argument chosen)
                            (shell-quote-argument path))
                    60)))
              (if (= 0 (cdr update-result))
                  (push (format "%s=%s" path (gptel-auto-workflow--truncate-hash chosen))
                        resolved)
                (setq all-resolved nil))))))
      (when (and all-resolved resolved)
        (message "[auto-workflow] Resolved submodule merge conflicts: %s"
                 (mapconcat #'identity (nreverse resolved) ", "))
        t))))


(defun gptel-auto-workflow--review-diff-content (optimize-branch)
  "Return review diff content for OPTIMIZE-BRANCH.

The review surface must match the exact tip commit that staging merge will
cherry-pick, not the full branch delta against staging."
  (let* ((optimize-ref (gptel-auto-workflow--ensure-merge-source-ref optimize-branch)))
    (cond
     ((not optimize-ref)
      (format "Error resolving review branch: %s" optimize-branch))
     (t
      (let* ((rev-result
              (gptel-auto-workflow--git-result
               (format "git rev-parse %s"
                       (shell-quote-argument optimize-ref))
               60))
             (commit-hash (string-trim (car rev-result))))
        (cond
         ((not (= 0 (cdr rev-result)))
          (format "Error resolving review commit: %s" (car rev-result)))
         ((not (string-match-p "^[a-f0-9]\\{7,40\\}$" commit-hash))
          (format "Error resolving review commit: %s" commit-hash))
         (t
          (let* ((diff-result
                  (gptel-auto-workflow--git-result
                   (format "git diff --find-renames %s^ %s"
                           (shell-quote-argument commit-hash)
                           (shell-quote-argument commit-hash))
                   60))
                 (diff-output (car diff-result)))
            (cond
             ((string-empty-p diff-output)
              "No changes detected in review commit.")
             ((not (= 0 (cdr diff-result)))
              (format "Error generating diff: %s" diff-output))
              (t
               diff-output))))))))))

(defun gptel-auto-workflow--review-attachment-files (worktree changed-files)
  "Return reviewer file attachments for CHANGED-FILES in WORKTREE.

The returned plist contains:
- `:files' absolute file paths safe to attach
- `:skipped' relative file paths omitted due to reviewer context limits
- `:bytes' cumulative bytes attached"
  (let ((files nil)
        (skipped nil)
        (total-bytes 0))
    (dolist (relative-file changed-files
                           (list :files (nreverse files)
                                 :skipped (nreverse skipped)
                                 :bytes total-bytes))
      (let* ((absolute-file (expand-file-name relative-file worktree))
             (attrs (and (file-readable-p absolute-file)
                         (file-attributes absolute-file)))
             (size (and attrs (file-attribute-size attrs))))
        (if (or (not (integerp size))
                (> size gptel-auto-workflow-review-file-context-max-bytes)
                (> (+ total-bytes size)
                   gptel-auto-workflow-review-file-context-max-total-bytes))
            (push relative-file skipped)
          (push absolute-file files)
          (cl-incf total-bytes size))))))

(defun gptel-auto-workflow--review-changes (optimize-branch callback)
  "Review changes in OPTIMIZE-BRANCH before merging to staging.
Calls CALLBACK with (approved-p . review-output).
Reviewer checks for Blocker/Critical issues."
  (if (not gptel-auto-workflow-require-review)
      (my/gptel--invoke-callback-safely callback (cons t "Review disabled by config"))
    (let* ((proj-root (gptel-auto-workflow--project-root))
           (worktree (car (gptel-auto-workflow--branch-worktree-paths
                           optimize-branch proj-root)))
           (changed-files (and worktree
                               (gptel-auto-workflow--worktree-tip-changed-elisp-files
                                worktree)))
           (review-file-info (and worktree
                                  changed-files
                                  (gptel-auto-workflow--review-attachment-files
                                   worktree changed-files)))
           (review-files (plist-get review-file-info :files))
           (skipped-review-files (plist-get review-file-info :skipped))
           (default-directory proj-root)
           (review-timeout (max my/gptel-agent-task-timeout
                                gptel-auto-workflow-review-time-budget))
           (diff-content (gptel-auto-workflow--review-diff-content optimize-branch))
           (attachment-note
            (if skipped-review-files
                (format "ATTACHED FILE CONTEXT:\n- Attached changed files: %d\n- Omitted oversized files: %s\n- Use repo tools to inspect omitted files when needed.\n\n"
                        (length review-files)
                        (mapconcat #'identity skipped-review-files ", "))
              ""))
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
- When attached changed file contents are present, use them before claiming a file
  cannot be located.

%s

OUTPUT: First line must be exactly 'APPROVED' or 'BLOCKED: [reason]'.
You may include structured markdown after that verdict line.

Maximum response: 1000 characters."
                                  (truncate-string-to-width diff-content 3000 nil nil "...")
                                  attachment-note)))
      (message "[auto-workflow] Reviewing changes in %s..." optimize-branch)
      (when skipped-review-files
        (message "[auto-workflow] Reviewer attachments omitted oversized files: %s"
                 (mapconcat #'identity skipped-review-files ", ")))
      (if (and gptel-auto-experiment-use-subagents
               (fboundp 'gptel-benchmark-call-subagent))
          (let ((gptel-benchmark--subagent-files review-files))
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
                 (my/gptel--invoke-callback-safely
                  callback
                  (cons approved response))))
             review-timeout))
        (my/gptel--invoke-callback-safely callback (cons t "No reviewer agent available, auto-approving"))))))

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
                          (* (any "#*>`*_"))
                          (* blank)
                          "APPROVED" word-end)
                      normalized))
           (blocked (string-match
                     (rx (or line-start "\n")
                         (* blank)
                         (* (any "#*>`*_"))
                         (* blank)
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

(defun gptel-auto-workflow--review-undefined-function-symbol (review-output)
  "Return the undefined function symbol named in REVIEW-OUTPUT, or nil.
Used to catch reviewer false positives before they enter the fix loop."
  (when (stringp review-output)
    (let ((case-fold-search t))
      (when (string-match
             "undefined function[[:space:]]+[`'\"“”‘’]?\\([^`'\"“”‘’[:space:])]+\\)[`'\"“”‘’]?"
             review-output)
        (match-string 1 review-output)))))

(defun gptel-auto-workflow--worktree-tip-changed-elisp-files (worktree)
  "Return Elisp files changed by the tip commit in WORKTREE."
  (when (and (stringp worktree) (file-directory-p worktree))
    (let* ((default-directory worktree)
           (result (gptel-auto-workflow--git-result
                    "git diff --name-only --diff-filter=ACMR HEAD~1 HEAD -- '*.el'"
                    60)))
      (when (= 0 (cdr result))
        (split-string (car result) "\n" t)))))

(defun gptel-auto-workflow--file-defines-function-p (filepath function-name)
  "Return non-nil when FILEPATH defines FUNCTION-NAME in a defun-like form."
  (when-let ((content (gptel-auto-workflow--read-file-contents filepath)))
    (let ((case-fold-search nil))
      (or (string-match-p
           (format
            "^[[:space:]]*(\\(?:cl-\\)?def\\(?:un\\|macro\\|subst\\)\\_>\\s-+%s\\_>"
            (regexp-quote function-name))
           content)
          (string-match-p
           (format
            "^[[:space:]]*(defalias\\_>\\s-+'%s\\_>"
            (regexp-quote function-name))
           content)))))

(defun gptel-auto-workflow--review-disproven-undefined-function-blocker-p (optimize-branch review-output)
  "Return blocker symbol when REVIEW-OUTPUT makes a disproven undefined-function claim.
The blocker is treated as disproven only when the review output cites a single
undefined-function claim and a changed Elisp file in OPTIMIZE-BRANCH defines
that function locally."
  (when-let* ((function-name
               (gptel-auto-workflow--review-undefined-function-symbol review-output))
              ((stringp review-output))
              ((not (string-match-p
                     (rx (or "Proven Correctness Bugs"
                             "Action Items"
                             "Issue:"
                             "security"
                             "logic failure"
                             "state corruption"))
                     review-output)))
              (worktree (car (gptel-auto-workflow--branch-worktree-paths optimize-branch)))
              (changed-files (gptel-auto-workflow--worktree-tip-changed-elisp-files worktree)))
    (when (cl-some
           (lambda (relative-file)
             (gptel-auto-workflow--file-defines-function-p
              (expand-file-name relative-file worktree)
              function-name))
           changed-files)
      function-name)))

(defun gptel-auto-workflow--fix-review-issues (optimize-branch review-output callback)
  "Try to fix issues found in review for OPTIMIZE-BRANCH.
REVIEW-OUTPUT contains the blocker/critical issues.
Calls CALLBACK with (success-p . fix-output).
If `gptel-auto-workflow-research-before-fix' is nil, executor handles directly."
  (let* ((proj-root (gptel-auto-workflow--project-root))
         (worktree (car (gptel-auto-workflow--branch-worktree-paths optimize-branch proj-root)))
         (default-directory (or worktree proj-root)))
    (message "[auto-workflow] Fixing review issues (retry %d/%d)..."
             gptel-auto-workflow--review-retry-count gptel-auto-workflow--review-max-retries)
    (if (not (and (stringp worktree) (file-directory-p worktree)))
        (funcall callback
                 (cons nil
                       (format "Error: Missing review fix worktree for %s"
                               optimize-branch)))
      (if (not gptel-auto-workflow-research-before-fix)
          (gptel-auto-workflow--fix-directly review-output callback worktree)
        (gptel-auto-workflow--research-then-fix review-output callback worktree)))))

(defun gptel-auto-workflow--review-retryable-error-p (review-output)
  "Return non-nil when REVIEW-OUTPUT reflects a reviewer failure worth retrying.

This covers transient transport/provider failures plus contract failures where
the reviewer admits it could not verify the diff or locate the relevant file."
  (when (and (stringp review-output)
             (not (gptel-auto-workflow--review-approved-p review-output)))
    (let ((case-fold-search t))
      (or (memq (car (gptel-auto-experiment--categorize-error review-output))
                '(:api-rate-limit :api-error :timeout))
          (string-match-p
           (rx (or line-start "\n")
               (* blank)
               "UNVERIFIED")
           review-output)
           (string-match-p "did not meet verification contract" review-output)
           (string-match-p "cannot access the file directly" review-output)
           (string-match-p "cannot locate the file" review-output)))))

(defun gptel-auto-workflow--review-provider-chain-incomplete-p ()
  "Return non-nil when reviewer provider failover still has retries worth trying.

This keeps staging review alive long enough to rate-limit the current reviewer
backend and actually try the next available fallback provider."
  (let* ((preset (and (fboundp 'gptel-auto-experiment--current-subagent-preset)
                      (gptel-auto-experiment--current-subagent-preset "reviewer")))
         (backend (and (listp preset)
                       (gptel-auto-workflow--preset-backend-name
                        (plist-get preset :backend))))
         (failures (or (and (stringp backend)
                            (cdr (cl-assoc backend
                                           gptel-auto-workflow--backend-failure-counts
                                           :test #'string=)))
                       0)))
    (or (and (stringp backend)
             (< failures gptel-auto-workflow-backend-rate-limit-failure-threshold))
        (gptel-auto-experiment--remaining-provider-failover-candidate "reviewer"))))

(defun gptel-auto-workflow--review-error-retry-allowed-p (review-output)
  "Return non-nil when REVIEW-OUTPUT should get another transient retry."
  (or (< gptel-auto-workflow--review-error-retry-count
         gptel-auto-workflow--review-max-retries)
      (and (stringp review-output)
           (memq (car-safe (gptel-auto-experiment--categorize-error review-output))
                 '(:api-rate-limit :api-error :timeout))
           (gptel-auto-workflow--review-provider-chain-incomplete-p))))

(defun gptel-auto-workflow--fix-output-indicates-already-fixed-p (fix-output)
  "Return non-nil when FIX-OUTPUT says the worktree already contains the fix."
  (when (stringp fix-output)
    (let ((case-fold-search t))
      (or (string-match-p "already been fixed" fix-output)
          (string-match-p "already fixed" fix-output)
          (string-match-p "already present in the worktree" fix-output)
          (string-match-p "fix already present in worktree" fix-output)))))

(defun gptel-auto-workflow--worktree-dirty-p ()
  "Return non-nil when `default-directory' has uncommitted changes."
  (let ((status (string-trim (or (ignore-errors
                                   (gptel-auto-workflow--git-cmd
                                    "git status --porcelain 2>/dev/null"
                                    30))
                                 ""))))
    (gptel-auto-workflow--non-empty-string-p status)))

(defun gptel-auto-workflow--finalize-review-fix-result (response pre-fix-head)
  "Return (success-p . RESPONSE) after verifying a review-fix attempt.
PRE-FIX-HEAD is the current HEAD hash before the fixer runs."
  (let ((success (not (string-match-p "^Error:" response)))
        (fix-captured nil))
    (when success
      (when (gptel-auto-workflow--worktree-dirty-p)
        (setq fix-captured
              (and (gptel-auto-workflow--stage-worktree-changes
                    "Stage review fix"
                    60)
                   (gptel-auto-workflow--commit-step-success-p
                    (format "%s git commit -m %s"
                            gptel-auto-workflow--skip-submodule-sync-env
                            (shell-quote-argument "fix: address review issues"))
                    "Commit review fix"
                    gptel-auto-workflow-git-timeout))))
      (let ((post-fix-head (gptel-auto-workflow--current-head-hash)))
        (setq fix-captured
              (or fix-captured
                  (and pre-fix-head
                       post-fix-head
                       (not (equal pre-fix-head post-fix-head))))))
      (unless fix-captured
        (message "[auto-workflow] Review fix returned without code changes or commit")))
    (cons (and success fix-captured) response)))

(defun gptel-auto-workflow--fix-directly (review-output callback &optional worktree)
  "Let executor fix REVIEW-OUTPUT issues directly (faster).
When WORKTREE is non-nil, run the fixer and git capture there."
  (let* ((proj-root (gptel-auto-workflow--project-root))
         (fix-root
          (or (and (fboundp 'gptel-auto-workflow--normalize-worktree-dir)
                   (gptel-auto-workflow--normalize-worktree-dir
                    (or worktree proj-root)
                    proj-root))
              (file-name-as-directory
               (expand-file-name (or worktree proj-root)))))
         (fix-buffer
          (or (and (fboundp 'gptel-auto-workflow--get-worktree-buffer)
                   (ignore-errors
                     (gptel-auto-workflow--get-worktree-buffer fix-root)))
              (get-buffer-create
               (format " *aw-review-fix:%s*"
                       (file-name-nondirectory
                        (directory-file-name fix-root))))))
         (default-directory fix-root)
         (pre-fix-head (gptel-auto-workflow--current-head-hash))
         (fix-prompt
          (format "Fix the following issues in the code.

ISSUES FROM REVIEW:
%s

INSTRUCTIONS:
1. Read the affected files to understand context
2. Make minimal fixes to address each issue
3. Do NOT make unrelated changes
4. Do NOT create git commits yourself; leave file changes in the worktree
5. Do not reply with only a plan or explanation; actually modify the relevant files
6. If you cannot apply a real code change, reply with 'Error: no fix applied'

Focus only on the issues mentioned. Do not refactor or add features."
                  (truncate-string-to-width review-output 1500 nil nil "..."))))
    (when (buffer-live-p fix-buffer)
      (with-current-buffer fix-buffer
        (setq default-directory fix-root)))
    (if (and gptel-auto-experiment-use-subagents
             (fboundp 'gptel-benchmark-call-subagent))
        (gptel-auto-experiment--call-in-context
         fix-buffer fix-root
         (lambda ()
           (gptel-benchmark-call-subagent
            'executor
            "Fix review issues"
            fix-prompt
            (lambda (result)
              (let ((default-directory fix-root)
                    (response (if (stringp result) result (format "%S" result))))
                (funcall callback
                         (gptel-auto-workflow--finalize-review-fix-result
                          response
                          pre-fix-head)))))))
      (funcall callback (cons nil "No executor agent available")))))

(defun gptel-auto-workflow--research-then-fix (review-output callback &optional worktree)
  "Use researcher to find approach, then executor to fix REVIEW-OUTPUT.
When WORKTREE is non-nil, run both phases and git capture there."
  (let* ((proj-root (gptel-auto-workflow--project-root))
         (fix-root
          (or (and (fboundp 'gptel-auto-workflow--normalize-worktree-dir)
                   (gptel-auto-workflow--normalize-worktree-dir
                    (or worktree proj-root)
                    proj-root))
              (file-name-as-directory
               (expand-file-name (or worktree proj-root)))))
         (fix-buffer
          (or (and (fboundp 'gptel-auto-workflow--get-worktree-buffer)
                   (ignore-errors
                     (gptel-auto-workflow--get-worktree-buffer fix-root)))
              (get-buffer-create
               (format " *aw-review-fix:%s*"
                       (file-name-nondirectory
                        (directory-file-name fix-root))))))
         (default-directory fix-root)
         (pre-fix-head (gptel-auto-workflow--current-head-hash))
         (research-prompt
          (format "Research the best approach to fix these issues:

ISSUES FROM REVIEW:
%s

TASK:
1. Find relevant code patterns in the codebase
2. Check for similar fixes already implemented
3. Identify the minimal, correct fix approach
4. Return a concise fix plan (file:line, change description)

Do NOT make changes. Only research and report findings."
                  (truncate-string-to-width review-output 1000 nil nil "..."))))
    (when (buffer-live-p fix-buffer)
      (with-current-buffer fix-buffer
        (setq default-directory fix-root)))
    (message "[auto-workflow] Researching fix approach...")
    (if (and gptel-auto-experiment-use-subagents
             (fboundp 'gptel-benchmark-call-subagent))
        (gptel-auto-experiment--call-in-context
         fix-buffer fix-root
         (lambda ()
           (gptel-benchmark-call-subagent
            'researcher
            "Research fix approach"
            research-prompt
            (lambda (research-result)
              (let* ((default-directory fix-root)
                     (research-response
                      (if (stringp research-result)
                          research-result
                        (format "%S" research-result)))
                     (fix-prompt
                      (format "Apply fixes based on this research:

RESEARCH FINDINGS:
%s

ORIGINAL ISSUES:
%s

INSTRUCTIONS:
1. Apply the minimal fixes identified in research
2. Do NOT make unrelated changes
3. Do NOT create git commits yourself; leave file changes in the worktree
4. Do not reply with only an explanation; actually modify the files
5. If you cannot apply a real code change, reply with 'Error: no fix applied'"
                              (truncate-string-to-width research-response 1000 nil nil "...")
                              (truncate-string-to-width review-output 500 nil nil "..."))))
                (gptel-auto-experiment--call-in-context
                 fix-buffer fix-root
                 (lambda ()
                   (gptel-benchmark-call-subagent
                    'executor
                    "Apply researched fixes"
                    fix-prompt
                    (lambda (result)
                      (let ((default-directory fix-root)
                            (response (if (stringp result)
                                          result
                                        (format "%S" result))))
                        (funcall callback
                                 (gptel-auto-workflow--finalize-review-fix-result
                                  response
                                  pre-fix-head))))))))))))
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
         (staging (gptel-auto-workflow--require-staging-branch)))
    (gptel-auto-workflow--with-error-handling
     "ensure staging branch exists"
     (lambda ()
       (when staging
         (let* ((staging-q (shell-quote-argument staging))
                (remote-staging (format "refs/remotes/origin/%s" staging))
                (remote-staging-q (shell-quote-argument remote-staging))
                (remote-staging-refspec
                 (format "+refs/heads/%s:refs/remotes/origin/%s" staging staging))
                (remote-staging-refspec-q (shell-quote-argument remote-staging-refspec))
                (local-exists
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
                   (= 0 (cdr create-result)))))))))))))

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
  (let* ((staging (gptel-auto-workflow--require-staging-branch))
         (reset-q (shell-quote-argument reset-target)))
    (when staging
      (let* ((staging-q (shell-quote-argument staging))
             (current-branch-result
              (gptel-auto-workflow--git-result "git branch --show-current" 30))
             (current-branch
              (and (= 0 (cdr current-branch-result))
                   (string-trim (car current-branch-result))))
             (setup-results
              (append
               (unless (equal current-branch staging)
                 (list (gptel-auto-workflow--git-result
                        (format "git checkout %s" staging-q)
                        60)))
               (list (gptel-auto-workflow--git-result
                      (format "git reset --hard %s" reset-q)
                      180))))
             (failed-setup (cl-find-if (lambda (item) (/= 0 (cdr item)))
                                       setup-results)))
        (if failed-setup
            (progn
              (message "[auto-workflow] Failed to prepare staging merge: %s"
                       (my/gptel--sanitize-for-logging (car failed-setup) 160))
              nil)
          t)))))

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
                  (or (gptel-auto-workflow--empty-commit-output-p output)
                      (string-match-p
                       "already applied\\|previous cherry-pick is now empty\\|The previous cherry-pick is now empty"
                       output))))
         (string-empty-p unmerged-files)
         (string-empty-p worktree-status))))

(defun gptel-auto-workflow--merge-to-staging (optimize-branch)
  "Merge OPTIMIZE-BRANCH to staging using cherry-pick.
Cherry-pick the tip commit of OPTIMIZE-BRANCH onto staging.
Returns t when the branch adds changes, `:already-integrated' when staging
already contains the candidate patch, and nil on failure.
Uses the staging worktree instead of switching branches in the root repo."
  (let* ((staging (gptel-auto-workflow--configured-staging-branch))
         (optimize-ref (gptel-auto-workflow--ensure-merge-source-ref optimize-branch))
         (merge-message (format "Merge %s for verification" optimize-branch))
         (commit-timeout (max 300 gptel-auto-workflow-git-timeout)))
    (if (not (gptel-auto-workflow--ensure-staging-branch-exists))
        nil
      (if (not optimize-ref)
          (progn
            (message "[auto-workflow] Missing merge source branch: %s" optimize-branch)
            nil)
        (message "[auto-workflow] Cherry-picking %s to %s" optimize-branch staging)
        (gptel-auto-workflow--with-staging-worktree
         (lambda ()
           (let ((reset-target staging)
                 (worktree gptel-auto-workflow--staging-worktree-dir))
             (if (not (and (gptel-auto-workflow--prepare-staging-merge-base reset-target)
                           (gptel-auto-workflow--ensure-staging-submodules-ready worktree)))
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
                  ((= 0 (cdr cherry-result))
                   (let ((commit-result
                          (gptel-auto-workflow--git-result
                           (format "%s git commit -m %s"
                                   gptel-auto-workflow--skip-submodule-sync-env
                                   (shell-quote-argument merge-message))
                           commit-timeout)))
                     (cond
                      ((= 0 (cdr commit-result))
                       t)
                       ((gptel-auto-workflow--empty-cherry-pick-state-p (car commit-result) t)
                        (ignore-errors (gptel-auto-workflow--git-cmd "git cherry-pick --skip" 60))
                        (message "[auto-workflow] Cherry-pick empty after apply (already in staging)")
                        :already-integrated)
                      (t
                       (message "[auto-workflow] Commit failed after cherry-pick: %s"
                                (my/gptel--sanitize-for-logging (car commit-result) 160))
                       nil))))
                  ((or (gptel-auto-workflow--empty-cherry-pick-state-p cherry-output t)
                       (string-match-p "already applied\\|previous cherry-pick is now empty\\|The previous cherry-pick is now empty"
                                       cherry-output))
                   (message "[auto-workflow] Cherry-pick empty (already in staging)")
                    (ignore-errors (gptel-auto-workflow--git-cmd "git cherry-pick --abort" 60))
                    :already-integrated)
                  (t
                   (ignore-errors (gptel-auto-workflow--git-cmd "git cherry-pick --abort" 60))
                   (message "[auto-workflow] Cherry-pick failed, falling back to merge: %s"
                            (my/gptel--sanitize-for-logging cherry-output 160))
                   (if (not (and (gptel-auto-workflow--prepare-staging-merge-base reset-target)
                                 (gptel-auto-workflow--ensure-staging-submodules-ready worktree)))
                       nil
                     (let* ((merge-result
                             (gptel-auto-workflow--git-result
                              (format "git merge -X theirs %s --no-ff -m %s"
                                      (shell-quote-argument optimize-ref)
                                      (shell-quote-argument merge-message))
                              180))
                            (merge-output (car merge-result)))
                       (cond
                        ((= 0 (cdr merge-result)) t)
                         ((string-match-p "Already up[ -]to[- ]date" merge-output)
                          :already-integrated)
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
  (if (or (null directory) (null output-buffer))
      (progn
        (message "[auto-workflow] check-el-syntax: nil argument")
        nil)
    (let ((errors nil)
          (files (ignore-errors (directory-files-recursively directory "\\.el\\'"))))
      (dolist (file (or files nil) (null errors))
        (when (file-readable-p file)
          (condition-case err
              (with-temp-buffer
                (insert-file-contents file)
                ;; Parse with `emacs-lisp-mode' so syntax-propertize handles
                ;; reader forms correctly, but suppress mode hooks so staging
                ;; verification cannot trip unrelated editor setup.
                (delay-mode-hooks
                  (emacs-lisp-mode))
                (goto-char (point-min))
                (while (not (eobp))
                  (forward-sexp)))
            (error
             (let ((msg (format "SYNTAX ERROR: %s: %s"
                                (file-relative-name file directory)
                                (error-message-string err))))
               (push msg errors)
               (when (buffer-live-p output-buffer)
                 (with-current-buffer output-buffer
                   (insert msg "\n")))))))))))

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
              (submodule-note
               (and syntax-pass
                    (not submodule-pass)
                    (let ((note (car-safe submodules)))
                      (if (gptel-auto-workflow--non-empty-string-p note)
                          note
                        "Staging submodule hydration failed"))))
              (_ (when submodule-note
                   (with-current-buffer output-buffer
                     (insert submodule-note "\n"))))
              (test-result (when (and submodule-pass test-script (file-exists-p test-script))
                             (gptel-auto-workflow--call-process-with-watchdog
                              "bash" nil output-buffer nil test-script "unit")))
             (verify-result (when (and submodule-pass verify-script (file-exists-p verify-script))
                              (let ((process-environment
                                     (cons "VERIFY_NUCLEUS_SKIP_SUBMODULE_SYNC=1"
                                           process-environment)))
                                (gptel-auto-workflow--call-process-with-watchdog
                                 "bash" nil output-buffer nil verify-script))))
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
            (setq checks-pass (not (null (car-safe baseline-check))))
            (with-current-buffer output-buffer
              (goto-char (point-max))
              (unless (bolp)
                (insert "\n"))
              (insert "\n"
                      (let ((note (cdr-safe baseline-check)))
                        (if (gptel-auto-workflow--non-empty-string-p note)
                            note
                          "Staging verification failed against main baseline"))
                      "\n"))
            (setq output (with-current-buffer output-buffer (buffer-string)))))
        (kill-buffer output-buffer)
        (setq result (and syntax-pass submodule-pass checks-pass))
        (message "[auto-workflow] Staging verification: %s" (if result "PASS" "FAIL"))
        (cons result output)))))



(defun gptel-auto-workflow--parse-remote-head (branch output)
  "Return BRANCH head parsed from git ls-remote OUTPUT, ignoring SSH noise."
  (let ((pattern (format "^\\([0-9a-f]\\{40\\}\\)\trefs/heads/%s$"
                         (regexp-quote branch)))
        head)
    (dolist (line (split-string (or output "") "\n" t) head)
      (when (and (null head)
                 (string-match pattern line))
        (setq head (match-string 1 line))))))

(defun gptel-auto-workflow--push-branch-with-lease (branch action &optional timeout)
  "Push BRANCH to origin, using `--force-with-lease' when it already exists.
ACTION is a short description used in failure messages."
  (let* ((branch-q (shell-quote-argument branch))
         (remote-result
          (gptel-auto-workflow--git-result
           (format "git ls-remote --exit-code --heads origin %s" branch-q)
           60))
         (remote-head
          (and (= 0 (cdr remote-result))
               (gptel-auto-workflow--parse-remote-head branch (car remote-result))))
         (push-command
          (if remote-head
              (format "git push %s origin %s"
                      (shell-quote-argument
                       (format "--force-with-lease=%s:%s"
                               branch
                               remote-head))
                      branch-q)
            (format "git push origin %s" branch-q)))
         (push-result
          (gptel-auto-workflow--with-skipped-submodule-sync
           (lambda ()
             (gptel-auto-workflow--git-result
              push-command
              (or timeout 180))))))
    (if (= 0 (cdr push-result))
        t
      (message "[auto-workflow] %s failed: %s"
               action
               (my/gptel--sanitize-for-logging (car push-result) 160))
      nil)))

(defun gptel-auto-workflow--push-staging ()
  "Push staging branch to origin after successful verification.
Unlike per-experiment optimize branches, staging is a shared integration branch,
so this push must not rewrite remote history."
  (let ((staging (gptel-auto-workflow--require-staging-branch)))
    (message "[auto-workflow] Pushing staging to origin")
    (when staging
      (gptel-auto-workflow--with-staging-worktree
       (lambda ()
         (setq gptel-auto-workflow--last-staging-push-output nil)
         (let* ((push-result
                 (gptel-auto-workflow--with-skipped-submodule-sync
                  (lambda ()
                    (gptel-auto-workflow--git-result
                     (format "git push origin %s"
                             (shell-quote-argument staging))
                     180)))))
           (setq gptel-auto-workflow--last-staging-push-output (car push-result))
           (if (= 0 (cdr push-result))
               t
             (message "[auto-workflow] Push staging failed: %s"
                      (my/gptel--sanitize-for-logging (car push-result) 160))
             nil)))))))

(defvar gptel-auto-workflow--last-staging-push-output nil
  "Raw output from the most recent staging push attempt.")

(defun gptel-auto-workflow--staging-push-remote-advanced-p (output)
  "Return non-nil when OUTPUT shows `origin/staging' advanced mid-run."
  (string-match-p
   (rx (or "fetch first"
           "non-fast-forward"
           "failed to push some refs"
           "remote contains work that you do not have locally"))
   (or output "")))

(defun gptel-auto-workflow--retry-staging-publish-after-remote-advance (optimize-branch &optional retries-remaining)
  "Refresh shared staging and retry publishing OPTIMIZE-BRANCH.
RETRIES-REMAINING counts remaining refresh-and-retry attempts after an
initial remote-advance rejection. Returns a plist with keys `:success',
`:reason', and `:output'."
  (let* ((remaining (or retries-remaining
                        gptel-auto-workflow--staging-push-max-retries))
         (max-retries (max 1 gptel-auto-workflow--staging-push-max-retries))
         (attempt (1+ (- max-retries remaining))))
    (message "[auto-workflow] origin/staging advanced; refreshing staging and retrying publish (%d/%d)"
             attempt max-retries)
    (setq gptel-auto-workflow--last-staging-push-output nil)
    (cond
     ((not (gptel-auto-workflow--sync-staging-from-main))
      (if (> remaining 1)
          (progn
            (message "[auto-workflow] Failed to sync refreshed staging; retrying publish refresh (%d/%d)"
                     attempt max-retries)
            (gptel-auto-workflow--retry-staging-publish-after-remote-advance
             optimize-branch
             (1- remaining)))
        (list :success nil
              :reason 'staging-sync-failed
              :output "Failed to sync staging from updated origin/staging")))
     ((not (gptel-auto-workflow--merge-to-staging optimize-branch))
      (list :success nil
            :reason 'staging-merge-failed
            :output (format "Failed to merge %s onto refreshed staging" optimize-branch)))
     (t
      (let ((worktree (or gptel-auto-workflow--staging-worktree-dir
                          (gptel-auto-workflow--create-staging-worktree))))
        (cond
         ((not worktree)
          (list :success nil
                :reason 'staging-worktree-failed
                :output "Failed to create staging worktree"))
         (t
          (let* ((verification (gptel-auto-workflow--verify-staging))
                 (tests-passed (car verification))
                 (output (or (cdr verification) "")))
            (if (not tests-passed)
                (list :success nil
                      :reason 'staging-verification-failed
                      :output output)
              (if (gptel-auto-workflow--push-staging)
                  (list :success t :output output)
                (let ((push-output
                       (or gptel-auto-workflow--last-staging-push-output
                           output
                           "")))
                  (if (and (> remaining 1)
                           (gptel-auto-workflow--staging-push-remote-advanced-p
                            push-output))
                      (gptel-auto-workflow--retry-staging-publish-after-remote-advance
                       optimize-branch
                       (1- remaining))
                    (list :success nil
                          :reason 'staging-push-failed
                          :output push-output)))))))))))))

(defun gptel-auto-workflow--log-staging-step-failure (reason optimize-branch output)
  "Log staging step failure REASON for OPTIMIZE-BRANCH with OUTPUT."
  (pcase reason
    ('staging-worktree-failed
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
            :agent-output "")))
    ('staging-verification-failed
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
            :comparator-reason (truncate-string-to-width (or output "") 200)
            :analyzer-patterns ""
            :agent-output (or output ""))))
    ('staging-merge-failed
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
            (or output (format "Failed to merge %s to staging" optimize-branch))
            :analyzer-patterns ""
            :agent-output "")))
    ((or 'staging-push-failed 'staging-sync-failed)
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
            :grader-reason
            (pcase reason
              ('staging-sync-failed "staging-sync-failed")
              (_ "staging-push-failed"))
            :comparator-reason
            (if (string-empty-p (string-trim (or output "")))
                "Failed to push staging"
              (truncate-string-to-width output 200))
            :analyzer-patterns ""
            :agent-output (or output ""))))))


(defun gptel-auto-workflow--current-staging-head ()
  "Return the current commit at the staging branch head, or nil if unavailable."
  (let* ((proj-root (gptel-auto-workflow--project-root))
         (default-directory proj-root))
    (when (gptel-auto-workflow--ensure-staging-branch-exists)
      (let* ((staging-q (shell-quote-argument
                         (gptel-auto-workflow--configured-staging-branch)))
             (head-result
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
         (base-q (shell-quote-argument base-ref)))
    (when (and base-ref (gptel-auto-workflow--ensure-staging-branch-exists))
      (let ((staging (gptel-auto-workflow--configured-staging-branch)))
        (gptel-auto-workflow--delete-staging-worktree)
        (let ((worktree (gptel-auto-workflow--create-staging-worktree)))
          (when worktree
            (let ((default-directory worktree))
              (let* ((staging-q (shell-quote-argument staging))
                     (results (list
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
                  t)))))))))

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
           (gptel-auto-workflow--make-idempotent-staging-completion completion-callback))))
    (gptel-auto-workflow--assert-main-untouched)
    (setq gptel-auto-workflow--review-retry-count 0)
    (setq gptel-auto-workflow--review-error-retry-count 0)
    (message "[auto-workflow] Starting staging flow for %s" optimize-branch)
    (let ((skip-review (gptel-auto-workflow--optimize-branch-integrated-p optimize-branch)))
      (if skip-review
          (condition-case err
              (progn
                (message "[auto-workflow] Candidate already present in staging or main; skipping review for %s"
                         optimize-branch)
                (gptel-auto-workflow--staging-flow-after-review
                 optimize-branch
                 '(t . "Review skipped: branch already integrated")
                 completion-callback))
            (error
             (message "[auto-workflow] Staging flow callback failed for %s: %s"
                      optimize-branch
                      (my/gptel--sanitize-for-logging
                       (error-message-string err) 200))
             (ignore-errors (gptel-auto-workflow--delete-staging-worktree))
             (when completion-callback
               (my/gptel--invoke-callback-safely completion-callback nil))))
        (gptel-auto-workflow--review-changes
         optimize-branch
         (lambda (review-result)
           (condition-case err
               (gptel-auto-workflow--staging-flow-after-review
                optimize-branch
                review-result
                completion-callback)
             (error
              (message "[auto-workflow] Staging flow callback failed for %s: %s"
                       optimize-branch
                       (my/gptel--sanitize-for-logging
                        (error-message-string err) 200))
              (ignore-errors (gptel-auto-workflow--delete-staging-worktree))
              (when completion-callback
                (my/gptel--invoke-callback-safely completion-callback nil))))))))))


(defun gptel-auto-workflow--staging-flow-after-review (optimize-branch review-result &optional completion-callback)
  "Continue staging flow after review for OPTIMIZE-BRANCH.
REVIEW-RESULT is (approved-p . review-output).
When COMPLETION-CALLBACK is non-nil, call it with non-nil on success."
  (let* ((raw-approved (car review-result))
         (review-output (cdr review-result))
         (disproven-undefined-blocker
          (and (not raw-approved)
               (gptel-auto-workflow--review-disproven-undefined-function-blocker-p
                optimize-branch review-output)))
         (approved (or raw-approved disproven-undefined-blocker))
         (review-error-category
          (and (not approved)
               (stringp review-output)
               (car-safe
                (gptel-auto-experiment--categorize-error review-output))))
         (review-error (and (not approved)
                            (gptel-auto-workflow--review-retryable-error-p review-output)))
         (run-id (and (or gptel-auto-workflow--running
                          (bound-and-true-p gptel-auto-workflow--cron-job-running))
                      (boundp 'gptel-auto-workflow--run-id)
                      gptel-auto-workflow--run-id))
         (finish (gptel-auto-workflow--make-idempotent-callback
                   (lambda (success &optional reason)
                     (gptel-auto-workflow--invoke-staging-completion
                      completion-callback success reason)))))
    (when disproven-undefined-blocker
      (message "[auto-workflow] Reviewer undefined-function blocker disproven locally for %s; continuing"
               disproven-undefined-blocker))
    (cond
     (review-error
      (if (gptel-auto-workflow--review-error-retry-allowed-p review-output)
          (progn
            (when (memq review-error-category '(:api-rate-limit :api-error :timeout))
              (when-let ((reviewer-preset
                          (gptel-auto-workflow--agent-base-preset "reviewer")))
                (gptel-auto-workflow--activate-provider-failover
                  "reviewer" reviewer-preset review-output)))
            (cl-incf gptel-auto-workflow--review-error-retry-count)
            (message "[auto-workflow] Review failed transiently, retrying review (%d/%d%s)..."
                     gptel-auto-workflow--review-error-retry-count
                     gptel-auto-workflow--review-max-retries
                     (if (> gptel-auto-workflow--review-error-retry-count
                            gptel-auto-workflow--review-max-retries)
                         ", provider failover"
                       ""))
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
               (let* ((fix-success (car fix-result))
                      (fix-output (cdr fix-result))
                      (already-fixed
                       (and (not fix-success)
                            (gptel-auto-workflow--fix-output-indicates-already-fixed-p
                             fix-output))))
                 (cond
                  (fix-success
                   (message "[auto-workflow] Fix applied, re-reviewing...")
                   (gptel-auto-workflow--review-changes
                    optimize-branch
                    (lambda (re-review-result)
                      (gptel-auto-workflow--staging-flow-after-review
                       optimize-branch
                       re-review-result
                       completion-callback))))
                  (already-fixed
                   (message "[auto-workflow] Fixer reports issue already resolved; re-reviewing current branch...")
                   (gptel-auto-workflow--review-changes
                    optimize-branch
                    (lambda (re-review-result)
                      (gptel-auto-workflow--staging-flow-after-review
                       optimize-branch
                       re-review-result
                       completion-callback))))
                  (t
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
                   (funcall finish nil)))))))
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
                     (merge-result
                      (gptel-auto-workflow--merge-to-staging optimize-branch))
                     (already-integrated-p (eq merge-result :already-integrated))
                     (finish-publish
                      (lambda (&optional retried)
                        (gptel-auto-workflow--delete-staging-worktree)
                        (if (not (gptel-auto-workflow--run-callback-live-p run-id))
                            (progn
                              (message "[auto-workflow] Skipping stale staging publish for %s; run %s is no longer active"
                                       optimize-branch run-id)
                              (funcall finish nil "stale-staging-publish"))
                          (if already-integrated-p
                              (progn
                                (message
                                 (if retried
                                     "[auto-workflow] Candidate already present in staging after refresh; published staging sync only."
                                   "[auto-workflow] Candidate already present in staging; published staging sync only."))
                                (funcall finish nil "already-in-staging"))
                            (message
                             (if retried
                                 "[auto-workflow] ✓ Staging pushed after refreshing remote advance."
                               "[auto-workflow] ✓ Staging pushed. Human must merge to main."))
                            (funcall finish t))))))
                (if (not merge-result)
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
              (when already-integrated-p
                (message "[auto-workflow] Candidate changes already present in staging; verifying staged sync only"))
              (let ((worktree (or gptel-auto-workflow--staging-worktree-dir
                                  (gptel-auto-workflow--create-staging-worktree))))
                (if (not worktree)
                    (progn
                      (gptel-auto-workflow--log-staging-step-failure
                       'staging-worktree-failed optimize-branch "")
                      (gptel-auto-workflow--reset-staging-after-failure staging-base)
                      (funcall finish nil))
                  (let* ((verification (gptel-auto-workflow--verify-staging))
                         (tests-passed (car verification))
                         (output (or (cdr verification) "")))
                    (if (not tests-passed)
                        (progn
                          (gptel-auto-workflow--log-staging-step-failure
                           'staging-verification-failed optimize-branch output)
                          (gptel-auto-workflow--reset-staging-after-failure staging-base)
                          (funcall finish nil))
                      (message "[auto-workflow] ✓ Staging verification PASSED")
                      (if (gptel-auto-workflow--push-staging)
                          (funcall finish-publish nil)
                        (let* ((push-output gptel-auto-workflow--last-staging-push-output)
                               (remote-advanced-p
                                (gptel-auto-workflow--staging-push-remote-advanced-p
                                 push-output)))
                          (if remote-advanced-p
                              (if (> gptel-auto-workflow--staging-push-max-retries 0)
                                  (let* ((retry-result
                                          (gptel-auto-workflow--retry-staging-publish-after-remote-advance
                                           optimize-branch))
                                         (retry-success (plist-get retry-result :success))
                                         (retry-reason (plist-get retry-result :reason))
                                         (retry-output (plist-get retry-result :output)))
                                    (if retry-success
                                        (funcall finish-publish t)
                                      (gptel-auto-workflow--log-staging-step-failure
                                       retry-reason optimize-branch retry-output)
                                      (gptel-auto-workflow--sync-staging-from-main)
                                      (funcall finish nil)))
                                (gptel-auto-workflow--log-staging-step-failure
                                 'staging-push-failed optimize-branch push-output)
                                (gptel-auto-workflow--sync-staging-from-main)
                                (funcall finish nil))
                            (gptel-auto-workflow--log-staging-step-failure
                             'staging-push-failed optimize-branch push-output)
                            (gptel-auto-workflow--reset-staging-after-failure staging-base)
                            (funcall finish nil))))))))))))))))


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
         (hydrate-submodules-p
          (and worktree
               (or (and proj-root
                        (not (file-equal-p proj-root worktree)))
                   (gptel-auto-workflow--worktree-needs-submodule-hydration-p worktree))))
          (default-directory worktree)
          (process-environment
           (gptel-auto-workflow--isolated-state-environment
            "copilot-auto-workflow-test-"
            (list "VERIFY_NUCLEUS_SKIP_SUBMODULE_SYNC=1")))
          (isolated-status-file (getenv "AUTO_WORKFLOW_STATUS_FILE"))
           (test-script (expand-file-name "scripts/run-tests.sh" worktree))
           (output-buffer (generate-new-buffer "*test-output*"))
           result)
    (unwind-protect
        (if (not (file-executable-p test-script))
            (progn
              (message "[auto-experiment] Test script not found or not executable: %s" test-script)
              (cons t "No test script - skipping"))
          (let* (;; Linked worktrees need the same shared-repo hydration that
                 ;; staging uses, and fresh project-root worktrees can also
                 ;; arrive with gitlink directories that exist but are empty.
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
               (cl-labels
                   ((run-tests-once (attempt)
                      (message "[auto-experiment] Running tests%s..."
                               (if (> attempt 1)
                                   (format " (attempt %d)" attempt)
                                 ""))
                      (with-current-buffer output-buffer
                        (erase-buffer))
                      (let ((exit-code
                             (gptel-auto-workflow--call-process-with-watchdog
                              test-script nil output-buffer nil "unit")))
                        (with-current-buffer output-buffer
                          (cons (zerop exit-code) (buffer-string))))))
                 (setq result (run-tests-once 1))
                 (unless (car result)
                   (let ((first-output (cdr result)))
                     (message "[auto-experiment] Retrying tests after failure")
                     (sleep-for 1)
                     (let ((retry-result (run-tests-once 2)))
                       (setq result
                             (if (car retry-result)
                                 retry-result
                               (cons nil
                                     (format "Initial test run failed:\n%s\n\nRetry failed:\n%s"
                                             first-output
                                             (cdr retry-result))))))))
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

(defun gptel-auto-experiment--defer-tests-to-staging-p (skip-tests)
  "Return non-nil when benchmark tests should be deferred to staging.
This only applies to headless auto-workflow runs that already verify candidates
through the staging gate."
  (and skip-tests
       gptel-auto-experiment-require-tests
       gptel-auto-workflow-use-staging
       (bound-and-true-p gptel-auto-workflow--headless)))

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
tests still run before the experiment is considered passed, even if SKIP-TESTS
is t. The exception is the normal headless staging workflow, where benchmark
tests are deferred to the staging gate to keep the worker daemon alive."
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
      (let* ((defer-tests-to-staging
              (gptel-auto-experiment--defer-tests-to-staging-p skip-tests))
             (should-run-tests
              (or (not skip-tests)
                  (and gptel-auto-experiment-require-tests
                       (not defer-tests-to-staging))))
             (tests-result (when should-run-tests
                             (gptel-auto-experiment-run-tests)))
             (raw-tests-passed (and tests-result (car tests-result)))
             (tests-output (when tests-result (cdr tests-result)))
             ;; Allow test failures that match main baseline
             (baseline-check (when (and should-run-tests (not raw-tests-passed))
                               (gptel-auto-workflow--staging-tests-match-main-baseline-p tests-output)))
             (tests-passed (or (not should-run-tests)
                               (and skip-tests (not gptel-auto-experiment-require-tests))
                               raw-tests-passed
                               (and baseline-check (car baseline-check))))
             (final-tests-output (or (and baseline-check (cdr baseline-check))
                                     tests-output))
             (scores (gptel-auto-experiment--eight-keys-scores)))
        (when defer-tests-to-staging
          (message "[auto-exp] Deferring tests to staging flow for %s"
                   (or gptel-auto-workflow--current-target default-directory)))
        (when (and skip-tests gptel-auto-experiment-require-tests)
          (message "[auto-exp] Tests required before staging merge: %s"
                   (if tests-passed "PASS" "FAIL")))
        (list :passed tests-passed
              :nucleus-passed t
              :nucleus-skipped t
              :tests-passed tests-passed
              :tests-output final-tests-output
              :tests-skipped (not should-run-tests)
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

(defun gptel-auto-experiment--call-in-context (buffer directory fn &optional run-root)
  "Call FN in BUFFER with DIRECTORY bound as `default-directory'.
When RUN-ROOT is non-nil, preserve that workflow root for async callbacks that
resume from buffers outside the original project context."
  (gptel-auto-workflow--call-in-run-context
   run-root fn buffer directory))

(defmacro gptel-auto-experiment--with-context (buffer directory &rest body)
  "Run BODY in BUFFER with DIRECTORY bound as `default-directory'."
  (declare (indent 2) (debug t))
  `(gptel-auto-experiment--call-in-context
    ,buffer ,directory
    (lambda ()
      ,@body)))

(defmacro gptel-auto-experiment--with-run-context (buffer directory run-root &rest body)
  "Run BODY in BUFFER with DIRECTORY and RUN-ROOT rebound for workflow callbacks."
  (declare (indent 3) (debug t))
  `(gptel-auto-experiment--call-in-context
    ,buffer ,directory
    (lambda ()
      ,@body)
    ,run-root))

(defun gptel-auto-experiment--analysis-value-present-p (value)
  "Return non-nil when VALUE contains usable analyzer content."
  (cond
   ((null value) nil)
   ((stringp value) (not (string-empty-p (string-trim value))))
   ((vectorp value) (> (length value) 0))
   ((listp value) (not (null value)))
   (t t)))

(defun gptel-auto-experiment--analysis-list (value)
  "Return VALUE as a list for analyzer prompt composition."
  (cond
   ((null value) nil)
   ((vectorp value) (append value nil))
   ((listp value) value)
   (t (list value))))

(defun gptel-auto-experiment--summarize-previous-results (previous-results)
  "Return a prompt-friendly summary string for PREVIOUS-RESULTS."
  (when previous-results
    (mapconcat
     (lambda (result)
       (let* ((experiment-id (gptel-auto-workflow--plist-get result :id "?"))
              (decision (gptel-auto-experiment--tsv-decision-label result))
              (hypothesis
               (truncate-string-to-width
                (gptel-auto-experiment--tsv-escape
                 (gptel-auto-workflow--plist-get result :hypothesis "unknown"))
                220 nil nil "...")))
         (format "- Experiment %s: %s - %s"
                 experiment-id decision hypothesis)))
     previous-results
     "\n")))

(defun gptel-auto-experiment--fallback-analysis (previous-results)
  "Return deterministic analysis plist derived from PREVIOUS-RESULTS."
  (when previous-results
    (let ((recommendations '()))
      (push "Do not repeat a previous hypothesis verbatim. Choose a materially different change or explain why it avoids the earlier outcome."
            recommendations)
      (when (cl-some
             (lambda (result)
               (string= (gptel-auto-experiment--tsv-decision-label result)
                        "discarded"))
             previous-results)
        (push "At least one prior attempt was discarded as no improvement; pivot to a different function, defect, or improvement type."
              recommendations))
      (when (cl-some
             (lambda (result)
               (member (gptel-auto-experiment--tsv-decision-label result)
                       '("tests-failed"
                         "validation-failed"
                         "inspection-thrash"
                         "repeated-focus-symbol"
                         "retry-grade-failed")))
             previous-results)
        (push "At least one prior attempt failed validation/tests; avoid editing the same code path again unless the new change directly fixes that failure."
              recommendations))
      (list :patterns (gptel-auto-experiment--summarize-previous-results
                       previous-results)
            :issues nil
            :recommendations (nreverse (delete-dups recommendations))))))

(defun gptel-auto-experiment--merge-analysis (analysis previous-results)
  "Merge ANALYSIS with deterministic history from PREVIOUS-RESULTS."
  (let* ((fallback (gptel-auto-experiment--fallback-analysis previous-results))
         (patterns (if (gptel-auto-experiment--analysis-value-present-p
                        (plist-get analysis :patterns))
                       (plist-get analysis :patterns)
                     (plist-get fallback :patterns)))
         (issues (if (gptel-auto-experiment--analysis-value-present-p
                      (plist-get analysis :issues))
                     (plist-get analysis :issues)
                   (plist-get fallback :issues)))
         (recommendations
          (delete-dups
           (append (gptel-auto-experiment--analysis-list
                    (plist-get analysis :recommendations))
                   (gptel-auto-experiment--analysis-list
                    (plist-get fallback :recommendations))))))
    (when (or (gptel-auto-experiment--analysis-value-present-p patterns)
              (gptel-auto-experiment--analysis-value-present-p issues)
              recommendations)
      (list :patterns patterns
            :issues issues
            :recommendations recommendations))))

(defcustom gptel-auto-experiment-repeat-focus-threshold 2
  "Prior non-kept attempts on the same changed symbol before short-circuiting repeats."
  :type 'integer
  :group 'gptel-tools-agent)

(defun gptel-auto-experiment--extract-focus-symbols (output)
  "Return deduplicated function-like symbols mentioned in OUTPUT."
  (let (symbols)
    (when (stringp output)
      (with-temp-buffer
        (insert output)
        (goto-char (point-min))
        (while (re-search-forward "`\\([^`\n]+\\)`" nil t)
          (let ((candidate (match-string 1)))
            (when (and (stringp candidate)
                       (string-match-p "--\\|::" candidate)
                       (not (string-match-p "\\.el\\'" candidate)))
              (push candidate symbols))))))
    (nreverse (cl-remove-duplicates symbols :test #'string=))))

(defun gptel-auto-experiment--repeated-focus-match (output previous-results)
  "Return plist when OUTPUT repeats a changed symbol in PREVIOUS-RESULTS.
Only counts prior non-kept results and triggers once a symbol appears in at
least `gptel-auto-experiment-repeat-focus-threshold' previous attempts."
  (let ((current-symbols (gptel-auto-experiment--extract-focus-symbols output)))
    (when current-symbols
      (let ((counts (make-hash-table :test 'equal))
            matches)
        (dolist (result previous-results)
          (unless (gptel-auto-workflow--plist-get result :kept nil)
            (dolist (symbol
                     (gptel-auto-experiment--extract-focus-symbols
                      (gptel-auto-workflow--plist-get result :agent-output "")))
              (puthash symbol (1+ (gethash symbol counts 0)) counts))))
        (dolist (symbol current-symbols)
          (let ((count (gethash symbol counts 0)))
            (when (>= count gptel-auto-experiment-repeat-focus-threshold)
              (push (cons symbol count) matches))))
        (when matches
          (let* ((sorted (sort matches (lambda (a b) (> (cdr a) (cdr b)))))
                 (best (car sorted)))
             (list :symbol (car best)
                   :count (cdr best)
                   :matches (nreverse sorted))))))))

(defun gptel-auto-experiment--subagent-raw-result (result)
  "Return raw transient error text from RESULT, or nil when unavailable."
  (cond
   ((stringp result) result)
   ((and (listp result)
         (stringp (plist-get result :raw)))
    (plist-get result :raw))
   (t nil)))

(defun gptel-auto-experiment--subagent-error-output-p (raw)
  "Return non-nil when RAW looks like a real subagent failure payload.
Successful analyzer/comparator text can mention prior timeouts or failures in
its narrative.  Those references must not be treated as retryable transport
errors."
  (and (stringp raw)
       (or (string-match-p "\\`Error:" raw)
           (string-match-p "\\`Warning:.*not available" raw)
           (gptel-auto-experiment--aborted-agent-output-p raw))))

(defun gptel-auto-experiment--retryable-aux-subagent-category (result)
  "Return retryable transient error category for RESULT, or nil."
  (when-let* ((raw (gptel-auto-experiment--subagent-raw-result result))
              ((gptel-auto-experiment--subagent-error-output-p raw))
              (category (car (gptel-auto-experiment--categorize-error raw))))
    (when (or (memq category '(:timeout :api-rate-limit))
              (and (eq category :api-error)
                   (gptel-auto-experiment--is-retryable-error-p raw)))
      category)))

(defun gptel-auto-experiment--current-subagent-preset (agent-type)
  "Return the effective preset for AGENT-TYPE in the current run."
  (when-let* ((base-preset
               (and (fboundp 'gptel-auto-workflow--agent-base-preset)
                    (gptel-auto-workflow--agent-base-preset agent-type))))
    (if (fboundp 'gptel-auto-workflow--maybe-override-subagent-provider)
        (gptel-auto-workflow--maybe-override-subagent-provider agent-type base-preset)
      base-preset)))

(defun gptel-auto-experiment--call-aux-subagent-with-retry
    (agent-type invoke callback &optional retries)
  "Invoke AGENT-TYPE via INVOKE, retrying transient failures before CALLBACK.

INVOKE is called with a single callback argument and must start the actual
subagent request."
  (funcall
   invoke
   (lambda (result)
     (let* ((attempt (or retries 0))
            (category
             (gptel-auto-experiment--retryable-aux-subagent-category result))
            (raw (gptel-auto-experiment--subagent-raw-result result)))
       (if (and category
                (< attempt gptel-auto-experiment-max-aux-subagent-retries))
           (progn
             (when-let ((preset
                         (gptel-auto-experiment--current-subagent-preset
                          agent-type)))
               (gptel-auto-workflow--activate-provider-failover
                agent-type preset raw))
             (message "[auto-exp] %s failed transiently (%s), retrying (%d/%d)"
                      agent-type category
                      (1+ attempt) gptel-auto-experiment-max-aux-subagent-retries)
             (gptel-auto-experiment--call-aux-subagent-with-retry
              agent-type invoke callback (1+ attempt)))
         (funcall callback result))))))

(defun gptel-auto-experiment-analyze (previous-results callback)
  "Analyze patterns from PREVIOUS-RESULTS. Call CALLBACK with analysis.
The analyzer subagent overlay will appear in the current buffer at time of call."
  ;; Capture the current buffer to ensure analyzer overlay appears in right place
  (let ((analyze-buffer (current-buffer))
        (finalize
         (lambda (analysis)
           (funcall callback
                    (gptel-auto-experiment--merge-analysis
                     analysis previous-results)))))
    (if (and gptel-auto-experiment-use-subagents
             (fboundp 'gptel-benchmark-analyze)
             previous-results)
        (with-current-buffer analyze-buffer
          (gptel-auto-experiment--call-aux-subagent-with-retry
           "analyzer"
           (lambda (cb)
             (gptel-benchmark-analyze
              previous-results
              "Experiment patterns"
              cb))
           finalize))
      (funcall finalize nil))))

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
        (or (cond
             ((null content)
              (format "Empty or unreadable file: %s" file))
             ((condition-case err
                  (with-temp-buffer
                    (insert content)
                    (set-syntax-table emacs-lisp-mode-syntax-table)
                    (goto-char (point-min))
                    (while (progn
                             (forward-comment (point-max))
                             (< (point) (point-max)))
                      (push (read (current-buffer)) forms))
                    nil)
                (error (format "Syntax error in %s: %s" file err)))))
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
          (my/gptel--invoke-callback-safely callback result)
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

(defun gptel-auto-experiment--target-pending-changes-p (target &optional worktree)
  "Return non-nil when TARGET has pending git changes in WORKTREE."
  (let ((resolved-target target)
        (resolved-worktree worktree))
    (and (gptel-auto-workflow--non-empty-string-p resolved-target)
         (gptel-auto-workflow--non-empty-string-p resolved-worktree)
         (file-directory-p resolved-worktree)
         (let* ((default-directory resolved-worktree)
                (status-result
                 (gptel-auto-workflow--git-result
                  (format "git status --short -- %s"
                          (shell-quote-argument resolved-target))
                  30))
                (status-output (string-trim (car status-result))))
           (and (= (cdr status-result) 0)
                (not (string-empty-p status-output)))))))

(defun gptel-auto-experiment--executor-timeout-p (error-output)
  "Return non-nil when ERROR-OUTPUT reports an explicit executor timeout."
  (and (stringp error-output)
       (string-match-p
        "timed out after [0-9]+s\\(?: idle timeout ([-0-9.]+s total runtime)\\| total runtime\\)?\\.?"
        error-output)))

(defun gptel-auto-experiment--timeout-salvage-output (output prompt target &optional worktree)
  "Return synthetic executor output when timed-out error OUTPUT left real target edits.
PROMPT is the original executor prompt so the salvage path can preserve the
intended hypothesis. TARGET and WORKTREE identify the actual edited file."
  (when (and (gptel-auto-experiment--agent-error-p output)
             (gptel-auto-experiment--executor-timeout-p output)
             (gptel-auto-experiment--target-pending-changes-p target worktree))
    (let* ((raw-hypothesis (gptel-auto-experiment--extract-hypothesis prompt))
           (hypothesis
            (if (or (not (gptel-auto-workflow--non-empty-string-p raw-hypothesis))
                    (member raw-hypothesis '("Agent error" "No hypothesis stated")))
                (format "Timed-out executor left partial changes in %s for workflow evaluation"
                        target)
              raw-hypothesis)))
      (format
       (concat
        "HYPOTHESIS: %s\n"
        "CHANGED:\n"
        "- Executor timed out before returning a final response, but the worktree contains pending changes for %s.\n"
        "EVIDENCE:\n"
        "- Treat the concrete worktree diff below as the source of truth for this partial attempt.\n"
        "- Original timeout: %s\n"
        "VERIFY:\n"
        "- Run the normal benchmark and required tests against the changed worktree.\n"
        "COMMIT:\n"
        "- No commit was created before timeout; only keep the change if benchmark and review gates pass.\n"
       "Task completed with partial work ready for workflow evaluation.")
       hypothesis
       target
       (my/gptel--sanitize-for-logging output 200)))))

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
          (my/gptel--invoke-callback-safely
           callback (list :score 0 :passed nil
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

(defun gptel-auto-experiment--parse-comparator-winner (response)
  "Return comparator winner token parsed from RESPONSE, or nil."
  (when (stringp response)
    (let ((case-fold-search t))
      (cond
       ((string-match "^\\s-*A\\b" response) "A")
       ((string-match "^\\s-*B\\b" response) "B")
       ((string-match "^\\s-*tie\\b" response) "tie")))))

(defun gptel-auto-experiment--expected-comparator-winner (combined-before combined-after &optional threshold)
  "Return the winner implied by COMBINED-BEFORE vs COMBINED-AFTER.
THRESHOLD defaults to 0.005 and matches the comparator prompt rules."
  (let* ((decision-threshold (or threshold 0.005))
         (combined-delta (- combined-after combined-before)))
    (cond
     ((>= combined-delta decision-threshold) "B")
     ((<= combined-delta (- decision-threshold)) "A")
     (t "tie"))))

(defun gptel-auto-experiment--decision-gate
    (winner score-before score-after quality-before quality-after combined-before combined-after
            &optional threshold)
  "Return gated comparator decision metadata for WINNER.

The gate rejects any score regression, and also rejects score ties unless code
quality improves by at least
`gptel-auto-experiment-min-quality-gain-on-score-tie' while the combined score
still improves."
  (let* ((decision-threshold (or threshold 0.005))
         (score-delta (- score-after score-before))
         (quality-delta (- quality-after quality-before))
         (combined-delta (- combined-after combined-before)))
    (cond
     ((<= score-delta (- decision-threshold))
      (list :winner "A"
            :note "Rejected: score regressed"))
     ((< (abs score-delta) decision-threshold)
      (if (and (> combined-delta 0)
               (>= quality-delta gptel-auto-experiment-min-quality-gain-on-score-tie))
          (list :winner "B"
                :note (format "Kept: score tie with >= %.2f quality gain"
                              gptel-auto-experiment-min-quality-gain-on-score-tie))
        (list :winner "A"
              :note (if (<= combined-delta 0)
                        "Rejected: score tie without positive combined improvement"
                      (format "Rejected: score tie without >= %.2f quality gain"
                              gptel-auto-experiment-min-quality-gain-on-score-tie)))))
     (t
       (list :winner (if (string= winner "tie") "B" winner)
             :note (and (string= winner "tie")
                        "Kept: score improved despite combined tie"))))))

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
         (combined-after (+ (* 0.6 score-after) (* 0.4 quality-after)))
         (decision-threshold 0.005)
         (numeric-winner
          (gptel-auto-experiment--expected-comparator-winner
           combined-before combined-after decision-threshold))
         (gated-decision
          (gptel-auto-experiment--decision-gate
           numeric-winner
           score-before score-after
           quality-before quality-after
           combined-before combined-after
           decision-threshold))
         (expected-winner (plist-get gated-decision :winner))
         (gate-note (plist-get gated-decision :note)))
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
- B should win if combined score improved by ≥%.3f
- A should win if combined score decreased by ≥%.3f
- Tie if difference < %.3f

Output ONLY a single line: \"A\" or \"B\" or \"tie\"

Then on a new line, briefly explain why (1 sentence)."
                                      score-before quality-before combined-before
                                      score-after quality-after combined-after
                                      decision-threshold
                                      decision-threshold
                                      decision-threshold)))
           (with-current-buffer decide-buffer
             (gptel-auto-experiment--call-aux-subagent-with-retry
              "comparator"
              (lambda (cb)
                (gptel-benchmark-call-subagent
                 'comparator
                 "Compare experiment results"
                 compare-prompt
                 cb))
              (lambda (result)
                (let* ((response (if (stringp result) result (format "%S" result)))
                       (reported-winner (or (gptel-auto-experiment--parse-comparator-winner response)
                                            "unparsed"))
                       (winner expected-winner)
                       (override (not (string= reported-winner expected-winner)))
                       (keep (string= winner "B")))
                  (my/gptel--invoke-callback-safely
                   callback
                   (list :keep keep
                         :reasoning (format "%sWinner: %s | Score: %.2f → %.2f, Quality: %.2f → %.2f, Combined: %.2f → %.2f%s"
                                            (if override
                                                (format "Comparator override: %s -> %s | "
                                                        reported-winner winner)
                                              "")
                                            winner score-before score-after
                                            quality-before quality-after
                                            combined-before combined-after
                                            (if gate-note
                                                (format " | %s" gate-note)
                                              ""))
                         :improvement (list :score (- score-after score-before)
                                            :quality (- quality-after quality-before)
                                            :combined (- combined-after combined-before)))))))))
      (let ((winner expected-winner)
            (keep (string= expected-winner "B")))
        (my/gptel--invoke-callback-safely
         callback
         (list :keep keep
                :reasoning (format "Local: Winner: %s | Score: %.2f → %.2f, Quality: %.2f → %.2f, Combined: %.2f → %.2f%s"
                                   winner
                                   score-before score-after
                                   quality-before quality-after
                                   combined-before combined-after
                                   (if gate-note
                                       (format " | %s" gate-note)
                                     ""))
                :improvement (list :score (- score-after score-before)
                                   :quality (- quality-after quality-before)
                                   :combined (- combined-after combined-before))))))))

(defun gptel-auto-experiment--strong-grade-pass-p (grade-score grade-total)
  "Return non-nil when GRADE-SCORE reflects a strong pass.
GRADE-TOTAL can be nil when the grader omits an explicit denominator."
  (let ((score (if (numberp grade-score) grade-score 0)))
    (if (and (numberp grade-total) (> grade-total 0))
        (>= (/ (float score) grade-total) 0.85)
      (>= score 8))))

(defun gptel-auto-experiment--speculative-correctness-language-p (text)
  "Return non-nil when TEXT describes a speculative or clarity-only fix."
  (when (stringp text)
    (string-match-p
     (rx (or "potential "
             "possible "
             "hypothetical"
             "defensive hardening"
             "improves robustness"
             "enhances robustness"
             "without changing behavior"
             "without altering behavior"
             "improves clarity"
             "improves testability"
             "improve clarity"
             "improve testability"
             "clarity by "
             "making the control flow explicit"
             "consistent with "
             "reducing code duplication"
             "avoid unnecessary"
             "avoids unnecessary"
             "unnecessary timer cancellation"
             "unnecessary stop/start operations"
             "wasteful operations"
             "redundant timer cancellation"
             "edge case"
             "edge cases"
             "could "
             "might "
             "may "))
     text)))

(defun gptel-auto-experiment--grade-explanation-text (grade-details)
  "Return explanation-only text extracted from GRADE-DETAILS.
When the grader emits rubric bullets like `PASS - ...', ignore the rubric labels
and preserve only the explanatory text to avoid matching static prompt wording."
  (when (stringp grade-details)
    (let ((start 0)
          explanations)
      (while (string-match
              (rx (or "PASS - " "FAIL - ")
                  (group (*? (not (any "|")))))
              grade-details
              start)
        (let ((segment (string-trim (match-string 1 grade-details))))
          (unless (string-empty-p segment)
            (push segment explanations)))
        (setq start (match-end 0)))
      (if explanations
          (string-join (nreverse explanations) "\n")
        grade-details))))

(defun gptel-auto-experiment--grader-indicates-correctness-fix-p (grade-details)
  "Return non-nil when GRADE-DETAILS describes a real correctness fix.
Speculative or purely defensive hardening language does not count."
  (let ((grade-signals
         (gptel-auto-experiment--grade-explanation-text grade-details)))
    (when (stringp grade-signals)
    (let ((case-fold-search t))
      (and
       (string-match-p
        (rx (or (seq (or "fixes"
                         "fixed"
                         "resolves"
                         "resolved"
                         "corrects"
                         "corrected"
                         "eliminates"
                         "eliminated"
                         "addresses"
                         "addressed")
                     (* (not (any ".\n")))
                     (or "bug"
                         "bugs"
                         "runtime error"
                         "runtime errors"
                         "crash"
                         "crashes"
                         "security hole"
                         "security issue"
                         "state corruption"
                         "logic failure"
                         "correctness bug"
                         "correctness bugs"
                         "functional regression"
                         "functional regressions"))
                "genuine bug"
                "genuine bugs"
                 "actual functional bug"
                 "actual functional bugs"
                 "demonstrably buggy"))
        grade-signals)
        (not
         (gptel-auto-experiment--speculative-correctness-language-p
          grade-signals)))))))

(defun gptel-auto-experiment--normal-grade-details-p (grade-details)
  "Return non-nil when GRADE-DETAILS is a normal rubric result."
  (and (stringp grade-details)
       (string-match-p "Grader result for task:[[:space:]]*Grade output" grade-details)
       (string-match-p "SUMMARY:[[:space:]]*SCORE:" grade-details)))

(defun gptel-auto-experiment--promote-correctness-fix-decision
    (decision tests-passed grade-score grade-total grade-details &optional hypothesis)
  "Return DECISION or a promoted keep decision for high-confidence ties.
Promotion is allowed only for non-regressing ties with passing tests, some
positive quality/combined improvement, and strong grader evidence of a real
correctness fix."
  (let* ((improvement (and (listp decision) (plist-get decision :improvement)))
         (decision-threshold 0.005)
         (score-delta (if (listp improvement)
                          (or (plist-get improvement :score) 0)
                        0))
         (quality-delta (if (listp improvement)
                            (or (plist-get improvement :quality) 0)
                          0))
         (combined-delta (if (listp improvement)
                             (or (plist-get improvement :combined) 0)
                           0))
         (reasoning (and (listp decision) (plist-get decision :reasoning)))
          (correctness-fix-p
           (gptel-auto-experiment--grader-indicates-correctness-fix-p
            grade-details))
         (speculative-hypothesis-p
          (gptel-auto-experiment--speculative-correctness-language-p
           hypothesis))
         (override-note
           "Override: keep non-regressing high-confidence tie with passing tests"))
    (if (or (not (listp decision))
            (plist-get decision :keep)
            (not tests-passed)
            (<= score-delta (- decision-threshold))
            (<= quality-delta 0)
            (<= combined-delta 0)
            (not correctness-fix-p)
            speculative-hypothesis-p
            (not (gptel-auto-experiment--strong-grade-pass-p
                  grade-score grade-total)))
        decision
      (let ((promoted (copy-sequence decision)))
        (setq promoted (plist-put promoted :keep t))
        (plist-put
         promoted
         :reasoning
         (if (and (stringp reasoning)
                  (not (string-match-p (regexp-quote override-note) reasoning)))
             (format "%s | %s" override-note reasoning)
           override-note))))))

;;; Prompt Building

(defconst gptel-auto-experiment-focused-target-byte-threshold 32768
  "Byte size above which prompts require a controller-selected starting symbol.
This covers medium-large targets that are prone to inspection-thrash before the
first edit, even when they are smaller than the large-target guidance band.")

(defconst gptel-auto-experiment-large-target-byte-threshold 60000
  "Byte size above which experiment prompts add large-target advisory guidance.")

(defconst gptel-auto-experiment-large-target-focus-token-weights
  '(("callback" . 6.0)
    ("timer" . 5.0)
    ("safe" . 5.0)
    ("validate" . 4.0)
    ("check" . 4.0)
    ("status" . 4.0)
    ("build" . 3.0)
    ("prompt" . 3.0)
    ("state" . 3.0)
    ("retry" . 3.0)
    ("sync" . 2.0)
    ("select" . 2.0)
    ("focus" . 2.0)
    ("buffer" . 2.0)
    ("worktree" . 1.0)
    ("stage" . 1.0))
  "Name-token weights for controller-selected large-target focus symbols.")

(defconst gptel-auto-experiment-large-target-focus-max-candidates 8
  "Maximum ranked large-target focus candidates to rotate across experiments.")

(defun gptel-auto-experiment--target-byte-size (target-full-path)
  "Return the byte size for TARGET-FULL-PATH, or nil when unavailable."
  (let ((attrs (and (stringp target-full-path)
                    (ignore-errors (file-attributes target-full-path)))))
    (when attrs
      (file-attribute-size attrs))))

(defun gptel-auto-experiment--collect-top-level-definitions (target-full-path)
  "Return top-level definitions from TARGET-FULL-PATH as plists."
  (when (and (stringp target-full-path)
             (file-readable-p target-full-path))
    (with-temp-buffer
      (insert-file-contents target-full-path)
      (let ((definition-rx
             "^(\\(\\(?:cl-defun\\|defun\\|defsubst\\|defmacro\\|cl-defmethod\\|defvar\\|defconst\\|defcustom\\)\\)\\s-+\\([^()\n\t ]+\\)")
            definitions
            total-lines)
        (goto-char (point-min))
        (while (re-search-forward definition-rx nil t)
          (push (list :kind (match-string 1)
                      :name (match-string 2)
                      :start-line (line-number-at-pos (match-beginning 0)))
                definitions))
        (setq definitions (nreverse definitions)
              total-lines (line-number-at-pos (point-max)))
        (cl-loop for current in definitions
                 for next = (cadr (memq current definitions))
                 collect
                 (let* ((start-line (plist-get current :start-line))
                        (end-line (if next
                                      (1- (plist-get next :start-line))
                                    total-lines))
                        (size-lines (1+ (- end-line start-line)))
                        (candidate (copy-sequence current)))
                   (setq candidate (plist-put candidate :end-line end-line))
                   (plist-put candidate :size-lines size-lines)))))))

(defun gptel-auto-experiment--large-target-focus-score (candidate)
  "Return a deterministic focus score for large-target CANDIDATE."
  (let* ((name (downcase (or (plist-get candidate :name) "")))
         (size (or (plist-get candidate :size-lines) 0))
         (score 0.0))
    (dolist (entry gptel-auto-experiment-large-target-focus-token-weights)
      (when (string-match-p (car entry) name)
        (setq score (+ score (cdr entry)))))
    (setq score (+ score (max 0.0 (- 8.0 (/ (abs (- size 24)) 4.0)))))
    (when (string-prefix-p "my/" name)
      (setq score (+ score 1.5)))
    (when (string-match-p "--" name)
      (setq score (+ score 0.5)))
    score))

(defun gptel-auto-experiment--select-large-target-focus (target-full-path experiment-id)
  "Return a controller-selected focus candidate for TARGET-FULL-PATH.
Rotates across the top-ranked candidates using EXPERIMENT-ID."
  (let* ((candidates
          (cl-loop for candidate in (gptel-auto-experiment--collect-top-level-definitions
                                     target-full-path)
                   when (and (member (plist-get candidate :kind)
                                     '("defun" "cl-defun" "defsubst"))
                             (<= 8 (or (plist-get candidate :size-lines) 0) 120))
                   collect (plist-put (copy-sequence candidate)
                                      :score
                                      (gptel-auto-experiment--large-target-focus-score
                                       candidate))))
         (ranked (sort candidates
                       (lambda (a b)
                         (let ((score-a (or (plist-get a :score) 0.0))
                               (score-b (or (plist-get b :score) 0.0)))
                           (if (= score-a score-b)
                               (< (or (plist-get a :start-line) most-positive-fixnum)
                                  (or (plist-get b :start-line) most-positive-fixnum))
                             (> score-a score-b))))))
         (shortlist (seq-take ranked gptel-auto-experiment-large-target-focus-max-candidates)))
    (when shortlist
      (nth (mod (max 0 (1- (or experiment-id 1)))
                (length shortlist))
           shortlist))))

(defun gptel-auto-experiment--inspection-thrash-result-p (result)
  "Return non-nil when RESULT records an inspection-thrash failure."
  (cl-some
   (lambda (text)
     (and (stringp text)
          (string-match-p "inspection-thrash aborted" text)))
   (list (plist-get result :error)
         (plist-get result :agent-output)
         (plist-get result :grader-reason)
         (plist-get result :comparator-reason))))

(defun gptel-auto-experiment--needs-inspection-thrash-recovery-p (previous-results)
  "Return non-nil when PREVIOUS-RESULTS include inspection-thrash failures."
  (cl-some #'gptel-auto-experiment--inspection-thrash-result-p previous-results))

(defun gptel-auto-experiment--retry-history (previous-results result)
  "Return retry history from PREVIOUS-RESULTS plus any durable guidance in RESULT.
Retries should learn from inspection-thrash failures immediately so the next
prompt activates the focused recovery contract."
  (if (and result
           (gptel-auto-experiment--inspection-thrash-result-p result))
      (append previous-results (list result))
    previous-results))

(defun gptel-auto-experiment-build-prompt (target experiment-id max-experiments analysis baseline
                                                  &optional previous-results)
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
         (target-full-path (expand-file-name target worktree-path))
         (target-bytes (gptel-auto-experiment--target-byte-size target-full-path))
         (recovery-p
          (gptel-auto-experiment--needs-inspection-thrash-recovery-p previous-results))
         (follow-up-focus-p
           (and previous-results (not recovery-p)))
         (focused-target-p
           (and (numberp target-bytes)
                (>= target-bytes gptel-auto-experiment-focused-target-byte-threshold)))
          (large-target-p
             (and (numberp target-bytes)
                   (>= target-bytes gptel-auto-experiment-large-target-byte-threshold)))
          (preemptive-focus-contract-p
           (and focused-target-p
                (not previous-results)))
         (focus-candidate
             (when focused-target-p
               (gptel-auto-experiment--select-large-target-focus target-full-path experiment-id)))
          (focused-target-guidance
           (when (and focused-target-p
                      (not preemptive-focus-contract-p)
                      (not large-target-p))
             (concat "## Focused Target Guidance\n"
                     (format "This target is medium-large (%d bytes). Start from one concrete function or variable before broader file surveys.\n"
                             target-bytes)
                    (when focus-candidate
                      (format "- Begin at `%s` or a direct caller/callee.\n"
                              (plist-get focus-candidate :name)))
                    "- Prefer focused Grep or narrow Read before broader Code_Map surveys.\n"
                    "- Make the first edit before exploring a second subsystem.\n\n")))
         (large-target-guidance
           (when large-target-p
             (concat "## Large Target Guidance\n"
                     (format "This target is large (%d bytes). Start from one concrete function or variable instead of surveying the whole file.\n"
                            target-bytes)
                    (when focus-candidate
                      (format "- Begin at `%s` or a direct caller/callee.\n"
                              (plist-get focus-candidate :name)))
                    "- Prefer focused Grep or narrow Read before broader Code_Map surveys.\n"
                    "- Make the first edit before exploring a second subsystem.\n\n")))
         (focus-line
          (format "FOCUS: %s"
                  (or (plist-get focus-candidate :name)
                      "<one concrete function or variable>")))
         (controller-focus
           (when focus-candidate
             (format "## Controller-Selected Starting Symbol\n- Symbol: `%s`\n- Kind: %s\n- Approx lines: %d-%d (%d lines)\n- Reason: controller-selected small or medium helper in a medium or large file; start here or at a direct caller/callee.\n\n"
                     (plist-get focus-candidate :name)
                     (plist-get focus-candidate :kind)
                     (plist-get focus-candidate :start-line)
                    (plist-get focus-candidate :end-line)
                    (plist-get focus-candidate :size-lines))))
         (mandatory-focus-contract
          (when (or recovery-p preemptive-focus-contract-p)
            (concat "## Mandatory Focus Contract\n"
                     (cond
                      (recovery-p
                       "A previous attempt on this target already failed with inspection-thrash.\n")
                      (preemptive-focus-contract-p
                       (format "This target is %s and prone to inspection-thrash before the first edit.\n"
                               (if large-target-p "large" "medium-large"))))
                    (when focused-target-p
                      (format "This target is %s (%d bytes). Broad file surveys are likely to fail.\n"
                              (if large-target-p "large" "medium-large")
                              target-bytes))
                    "Follow this exact opening sequence:\n"
                    (format "1. The second line after HYPOTHESIS must be exactly `%s`.\n"
                            focus-line)
                    "2. Do NOT use Code_Map on the whole file.\n"
                    "3. Use at most 3 read-only tool calls, all on that same symbol or its direct callers/callees.\n"
                    "4. Your next tool call after those reads must be a write-capable tool on that same symbol.\n"
                    "5. Do not inspect a second subsystem before the first edit exists.\n\n")))
         (follow-up-focus-contract
          (when follow-up-focus-p
            (concat "## Follow-up Focus Contract\n"
                    "This is not the first attempt on this target. Do not resurvey the whole file.\n"
                    (format "The second line after HYPOTHESIS must be exactly `%s`.\n"
                            focus-line)
                    "Do NOT use Code_Map on the whole file.\n"
                    "Use at most 3 read-only tool calls, all on that same symbol or its direct callers/callees.\n"
                    "Your next tool call after those reads must be a write-capable tool on that same symbol.\n"
                    "Prefer the symbol from the previous attempt, prior analysis, or a direct caller/callee.\n"
                    "Do not inspect a second subsystem before the first edit exists.\n\n"))))
    (format "You are running experiment %d of %d to optimize %s.

## Working Directory
%s

## Target File (full path)
%s

%s

%s

%s

%s

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
2. If a Controller-Selected Starting Symbol or any Focus Contract is present, line 2 must be exactly `%s`
3. If a Mandatory Focus Contract is present, obey it exactly; otherwise if a Follow-up Focus Contract is present, obey it before broader exploration; otherwise start from one concrete function or variable and prefer focused Grep or narrow Read before broader Code_Map surveys
4. Read only focused line ranges from the target file using its full path; avoid reading the entire file unless absolutely necessary
5. IDENTIFY a real code issue (bug, performance, duplication, missing validation)
6. Implement the CODE change minimally using Edit tool
7. Run tests to verify: ./scripts/verify-nucleus.sh && ./scripts/run-tests.sh
8. DO NOT run git add, git commit, git push, or stage changes yourself.
   Leave edits uncommitted in the worktree; the auto-workflow controller
   handles grading, commit creation, review, and staging.
9. FINAL RESPONSE must include:
   - CHANGED: exact file path(s) and function/variable names touched
   - EVIDENCE: 1-2 concrete code snippets or diff hunks showing the real edit
   - VERIFY: exact command(s) run and whether they passed or failed
   - COMMIT: always \"not committed\" (workflow controller handles commits)
10. End the final response with: Task completed
11. NEVER reply with only \"Done\", only a commit message, or a vague success claim

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
              (or controller-focus "")
              (or focused-target-guidance "")
              (or large-target-guidance "")
              (or mandatory-focus-contract "")
              (or follow-up-focus-contract "")
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
            (/ gptel-auto-experiment-time-budget 60)
            focus-line)))

;;; TSV Logging (Explainable)

(defun gptel-auto-experiment--tsv-escape (str)
  "Escape STR for TSV format (replace newlines/tabs with spaces)."
  (when str
    (let ((s (if (stringp str) str (format "%s" str))))
      (replace-regexp-in-string "[\t\n\r]+" " | " s))))

(defun gptel-auto-experiment--tsv-decision-token (value)
  "Return a normalized TSV decision token extracted from VALUE, or nil."
  (when (stringp value)
    (let ((normalized (string-trim value)))
      (when (string-prefix-p ":" normalized)
        (setq normalized (substring normalized 1)))
      (when (string-match-p "\\`[[:lower:]][[:lower:]-]*\\'" normalized)
        normalized))))

(defun gptel-auto-experiment--tsv-decision-label (experiment)
  "Return the durable TSV decision label for EXPERIMENT."
  (or (and (gptel-auto-workflow--plist-get experiment :kept nil)
           "kept")
      (and (gptel-auto-experiment--inspection-thrash-result-p experiment)
           "inspection-thrash")
      (and (gptel-auto-workflow--plist-get experiment :validation-error nil)
           "validation-failed")
      (gptel-auto-experiment--tsv-decision-token
       (gptel-auto-workflow--plist-get experiment :decision nil))
      (gptel-auto-experiment--tsv-decision-token
       (gptel-auto-workflow--plist-get experiment :comparator-reason nil))
      (gptel-auto-experiment--tsv-decision-token
       (gptel-auto-workflow--plist-get experiment :grader-reason nil))
      "discarded"))

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
  (let* ((file (gptel-auto-workflow--ensure-results-file run-id))
         (agent-output (gptel-auto-workflow--plist-get experiment :agent-output ""))
         (truncated-output (gptel-auto-experiment--tsv-escape
                            (truncate-string-to-width agent-output 500 nil nil "..."))))
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
                      (gptel-auto-experiment--tsv-decision-label experiment)
                      (gptel-auto-workflow--plist-get experiment :duration 0)
                      (gptel-auto-workflow--plist-get experiment :grader-quality "?")
                      (gptel-auto-experiment--tsv-escape (gptel-auto-workflow--plist-get experiment :grader-reason "N/A"))
                      (gptel-auto-experiment--tsv-escape (gptel-auto-workflow--plist-get experiment :comparator-reason "N/A"))
                      (gptel-auto-experiment--tsv-escape (gptel-auto-workflow--plist-get experiment :analyzer-patterns "N/A"))
                      truncated-output))
      (write-region (point-min) (point-max) file))
    (gptel-auto-workflow--sync-live-kept-count run-id file)))

(defun gptel-auto-experiment--make-kept-result-callback (run-id exp-result log-fn callback)
  "Return idempotent callback that finalizes EXP-RESULT after optional staging.

When invoked without arguments, or with a non-nil first argument, log
EXP-RESULT as kept. When invoked with nil, downgrade the result so staging-flow
failures do not masquerade as published kept results. When a second argument is
supplied on failure, use it as the downgrade reason."
  (gptel-auto-workflow--make-idempotent-callback
   (lambda (&rest success-args)
      (let* ((staging-reported-p (not (null success-args)))
             (staging-succeeded (car-safe success-args))
             (failure-reason-arg (cadr success-args))
             (failure-reason
              (cond
               ((stringp failure-reason-arg)
                failure-reason-arg)
               ((and failure-reason-arg
                     (symbolp failure-reason-arg))
                (symbol-name failure-reason-arg))
               (t
                "staging-flow-failed")))
             (final-result
              (if (or (not staging-reported-p) staging-succeeded)
                  exp-result
                (let ((failed-result (and (listp exp-result)
                                           (plist-put (copy-sequence exp-result) :kept nil))))
                  (when failed-result
                    (plist-put failed-result :comparator-reason failure-reason))
                  (or failed-result exp-result)))))
        (when (functionp log-fn)
          (funcall log-fn run-id final-result))
        (when (and callback (functionp callback))
          (funcall callback final-result))))))

(defun gptel-auto-workflow--invoke-staging-completion (callback success &optional reason)
  "Invoke staging CALLBACK with SUCCESS and optional REASON.

Older completion callbacks only accept a single success flag. Newer callbacks
may also accept a second argument describing why staging downgraded an
experiment that had previously looked keep-worthy."
  (when (functionp callback)
    (let* ((arity (ignore-errors (func-arity callback)))
           (max-args (cdr-safe arity)))
      (if (or (eq max-args 'many)
              (and (integerp max-args) (>= max-args 2)))
          (funcall callback success reason)
        (funcall callback success)))))

(defun gptel-auto-workflow--make-idempotent-staging-completion (callback)
  "Return idempotent staging completion wrapper preserving CALLBACK arity."
  (let ((called nil)
        (arity (ignore-errors (func-arity callback))))
    (if (or (eq (cdr-safe arity) 'many)
            (and (integerp (cdr-safe arity))
                 (>= (cdr-safe arity) 2)))
        (lambda (success &optional reason)
          (unless called
            (setq called t)
            (funcall callback success reason)))
      (lambda (success)
        (unless called
          (setq called t)
          (funcall callback success))))))

;;; Error Analysis and Adaptive Workflow

(defvar gptel-auto-experiment--api-error-count 0
  "Count of API errors in current run.")

(defvar gptel-auto-experiment--api-error-threshold 3
  "Threshold of API errors before reducing or stopping future experiments.")

(defvar gptel-auto-experiment--quota-exhausted nil
  "Non-nil when provider quota exhaustion should stop the current workflow.")

(defun gptel-auto-experiment--error-snippet (agent-output &optional max-len)
  "Extract safe snippet from AGENT-OUTPUT for logging.
MAX-LEN defaults to 200 characters. Handles nil/empty strings safely."
  (if (and (stringp agent-output) (> (length agent-output) 0))
      (my/gptel--sanitize-for-logging agent-output (or max-len 200))
    ""))

(defvar gptel-auto-experiment-max-retries 2
  "Maximum retries for executor on transient errors.")

(defvar gptel-auto-experiment-max-grader-retries 2
  "Maximum local retries for transient grader failures.
These retries reuse the successful executor output instead of rerunning the
entire experiment. Two retries let the grader advance past one failing
fallback backend before giving up on otherwise-good executor output.")

(defvar gptel-auto-experiment-max-aux-subagent-retries 2
  "Maximum local retries for transient analyzer/comparator failures.
These retries keep the current experiment alive while headless provider
failover advances past transient timeout or provider-pressure failures.")

(defvar gptel-auto-experiment-retry-delay 5
  "Seconds to wait between retries.")

(defvar gptel-auto-experiment-rate-limit-max-retry-delay 60
  "Maximum seconds between retries for rate-limited API failures.")

(defcustom gptel-auto-workflow-headless-subagent-fallbacks
  '(("MiniMax" . "minimax-m2.7-highspeed")
    ("moonshot" . "kimi-k2.6")
    ("DashScope" . "qwen3.6-plus")
    ("DeepSeek" . "deepseek-reasoner")
    ("CF-Gateway" . "@cf/moonshotai/kimi-k2.6")
    ("Gemini" . "gemini-3.1-pro-preview"))
  "Ordered backend/model fallbacks for headless auto-workflow subagents.

Each entry is (BACKEND . MODEL), where BACKEND matches the agent preset backend
string and MODEL is the model string to use with that backend. The workflow
tries backends in order when the primary is unavailable or rate-limited."
  :type '(repeat (cons (string :tag "Backend")
                       (string :tag "Model")))
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-headless-fallback-agents
  '("analyzer" "comparator" "executor" "grader" "reviewer")
  "Headless subagents that should use the fallback provider list.

Headless workflow runs prefer MiniMax as the workhorse, falling back to
DashScope and others when rate-limited or unavailable."
  :type '(repeat string)
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-executor-rate-limit-fallbacks
  '(("MiniMax" . "minimax-m2.7-highspeed")
    ("moonshot" . "kimi-k2.6")
    ("DashScope" . "qwen3.6-plus")
    ("DeepSeek" . "deepseek-reasoner")
    ("CF-Gateway" . "@cf/moonshotai/kimi-k2.6")
    ("Gemini" . "gemini-3.1-pro-preview"))
  "Ordered backend/model fallbacks for executor after provider rate limits.

Headless executor prefers MiniMax by default. When the active executor backend
returns a rate-limit error during a headless run, later retries in that same
run can advance through this list instead of repeatedly hammering the same provider."
  :type '(repeat (cons (string :tag "Backend")
                       (string :tag "Model")))
  :group 'gptel-tools-agent)

(defconst gptel-auto-workflow--legacy-headless-fallback-agents
  '("analyzer" "grader" "reviewer")
  "Previous default for `gptel-auto-workflow-headless-fallback-agents'.")

(defconst gptel-auto-workflow--previous-headless-fallback-agents
  '("analyzer" "executor" "grader" "reviewer")
  "Prior runtime default for `gptel-auto-workflow-headless-fallback-agents'.")

(defconst gptel-auto-workflow--legacy-headless-subagent-fallbacks
  '(("MiniMax" . "minimax-m2.7-highspeed")
    ("DashScope" . "qwen3.6-plus")
    ("DeepSeek" . "deepseek-reasoner")
    ("CF-Gateway" . "@cf/moonshotai/kimi-k2.6")
    ("Gemini" . "gemini-3.1-pro-preview"))
  "Previous default for `gptel-auto-workflow-headless-subagent-fallbacks'.")

(defconst gptel-auto-workflow--current-headless-subagent-fallbacks
  '(("MiniMax" . "minimax-m2.7-highspeed")
    ("moonshot" . "kimi-k2.6")
    ("DashScope" . "qwen3.6-plus")
    ("DeepSeek" . "deepseek-reasoner")
    ("CF-Gateway" . "@cf/moonshotai/kimi-k2.6")
    ("Gemini" . "gemini-3.1-pro-preview"))
  "Current runtime default for `gptel-auto-workflow-headless-subagent-fallbacks'.")

(defconst gptel-auto-workflow--legacy-executor-rate-limit-fallbacks
  '(("DeepSeek" . "deepseek-reasoner")
    ("CF-Gateway" . "@cf/moonshotai/kimi-k2.6")
    ("DashScope" . "qwen3.6-plus")
    ("Gemini" . "gemini-3.1-pro-preview"))
  "Previous default for `gptel-auto-workflow-executor-rate-limit-fallbacks'.")

(defconst gptel-auto-workflow--current-headless-fallback-agents
  '("analyzer" "comparator" "executor" "grader" "reviewer")
  "Current runtime default for `gptel-auto-workflow-headless-fallback-agents'.")

(defconst gptel-auto-workflow--current-executor-rate-limit-fallbacks
  '(("MiniMax" . "minimax-m2.7-highspeed")
    ("moonshot" . "kimi-k2.6")
    ("DashScope" . "qwen3.6-plus")
    ("DeepSeek" . "deepseek-reasoner")
    ("CF-Gateway" . "@cf/moonshotai/kimi-k2.6")
    ("Gemini" . "gemini-3.1-pro-preview"))
  "Current runtime default for `gptel-auto-workflow-executor-rate-limit-fallbacks'.")

(defvar gptel-auto-workflow--runtime-subagent-provider-overrides nil
  "Per-run provider overrides activated by live workflow failures.

Each element is (AGENT-TYPE . (BACKEND . MODEL)). These overrides are cleared
at run start and whenever workflow state is force-reset.")

(defvar gptel-auto-workflow--rate-limited-backends nil
  "Per-run backend rate-limit state with timestamps.

Each element is (BACKEND . TIMESTAMP). BACKEND is a string, TIMESTAMP
is the time when it was marked rate-limited (via current-time).
After the cooldown period expires, the backend becomes available again.

Format: ((\"MiniMax\" . 415500.123) (\"DeepSeek\" . 415500.456))")

(defcustom gptel-auto-workflow-rate-limit-cooldown-seconds 7200
  "Seconds to wait before retrying a rate-limited backend.
Default 7200 = 2 hours. After this period, the backend becomes available
again for new attempts. Set to 3600 for 1 hour, 14400 for 4 hours."
  :type 'integer
  :group 'gptel-tools-agent)

(defvar gptel-auto-workflow--backend-failure-counts nil
  "Per-run failure count per backend before marking as rate-limited.

Each element is (BACKEND . COUNT). Backend is only added to
rate-limited-backends after reaching `gptel-auto-workflow--backend-rate-limit-failure-threshold'
consecutive failures. This prevents single errors from permanently skipping a backend.")

(defcustom gptel-auto-workflow-backend-rate-limit-failure-threshold 10
  "Number of consecutive failures before a backend is marked as rate-limited.
Lower values make fallback trigger faster but risk skipping good backends.
Higher values try harder on the primary backend before falling back.
With MiniMax quota at 10%, set high to prefer MiniMax over fallback providers."
  :type 'integer
  :group 'gptel-tools-agent)

(defconst gptel-auto-workflow--backend-key-hosts
  '(("MiniMax" . "api.minimaxi.com")
    ("DeepSeek" . "api.deepseek.com")
    ("Gemini" . "generativelanguage.googleapis.com")
    ("CF-Gateway" . "gateway.ai.cloudflare.com")
    ("DashScope" . "coding.dashscope.aliyuncs.com")
    ("moonshot" . "api.kimi.com"))
  "Map gptel backend names to auth-source hosts for workflow failover.")

(defconst gptel-auto-workflow--backend-object-vars
  '(("MiniMax" . gptel--minimax)
    ("DeepSeek" . gptel--deepseek)
    ("Gemini" . gptel--gemini)
    ("CF-Gateway" . gptel--cf-gateway)
    ("DashScope" . gptel--dashscope)
    ("moonshot" . gptel--moonshot))
  "Map gptel backend names to the corresponding backend object variables.")

(defun gptel-auto-workflow--backend-available-p (backend-name)
  "Return non-nil when BACKEND-NAME has credentials configured."
  (let ((host (alist-get backend-name gptel-auto-workflow--backend-key-hosts
                         nil nil #'string=)))
    (and host
         (fboundp 'my/gptel-api-key)
         (gptel-auto-workflow--non-empty-string-p
          (my/gptel-api-key host)))))

(defun gptel-auto-workflow--headless-provider-override-active-p ()
  "Return non-nil when headless auto-workflow provider override should apply."
  (and (bound-and-true-p gptel-auto-workflow--headless)
       (bound-and-true-p gptel-auto-workflow-persistent-headless)
       (bound-and-true-p gptel-auto-workflow--current-project)))

(defun gptel-auto-workflow--backend-object (backend-name)
  "Return the backend object for BACKEND-NAME, or nil when unavailable."
  (when-let* ((var (alist-get backend-name gptel-auto-workflow--backend-object-vars
                              nil nil #'string=))
              ((boundp var)))
    (symbol-value var)))

(defun gptel-auto-workflow--custom-var-user-customized-p (symbol)
  "Return non-nil when SYMBOL has an explicit Customize override."
  (or (get symbol 'saved-value)
      (get symbol 'customized-value)
      (get symbol 'theme-value)))

(defun gptel-auto-workflow--migrate-legacy-provider-defaults ()
  "Refresh known legacy in-memory provider defaults after hot reloads.

Long-lived daemons can keep pre-fix `defcustom' values even after the source
defines newer defaults.  Migrate only the exact legacy defaults, and only when
the user has not explicitly customized the variable."
  (let (migrated)
    (unless (gptel-auto-workflow--custom-var-user-customized-p
             'gptel-auto-workflow-headless-fallback-agents)
      (when (or (equal gptel-auto-workflow-headless-fallback-agents
                       gptel-auto-workflow--legacy-headless-fallback-agents)
                (equal gptel-auto-workflow-headless-fallback-agents
                       gptel-auto-workflow--previous-headless-fallback-agents))
        (setq gptel-auto-workflow-headless-fallback-agents
              (copy-tree gptel-auto-workflow--current-headless-fallback-agents))
        (push 'gptel-auto-workflow-headless-fallback-agents migrated)))
    (unless (gptel-auto-workflow--custom-var-user-customized-p
             'gptel-auto-workflow-headless-subagent-fallbacks)
      (when (equal gptel-auto-workflow-headless-subagent-fallbacks
                   gptel-auto-workflow--legacy-headless-subagent-fallbacks)
        (setq gptel-auto-workflow-headless-subagent-fallbacks
              (copy-tree gptel-auto-workflow--current-headless-subagent-fallbacks))
        (push 'gptel-auto-workflow-headless-subagent-fallbacks migrated)))
    (unless (gptel-auto-workflow--custom-var-user-customized-p
             'gptel-auto-workflow-executor-rate-limit-fallbacks)
      (when (equal gptel-auto-workflow-executor-rate-limit-fallbacks
                   gptel-auto-workflow--legacy-executor-rate-limit-fallbacks)
        (setq gptel-auto-workflow-executor-rate-limit-fallbacks
              (copy-tree
               gptel-auto-workflow--current-executor-rate-limit-fallbacks))
        (push 'gptel-auto-workflow-executor-rate-limit-fallbacks migrated)))
    (unless (gptel-auto-workflow--custom-var-user-customized-p
             'gptel-auto-experiment-validation-retry-active-grace)
      (when (= gptel-auto-experiment-validation-retry-active-grace
               gptel-auto-workflow--legacy-validation-retry-active-grace)
        (setq gptel-auto-experiment-validation-retry-active-grace
              gptel-auto-workflow--current-validation-retry-active-grace)
        (push 'gptel-auto-experiment-validation-retry-active-grace migrated)))
    (when migrated
      (setq migrated (nreverse migrated))
      (message "[auto-workflow] Refreshed legacy fallback defaults: %s"
               (mapconcat #'symbol-name migrated ", ")))
    migrated))

(defun gptel-auto-workflow--backend-model-symbol (backend model-name)
  "Return MODEL-NAME as a supported symbol for BACKEND.

If MODEL-NAME is not yet listed on BACKEND, append it so hot-reloaded daemons
can use newer models without a restart."
  (let ((model (if (symbolp model-name) model-name (intern model-name))))
    (when (and backend (fboundp 'gptel-backend-models))
      (let ((models (gptel-backend-models backend)))
        (unless (memq model models)
          (setf (gptel-backend-models backend) (append models (list model))))))
    model))

(defun gptel-auto-workflow--clear-runtime-subagent-provider-overrides ()
  "Reset per-run provider failover state."
  (setq gptel-auto-workflow--runtime-subagent-provider-overrides nil
        gptel-auto-workflow--rate-limited-backends nil
        gptel-auto-workflow--backend-failure-counts nil))

(defun gptel-auto-workflow--rate-limit-failover-candidates (agent-type)
  "Return fallback provider candidates for AGENT-TYPE after rate limiting."
  (cond
   ((not (stringp agent-type)) nil)
   ((string= agent-type "executor")
    gptel-auto-workflow-executor-rate-limit-fallbacks)
   ((member agent-type gptel-auto-workflow-headless-fallback-agents)
    gptel-auto-workflow-headless-subagent-fallbacks)))

(defun gptel-auto-workflow--agent-base-preset (agent-type)
  "Return the current base preset plist for AGENT-TYPE, or nil when unavailable."
  (when-let* ((agent-type (and (stringp agent-type) agent-type))
              (agent-config (and (boundp 'gptel-agent--agents)
                                 (assoc agent-type gptel-agent--agents))))
    (append (list :include-reasoning nil
                  :use-tools t
                  :use-context nil
                  :stream my/gptel-subagent-stream)
            (copy-sequence (cdr agent-config)))))

(defun gptel-auto-workflow--runtime-subagent-provider-override (agent-type)
  "Return the active per-run provider override for AGENT-TYPE, if any."
  (alist-get agent-type
             gptel-auto-workflow--runtime-subagent-provider-overrides
             nil nil #'string=))

(defun gptel-auto-workflow--backend-rate-limited-p (backend-name)
  "Return non-nil when BACKEND-NAME is currently rate-limited.
A backend is considered rate-limited if it was marked within the
cooldown period (`gptel-auto-workflow-rate-limit-cooldown-seconds').
After the cooldown expires, the backend becomes available again."
  (when (stringp backend-name)
    (when-let* ((entry (cl-assoc backend-name gptel-auto-workflow--rate-limited-backends
                                 :test #'string=))
                (timestamp (cdr entry))
                (elapsed (- (float-time (current-time)) timestamp))
                ((>= elapsed gptel-auto-workflow-rate-limit-cooldown-seconds)))
      (setq gptel-auto-workflow--rate-limited-backends
            (cl-remove-if (lambda (e)
                            (and (consp e) (string= (car e) backend-name)))
                          gptel-auto-workflow--rate-limited-backends))
      nil)
    (cl-assoc backend-name gptel-auto-workflow--rate-limited-backends
               :test #'string=)))

(defun gptel-auto-workflow--rate-limited-backend-names ()
  "Return list of backend names currently rate-limited.
Extracts just the backend names from the timestamp alist."
  (mapcar #'car gptel-auto-workflow--rate-limited-backends))

(defun gptel-auto-workflow--preset-backend-name (backend)
  "Return a readable backend name for BACKEND."
  (cond
   ((stringp backend) backend)
   ((and backend (fboundp 'gptel-backend-name))
    (gptel-backend-name backend))
   (t nil)))

(defun gptel-auto-workflow--model-max-output-tokens (model-id)
  "Return the documented max output tokens for MODEL-ID, or nil when unknown."
  (when (require 'gptel-ext-context-cache nil t)
    (when-let* (((fboundp 'my/gptel-get-model-metadata))
                (meta (my/gptel-get-model-metadata model-id))
                (max-output
                 (if (fboundp 'my/gptel--plist-get)
                     (my/gptel--plist-get meta :max-output nil)
                   (plist-get meta :max-output)))
                ((integerp max-output))
                ((> max-output 0)))
      max-output)))

(defun gptel-auto-workflow--first-available-provider-candidate (candidates &optional excluded-backends)
  "Return the first available entry from CANDIDATES, skipping EXCLUDED-BACKENDS.

EXCLUDED-BACKENDS may be nil, a backend name string, or a list of backend
name strings."
  (let ((excluded
         (cond
          ((null excluded-backends) nil)
          ((listp excluded-backends) excluded-backends)
          (t (list excluded-backends)))))
    (seq-find
     (lambda (entry)
       (and (not (seq-some (lambda (backend-name)
                             (and (stringp backend-name)
                                  (string= (car entry) backend-name)))
                           excluded))
            (gptel-auto-workflow--backend-available-p (car entry))))
     candidates)))

(defun gptel-auto-workflow--runtime-provider-failover-candidate (agent-type preset)
  "Return the active provider-wide fallback candidate for AGENT-TYPE and PRESET."
  (let* ((current-backend
          (gptel-auto-workflow--preset-backend-name
           (plist-get preset :backend)))
         (candidates
          (gptel-auto-workflow--rate-limit-failover-candidates agent-type)))
    (when (gptel-auto-workflow--backend-rate-limited-p current-backend)
      (gptel-auto-workflow--first-available-provider-candidate
       candidates
       (gptel-auto-workflow--rate-limited-backend-names)))))

(defun gptel-auto-workflow--rewrite-subagent-provider (preset candidate)
  "Return PRESET rewritten to use CANDIDATE backend/model."
  (let* ((override (copy-sequence preset))
         (backend-name (car candidate))
         (model-name (cdr candidate))
         (backend-object (gptel-auto-workflow--backend-object backend-name))
         (model-symbol
          (gptel-auto-workflow--backend-model-symbol
           backend-object model-name))
         (max-output
          (gptel-auto-workflow--model-max-output-tokens
           (or model-symbol model-name)))
         (existing-max-tokens
          (let ((value (plist-get override :max-tokens)))
            (cond
             ((integerp value) value)
             ((and (stringp value)
                   (string-match-p "^[0-9]+$" value))
              (string-to-number value))
             (t nil)))))
    (setq override (plist-put override :backend
                              (or backend-object backend-name)))
    (setq override (plist-put override :model
                              (or model-symbol model-name)))
    (when (and (integerp max-output) (> max-output 0))
      (setq override
            (plist-put override :max-tokens
                       (if (and (integerp existing-max-tokens)
                                (> existing-max-tokens 0))
                           (min existing-max-tokens max-output)
                         max-output))))
    override))

(defun gptel-auto-workflow--activate-provider-failover (agent-type preset &optional reason)
  "Increment failure count for PRESET's backend; mark as rate-limited after threshold.

REASON is only used for logging. This implements retry-before-failover:
a backend must fail `gptel-auto-workflow-backend-rate-limit-failure-threshold'
times before the workflow stops using it."
  (when (and (gptel-auto-workflow--headless-provider-override-active-p)
             (stringp agent-type)
             (listp preset))
    (let* ((current-backend
            (gptel-auto-workflow--preset-backend-name
             (plist-get preset :backend)))
           (current-model (plist-get preset :model))
           (candidate nil)
           (already-limited
            (gptel-auto-workflow--backend-rate-limited-p current-backend)))
      (when (stringp current-backend)
        (unless already-limited
          (let* ((existing-count
                  (or (cdr (cl-assoc current-backend
                                     gptel-auto-workflow--backend-failure-counts
                                     :test #'string=))
                      0))
                 (new-count (1+ existing-count)))
             (setq gptel-auto-workflow--backend-failure-counts
                   (cons (cons current-backend new-count)
                         (cl-remove-if
                          (lambda (pair) (string= (car pair) current-backend))
                          gptel-auto-workflow--backend-failure-counts)))
             (message "[auto-workflow] Provider pressure on %s/%s for %s (failure %d/%d)"
                      (or current-backend "unknown")
                      (or current-model "unknown")
                      agent-type
                      new-count
                     gptel-auto-workflow-backend-rate-limit-failure-threshold)
            (when (>= new-count gptel-auto-workflow-backend-rate-limit-failure-threshold)
              (push (cons current-backend (float-time (current-time)))
                    gptel-auto-workflow--rate-limited-backends)
              (message "[auto-workflow] Backend %s marked rate-limited until %s (%d second cooldown)"
                       current-backend
                       (format-time-string "%H:%M:%S"
                                           (time-add (current-time)
                                                     (seconds-to-time
                                                      gptel-auto-workflow-rate-limit-cooldown-seconds)))
                       gptel-auto-workflow-rate-limit-cooldown-seconds)
              (setq candidate
                    (gptel-auto-workflow--runtime-provider-failover-candidate
                     agent-type preset))
              (when candidate
                (message "[auto-workflow] Provider failure threshold reached on %s/%s for %s%s; future retries will use %s/%s"
                         (or current-backend "unknown")
                         (or current-model "unknown")
                         agent-type
                         (if (and (stringp reason) (not (string-empty-p reason)))
                             (format " (%s)"
                                     (my/gptel--sanitize-for-logging reason 120))
                           "")
                         (car candidate)
                         (cdr candidate)))))))
      candidate)))

(defun gptel-auto-workflow--maybe-activate-rate-limit-failover (agent-type preset result)
  "Activate a per-run fallback for AGENT-TYPE when RESULT shows provider pressure."
  (when (and (gptel-auto-workflow--headless-provider-override-active-p)
             (gptel-auto-experiment--provider-pressure-error-p result))
    (gptel-auto-workflow--activate-provider-failover
     agent-type preset "provider pressure")))

(defun gptel-auto-workflow--maybe-override-subagent-provider (agent-type preset)
  "Return PRESET with a fallback provider for headless auto-workflow AGENT-TYPE."
  (let* ((runtime-candidate
          (and (gptel-auto-workflow--headless-provider-override-active-p)
               (or (gptel-auto-workflow--runtime-provider-failover-candidate
                    agent-type preset)
                   (gptel-auto-workflow--runtime-subagent-provider-override
                    agent-type)))))
    (cond
     (runtime-candidate
      (gptel-auto-workflow--rewrite-subagent-provider preset runtime-candidate))
     (t preset))))

(defun gptel-auto-experiment--aborted-agent-output-p (output)
  "Return non-nil when OUTPUT reflects an explicit subagent abort."
  (and (stringp output)
       (let ((case-fold-search t)
             (trimmed (string-trim-left output)))
         (string-match-p
          "\\`\\(?:Aborted:\\|\\(?:gptel:\\s-*\\)?inspection-thrash aborted\\|\\(?:gptel:\\s-*\\)?doom-loop aborted\\|Error: Task .* was aborted by the user\\|Error: Task .* was cancelled or timed out\\)"
          trimmed))))

(defun gptel-auto-experiment--shared-transient-error-p (error-output)
  "Return non-nil when ERROR-OUTPUT matches shared transient retry rules."
  (and (stringp error-output)
       (not (gptel-auto-experiment--aborted-agent-output-p error-output))
       (fboundp 'my/gptel--transient-error-p)
       (my/gptel--transient-error-p error-output nil)))

(defun gptel-auto-experiment--is-retryable-error-p (error-output)
  "Check if ERROR-OUTPUT is a transient/retryable error."
  (and (stringp error-output)
       (not (gptel-auto-experiment--aborted-agent-output-p error-output))
       (or (gptel-auto-experiment--shared-transient-error-p error-output)
           (gptel-auto-experiment--provider-usage-limit-error-p error-output)
            (let ((case-fold-search t))
              (string-match-p
               "rate_limit_error\\|rate.limit.exceeded\\|rate.limit.hit\\|quota.exceeded\\|quota.insufficient\\|429\\|timeout\\|timed out\\|temporary\\|overloaded\\|server_error\\|WebClientRequestException\\|curl failed with exit code 28\\|curl failed with exit code 56\\|operation timed out\\|authorized_error\\|token is unusable\\|invalid[_ ]api[_ ]key\\|unauthorized\\|http_code \"401\""
               error-output)))))

(defun gptel-auto-experiment--provider-usage-limit-error-p (error-output)
  "Return non-nil when ERROR-OUTPUT reflects a provider billing-cycle limit."
  (and (stringp error-output)
       (let ((case-fold-search t))
         (string-match-p
          "access_terminated_error\\|usage limit exceeded\\|usage limit for this billing cycle\\|reached your usage limit for this billing cycle"
          error-output))))

(defun gptel-auto-experiment--rate-limit-error-p (error-output)
  "Return non-nil when ERROR-OUTPUT reflects retryable provider pressure.
Only triggers on actual quota/rate limit errors, not general throttling."
  (and (stringp error-output)
       (or (gptel-auto-experiment--provider-usage-limit-error-p error-output)
           (let ((case-fold-search t))
             (string-match-p
              "rate_limit_error\\|allocated quota exceeded\\|insufficient_quota\\|billing_hard_limit_reached\\|rate.limit.exceeded\\|rate.limit.hit\\|429\\|overloaded_error\\|cluster overloaded\\|529\\|负载较高"
              error-output)))))

(defun gptel-auto-experiment--provider-auth-error-p (error-output)
  "Return non-nil when ERROR-OUTPUT reflects provider auth failure."
  (and (stringp error-output)
       (let ((case-fold-search t))
         (string-match-p
          "authorized_error\\|token is unusable\\|invalid[_ ]api[_ ]key\\|unauthorized\\|http_code \"401\""
          error-output))))

(defun gptel-auto-experiment--provider-pressure-error-p (error-output)
  "Return non-nil when ERROR-OUTPUT suggests trying a fallback backend.

Be conservative: only trigger fallback for actual quota/rate-limit errors.
Generic timeouts and server errors may be transient and recover on retry."
  (or (gptel-auto-experiment--rate-limit-error-p error-output)
      (gptel-auto-experiment--provider-auth-error-p error-output)
      (gptel-auto-experiment--shared-transient-error-p error-output)))

(defun gptel-auto-experiment--retry-delay-seconds (error-output retries)
  "Return retry delay for ERROR-OUTPUT after RETRIES previous attempts."
  (let ((base-delay (max 1 gptel-auto-experiment-retry-delay)))
    (if (gptel-auto-experiment--rate-limit-error-p error-output)
        (min gptel-auto-experiment-rate-limit-max-retry-delay
             (* base-delay (ash 1 retries)))
      base-delay)))

(defun gptel-auto-experiment--grade-failure-error-output (grade-details agent-output)
  "Return retryable/error-shaped output for a failed grade.
Prefer GRADE-DETAILS when the grader itself failed transiently; otherwise
fall back to an error-shaped AGENT-OUTPUT."
  (cond
   ((gptel-auto-experiment--normal-grade-details-p grade-details)
    nil)
   ((and (stringp grade-details)
         (or (gptel-auto-experiment--agent-error-p grade-details)
             (gptel-auto-experiment--is-retryable-error-p grade-details)
             (gptel-auto-experiment--quota-exhausted-p grade-details)))
    grade-details)
   ((gptel-auto-experiment--agent-error-p agent-output)
    agent-output)))

(defun gptel-auto-experiment--grader-only-failure-p (agent-output grade-error-output)
  "Return non-nil when GRADE-ERROR-OUTPUT came from the grader, not the executor."
  (and (stringp grade-error-output)
       (not (gptel-auto-experiment--agent-error-p agent-output))))

(defun gptel-auto-experiment--grader-only-error-label (error-category)
  "Return a durable result label for grader-only ERROR-CATEGORY."
  (pcase error-category
    (:timeout "grader-timeout")
    (:api-rate-limit "grader-api-rate-limit")
    (:api-error "grader-api-error")
    (:grader-failed "grader-failed")
    (:tool-error "grader-failed")
    (_ "grader-failed")))

(defun gptel-auto-experiment--should-retry-grader-p (agent-output grade-error-output error-category retries)
  "Return non-nil when a failed grade should retry locally.
Only successful executor output may take the local grader retry path."
  (and (gptel-auto-experiment--grader-only-failure-p agent-output grade-error-output)
       (memq error-category '(:api-rate-limit :api-error :timeout))
       (not (gptel-auto-experiment--hard-quota-stops-run-p "grader"
                                                           grade-error-output))
       (< retries gptel-auto-experiment-max-grader-retries)))

(defun gptel-auto-experiment--remaining-provider-failover-candidate (agent-type)
  "Return the next available provider fallback for AGENT-TYPE in this run, or nil."
  (when (and (stringp agent-type)
             (fboundp 'gptel-auto-workflow--headless-provider-override-active-p)
             (gptel-auto-workflow--headless-provider-override-active-p)
             (fboundp 'gptel-auto-workflow--rate-limit-failover-candidates)
             (fboundp 'gptel-auto-workflow--first-available-provider-candidate))
    (gptel-auto-workflow--first-available-provider-candidate
     (gptel-auto-workflow--rate-limit-failover-candidates agent-type)
     gptel-auto-workflow--rate-limited-backends)))

(defun gptel-auto-experiment--provider-chain-incomplete-p (&optional agent-type)
  "Return non-nil when AGENT-TYPE still has provider retries worth trying.

This covers both retries that should stay on the current backend and retries
that should advance to the next failover candidate.  Defaults to the executor
path used by experiment loops."
  (let* ((resolved-agent-type (or agent-type "executor"))
         (current-preset
          (and (fboundp 'gptel-auto-experiment--current-subagent-preset)
               (gptel-auto-experiment--current-subagent-preset
                resolved-agent-type)))
         (base-preset
          (and (or (not (listp current-preset))
                   (null (plist-get current-preset :backend)))
               (fboundp 'gptel-auto-workflow--agent-base-preset)
               (gptel-auto-workflow--agent-base-preset resolved-agent-type)))
         (effective-preset
          (cond
           ((and (listp current-preset)
                 (plist-get current-preset :backend))
            current-preset)
           ((and (listp base-preset)
                 (fboundp 'gptel-auto-workflow--maybe-override-subagent-provider))
            (gptel-auto-workflow--maybe-override-subagent-provider
             resolved-agent-type base-preset))
           (t base-preset)))
         (backend
          (and (listp effective-preset)
               (fboundp 'gptel-auto-workflow--preset-backend-name)
               (gptel-auto-workflow--preset-backend-name
                (plist-get effective-preset :backend))))
         (failures (or (and (stringp backend)
                            (cdr (cl-assoc backend
                                           gptel-auto-workflow--backend-failure-counts
                                           :test #'string=)))
                       0)))
    (or (and (stringp backend)
             (< failures
                gptel-auto-workflow-backend-rate-limit-failure-threshold))
        (gptel-auto-experiment--remaining-provider-failover-candidate
         resolved-agent-type))))

(defun gptel-auto-experiment--hard-quota-stops-run-p (agent-type error-output)
  "Return non-nil when ERROR-OUTPUT should stop the run for AGENT-TYPE.

Hard quota errors only stop the whole run after the configured provider fallback
chain is exhausted. When another backend is still available, the workflow keeps
retrying on that provider instead."
  (and (gptel-auto-experiment--hard-quota-exhausted-p error-output)
       (not (gptel-auto-experiment--remaining-provider-failover-candidate
             agent-type))))

(cl-defun gptel-auto-experiment--note-api-pressure (target error-category error-source
                                                           &optional agent-type
                                                           (escalate-run-pressure t))
  "Record API pressure state for TARGET after ERROR-CATEGORY from ERROR-SOURCE.

AGENT-TYPE is the subagent that produced ERROR-SOURCE, when known.
When ESCALATE-RUN-PRESSURE is nil, log provider pressure without incrementing
the shared run-wide API counter or stopping the rest of the workflow."
  (when (memq error-category '(:api-rate-limit :api-error))
    (let* ((resolved-agent-type (or agent-type "executor"))
           (hard-quota (gptel-auto-experiment--hard-quota-exhausted-p error-source)))
        (if escalate-run-pressure
            (progn
              (cl-incf gptel-auto-experiment--api-error-count)
              (message "[auto-workflow] API error #%d: %s"
                       gptel-auto-experiment--api-error-count error-category)
             (when hard-quota
               (if-let ((remaining
                         (gptel-auto-experiment--remaining-provider-failover-candidate
                          resolved-agent-type)))
                   (message "[auto-workflow] Provider hard quota on %s; continuing with %s/%s"
                            resolved-agent-type
                            (car remaining)
                            (cdr remaining))
                  (setq gptel-auto-experiment--quota-exhausted t)
                  (message "[auto-workflow] Provider quota exhausted; stopping remaining work for this run")))
              (when (>= gptel-auto-experiment--api-error-count
                        gptel-auto-experiment--api-error-threshold)
                (if (gptel-auto-experiment--provider-chain-incomplete-p
                     resolved-agent-type)
                    (message "[auto-workflow] API pressure threshold reached for %s, but provider failover remains available for %s"
                             target resolved-agent-type)
                  (message "[auto-workflow] API pressure detected; reducing future experiments for %s"
                           target))))
          (progn
            (message "[auto-workflow] Local API pressure on %s for %s; keeping run-wide pressure unchanged"
                     resolved-agent-type target)
            (when hard-quota
             (if-let ((remaining
                       (gptel-auto-experiment--remaining-provider-failover-candidate
                        resolved-agent-type)))
                 (message "[auto-workflow] Provider hard quota on %s; continuing with %s/%s"
                          resolved-agent-type
                          (car remaining)
                         (cdr remaining))
              (message "[auto-workflow] Provider quota exhausted for %s; continuing other workflow work"
                       resolved-agent-type))))))))

(defun gptel-auto-experiment--grade-with-retry (output callback &optional retry-count)
  "Grade OUTPUT and locally retry transient grader failures.
CALLBACK receives the final grade plist. RETRY-COUNT tracks local grader retries."
  (let* ((retries (or retry-count 0))
         (grade-buffer (current-buffer))
         (target gptel-auto-experiment--grading-target)
         (worktree gptel-auto-experiment--grading-worktree))
    (gptel-auto-experiment-grade
     output
     (lambda (grade)
       (let* ((grade-passed (plist-get grade :passed))
              (grade-details (plist-get grade :details))
              (grade-error-output
               (gptel-auto-experiment--grade-failure-error-output
                grade-details output))
              (error-source (or grade-error-output output))
              (error-info (gptel-auto-experiment--categorize-error error-source))
              (error-category (car error-info))
              (grader-only-failure
               (gptel-auto-experiment--grader-only-failure-p output grade-error-output)))
          (if (and (not grade-passed)
                   (gptel-auto-experiment--should-retry-grader-p
                    output grade-error-output error-category retries))
              (progn
                (gptel-auto-experiment--note-api-pressure
                 target error-category grade-error-output "grader" nil)
                (let ((retry-delay
                       (gptel-auto-experiment--retry-delay-seconds
                        grade-error-output retries)))
                 (message "[auto-exp] Retrying grader (attempt %d/%d) after %ds delay"
                          (1+ retries) gptel-auto-experiment-max-grader-retries retry-delay)
                 (run-with-timer
                  retry-delay nil
                  (lambda ()
                    (if (buffer-live-p grade-buffer)
                        (with-current-buffer grade-buffer
                          (let ((gptel-auto-experiment--grading-target target)
                                (gptel-auto-experiment--grading-worktree worktree))
                            (gptel-auto-experiment--grade-with-retry
                             output callback (1+ retries))))
                      (let ((final-grade (copy-sequence grade)))
                        (when grade-error-output
                          (setq final-grade
                                (plist-put final-grade :error-source grade-error-output)))
                        (when grader-only-failure
                          (setq final-grade
                                (plist-put final-grade :grader-only-failure t)))
                        (funcall callback final-grade)))))))
            (when (and (not grade-passed)
                       (memq error-category '(:api-rate-limit :api-error)))
              (gptel-auto-experiment--note-api-pressure
               target error-category error-source
               (if grader-only-failure "grader" "executor")
               (not grader-only-failure)))
            (let ((final-grade (copy-sequence grade)))
              (when grade-error-output
                (setq final-grade
                     (plist-put final-grade :error-source grade-error-output)))
             (when grader-only-failure
               (setq final-grade
                     (plist-put final-grade :grader-only-failure t)))
             (funcall callback final-grade))))))))

(defun gptel-auto-experiment--hard-timeout-p (error-output)
  "Return non-nil when ERROR-OUTPUT reports a hard wall-clock timeout."
  (and (stringp error-output)
       (string-match-p
        "timed out after [0-9]+s total runtime\\.?"
        error-output)))

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
       (or (gptel-auto-experiment--provider-usage-limit-error-p agent-output)
           (let ((case-fold-search t))
             (string-match-p
              "allocated quota exceeded\\|insufficient_quota\\|insufficient balance\\|billing_hard_limit_reached\\|hard limit reached"
              agent-output)))))

(defun gptel-auto-experiment--hard-quota-exhausted-p (agent-output)
  "Return non-nil when AGENT-OUTPUT shows a hard quota stop for executor work."
  (and (stringp agent-output)
       (let ((case-fold-search t))
         (string-match-p
          "allocated quota exceeded\\|insufficient_quota\\|insufficient balance\\|billing_hard_limit_reached\\|hard limit reached"
          agent-output))))

(defun gptel-auto-experiment--run-with-retry (target experiment-id max-experiments baseline baseline-code-quality previous-results callback &optional retry-count)
  "Run experiment with automatic retry on transient errors.
RETRY-COUNT tracks current retry attempt."
  (let ((retries (or retry-count 0))
        (workflow-root (gptel-auto-workflow--resolve-run-root))
        (retry-buffer (current-buffer))
        (run-id gptel-auto-workflow--run-id)
        (attempt-logs nil))
    (gptel-auto-experiment-run
     target experiment-id max-experiments baseline baseline-code-quality previous-results
      (lambda (result)
        (let* ((agent-output (plist-get result :agent-output))
               (raw-error (or (plist-get result :error)
                              (and (gptel-auto-experiment--agent-error-p agent-output)
                                   agent-output)))
               (grader-only-failure (plist-get result :grader-only-failure))
               (quota-source raw-error)
                (retry-delay
                 (gptel-auto-experiment--retry-delay-seconds
                  (or raw-error agent-output)
                 retries))
               (error-type (plist-get result :comparator-reason))
               (hard-timeout
                (gptel-auto-experiment--hard-timeout-p raw-error))
               (quota-exhausted
                (or gptel-auto-experiment--quota-exhausted
                    (gptel-auto-experiment--hard-quota-stops-run-p
                     "executor" quota-source)))
               (api-rate-limit-category
                (memq error-type '(:api-rate-limit)))
               (timeout-category
                (memq error-type '(:timeout)))
                (retryable-category
                 (or api-rate-limit-category
                     (and (not hard-timeout)
                          timeout-category)))
                 (retryable-failure
                  (and (not grader-only-failure)
                       (or retryable-category
                           (and raw-error
                                (not hard-timeout)
                                (gptel-auto-experiment--is-retryable-error-p raw-error)))))
                (retry-history
                 (gptel-auto-experiment--retry-history previous-results result)))
           (gptel-auto-workflow--restore-live-target-file target workflow-root)
           (when quota-exhausted
             (setq gptel-auto-experiment--quota-exhausted t))
           (if (and (not quota-exhausted)
                    (< retries gptel-auto-experiment-max-retries)
                   retryable-failure)
             (progn
               (setq attempt-logs nil)
               (message "[auto-exp] Retrying experiment %d (attempt %d/%d) after %ds delay"
                        experiment-id (1+ retries) gptel-auto-experiment-max-retries
                        retry-delay)
               (run-with-timer retry-delay nil
                               (lambda ()
                                 (if (gptel-auto-workflow--run-callback-live-p run-id)
                                     (gptel-auto-workflow--call-in-run-context
                                      workflow-root
                                       (lambda ()
                                         (gptel-auto-experiment--run-with-retry
                                          target experiment-id max-experiments baseline baseline-code-quality
                                         retry-history callback (1+ retries)))
                                       retry-buffer
                                       workflow-root)
                                    (progn
                                      (message "[auto-exp] Skipping stale retry for experiment %d; run %s is no longer active"
                                               experiment-id run-id)
                                     (funcall callback
                                              (list :target target
                                                    :id experiment-id
                                                    :stale-run t)))))))
           (dolist (logged-result (nreverse attempt-logs))
             (gptel-auto-experiment-log-tsv run-id logged-result))
           (setq attempt-logs nil)
           (when hard-timeout
             (message "[auto-exp] Hard executor timeout during experiment %d; skipping retries"
                      experiment-id))
           (when quota-exhausted
             (message "[auto-exp] Quota exhausted during experiment %d; skipping retries"
                      experiment-id))
           (funcall callback result))))
     (lambda (_logged-run-id exp-result)
       (push exp-result attempt-logs)))))
(defun gptel-auto-experiment--categorize-error (agent-output)
  "Categorize error from AGENT-OUTPUT and return (CATEGORY . DETAILS).
Categories: :api-rate-limit :api-error :tool-error :timeout :grader-failed :unknown
Also logs agent-output snippet for debugging when category is :unknown."
  (cond
   ((or (null agent-output) (string= agent-output ""))
    (cons :grader-failed "Grader returned no output"))
   ((gptel-auto-experiment--aborted-agent-output-p agent-output)
    (cons :tool-error "Subagent aborted"))
   ((string-match-p "hour allocated quota exceeded" agent-output)
    (cons :api-rate-limit "Hourly quota exhausted"))
   ((string-match-p "week allocated quota exceeded" agent-output)
    (cons :api-rate-limit "Weekly quota exhausted"))
   ((gptel-auto-experiment--provider-usage-limit-error-p agent-output)
    (cons :api-rate-limit "Provider usage limit reached"))
   ((string-match-p "throttling\\|rate.limit\\|quota exceeded\\|429" agent-output)
    (cons :api-rate-limit "API rate limit exceeded"))
   ((let ((case-fold-search t))
       (string-match-p "overloaded_error\\|cluster overloaded\\|529\\|负载较高"
                       agent-output))
    (cons :api-rate-limit "Provider overloaded"))
   ((gptel-auto-experiment--provider-auth-error-p agent-output)
    (cons :api-error "Provider authorization failed"))
   ((string-match-p "invalid_parameter_error\\|InvalidParameter\\|JSON format" agent-output)
    (cons :api-error "API parameter error (invalid JSON format)"))
   ((let ((case-fold-search t))
      (string-match-p "timeout\\|timed out\\|curl failed with exit code 28\\|curl failed with exit code 56\\|operation timed out"
                      agent-output))
    (cons :timeout "Experiment timed out"))
    ((let ((case-fold-search t))
       (string-match-p "server_error\\|WebClientRequestException" agent-output))
     (cons :api-error "Provider server error"))
    ((gptel-auto-experiment--shared-transient-error-p agent-output)
     (cons :api-error "Transient provider response error"))
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

(defun gptel-auto-experiment--should-reduce-experiments-p (&optional agent-type)
  "Return non-nil when API pressure should reduce experiment count.

When AGENT-TYPE still has current-backend retries or a failover candidate left,
the workflow keeps going instead of reducing experiment budgets prematurely."
  (and (>= gptel-auto-experiment--api-error-count
           gptel-auto-experiment--api-error-threshold)
       (not (gptel-auto-experiment--provider-chain-incomplete-p agent-type))))

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

(defun gptel-auto-experiment-run (target experiment-id max-experiments baseline baseline-code-quality previous-results callback &optional log-fn)
  "Run single experiment. Call CALLBACK with result plist.
BASELINE-CODE-QUALITY is the initial code quality score.
LOG-FN receives deferred results as (RUN-ID EXPERIMENT)."
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
         (log-fn (or log-fn #'gptel-auto-experiment-log-tsv))
         ;; Get project buffer for overlay routing (ensure hash table exists)
         (project-buf (when (and (boundp 'gptel-auto-workflow--current-project)
                                 gptel-auto-workflow--current-project)
                        (gptel-auto-workflow--hash-get-bound
                         'gptel-auto-workflow--project-buffers
                         (expand-file-name gptel-auto-workflow--current-project))))
         ;; Disable preview for headless auto-workflow
         (gptel-tools-preview-enabled nil)
         ;; Disable tool confirmations for headless auto-workflow
         (gptel-confirm-tool-calls nil)
         ;; Capture the experiment timeout lexically because later analyzer
         ;; callbacks run after this outer let frame exits.
         (experiment-timeout gptel-auto-experiment-time-budget)
          (run-id gptel-auto-workflow--run-id)
          (workflow-root (gptel-auto-workflow--resolve-run-root))
          ;; The subagent timeout wrapper owns executor timeout/abort behavior.
          (my/gptel-agent-task-timeout experiment-timeout)
          (start-time (float-time))
          (finished nil)
          (provisional-commit-hash nil)
          (executor-prompt nil))
    (if (not worktree)
        (funcall callback (list :target target :error "Failed to create worktree"))
      (gptel-auto-experiment--with-run-context experiment-buffer experiment-worktree workflow-root
        (gptel-auto-experiment-analyze
         previous-results
         (lambda (analysis)
            (gptel-auto-experiment--with-run-context experiment-buffer experiment-worktree workflow-root
              (let* ((patterns (when analysis (plist-get analysis :patterns)))
                     (prompt (gptel-auto-experiment-build-prompt
                              target experiment-id max-experiments analysis baseline previous-results)))
                (setq executor-prompt prompt)
                ;; Routing handled by gptel-auto-workflow--advice-task-override
                (my/gptel--run-agent-tool-with-timeout
                 experiment-timeout
                 (lambda (agent-output)
                   (gptel-auto-experiment--with-run-context experiment-buffer experiment-worktree workflow-root
                     (if (gptel-auto-experiment--stale-run-p run-id)
                         (unless finished
                           (setq finished t)
                           (message "[auto-experiment] Ignoring stale executor callback for %s experiment %d; run %s is no longer active"
                                    target experiment-id run-id)
                          (funcall callback
                                   (gptel-auto-experiment--stale-run-result
                                    target experiment-id)))
                      (let* ((salvaged-agent-output
                              (gptel-auto-experiment--timeout-salvage-output
                               agent-output executor-prompt target experiment-worktree))
                             (effective-agent-output
                              (or salvaged-agent-output agent-output))
                             (repeated-focus
                              (gptel-auto-experiment--repeated-focus-match
                               effective-agent-output previous-results)))
                        (when salvaged-agent-output
                          (message "[auto-exp] Executor timed out after partial changes for %s; evaluating actual worktree diff"
                                   target))
                        (message "[auto-exp] Agent output (first 150 chars): %s"
                                 (my/gptel--sanitize-for-logging effective-agent-output 150))
                        (unless finished
                          (if repeated-focus
                              (let* ((hypothesis
                                      (gptel-auto-experiment--extract-hypothesis
                                       effective-agent-output))
                                     (symbol (plist-get repeated-focus :symbol))
                                     (count (plist-get repeated-focus :count))
                                     (reason
                                      (format "Repeated focus on `%s` after %d prior non-kept attempts; choose a different function or subsystem."
                                              symbol count))
                                     (exp-result
                                      (list :target target
                                            :id experiment-id
                                            :hypothesis hypothesis
                                            :score-before baseline
                                            :score-after 0
                                            :code-quality baseline-code-quality
                                            :kept nil
                                            :duration (- (float-time) start-time)
                                            :grader-quality 0
                                            :grader-reason reason
                                            :comparator-reason "repeated-focus-symbol"
                                            :analyzer-patterns (format "%s" patterns)
                                            :agent-output effective-agent-output)))
                                (setq finished t)
                                (let ((default-directory experiment-worktree))
                                  (message "[auto-exp] Repeated focus on %s after %d prior non-kept attempts; discarding without grading"
                                           symbol count)
                                  (magit-git-success "checkout" "--" "."))
                                (cl-incf gptel-auto-experiment--no-improvement-count)
                                (funcall log-fn run-id exp-result)
                                (funcall callback exp-result))
                            (let ((gptel-auto-experiment--grading-target target)
                                  (gptel-auto-experiment--grading-worktree experiment-worktree))
                              (gptel-auto-experiment--grade-with-retry
                               effective-agent-output
                               (lambda (grade)
                                 (gptel-auto-experiment--with-run-context experiment-buffer experiment-worktree workflow-root
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
                                          (hypothesis (gptel-auto-experiment--extract-hypothesis effective-agent-output)))
                                      (message "[auto-exp] Grade result: score=%s/%s passed=%s"
                                               grade-score grade-total grade-passed)
                                      (when (and effective-agent-output (> (length effective-agent-output) 0))
                                        (message "[auto-exp] Agent preview: %s"
                                                (my/gptel--sanitize-for-logging effective-agent-output 100)))
                                       ;; Check if grader passed
                                       (if (not grade-passed)
                                            ;; Grader failures should classify from grader details when
                                            ;; they carry the real transient/API error instead of the
                                            ;; executor's normal success output.
                                            (let* ((normal-grade-rejection
                                                    (gptel-auto-experiment--normal-grade-details-p
                                                     grade-details))
                                                   (grade-error-output
                                                    (and (not normal-grade-rejection)
                                                         (or (plist-get grade :error-source)
                                                             (gptel-auto-experiment--grade-failure-error-output
                                                              grade-details effective-agent-output))))
                                                   (error-source (and (not normal-grade-rejection)
                                                                      (or grade-error-output effective-agent-output)))
                                                    (error-info (and error-source
                                                                     (gptel-auto-experiment--categorize-error
                                                                      error-source)))
                                                    (error-category (car-safe error-info))
                                                    (grader-only-failure
                                                    (and (not normal-grade-rejection)
                                                         (plist-get grade :grader-only-failure))))
                                              (setq finished t)
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
                                                                      :comparator-reason
                                                                      (cond
                                                                       (normal-grade-rejection
                                                                        "grader-rejected")
                                                                       (grader-only-failure
                                                                        (gptel-auto-experiment--grader-only-error-label
                                                                         error-category))
                                                                       (t
                                                                        (symbol-name (or error-category :unknown))))
                                                                       :analyzer-patterns (format "%s" patterns)
                                                                       :agent-output effective-agent-output)))
                                                (when grade-error-output
                                                  (setq exp-result
                                                        (plist-put exp-result :error grade-error-output)))
                                              (when grader-only-failure
                                                (setq exp-result
                                                      (plist-put exp-result :grader-only-failure t)))
                                              (funcall log-fn
                                                       run-id exp-result)
                                              (funcall callback exp-result)))
                                       ;; Grader passed - create a provisional commit so the
                                       ;; benchmark/scope logic can diff against HEAD~1.
                                       (let ((default-directory experiment-worktree))
                                         (setq provisional-commit-hash
                                               (gptel-auto-workflow--create-provisional-experiment-commit
                                                target hypothesis
                                                (max 300 gptel-auto-workflow-git-timeout))))
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
	                                                  effective-agent-output)
                                                (lambda (decision)
	                                              (unless finished
	                                                (setq finished t)
	                                                (let*
	                                                    ((decision
	                                                      (gptel-auto-experiment--promote-correctness-fix-decision
	                                                       decision
	                                                       tests-passed
	                                                       grade-score
	                                                       grade-total
	                                                       grade-details
	                                                       hypothesis))
	                                                     (keep (plist-get decision :keep))
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
		                                                        effective-agent-output)))
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
			                                                     (commit-timeout
			                                                      (max 300 gptel-auto-workflow-git-timeout))
			                                                     (finalize
			                                                      (gptel-auto-experiment--make-kept-result-callback
			                                                       run-id exp-result log-fn callback)))
		                                                    (gptel-auto-workflow--assert-main-untouched)
		                                                    (message "[auto-experiment] ✓ Committing improvement for %s" target)
		                                                    (if (and (gptel-auto-workflow--stage-worktree-changes
			                                                          (format "Stage experiment changes for %s" target)
			                                                          60)
			                                                         (gptel-auto-workflow--promote-provisional-commit
			                                                          msg
			                                                          (format "Commit experiment changes for %s" target)
			                                                          provisional-commit-hash
			                                                          commit-timeout))
		                                                        (progn
			                                                      (setq provisional-commit-hash nil)
			                                                      (gptel-auto-workflow--track-commit experiment-id
							                                                                         target
							                                                                         experiment-worktree)
			                                                      (setq gptel-auto-experiment--best-score score-after
			                                                            gptel-auto-experiment--no-improvement-count 0)
			                                                      (if gptel-auto-experiment-auto-push
			                                                          (progn
			                                                            (message "[auto-experiment] Pushing to %s" experiment-branch)
			                                                            (if (gptel-auto-workflow--push-branch-with-lease
				                                                             experiment-branch
				                                                             (format "Push optimize branch %s" experiment-branch)
				                                                             180)
				                                                            (if gptel-auto-workflow-use-staging
				                                                                (gptel-auto-workflow--staging-flow
					                                                             experiment-branch
					                                                             finalize)
				                                                              (funcall finalize))
				                                                          (let ((failed-result
					                                                             (plist-put (copy-sequence exp-result)
						                                                                    :comparator-reason
						                                                                    "optimize-push-failed")))
				                                                            (setq failed-result (plist-put failed-result :kept nil))
				                                                            (funcall log-fn run-id failed-result)
				                                                            (funcall callback failed-result))))
			                                                        (funcall finalize)))
		                                                      (let ((failed-result
			                                                         (plist-put (copy-sequence exp-result)
				                                                                :comparator-reason
				                                                                "experiment-commit-failed")))
		                                                        (gptel-auto-workflow--drop-provisional-commit
			                                                     provisional-commit-hash
			                                                     (format "Drop provisional commit for %s" target))
		                                                        (setq provisional-commit-hash nil)
		                                                        (setq failed-result (plist-put failed-result :kept nil))
		                                                        (funcall log-fn run-id failed-result)
		                                                        (funcall callback failed-result))))
	                                                    (let ((default-directory experiment-worktree))
		                                                  (message "[auto-experiment] Discarding changes for %s (no improvement)" target)
		                                                  (magit-git-success "checkout" "--" ".")
		                                                  (gptel-auto-workflow--drop-provisional-commit
		                                                   provisional-commit-hash
		                                                   (format "Discard provisional commit for %s" target))
		                                                  (setq provisional-commit-hash nil)
		                                                  (cl-incf gptel-auto-experiment--no-improvement-count)
		                                                  (funcall log-fn
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
                                                  (gptel-auto-experiment--prepare-validation-retry-worktree
                                                   target provisional-commit-hash)
                                                  (setq provisional-commit-hash nil)
                                                  (let ((gptel-auto-experiment-active-grace
                                                         gptel-auto-experiment-validation-retry-active-grace))
                                                    (my/gptel--run-agent-tool-with-timeout
                                                     gptel-auto-experiment-validation-retry-time-budget
                                                    (lambda (retry-output)
                                                      (let ((gptel-auto-experiment--grading-target target)
                                                            (gptel-auto-experiment--grading-worktree experiment-worktree))
                                                        (gptel-auto-experiment--grade-with-retry
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
		                                                                            (let* ((decision
		                                                                                    (gptel-auto-experiment--promote-correctness-fix-decision
		                                                                                     decision
		                                                                                     (plist-get retry-bench :tests-passed)
		                                                                                     (plist-get retry-grade :score)
		                                                                                     (plist-get retry-grade :total)
		                                                                                     (plist-get retry-grade :details)
		                                                                                     retry-hypothesis))
		                                                                                   (keep (plist-get decision :keep))
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
									                                                     (commit-timeout
									                                                      (max 300 gptel-auto-workflow-git-timeout))
									                                                     (finalize
									                                                      (gptel-auto-experiment--make-kept-result-callback
									                                                       run-id exp-result log-fn callback)))
								                                                    (gptel-auto-workflow--assert-main-untouched)
								                                                    (if (and (gptel-auto-workflow--stage-worktree-changes
									                                                          (format "Stage retry changes for %s" target)
									                                                          60)
									                                                         (gptel-auto-workflow--promote-provisional-commit
									                                                          msg
									                                                          (format "Commit retry changes for %s" target)
									                                                          provisional-commit-hash
									                                                          commit-timeout))
									                                                    (progn
									                                                      (setq provisional-commit-hash nil)
									                                                      (gptel-auto-workflow--track-commit experiment-id
												                                                                             target
												                                                                             experiment-worktree)
                                                                                          (setq gptel-auto-experiment--best-score retry-score
                                                                                                gptel-auto-experiment--no-improvement-count 0)
                                                                                          (if gptel-auto-experiment-auto-push
                                                                                              (progn
                                                                                                (message "[auto-experiment] Pushing to %s" experiment-branch)
                                                                                                (if (gptel-auto-workflow--push-branch-with-lease
                                                                                                     experiment-branch
                                                                                                     (format "Push optimize branch %s" experiment-branch)
                                                                                                     180)
                                                                                                    (if gptel-auto-workflow-use-staging
                                                                                                        (gptel-auto-workflow--staging-flow
                                                                                                         experiment-branch
                                                                                                         finalize)
                                                                                                      (funcall finalize))
                                                                                                  (let ((failed-result
                                                                                                         (plist-put (copy-sequence exp-result)
                                                                                                                    :comparator-reason
                                                                                                                    "retry-push-failed")))
                                                                                                    (setq failed-result (plist-put failed-result :kept nil))
                                                                                                    (funcall log-fn run-id failed-result)
                                                                                                    (funcall callback failed-result))))
                                                                                            (funcall finalize)))
								                                                      (let ((failed-result
									                                                         (plist-put (copy-sequence exp-result)
											                                                            :comparator-reason
											                                                            "retry-commit-failed")))
									                                                    (gptel-auto-workflow--drop-provisional-commit
									                                                     provisional-commit-hash
									                                                     (format "Drop provisional commit for %s" target))
									                                                    (setq provisional-commit-hash nil)
									                                                    (setq failed-result (plist-put failed-result :kept nil))
									                                                    (funcall log-fn run-id failed-result)
									                                                    (funcall callback failed-result))))
							                                                    (let ((default-directory experiment-worktree))
								                                                  (message "[auto-experiment] Discarding changes for %s (no improvement)" target)
								                                                  (magit-git-success "checkout" "--" ".")
								                                                  (gptel-auto-workflow--drop-provisional-commit
								                                                   provisional-commit-hash
								                                                   (format "Discard provisional commit for %s" target))
								                                                  (setq provisional-commit-hash nil)
								                                                  (cl-incf gptel-auto-experiment--no-improvement-count)
								                                                  (funcall log-fn
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
                                                                     (funcall log-fn
                                                                              run-id exp-result)
                                                                     (gptel-auto-workflow--drop-provisional-commit
                                                                      provisional-commit-hash
                                                                      (format "Drop provisional commit for %s" target))
                                                                     (setq provisional-commit-hash nil)
                                                                     (funcall callback exp-result))))
                                                              (setq finished t)
                                                              (let* ((retry-hypothesis
                                                                      (gptel-auto-experiment--extract-hypothesis retry-output))
                                                                     (retry-grade-details
                                                                      (plist-get retry-grade :details))
                                                                     (normal-grade-rejection
                                                                      (gptel-auto-experiment--normal-grade-details-p
                                                                       retry-grade-details))
                                                                     (retry-grade-error-output
                                                                      (and (not normal-grade-rejection)
                                                                           (or (plist-get retry-grade :error-source)
                                                                               (gptel-auto-experiment--grade-failure-error-output
                                                                                retry-grade-details retry-output))))
                                                                     (grader-only-failure
                                                                      (and (not normal-grade-rejection)
                                                                           (or (plist-get retry-grade :grader-only-failure)
                                                                               (gptel-auto-experiment--grader-only-failure-p
                                                                                retry-output retry-grade-error-output))))
                                                                     (retry-error-category
                                                                      (and retry-grade-error-output
                                                                           (car (gptel-auto-experiment--categorize-error
                                                                                 retry-grade-error-output))))
                                                                     (reason
                                                                      (if retry-grade-error-output
                                                                          (if grader-only-failure
                                                                              (gptel-auto-experiment--grader-only-error-label
                                                                               retry-error-category)
                                                                            (symbol-name (or retry-error-category :unknown)))
                                                                        "retry-grade-rejected"))
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
                                                                            :grader-reason retry-grade-details
                                                                            :comparator-reason reason
                                                                            :analyzer-patterns (format "%s" patterns)
                                                                            :agent-output retry-output
                                                                            :retries 1)))
                                                                (when retry-grade-error-output
                                                                  (setq exp-result
                                                                        (plist-put exp-result :error retry-grade-error-output)))
                                                                (when grader-only-failure
                                                                  (setq exp-result
                                                                        (plist-put exp-result :grader-only-failure t)))
                                                                (funcall log-fn
                                                                         run-id exp-result)
                                                                (gptel-auto-workflow--drop-provisional-commit
                                                                 provisional-commit-hash
                                                                 (format "Drop provisional commit for %s" target))
                                                                (setq provisional-commit-hash nil)
                                                                (funcall callback exp-result)))))))
                                                    "executor"
                                                    (format "Retry: fix validation error in %s" target)
                                                    (gptel-auto-experiment--make-retry-prompt
                                                     target validation-error executor-prompt)
                                                    nil "false" nil)))
                                             (let ((default-directory experiment-worktree))
                                               (setq finished t)
                                               (magit-git-success "checkout" "--" ".")
                                               (gptel-auto-workflow--drop-provisional-commit
                                                provisional-commit-hash
                                                (format "Discard provisional commit for %s" target))
                                               (setq provisional-commit-hash nil)
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
                                                 (funcall log-fn
                                                          run-id exp-result)
                                                 (funcall callback exp-result))))))
                                       )))))))))))))
                "executor"
                (format "Experiment %d: optimize %s" experiment-id target)
                executor-prompt
                nil "false" nil))))))))
  )





(defun gptel-auto-experiment--placeholder-hypothesis-p (hypothesis)
  "Return non-nil when HYPOTHESIS is still an unresolved prompt template."
  (let ((trimmed (and (stringp hypothesis) (string-trim hypothesis))))
    (or (not (gptel-auto-workflow--non-empty-string-p trimmed))
        (member trimmed '("[What CODE change and why]"
                          "What CODE change and why"))
        (string-match-p "\\`\\[What\\b.*\\]\\'" trimmed))))

(defun gptel-auto-experiment--extract-last-explicit-hypothesis (output pattern)
  "Return the last non-placeholder hypothesis in OUTPUT matching PATTERN."
  (when (stringp output)
    (let ((start 0)
          candidate)
      (while (and (< start (length output))
                  (string-match pattern output start))
        (let ((match (string-trim (match-string 1 output))))
          (unless (gptel-auto-experiment--placeholder-hypothesis-p match)
            (setq candidate match)))
        ;; Advance from the current match start so nested/repeated markers on the
        ;; same logical line still get a chance to replace malformed earlier text.
        (setq start (1+ (match-beginning 0))))
      candidate)))

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
   ((gptel-auto-experiment--agent-error-p output)
    "Agent error")
   ((gptel-auto-experiment--extract-last-explicit-hypothesis
     output
     "HYPOTHESIS:\\s-*\\([^\n]+\\)"))
   ((gptel-auto-experiment--extract-last-explicit-hypothesis
     output
     "\\*\\*HYPOTHESIS\\*\\*:?\\s-*\\([^\n]+\\)"))
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
  (and (stringp output)
       (or (string-match-p "^Error:" output)
           (gptel-auto-experiment--aborted-agent-output-p output))))

(defun gptel-auto-experiment--summarize (hypothesis)
  "Create short summary of HYPOTHESIS."
  (let ((words (split-string hypothesis)))
    (string-join (cl-subseq words 0 (min 6 (length words))) " ")))

(defvar gptel-auto-experiment-max-validation-retries 1
  "Maximum retries when validation fails due to teachable patterns.
Executor will be instructed to load relevant skill and regenerate.")

(defun gptel-auto-experiment--elisp-syntax-error-p (target error)
  "Return non-nil when ERROR indicates an Elisp syntax issue in TARGET."
  (and (stringp error)
       (or (string-match-p
            "cl-return-from.*without.*cl-block\\|Dangerous pattern"
            error)
           (and (stringp target)
                (string-suffix-p ".el" target)
                (string-match-p "\\`Syntax error in " error)))))

(defun gptel-auto-experiment--teachable-validation-error-p (target validation-error)
  "Return non-nil when VALIDATION-ERROR should trigger an immediate retry.
TARGET is the file currently being optimized."
  (and (stringp validation-error)
       (> (length validation-error) 0)
       (not (null (gptel-auto-experiment--elisp-syntax-error-p target validation-error)))))

(defun gptel-auto-experiment--make-retry-prompt (target validation-error original-prompt)
  "Create retry prompt after validation failure.
TARGET is the file being edited.
VALIDATION-ERROR is the error message.
Instructs executor to load relevant skill instead of hardcoding patterns."
  (let ((skill-guidance
         (cond
          ;; Elisp syntax and dangerous patterns - tell executor to load skill
          ((gptel-auto-experiment--elisp-syntax-error-p target validation-error)
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
  (let* ((workflow-root (gptel-auto-workflow--resolve-run-root))
         (loop-buffer (current-buffer))
         baseline
         baseline-code-quality)
    (gptel-auto-workflow--call-in-run-context
     workflow-root
     (lambda ()
       (setq baseline (gptel-auto-experiment-benchmark t)
             baseline-code-quality (or (gptel-auto-experiment--code-quality-score) 0.5)))
     loop-buffer
     workflow-root)
    (let* ((original-max gptel-auto-experiment-max-per-target)
         (max-exp (gptel-auto-experiment--adaptive-max-experiments original-max))
         (threshold gptel-auto-experiment-no-improvement-threshold)
         (run-id gptel-auto-workflow--run-id)
         (results nil)
         (best-score (let ((score (gptel-auto-workflow--plist-get baseline :eight-keys nil)))
                       (if (numberp score) score 0.0)))
         (no-improvement-count 0))
      (message "[auto-experiment] Baseline for %s: %.2f (max-exp: %d)"
               target best-score max-exp)
      (cl-labels ((run-next (exp-id)
                    (when gptel-auto-experiment--quota-exhausted
                      (message "[auto-workflow] Provider quota exhausted; stopping early for %s"
                               target)
                      (setq max-exp (min max-exp (1- exp-id))))
                    (when (and (gptel-auto-experiment--should-reduce-experiments-p
                                "executor")
                               (< exp-id max-exp))
                       (message "[auto-workflow] API pressure reached threshold (%d), stopping early for %s"
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
                                (kept (gptel-auto-workflow--plist-get result :kept nil))
                                (quality-after
                                 (gptel-auto-workflow--plist-get result :code-quality baseline-code-quality))
                                (hard-timeout
                                 (gptel-auto-experiment--result-hard-timeout-p result))
                                (grader-only-failure
                                 (plist-get result :grader-only-failure))
                                (next-exp-id (1+ exp-id)))
                            (when grader-only-failure
                              (message "[auto-experiment] Final grader-only failure for %s in experiment %d; stopping further experiments for this target"
                                       target exp-id)
                              (setq max-exp exp-id))
                            (when kept
                              (setq best-score score-after
                                    baseline-code-quality quality-after
                                    no-improvement-count 0))
                            (when (and (not kept)
                                       score-after
                                       (<= score-after best-score))
                              (cl-incf no-improvement-count))
                            (when hard-timeout
                              (message "[auto-experiment] Hard timeout for %s in experiment %d; skipping retries for this attempt and continuing if budget remains"
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
         workflow-root)))))

;;; Main Entry Point

(defvar gptel-auto-workflow--running nil
  "Flag to track if auto-workflow is currently running.")

(defvar gptel-auto-workflow--headless nil
  "Flag to suppress interactive prompts during headless operation.")

(defvar gptel-auto-workflow--auto-revert-was-enabled nil
  "Remember if global-auto-revert-mode was enabled before headless operation.")

(defvar gptel-auto-workflow--uniquify-style nil
  "Remember uniquify-buffer-name-style before headless operation.")

(defvar gptel-auto-workflow--compile-angel-on-load-was-enabled nil
  "Remember whether `compile-angel-on-load-mode' was enabled before headless operation.")

(defvar gptel-auto-workflow--create-lockfiles-value t
  "Remember `create-lockfiles' before headless operation.")

(defvar gptel-auto-workflow--stats nil
  "Current run statistics: (:kept :total :phase).")

(defvar gptel-auto-workflow--current-target nil
  "Current target file being processed by auto-workflow.")

(defvar gptel-auto-workflow--cron-job-running nil
  "Non-nil while a queued cron job is executing.")

(defvar gptel-auto-workflow--cron-job-timer nil
  "Timer object for a queued cron job that has not started yet.")

(defvar gptel-auto-workflow--watchdog-timer nil
  "Watchdog timer to prevent workflow from getting stuck.")

(defvar gptel-auto-workflow--status-refresh-timer nil
  "Timer that keeps the persisted workflow status snapshot fresh.")

(defvar gptel-auto-workflow--last-progress-time nil
  "Timestamp of last progress update.")

(defvar gptel-auto-workflow--messages-start-pos nil
  "Buffer position where the current workflow run's messages begin.")

(defvar gptel-auto-workflow--max-stuck-minutes 30
  "Maximum minutes workflow can be stuck before auto-stopping.")

(defcustom gptel-auto-workflow-status-file "var/tmp/cron/auto-workflow-status.sexp"
  "Path to the persisted auto-workflow status snapshot.
Relative paths are resolved from the project root."
  :type 'file
  :group 'gptel)

(defcustom gptel-auto-workflow-messages-file "var/tmp/cron/auto-workflow-messages-tail.txt"
  "Path to the persisted auto-workflow messages snapshot.
Relative paths are resolved from the project root."
  :type 'file
  :group 'gptel)

(defcustom gptel-auto-workflow-messages-chars 16000
  "Maximum number of trailing *Messages* characters to persist for cron tools."
  :type 'integer
  :group 'gptel)

(defcustom gptel-auto-workflow-status-refresh-interval 10
  "Seconds between persisted status refreshes during active workflow runs."
  :type 'integer
  :group 'gptel)

(defvar gptel-auto-workflow--persisted-status-file nil
  "Sticky status snapshot path captured at workflow start.")

(defvar gptel-auto-workflow--persisted-messages-file nil
  "Sticky messages snapshot path captured at workflow start.")

(defun gptel-auto-workflow--resolve-status-file ()
  "Resolve the current workflow status snapshot path."
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

(defun gptel-auto-workflow--resolve-messages-file ()
  "Resolve the current workflow messages snapshot path."
  (let* ((configured-file gptel-auto-workflow-messages-file)
         (default-file "var/tmp/cron/auto-workflow-messages-tail.txt")
         (env-file (getenv "AUTO_WORKFLOW_MESSAGES_FILE")))
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

(defun gptel-auto-workflow--capture-persisted-snapshot-files ()
  "Capture sticky snapshot paths for the current workflow run."
  (setq gptel-auto-workflow--persisted-status-file
        (gptel-auto-workflow--resolve-status-file)
        gptel-auto-workflow--persisted-messages-file
        (gptel-auto-workflow--resolve-messages-file)))

(defun gptel-auto-workflow--clear-persisted-snapshot-files ()
  "Clear sticky snapshot paths after a workflow run finishes."
  (setq gptel-auto-workflow--persisted-status-file nil
        gptel-auto-workflow--persisted-messages-file nil))

(defun gptel-auto-workflow--status-file ()
  "Return absolute path to the persisted workflow status snapshot."
  (or gptel-auto-workflow--persisted-status-file
      (gptel-auto-workflow--resolve-status-file)))

(defun gptel-auto-workflow--messages-file ()
  "Return absolute path to the persisted workflow messages snapshot."
  (or gptel-auto-workflow--persisted-messages-file
      (gptel-auto-workflow--resolve-messages-file)))

(defun gptel-auto-workflow--messages-chars ()
  "Return the configured trailing *Messages* snapshot size."
  (let* ((env-value (getenv "AUTO_WORKFLOW_MESSAGES_CHARS"))
         (parsed-env (and (stringp env-value)
                          (not (string-empty-p env-value))
                          (string-to-number env-value))))
    (if (and parsed-env (> parsed-env 0))
        parsed-env
      gptel-auto-workflow-messages-chars)))

(defun gptel-auto-workflow--mark-messages-start ()
  "Mark the current end of *Messages* as the start of a new workflow run."
  (with-current-buffer (get-buffer-create "*Messages*")
    (setq gptel-auto-workflow--messages-start-pos (point-max))))

(defun gptel-auto-workflow--persist-messages-tail ()
  "Persist the trailing *Messages* tail for non-blocking cron inspection."
  (let* ((file (gptel-auto-workflow--messages-file))
         (dir (file-name-directory file))
         (max-chars (gptel-auto-workflow--messages-chars)))
    (when dir
      (make-directory dir t))
    (with-current-buffer (get-buffer-create "*Messages*")
      (let* ((start-pos (cond
                         ((integer-or-marker-p gptel-auto-workflow--messages-start-pos)
                          (max (point-min)
                               (min (point-max)
                                    gptel-auto-workflow--messages-start-pos)))
                         (t (point-min))))
             (tail-start (max (point-min) (- (point-max) max-chars))))
        (condition-case err
            (write-region (max start-pos tail-start)
                          (point-max)
                          file nil 'silent)
          (error
           (message "[auto-workflow] Messages tail persist failed: %s"
                    (error-message-string err))))))))

(defun gptel-auto-workflow--status-plist ()
  "Return current workflow status as a plist."
  (let* ((running (or gptel-auto-workflow--running
                      (bound-and-true-p gptel-auto-workflow--cron-job-running)))
         (phase (gptel-auto-workflow--plist-get gptel-auto-workflow--stats :phase "idle"))
         (active-run-id (and (stringp gptel-auto-workflow--run-id)
                             (not (string-empty-p gptel-auto-workflow--run-id))
                             gptel-auto-workflow--run-id))
         (status-run-id (and (stringp gptel-auto-workflow--status-run-id)
                             (not (string-empty-p gptel-auto-workflow--status-run-id))
                             gptel-auto-workflow--status-run-id))
         (run-id (or active-run-id
                     (and running status-run-id)
                     (and (member phase '("complete" "quota-exhausted" "error"))
                          status-run-id))))
    (list :running running
          :kept (gptel-auto-workflow--plist-get gptel-auto-workflow--stats :kept 0)
          :total (gptel-auto-workflow--plist-get gptel-auto-workflow--stats :total 0)
          :phase phase
          :run-id run-id
          :results (and run-id
                        (gptel-auto-workflow--results-relative-path run-id)))))

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

(defun gptel-auto-workflow--status-owned-by-current-run-p (status)
  "Return non-nil when STATUS belongs to the current workflow run."
  (and (listp status)
       (stringp gptel-auto-workflow--run-id)
       (not (string-empty-p gptel-auto-workflow--run-id))
       (equal (plist-get status :run-id)
              gptel-auto-workflow--run-id)))

(defvar gptel-auto-workflow--allow-placeholder-status-overwrite nil
  "When non-nil, let placeholder idle snapshots replace active persisted status.")

(defun gptel-auto-workflow--persist-status ()
  "Persist current workflow status for non-blocking cron health checks."
  (let* ((file (gptel-auto-workflow--status-file))
         (dir (file-name-directory file))
         (status (gptel-auto-workflow--status-plist)))
    ;; Preserve the last active snapshot when an unrelated process only has an
    ;; idle placeholder view of workflow state. The shell wrapper already owns
     ;; stale-active detection; this guard prevents bogus idle rewrites with
     ;; synthetic run ids while a real run is still active elsewhere.
     (when (and (gptel-auto-workflow--status-placeholder-p status)
                (not gptel-auto-workflow--allow-placeholder-status-overwrite))
       (let ((existing-status (gptel-auto-workflow-read-persisted-status)))
         (when (and (gptel-auto-workflow--status-active-p existing-status)
                    (not (gptel-auto-workflow--status-owned-by-current-run-p
                          existing-status)))
           (setq status existing-status))))
     (when dir
      (make-directory dir t))
    (condition-case err
        (progn
          (with-temp-file file
            (let ((print-length nil)
                  (print-level nil))
              (prin1 status (current-buffer))
              (insert "\n")))
          (gptel-auto-workflow--persist-messages-tail))
      (error
       (message "[auto-workflow] Status persist failed: %s"
                (error-message-string err))))))

(defun gptel-auto-workflow--append-messages-line (text)
  "Append TEXT to *Messages* without going through `message'."
  (when (gptel-auto-workflow--non-empty-string-p text)
    (with-current-buffer (get-buffer-create "*Messages*")
      (let ((inhibit-read-only t))
        (goto-char (point-max))
        (unless (bolp)
          (insert "\n"))
        (insert text)
        (unless (string-suffix-p "\n" text)
          (insert "\n"))))))

(defun gptel-auto-workflow--report-finalization-error (context err)
  "Record a finalization failure for CONTEXT and ERR in *Messages*."
  (gptel-auto-workflow--append-messages-line
   (format "[auto-workflow] %s: %s"
           context
           (my/gptel--sanitize-for-logging (error-message-string err) 200))))

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
Also disables auto-revert, compile-angel, and uniquify to prevent
buffer churn in ephemeral workflow worktrees."
  (setq gptel-auto-workflow--headless t)
  ;; Remember and disable auto-revert
  (setq gptel-auto-workflow--auto-revert-was-enabled 
        (bound-and-true-p global-auto-revert-mode))
  (when gptel-auto-workflow--auto-revert-was-enabled
    (global-auto-revert-mode -1))
  ;; Disable on-load auto-compilation so clean replay/worktree buffers do not
  ;; spend their first analyzer/executor pass byte-compiling repo files.
  (setq gptel-auto-workflow--compile-angel-on-load-was-enabled
        (bound-and-true-p compile-angel-on-load-mode))
  (when (and gptel-auto-workflow--compile-angel-on-load-was-enabled
             (fboundp 'compile-angel-on-load-mode))
    (compile-angel-on-load-mode -1))
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
Restores auto-revert, compile-angel, and uniquify if they were
enabled before headless operation.
Does nothing if `gptel-auto-workflow-persistent-headless' is non-nil."
  (when (and (not gptel-auto-workflow-persistent-headless)
             gptel-auto-workflow--headless)
    (setq gptel-auto-workflow--headless nil)
    ;; Restore auto-revert
    (when (and (boundp 'gptel-auto-workflow--auto-revert-was-enabled)
               gptel-auto-workflow--auto-revert-was-enabled)
      (global-auto-revert-mode 1))
    ;; Restore on-load auto-compilation only when this session disabled it.
    (when (and gptel-auto-workflow--compile-angel-on-load-was-enabled
               (fboundp 'compile-angel-on-load-mode))
      (compile-angel-on-load-mode 1))
    (setq gptel-auto-workflow--compile-angel-on-load-was-enabled nil)
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

(defconst gptel-auto-workflow--skip-submodule-sync-env
  "VERIFY_NUCLEUS_SKIP_SUBMODULE_SYNC=1"
  "Environment override used to skip workflow git-hook submodule sync checks.")

(defun gptel-auto-workflow--with-skipped-submodule-sync (fn)
  "Run FN with workflow git hooks skipping submodule sync."
  (let ((process-environment
         (cons gptel-auto-workflow--skip-submodule-sync-env
               process-environment)))
    (funcall fn)))

(defconst gptel-auto-workflow--isolated-state-env-prefixes
  '("AUTO_WORKFLOW_STATUS_FILE="
    "AUTO_WORKFLOW_MESSAGES_FILE="
    "AUTO_WORKFLOW_SNAPSHOT_PATHS_FILE="
    "AUTO_WORKFLOW_EMACS_SERVER=")
  "Environment prefixes that bind a process to workflow state.")

(defvar gptel-auto-workflow--subagent-process-environment nil
  "Full isolated env to persist on routed headless subagent buffers.")

(defun gptel-auto-workflow--isolated-state-env-entry-p (entry)
  "Return non-nil when ENTRY binds shared workflow state."
  (and (stringp entry)
       (cl-some (lambda (prefix)
                  (string-prefix-p prefix entry))
                gptel-auto-workflow--isolated-state-env-prefixes)))

(defun gptel-auto-workflow--isolated-state-environment (&optional server-prefix extra-env include-messages-p)
  "Return `process-environment' isolated from live workflow state.
SERVER-PREFIX customizes the temporary daemon name prefix.
EXTRA-ENV entries are prepended ahead of the isolated workflow vars.
When INCLUDE-MESSAGES-P is non-nil, also isolate messages and snapshot files."
  (let* ((isolated-status-file (make-temp-file "auto-workflow-status-" nil ".sexp"))
         (isolated-messages-file
          (and include-messages-p
               (make-temp-file "auto-workflow-messages-" nil ".txt")))
         (isolated-snapshot-file
          (and include-messages-p
               (make-temp-file "auto-workflow-snapshot-paths-" nil ".txt")))
         (isolated-server-name
          (make-temp-name (or server-prefix "copilot-auto-workflow-test-")))
         (env
          (append
           extra-env
           (list (format "AUTO_WORKFLOW_STATUS_FILE=%s" isolated-status-file))
           (when include-messages-p
             (list (format "AUTO_WORKFLOW_MESSAGES_FILE=%s" isolated-messages-file)
                   (format "AUTO_WORKFLOW_SNAPSHOT_PATHS_FILE=%s" isolated-snapshot-file)))
           (list (format "AUTO_WORKFLOW_EMACS_SERVER=%s" isolated-server-name)))))
    (dolist (path (delq nil (list isolated-status-file
                                  (and include-messages-p isolated-messages-file)
                                  (and include-messages-p isolated-snapshot-file))))
      (when (file-exists-p path)
        (delete-file path)))
    (append (flatten-tree env)
            (cl-remove-if #'gptel-auto-workflow--isolated-state-env-entry-p
                          process-environment))))

 (defun gptel-auto-workflow--persist-subagent-process-environment (&optional buffer env)
   "Persist isolated workflow ENV onto BUFFER for later async tool processes."
   (let ((target (or buffer (current-buffer)))
         (effective-env (or env gptel-auto-workflow--subagent-process-environment)))
     (when (and (buffer-live-p target)
                (listp effective-env))
       (with-current-buffer target
         (let ((copied-env (copy-sequence effective-env)))
           (if (fboundp 'buffer-local-set-state)
               (buffer-local-set-state
                gptel-auto-workflow--subagent-process-environment (copy-sequence copied-env)
                process-environment copied-env)
             (set (make-local-variable 'gptel-auto-workflow--subagent-process-environment)
                  (copy-sequence copied-env))
             (set (make-local-variable 'process-environment)
                  copied-env)))))))

(defun gptel-auto-workflow--git-step-success-p (cmd action &optional timeout)
  "Run git CMD and report whether it succeeded.
ACTION is a short description used in the failure message."
  (pcase-let ((`(,output . ,exit-code)
               (gptel-auto-workflow--git-result cmd timeout)))
    (if (= exit-code 0)
        t
      (message "[auto-workflow] %s failed: %s"
               action
               (my/gptel--sanitize-for-logging output 200))
      nil)))

(defun gptel-auto-workflow--empty-commit-output-p (output)
  "Return non-nil when OUTPUT describes a localized clean no-op commit."
  (and (stringp output)
       (string-match-p
        "nothing to commit\\|working tree clean\\|无文件要提交\\|工作区干净"
        output)))

(defun gptel-auto-workflow--commit-step-success-p (cmd action &optional timeout)
  "Run commit CMD and report whether it succeeded or was already captured.
ACTION is a short description used in the failure message."
  (pcase-let ((`(,output . ,exit-code)
               (gptel-auto-workflow--git-result cmd timeout)))
    (cond
     ((= exit-code 0) t)
     ((gptel-auto-workflow--empty-commit-output-p output)
      (message "[auto-workflow] %s already captured (nothing new to commit)" action)
      t)
     (t
      (message "[auto-workflow] %s failed: %s"
               action
               (my/gptel--sanitize-for-logging output 200))
      nil))))

(defun gptel-auto-workflow--current-head-hash ()
  "Return the current HEAD hash in `default-directory', or nil on failure."
  (let ((hash (string-trim (or (ignore-errors
                                 (gptel-auto-workflow--git-cmd "git rev-parse HEAD" 30))
                               ""))))
    (when (string-match-p "^[a-f0-9]\\{7,40\\}$" hash)
      hash)))

(defun gptel-auto-workflow--checked-out-submodule-head (&optional worktree path)
  "Return the checked-out HEAD for top-level submodule PATH in WORKTREE, or nil."
  (let* ((root (or worktree default-directory))
         (target (and (stringp path) (expand-file-name path root)))
         (git-marker (and target (expand-file-name ".git" target)))
         (result (and target
                      (file-directory-p target)
                      (file-exists-p git-marker)
                      (gptel-auto-workflow--git-result
                       (format "git -C %s rev-parse HEAD"
                               (shell-quote-argument target))
                       60)))
         (hash (and result (string-trim (car result)))))
    (when (and result
               (= 0 (cdr result))
               (string-match-p "^[a-f0-9]\\{40\\}$" hash))
      hash)))

(defun gptel-auto-workflow--restage-top-level-submodule-gitlinks (&optional worktree)
  "Restore top-level submodule gitlinks in WORKTREE after `git add -A'.
Hydrated experiment worktrees materialize submodules as checked-out directories.
Reassert gitlink index entries so commits do not record those paths as typechanges."
  (let* ((root (or worktree default-directory))
         (paths (gptel-auto-workflow--staging-submodule-paths root))
         failure)
    (dolist (path paths)
      (unless failure
        (let* ((commit (or (gptel-auto-workflow--checked-out-submodule-head root path)
                           (gptel-auto-workflow--staging-submodule-gitlink-revision root path)))
               (result (and commit
                            (gptel-auto-workflow--git-result
                             (format "git update-index --cacheinfo 160000 %s %s"
                                     (shell-quote-argument commit)
                                     (shell-quote-argument path))
                             60))))
          (cond
           ((not commit)
            (setq failure
                  (format "Missing gitlink revision for submodule %s" path)))
           ((/= 0 (cdr result))
            (setq failure
                  (format "Failed to restage %s as gitlink: %s"
                          path
                          (car result))))))))
    (if failure
        (progn
          (message "[auto-workflow] Failed to preserve submodule gitlinks: %s"
                   (my/gptel--sanitize-for-logging failure 200))
          nil)
      t)))

(defun gptel-auto-workflow--stage-worktree-changes (action &optional timeout)
  "Stage current worktree changes for ACTION while preserving submodule gitlinks."
  (and (gptel-auto-workflow--git-step-success-p
        "git add -A"
        action
        timeout)
       (gptel-auto-workflow--restage-top-level-submodule-gitlinks)))

(defun gptel-auto-workflow--create-provisional-experiment-commit (target hypothesis &optional timeout)
  "Create a provisional WIP commit for TARGET and return its hash.
Returns nil when the commit could not be created."
  (let ((msg (format "WIP: experiment %s\n\nHYPOTHESIS: %s"
                     target
                     (or hypothesis "Improve code quality"))))
    (when (and (gptel-auto-workflow--stage-worktree-changes
                (format "Stage provisional experiment for %s" target)
                60)
               (gptel-auto-workflow--git-step-success-p
                (format "%s git commit -m %s"
                        gptel-auto-workflow--skip-submodule-sync-env
                        (shell-quote-argument msg))
                (format "Create provisional experiment commit for %s" target)
                (or timeout gptel-auto-workflow-git-timeout)))
      (gptel-auto-workflow--current-head-hash))))

(defun gptel-auto-workflow--promote-provisional-commit (message action provisional-hash &optional timeout)
  "Create final commit with MESSAGE, amending PROVISIONAL-HASH when needed.
ACTION is used for failure logging."
  (let* ((head-hash (and provisional-hash
                         (gptel-auto-workflow--current-head-hash)))
         (commit-command
          (format "%s git commit -m %s"
                  gptel-auto-workflow--skip-submodule-sync-env
                  (shell-quote-argument message)))
         (amend-command
          (format "%s git commit --amend -m %s"
                  gptel-auto-workflow--skip-submodule-sync-env
                  (shell-quote-argument message))))
    (if (and provisional-hash head-hash (equal provisional-hash head-hash))
        (gptel-auto-workflow--git-step-success-p
         amend-command
         (format "%s (promote provisional commit)" action)
         timeout)
      (gptel-auto-workflow--commit-step-success-p
       commit-command
       action
       timeout))))

(defun gptel-auto-workflow--drop-provisional-commit (provisional-hash action &optional timeout)
  "Drop PROVISIONAL-HASH when it is still the current HEAD.
ACTION is used for failure logging."
  (when (and provisional-hash
             (equal provisional-hash (gptel-auto-workflow--current-head-hash)))
    (gptel-auto-workflow--git-step-success-p
     "git reset --hard HEAD~1"
     action
     (or timeout 60))))

(defun gptel-auto-experiment--prepare-validation-retry-worktree (target provisional-hash)
  "Reset the current experiment worktree to a clean base before retrying validation.
Drops PROVISIONAL-HASH when it is still the current HEAD so retries do not
start from a syntax-invalid provisional commit."
  (and (magit-git-success "checkout" "--" ".")
       (or (null provisional-hash)
           (not (equal provisional-hash (gptel-auto-workflow--current-head-hash)))
           (gptel-auto-workflow--drop-provisional-commit
            provisional-hash
            (format "Drop provisional commit before validation retry for %s" target)))))

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
        (gptel-auto-workflow--clear-runtime-subagent-provider-overrides)
        (setq gptel-auto-workflow--running nil
              gptel-auto-workflow--cron-job-running nil
              gptel-auto-workflow--status-run-id nil
              gptel-auto-workflow--run-id nil
              gptel-auto-workflow--run-project-root nil
              gptel-auto-workflow--current-project nil
              gptel-auto-workflow--current-target nil)
        (setq gptel-auto-workflow--stats
              (plist-put gptel-auto-workflow--stats :phase "idle"))
        (let ((gptel-auto-workflow--allow-placeholder-status-overwrite t))
          (gptel-auto-workflow--persist-status))
        (gptel-auto-workflow--clear-persisted-snapshot-files)
        (when gptel-auto-workflow--watchdog-timer
          (cancel-timer gptel-auto-workflow--watchdog-timer)
          (setq gptel-auto-workflow--watchdog-timer nil))
        (gptel-auto-workflow--stop-status-refresh-timer)
        nil)
       ((> stuck-minutes gptel-auto-workflow--max-stuck-minutes)
        (message "[auto-workflow] WATCHDOG: Workflow stuck for %.1f minutes, force-stopping"
                 stuck-minutes)
        (gptel-auto-workflow--clear-runtime-subagent-provider-overrides)
        (setq gptel-auto-workflow--running nil
              gptel-auto-workflow--cron-job-running nil
              gptel-auto-workflow--status-run-id nil
              gptel-auto-workflow--run-id nil
              gptel-auto-workflow--run-project-root nil
              gptel-auto-workflow--current-project nil
              gptel-auto-workflow--current-target nil)
        (setq gptel-auto-workflow--stats
              (plist-put gptel-auto-workflow--stats :phase "idle"))
        (let ((gptel-auto-workflow--allow-placeholder-status-overwrite t))
          (gptel-auto-workflow--persist-status))
        (gptel-auto-workflow--clear-persisted-snapshot-files)
        (when gptel-auto-workflow--watchdog-timer
          (cancel-timer gptel-auto-workflow--watchdog-timer)
          (setq gptel-auto-workflow--watchdog-timer nil))
        (gptel-auto-workflow--stop-status-refresh-timer)
        nil)
       (t
        ;; Still running normally, check again in 5 minutes
        t)))))

(defun gptel-auto-workflow--update-progress ()
  "Update progress timestamp for watchdog tracking."
  (setq gptel-auto-workflow--last-progress-time (current-time)))

(defun gptel-auto-workflow--restart-watchdog-timer ()
  "Restart the workflow watchdog timer if a workflow run is active."
  (when (timerp gptel-auto-workflow--watchdog-timer)
    (cancel-timer gptel-auto-workflow--watchdog-timer))
  (setq gptel-auto-workflow--watchdog-timer nil)
  (when (or gptel-auto-workflow--running
            gptel-auto-workflow--cron-job-running)
    (setq gptel-auto-workflow--watchdog-timer
          (run-with-timer 300 300 #'gptel-auto-workflow--watchdog-check))))

(defun gptel-auto-workflow--call-process-with-watchdog (program &optional infile destination display &rest args)
  "Run blocking PROGRAM while pausing the workflow watchdog.

This avoids false watchdog force-stops when long local verification phases block
Emacs long enough for a queued watchdog check to fire immediately afterward."
  (let ((workflow-active (or gptel-auto-workflow--running
                             gptel-auto-workflow--cron-job-running)))
    (when workflow-active
      (when (timerp gptel-auto-workflow--watchdog-timer)
        (cancel-timer gptel-auto-workflow--watchdog-timer))
      (setq gptel-auto-workflow--watchdog-timer nil))
    (unwind-protect
        (apply #'call-process program infile destination display args)
      (when workflow-active
        (gptel-auto-workflow--update-progress)
        (gptel-auto-workflow--persist-status)
        (gptel-auto-workflow--restart-watchdog-timer)))))

(defun gptel-auto-workflow--stop-status-refresh-timer ()
  "Cancel the active workflow status refresh timer, if any."
  (when (timerp gptel-auto-workflow--status-refresh-timer)
    (cancel-timer gptel-auto-workflow--status-refresh-timer)
    (setq gptel-auto-workflow--status-refresh-timer nil)))

(defun gptel-auto-workflow--refresh-status-if-running ()
  "Refresh the persisted workflow snapshot while the workflow is active."
  (if (and (or gptel-auto-workflow--running
               gptel-auto-workflow--cron-job-running)
           gptel-auto-workflow--stats
           (numberp gptel-auto-workflow-status-refresh-interval)
           (> gptel-auto-workflow-status-refresh-interval 0))
      (condition-case-unless-debug err
          (progn
            (gptel-auto-workflow--persist-status)
            (unless (or gptel-auto-workflow--running
                        gptel-auto-workflow--cron-job-running)
              (gptel-auto-workflow--stop-status-refresh-timer)))
        (error
         (message "[auto-workflow] Status refresh failed: %s"
                  (error-message-string err))
         (unless (or gptel-auto-workflow--running
                     gptel-auto-workflow--cron-job-running)
           (gptel-auto-workflow--stop-status-refresh-timer))))
    (gptel-auto-workflow--stop-status-refresh-timer)))

(defun gptel-auto-workflow--start-status-refresh-timer ()
  "Start the workflow status refresh timer if a workflow run is active."
  (when (and (or gptel-auto-workflow--running
                 gptel-auto-workflow--cron-job-running)
             (numberp gptel-auto-workflow-status-refresh-interval)
             (> gptel-auto-workflow-status-refresh-interval 0))
    (when (timerp gptel-auto-workflow--status-refresh-timer)
      (cancel-timer gptel-auto-workflow--status-refresh-timer))
    (setq gptel-auto-workflow--status-refresh-timer
          (run-with-timer gptel-auto-workflow-status-refresh-interval
                          gptel-auto-workflow-status-refresh-interval
                          #'gptel-auto-workflow--refresh-status-if-running))))

(defun gptel-auto-workflow-force-stop ()
  "Force stop a stuck workflow.
Interactive command to recover from hung workflow state."
  (interactive)
  (my/gptel--reset-agent-task-state)
  (gptel-auto-workflow--clear-runtime-subagent-provider-overrides)
  (gptel-mementum--reset-synthesis-state)
  (gptel-auto-experiment--reset-grade-state)
  (when gptel-auto-workflow--cron-job-timer
    (cancel-timer gptel-auto-workflow--cron-job-timer)
    (setq gptel-auto-workflow--cron-job-timer nil))
  (gptel-auto-workflow--stop-status-refresh-timer)
  (gptel-auto-workflow--terminate-active-shell-processes)
  (setq gptel-auto-workflow--running nil
         gptel-auto-workflow--cron-job-running nil
         gptel-auto-workflow--status-run-id nil
         gptel-auto-workflow--run-id nil
         gptel-auto-workflow--run-project-root nil
         gptel-auto-workflow--current-project nil
         gptel-auto-workflow--current-target nil)
  (setq gptel-auto-workflow--stats
        (plist-put gptel-auto-workflow--stats :phase "idle"))
  (let ((gptel-auto-workflow--allow-placeholder-status-overwrite t))
    (gptel-auto-workflow--persist-status))
  (gptel-auto-workflow--clear-persisted-snapshot-files)
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
    (gptel-auto-workflow--migrate-legacy-provider-defaults)
    (gptel-auto-workflow--clear-runtime-subagent-provider-overrides)
    (setq gptel-auto-workflow--current-project (gptel-auto-workflow--default-dir)
          gptel-auto-workflow--run-project-root (gptel-auto-workflow--default-dir)
          gptel-auto-workflow--run-id (or gptel-auto-workflow--run-id
                                          (gptel-auto-workflow--make-run-id))
          gptel-auto-workflow--status-run-id gptel-auto-workflow--run-id
          gptel-auto-experiment--api-error-count 0
          gptel-auto-experiment--quota-exhausted nil
          gptel-auto-workflow--running t
          gptel-auto-workflow--stats (list :phase "selecting" :total 0 :kept 0)
          gptel-auto-workflow--last-progress-time (current-time))
    (gptel-auto-workflow--capture-persisted-snapshot-files)
    (gptel-auto-workflow--ensure-results-file gptel-auto-workflow--run-id)
    (unless gptel-auto-workflow--cron-job-running
      (gptel-auto-workflow--mark-messages-start))
    (gptel-auto-workflow--start-status-refresh-timer)
    (gptel-auto-workflow--persist-status)
    ;; Start watchdog timer
    (gptel-auto-workflow--restart-watchdog-timer)
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

(defun gptel-auto-workflow--reload-live-support (&optional proj-root)
  "Reload workflow support modules and agent presets from PROJ-ROOT."
  (let ((root (file-name-as-directory
               (expand-file-name
                (or proj-root
                    (gptel-auto-workflow--default-dir)
                    default-directory)))))
    (load-file (expand-file-name "lisp/modules/gptel-ext-retry.el" root))
    (load-file (expand-file-name "lisp/modules/nucleus-presets.el" root))
    (load-file (expand-file-name "lisp/modules/gptel-auto-workflow-strategic.el" root))
    (load-file (expand-file-name "lisp/modules/gptel-auto-workflow-projects.el" root))
    (if (fboundp 'nucleus-presets-setup-agents)
        (progn
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
        (nucleus--override-gptel-agent-presets)))))


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
    (load-file (expand-file-name "lisp/modules/gptel-tools-agent.el" proj-root))
    (when (fboundp 'gptel-auto-workflow--reload-live-support)
      (gptel-auto-workflow--reload-live-support proj-root))
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

(defun gptel-auto-workflow--cleanup-integrated-remote-optimize-branches (&optional proj-root)
  "Delete remote optimize branches already integrated and prune stale tracking refs.

Only remote optimize branches whose tip commit is already contained in staging or
main are deleted. Stale `origin/optimize/*' tracking refs are pruned afterward."
  (let* ((default-directory (or proj-root (gptel-auto-workflow--default-dir))))
    (if (not (file-directory-p default-directory))
        0
      (let* ((tracking-before
              (length
               (gptel-auto-workflow--remote-tracking-optimize-branches default-directory)))
             (remote-branches
              (gptel-auto-workflow--remote-optimize-branches default-directory))
             (integrated nil)
             (deleted 0))
        (dolist (entry remote-branches)
          (let ((branch (plist-get entry :branch))
                (head (plist-get entry :head)))
            (when (and (gptel-auto-workflow--non-empty-string-p branch)
                       (gptel-auto-workflow--non-empty-string-p head)
                       (gptel-auto-workflow--commit-integrated-p head))
              (push branch integrated))))
        (let ((pending (nreverse integrated)))
          (while pending
            (let ((batch nil)
                  (count 0))
              (while (and pending (< count 25))
                (push (car pending) batch)
                (setq pending (cdr pending))
                (cl-incf count))
              (setq batch (nreverse batch))
              (let* ((delete-command
                      (format "git push origin --delete %s"
                              (mapconcat #'shell-quote-argument batch " ")))
                     (delete-result
                      (gptel-auto-workflow--with-skipped-submodule-sync
                       (lambda ()
                         (gptel-auto-workflow--git-result delete-command 180)))))
                (if (= 0 (cdr delete-result))
                    (cl-incf deleted (length batch))
                  (message "[auto-workflow] Failed to delete remote optimize branches %s: %s"
                           (mapconcat #'identity batch ", ")
                           (my/gptel--sanitize-for-logging (car delete-result) 200)))))))
        (when (> deleted 0)
          (message "[auto-workflow] Deleted %d integrated remote optimize branch(es)" deleted))
        (when (> tracking-before 0)
          (let ((prune-result
                 (gptel-auto-workflow--git-result "git remote prune origin" 180)))
            (if (= 0 (cdr prune-result))
                (let* ((tracking-after
                        (length
                         (gptel-auto-workflow--remote-tracking-optimize-branches
                          default-directory)))
                       (pruned (max 0 (- tracking-before tracking-after))))
                  (when (> pruned 0)
                    (message "[auto-workflow] Pruned %d stale remote optimize tracking ref(s)"
                             pruned)))
              (message "[auto-workflow] Failed to prune origin optimize tracking refs: %s"
                       (my/gptel--sanitize-for-logging (car prune-result) 200)))))
        deleted))))

(defun gptel-auto-workflow--cleanup-old-worktrees ()
  "Remove stale optimize state from previous runs.
Called at start of new run to ensure clean state.
Local optimize branches are only removed for the current host suffix. Remote
optimize branches are only removed when their tip commit is already integrated
into staging or main."
  (let* ((proj-root (gptel-auto-workflow--worktree-base-root))
         (worktree-base-dir (or gptel-auto-workflow-worktree-base
                                "var/tmp/experiments"))
         (worktree-base (expand-file-name worktree-base-dir proj-root))
         (optimize-dir (expand-file-name "optimize" worktree-base))
         (suffix (gptel-auto-workflow--experiment-suffix))
          (pattern (format "%s\\(?:-r[[:alnum:]]+\\)?-exp"
                           (regexp-quote suffix)))
         (removed 0)
         (removed-branches (make-hash-table :test 'equal)))
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
                (puthash branch t removed-branches)
                (cl-incf removed))
            (error
             (message "[auto-workflow] Failed to cleanup %s: %s" path err))))))
    (dolist (branch (gptel-auto-workflow--optimize-branches proj-root))
      (unless (gethash branch removed-branches)
        (condition-case err
            (progn
              (call-process "git" nil nil nil "branch" "-D" branch)
              (puthash branch t removed-branches)
              (cl-incf removed))
          (error
           (message "[auto-workflow] Failed to delete optimize branch %s: %s"
                    branch err)))))
    (cl-incf removed
             (gptel-auto-workflow--cleanup-integrated-remote-optimize-branches
              proj-root))
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
               (message "[auto-workflow] Failed to cleanup %s: %s" dir err)))))))
    (when (> removed 0)
      (message "[auto-workflow] Cleaned %d old optimize items" removed))
    removed))

(defun gptel-auto-workflow--cleanup-stale-state ()
  "Clean up stale timers, buffers, and state from aborted runs."
  (let* ((proj-root (gptel-auto-workflow--default-dir))
         (cleaned 0)
         (queued-run-id
          (and (bound-and-true-p gptel-auto-workflow--cron-job-running)
               (or (and (stringp gptel-auto-workflow--run-id)
                        (not (string-empty-p gptel-auto-workflow--run-id))
                        gptel-auto-workflow--run-id)
                   (and (stringp gptel-auto-workflow--status-run-id)
                        (not (string-empty-p gptel-auto-workflow--status-run-id))
                        gptel-auto-workflow--status-run-id)))))
    (when proj-root
      (my/gptel--reset-agent-task-state)
      (gptel-auto-workflow--clear-runtime-subagent-provider-overrides)
      (gptel-mementum--reset-synthesis-state)
      (gptel-auto-experiment--reset-grade-state)
      (when gptel-auto-workflow--cron-job-timer
        (cancel-timer gptel-auto-workflow--cron-job-timer)
        (setq gptel-auto-workflow--cron-job-timer nil))
      (gptel-auto-workflow--stop-status-refresh-timer)
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
            gptel-auto-workflow--status-run-id queued-run-id
            gptel-auto-workflow--run-id queued-run-id
            gptel-auto-workflow--current-target nil)
      (setq gptel-auto-workflow--stats
            (plist-put gptel-auto-workflow--stats
                       :phase (if (bound-and-true-p gptel-auto-workflow--cron-job-running)
                                  (or (plist-get gptel-auto-workflow--stats :phase)
                                      "queued")
                                "idle")))
      (gptel-auto-workflow--persist-status)
      (gptel-auto-workflow--clear-persisted-snapshot-files)
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
         (run-in-context
          (lambda (thunk)
             (if (buffer-live-p run-buffer)
                 (with-current-buffer run-buffer
                   (let ((default-directory proj-root)
                         (gptel-auto-workflow--project-root-override proj-root)
                         (gptel-auto-workflow--current-project proj-root)
                         (gptel-auto-workflow--run-project-root proj-root))
                     (funcall thunk)))
               (let ((default-directory proj-root)
                     (gptel-auto-workflow--project-root-override proj-root)
                     (gptel-auto-workflow--current-project proj-root)
                     (gptel-auto-workflow--run-project-root proj-root))
                 (funcall thunk)))))
         (all-results '())
         (kept-count 0)
         (finish
          (gptel-auto-workflow--make-idempotent-callback
           (lambda ()
             (funcall
              run-in-context
              (lambda ()
                 (let ((final-phase (if gptel-auto-experiment--quota-exhausted
                                        "quota-exhausted"
                                      "complete")))
                   (gptel-auto-workflow--clear-runtime-subagent-provider-overrides)
                   (gptel-auto-workflow--stop-status-refresh-timer)
                   (setq gptel-auto-workflow--status-run-id run-id
                         gptel-auto-workflow--running nil
                         gptel-auto-workflow--cron-job-running nil
                         gptel-auto-workflow--run-id nil
                         gptel-auto-workflow--run-project-root nil
                         gptel-auto-workflow--current-target nil
                         gptel-auto-workflow--current-project nil)
                   (set-default-toplevel-value 'gptel-auto-workflow--status-run-id run-id)
                   (set-default-toplevel-value 'gptel-auto-workflow--running nil)
                   (set-default-toplevel-value 'gptel-auto-workflow--cron-job-running nil)
                   (set-default-toplevel-value 'gptel-auto-workflow--run-id nil)
                   (set-default-toplevel-value 'gptel-auto-workflow--run-project-root nil)
                   (set-default-toplevel-value 'gptel-auto-workflow--current-target nil)
                   (set-default-toplevel-value 'gptel-auto-workflow--current-project nil)
                   (setq gptel-auto-workflow--stats
                         (plist-put gptel-auto-workflow--stats :phase final-phase))
                   (condition-case err
                       (gptel-auto-workflow--persist-status)
                     (error
                      (gptel-auto-workflow--report-finalization-error
                       "Failed to persist completion status" err)))
                   (condition-case err
                       (message "[auto-workflow] Complete: %d experiments, %d targets improved"
                                (length all-results) kept-count)
                     (error
                      (gptel-auto-workflow--report-finalization-error
                       "Failed to log completion message" err)))
                   (when completion-callback
                     (condition-case err
                         (funcall completion-callback all-results)
                       (error
                        (gptel-auto-workflow--report-finalization-error
                         "Completion callback failed" err))))
                   (condition-case err
                       (prog1
                           (gptel-auto-workflow--persist-messages-tail)
                         (gptel-auto-workflow--clear-persisted-snapshot-files))
                     (error
                      (gptel-auto-workflow--clear-persisted-snapshot-files)
                      (gptel-auto-workflow--report-finalization-error
                       "Failed to persist completion messages" err))))))))))
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
                            (funcall
                             run-in-context
                             (lambda ()
                               (setq all-results (append all-results results))
                                (setq kept-count
                                      (gptel-auto-workflow--kept-target-count all-results))
                                (setq gptel-auto-workflow--stats
                                      (plist-put gptel-auto-workflow--stats :kept kept-count))
                                (gptel-auto-workflow--persist-status)
                                (cond
                                 (gptel-auto-experiment--quota-exhausted
                                  (message "[auto-workflow] Provider quota exhausted; stopping remaining targets")
                                  (finish-run))
                                 ((and (> kept-count 0)
                                       (gptel-auto-experiment--should-reduce-experiments-p))
                                  (message "[auto-workflow] API pressure with %d kept target(s); stopping remaining targets"
                                           kept-count)
                                  (finish-run))
                                 (t
                                  (run-next (cdr remaining-targets)))))))))))
                   (gptel-auto-experiment-loop target target-complete))))))
      (funcall run-in-context (lambda () (run-next targets))))))

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
             (line-count (with-temp-buffer (insert extracted) (count-lines 1 (point-max)))))
        (if (< line-count 50)
            (message "[mementum] Skip '%s': only %d lines (need ≥50)" topic line-count)
          (if (bound-and-true-p gptel-auto-workflow--headless)
              (message "[mementum] Pending '%s': human approval required before saving (%d lines)"
                       topic line-count)
            (let ((preview-buffer (get-buffer-create "*Synthesis Preview*")))
              (with-current-buffer preview-buffer
                (erase-buffer)
                (insert (format "# Synthesis Preview: %s\n\n" topic))
                (insert (format "Generated: %d lines\n\n" line-count))
                (insert "## Generated Knowledge Page\n\n")
                (insert extracted)
                (goto-char (point-min)))
              (display-buffer preview-buffer)
              (when (y-or-n-p (format "Create knowledge page for '%s'? (%d lines) " topic line-count))
                (gptel-mementum--save-knowledge-page topic files extracted))))))
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
    (message "[mementum] Created knowledge page draft: %s (%d lines)"
             know-file
             (with-temp-buffer (insert content) (count-lines 1 (point-max))))
    (message "[mementum] Review and commit manually: %s"
             (file-relative-name know-file (gptel-auto-workflow--project-root)))
    know-file))



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
