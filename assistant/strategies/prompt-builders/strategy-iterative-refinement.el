;;; strategy-iterative-refinement.el --- Accumulated learning from experiment history -*- lexical-binding: t; -*-
;; Hypothesis: Weighting recent experimental outcomes more heavily improves pattern recognition.
;; Axis: F

(require 'gptel-tools-agent-prompt-build)

(defun strategy-iterative-refinement--compute-recency-weight (index total)
  "Compute exponential recency weight for experiment at INDEX out of TOTAL."
  (let ((position (/ (float index) (max 1 (1- total)))))
    (exp (* 0.5 (- 1 position)))))

(defun strategy-iterative-refinement--aggregate-patterns (previous-results)
  "Aggregate and weight patterns from PREVIOUS-RESULTS by recency."
  (when previous-results
    (let ((weighted-patterns '())
          (total (length previous-results)))
      (dotimes (i total)
        (let* ((result (nth i previous-results))
               (weight (strategy-iterative-refinement--compute-recency-weight i total))
               (patterns (plist-get result :patterns)))
          (when patterns
            (dolist (pattern patterns)
              (push (cons weight pattern) weighted-patterns)))))
      weighted-patterns)))

(defun strategy-iterative-refinement--format-weighted-guidance (weighted-patterns)
  "Format weighted patterns into guidance text."
  (when weighted-patterns
    (let* ((sorted (sort weighted-patterns (lambda (a b) (> (car a) (car b)))))
           (top-patterns (seq-take sorted 5))
           (guidance "\n\n;; Iterative refinement guidance from prior experiments:"))
      (dolist (wp top-patterns)
        (let* ((pattern (cdr wp))
               (weight (car wp))
               (type (plist-get pattern :type))
               (desc (plist-get pattern :description)))
          (when desc
            (setq guidance (concat guidance
                                   (format "\n;; [weight: %.2f] %s: %s" weight type desc))))))
      guidance)))

(defun strategy-iterative-refinement-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with iterative refinement based on weighted experiment history."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (weighted-patterns (strategy-iterative-refinement--aggregate-patterns previous-results))
         (refinement-guidance (strategy-iterative-refinement--format-weighted-guidance weighted-patterns)))
    (concat base-prompt (or refinement-guidance ""))))

(defun strategy-iterative-refinement-get-metadata ()
  (list :name "iterative-refinement"
        :version "1.0"
        :hypothesis "Weighting recent experimental outcomes more heavily improves pattern recognition."
        :axis "F"
        :components ["pattern-aggregation" "recency-weighting" "experiment-history"]))

(provide 'strategy-iterative-refinement)