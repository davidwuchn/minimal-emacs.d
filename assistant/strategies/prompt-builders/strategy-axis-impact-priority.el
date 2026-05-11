;;; strategy-axis-impact-priority.el --- Reorder guidance by computed axis impact scores -*- lexical-binding: t; -*-
;; Hypothesis: Prioritizing axes by historical failure impact focuses reasoning on the highest-yield improvement areas.
;; Axis: D

(require 'gptel-tools-agent-prompt-build)

(defun strategy-axis-impact-priority-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET using strategy axis-impact-priority.
EXPERIMENT-ID: current experiment number.
MAX-EXPERIMENTS: total experiments planned.
ANALYSIS: plist with :patterns :recommendations from previous experiments.
BASELINE: current baseline score.
PREVIOUS-RESULTS: list of previous experiment plists."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (patterns (plist-get analysis :patterns))
         (axis-alist nil))
    (dolist (p patterns)
      (let* ((axis (or (plist-get p :axis) "general"))
             (severity (or (plist-get p :severity) 1))
             (count (length (plist-get p :locations)))
             (score (* severity count))
             (existing (assoc axis axis-alist)))
        (if existing
            (setcdr existing (+ (cdr existing) score))
          (push (cons axis score) axis-alist))))
    (let* ((sorted-axes (sort axis-alist (lambda (a b) (> (cdr a) (cdr b)))))
           (priority-text (if sorted-axes
                             (concat "\n\n## Axis Priority Ranking\nFocus improvement effort on these axes in descending order of historical failure impact:\n"
                                     (mapconcat (lambda (pair)
                                                  (format "- %s: impact score %d" (car pair) (cdr pair)))
                                                sorted-axes
                                                "\n")
                                     "\n\nApply deeper reasoning to higher-ranked axes before optimizing lower-ranked ones.")
                           "")))
      (concat priority-text "\n\n" base-prompt))))

(defun strategy-axis-impact-priority-get-metadata ()
  "Return metadata for this strategy."
  (list :name "axis-impact-priority"
        :version "1.0"
        :hypothesis "Prioritizing axes by historical failure impact focuses reasoning on the highest-yield improvement areas."
        :axis "D"
        :components ["scoring" "prioritization" "axis-guidance"]))

(provide 'strategy-axis-impact-priority)