;;; strategy-improvement-velocity.el --- Velocity-weighted guidance prioritization -*- lexical-binding: t; -*-
;; Hypothesis: Weighting guidance by improvement velocity prioritizes insights that worked before
;; Axis: D
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-improvement-velocity-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with velocity-weighted guidance prioritization."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (velocity-score (cl-loop for result in previous-results
                                  when (and (plist-get result :score)
                                            (> (plist-get result :score) 0))
                                  collect (- (plist-get result :score) baseline)))
         (avg-velocity (/ (apply '+ velocity-score) (max 1 (length velocity-score))))
         (velocity-guidance (format ";; Improvement velocity: %.2f (higher = faster improvement trajectory)\n;; Prioritize approaches that produced rapid gains"
                                    avg-velocity)))
    (concat base-prompt "\n\n" velocity-guidance)))

(defun strategy-improvement-velocity-get-metadata ()
  (list :name "improvement-velocity"
        :version "1.0"
        :hypothesis "Weighting guidance by improvement velocity prioritizes insights that worked before"
        :axis "D"
        :components ["velocity-computation" "weighted-guidance"]))

(provide 'strategy-improvement-velocity)