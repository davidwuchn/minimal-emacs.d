;;; strategy-candidate-template-d-3.el --- Switch to critique envelope when frontier saturates -*- lexical-binding: t; -*-
;; Hypothesis: When the improvement frontier saturates, reframing the task as critique of previous attempts breaks plateaus better than continued generation.
;; Axis: A
;;
;; IMPORTANT: Use a MEANINGFUL name replacing NAME (e.g., strategy-weighted-skills,
;; strategy-outcome-reasoning, not strategy-evolved-0006).
;; The name should describe the core mechanism in 2-4 hyphenated words.

(require 'gptel-tools-agent-prompt-build)

(defun strategy-candidate-template-d-3-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET using saturation-aware template envelope.
EXPERIMENT-ID: current experiment number.
MAX-EXPERIMENTS: total experiments planned.
ANALYSIS: plist with :patterns :recommendations from previous experiments.
BASELINE: current baseline score.
PREVIOUS-RESULTS: list of previous experiment plists."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (saturation (gptel-auto-experiment--frontier-saturation-guidance previous-results))
         (saturated-p (and saturation (string-match-p "saturat" saturation)))
         (envelope (if saturated-p
                       "CRITIQUE PROTOCOL: The improvement frontier has plateaued. Do not generate a solution yet. First, list 3 flawed assumptions in the previous approaches described below. Then provide a corrected approach.\n\n"
                     "GENERATION PROTOCOL: Standard improvement instructions follow.\n\n")))
    (concat envelope base-prompt)))

(defun strategy-candidate-template-d-3-get-metadata ()
  "Return metadata for this strategy."
  (list :name "candidate-template-d-3"
        :version "1.0"
        :hypothesis "When the improvement frontier saturates, reframing the task as critique of previous attempts breaks plateaus better than continued generation."
        :axis "A"
        :components ["saturation-detection" "template-envelope" "critique-mode"]))

(provide 'strategy-candidate-template-d-3)