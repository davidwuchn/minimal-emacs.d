;;; strategy-failure-pattern-skill-weighting.el --- Weight skill content by historical failure patterns -*- lexical-binding: t; -*-
;; Hypothesis: Skills that address historical failure patterns should receive increased emphasis.
;; Axis: E
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-failure-pattern-skill-weighting-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET with failure-pattern-weighted skill loading."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (failure-patterns (plist-get analysis :patterns))
         (failure-frequencies (strategy-failure-pattern-skill-weighting--count-patterns failure-patterns))
         (skill-names '("type-checking" "error-handling" "refactoring" "testing" "performance"))
         (skill-weights (strategy-failure-pattern-skill-weighting--compute-weights skill-names failure-frequencies))
         (relevant-skills (cl-loop for (skill . weight) in skill-weights
                                   when (> weight 0.3)
                                   collect (cons skill weight)))
         (skill-section ""))
    (when relevant-skills
      (let ((skill-mentions (mapconcat
                              (lambda (pair)
                                (format "%s (weight=%.2f - prioritize this skill)" (car pair) (cdr pair)))
                              relevant-skills
                              ", ")))
        (setq skill-section (format "\n\n;; Failure-Pattern-Weighted Skill Prioritization
Based on historical patterns: %s
Emphasize these skills heavily in your approach.\n" skill-mentions))))
    (concat base-prompt skill-section)))

(defun strategy-failure-pattern-skill-weighting--count-patterns (patterns)
  "Count keyword frequencies in PATTERNS list."
  (let ((counts (list :type 0 :error 0 :refactor 0 :test 0 :perf 0)))
    (dolist (pattern patterns counts)
      (let ((pstr (format "%s" pattern)))
        (when (string-match-p "type\\|signature\\|argument" pstr)
          (cl-incf (plist-get counts :type)))
        (when (string-match-p "error\\|exception\\|nil\\|wrong" pstr)
          (cl-incf (plist-get counts :error)))
        (when (string-match-p "refactor\\|cleanup\\|simplif" pstr)
          (cl-incf (plist-get counts :refactor)))
        (when (string-match-p "test\\|assert\\|spec" pstr)
          (cl-incf (plist-get counts :test)))
        (when (string-match-p "perform\\|slow\\|optim" pstr)
          (cl-incf (plist-get counts :perf)))))))

(defun strategy-failure-pattern-skill-weighting--compute-weights (skill-names failure-frequencies)
  "Map skill names to normalized weights based on FAILURE-FREQUENCIES."
  (let ((mapping (list (cons "type-checking" :type)
                       (cons "error-handling" :error)
                       (cons "refactoring" :refactor)
                       (cons "testing" :test)
                       (cons "performance" :perf)))
        (total-failures 0)
        weights)
    (setq total-failures (+ (plist-get failure-frequencies :type)
                            (plist-get failure-frequencies :error)
                            (plist-get failure-frequencies :refactor)
                            (plist-get failure-frequencies :test)
                            (plist-get failure-frequencies :perf)))
    (dolist (skill skill-names)
      (let* ((key (cdr (assoc skill mapping)))
             (freq (if key (plist-get failure-frequencies key) 0)))
        (push (cons skill (if (> total-failures 0)
                              (/ (float freq) total-failures)
                            0.2))
              weights)))
    weights))

(defun strategy-failure-pattern-skill-weighting-get-metadata ()
  (list :name "failure-pattern-skill-weighting"
        :version "1.0"
        :hypothesis "Skills addressing historical failure patterns should receive increased emphasis."
        :axis "E"
        :components ["failure-analysis" "skill-weighting" "historical-patterns"]))

(provide 'strategy-failure-pattern-skill-weighting)