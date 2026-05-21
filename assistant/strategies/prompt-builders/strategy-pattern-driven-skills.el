;;; strategy-pattern-driven-skills.el --- Dynamic skill loading based on code patterns -*- lexical-binding: t; -*-
;; Hypothesis: Dynamically loading skills based on detected code patterns yields better targeted improvements.
;; Axis: E
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-pattern-driven-skills-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET using pattern-driven skill selection.
Loads skills dynamically based on detected code patterns rather than static skill lists."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (code-content (when (file-exists-p target)
                         (with-temp-buffer
                           (insert-file-contents target)
                           (buffer-string))))
         (detected-patterns (when code-content
                              (strategy-pattern-driven-skills--detect-patterns code-content)))
         (skill-load-commands (strategy-pattern-driven-skills--build-skill-commands detected-patterns)))
    (concat base-prompt "\n\n;; Dynamic Skill Loading\n"
            "Based on code analysis, the following skill patterns are relevant:\n"
            skill-load-commands)))

(defun strategy-pattern-driven-skills--detect-patterns (code-content)
  "Detect code patterns in CODE-CONTENT and return a list of pattern types."
  (let ((patterns nil))
    (when (string-match-p "\\(defun\\|defmacro\\|lambda\\)" code-content)
      (push "function-definition" patterns))
    (when (string-match-p "\\(let\\*?\\|letrec\\)" code-content)
      (push "variable-scoping" patterns))
    (when (string-match-p "\\(cond\\|if\\|when\\|unless\\)" code-content)
      (push "conditional-logic" patterns))
    (when (string-match-p "\\(mapcar\\|mapc\\|mapconcat\\|dolist\\|dotimes\\)" code-content)
      (push "iteration-patterns" patterns))
    (when (string-match-p "\\(recursive\\|self\\)" code-content)
      (push "recursion-patterns" patterns))
    (when (string-match-p "\\(condition-case\\|signal\\|throw\\)" code-content)
      (push "error-handling" patterns))
    patterns))

(defun strategy-pattern-driven-skills--build-skill-commands (patterns)
  "Build skill loading commands based on PATTERNS."
  (mapconcat (lambda (pattern)
               (format ";; Load skill for: %s" pattern))
             patterns "\n"))

(defun strategy-pattern-driven-skills-get-metadata ()
  (list :name "pattern-driven-skills"
        :version "1.0"
        :hypothesis "Dynamic skill selection based on detected code patterns yields more targeted improvements."
        :axis "E"
        :components ["pattern-detection" "dynamic-skill-loading"]))

(provide 'strategy-pattern-driven-skills)