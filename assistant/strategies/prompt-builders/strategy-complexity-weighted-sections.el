;;; strategy-complexity-weighted-sections.el --- Complexity-based section prioritization -*- lexical-binding: t; -*-
;; Hypothesis: Files with higher cyclomatic complexity benefit from reordered sections prioritizing testing and defensive patterns.
;; Axis: C, D
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-complexity-weighted-sections-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with complexity-weighted section ordering."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (complexity (gptel-auto-experiment--compute-complexity target)))
    (if (> complexity 10)
        (concat base-prompt "\n\n;; COMPLEXITY-AWARE GUIDANCE:\n;; High complexity detected. Prioritize test coverage, defensive coding, and edge case handling.")
      (concat base-prompt "\n\n;; COMPLEXITY-AWARE GUIDANCE:\n;; Low complexity detected. Focus on simplicity, clarity, and potential for refactoring."))))

(defun gptel-auto-experiment--compute-complexity (file)
  "Compute cyclomatic complexity approximation for FILE."
  (when (file-exists-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (let ((control-keywords 0)
            (functions 0))
        (goto-char (point-min))
        (while (re-search-forward (rx (or "if" "when" "unless" "cond" "while" "dolist" "dotimes" "cl-loop" "cl-dolist" "cl-dotimes" "condition-case")) nil t)
          (setq control-keywords (1+ control-keywords)))
        (goto-char (point-min))
        (while (re-search-forward (rx (or "defun" "defmacro" "defadvice" "cl-defun" "cl-defmacro")) nil t)
          (setq functions (1+ functions)))
        (max 1 (+ control-keywords functions))))))

(defun strategy-complexity-weighted-sections-get-metadata ()
  (list :name "complexity-weighted-sections"
        :version "1.0"
        :hypothesis "Complexity metrics should determine which guidance sections receive priority."
        :axis "C,D"
        :components ["complexity" "section-ordering" "adaptive-guidance"]))

(provide 'strategy-complexity-weighted-sections)