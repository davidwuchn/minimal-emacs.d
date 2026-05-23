;;; strategy-semantic-failure-clustering.el --- Cluster failures by semantic similarity -*- lexical-binding: t; -*-
;; Hypothesis: Grouping failure patterns by semantic similarity enables faster root-cause identification.
;; Axis: B/D (Context retrieval / Variable computation)
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-semantic-failure-clustering-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET by clustering failure patterns semantically."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt target experiment-id max-experiments analysis baseline previous-results))
         (patterns (plist-get analysis :patterns))
         (clusters (strategy-scf--cluster-patterns patterns))
         (clustered-failures (strategy-scf--format-clusters clusters)))
    (concat base-prompt "\n\n;; Semantically Clustered Failures\n" clustered-failures)))

(defun strategy-scf--cluster-patterns (patterns)
  "Cluster PATTERNS by semantic similarity using keyword overlap."
  (if (null patterns)
      nil
    (let* ((groups (list nil)))
      (dolist (pattern patterns)
        (let* ((keywords (strategy-scf--extract-keywords pattern))
               (placed nil))
          (dolist (group groups)
            (let* ((group-key (car group)))
              (when (strategy-scf--keyword-overlap keywords group-key 2)
                (setcdr group (cons pattern (cdr group)))
                (setq placed t))))
          (unless placed
            (push (cons keywords (list pattern)) groups))))
      (delq nil groups))))

(defun strategy-scf--extract-keywords (pattern)
  "Extract keywords from PATTERN for similarity matching."
  (let* ((desc (or (plist-get pattern :description) ""))
         (type (or (plist-get pattern :type) ""))
         (combined (concat type " " desc))
         (words (split-string combined "[^a-zA-Z0-9]+"))
         (filtered (seq-filter (lambda (w) (> (length w) 3)) words)))
    (seq-uniq filtered)))

(defun strategy-scf--keyword-overlap (kw1 kw2 threshold)
  "Check if KW1 and KW2 share at least THRESHOLD common keywords."
  (let* ((intersection (seq-intersection kw1 kw2)))
    (>= (length intersection) threshold)))

(defun strategy-scf--format-clusters (clusters)
  "Format CLUSTERS for prompt inclusion."
  (if (null clusters)
      "No failure patterns detected."
    (mapconcat
     (lambda (cluster)
       (let* ((keywords (car cluster))
              (failures (cdr cluster))
              (count (length failures)))
         (format "[%s cluster: %d failure(s)]\n- %s"
                 (string-join (seq-take keywords 3) ",")
                 count
                 (mapconcat (lambda (f) (or (plist-get f :description) "Unknown"))
                            failures "\n- "))))
     clusters
     "\n\n")))

(defun strategy-semantic-failure-clustering-get-metadata ()
  (list :name "semantic-failure-clustering"
        :version "1.0"
        :hypothesis "Clustering failure patterns by semantic similarity enables faster root-cause identification"
        :axis "B/D"
        :components ["failure-analysis" "semantic-grouping"]))

(provide 'strategy-semantic-failure-clustering)