;;; strategy-cross-target-injection.el --- Inject cross-target patterns -*- lexical-binding: t; -*-
;; Hypothesis: Leveraging failure patterns from other targets improves generalization
;; Axis: B
;;
;; IMPORTANT: Uses cross-target pattern synthesis to inform current target improvements.

(require 'gptel-tools-agent-prompt-build)

(defun strategy-cross-target-injection-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with cross-target pattern injection.
TARGET: current target file path.
EXPERIMENT-ID: current experiment number.
MAX-EXPERIMENTS: total experiments planned.
ANALYSIS: plist with :patterns :recommendations.
BASELINE: current baseline score.
PREVIOUS-RESULTS: list of previous experiment plists."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (cross-patterns (gptel-auto-experiment--format-cross-target-patterns target))
         (current-patterns (gptel-auto-experiment--format-failure-patterns
                            (plist-get analysis :patterns)))
         (synthesis-section
          (when (and cross-patterns (not (string-empty-p cross-patterns)))
            (format "\n\n## Cross-Target Pattern Synthesis\n%s\n\n## Current Target Patterns\n%s\n\n## Synthesis Guidance\nApply insights from cross-target patterns while adapting to current target specifics."
                    cross-patterns
                    (or current-patterns "No specific patterns detected.")))))
    (if synthesis-section
        (concat base-prompt synthesis-section)
      base-prompt)))

(defun strategy-cross-target-injection-get-metadata ()
  "Return metadata for cross-target injection strategy."
  (list :name "cross-target-injection"
        :version "1.0"
        :hypothesis "Cross-target pattern synthesis improves generalization and avoids repeated mistakes"
        :axis "B"
        :components ["cross-target" "pattern-synthesis" "generalization"]))

(provide 'strategy-cross-target-injection)