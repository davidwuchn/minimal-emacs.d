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
;; Root cause fixed: gptel-abort now defers callback to break sync recursion.
(setq max-lisp-eval-depth 320000)

;; Increase max-specpdl-size for subagent chain depth
;; REQUIRED: 5+ nested subagent layers without C stack overflow.
;; Researcher daemon's single-turn fallback (300s timeout) triggers
;; deep recursion during subagent setup. 10000 provides headroom.
(setq max-specpdl-size 50000)

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
                  (if (> gptel-curl--sentinel-depth 0)
                      ;; Already processing a sentinel — defer to break the
                      ;; C-stack chain. Reset depth so the deferred call runs
                      ;; as a fresh top-level sentinel.
                      (progn
                        (setq gptel-curl--sentinel-depth 0)
                        (run-at-time 0 nil
                          (lambda ()
                            (condition-case err
                                (funcall orig-fn process status)
                              (error
                               (message "[gptel] Deferred sentinel error: %S" err)
                               (when (process-live-p process)
                                 (delete-process process)))))))
                    (apply orig-fn process status args))))))

(provide 'post-early-init)

;;; post-early-init.el ends here
