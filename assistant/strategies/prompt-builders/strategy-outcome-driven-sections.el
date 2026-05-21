;;; strategy-outcome-driven-sections.el --- Reorder sections based on failure pattern frequency -*- lexical-binding: t; -*-
;; Hypothesis: Prompt sections addressing most frequent failures should appear first
;; Axis: C (Section ordering) + D (Variable computation)
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-outcome-driven-sections-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET with outcome-driven section prioritization."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         ;; Compute failure frequency rankings from analysis
         (failure-priorities (strategy-outcome-driven-sections--compute-priorities analysis previous-results))
         ;; Build prioritized guidance
         (prioritized-guidance (strategy-outcome-driven-sections--build-guidance failure-priorities)))
    (concat base-prompt "\n\n;; Outcome-driven section prioritization\n" prioritized-guidance)))

(defun strategy-outcome-driven-sections--compute-priorities (analysis previous-results)
  "Compute section priorities based on failure patterns in ANALYSIS and PREVIOUS-RESULTS."
  (let ((priorities (ht-create))
        (pattern-types '()))
    ;; Extract pattern types from analysis
    (when (and (proper-list-p analysis)
               (plist-get analysis :patterns))
      (dolist (pattern (plist-get analysis :patterns))
        (when (proper-list-p pattern)
          (let ((ptype (plist-get pattern :type))
                (freq (or (plist-get pattern :frequency) 1)))
            (push (cons ptype freq) pattern-types)
            (puthash ptype freq priorities)))))
    ;; Boost priorities based on recent failures
    (dolist (result previous-results)
      (when (and (proper-list-p result)
                 (plist-get result :failed-patterns))
        (dolist (fp (plist-get result :failed-patterns))
          (let ((current (gethash fp priorities 0)))
            (puthash fp (+ current 0.5) priorities)))))
    ;; Sort by priority
    (sort (ht-to-alist priorities) (lambda (a b) (> (cdr a) (cdr b))))))

(defun strategy-outcome-driven-sections--build-guidance (priorities)
  "Build guidance string from PRIORITIES list."
  (if (null priorities)
      "Focus on general code quality improvements.\n"
    (concat "Priority focus areas based on observed failures:\n"
            (mapconcat (lambda (pair)
                         (format "- %s (priority: %.1f)" (car pair) (cdr pair)))
                       priorities "\n")
            "\nPrioritize addressing higher-priority issues first.\n")))

(defun strategy-outcome-driven-sections-get-metadata ()
  "Return metadata for this strategy."
  (list :name "outcome-driven-sections"
        :version "1.0"
        :hypothesis "Prioritizing sections addressing common failures improves resolution"
        :axis "C"
        :components ["section-ordering" "failure-prioritization" "outcome-tracking"]))

(provide 'strategy-outcome-driven-sections)