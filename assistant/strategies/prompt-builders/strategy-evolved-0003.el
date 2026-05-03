;;; strategy-evolved-0003.el --- Weighted skill composition strategy -*- lexical-binding: t; -*-
;; Hypothesis: Dynamically composing skills based on target characteristics and failure history improves focus
;; Axis: Prompt template architecture

(require 'gptel-tools-agent-prompt-build)

(defun strategy-evolved-0003-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt using weighted skill composition based on target analysis."
  (let* ((skill-weights (strategy-evolved-0003--compute-weights target analysis previous-results))
         (selected-skills (cl-loop for (skill . weight) in skill-weights
                                   when (>= weight 0.3)
                                   collect skill))
         (composed-skills (mapconcat
                           (lambda (skill)
                             (or (gptel-auto-workflow--load-skill-content skill) ""))
                           selected-skills
                           "\n\n---\n\n"))
         (base-prompt (gptel-auto-experiment-build-prompt target experiment-id max-experiments analysis baseline previous-results)))
    (if (string-empty-p composed-skills)
        base-prompt
      (gptel-auto-workflow--substitute-template
       base-prompt
       (list (cons "{{skills}}" composed-skills))))))

(defun strategy-evolved-0003--compute-weights (target analysis previous-results)
  "Compute skill weights based on target characteristics and history."
  (let* ((failure-patterns (when analysis
                             (gethash 'failure-patterns analysis)))
         (top-failures (cl-loop for pattern in failure-patterns
                                for freq = (or (gethash 'frequency pattern) 0)
                                when (> freq 0.1)
                                collect (cons (gethash 'type pattern) freq)))
         (weights '(("error-handling" . 0.0)
                    ("refactoring" . 0.0)
                    ("optimization" . 0.0)
                    ("documentation" . 0.0)
                    ("testing" . 0.0))))
    (dolist (failure top-failures)
      (let ((type (car failure))
            (freq (cdr failure)))
        (cond
         ((member type '("null-check" "type-error" "undefined")) 
          (setcdr (assoc "error-handling" weights) (max (cdr (assoc "error-handling" weights)) freq)))
         ((member type '("complexity" "duplication"))
          (setcdr (assoc "refactoring" weights) (max (cdr (assoc "refactoring" weights)) freq)))
         ((member type '("performance" "memory"))
          (setcdr (assoc "optimization" weights) (max (cdr (assoc "optimization" weights)) freq))))))
    weights))

(defun strategy-evolved-0003-get-metadata ()
  (list :name "evolved-0003"
        :version "1.0"
        :hypothesis "Dynamic skill composition weighted by failure pattern frequency"
        :axis "Prompt template architecture"
        :components ["weighted-selection" "failure-driven" "skill-composition"]))

(provide 'strategy-evolved-0003)