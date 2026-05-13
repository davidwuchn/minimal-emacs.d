;;; strategy-complexity-proportional-context.el --- Complexity-weighted context allocation -*- lexical-binding: t; -*-
;; Hypothesis: Allocating proportionally more context to complex code regions yields better improvements.
;; Axis: F
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-complexity-proportional-context-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with context proportional to code complexity regions."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         ;; Retrieve code structure to identify complex regions
         (code-structure (condition-case nil
                             (gptel-auto-experiment--get-code-structure target)
                           (error nil)))
         (complexity-map (when code-structure
                           (gptel-auto-experiment--compute-complexity-regions code-structure)))
         ;; Generate complexity-aware section guidance
         (complexity-guidance
          (when complexity-map
            (format "\n\n;; Complexity-Weighted Context Guidance\n;; Focus detailed analysis on high-complexity regions:\n%s"
                    (gptel-auto-experiment--format-complexity-guidance complexity-map)))))
    (if complexity-guidance
        (concat base-prompt complexity-guidance)
      base-prompt)))

(defun strategy-complexity-proportional-context-get-metadata ()
  (list :name "complexity-proportional-context"
        :version "1.0"
        :hypothesis "All context allocation proportionally to code complexity regions improves targeted improvements"
        :axis "F"
        :components ["complexity-detection" "proportional-context"]))

(provide 'strategy-complexity-proportional-context)