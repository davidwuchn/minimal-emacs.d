;;; strategy-candidate-candidate--1.el --- Inject topic knowledge and cross-target patterns -*- lexical-binding: t; -*-
;; Hypothesis: Prepending domain topic knowledge and appending cross-target patterns improves contextual relevance.
;; Axis: B

(require 'gptel-tools-agent-prompt-build)

(defun strategy-candidate-candidate--1-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET using cascading context retrieval."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (topic (gptel-auto-experiment--get-topic-knowledge target))
         (cross (when previous-results
                  (gptel-auto-experiment--format-cross-target-patterns previous-results))))
    (concat (when topic (format ";; Topic Knowledge\n%s\n\n" topic))
            base-prompt
            (when cross (format "\n\n;; Cross-Target Patterns\n%s" cross)))))

(defun strategy-candidate-candidate--1-get-metadata ()
  (list :name "candidate-candidate--1"
        :version "1.0"
        :hypothesis "Prepending domain topic knowledge and appending cross-target patterns improves contextual relevance."
        :axis "B"
        :components ["context-retrieval" "cross-target"]))

(provide 'strategy-candidate-candidate--1)