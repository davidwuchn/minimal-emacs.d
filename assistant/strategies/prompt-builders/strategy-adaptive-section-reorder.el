;;; strategy-adaptive-section-reorder.el --- Experiment-driven section reordering -*- lexical-binding: t; -*-
;; Hypothesis: Dynamically reordering prompt sections based on past experiment impact scores improves effectiveness.
;; Axis: C

(require 'gptel-tools-agent-prompt-build)

(defun strategy-adaptive-section-reorder-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET with experiment-driven section reordering."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (section-scores (strategy-adaptive-section-reorder--compute-scores previous-results))
         (reordered-sections (strategy-adaptive-section-reorder--apply-ordering base-prompt section-scores)))
    reordered-sections))

(defun strategy-adaptive-section-reorder--compute-scores (previous-results)
  "Compute impact scores for each section from PREVIOUS-RESULTS."
  (let ((scores (list (cons "context" 0)
                      (cons "constraints" 0)
                      (cons "guidance" 0)
                      (cons "skills" 0))))
    (dolist (result previous-results)
      (when (plist-get result :success)
        (dolist (section scores)
          (setcdr section (+ (cdr section) 1)))))
    scores))

(defun strategy-adaptive-section-reorder--apply-ordering (prompt scores)
  "Apply section reordering to PROMPT based on SCORES."
  (let* ((sorted (sort scores (lambda (a b) (> (cdr a) (cdr b)))))
         (reorder-guidance (concat "\n\n;; Adaptive Section Ordering\n"
                                   ";; Based on experiment analysis, prioritize these sections:\n"
                                   (mapconcat (lambda (s) (format ";; - %s (priority: %d)" (car s) (cdr s)))
                                              sorted "\n"))))
    (concat prompt reorder-guidance)))

(defun strategy-adaptive-section-reorder-get-metadata ()
  (list :name "adaptive-section-reorder"
        :version "1.0"
        :hypothesis "Dynamically reordering prompt sections based on past experiment impact scores improves effectiveness."
        :axis "C"
        :components ["section-ordering" "experiment-analysis" "impact-scoring"]))

(provide 'strategy-adaptive-section-reorder)