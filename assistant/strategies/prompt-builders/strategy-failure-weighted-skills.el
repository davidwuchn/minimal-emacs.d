;;; strategy-failure-weighted-skills.el --- Weight skills by failure history -*- lexical-binding: t; -*-
;; Hypothesis: Prioritizing skills that address patterns that failed in previous experiments improves success rates.
;; Axis: E (Skill loading)
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-failure-weighted-skills-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET weighting skills by failure history."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (failure-patterns (plist-get analysis :patterns))
         (skill-weights (strategy-fw--compute-skill-weights failure-patterns))
         (weighted-guidance (strategy-fw--format-weighted-skill-guidance skill-weights)))
    (concat base-prompt "\n\n;; FAILURE-WEIGHTED SKILL GUIDANCE\n" weighted-guidance)))

(defun strategy-fw--compute-skill-weights (patterns)
  "Compute skill weights based on failure pattern frequency.
PATTERNS: list of failure pattern keywords."
  (let ((weights '((refactoring . 1.0)
                   (error-handling . 1.0)
                   (performance . 1.0)
                   (documentation . 0.8)
                   (testing . 1.0)
                   (type-safety . 0.7))))
    (dolist (pattern patterns weights)
      (setq pattern (intern pattern))
      (pcase pattern
        ('null-check (cl-remf weights 'error-handling) (cl-remf weights 'type-safety)
                      (setq weights (cons '(error-handling . 2.0) weights)))
        ('resource-leak (cl-remf weights 'error-handling)
                        (setq weights (cons '(error-handling . 2.0) weights)))
        ('performance-issue (cl-remf weights 'performance)
                            (setq weights (cons '(performance . 2.0) weights)))
        ('complexity (cl-remf weights 'refactoring)
                     (setq weights (cons '(refactoring . 2.0) weights)))
        ('missing-docs (cl-remf weights 'documentation)
                       (setq weights (cons '(documentation . 2.0) weights)))
        (_ (when (assq pattern weights)
             (cl-remf weights pattern)
             (setq weights (cons (cons pattern 1.5) weights))))))))

(defun strategy-fw--format-weighted-skill-guidance (weights)
  "Format skill guidance emphasizing high-weight skills."
  (let ((sorted (sort weights (lambda (a b) (> (cdr a) (cdr b)))))
        (lines '()))
    (push "Based on previous failure patterns, prioritize:\n" lines)
    (dolist (w sorted)
      (let ((weight (cdr w))
            (skill (car w)))
        (when (> weight 1.0)
          (push (format "- %s: [HIGH PRIORITY - weight %.1f]" skill weight) lines))))
    (push "\nFocus on addressing identified failure patterns before applying other improvements." lines)
    (mapconcat #'identity (reverse lines) "\n")))

(defun strategy-failure-weighted-skills-get-metadata ()
  (list :name "failure-weighted-skills"
        :version "1.0"
        :hypothesis "Prioritizing skills that address patterns that failed in previous experiments improves success rates."
        :axis "E"
        :components ["skill-weighting" "failure-analysis"]))

(provide 'strategy-failure-weighted-skills)