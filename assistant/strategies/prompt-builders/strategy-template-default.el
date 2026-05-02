;;; strategy-template-default.el --- Default template-based prompt builder -*- lexical-binding: t; -*-
;; Strategy for gptel-tools-agent-strategy-harness
;;
;; This is the baseline strategy that uses template substitution with skills.
;; It represents the hand-engineered approach before harness evolution.

(require 'gptel-tools-agent-prompt-build)

(defun strategy-template-default-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt using the default template-based approach.
This is the baseline strategy that all evolved strategies build upon."
  (gptel-auto-experiment-build-prompt target experiment-id max-experiments analysis baseline previous-results))

(defun strategy-template-default-get-metadata ()
  "Return metadata for this strategy."
  (list :name "template-default"
        :version "1.0"
        :hypothesis "Baseline: Template substitution with skill loading"
        :axis "baseline"
        :created (format-time-string "%Y-%m-%d")
        :parent-strategies nil
        :description "Hand-engineered template with {{variable}} substitution from skills."))

;; Register self
(when (fboundp 'gptel-auto-workflow--register-strategy)
  (gptel-auto-workflow--register-strategy
   "template-default"
   #'strategy-template-default-build-prompt
   (strategy-template-default-get-metadata)))

(provide 'strategy-template-default)
;;; strategy-template-default.el ends here