;;; gptel-tools-agent.el --- Subagent delegation for gptel -*- no-byte-compile: t; lexical-binding: t; -*-

;; Author: David Wu
;; Version: 1.0.0
;;
;; Subagent delegation with timeout and model override.
;; Split into modules (all under 1000 lines).

;; Core requires
(require 'cl-lib)
(require 'subr-x)
(require 'gptel nil t)
(require 'gptel-agent nil t)
(require 'magit-git nil t)

;; Split modules.  Load source files explicitly so cron `load-file' hot-reloads
;; patched module definitions in long-lived workflow daemons.
(defvar gptel-tools-agent--module-dir nil
  "Directory containing gptel-tools-agent modules.")

(defun gptel-tools-agent--ensure-module-dir ()
  "Ensure `gptel-tools-agent--module-dir' is set and return it.
Signals an error if the directory cannot be determined or does not exist."
  (unless gptel-tools-agent--module-dir
    (let ((file (or (bound-and-true-p load-file-name)
                    buffer-file-name)))
      (unless file
        (error "Cannot determine module directory"))
      (let ((dir (file-name-directory file)))
        (unless (and dir (file-directory-p dir))
          (error "Module directory does not exist: %s" dir))
        (setq gptel-tools-agent--module-dir dir))))
  gptel-tools-agent--module-dir)

(defun gptel-tools-agent--module-path (feature-name)
  "Return the full path for module with FEATURE-NAME (a symbol).
Ensures the module directory exists before constructing the path."
  (unless (and feature-name (symbolp feature-name))
    (error "Feature name must be a non-nil symbol: %S" feature-name))
  (expand-file-name (format "%s.el" feature-name)
                    (gptel-tools-agent--ensure-module-dir)))

(defun gptel-tools-agent--load-module (feature)
  "Load split module FEATURE from this directory, falling back to `require'."
  (unless (and feature (symbolp feature))
    (error "Feature must be a non-nil symbol: %S" feature))
  (when (string-match-p "[/\\]" (symbol-name feature))
    (error "Feature name contains invalid characters: %S" feature))
  (unless (featurep feature)
    (let ((source (gptel-tools-agent--module-path feature)))
      (if (file-readable-p source)
          (condition-case err
              (progn
                (load source nil 'nomessage)
                (unless (featurep feature)
                  (error "Module %s did not provide feature %S" source feature)))
            (error
             (let ((err-msg (error-message-string err)))
               (if (string-match-p "did not provide feature" err-msg)
                   (error "%s" err-msg)
                 (condition-case require-err
                     (require feature)
                   (error
                    (error "Failed to load %s: %s (require also failed: %s)"
                           source err-msg (error-message-string require-err))))))))
        (require feature)))))

(dolist (feature '(gptel-tools-agent-base
                   gptel-tools-agent-git
                   gptel-tools-agent-subagent
                   gptel-tools-agent-runtime
                   gptel-tools-agent-worktree
                   gptel-tools-agent-staging-baseline
                   gptel-tools-agent-staging-merge
                   gptel-tools-agent-validation
                   gptel-tools-agent-benchmark
                   gptel-tools-agent-prompt-analyze
                   gptel-tools-agent-prompt-build
                   gptel-tools-agent-strategy-harness
                   gptel-tools-agent-strategy-evolver
                   gptel-tools-agent-error
                   gptel-tools-agent-experiment-core
                   gptel-tools-agent-experiment-loop
                   gptel-tools-agent-main
                   gptel-tools-agent-research))
  (condition-case err
      (gptel-tools-agent--load-module feature)
    (error
     (message "Warning: Failed to load module %S: %s"
              feature (error-message-string err)))))

(provide 'gptel-tools-agent)
;;; gptel-tools-agent.el ends here
