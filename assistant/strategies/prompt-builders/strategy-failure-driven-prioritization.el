;;; strategy-failure-driven-prioritization.el --- Reorder sections by failure patterns -*- lexical-binding: t; -*-
;; Hypothesis: Prioritizing guidance based on observed failure patterns improves fix accuracy.
;; Axis: C (Section ordering)

(require 'gptel-tools-agent-prompt-build)
(require 'cl-lib)

(defun strategy-failure-driven-prioritization--compute-frequencies (previous-results)
  "Compute failure pattern frequencies from PREVIOUS-RESULTS."
  (let ((freqs (list)))
    (dolist (result previous-results freqs)
      (when (and (listp result) (plist-get result :patterns))
        (dolist (pattern (plist-get result :patterns))
          (let* ((key (if (consp pattern) (car pattern) pattern))
                 (existing (assoc key freqs)))
            (if existing
                (cl-incf (cdr existing))
              (push (cons key 1) freqs))))))
    (sort freqs (lambda (a b) (> (cdr a) (cdr b))))))

(defun strategy-failure-driven-prioritization-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with sections reordered by failure pattern frequency."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (freqs (strategy-failure-driven-prioritization--compute-frequencies previous-results)))
    (if (null freqs)
        base-prompt
      (let* ((top-failures (mapconcat (lambda (f) (format "- %s" (car f)))
                                      (cl-subseq freqs 0 (min 3 (length freqs)))
                                      "\n")))
        (concat base-prompt "\n\n;; Failure-driven prioritization\n"
                "Based on recent failures, prioritize addressing:\n" top-failures "\n"
                "Focus first on the highest-impact failures before addressing secondary issues.")))))

(defun strategy-failure-driven-prioritization-get-metadata ()
  (list :name "strategy-failure-driven-prioritization"
        :version "1.0"
        :hypothesis "Reordering guidance by observed failure frequency improves fix accuracy."
        :axis "C"
        :components ["failure-frequency" "section-reorder"]))

(provide 'strategy-failure-driven-prioritization)