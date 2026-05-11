;;; strategy-skill-relevance-routing.el --- Route skills by relevance scoring -*- lexical-binding: t; -*-
;; Hypothesis: Routing skills based on relevance to target characteristics yields better skill selection.
;; Axis: E
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-skill-relevance-routing-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET with relevance-scored skill routing."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (target-stats (strategy-skill-relevance-routing--compute-stats target))
         (relevant-skills (strategy-skill-relevance-routing--select-skills target-stats)))
    (if relevant-skills
        (concat base-prompt "\n\n;; Top-relevant skills:\n" relevant-skills)
      base-prompt)))

(defun strategy-skill-relevance-routing--compute-stats (target)
  "Compute target file statistics for skill relevance scoring."
  (let* ((file-exists (and target (file-exists-p target)))
         (size (if file-exists (nth 7 (file-attributes target)) 0))
         (line-count (if file-exists
                         (with-temp-buffer
                           (insert-file-contents target nil 0 10000)
                           (count-lines (point-min) (point-max)))
                       0)))
    (list :size size
          :line-count line-count
          :complexity (cond ((> line-count 500) 'large)
                            ((> line-count 150) 'medium)
                            (t 'small))
          :is-large (> size 20000))))

(defun strategy-skill-relevance-routing--select-skills (stats)
  "Select skills based on relevance to STATS."
  (let* ((complexity (plist-get stats :complexity))
         (is-large (plist-get stats :is-large))
         (skills nil))
    (when is-large
      (push "performance-optimization" skills))
    (push (cond ((eq complexity 'large) "refactoring-patterns")
                ((eq complexity 'medium) "code-clarity")
                (t "concise-style"))
          skills)
    (when (> (plist-get stats :line-count) 100)
      (push "maintainability" skills))
    (format "- %s" (mapconcat 'identity skills "\n- "))))

(defun strategy-skill-relevance-routing-get-metadata ()
  (list :name "skill-relevance-routing"
        :version "1.0"
        :hypothesis "Routing skills based on relevance to target characteristics yields better skill selection"
        :axis "E"
        :components ["skill-scoring" "relevance-routing"]))

(provide 'strategy-skill-relevance-routing)