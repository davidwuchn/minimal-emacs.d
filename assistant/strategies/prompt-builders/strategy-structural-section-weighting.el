;;; strategy-structural-section-weighting.el --- Weight prompt sections by code structure -*- lexical-binding: t; -*-
;; Hypothesis: Dynamic section weighting based on code structural characteristics improves focus on relevant guidance
;; Axis: D (Variable computation)
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-structural-section-weighting-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with sections weighted by code structural analysis."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (code-stats (strategy-structural-section-weighting--analyze-structure target))
         (section-weights (strategy-structural-section-weighting--compute-weights code-stats))
         (weighted-guidance (strategy-structural-section-weighting--format-weighted-guidance section-weights code-stats)))
    (concat base-prompt "\n\n;; Structural Analysis\n" weighted-guidance)))

(defun strategy-structural-section-weighting--analyze-structure (target)
  "Analyze structural characteristics of code at TARGET."
  (with-temp-buffer
    (insert-file-contents target)
    (let* ((content (buffer-string))
           (lines (split-string content "\n"))
           (line-count (length lines))
           (non-empty-lines (cl-count-if (lambda (s) (not (string-blank-p s))) lines))
           (comment-density (/ (float (cl-count-if (lambda (s) (string-match-p ";;" s)) lines)) (max 1 line-count)))
           (defun-count (cl-count-if (lambda (s) (string-match-p "^(def" s)) lines))
           (docstring-density (/ (float (cl-count-if (lambda (s) (string-match-p "\"" s)) lines)) (max 1 defun-count))))
      (list :line-count line-count
            :non-empty-lines non-empty-lines
            :comment-density comment-density
            :defun-count defun-count
            :docstring-density docstring-density
            :code-density (/ (float non-empty-lines) (max 1 line-count))))))

(defun strategy-structural-section-weighting--compute-weights (stats)
  "Compute section weights from structural STATS."
  (let ((comment-density (plist-get stats :comment-density))
        (docstring-density (plist-get stats :docstring-density))
        (defun-count (plist-get stats :defun-count))
        (code-density (plist-get stats :code-density)))
    (list :documentation-weight (cond
                                  ((< comment-density 0.1) 0.8)
                                  ((< comment-density 0.25) 0.5)
                                  (t 0.2))
          :refinement-weight (cond
                              ((> defun-count 20) 0.9)
                              ((> defun-count 10) 0.6)
                              (t 0.3))
          :structure-weight (cond
                             ((< code-density 0.6) 0.7)
                             (t 0.3))
          :test-priority (if (> docstring-density 0.5) 0.5 0.2))))

(defun strategy-structural-section-weighting--format-weighted-guidance (weights stats)
  "Format guidance based on computed WEIGHTS and STATS."
  (let ((doc-weight (plist-get weights :documentation-weight))
        (ref-weight (plist-get weights :refinement-weight))
        (struct-weight (plist-get weights :structure-weight))
        (line-count (plist-get stats :line-count))
        (defun-count (plist-get stats :defun-count)))
    (format "Based on code structure analysis (%.0f lines, %d definitions):\n\nPriority focus areas:\n- Documentation emphasis: %.0f%% (code has %.0f%% comment coverage)\n- Refinement thoroughness: %.0f%% (detected %d definitions requiring careful handling)\n- Structure preservation: %.0f%% (code density indicates structural concerns)"
            line-count defun-count
            (* doc-weight 100) (* (plist-get stats :comment-density) 100)
            (* ref-weight 100) defun-count
            (* struct-weight 100))))

(defun strategy-structural-section-weighting-get-metadata ()
  "Return metadata for this strategy."
  (list :name "structural-section-weighting"
        :version "1.0"
        :hypothesis "Dynamic section weighting based on code structural characteristics improves focus on relevant guidance"
        :axis "D"
        :components ["structural-analysis" "dynamic-weighting"]))

(provide 'strategy-structural-section-weighting)