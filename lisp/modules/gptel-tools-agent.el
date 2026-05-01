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

;; Split modules
(require 'gptel-tools-agent-base)
(require 'gptel-tools-agent-git)
(require 'gptel-tools-agent-subagent)
(require 'gptel-tools-agent-runtime)
(require 'gptel-tools-agent-worktree)
(require 'gptel-tools-agent-staging-baseline)
(require 'gptel-tools-agent-staging-merge)
(require 'gptel-tools-agent-benchmark)
(require 'gptel-tools-agent-prompt-analyze)
(require 'gptel-tools-agent-prompt-build)
(require 'gptel-tools-agent-error)
(require 'gptel-tools-agent-experiment-core)
(require 'gptel-tools-agent-experiment-loop)
(require 'gptel-tools-agent-main)
(require 'gptel-tools-agent-research)

(provide 'gptel-tools-agent)
;;; gptel-tools-agent.el ends here
