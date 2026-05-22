;;; strategy-convergence-adaptive-ordering.el --- Outcome-predictive section ordering -*- lexical-binding: t; -*-
;; Hypothesis: Reordering prompt sections based on convergence trajectory improves final outcome quality.
;; Axis: C (Section ordering)

(require 'gptel-tools-agent-prompt-build)

(defun strategy-convergence-adaptive-ordering-build-prompt
    (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with convergence-adaptive section ordering.
Orders sections based on whether the experiment is converging or diverging."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         ;; Determine convergence state
         (convergence-state (strategy-convergence-adaptive-ordering--assess-state
                             experiment-id max-experiments baseline previous-results))
         ;; Get reordered guidance
         (ordered-guidance (strategy-convergence-adaptive-ordering--reorder-guidance
                            convergence-state analysis)))
    (concat base-prompt
            "\n\n;; Convergence-Adaptive Section\n"
            ordered-guidance)))

(defun strategy-convergence-adaptive-ordering--assess-state
    (experiment-id max-experiments baseline previous-results)
  "Assess whether experiment is converging, diverging, or stable.
Returns symbol: :converging, :diverging, or :stable."
  (let* ((scores (mapcar (lambda (r) (plist-get r :score)) previous-results))
         (recent-window (last scores (min 3 (length scores))))
         (older-window (butlast scores (max 0 (- (length scores) 6)))))
    (cond ((<= (length scores) 2) :stable)
          ((and older-window recent-window)
           (let ((recent-avg (/ (apply #'+ recent-window) (float (length recent-window))))
                 (older-avg (/ (apply #'+ older-window) (float (length older-window))))
                 (improvement-threshold 0.05)
                 (decline-threshold 0.05))
             (cond ((> (- recent-avg older-avg) improvement-threshold) :converging)
                   ((< (- recent-avg older-avg) (- decline-threshold)) :diverging)
                   (t :stable))))
          (t :stable))))

(defun strategy-convergence-adaptive-ordering--reorder-guidance (state analysis)
  "Reorder guidance sections based on convergence STATE.
Returns reordered guidance string."
  (let* ((patterns (plist-get analysis :patterns))
         (recommendations (plist-get analysis :recommendations))
         (pattern-section (gptel-auto-experiment--format-failure-patterns patterns))
         (rec-section (mapconcat #'identity recommendations "\n")))
    (pcase state
      (:converging
       (concat "Focus on refinement rather than major changes.\n"
               "Recommendations:\n" rec-section
               "\nObserved patterns:\n" pattern-section))
      (:diverging
       (concat "Previous changes may have introduced issues. Prioritize:\n"
               "1. Identify regressions from recent changes\n"
               "2. Revert high-risk modifications\n"
               "3. Apply conservative fixes only\n"
               "Observed patterns:\n" pattern-section))
      (:stable
       (concat "Incremental improvements recommended.\n"
               "Recommendations:\n" rec-section
               "\nObserved patterns:\n" pattern-section)))))

(defun strategy-convergence-adaptive-ordering-get-metadata ()
  (list :name "convergence-adaptive-ordering"
        :version "1.0"
        :hypothesis "Reordering guidance by convergence state produces better final outcomes"
        :axis "C"
        :components ["convergence-assessment" "adaptive-reordering"]))

(provide 'strategy-convergence-adaptive-ordering)