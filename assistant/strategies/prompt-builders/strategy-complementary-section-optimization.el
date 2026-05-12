;;; strategy-complementary-section-optimization.el --- Select non-redundant sections -*- lexical-binding: t; -*-
;; Hypothesis: Selecting complementary sections that maximize unique coverage improves efficiency
;; Axis: C, A

(require 'gptel-tools-agent-prompt-build)

(defun strategy-complementary-section-optimization-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt selecting complementary non-redundant sections."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (coverage-analysis (analyze-section-coverage previous-results))
         (selected-sections (select-complementary-sections coverage-analysis))
         (section-guidance (format-complementary-guidance selected-sections coverage-analysis)))
    (concat base-prompt section-guidance)))

(defun analyze-section-coverage (previous-results)
  "Analyze which sections contributed to successful improvements in PREVIOUS-RESULTS.
Returns an alist of (section-name . success-rate)."
  (let ((section-scores '()))
    (dolist (result previous-results)
      (let ((improved (plist-get result :improved))
            (sections (plist-get result :included-sections)))
        (when sections
          (dolist (section sections)
            (let ((current (alist-get section section-scores nil nil #'string-equal)))
              (push (cons section (+ (if improved 1.0 0.0) (or current 0.0)))
                    section-scores)))))
      (let ((result-count (length previous-results))
            (normalized '()))
        (dolist (pair section-scores)
          (push (cons (car pair) (/ (cdr pair) result-count)) normalized))
        normalized))))

(defun select-complementary-sections (coverage-analysis)
  "Select sections that provide complementary coverage (maximize unique info).
Uses greedy selection preferring sections with high success rate and low overlap."
  (let ((selected '())
        (remaining coverage-analysis))
    (while (and remaining (< (length selected) 4))
      (let* ((best (car remaining))
             (best-section (car best))
             (best-score (cdr best)))
        (when (> best-score 0.3)
          (push best-section selected))
        (setq remaining (cdr remaining))))
    selected))

(defun format-complementary-guidance (selected-sections coverage-analysis)
  "Format guidance emphasizing SELECTED-SECTIONS for complementary coverage."
  (concat "\n\n;; Complementary Section Strategy:\n"
          (format ";; Prioritizing sections: %s\n" (mapconcat #'identity selected-sections ", "))
          ";; Rationale: Select sections that together maximize unique improvement coverage\n"
          (mapconcat (lambda (section)
                       (let ((score (alist-get section coverage-analysis nil nil #'string-equal)))
                         (format ";; - %s: %.1f%% historical success rate" section (* 100 (or score 0)))))
                     selected-sections "\n")))

(defun strategy-complementary-section-optimization-get-metadata ()
  (list :name "complementary-section-optimization"
        :version "1.0"
        :hypothesis "Selecting complementary non-redundant sections maximizes unique coverage per token"
        :axis "C,A"
        :components ["complementary-selection" "coverage-optimization" "section-pruning"]))

(provide 'strategy-complementary-section-optimization)