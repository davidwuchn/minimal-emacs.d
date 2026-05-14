;;; strategy-complexity-weighted.el --- Complexity-based section weighting -*- lexical-binding: t; -*-
;; Hypothesis: Dynamically weighting prompt sections based on code complexity produces better-tailored recommendations.
;; Axis: D (Variable computation)
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-complexity-weighted-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET with complexity-weighted sections."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (complexity (strategy-complexity-weighted--compute-complexity target))
         (complexity-score (plist-get complexity :score))
         (complexity-guidance (strategy-complexity-weighted--generate-guidance complexity)))
    (concat base-prompt "\n\n;; Complexity-Aware Guidance\n" complexity-guidance)))

(defun strategy-complexity-weighted--compute-complexity (file-path)
  "Compute complexity metrics for FILE-PATH.
Returns plist with :score :defun-count :avg-defun-size :nesting-level."
  (when (and (stringp file-path) (file-exists-p file-path))
    (with-temp-buffer
      (insert-file-contents file-path)
      (let* ((total-lines (count-lines (point-min) (point-max)))
             (defuns (strategy-complexity-weighted--count-defuns))
             (avg-defun-size (if (> defuns 0) (/ total-lines defuns) total-lines))
             (nesting (strategy-complexity-weighted--max-nesting)))
        (list :score (min 10 (+ (/ (float total-lines) 100)
                                (* defuns 0.1)
                                (* nesting 0.3)))
              :defun-count defuns
              :avg-defun-size avg-defun-size
              :nesting-level nesting
              :total-lines total-lines)))))

(defun strategy-complexity-weighted--count-defuns ()
  "Count top-level defun-like forms."
  (let ((count 0))
    (goto-char (point-min))
    (while (re-search-forward (concat "^[ \t]*(" (regexp-opt '("defun" "defmacro" "defsubst" "defadvice"
                                                                             "cl-defun" "cl-defmacro" "cl-defmethod"
                                                                             "define-minor-mode" "define-globalized-minor-mode"
                                                                             "define-derived-mode" "define-generic-mode") t))
                              nil t)
      (setq count (1+ count)))
    count))

(defun strategy-complexity-weighted--max-nesting ()
  "Estimate maximum nesting depth."
  (let ((max-depth 0)
        (current-depth 0))
    (goto-char (point-min))
    (while (re-search-forward "(" nil t)
      (when (not (eq (char-after) ?\;))
        (setq current-depth (1+ current-depth))
        (setq max-depth (max max-depth current-depth)))
    (when (and (not (eobp)) (eq (following-char) ?\)))
      (setq current-depth (max 0 (1- current-depth)))))
    max-depth))

(defun strategy-complexity-weighted--generate-guidance (complexity)
  "Generate guidance string based on COMPLEXITY metrics."
  (let ((score (plist-get complexity :score))
        (defuns (plist-get complexity :defun-count)))
    (cond
     ((> score 7) "HIGH COMPLEXITY detected. Prioritize refactoring opportunities, function extraction, and reducing coupling. Consider adding comments explaining complex control flow.")
     ((> score 4) "MODERATE COMPLEXITY. Balance feature additions with maintainability. Look for opportunities to simplify without changing external behavior.")
     (t "LOW COMPLEXITY. Focus on idiomatic Emacs Lisp patterns and potential feature additions rather than extensive refactoring."))))

(defun strategy-complexity-weighted-get-metadata ()
  (list :name "complexity-weighted"
        :version "1.0"
        :hypothesis "Dynamically weighting prompt sections based on code complexity produces better-tailored recommendations."
        :axis "D"
        :components ["variable-computation" "complexity-analysis"]))

(provide 'strategy-complexity-weighted)