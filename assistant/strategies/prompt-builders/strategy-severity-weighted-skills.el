;;; strategy-severity-weighted-skills.el --- Skill loading proportional to detected issue severity -*- lexical-binding: t; -*-
;; Hypothesis: Loading skills weighted by pattern severity rather than uniformly produces more focused solutions
;; Axis: E (Skill loading) + D (Variable computation)
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-severity-weighted-skills-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with severity-weighted skill loading."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (patterns (plist-get analysis :patterns))
         (severity-scores (strategy-severity-weighted-skills--compute-severity patterns))
         (weighted-skills (strategy-severity-weighted-skills--load-skills severity-scores)))
    (if weighted-skills
        (concat base-prompt "\n\n;; Severity-weighted relevant skills\n" weighted-skills)
      base-prompt)))

(defun strategy-severity-weighted-skills--compute-severity (patterns)
  "Compute severity scores for PATTERNS based on frequency and impact."
  (let (scores)
    (dolist (pattern patterns)
      (let* ((type (car pattern))
             (freq (or (plist-get (cdr pattern) :frequency) 1))
             (impact (or (plist-get (cdr pattern) :impact) 1.0))
             (severity (* freq impact)))
        (push (cons type severity) scores)))
    scores))

(defun strategy-severity-weighted-skills--load-skills (severity-scores)
  "Load skill content weighted by SEVERITY-SCORES."
  (let* ((all-skills '("refactoring" "error-handling" "performance" "testing" "documentation"))
         (skill-content-list nil))
    (dolist (skill all-skills)
      (let ((skill-severity (or (cdr (assoc skill severity-scores)) 0.5)))
        (when (> skill-severity 0.7)
          (let ((content (gptel-auto-workflow--load-skill-content skill)))
            (when content
              (push (format ";; [Severity: %.2f] %s\n%s" skill-severity skill content)
                    skill-content-list))))))
    (when skill-content-list
      (string-join (nreverse skill-content-list) "\n"))))

(defun strategy-severity-weighted-skills-get-metadata ()
  (list :name "severity-weighted-skills"
        :version "1.0"
        :hypothesis "Loading skills weighted by detected pattern severity produces more focused solutions"
        :axis "E"
        :components ["skill-weighting" "severity-scoring"]))

(provide 'strategy-severity-weighted-skills)