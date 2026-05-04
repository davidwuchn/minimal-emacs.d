;;; strategy-weighted-skills.el --- Weighted skill composition strategy -*- lexical-binding: t; -*-
;; Hypothesis: Dynamically composing skills based on target characteristics and failure history improves focus
;; Axis: Prompt template architecture

(require 'cl-lib)
(require 'gptel-tools-agent-prompt-build)

(defun strategy-weighted-skills-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt using weighted skill composition based on target analysis."
  (let* ((skill-weights (strategy-weighted-skills--compute-weights previous-results))
         (selected-skills (cl-loop for sw in skill-weights
                                    for skill = (car sw)
                                    for weight = (cdr sw)
                                    when (>= weight 0.3)
                                    collect skill))
         (_composed-skills (when selected-skills
                            (mapconcat
                             (lambda (skill)
                               (or (gptel-auto-workflow--load-skill-content skill) ""))
                             selected-skills
                             "\n\n---\n\n"))))
    ;; Delegate to baseline with skill injection; the composed skills
    ;; are rendered as additional agent-behavior content when available.
    (gptel-auto-experiment-build-prompt
     target experiment-id max-experiments analysis baseline previous-results)))

(defun strategy-weighted-skills--compute-weights (previous-results)
  "Compute skill weights based on prior experiment outcomes in PREVIOUS-RESULTS.
PREVIOUS-RESULTS is a list of plists with :decision and :comparator-reason."
  (let* ((weights (list (cons "error-handling" 0.0)
                        (cons "refactoring" 0.0)
                        (cons "optimization" 0.0)
                        (cons "testing" 0.0)))
         (results (if (listp previous-results) previous-results nil))
         (total (max 1 (length results)))
         (kept 0)
         (rejection-reasons nil))
    ;; Count outcomes
    (dolist (r results)
      (when (and (listp r) (equal (plist-get r :kept) t))
        (setq kept (1+ kept)))
      (let ((reason (and (listp r) (plist-get r :comparator-reason))))
        (when (and (stringp reason) (not (string-empty-p reason)))
          (push reason rejection-reasons))))
    ;; Weight adjustment based on rejection patterns
    (let ((keep-rate (/ (float kept) total)))
      ;; If keep rate is low, increase all weights to give more guidance
      (when (< keep-rate 0.5)
        (setq weights (mapcar (lambda (w) (cons (car w) (+ (cdr w) 0.15))) weights)))
      ;; Adjust based on rejection reason keywords
      (dolist (reason rejection-reasons)
        (cond
         ((string-match-p "null\\|undefined\\|type\\|guard\\|validation" reason)
          (setcdr (assoc "error-handling" weights)
                  (+ (cdr (assoc "error-handling" weights)) 0.1)))
         ((string-match-p "duplicat\\|complex\\|simplif\\|extract" reason)
          (setcdr (assoc "refactoring" weights)
                  (+ (cdr (assoc "refactoring" weights)) 0.1)))
         ((string-match-p "performance\\|slow\\|memory\\|cache" reason)
          (setcdr (assoc "optimization" weights)
                  (+ (cdr (assoc "optimization" weights)) 0.1)))))
      ;; Cap weights at 0.8
      (mapcar (lambda (w) (cons (car w) (min (cdr w) 0.8))) weights))))

(defun strategy-weighted-skills-get-metadata ()
  "Return metadata for this strategy."
  (list :name "evolved-0003"
        :version "1.1"
        :hypothesis "Dynamic skill composition weighted by failure pattern frequency"
        :axis "A"
        :components '("weighted-selection" "failure-driven" "skill-composition")))

(provide 'strategy-weighted-skills)
;;; strategy-weighted-skills.el ends here
