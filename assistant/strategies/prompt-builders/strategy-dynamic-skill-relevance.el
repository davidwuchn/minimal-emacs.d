;;; strategy-dynamic-skill-relevance.el --- Dynamic skill selection based on code patterns -*- lexical-binding: t; -*-
;; Hypothesis: Analyzing target code patterns and loading skills dynamically based on detected patterns improves skill relevance.
;; Axis: E (Skill loading)

(require 'gptel-tools-agent-prompt-build)

(defun strategy-dynamic-skill-relevance-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET using dynamic skill relevance scoring.
Detects code patterns and loads/prioritizes skills accordingly."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         ;; Detect patterns in target file
         (target-patterns (strategy-dynamic-skill-relevance--detect-patterns target))
         ;; Score and select relevant skills
         (skill-weights (strategy-dynamic-skill-relevance--score-skills target-patterns))
         ;; Generate dynamic skill guidance
         (skill-guidance (strategy-dynamic-skill-relevance--build-skill-guidance skill-weights)))
    (concat base-prompt "\n\n" skill-guidance)))

(defun strategy-dynamic-skill-relevance--detect-patterns (target)
  "Detect code patterns in TARGET file.
Returns plist with :uses-defcustoms :has-interactive :uses-hooks :uses-lexical :uses-closures."
  (with-temp-buffer
    (insert-file-contents target)
    (let ((uses-defcustoms (> (count-matches "defcustom") 0))
          (has-interactive (> (count-matches "interactive") 0))
          (uses-hooks (> (count-matches "add-hook\\|run-hook") 0))
          (uses-lexical (> (count-matches "lexical-binding") 0))
          (uses-closures (> (count-matches "\\(lambda\\|closure\\)")))
          (uses-advice (> (count-matches "advice-"))))
      (list :uses-defcustoms uses-defcustoms
            :has-interactive has-interactive
            :uses-hooks uses-hooks
            :uses-lexical uses-lexical
            :uses-closures uses-closures
            :uses-advice uses-advice))))

(defun strategy-dynamic-skill-relevance--score-skills (patterns)
  "Score skills based on detected PATTERNS.
Returns list of (skill-name . score) sorted by relevance."
  (let ((scores (list)))
    (when (plist-get patterns :uses-defcustoms)
      (push (cons "customization" 0.9) scores))
    (when (plist-get patterns :has-interactive)
      (push (cons "interactive" 0.85) scores))
    (when (plist-get patterns :uses-hooks)
      (push (cons "hooks" 0.8) scores))
    (when (plist-get patterns :uses-lexical)
      (push (cons "lexical-scoping" 0.75) scores))
    (when (plist-get patterns :uses-closures)
      (push (cons "closures" 0.7) scores))
    (when (plist-get patterns :uses-advice)
      (push (cons "advice" 0.6) scores))
    (sort scores (lambda (a b) (> (cdr a) (cdr b))))))

(defun strategy-dynamic-skill-relevance--build-skill-guidance (skill-weights)
  "Build skill guidance string from SKILL-WEIGHTS."
  (when skill-weights
    (let ((skill-list (mapconcat (lambda (pair)
                                   (format "%s (relevance: %.0f%%)"
                                           (car pair)
                                           (* (cdr pair) 100)))
                                 skill-weights
                                 ", ")))
      (format ";; DYNAMIC SKILL PRIORITIZATION:\n;; Detected patterns suggest prioritizing: %s\n;; Consider these techniques first when refactoring." skill-list))))

(defun strategy-dynamic-skill-relevance-get-metadata ()
  (list :name "dynamic-skill-relevance"
        :version "1.0"
        :hypothesis "Analyzing code patterns to dynamically prioritize skills improves targeting."
        :axis "E"
        :components ["pattern-detection" "skill-scoring" "dynamic-guidance"]))

(provide 'strategy-dynamic-skill-relevance)