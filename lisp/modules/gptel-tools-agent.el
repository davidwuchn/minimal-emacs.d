;;; gptel-tools-agent.el --- Subagent delegation for gptel -*- no-byte-compile: t; lexical-binding: t; -*-

;; Author: David Wu
;; Version: 1.0.0
;;
;; Subagent delegation with timeout and model override.
;; Split into modules (all under 1000 lines).

;; Core requires
(require 'cl-lib)
(require 'subr-x)
(require 'gptel)
(require 'gptel-agent)
(require 'magit-git nil t)

;; Split modules.  Load source files explicitly so cron `load-file' hot-reloads
;; patched module definitions in long-lived workflow daemons.
(defun gptel-tools-agent--load-module (feature)
  "Load split module FEATURE from this directory, falling back to `require'."
  (let* ((dir (file-name-directory (or load-file-name buffer-file-name)))
         (source (and dir (expand-file-name (format "%s.el" feature) dir))))
    (if (and source (file-readable-p source))
        (load source nil 'nomessage)
      (require feature))))

(dolist (feature '(gptel-tools-agent-base
                   gptel-tools-agent-git
                   gptel-tools-agent-subagent
                   gptel-tools-agent-runtime
                   gptel-tools-agent-worktree
                   gptel-tools-agent-staging-baseline
                   gptel-tools-agent-staging-merge
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
  (gptel-tools-agent--load-module feature))

(provide 'gptel-tools-agent)
;;; gptel-tools-agent.el ends here
