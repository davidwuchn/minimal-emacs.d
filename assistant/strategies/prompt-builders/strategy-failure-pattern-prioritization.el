;;; strategy-failure-pattern-prioritization.el --- Prioritize guidance by failure pattern matching -*- lexical-binding: t; -*-
;; Hypothesis: Dynamically reordering prompt sections based on failure pattern matching improves guidance relevance.
;; Axis: C (Section ordering)

(require 'gptel-tools-agent-prompt-build)

(defun strategy-failure-pattern-prioritization-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with sections reordered based on failure pattern matching."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         ;; NEW MECHANISM: Extract dominant failure patterns
         (patterns (plist-get analysis :patterns))
         (dominant-category (strategy-failure-pattern-prioritization--find-dominant patterns))
         ;; NEW MECHANISM: Reorder sections based on dominant pattern
         (prioritized-prompt (strategy-failure-pattern-prioritization--reorder base-prompt dominant-category)))
    prioritized-prompt))

(defun strategy-failure-pattern-prioritization--find-dominant (patterns)
  "Find the most frequent failure category in PATTERNS."
  (when patterns
    (let ((category-counts (seq-group-by (lambda (p) (plist-get p :category)) patterns)))
      (car (seq-sort-by (lambda (pair) (length (cdr pair))) #'> category-counts)))))

(defun strategy-failure-pattern-prioritization--reorder (prompt dominant-category)
  "Reorder sections in PROMPT to prioritize sections related to DOMINANT-CATEGORY."
  (let* ((sections (split-string prompt "\n\n;; ---"))
         (category-keywords (pcase dominant-category
                              ('performance '("optimization" "efficiency" "performance"))
                              ('correctness '("edge-case" "validation" "error"))
                              ('maintainability '("clarity" "refactor" "design"))
                              (t '("general" "style")))))
    (if (< (length sections) 3)
        prompt
      ;; NEW MECHANISM: Boost sections matching dominant category
      (let ((boosted-sections (mapcar (lambda (s)
                                        (if (seq-some (lambda (kw) (string-match-p kw s)) category-keywords)
                                            (concat s "\n;; [PRIORITY]") ; Boost signal
                                          s))
                                      sections)))
        (string-join boosted-sections "\n\n;; ---")))))

(defun strategy-failure-pattern-prioritization-get-metadata ()
  (list :name "failure-pattern-prioritization"
        :version "1.0"
        :hypothesis "Dynamically reordering prompt sections based on failure pattern matching improves guidance relevance."
        :axis "C"
        :components ["pattern-analysis" "section-reorder"]))

(provide 'strategy-failure-pattern-prioritization)