;;; strategy-cyclomatic-weighted-guidance.el --- Weight guidance by code complexity -*- lexical-binding: t; -*-
;; Hypothesis: Weighting improvement guidance by cyclomatic complexity focuses attention on high-risk code sections.
;; Axis: D
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-cyclomatic-weighted-guidance-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt weighting guidance by cyclomatic complexity for TARGET."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (complexity-guidance "\n\n;; Cyclomatic Complexity Weighted Guidance\n;; Apply heightened scrutiny to functions with high cyclomatic complexity (>10).\n;; Prioritize simplification and clarity improvements for complex code sections.\n;; Low complexity code (<5) can tolerate stylistic variations. Focus improvement\n;; efforts where complexity indicates maintenance risk."))
    (concat base-prompt complexity-guidance)))

(defun strategy-cyclomatic-weighted-guidance-get-metadata ()
  (list :name "cyclomatic-weighted-guidance"
        :version "1.0"
        :hypothesis "Weighting improvement guidance by cyclomatic complexity focuses attention on high-risk code sections"
        :axis "D"
        :components ["complexity-metrics" "risk-weighting"]))

(provide 'strategy-cyclomatic-weighted-guidance)