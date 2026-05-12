;;; strategy-progress-adaptive-compression.el --- Shorten failure details if recent progress exists -*- lexical-binding: t; -*-
;; Hypothesis: When experiments already show improvement, detailed failure logs are less useful; brevity focuses on novelty.
;; Axis: F (Adaptive compression)
;;
;; IMPORTANT: The name "progress-adaptive-compression" reflects the mechanism of compressing failure context based on score trends.

(require 'gptel-tools-agent-prompt-build)

(defun strategy-progress-adaptive-compression-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET: if any previous experiment improved over baseline, replace the failure patterns section with a concise note."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (any-progress (seq-find (lambda (res) (> (or (plist-get res :score) 0) baseline))
                                 previous-results)))
    (if any-progress
        ;; Replace the entire failure patterns block with a short placeholder.
        ;; The block is assumed to start with ";; ### Failure Patterns" and run until the next section.
        (replace-regexp-in-string
         ";; ### Failure Patterns.*?\\(;; ###\\|\\'\\)"
         ";; ### Failure Patterns (supressed due to progress)\n;; Previous experiments have improved; focus on novel directions.\n\n"
         base-prompt)
      base-prompt)))

(defun strategy-progress-adaptive-compression-get-metadata ()
  (list :name "progress-adaptive-compression"
        :version "1.0"
        :hypothesis "Dynamically shortening failure logs when progress exists reduces noise and encourages exploration."
        :axis "F"
        :components ["adaptive-compression" "score-tracking"]))

(provide 'strategy-progress-adaptive-compression)