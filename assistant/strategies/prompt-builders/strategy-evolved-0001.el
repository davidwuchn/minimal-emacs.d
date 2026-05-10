;;; strategy-evolved-0001.el --- Branch prompt template by experiment maturity -*- lexical-binding: t; -*-
;; Hypothesis: Early experiments need exploratory architecture while late experiments need surgical focus.
;; Axis: A
;;
;; IMPORTANT: Use a MEANINGFUL name replacing NAME (e.g., strategy-weighted-skills,
;; strategy-outcome-reasoning, not strategy-evolved-0006).
;; The name should describe the core mechanism in 2-4 hyphenated words.

(require 'gptel-tools-agent-prompt-build)

(defun strategy-evolved-0001-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET using strategy evolved-0001.
EXPERIMENT-ID: current experiment number.
MAX-EXPERIMENTS: total experiments planned.
ANALYSIS: plist with :patterns :recommendations from previous experiments.
BASELINE: current baseline score.
PREVIOUS-RESULTS: list of previous experiment plists."
  (let* ((maturity-ratio (if (> max-experiments 0)
                             (/ (float experiment-id) (float max-experiments))
                           0.0))
         (template-name (cond
                         ((< maturity-ratio 0.33) "exploratory")
                         ((< maturity-ratio 0.66) "refinement")
                         (t "surgical")))
         (template (condition-case nil
                       (gptel-auto-workflow--load-prompt-template template-name)
                     (error nil)))
         (base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (branched-prompt (if template
                              (gptel-auto-workflow--substitute-template
                               template
                               (list :base base-prompt
                                     :experiment-id experiment-id
                                     :max-experiments max-experiments
                                     :baseline baseline))
                            base-prompt)))
    branched-prompt))

(defun strategy-evolved-0001-get-metadata ()
  "Return metadata for this strategy."
  (list :name "evolved-0001"
        :version "1.0"
        :hypothesis "Early experiments need exploratory architecture while late experiments need surgical focus."
        :axis "A"
        :components ["template-branching" "maturity-ratio" "adaptive-architecture"]))

(provide 'strategy-evolved-0001)