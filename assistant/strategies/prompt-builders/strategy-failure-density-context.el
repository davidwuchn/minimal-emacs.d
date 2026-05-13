;;; strategy-failure-density-context.el --- Risk-weighted context prioritization -*- lexical-binding: t; -*-
;; Hypothesis: Prioritizing context from code regions with high historical failure density improves AI targeting.
;; Axis: B/D

(require 'gptel-tools-agent-prompt-build)

(defun strategy-failure-density-context-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with risk-weighted context from high-failure-density regions."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (failure-patterns (plist-get analysis :patterns))
         (region-failures (compute-region-failure-density failure-patterns))
         (high-risk-regions (filter-high-density-regions region-failures)))
    (concat base-prompt "\n\n;; Risk-weighted context prioritization\n"
            "Focus improvements on these high-failure-density regions:\n"
            (format-region-priorities high-risk-regions)
            "\nPrioritize stability over aggressive optimization in high-risk areas.")))

(defun compute-region-failure-density (failure-patterns)
  "Compute failure density per code region from FAILURE-PATTERNS."
  (let ((density-alist nil))
    (dolist (pattern failure-patterns)
      (let* ((region (get-pattern-region pattern))
             (count (get-pattern-failure-count pattern)))
        (when region
          (push (cons region count) density-alist))))
    (if density-alist
        (sort (copy-sequence density-alist)
              (lambda (a b) (> (cdr a) (cdr b))))
      nil)))

(defun filter-high-density-regions (density-alist)
  "Return regions with failure density above median."
  (let* ((counts (mapcar #'cdr density-alist))
         (median (if counts (nth (floor (length counts) 2) (sort counts '<)) 0)))
    (cl-loop for entry in density-alist
             for region = (car entry)
             for count = (cdr entry)
             when (> count median)
             collect entry)))

(defun format-region-priorities (prioritized-regions)
  "Format prioritized regions for prompt injection."
  (mapconcat (lambda (entry)
               (format "- %s (failure count: %d)" (car entry) (cdr entry)))
             prioritized-regions "\n"))

(defun strategy-failure-density-context-get-metadata ()
  (list :name "failure-density-context"
        :version "1.0"
        :hypothesis "Prioritizing context from code regions with high historical failure density improves AI targeting."
        :axis "B/D"
        :components ["risk-weighting" "failure-density" "context-prioritization"]))

(provide 'strategy-failure-density-context)