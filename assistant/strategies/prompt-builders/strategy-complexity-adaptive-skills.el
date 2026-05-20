;;; strategy-complexity-adaptive-skills.el --- Select skills based on computed complexity -*- lexical-binding: t; -*-
;; Hypothesis: Dynamically selecting skills based on code complexity metrics improves targeted guidance.
;; Axis: D+E
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-complexity-adaptive-skills-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET with complexity-based skill selection.
EXPERIMENT-ID: current experiment number.
MAX-EXPERIMENTS: total experiments planned.
ANALYSIS: plist with :patterns :recommendations from previous experiments.
BASELINE: current baseline score.
PREVIOUS-RESULTS: list of previous experiment plists."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (complexity-data (compute-file-complexity-metrics target))
         (selected-skills (select-skills-by-complexity complexity-data))
         (skill-context (when selected-skills
                         (format "\n\n;; Complexity-Aware Skill Guidance\n;; File complexity: %s (high=%s, nested=%s, functions=%s)\n;; Selected skills: %s\n"
                                 (plist-get complexity-data :overall-score)
                                 (plist-get complexity-data :high-complexity-regions)
                                 (plist-get complexity-data :max-nesting)
                                 (plist-get complexity-data :function-count)
                                 (mapconcat 'identity selected-skills ", ")))))
    (concat base-prompt (or skill-context ""))))

(defun compute-file-complexity-metrics (target)
  "Compute complexity metrics for TARGET file.
Returns plist with :overall-score :function-count :max-nesting :high-complexity-regions :line-count."
  (let ((line-count 0)
        (function-count 0)
        (max-nesting 0)
        (current-nesting 0)
        (high-complexity-regions 0))
    (when (and target (file-exists-p target))
      (with-temp-buffer
        (insert-file-contents target)
        (setq line-count (count-lines (point-min) (point-max)))
        (goto-char (point-min))
        (while (re-search-forward "^\\s-*(" nil t)
          (let ((sexp-start (match-beginning 0)))
            (ignore-errors
              (goto-char sexp-start)
              (let ((sexp (read (current-buffer))))
                (when (and (listp sexp) (symbolp (car sexp))
                           (string-match-p "^def" (symbol-name (car sexp))))
                  (setq function-count (1+ function-count))
                  (setq current-nesting (count-matching-subroutines sexp))
                  (when (> current-nesting max-nesting)
                    (setq max-nesting current-nesting))
                  (when (> current-nesting 3)
                    (setq high-complexity-regions (1+ high-complexity-regions))))))))
        (let ((score (min 10 (floor (+ (* 0.1 line-count)
                                       (* 0.5 function-count)
                                       (* 2 max-nesting)
                                       (* 3 high-complexity-regions))))))
          (list :overall-score score
                :function-count function-count
                :max-nesting max-nesting
                :high-complexity-regions high-complexity-regions
                :line-count line-count))))))

(defun count-matching-subroutines (sexp)
  "Count depth of nested conditionals in SEXP."
  (if (listp sexp)
      (apply #'max 0 (mapcar #'count-matching-subroutines (cdr sexp)))
    0))

(defun select-skills-by-complexity (complexity-data)
  "Select appropriate skills based on COMPLEXITY-DATA."
  (let ((score (plist-get complexity-data :overall-score))
        (skills '()))
    (when (>= score 3)
      (push "refactoring" skills))
    (when (>= score 5)
      (push "simplification" skills))
    (when (> (plist-get complexity-data :max-nesting) 4)
      (push "nesting-reduction" skills))
    (when (> (plist-get complexity-data :function-count) 10)
      (push "modularization" skills))
    skills))

(defun strategy-complexity-adaptive-skills-get-metadata ()
  "Return metadata for this strategy."
  (list :name "complexity-adaptive-skills"
        :version "1.0"
        :hypothesis "Computing code complexity metrics and selecting skills accordingly provides more targeted guidance"
        :axis "D+E"
        :components ["complexity-metrics" "adaptive-skill-selection"]))

(provide 'strategy-complexity-adaptive-skills)