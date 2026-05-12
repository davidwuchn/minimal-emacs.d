;;; strategy-contextual-skill-loading.el --- Load extra skills based on analysis patterns -*- lexical-binding: t; -*-
;; Hypothesis: Dynamically loading skill files whose names appear in pattern descriptions enriches the AI's domain knowledge.
;; Axis: E

(require 'gptel-tools-agent-prompt-build)

(defun strategy-contextual-skill-loading-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with additional skill files triggered by pattern terms.
ANALYSIS plist includes :patterns."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (patterns (plist-get analysis :patterns))
         (additional-content "")
         (pattern-texts (mapconcat (lambda (p) (plist-get p :description)) patterns " "))
         (skill-names '("functional" "performance" "error-handling" "refactoring" "testing"))
         (matched-skills
          (cl-remove-if-not
           (lambda (skill)
             (string-match-p (regexp-quote skill) pattern-texts))
           skill-names)))
    (dolist (skill matched-skills)
      (let ((content (gptel-auto-workflow--load-skill-content skill)))
        (when content
          (setq additional-content
                (concat additional-content
                        (format "\n\n;; Loaded Skill: %s\n%s" skill content))))))
    (concat base-prompt
            additional-content
            "\n\n;; Strategy: Contextual skill loading based on pattern keywords.")))

(defun strategy-contextual-skill-loading-get-metadata ()
  (list :name "contextual-skill-loading"
        :version "1.0"
        :hypothesis "Loading skill files mentioned in pattern descriptions provides targeted expertise."
        :axis "E"
        :components ["skill-loading" "contextual" "pattern-matching"]))

(provide 'strategy-contextual-skill-loading)