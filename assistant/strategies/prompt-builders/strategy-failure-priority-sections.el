;;; strategy-failure-priority-sections.el --- Failure-driven section ordering -*- lexical-binding: t; -*-
;; Hypothesis: Prioritizing sections addressing recurring failure patterns leads to better fix quality.
;; Axis: C
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-failure-priority-sections-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with failure-pattern-driven section prioritization."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (patterns (plist-get analysis :patterns))
         ;; Extract failure types and count their frequency
         (failure-frequencies (strategy-failure-priority-sections--compute-frequencies patterns))
         ;; Generate prioritized guidance based on most common failures
         (prioritized-guidance (strategy-failure-priority-sections--build-guidance failure-frequencies)))
    (concat base-prompt "\n\n;; Failure-pattern priority guidance\n" prioritized-guidance)))

(defun strategy-failure-priority-sections--compute-frequencies (patterns)
  "Compute frequency map of failure types from patterns."
  (let ((freqs (ht-create)))
    (dolist (pattern patterns)
      (let* ((type (plist-get pattern :type))
             (category (cond
                        ((string-match-p "null\\|nil\\|void" type) "null-check")
                        ((string-match-p "type\\|mismatch" type) "type-error")
                        ((string-match-p "bound\\|undefined" type) "unbound")
                        ((string-match-p "recursive\\|infinite" type) "recursion")
                        (t "other"))))
        (ht-put freqs category (1+ (or (ht-get freqs category) 0)))))
    freqs))

(defun strategy-failure-priority-sections--build-guidance (failure-frequencies)
  "Build guidance string prioritizing sections for most frequent failures."
  (let ((guidance "FOCUS areas based on failure history:\n"))
    (maphash (lambda (category count)
               (setq guidance
                     (concat guidance
                             (format "- %s failures (%d occurrences): %s\n"
                                     category count
                                     (pcase category
                                       ("null-check" "Ensure all nullable values are guarded before use")
                                       ("type-error" "Verify argument and return types match expectations")
                                       ("unbound" "Confirm all referenced symbols are bound in scope")
                                       ("recursion" "Check base case and termination conditions")
                                       (t "Review code structure and logic flow"))))))
             failure-frequencies)
    guidance))

(defun strategy-failure-priority-sections-get-metadata ()
  (list :name "failure-priority-sections"
        :version "1.0"
        :hypothesis "Prioritizing sections addressing recurring failure patterns leads to better fix quality"
        :axis "C"
        :components ["failure-analysis" "priority-guidance"]))

(provide 'strategy-failure-priority-sections)