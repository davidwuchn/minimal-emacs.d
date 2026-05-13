;;; strategy-topic-cluster-context.el --- Retrieve context from semantically similar changes -*- lexical-binding: t; -*-
;; Hypothesis: Retrieving context from previously successful changes in similar topics improves solution quality.
;; Axis: B (Context retrieval)

(require 'gptel-tools-agent-prompt-build)

(defun strategy-topic-cluster-context-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET with topic-cluster-based context retrieval."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         ;; Get topic knowledge for target
         (target-topic (gptel-auto-experiment--get-topic-knowledge target))
         ;; Extract semantic cluster from previous results
         (cluster-context (strategy-topic-cluster-context--retrieve-cluster target-topic previous-results))
         ;; Generate cluster-specific guidance
         (cluster-guidance (strategy-topic-cluster-context--format-cluster-guidance cluster-context)))
    (concat base-prompt "\n\n;; Topic cluster context\n" cluster-context "\n\n" cluster-guidance)))

(defun strategy-topic-cluster-context--retrieve-cluster (topic previous-results)
  "Retrieve context from similar topics in PREVIOUS-RESULTS based on TOPIC."
  (when previous-results
    (let* ((topic-keywords (strategy-topic-cluster-context--extract-keywords topic))
           ;; Find results with similar topics
           (similar-results (seq-filter
                             (lambda (result)
                               (strategy-topic-cluster-context--similar-topics-p topic-keywords result))
                             previous-results))
           ;; Extract successful patterns from similar results
           (success-patterns (mapcar
                              (lambda (result)
                                (plist-get result :successful-approach))
                              similar-results)))
      (when success-patterns
        (string-join (delq nil success-patterns) "\n---\n")))))

(defun strategy-topic-cluster-context--extract-keywords (topic)
  "Extract semantic keywords from TOPIC."
  (when topic
    (let* ((words (split-string topic "[^a-zA-Z0-9-]+" t))
           (significant (seq-filter
                         (lambda (w)
                           (and (>= (length w) 4)
                                (not (member (downcase w) '("mode" "hook" "func" "defun" "defvar")))))
                         words)))
      significant)))

(defun strategy-topic-cluster-context--similar-topics-p (keywords result)
  "Check if RESULT has similar topics to KEYWORDS."
  (let ((result-topic (plist-get result :topic)))
    (when result-topic
      (let ((result-keywords (strategy-topic-cluster-context--extract-keywords result-topic)))
        (seq-intersection keywords result-keywords)))))

(defun strategy-topic-cluster-context--format-cluster-guidance (cluster-context)
  "Format guidance based on CLUSTER-CONTEXT."
  (if (string-empty-p cluster-context)
      "No similar topic patterns found; apply general best practices."
    (format "Similar topics have been successfully resolved using the following approaches:\n%s"
            "See patterns above and adapt them to this context.")))

(defun strategy-topic-cluster-context-get-metadata ()
  (list :name "topic-cluster-context"
        :version "1.0"
        :hypothesis "Retrieving context from semantically similar past changes improves solution quality."
        :axis "B"
        :components ["topic-extraction" "cluster-retrieval" "semantic-matching"]))

(provide 'strategy-topic-cluster-context)