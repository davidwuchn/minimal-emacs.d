;;; strategy-complexity-weighted-guidance.el --- Complexity-based guidance weighting -*- lexical-binding: t; -*-
;; Hypothesis: Code complexity metrics should modulate the intensity of improvement guidance.
;; Axis: D
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-complexity-weighted-guidance-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET with complexity-weighted guidance."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (complexity-metrics (gptel-auto-experiment--compute-complexity-metrics target))
         (complexity-score (plist-get complexity-metrics :score))
         (guidance-intensity (cond
                              ((>= complexity-score 0.8) "HIGH - File has significant complexity, prioritize simplicity improvements")
                              ((>= complexity-score 0.5) "MEDIUM - Moderate complexity detected, consider refactoring opportunities")
                              (t "LOW - File complexity is manageable, focus on other quality aspects"))))
    (concat base-prompt "\n\n;; Complexity-Weighted Guidance\n"
            "File Complexity Assessment: " guidance-intensity
            "\nComplexity Score: " (number-to-string complexity-score)
            "\nTop complexity areas: " (mapconcat 'identity (plist-get complexity-metrics :hotspots) ", "))))

(defun gptel-auto-experiment--compute-complexity-metrics (target)
  "Compute cyclomatic complexity and nesting depth metrics for TARGET."
  (with-temp-buffer
    (insert-file-contents target)
    (let ((functions 0)
          (max-nesting 0)
          (total-nesting 0)
          (lines 0))
      (goto-char (point-min))
      (while (re-search-forward (rx bol (or "defun" "defmacro" "cl-defun" "defsubst")) nil t)
        (setq functions (1+ functions))
        (let ((func-end (save-excursion
                          (forward-defun 1)
                          (point))))
          (goto-char (match-beginning 0))
          (while (and (< (point) func-end) (re-search-forward (rx (any "(")) func-end t))
            (setq total-nesting (1+ total-nesting))
            (setq max-nesting (max max-nesting total-nesting)))
          (goto-char func-end)))
      (setq lines (count-lines (point-min) (point-max)))
      (let ((score (min 1.0 (/ (+ (* 0.1 functions) (* 0.01 max-nesting) (* 0.001 lines)) 10.0))))
        (list :score score
              :functions functions
              :max-nesting max-nesting
              :lines lines
              :hotspots (list (format "%d functions" functions)
                              (format "max nesting %d" max-nesting)))))))

(defun strategy-complexity-weighted-guidance-get-metadata ()
  (list :name "complexity-weighted-guidance"
        :version "1.0"
        :hypothesis "Code complexity metrics should modulate the intensity of improvement guidance."
        :axis "D"
        :components ["complexity-metrics" "adaptive-guidance"]))

(provide 'strategy-complexity-weighted-guidance)