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

;; Disable native compilation for workflow daemon to prevent stale cache issues
(when (my/workflow-daemon-p)
  (setq native-comp-jit-compilation nil)
  (setq native-comp-enable-subprocesses nil))

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

(provide 'post-early-init)

;;; post-early-init.el ends here
