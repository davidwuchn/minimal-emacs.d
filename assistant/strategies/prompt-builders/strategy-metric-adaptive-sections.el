;;; strategy-metric-adaptive-sections.el --- Reorder sections based on file metrics -*- lexical-binding: t; -*-
;; Hypothesis: Section ordering should adapt to file characteristics: large/complex files prioritize structure, small files get comprehensive guidance
;; Axis: C, D

(require 'gptel-tools-agent-prompt-build)

(defun strategy-metric-adaptive-sections-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET using metric-adaptive section ordering."
  (let* ((metrics (strategy-metric-compute target))
         (base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (section-order (strategy-metric-determine-order metrics))
         (metric-guidance (format "\n\n;; Adaptive Section Ordering Guidance\n;; File metrics: %s\n;; Recommended section priority: %s"
                                  (prin1-to-string metrics)
                                  section-order)))
    (concat base-prompt metric-guidance)))

(defun strategy-metric-compute (target)
  "Compute metrics for TARGET content."
  (list :char-count (length target)
        :line-count (cl-count ?\n target)
        :complexity-score (strategy-metric-complexity target)
        :change-frequency (strategy-metric-change-frequency target)
        :pattern-density (strategy-metric-pattern-density target)))

(defun strategy-metric-complexity (target)
  "Compute cyclomatic-like complexity from nesting depth and control structures."
  (let ((nesting 0) (max-nesting 0) (controls 0))
    (dolist (char (string-to-list target))
      (cond ((eq char ?\() (setq nesting (1+ nesting))
             (setq max-nesting (max max-nesting nesting)))
            ((eq char ?\)) (setq nesting (1- nesting)))
            ((and (eq char ?\s) (> nesting 0)))
            (t (setq controls (1+ controls)))))
    (min 100 (+ (* 0.3 max-nesting) (* 0.7 (mod controls 100))))))

(defun strategy-metric-change-frequency (target)
  "Estimate change frequency from code patterns (todo/comment density)."
  (let ((todo-density (/ (float (cl-count ?T target)) (max 1 (length target)))))
    (min 100 (* todo-density 10000))))

(defun strategy-metric-pattern-density (target)
  "Compute pattern density for special forms usage."
  (let ((specials '("defun" "lambda" "let" "if" "cond" "when" "unless" "dolist" "mapcar" "setq"))
        (count 0))
    (dolist (spec specials) (setq count (+ count (cl-count ?\n target))))
    (min 100 (/ (float count) (max 1 (/ (length target) 1000))))))

(defun strategy-metric-determine-order (metrics)
  "Determine section order based on computed METRICS."
  (let ((size (plist-get metrics :char-count))
        (complexity (plist-get metrics :complexity-score)))
    (cond
     ((> size 10000) '("structure-first" "recent-changes" "patterns" "guidance"))
     ((> complexity 50) '("patterns" "structure-first" "recent-changes" "guidance"))
     (t '("guidance" "patterns" "structure-first" "recent-changes")))))

(defun strategy-metric-adaptive-sections-get-metadata ()
  (list :name "metric-adaptive-sections"
        :version "1.0"
        :hypothesis "Section ordering should adapt to file characteristics for optimal context delivery"
        :axis "C"
        :components ["metric-computation" "adaptive-ordering"]))

(provide 'strategy-metric-adaptive-sections)