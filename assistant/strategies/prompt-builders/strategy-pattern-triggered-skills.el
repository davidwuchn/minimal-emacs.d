;;; strategy-pattern-triggered-skills.el --- Load skills based on detected patterns -*- lexical-binding: t; -*-
;; Hypothesis: Loading skills that match detected code patterns improves relevance
;; Axis: E (Skill loading)

(require 'gptel-tools-agent-prompt-build)

(defun strategy-pattern-triggered-skills-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with pattern-triggered skill loading."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (detected-patterns (strategy-detect-code-patterns target))
         (triggered-skills (strategy-load-triggered-skills detected-patterns)))
    (concat base-prompt "\n\n;; Pattern-triggered skill additions:\n" triggered-skills)))

(defun strategy-detect-code-patterns (target)
  "Detect code patterns in TARGET file."
  (with-temp-buffer
    (insert-file-contents target)
    (let* ((content (buffer-string))
           (patterns nil))
      (when (string-match-p (rx "-->" (0+ anything) "->") content)
        (push "threading" patterns))
      (when (string-match-p (rx "(condition-case " (0+ anything) "(error " ) content)
        (push "error-handling" patterns))
      (when (string-match-p (rx "(cl-loop " (0+ anything) "for") content)
        (push "iteration" patterns))
      (when (string-match-p (rx "(lambda " (0+ anything) (any ")")) content)
        (push "functional" patterns))
      (when (string-match-p (rx "(pcase ") content)
        (push "pattern-matching" patterns))
      (when (string-match-p (rx "(thread-first\\|thread-last\\|->>\\|+->>") content)
        (push "threading-macros" patterns))
      (when (string-match-p (rx "(defmacro ") content)
        (push "metaprogramming" patterns))
      (when (string-match-p (rx "(defstruct ") content)
        (push "adt" patterns))
      (nreverse patterns))))

(defun strategy-load-triggered-skills (patterns)
  "Load skills triggered by PATTERNS."
  (let* ((skill-map '(("threading" . "functional-threading")
                      ("error-handling" . "robust-error-handling")
                      ("iteration" . "iteration-patterns")
                      ("functional" . "functional-patterns")
                      ("pattern-matching" . "pcase-patterns")
                      ("threading-macros" . "threading-patterns")
                      ("metaprogramming" . "macro-best-practices")
                      ("adt" . "struct-design")))
         (skill-names nil))
    (dolist (pattern patterns)
      (let ((skill (assoc pattern skill-map)))
        (when skill
          (let ((skill-content (gptel-auto-workflow--load-skill-content (cdr skill))))
            (when skill-content
              (push skill-content skill-names))))))
    (if skill-names
        (mapconcat #'identity (nreverse skill-names) "\n\n")
      "- No specific pattern-triggered skills needed for this file.")))

(defun strategy-pattern-triggered-skills-get-metadata ()
  (list :name "pattern-triggered-skills"
        :version "1.0"
        :hypothesis "Dynamically loading skills based on detected code patterns provides more relevant guidance"
        :axis "E"
        :components ["pattern-detection" "skill-triggering"]))

(provide 'strategy-pattern-triggered-skills)