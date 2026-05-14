;;; strategy-cyclomatic-complexity-skill-loading.el --- Load skills based on complexity -*- lexical-binding: t; -*-
;; Hypothesis: Code complexity determines which skill set to emphasize in the prompt.
;; Axis: E, D

(require 'gptel-tools-agent-prompt-build)

(defun strategy-cyclomatic-complexity-skill-loading-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with complexity-driven skill loading priority."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         ;; Extract complexity hints from analysis
         (recommendations (plist-get analysis :recommendations))
         (complexity-indicator (or (plist-get recommendations :complexity) 'medium))
         (skill-priority (cond
                          ((eq complexity-indicator 'high) '("refactoring" "testing" "performance"))
                          ((eq complexity-indicator 'medium) '("refactoring" "clarity"))
                          (t '("clarity" "documentation"))))
         (skill-load-commands (mapconcat
                                (lambda (skill)
                                  (format "Load skill: %s (priority: high)" skill))
                                skill-priority "\n")))
    (concat base-prompt (format "
;; COMPLEXITY-DRIVEN SKILL LOADING
;; Detected complexity: %s
;; Skill loading priority order:
%s
;; Ensure primary skills are referenced before secondary skills in prompt.
" complexity-indicator skill-load-commands))))

(defun strategy-cyclomatic-complexity-skill-loading-get-metadata ()
  (list :name "complexity-skill-sequencing"
        :version "1.0"
        :hypothesis "Loading and prioritizing skills based on code complexity improves relevance"
        :axis "E-D"
        :components ["complexity-analysis" "skill-prioritization"]))

(provide 'strategy-cyclomatic-complexity-skill-loading)