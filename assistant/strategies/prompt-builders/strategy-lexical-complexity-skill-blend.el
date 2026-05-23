;;; strategy-lexical-complexity-skill-blend.el --- Dynamic skill blending based on code complexity -*- lexical-binding: t; -*-
;; Hypothesis: Blending skills dynamically based on detected code complexity yields more targeted guidance.
;; Axis: E
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-lexical-complexity-skill-blend-build-prompt
    (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET using lexical-complexity-based skill blending."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (skill-blend (gptel-auto-workflow--blend-skills-by-complexity target)))
    (concat base-prompt "\n\n;; Dynamic Skill Blend\n" skill-blend)))

(defun gptel-auto-workflow--blend-skills-by-complexity (target)
  "Detect code complexity and blend relevant skills dynamically."
  (with-temp-buffer
    (insert-file-contents target)
    (let* ((content (buffer-string))
           (lexical-count (if (string-match-p "^-.* lexical-binding" content) 1 0))
           (macro-count (length (s-match-strings-all "(defmacro\\|cl-defmacro\\|define-modification-macro" content)))
           (destructuring-count (length (s-match-strings-all "(destructuring-bind\\|pcase\\|cl-destructuring-bind" content)))
           (complexity-score (+ (* 3 lexical-count) (* 2 macro-count) destructuring-count)))
      (cond
       ((>= complexity-score 5)
        (concat ";; High complexity detected (score: " (number-to-string complexity-score) ")\n"
                "- Prioritize macro expansion and hygiene guidance\n"
                "- Apply destructuring pattern best practices\n"
                "- Consider lexical environment implications"))
       ((>= complexity-score 2)
        (concat ";; Moderate complexity detected (score: " (number-to-string complexity-score) ")\n"
                "- Apply pattern matching considerations\n"
                "- Note lexical scope interactions"))
       (t
        ";; Simple code structure - standard improvements apply")))))

(defun strategy-lexical-complexity-skill-blend-get-metadata ()
  (list :name "lexical-complexity-skill-blend"
        :version "1.0"
        :hypothesis "Blending skills dynamically based on detected code complexity yields more targeted guidance"
        :axis "E"
        :components ["skill-blending" "lexical-detection" "complexity-scoring"]))

(provide 'strategy-lexical-complexity-skill-blend)