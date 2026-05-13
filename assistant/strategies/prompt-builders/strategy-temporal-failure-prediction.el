;;; strategy-temporal-failure-prediction.el --- Predict future failures from temporal patterns -*- lexical-binding: t; -*-
;; Hypothesis: Predicting which failure patterns will recur based on temporal analysis enables proactive avoidance
;; Axis: D
;;
(require 'gptel-tools-agent-prompt-build)
(require 'cl-lib)

(defun strategy-temporal-failure-prediction--extract-failure-themes (previous-results)
  "Extract recurring failure themes from PREVIOUS-RESULTS."
  (let ((themes nil))
    (dolist (result previous-results)
      (dolist (pattern (plist-get result :patterns))
        (let ((category (plist-get pattern :category)))
          (when category
            (let ((existing (assoc category themes)))
              (if existing
                  (setcdr existing (1+ (cdr existing)))
                (push (cons category 1) themes)))))))
    (cl-sort themes #'> :key #'cdr)))

(defun strategy-temporal-failure-prediction--predict-recurrence (themes experiment-id max-experiments)
  "Predict which themes will recur based on temporal position.
Early experiments show different recurrence patterns than late ones."
  (let* ((position (/ (float experiment-id) (float max-experiments)))
         (predicted-recurrence nil))
    (cond
     ((< position 0.3)
      (setq predicted-recurrence (cl-subseq themes 0 (min 2 (length themes)))))
     ((< position 0.7)
      (setq predicted-recurrence (cl-subseq themes 0 (min 3 (length themes)))))
     (t
      (setq predicted-recurrence (cl-subseq themes 0 (min 4 (length themes))))))
    predicted-recurrence))

(defun strategy-temporal-failure-prediction--generate-guidance (predicted-themes)
  "Generate proactive guidance based on PREDICTED-THEMES."
  (if (null predicted-themes)
      "No persistent failure patterns detected from prior experiments."
    (concat "Based on temporal analysis of your experiments, these patterns have historically recurred and warrant proactive attention:\n\n"
            (mapconcat #'(lambda (entry)
                           (format "- %s (observed in %d experiment(s))"
                                   (car entry) (cdr entry)))
                       predicted-themes
                       "\n")
            "\n\nPrioritize addressing these patterns before they manifest again.")))

(defun strategy-temporal-failure-prediction-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET using temporal failure prediction.
EXPERIMENT-ID: current experiment number.
MAX-EXPERIMENTS: total experiments planned.
ANALYSIS: plist with :patterns :recommendations from previous experiments.
BASELINE: current baseline score.
PREVIOUS-RESULTS: list of previous experiment plists."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (themes (strategy-temporal-failure-prediction--extract-failure-themes previous-results))
         (predicted (strategy-temporal-failure-prediction--predict-recurrence themes experiment-id max-experiments))
         (guidance (strategy-temporal-failure-prediction--generate-guidance predicted)))
    (concat base-prompt "\n\n;; Temporal Failure Prediction
;; This guidance is based on when in your experiment timeline you are.
;; Experiment " (number-to-string experiment-id) " of " (number-to-string max-experiments) "
;;
" guidance)))

(defun strategy-temporal-failure-prediction-get-metadata ()
  "Return metadata for this strategy."
  (list :name "temporal-failure-prediction"
        :version "1.0"
        :hypothesis "Predicting which failure patterns will recur based on temporal position enables proactive avoidance"
        :axis "D"
        :components ["temporal" "prediction" "recurrence"]))

(provide 'strategy-temporal-failure-prediction)