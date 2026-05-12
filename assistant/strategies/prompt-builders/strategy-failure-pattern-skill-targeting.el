;;; strategy-failure-pattern-skill-targeting.el --- Targeted skill loading based on failure patterns -*- lexical-binding: t; -*-
;; Hypothesis: Loading skills that specifically address detected failure patterns improves fix quality
;; Axis: E (Skill loading)

(require 'gptel-tools-agent-prompt-build)

(defun strategy-failure-pattern-skill-targeting-build-prompt
    (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET with failure-pattern-driven skill selection."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         ;; Retrieve patterns from analysis
         (patterns (plist-get analysis :patterns))
         ;; Load skills dynamically based on pattern types detected
         (targeted-skills (strategy-failure-pattern-skill-targeting--select-skills patterns))
         ;; Format skill guidance with pattern mapping
         (skill-guidance (strategy-failure-pattern-skill-targeting--format-skill-guidance
                          targeted-skills patterns)))
    ;; Append targeted skill guidance to base prompt
    (concat base-prompt "\n\n;; Targeted skill guidance\n" skill-guidance)))

(defun strategy-failure-pattern-skill-targeting--select-skills (patterns)
  "Select skills based on failure PATTERNS detected."
  (let ((selected-skills nil))
    ;; Map pattern types to relevant skills
    (dolist (pattern patterns)
      (let ((pattern-type (car pattern)))
        (cond
         ;; Memory/leak patterns -> load memory management skill
         ((string-match-p "memory\\|leak\\|alloc" (format "%s" pattern-type))
          (push "memory-management" selected-skills))
         ;; Performance patterns -> load optimization skill
         ((string-match-p "performance\\|slow\\|inefficient" (format "%s" pattern-type))
          (push "performance-optimization" selected-skills))
         ;; Concurrency patterns -> load threading skill
         ((string-match-p "race\\|thread\\|concurrent" (format "%s" pattern-type))
          (push "concurrency-patterns" selected-skills))
         ;; API misuse patterns -> load elisp-best-practices
         ((string-match-p "api\\| misuse\\|wrong" (format "%s" pattern-type))
          (push "elisp-best-practices" selected-skills))
         ;; Default: load general improvement skill
         (t (push "code-quality" selected-skills)))))
    ;; Remove duplicates while preserving order
    (delete-dups selected-skills)))

(defun strategy-failure-pattern-skill-targeting--format-skill-guidance (skills patterns)
  "Format SKILLS with associated PATTERNS as guidance."
  (let ((sections nil))
    (setq sections (cons "The following skills are relevant to the detected patterns:\n" sections))
    (dolist (skill skills)
      (let ((skill-content (condition-case nil
                              (gptel-auto-workflow--load-skill-content skill)
                            (error ""))))
        (when (and skill-content (not (string-empty-p skill-content)))
          (setq sections (cons (format "## %s\n%s\n" skill skill-content) sections)))))
    (when patterns
      (setq sections (cons (format "Detected pattern categories: %s"
                                  (mapconcat #'car patterns ", ")) sections)))
    (string-join (reverse sections) "\n")))

(defun strategy-failure-pattern-skill-targeting-get-metadata ()
  "Return metadata for this strategy."
  (list :name "failure-pattern-skill-targeting"
        :version "1.0"
        :hypothesis "Loading skills that specifically address detected failure patterns improves fix quality"
        :axis "E"
        :components ["skill-targeting" "pattern-analysis" "dynamic-loading"]))

(provide 'strategy-failure-pattern-skill-targeting)