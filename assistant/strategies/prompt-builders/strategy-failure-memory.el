;;; strategy-failure-memory.el --- Cross-experiment failure pattern mining -*- lexical-binding: t; -*-
;; Hypothesis: Mining cross-target failure patterns from previous experiments enables anticipatory guidance
;; Axis: D (Variable computation)
;;
;; This strategy analyzes failure patterns across all previous experiments to identify
;; recurring failure modes, then injects targeted guidance to prevent those specific failures.

(require 'gptel-tools-agent-prompt-build)
(require 'cl-lib)

(defun strategy-failure-memory-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET with cross-experiment failure memory.
Analyzes previous results to identify recurring failure patterns and injects anticipatory guidance."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (failure-memory (strategy-failure-memory--mine-failure-patterns previous-results)))
    (if (> (length failure-memory) 0)
        (concat base-prompt "\n\n;; Cross-experiment failure memory\n" failure-memory)
      base-prompt)))

(defun strategy-failure-memory--mine-failure-patterns (previous-results)
  "Mine recurring failure patterns from PREVIOUS-RESULTS.
Identifies patterns appearing across multiple experiments and extracts their characteristics."
  (let* ((failure-signatures (cl-loop for result in previous-results
                                      when (plist-get result :keep)
                                      collect (strategy-failure-memory--extract-signature result)))
         (pattern-counts (strategy-failure-memory--count-common-patterns failure-signatures))
         (top-patterns (cl-loop for (pattern . count) in pattern-counts
                                when (>= count 2)
                                collect (cons pattern count)
                                into qualifying
                                finally return (sort qualifying (lambda (a b) (> (cdr a) (cdr b)))))))
    (when top-patterns
      (strategy-failure-memory--format-failure-guidance top-patterns))))

(defun strategy-failure-memory--extract-signature (result)
  "Extract a failure signature from RESULT.
Captures key characteristics that may indicate failure modes."
  (let ((patterns (plist-get result :patterns))
        (recommendations (plist-get result :recommendations)))
    (list
     :complexity (cond
                  ((and patterns (string-match-p "large" (format "%s" patterns))) 'high-complexity)
                  ((and patterns (string-match-p "small" (format "%s" patterns))) 'low-complexity)
                  (t 'medium-complexity))
     :domain (cond
              ((and recommendations (string-match-p "regex\\|string" (format "%s" recommendations))) 'text-processing)
              ((and recommendations (string-match-p "buffer\\|window" (format "%s" recommendations))) 'ui-operations)
              ((and recommendations (string-match-p "list\\|sequence" (format "%s" recommendations))) 'iteration)
              (t 'general)))))

(defun strategy-failure-memory--count-common-patterns (signatures)
  "Count occurrences of each pattern type in SIGNATURES.
Returns alist of (pattern . count)."
  (let ((counts (make-hash-table :test 'equal)))
    (dolist (sig signatures)
      (let ((complexity (plist-get sig :complexity))
            (domain (plist-get sig :domain)))
        (when complexity
          (puthash (format "complexity:%s" complexity)
                   (1+ (gethash (format "complexity:%s" complexity) counts 0))
                   counts))
        (when domain
          (puthash (format "domain:%s" domain)
                   (1+ (gethash (format "domain:%s" domain) counts 0))
                   counts))))
    (let ((result '()))
      (maphash (lambda (k v) (push (cons k v) result)) counts)
      result)))

(defun strategy-failure-memory--format-failure-guidance (top-patterns)
  "Format TOP-PATTERNS into guidance text.
Creates specific preventive guidance based on recurring failure modes."
  (let ((guidance-lines '("Based on cross-experiment analysis:"))
        (domain-guidance '((text-processing . "When working with text/regex operations, verify all match groups are properly handled and edge cases are covered")
                           (ui-operations . "For buffer/window operations, ensure proper cleanup and guard against nil window/buffer states")
                           (iteration . "In iteration scenarios, handle empty sequences and potential side-effects in traversed structures")
                           (general . "General code improvements should preserve existing behavior and handle edge cases"))))
    (dolist (pattern-count top-patterns)
      (let ((pattern (car pattern-count)))
        (cond
         ((string-match "domain:" pattern)
          (let* ((domain-str (substring pattern (length "domain:")))
                 (domain (intern domain-str))
                 (guidance (or (cdr (assq domain domain-guidance)) "Apply domain-specific best practices")))
            (push (format "- %s" guidance) guidance-lines)))
         ((string-match "complexity:high-complexity" pattern)
          (push "- For high-complexity targets, prefer minimal changes that preserve existing structure" guidance-lines))
         ((string-match "complexity:low-complexity" pattern)
          (push "- For low-complexity targets, opportunities for refactoring may be limited" guidance-lines)))))
    (string-join (reverse guidance-lines) "\n")))

(defun strategy-failure-memory-get-metadata ()
  (list :name "failure-memory"
        :version "1.0"
        :hypothesis "Mining cross-target failure patterns enables anticipatory guidance that prevents recurring failures"
        :axis "D"
        :components ["failure-signature-extraction" "cross-experiment-pattern-mining"]))

(provide 'strategy-failure-memory)