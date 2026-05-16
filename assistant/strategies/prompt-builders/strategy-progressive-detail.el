;;; strategy-progressive-detail.el --- Escalating detail based on context -*- lexical-binding: t; -*-
;; Hypothesis: Using progressive detail escalation (more detail early, less later)
;; optimizes token usage while maintaining improvement quality
;; Axis: F (Adaptive compression)

(require 'gptel-tools-agent-prompt-build)

(defvar strategy-progressive-detail--early-threshold 0.4
  "Fraction of max-experiments considered 'early' (high detail).")
(defvar strategy-progressive-detail--late-threshold 0.7
  "Fraction of max-experiments considered 'late' (aggressive compression).")

(defun strategy-progressive-detail--calculate-phase (experiment-id max-experiments)
  "Determine experiment phase: early, middle, or late."
  (let ((ratio (/ (float experiment-id) (max 1 max-experiments))))
    (cond
     ((< ratio strategy-progressive-detail--early-threshold) 'early)
     ((> ratio strategy-progressive-detail--late-threshold) 'late)
     (t 'middle))))

(defun strategy-progressive-detail--determine-window-size (target-file)
  "Determine analysis window size based on TARGET-FILE size."
  (when (and target-file (file-exists-p target-file))
    (with-temp-buffer
      (insert-file-contents target-file)
      (let ((lines (count-lines (point-min) (point-max))))
        (cond
         ((< lines 100) 50)
         ((< lines 300) 30)
         ((< lines 600) 20)
         (t 10))))))

(defun strategy-progressive-detail--select-sections-for-phase
    (target phase analysis)
  "Select which prompt sections to emphasize based on PHASE and ANALYSIS."
  (pcase phase
    ('early
     ;; Early: comprehensive overview, show all sections
     (list :focus 'all :detail-level 3 :include-examples t))
    ('middle
     ;; Middle: focus on patterns and recommendations
     (list :focus 'patterns :detail-level 2 :include-examples nil))
    ('late
     ;; Late: aggressive compression, focus only on critical patterns
     (list :focus 'critical :detail-level 1 :include-examples nil))))

(defun strategy-progressive-detail--generate-guidance (phase detail-level)
  "Generate compression guidance based on PHASE and DETAIL-LEVEL."
  (let ((depth-instruction
         (pcase detail-level
           (3 "Provide detailed, line-by-line analysis. Include specific examples from the code.")
           (2 "Provide moderate analysis. Focus on functional patterns and obvious improvements.")
           (1 "Provide concise guidance. Only mention critical issues requiring immediate action."))))
    (concat "\n\n;; Progressive Detail Guidance\n"
            (format ";; Experiment Phase: %s (detail level %d)\n" phase detail-level)
            depth-instruction "\n"
            (pcase phase
              ('early ";; Invest full context understanding now.\n")
              ('middle ";; Balance thoroughness with efficiency.\n")
              ('late ";; Maximize efficiency, rely on earlier context.\n")))))

(defun strategy-progressive-detail-build-prompt
    (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with progressive detail escalation for TARGET.
EXPERIMENT-ID: current experiment number.
MAX-EXPERIMENTS: total experiments planned.
ANALYSIS: plist with :patterns :recommendations.
BASELINE: current baseline score.
PREVIOUS-RESULTS: list of previous experiment plists."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (phase (strategy-progressive-detail--calculate-phase experiment-id max-experiments))
         (window-size (strategy-progressive-detail--determine-window-size target))
         (section-config (strategy-progressive-detail--select-sections-for-phase
                          target phase analysis))
         (detail-level (plist-get section-config :detail-level))
         (detail-guidance (strategy-progressive-detail--generate-guidance
                           phase detail-level))
         (window-hint (when window-size
                        (format ";; Analysis window: ~%d lines from relevant sections\n"
                                window-size)))
         (final-prompt (concat base-prompt detail-guidance
                               (or window-hint ""))))
    final-prompt))

(defun strategy-progressive-detail-get-metadata ()
  "Return metadata for this strategy."
  (list :name "progressive-detail"
        :version "1.0"
        :hypothesis "Escalating detail level based on experiment progress (high early, compressed late) optimizes token usage without sacrificing improvement quality"
        :axis "F"
        :components ["phase-detection" "adaptive-compression"]))

(provide 'strategy-progressive-detail)