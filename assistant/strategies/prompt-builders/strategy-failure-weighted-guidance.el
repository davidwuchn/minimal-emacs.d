;;; strategy-failure-weighted-guidance.el --- Weight guidance by failure history -*- lexical-binding: t; -*-
;; Hypothesis: Prioritizing guidance based on historical failure patterns is more effective than uniform guidance.
;; Axis: D (Variable computation)

(require 'gptel-tools-agent-prompt-build)

(defun strategy-failure-weighted-guidance--compute-pattern-weights (previous-results)
  "Compute importance weights for pattern types based on failure history."
  (let ((pattern-stats '()))
    (dolist (result previous-results)
      (when (proper-list-p result)
        (let ((patterns (plist-get result :failure-patterns))
              (outcome (plist-get result :outcome)))
        (when patterns
          (dolist (pattern patterns)
            (let ((entry (assoc pattern pattern-stats)))
              (if entry
                  (progn
                    (cl-incf (cadr entry))
                    (when (eq outcome 'failure)
                      (cl-incf (caddr entry))))
                (push (list pattern 1 (if (eq outcome 'failure) 1 0)) pattern-stats))))))))
    (mapcar (lambda (e)
              (let ((freq (cadr e)) (fails (caddr e)))
                (list (car e) (/ fails (max freq 1)))))
            pattern-stats)))

(defun strategy-failure-weighted-guidance--format-weighted (weighted-patterns)
  "Format weighted patterns into prioritized guidance."
  (if (null weighted-patterns)
      ""
    (let* ((sorted (sort weighted-patterns (lambda (a b) (> (cadr a) (cadr b)))))
           (lines '("\n;; Failure-pattern-weighted guidance:")))
      (dotimes (i (min 5 (length sorted)))
        (let ((p (nth i sorted)))
          (push (format "  %d. %s (fail-rate: %.0f%%)"
                        (1+ i) (car p) (* 100 (cadr p))) lines)))
      (mapconcat #'identity (nreverse lines) "\n"))))

(defun strategy-failure-weighted-guidance-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with failure-history-weighted guidance."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt target experiment-id max-experiments analysis baseline previous-results))
         (weights (strategy-failure-weighted-guidance--compute-pattern-weights previous-results))
         (weighted-section (strategy-failure-weighted-guidance--format-weighted weights)))
    (concat base-prompt weighted-section)))

(defun strategy-failure-weighted-guidance-get-metadata ()
  (list :name "failure-weighted-guidance"
        :version "1.0"
        :hypothesis "Prioritizing guidance based on historical failure patterns is more effective than uniform guidance."
        :axis "D"
        :components ["failure-analysis" "weighted-prioritization"]))

(provide 'strategy-failure-weighted-guidance)