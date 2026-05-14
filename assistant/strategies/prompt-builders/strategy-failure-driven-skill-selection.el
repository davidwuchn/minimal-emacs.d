;;; strategy-failure-driven-skill-selection.el --- Dynamic skill loading based on failure analysis -*- lexical-binding: t; -*-
;; Hypothesis: Loading skills dynamically based on detected failure pattern signatures will yield more targeted improvements
;; Axis: E (Skill loading)
;;
(require 'gptel-tools-agent-prompt-build)
(require 'cl-lib)

(defun strategy-failure-driven-skill-selection-build-prompt
    (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt using failure-driven dynamic skill selection."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (failure-patterns (plist-get analysis :patterns))
         (skill-tags (strategy-failure-driven--extract-skill-tags failure-patterns))
         (dynamic-skills (strategy-failure-driven--load-matching-skills skill-tags)))
    (if (string-empty-p dynamic-skills)
        base-prompt
      (concat base-prompt "\n\n;; Dynamically Selected Skill Context\n" dynamic-skills))))

(defun strategy-failure-driven--extract-skill-tags (patterns)
  "Map failure patterns to relevant skill tags."
  (cl-loop for pattern in patterns
           append (cond
                   ((or (string-match-p "naming\\|identifier\\|convention" pattern)
                        (string-match-p "symbol" pattern))
                    '("naming" "code-style"))
                   ((or (string-match-p "logic\\|condition\\|branch" pattern)
                        (string-match-p "control flow" pattern))
                    '("logic-validation" "testing"))
                   ((or (string-match-p "memory\\|leak\\|resource" pattern)
                        (string-match-p "garbage" pattern))
                    '("memory-management" "resource-handling"))
                   ((or (string-match-p "performance\\|efficiency\\|slow" pattern)
                        (string-match-p "optimization" pattern))
                    '("performance" "optimization"))
                   (t '()))))

(defun strategy-failure-driven--load-matching-skills (tags)
  "Load skill content for each tag in TAGS."
  (mapconcat (lambda (tag)
               (or (gptel-auto-workflow--load-skill-content tag) ""))
             tags "\n"))

(defun strategy-failure-driven-skill-selection-get-metadata ()
  (list :name "failure-driven-skill-selection"
        :version "1.0"
        :hypothesis "Loading skills dynamically based on detected failure pattern signatures will yield more targeted improvements"
        :axis "E"
        :components ["failure-pattern-analysis" "dynamic-skill-loading"]))

(provide 'strategy-failure-driven-skill-selection)