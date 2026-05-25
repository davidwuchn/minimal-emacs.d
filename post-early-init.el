;;; post-early-init.el --- Post Early Init -*- no-byte-compile: t; lexical-binding: t; -*-

;;; Commentary:
;; This file is loaded after early-init.el but before init.el.
;; Use it for early configuration that must be set before packages are loaded.

;;; Code:

;; ═══════════════════════════════════════════════════════════════════════════
;; Prevent multiple Emacs daemons
;; ═══════════════════════════════════════════════════════════════════════════
;; Check if another daemon is already running before this one fully starts.
;; This prevents the "server did not start correctly" error and resource waste.
(defconst my/secondary-daemon-env "MINIMAL_EMACS_ALLOW_SECOND_DAEMON"
  "Environment variable that allows a dedicated secondary daemon to start.")

(defun my/secondary-daemon-allowed-p ()
  "Return non-nil when startup explicitly allows a second daemon."
  (string= (getenv my/secondary-daemon-env) "1"))

(defconst my/workflow-daemon-env "MINIMAL_EMACS_WORKFLOW_DAEMON"
  "Environment variable that marks a dedicated workflow daemon startup.")

(defun my/workflow-daemon-p ()
  "Return non-nil when startup is for a dedicated workflow daemon."
  (string= (getenv my/workflow-daemon-env) "1"))

(when (daemonp)
  (require 'server)
  (when (and (not (my/secondary-daemon-allowed-p))
             (server-running-p))
    (message "[daemon] Another Emacs daemon is already running, exiting this one")
    (kill-emacs 0)))

;; Set tree-sitter grammar directory early, before any tree-sitter modes are loaded
;; Note: user-emacs-directory is already set to var/ by pre-early-init.el
(setq treesit-extra-load-path
      (list (expand-file-name "tree-sitter" user-emacs-directory)))

;; ═══════════════════════════════════════════════════════════════════════════
;; AUTO-WORKFLOW: Mark all project variables as safe
;; ═══════════════════════════════════════════════════════════════════════════

;; Auto-workflow relies on dir-locals even in daemon mode, so daemon startup
;; should load safe values and skip prompts for anything unsafe.
(when (daemonp)
  (setq enable-local-variables :safe))

;; DEBUG: Log backtraces for gptel callback errors
(when (my/workflow-daemon-p)
  (defmacro with-demoted-errors (message-format &rest body)
    "Execute BODY and log full backtrace on any error."
    `(condition-case err
         (progn ,@body)
        ((debug error)
         (let ((backtrace-str (with-output-to-string (backtrace))))
           (with-temp-file "/tmp/gptel-callback-error.log"
             (insert (format "Error: %S\n\nBacktrace:\n%s\n" err backtrace-str))))
         (message ,message-format err)
         nil))))

;; These variables are used by auto-workflow in .dir-locals.el files.
(put 'gptel-auto-workflow-targets 'safe-local-variable
     (lambda (value)
       (and (listp value)
            (catch 'invalid
              (dolist (entry value t)
                (unless (stringp entry)
                  (throw 'invalid nil)))))))
(put 'gptel-auto-experiment-max-per-target 'safe-local-variable #'integerp)
(put 'gptel-auto-experiment-time-budget 'safe-local-variable #'integerp)
(put 'gptel-auto-experiment-no-improvement-threshold 'safe-local-variable #'integerp)
(put 'gptel-model 'safe-local-variable #'symbolp)
(put 'gptel-auto-workflow-projects 'safe-local-variable #'listp)
(put 'gptel-auto-workflow--project-root-override 'safe-local-variable #'stringp)

;; Suppress cl-no-applicable-method cascade during error printing
;; Emacs 30.2 cl-print-object may not handle all closure/byte-code types,
;; causing recursive errors when M-x completion triggers backtrace printing.
(setq debug-on-error nil)
(add-to-list 'debug-ignored-errors 'cl-no-applicable-method)

;; HARDEN: Defvar common closure-capture variables to prevent void-variable
;; errors from Emacs 30.1 arm64 native-comp bug in lexical closures.
;; These variables are used as parameters in functions that create closures.
;; If native-comp fails to capture them lexically, the dynamic fallback prevents crashes.
(defvar async nil)
(defvar process nil)
(defvar monitoring nil)
(defvar state nil)
(defvar machine nil)
(defvar pattern nil)
(defvar label nil)
(defvar fn-name nil)
(defvar callback nil)

;; HARDEN: Increase max-lisp-eval-depth for auto-workflow daemon to prevent
;; "Lisp nesting exceeds max-lisp-eval-depth" errors from deeply nested
;; subagent async callbacks (curl sentinel → FSM → callback → next process).
;; Default 1600 is too low for 5+ nested subagent layers.
;; 320000 caused macOS C stack overflow (64MB SIP limit) → silent SEGFAULT.
;; 15000 provides headroom while staying within macOS stack budget.
;; Root cause fixed: gptel-abort now defers callback to break sync recursion.
<<<<<<< Updated upstream
(setq max-lisp-eval-depth 15000)

;; Increase max-specpdl-size for subagent chain depth
;; REQUIRED: 5+ nested subagent layers without C stack overflow.
;; Reduced from 50000 to avoid macOS C stack exhaustion.
(setq max-specpdl-size 8000)
=======
(setq max-lisp-eval-depth 8000)

;; Increase max-specpdl-size for subagent chain depth
;; REQUIRED: 5+ nested subagent layers without C stack overflow.
;; Kept at 5000 to stay well within macOS 64MB C stack limit.
;; (320000 caused silent SEGFAULT from C stack overflow under SIP.)
(setq max-specpdl-size 5000)
>>>>>>> Stashed changes

;; HARDEN: Defer gptel curl sentinel via run-at-time 0 to break
;; synchronous recursion chains (sentinel → FSM → HTTP → sentinel).
;; The built-in sentinel-depth guard (10 max) prevents infinite loops
;; but doesn't break the sync call stack — Lisp nesting still grows
;; until it hits max-lisp-eval-depth. run-at-time breaks the chain.
;;
;; GUARD: Deferred sentinels can leak pipe FDs if the daemon blocks
;; on another pipe read before the deferred sentinel runs. A 120s
;; cleanup timer ensures orphaned process pipes are closed.
(when (daemonp)
  (with-eval-after-load 'gptel-request
    (advice-add 'gptel-curl--sentinel :around
                (lambda (orig-fn process status &rest args)
                  (if (>= gptel-curl--sentinel-depth 0)
                      (run-at-time 0 nil
                        (lambda ()
                          (condition-case err
                              (funcall orig-fn process status)
                            (error
                             (message "[gptel] Deferred sentinel error: %S" err)
                             (when (process-live-p process)
                               (delete-process process))))))
                    (apply orig-fn process status args)))))
  ;; ZOMBIE REAPER: Periodic cleanup of orphaned gptel curl processes.
  ;; gptel--request-alist can contain non-process entries (buffers from
  ;; async completions, or corrupted float values).  Filter active-procs
  ;; with processp to skip non-process keys, preventing crashes from
  ;; (process-name <buffer>) or (memq <float> ...).
  (run-at-time 60 60
               (lambda ()
                 (ignore-errors
                   (when (and (boundp 'gptel--request-alist)
                              (listp gptel--request-alist))
                     (let* ((all-keys (mapcar #'car gptel--request-alist))
                            (active-procs (cl-remove-if-not #'processp all-keys))
                            (reaped 0))
                       (dolist (proc (process-list))
                         (when (and (process-live-p proc)
                                    (let ((pname (process-name proc)))
                                      (and (stringp pname)
                                           (string-match-p "curl" pname)))
                                    (not (memq proc active-procs)))
                           (condition-case nil
                               (progn
                                 (delete-process proc)
                                 (setq reaped (1+ reaped)))
                             (error nil))))
                       (when (> reaped 0)
                         (message "[gptel] Reaped %d orphaned curl process(es)" reaped))))))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Async-safe message: prevent *Messages* buffer corruption
;; ═══════════════════════════════════════════════════════════════════════════
;;
;; Emacs's message_dolog (C) writes bytes non-atomically to *Messages*.
;; When concurrent sentinel/timer callbacks call (message ...) or C internals
;; call message_with_string simultaneously, byte writes interleave, producing
;; "Unknown message" errors and garbled text.
;;
;; Fix: disable *Messages* buffer entirely (message-log-max 0 prevents all
;; message_dolog calls at the C level). Redirect all (message ...) output to
;; a file via :after advice — each write-region call is OS-atomic, so no
;; interleaving is possible regardless of concurrency.
;;
;; C-level message_with_string (from load, save-buffer, etc.) is also
;; suppressed from *Messages* (message-log-max 0 blocks message_dolog).
(setq message-log-max 0)

(defvar mw--message-log-file nil
  "Path to OS-atomic message log file. Computed lazily on first use.")

(defvar mw--message-log-dir-created nil
  "Non-nil when the message log directory has been created.")

(defun mw-message--ensure-log-file ()
  "Lazily init the message log file path and ensure its directory exists.
Uses per-instance naming to avoid log interleaving when multiple Emacs
daemons share the same config directory."
  (unless mw--message-log-file
    (let* ((base (if (boundp 'minimal-emacs-user-directory)
                     minimal-emacs-user-directory
                   user-emacs-directory))
           (instance (format "emacs-%d" (emacs-pid)))
           (log-dir (expand-file-name "var/log" base)))
      (setq mw--message-log-file
            (expand-file-name (format "%s.log" instance) log-dir))))
  (unless mw--message-log-dir-created
    (setq mw--message-log-dir-created t)
    (condition-case nil
        (make-directory (file-name-directory mw--message-log-file) t)
      (ignore))))

;; Ensure log directory exists before first message write
(mw-message--ensure-log-file)

(defun mw-message--file-log (format-string &rest args)
  "Log message to file as OS-atomic append (no *Messages* interleaving)."
  (let* ((msg (format "%s %s\n"
                      (format-time-string "%Y-%m-%dT%H:%M:%S")
                      (apply #'format-message format-string args))))
    (condition-case nil
        (write-region msg nil mw--message-log-file 'append 'quiet)
      (ignore))))

(advice-add 'message :after #'mw-message--file-log)

(provide 'post-early-init)

;;; post-early-init.el ends here
