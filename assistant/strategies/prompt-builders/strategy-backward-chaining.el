;;; strategy-backward-chaining.el --- Goal-first prompt architecture -*- lexical-binding: t; -*-
;; Hypothesis: Structuring prompts to lead with success criteria before problem state improves agent goal clarity.
;; Axis: A
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-backward-chaining-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET using backward-chaining architecture.
Leads with desired outcomes before presenting current problems.
EXPERIMENT-ID: current experiment number.
MAX-EXPERIMENTS: total experiments planned.
ANALYSIS: plist with :patterns :recommendations from previous experiments.
BASELINE: current baseline score.
PREVIOUS-RESULTS: list of previous experiment plists."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         ;; Extract success criteria from analysis patterns
         (failure-patterns (plist-get analysis :patterns))
         (recommendations (plist-get analysis :recommendations))
         ;; Build backward-chained section
         (goal-section "\n\n;; === GOAL-FIRST REASONING ===\n;; Before addressing failures, establish what success looks like:\n;; 1. Code should be maintainable and follow language idioms\n;; 2. Functions should have clear contracts and minimal side effects\n;; 3. Error handling should be explicit and informative\n;; 4. Patterns that caused failures in similar code should be avoided\n;;\n;; Root Cause Categories to Avoid:\n")
         (pattern-section (when failure-patterns
                            (mapconcat (lambda (p)
                                         (format ";; - %s" p))
                                       (cl-subseq failure-patterns 0 (min 5 (length failure-patterns)))
                                       "\n")))
         (reasoning-section "\n;;\n;; Working Backward:\n;; To achieve these goals, identify which specific failures in the code\n;; prevent each success criterion from being met."))
    (concat base-prompt goal-section (or pattern-section "") reasoning-section)))

(defun strategy-backward-chaining-get-metadata ()
  (list :name "backward-chaining"
        :version "1.0"
        :hypothesis "Leading with success criteria before presenting problems improves agent goal clarity and reduces fixation on symptoms."
        :axis "A"
        :components ["goal-first" "backward-reasoning"]))

(provide 'strategy-backward-chaining)