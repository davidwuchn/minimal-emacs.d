;;; strategy-cross-target-synthesis.el --- Synthesize patterns from all targets -*- lexical-binding: t; -*-
;; Hypothesis: Cross-pollinating successful patterns from other targets accelerates improvement discovery
;; Axis: D

(require 'gptel-tools-agent-prompt-build)

(defun strategy-cross-target-synthesis-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt synthesizing patterns from all targets in PREVIOUS-RESULTS."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (cross-patterns (gptel-auto-experiment--format-cross-target-patterns previous-results))
         (success-synthesis (strategy-cross-target-synthesis--extract-successes previous-results))
         (failure-avoidance (strategy-cross-target-synthesis--extract-failures previous-results))
         (synthesis-section
          (concat
           "\n\n;; Cross-Target Pattern Synthesis\n"
           (when cross-patterns (format ";; Shared patterns across targets:\n%s\n" cross-patterns))
           (when success-synthesis (format ";; Successful approaches to adapt:\n%s\n" success-synthesis))
           (when failure-avoidance (format ";; Approaches to avoid:\n%s\n" failure-avoidance)))))
    (concat base-prompt synthesis-section)))

(defun strategy-cross-target-synthesis--extract-successes (previous-results)
  "Extract successful improvement patterns from PREVIOUS-RESULTS."
  (let ((successes nil))
    (dolist (result previous-results)
      (let ((score (plist-get result :score))
            (baseline (plist-get result :baseline))
            (approach (plist-get result :approach)))
        (when (and score baseline approach (> score baseline))
          (push (format "- Score improvement: %.2f → %.2f using: %s"
                       baseline score approach)
                successes))))
    (mapconcat #'identity (seq-take (delete-dups successes) 5) "\n")))

(defun strategy-cross-target-synthesis--extract-failures (previous-results)
  "Extract failed approaches from PREVIOUS-RESULTS."
  (let ((failures (make-hash-table :test 'equal)))
    (dolist (result previous-results)
      (let ((score (plist-get result :score))
            (baseline (plist-get result :baseline))
            (approach (plist-get result :approach)))
        (when (and score baseline approach (< score (* 0.9 baseline)))
          (puthash approach (1+ (gethash approach failures 0)) failures))))
    (let ((sorted (sort (hash-table-keys failures)
                        (lambda (a b) (> (gethash a failures 0)
                                        (gethash b failures 0))))))
      (mapconcat (lambda (f) (format "- Avoid: %s (failed %d times)"
                                    f (gethash f failures)))
                 (seq-take sorted 3)
                 "\n"))))

(defun strategy-cross-target-synthesis-get-metadata ()
  (list :name "cross-target-synthesis"
        :version "1.0"
        :hypothesis "Cross-pollinating patterns from other targets accelerates discovery of effective improvements"
        :axis "D"
        :components ["cross-target-patterns" "success-synthesis" "failure-aggregation"]))

(provide 'strategy-cross-target-synthesis)