;;; strategy-failure-trajectory-tracking.el --- Track failure trajectories to avoid repeated patterns -*- lexical-binding: t; -*-
;; Hypothesis: Knowing what was tried before and still failed prevents redundant exploration
;; Axis: D
;;
(require 'gptel-tools-agent-prompt-build)
(require 'cl-lib)
(require 'subr-x)

(defun strategy-failure-trajectory-tracking-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with failure trajectory analysis to avoid repeated failures."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                        target experiment-id max-experiments analysis baseline previous-results))
          ;; Compute trajectories: patterns that appear across multiple experiments
          (trajectories (cl-loop for result in previous-results
                                 when (plist-get result :patterns)
                                collect it))
         ;; Generate anti-pattern guidance
         (anti-pattern-section
          (if (and trajectories (> (length trajectories) 1))
              (concat "\n\n;; Failure Trajectory Avoidance\n"
                      ";; Patterns that persisted across experiments (avoid re-exploring):\n"
                       (string-join (cl-loop for trajectory in trajectories
                                            when trajectory
                                            collect (format "- %s" trajectory))
                                    "\n"))
            "")))
    (concat base-prompt anti-pattern-section)))

(defun strategy-failure-trajectory-tracking-get-metadata ()
  (list :name "failure-trajectory-tracking"
        :version "1.0"
        :hypothesis "Tracking failure trajectories across experiments prevents redundant exploration"
        :axis "D"
        :components ["trajectory-analysis" "failure-patterns"]))

(provide 'strategy-failure-trajectory-tracking)
