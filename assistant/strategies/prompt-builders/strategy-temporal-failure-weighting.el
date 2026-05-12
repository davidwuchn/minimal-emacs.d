;;; strategy-temporal-failure-weighting.el --- Weight failures by recency -*- lexical-binding: t; -*-
;; Hypothesis: Recent failures indicate current problems; weighting them higher improves focus.
;; Axis: D (Variable computation)
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-temporal-failure-weighting-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt weighting failure patterns by temporal recency."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (patterns (plist-get analysis :patterns))
         (weighted-patterns (strategy-temporal-failure-weighting--compute-weights patterns previous-results experiment-id))
         (formatted-patterns (gptel-auto-experiment--format-failure-patterns weighted-patterns)))
    (concat base-prompt "\n\n;; Temporal-weighted failure patterns (recent = higher priority):\n" formatted-patterns)))

(defun strategy-temporal-failure-weighting--compute-weights (patterns previous-results current-exp)
  "Compute temporal weights for PATTERNS based on when they last appeared in PREVIOUS-RESULTS."
  (let ((pattern-last-seen (make-hash-table :test 'equal)))
    (cl-loop for result in previous-results
             for exp-num from 1
             do (dolist (pattern (plist-get result :patterns))
                  (let ((key (symbol-name (if (symbolp pattern) pattern (car pattern)))))
                    (puthash key exp-num pattern-last-seen))))
    (mapcar (lambda (pattern)
              (let* ((key (symbol-name (if (symbolp pattern) pattern (car pattern))))
                     (last-seen (or (gethash key pattern-last-seen) 0))
                     (recency-weight (/ (+ last-seen 1.0) (+ current-exp 1))))
                (list pattern recency-weight)))
            patterns)))

(defun strategy-temporal-failure-weighting-get-metadata ()
  (list :name "temporal-failure-weighting"
        :version "1.0"
        :hypothesis "Weighting failure patterns by recency focuses attention on currently relevant issues"
        :axis "D"
        :components ["temporal-weighting" "failure-patterns" "recency-computation"]))

(provide 'strategy-temporal-failure-weighting)