;;; strategy-change-classification-loading.el --- Load context based on semantic change type -*- lexical-binding: t; -*-
;; Hypothesis: Classifying the required change (refactor/bugfix/feature) and loading targeted skills/context improves outcomes.
;; Axis: E (Skill loading) + B (Context retrieval)

(require 'gptel-tools-agent-prompt-build)

(defun strategy-change-classification-loading-build-prompt
    (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with change-type-aware skill and context loading."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (change-type (strategy-change-classification-loading--classify-change
                       target analysis previous-results))
         (type-specific-skills (strategy-change-classification-loading--load-type-skills change-type))
         (type-specific-context (strategy-change-classification-loading--load-type-context
                                 target change-type))
         (enhanced-prompt (concat base-prompt "\n\n" type-specific-skills "\n" type-specific-context)))
    enhanced-prompt))

(defun strategy-change-classification-loading--classify-change
    (target analysis previous-results)
  "Classify the nature of change needed based on analysis and history.
Returns symbol: 'refactor, 'bugfix, or 'feature."
  (let* ((patterns (plist-get analysis :patterns))
         (recommendations (plist-get analysis :recommendations))
         (recent-types (mapcar (lambda (r) (plist-get r :change-type)) previous-results))
         (pattern-keywords (mapconcat #'princ patterns "")))
    (cond
     ((or (string-match-p "duplicate\\|extract\\|rename\\|consolidate" pattern-keywords)
          (> (length (cl-remove-if-not
                      (lambda (s) (string-match-p "refactor" (format "%s" s)))
                      recent-types))
             1))
      'refactor)
     ((or (string-match-p "fix\\|error\\|fail\\|bug\\|crash" pattern-keywords)
          (string-match-p "assert\\|test.*fail" pattern-keywords))
      'bugfix)
     (t 'feature))))

(defun strategy-change-classification-loading--load-type-skills (change-type)
  "Load skills specific to CHANGE-TYPE."
  (let ((skill-paths
         (pcase change-type
           ('refactor '("refactoring-essentials" "code-smell-detection"))
           ('bugfix '("debugging-strategies" "error-analysis"))
           ('feature '("feature-implementation" "api-design"))
           (_ '()))))
    (string-join
     (delq nil
           (mapcar (lambda (s) (ignore-errors
                                (gptel-auto-workflow--load-skill-content s)))
                   skill-paths))
     "\n")))

(defun strategy-change-classification-loading--load-type-context (target change-type)
  "Load type-specific context for TARGET and CHANGE-TYPE."
  (let ((context-templates
         (pcase change-type
           ('refactor
            ";; Refactoring Focus\n;; Prioritize: maintaining behavior, reducing complexity, improving readability.")
           ('bugfix
            ";; Bugfix Focus\n;; Prioritize: root cause identification, minimal changes, preserving valid behavior.")
           ('feature
            ";; Feature Focus\n;; Prioritize: clean implementation, extensibility, backward compatibility.")
           (_ ""))))
    context-templates))

(defun strategy-change-classification-loading-get-metadata ()
  (list :name "change-classification-loading"
        :version "1.0"
        :hypothesis "Classifying changes as refactor/bugfix/feature and loading targeted skills/context produces better alignment with improvement goals."
        :axis "E"
        :components ["change-classification" "type-specific-skills" "type-specific-context"]))

(provide 'strategy-change-classification-loading)