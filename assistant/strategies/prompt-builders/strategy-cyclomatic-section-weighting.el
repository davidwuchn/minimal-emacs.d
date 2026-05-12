;;; strategy-cyclomatic-section-weighting.el --- Weight sections by code complexity -*- lexical-binding: t; -*-
;; Hypothesis: Prioritizing complex code sections in prompts will lead to better handling of edge cases
;; Axis: D (Variable computation)
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-cyclomatic-section-weighting-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET using cyclomatic complexity-weighted section ordering.
EXPERIMENT-ID: current experiment number.
MAX-EXPERIMENTS: total experiments planned.
ANALYSIS: plist with :patterns :recommendations from previous experiments.
BASELINE: current baseline score.
PREVIOUS-RESULTS: list of previous experiment plists."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (complexity-metrics (strategy-compute-cyclomatic-complexity target))
         (high-complexity-funcs (cl-loop for (func . complexity) in complexity-metrics
                                         when (> complexity 5)
                                         collect (cons func complexity)))
         (complexity-guidance (when high-complexity-funcs
                                (concat "\n\n;; High complexity functions (require extra caution):\n"
                                        (mapconcat (lambda (p)
                                                     (format "- %s (complexity: %d)" (car p) (cdr p)))
                                                   high-complexity-funcs "\n")))))
    (concat base-prompt (or complexity-guidance ""))))

(defun strategy-compute-cyclomatic-complexity (target)
  "Compute cyclomatic complexity for each defun in TARGET.
Returns alist of (function-name . complexity-score)."
  (with-temp-buffer
    (insert-file-contents target)
    (goto-char (point-min))
    (let ((func-list '()))
      (while (re-search-forward
              (concat "^\\s-*(defun\\s-+\\(?2:[a-z0-9_/-]+\\)\\s-+")
              nil t)
        (let* ((func-start (match-beginning 0))
               (func-name (match-string 2))
               (func-end (condition-case nil
                             (progn (forward-sexp) (point))
                           (scan-error (point-max))))
               (func-body (buffer-substring-no-properties func-start func-end)))
          (forward-sexp)
          (let* ((branch-count (cl-loop for pattern in '("when\\b" "unless\\b" "if\\b" "cond\\b" "and\\b" "or\\b" "while\\b" "catch\\b")
                                        count (string-match pattern func-body)))
                 (complexity (max 1 (+ 1 branch-count))))
            (push (cons func-name complexity) func-list))))
      func-list)))

(defun strategy-cyclomatic-section-weighting-get-metadata ()
  (list :name "cyclomatic-section-weighting"
        :version "1.0"
        :hypothesis "Prioritizing complex code sections in prompts will lead to better handling of edge cases"
        :axis "D"
        :components ["complexity-metrics" "section-prioritization"]))

(provide 'strategy-cyclomatic-section-weighting)