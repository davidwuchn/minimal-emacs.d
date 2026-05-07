;;; strategy-hypothesis-typed.el --- Hypothesis-type guided exploration strategy -*- lexical-binding: t; -*-
;; Hypothesis: Categorizing hypotheses by type and guiding toward underrepresented types
;; will improve diversity and coverage of the solution space.
;;
;; NEW MECHANISM: This strategy categorizes hypotheses into types (bug-fix, performance,
;; refactoring, safety, testing) and computes which types are underrepresented in prior
;; experiments. It then injects guidance encouraging exploration of under-explored types.

(require 'gptel-tools-agent-prompt-build)
(require 'cl-lib)

(defvar strategy-hypothesis-typed--hypothesis-types
  '(("bug-fix" . "Bug fixes: null checks, error handling, edge cases")
    ("performance" . "Performance: caching, algorithmic improvements, complexity reduction")
    ("refactoring" . "Refactoring: extract functions, remove duplication, improve naming")
    ("safety" . "Safety: validation, edge case protection, error messages")
    ("testing" . "Testing: add missing tests for existing functionality")))

(defun strategy-hypothesis-typed--categorize-hypothesis (hypothesis-text)
  "Categorize HYPOTHESIS-TEXT into one of the hypothesis types.
Returns a type string like \"bug-fix\", \"performance\", etc."
  (let ((h (downcase (or hypothesis-text ""))))
    (cond
     ((or (string-match-p "fix\\|bug\\|error\\|null\\|undefined" h)
          (string-match-p "guard\\|check\\|prevent\\|edge" h))
      "bug-fix")
     ((or (string-match-p "cache\\|performance\\|speed\\|optimiz" h)
          (string-match-p "complex\\|memory\\|efficient" h))
      "performance")
     ((or (string-match-p "extract\\|duplicat\\|refactor\\|simplif" h)
          (string-match-p "rename\\|reorganiz" h))
      "refactoring")
     ((or (string-match-p "validat\\|safe\\|protect\\|guard" h)
          (string-match-p "error message\\|sanitiz" h))
      "safety")
     ((or (string-match-p "test\\|coverage\\|assert" h))
      "testing")
     (t "unknown"))))

(defun strategy-hypothesis-typed--compute-type-distribution (previous-results)
  "Compute distribution of hypothesis types in PREVIOUS-RESULTS.
Returns (counts . total) where counts is a hash table."
  (let* ((type-names '("bug-fix" "performance" "refactoring" "safety" "testing"))
         (counts (make-hash-table :test 'equal))
         (total 0))
    (dolist (type type-names)
      (puthash type 0 counts))
    (dolist (result (if (listp previous-results) previous-results nil))
      (let* ((hypothesis (plist-get result :hypothesis))
             (type (strategy-hypothesis-typed--categorize-hypothesis hypothesis)))
        (unless (string= type "unknown")
          (setq total (1+ total))
          (puthash type (1+ (gethash type counts 0)) counts))))
    (cons counts total)))

(defun strategy-hypothesis-typed--select-underrepresented-types (counts total)
  "Select hypothesis types that are underrepresented.
Returns list of types that have been tried < 20% of the time."
  (let* ((type-names '("bug-fix" "performance" "refactoring" "safety" "testing"))
         (threshold (/ (float (max total 1)) 5.0))
         result)
    (dolist (type type-names result)
      (let ((count (gethash type counts 0)))
        (when (< count threshold)
          (push type result))))
    (nreverse result)))

(defun strategy-hypothesis-typed--build-exploration-guidance (underrepresented-types)
  "Build guidance encouraging exploration of UNDERREPRESENTED-TYPES.
Returns formatted string to inject into prompt."
  (when underrepresented-types
    (concat "## EXPERIMENT DIVERSITY GUIDANCE\n\n"
            "Based on analysis of prior experiments, the following hypothesis types are underrepresented:\n\n"
            (mapconcat
             (lambda (type)
               (let ((desc (or (cdr (assoc type strategy-hypothesis-typed--hypothesis-types)) type)))
                 (format "- EXPLORE: %s" desc)))
             underrepresented-types "\n")
            "\n\n"
            "Consider prioritizing one of these under-explored types to improve solution space coverage.\n")))

(defun strategy-hypothesis-typed-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt using hypothesis-type guided exploration.
This strategy adds diversity guidance based on categorizing prior hypotheses."
  ;; Get baseline prompt
  (let* ((base-prompt (gptel-auto-experiment-build-prompt target experiment-id max-experiments analysis baseline previous-results))
         ;; Compute type distribution from prior results
         (distribution (strategy-hypothesis-typed--compute-type-distribution previous-results))
         (counts (car distribution))
         (total (cdr distribution))
         ;; Select underrepresented types
         (underrepresented (strategy-hypothesis-typed--select-underrepresented-types counts total))
         ;; Build diversity guidance if we have data
         (diversity-guidance (when (> total 0)
                               (strategy-hypothesis-typed--build-exploration-guidance underrepresented))))
    ;; Inject diversity guidance into the prompt
    (if (and diversity-guidance (not (string-empty-p diversity-guidance)))
        (concat base-prompt "\n\n" diversity-guidance)
      base-prompt)))

(defun strategy-hypothesis-typed-get-metadata ()
  "Return metadata for this strategy."
  (list :name "hypothesis-typed"
        :version "1.0"
        :hypothesis "Categorizing hypotheses by type and guiding toward underrepresented types improves solution space diversity"
        :axis "A"
        :created (format-time-string "%Y-%m-%d")
        :parent-strategies '("template-default")
        :components '("hypothesis-categorization" "type-distribution" "diversity-guidance" "underrep-analysis")
        :description "Analyzes prior hypotheses by type and injects guidance encouraging exploration of under-explored hypothesis categories."))

;; Register self
(when (fboundp 'gptel-auto-workflow--register-strategy)
  (gptel-auto-workflow--register-strategy
   "hypothesis-typed"
   #'strategy-hypothesis-typed-build-prompt
   (strategy-hypothesis-typed-get-metadata)))

(provide 'strategy-hypothesis-typed)
;;; strategy-hypothesis-typed.el ends here
