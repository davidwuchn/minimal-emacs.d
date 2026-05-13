;;; strategy-tiered-context-expansion.el --- Progressive context loading based on analysis -*- lexical-binding: t; -*-
;; Hypothesis: Starting with minimal context and progressively expanding based on detected needs improves focus.
;; Axis: B, F
;;
(require 'gptel-tools-agent-prompt-build)
(require 'cl-lib)

(defun strategy-tiered-context-expansion-build-prompt
    (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with tiered context expansion based on analysis depth needs."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (patterns (plist-get analysis :patterns))
         (recommendations (plist-get analysis :recommendations))
         (needs-tier (cond
                      ((null patterns) 1)
                      ((null recommendations) 2)
                      ((> (length patterns) 5) 3)
                      (t 2)))
         (topic-knowledge (gptel-auto-experiment--get-topic-knowledge target))
         (tiered-additions
          (cl-case needs-tier
            (1 "")
            (2 (format "\n\n;; Tier 2 Context\n;; Additional context may be available if needed.\n;; Detected patterns: %d\n"
                       (length patterns)))
            (3 (format "\n\n;; Tier 3 Extended Context\n;; High complexity detected - additional context included.\n;; Pattern analysis:\n%s\n\n;; Topic knowledge:\n%s\n\n;; Recommendations:\n%s\n"
                       (mapconcat #'identity patterns "\n")
                       topic-knowledge
                       (mapconcat (lambda (r) (format "- %s" r)) recommendations "\n"))))))
    (concat base-prompt tiered-additions)))

(defun strategy-tiered-context-expansion-get-metadata ()
  (list :name "tiered-context-expansion"
        :version "1.0"
        :hypothesis "Tiered context expansion based on detected complexity improves prompt focus and reduces noise"
        :axis "B, F"
        :components ["tiered-loading" "complexity-detection"]))

(provide 'strategy-tiered-context-expansion)