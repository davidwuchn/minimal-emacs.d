;;; strategy-recency-weighted-skills.el --- Weight skills by recency of successful use -*- lexical-binding: t; -*-
;; Hypothesis: Recent successful skill usage predicts future effectiveness
;; Axis: D (Variable computation)

(require 'gptel-tools-agent-prompt-build)

(defun strategy-recency-weighted-skills-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with skills weighted by recency of successful use."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (skill-history (strategy-recency-weighted-skills--compute-skill-history previous-results))
         (top-skills (strategy-recency-weighted-skills--select-top-skills skill-history))
         (skill-guidance (when top-skills
                           (format "\n\n## Recently Effective Skills\nThese skills succeeded in recent experiments:\n%s"
                                   (mapconcat (lambda (s) (format "- %s (score: %.2f)" (car s) (cdr s))) top-skills "\n")))))
    (concat base-prompt (or skill-guidance ""))))

(defun strategy-recency-weighted-skills--compute-skill-history (previous-results)
  "Compute skill effectiveness scores based on recency and success in PREVIOUS-RESULTS."
  (let ((skill-scores (make-hash-table :test #'equal)))
    (dolist (result (reverse previous-results) skill-scores)
      (when (proper-list-p result)
        (let* ((score (or (plist-get result :score) 0.5))
               (timestamp (or (plist-get result :experiment-id) 0))
             (recency-weight (exp (/ (- (float timestamp)) 10.0)))
             (used-skills (plist-get result :skills)))
        (dolist (skill (if (listp used-skills) used-skills (list used-skills)))
          (when (stringp skill)
            (let ((current (gethash skill skill-scores 0)))
              (puthash skill (+ current (* score recency-weight)) skill-scores))))))
    skill-scores))

(defun strategy-recency-weighted-skills--select-top-skills (skill-scores)
  "Select top 5 skills by weighted score from SKILL-SCORES."
  (let ((sorted '()))
    (maphash (lambda (skill score) (push (cons skill score) sorted)) skill-scores)
    (setf sorted (cl-sort sorted #'> :key #'cdr))
    (cl-subseq sorted 0 (min 5 (length sorted)))))

(defun strategy-recency-weighted-skills-get-metadata ()
  (list :name "recency-weighted-skills"
        :version "1.0"
        :hypothesis "Recent successful skill usage predicts future effectiveness"
        :axis "D"
        :components ["skill-history" "recency-weighting"]))

(provide 'strategy-recency-weighted-skills)