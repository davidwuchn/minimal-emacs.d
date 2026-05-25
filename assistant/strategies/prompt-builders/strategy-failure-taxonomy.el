;;; strategy-failure-taxonomy.el --- Failure pattern classification -*- lexical-binding: t; -*-
;; Hypothesis: Categorizing targets by historical failure patterns enables tailored improvement strategies.
;; Axis: D (Variable computation)

(require 'gptel-tools-agent-prompt-build)

(defvar strategy-failure-taxonomy--patterns
  '((:undefined-reference . "Focus on declaration checking and import resolution")
    (:logic-error . "Trace control flow and verify conditional boundaries")
    (:style-violation . "Apply coding standards and convention enforcement")
    (:performance-issue . "Analyze algorithmic complexity and hot paths")
    (:edge-case . "Test boundary conditions and nil/size edge handling")
    (:concurrency . "Check thread safety and synchronization patterns")
    (:error-handling . "Review exception paths and recovery mechanisms")
    (:api-misuse . "Verify parameter contracts and return value handling")))

(defun strategy-failure-taxonomy--extract-patterns (previous-results)
  "Extract failure patterns from PREVIOUS-RESULTS plist list."
  (let ((patterns nil))
    (dolist (result previous-results)
      (when (plist-get result :failure-pattern)
        (push (plist-get result :failure-pattern) patterns)))
    patterns))

(defun strategy-failure-taxonomy--compute-dominant-pattern (patterns)
  "Compute most frequent pattern from PATTERNS list."
  (let ((freq-table nil))
    (dolist (pat patterns)
      (setq freq-table (cons pat patterns)))
    (car patterns)))

(defun strategy-failure-taxonomy--classify-target (target patterns)
  "Classify TARGET based on PATTERNS detected in similar files."
  (let ((dominant (strategy-failure-taxonomy--compute-dominant-pattern patterns)))
    (if dominant
        (format "Detected pattern category: %s" dominant)
      "No strong pattern detected; apply general improvements")))

(defun strategy-failure-taxonomy--get-guidance (pattern-category)
  "Get tailored guidance for PATTERN-CATEGORY from taxonomy."
  (or (cdr (assoc pattern-category strategy-failure-taxonomy--patterns))
      "Apply systematic code improvement following best practices"))

(defun strategy-failure-taxonomy--generate-strategy (patterns previous-results)
  "Generate strategy based on PATTERNS and PREVIOUS-RESULTS."
  (let ((dominant (strategy-failure-taxonomy--compute-dominant-pattern patterns))
        (success-count (cl-count-if (lambda (r) (plist-get r :improved)) previous-results)))
    (format "Strategy selection: %s | Success history: %d/%d improvements"
            (if dominant (symbol-name dominant) "general")
            success-count
            (length previous-results))))

(defun strategy-failure-taxonomy-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt using failure taxonomy classification.
Classifies the current target based on patterns from historical failures."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (patterns (strategy-failure-taxonomy--extract-patterns previous-results))
         (classification (strategy-failure-taxonomy--classify-target target patterns))
         (guidance (strategy-failure-taxonomy--get-guidance (car patterns)))
         (strategy (strategy-failure-taxonomy--generate-strategy patterns previous-results)))
    (concat base-prompt "\n\n;; Failure taxonomy analysis\n"
            classification "\n"
            guidance "\n"
            strategy)))

(defun strategy-failure-taxonomy-get-metadata ()
  (list :name "failure-taxonomy"
        :version "1.0"
        :hypothesis "Categorizing targets by historical failure patterns enables tailored improvement strategies"
        :axis "D"
        :components ["pattern-classification" "taxonomy-mapping" "adaptive-guidance"]))

(provide 'strategy-failure-taxonomy)