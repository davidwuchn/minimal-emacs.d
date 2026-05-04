;;; strategy-success-examples.el --- Comparative example augmentation architecture -*- lexical-binding: t; -*-
;; Hypothesis: Including successful prior examples as in-prompt demonstrations improves code improvement
;; Axis: A

(require 'gptel-tools-agent-prompt-build)

(defun strategy-success-examples-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt augmented with comparative successful examples from prior experiments."
  (let* ((baseline-prompt (gptel-auto-experiment-build-prompt target experiment-id max-experiments analysis baseline previous-results))
         (successful-examples (extract-successful-examples previous-results target))
         (improvement-patterns (derive-improvement-patterns successful-examples)))
    (concat
     baseline-prompt
     "\n\n"
     "## COMPARATIVE SUCCESS EXAMPLES\n"
     "The following patterns have successfully improved similar code:\n\n"
     (string-join improvement-patterns "\n\n")
     "\n\n"
     "## APPLICATION GUIDANCE\n"
     "Consider applying analogous transformations to the target, prioritizing patterns with >0.3 quality gain.")))

(defun extract-successful-examples (previous-results target)
  "Extract examples where experiments improved target code successfully."
  (let ((examples nil))
    (dolist (result previous-results)
      (when (and (listp result)
                 (> (gethash 'quality result 0) 0.3)
                 (equal target (gethash 'target result)))
        (push (list :target (gethash 'target result)
                    :improvement (gethash 'improvement result)
                    :quality-gain (gethash 'quality result)
                    :pattern (gethash 'pattern result))
              examples)))
    (nreverse examples)))

(defun derive-improvement-patterns (examples)
  "Derive reusable improvement patterns from successful examples."
  (mapcar (lambda (ex)
            (format "Pattern: %s\nQuality Gain: +%.2f\nContext: %s"
                    (plist-get ex :pattern)
                    (plist-get ex :quality-gain)
                    (substring (plist-get ex :target) 0 (min 50 (length (plist-get ex :target))))))
          (seq-take examples 3)))

(defun strategy-success-examples-get-metadata ()
  (list :name "evolved-0002"
        :version "1.0"
        :hypothesis "Including successful prior examples as in-prompt demonstrations improves code improvement"
        :axis "A"))

(provide 'strategy-success-examples)