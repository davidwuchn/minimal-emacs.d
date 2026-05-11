;;; strategy-error-cluster-skills.el --- Skill loading via error type clustering -*- lexical-binding: t; -*-
;; Hypothesis: Loading skills dynamically based on clustered error types improves fix relevance.
;; Axis: E (Skill loading)

(require 'gptel-tools-agent-prompt-build)

(defun strategy-error-cluster-skills-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET using error-cluster-based skill loading."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (failure-patterns (plist-get analysis :patterns))
         (error-cluster (when failure-patterns (cluster-failure-types failure-patterns)))
         (skill-content (when error-cluster (load-skills-for-cluster error-cluster))))
    (if (string-empty-p skill-content)
        base-prompt
      (concat base-prompt "\n\n;; Skills for dominant error cluster\n" skill-content))))

(defun cluster-failure-types (patterns)
  "Cluster failure PATTERNS by type and return the dominant cluster keyword."
  (let ((type-counts (make-hash-table :test 'equal)))
    (dolist (pattern patterns)
      (let ((type (or (plist-get pattern :type) "general")))
        (puthash type (1+ (gethash type type-counts 0)) type-counts)))
    (car (cl-sort (maphash (lambda (k v) (cons k v)) type-counts)
                  (lambda (a b) (> (cdr a) (cdr b)))
                  :key #'cdr))))

(defun load-skills-for-cluster (cluster-keyword)
  "Load relevant skill content for CLUSTER-KEYWORD."
  (let ((skill-map '(("type-error" . "type-checking")
                     ("null-error" . "null-safety")
                     ("scope-error" . "lexical-scoping")
                     ("performance" . "optimization")
                     (t . "general-debugging"))))
    (gptel-auto-workflow--load-skill-content
     (or (cdr (assoc cluster-keyword skill-map))
         "general-debugging"))))

(defun strategy-error-cluster-skills-get-metadata ()
  (list :name "error-cluster-skills"
        :version "1.0"
        :hypothesis "Loading skills dynamically based on clustered error types improves fix relevance."
        :axis "E"
        :components ["error-clustering" "dynamic-skill-load"]))

(provide 'strategy-error-cluster-skills)