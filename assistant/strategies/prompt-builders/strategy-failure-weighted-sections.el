;;; strategy-failure-weighted-sections.el --- Failure-weighted section ordering -*- lexical-binding: t; -*-
;; Hypothesis: Prioritizing sections based on failure pattern type improves signal quality
;; Axis: C
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-failure-weighted-sections-build-prompt
    (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with sections reordered based on failure pattern analysis."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (patterns (plist-get analysis :patterns))
         (failure-types (extract-failure-type-distribution patterns))
         (section-weights (compute-section-weights failure-types))
         (reordered-prompt (apply-section-weights base-prompt section-weights)))
    reordered-prompt))

(defun extract-failure-type-distribution (patterns)
  "Extract distribution of failure types from PATTERNS."
  (let ((type-counts '((:syntax . 0) (:logic . 0) (:style . 0) (:api . 0))))
    (dolist (pattern patterns)
      (let ((type (cond ((string-match-p "parse\\|syntax\\|unexpected" (prin1-to-string pattern)) :syntax)
                        ((string-match-p "incorrect\\|wrong\\|should\\|expected" (prin1-to-string pattern)) :logic)
                        ((string-match-p "naming\\|formatting\\|convention" (prin1-to-string pattern)) :style)
                        (t :api))))
        (cl-incf (cdr (assq type type-counts)))))
    type-counts))

(defun compute-section-weights (failure-types)
  "Compute section weights from FAILURE-TYPES distribution."
  (let ((syntax-weight (cdr (assq :syntax failure-types)))
        (logic-weight (cdr (assq :logic failure-types)))
        (style-weight (cdr (assq :style failure-types)))
        (api-weight (cdr (assq :api failure-types)))
        (total (apply #'+ (mapcar #'cdr failure-types))))
    (when (> total 0)
      (list :syntax (/ (* syntax-weight 100) total)
            :logic (/ (* logic-weight 100) total)
            :style (/ (* style-weight 100) total)
            :api (/ (* api-weight 100) total)))))

(defun apply-section-weights (prompt weights)
  "Apply WEIGHTS to reorder sections in PROMPT."
  (if (null weights)
      prompt
    (let ((syntax-weight (or (plist-get weights :syntax) 0))
          (logic-weight (or (plist-get weights :logic) 0))
          (api-weight (or (plist-get weights :api) 0))
          (reorder-strategy (cond ((> syntax-weight 40) "move-syntax-first")
                                  ((> logic-weight 40) "move-logic-first")
                                  ((> api-weight 30) "move-api-first")
                                  (t "keep-default"))))
      (gptel-auto-workflow--substitute-template
       prompt (list (cons "REORDER_STRATEGY" reorder-strategy))))))

(defun strategy-failure-weighted-sections-get-metadata ()
  (list :name "failure-weighted-sections"
        :version "1.0"
        :hypothesis "Prioritizing sections based on failure pattern type improves signal quality"
        :axis "C"
        :components ["failure-analysis" "section-weighting" "dynamic-reorder"]))

(provide 'strategy-failure-weighted-sections)