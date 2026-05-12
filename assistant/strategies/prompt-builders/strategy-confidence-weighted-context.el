;;; strategy-confidence-weighted-context.el --- Weight context by confidence scores -*- lexical-binding: t; -*-
;; Hypothesis: Higher confidence targets benefit from minimal context while lower confidence targets need expanded guidance
;; Axis: D
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-confidence-weighted-context-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt weighted by computed confidence scores."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (confidence (strategy-confidence-weighted-context--compute-confidence target))
         (context-weight (strategy-confidence-weighted-context--get-context-weight confidence))
         (confidence-section (format "\n\n;; Confidence analysis:\nConfidence: %.2f\nContext weight: %s\nReasoning: %s"
                                      confidence
                                      context-weight
                                      (strategy-confidence-weighted-context--reasoning target confidence))))
    (concat base-prompt confidence-section)))

(defun strategy-confidence-weighted-context--compute-confidence (target)
  "Compute confidence score for TARGET based on code complexity heuristics."
  (let ((score 0.5)
        (has-defuns nil)
        (has-macros nil)
        (complexity 0))
    (when (and (stringp target) (file-exists-p target))
      (with-temp-buffer
        (insert-file-contents target)
        (setq complexity (/ (buffer-size) 1000.0))
        (goto-char (point-min))
        (when (re-search-forward (rx (or bol ";;;")) nil t)
          (setq has-defuns t))
        (goto-char (point-min))
        (when (re-search-forward (rx (or "cl-" "gx-")) nil t)
          (setq has-macros t))))
    (setq score (+ 0.3 (* 0.1 (min complexity 3.0))))
    (when has-defuns (setq score (+ score 0.2)))
    (when has-macros (setq score (- score 0.2)))
    (max 0.1 (min 0.9 score))))

(defun strategy-confidence-weighted-context--get-context-weight (confidence)
  "Return context weighting based on CONFIDENCE."
  (cond ((< confidence 0.3) "expand")
        ((< confidence 0.6) "moderate")
        (t "compact")))

(defun strategy-confidence-weighted-context--reasoning (target confidence)
  "Generate reasoning string explaining the CONFIDENCE score for TARGET."
  (let ((factors nil))
    (when (and (stringp target) (file-exists-p target))
      (with-temp-buffer
        (insert-file-contents target)
        (let ((size (buffer-size)))
          (when (> size 5000) (push "large file" factors))
          (goto-char (point-min))
          (when (re-search-forward (rx (or "cl-loop" "cl-block")) nil t)
            (push "complex macros" factors)))))
    (if factors
        (format "Based on: %s" (mapconcat #'identity (reverse factors) ", "))
      "Based on: standard file characteristics")))

(defun strategy-confidence-weighted-context-get-metadata ()
  (list :name "confidence-weighted-context"
        :version "1.0"
        :hypothesis "Higher confidence targets benefit from minimal context while lower confidence targets need expanded guidance"
        :axis "D"
        :components ["confidence-scoring" "adaptive-weighting" "reasoning-explicit"]))

(provide 'strategy-confidence-weighted-context)