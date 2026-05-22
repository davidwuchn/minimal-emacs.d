;;; strategy-failure-pattern-guided.el --- Prioritize guidance based on historical failure patterns -*- lexical-binding: t; -*-
;; Hypothesis: Analyzing failure patterns from previous experiments and amplifying relevant guidance improves success rates
;; Axis: D
;;
(require 'gptel-tools-agent-prompt-build)
(require 'cl-lib)

(defun strategy-failure-pattern-guided--extract-patterns (previous-results)
  "Extract failure patterns from PREVIOUS-RESULTS."
  (let ((patterns '()))
    (dolist (result previous-results)
      (when (and (plistp result)
                 (eq (plist-get result :outcome) 'failed))
        (let ((pattern (plist-get result :pattern))
              (error-type (plist-get result :error-type)))
          (when pattern
            (push pattern patterns))
          (when error-type
            (push error-type patterns)))))
    patterns))

(defun strategy-failure-pattern-guided--select-counter-measures (patterns)
  "Select counter-measures based on PATTERNS."
  (let ((measures '()))
    (dolist (pat patterns)
      (cond
       ((string-match-p "undefined\\|void\\|missing" pat)
        (push "Verify all variables and functions are defined before use. Check for typos in symbol names." measures))
       ((string-match-p "type\\|wrong-arg" pat)
        (push "Ensure function arguments match expected types. Consult Emacs documentation for function signatures." measures))
       ((string-match-p "scope\\|unbound" pat)
        (push "Check variable scope. Use lexical-let for closures, verify variables are bound before reference." measures))
       ((string-match-p "loop\\|iteration\\|infinite" pat)
        (push "Verify loop termination conditions. Add debug prints to track iteration counts." measures))
       ((string-match-p "async\\|callback\\|timing" pat)
        (push "Account for asynchronous execution. Ensure callbacks properly handle state transitions." measures))))
    (delete-dups measures)))

(defun strategy-failure-pattern-guided-build-prompt
    (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with failure-pattern-guided counter-measures."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (patterns (strategy-failure-pattern-guided--extract-patterns previous-results))
         (counter-measures (when patterns
                             (strategy-failure-pattern-guided--select-counter-measures patterns))))
    (if counter-measures
        (concat base-prompt
                "\n\n;; === HISTORICAL FAILURE COUNTER-MEASURES ===\n"
                "Based on patterns from previous experiments, pay special attention to:\n"
                (mapconcat (lambda (m) (concat "- " m)) counter-measures "\n"))
      base-prompt)))

(defun strategy-failure-pattern-guided-get-metadata ()
  (list :name "failure-pattern-guided"
        :version "1.0"
        :hypothesis "Extracting failure patterns from experiment history and amplifying relevant counter-measures improves success"
        :axis "D"
        :components ["pattern-analysis" "counter-measure-selection"]))

(provide 'strategy-failure-pattern-guided)