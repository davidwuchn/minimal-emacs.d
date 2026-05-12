;;; strategy-cross-target-failure-clusters.el --- Load related failure patterns from other targets -*- lexical-binding: t; -*-
;; Hypothesis: Cross-target failure pattern analysis will surface related issues that tend to co-occur
;; Axis: B (Context retrieval)

(require 'gptel-tools-agent-prompt-build)

(defun strategy-cross-target-failure-clusters-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET using cross-target failure cluster analysis."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (current-failures (plist-get analysis :patterns))
         (clustered-patterns (strategy-cross-target-failure-clusters--find-related
                              current-failures previous-results)))
    (if clustered-patterns
        (concat base-prompt "\n\n;; Related failure patterns from cross-target analysis\n" clustered-patterns)
      base-prompt)))

(defun strategy-cross-target-failure-clusters--find-related (current-failures previous-results)
  "Find failure patterns that tend to co-occur with CURRENT-FAILURES."
  (let* ((cooccurrence-map (strategy-cross-target-failure-clusters--build-cooccurrence previous-results))
         (related-types nil))
    (dolist (cfailure current-failures)
      (setq related-types (append related-types
                                   (gethash cfailure cooccurrence-map '()))))
    (when related-types
      (format "Co-occurring failure clusters detected: %s\nThese patterns frequently appear together across targets - consider addressing them jointly."
              (mapconcat #'identity (delete-dups related-types) ", ")))))

(defun strategy-cross-target-failure-clusters--build-cooccurrence (previous-results)
  "Build co-occurrence map from previous experiment failures."
  (let ((cooccurrence (make-hash-table :test 'equal))
        (all-experiments (reverse previous-results)))
    (dolist (exp all-experiments)
      (let ((patterns (plist-get exp :patterns)))
        (when (listp patterns)
          (let ((relevant (if (> (length patterns) 3) (butlast patterns 2) patterns)))
            (dolist (p1 relevant)
              (dolist (p2 relevant)
                (unless (equal p1 p2)
                  (puthash p1 (cons p2 (gethash p1 cooccurrence '()))) cooccurrence)))))))
    cooccurrence))

(defun strategy-cross-target-failure-clusters-get-metadata ()
  (list :name "cross-target-failure-clusters"
        :version "1.0"
        :hypothesis "Cross-target failure pattern analysis will surface related issues that tend to co-occur"
        :axis "B"
        :components ["pattern-extraction" "cooccurrence-analysis" "clustering"]))

(provide 'strategy-cross-target-failure-clusters)