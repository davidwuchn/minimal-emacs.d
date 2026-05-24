;;; strategy-experiment-velocity-context.el --- Experiment-stage-aware context compression -*- lexical-binding: t; -*-
;; Hypothesis: Varying context granularity based on experiment progress balances exploration vs exploitation
;; Axis: F (Adaptive compression)

(require 'gptel-tools-agent-prompt-build)
(require 'cl-lib)

(defun strategy-experiment-velocity-context-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with experiment-stage-aware context compression."
  (let* ((stage (compute-experiment-stage experiment-id max-experiments))
         (context-level (stage-to-context-level stage))
         (base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (compressed-prompt (apply-context-compression base-prompt context-level)))
    (concat compressed-prompt "\n\n;; Experiment Stage: " (symbol-name stage))))

(defun compute-experiment-stage (experiment-id max-experiments)
  "Compute current experiment stage based on progress ratio."
  (let ((ratio (/ (float experiment-id) max-experiments)))
    (cond
     ((< ratio 0.33) 'early-exploration)
     ((< ratio 0.66) 'mid-refinement)
     (t 'late-exploitation))))

(defun stage-to-context-level (stage)
  "Map STAGE to context compression level."
  (pcase stage
    ('early-exploration 'aggressive)
    ('mid-refinement 'moderate)
    ('late-exploitation 'minimal)))

(defun apply-context-compression (prompt level)
  "Apply LEVEL of compression to PROMPT based on stage."
  (pcase level
    ('aggressive
     (compress-aggressive prompt))
    ('moderate
     (compress-moderate prompt))
    ('minimal
     prompt)))

(defun compress-aggressive (prompt)
  "Apply aggressive compression: summarize previous results, remove low-signal sections."
  (let* ((sections (split-string prompt "\n\n"))
         (keep-sections '("Task" "Code under analysis" "Failure patterns" "Guidance"))
         (compressed (cl-loop for section in sections
                              when (cl-some (lambda (k) (string-match-p k section)) keep-sections)
                              collect section)))
    (format "%s\n\n;; [Compressed: early-stage focus on core patterns]"
            (string-join compressed "\n\n"))))

(defun compress-moderate (prompt)
  "Apply moderate compression: summarize older experiments, keep recent patterns."
  (let ((summarized-patterns (summarize-pattern-history prompt)))
    (replace-regexp-in-string
     "\\|\\(# [0-9]+ results?\\)\\|\\(Experiment [0-9]+ details\\)"
     summarized-patterns
     prompt)))

(defun summarize-pattern-history (prompt)
  "Generate summary of pattern history instead of full details."
  ";; [Pattern summary: N failures across M categories - see detailed logs]")

(defun strategy-experiment-velocity-context-get-metadata ()
  "Return metadata for this strategy."
  (list :name "experiment-velocity-context"
        :version "1.0"
        :hypothesis "Varying context granularity based on experiment progress balances exploration vs exploitation"
        :axis "F"
        :components ["stage-awareness" "velocity-compression" "temporal-context"]))

(provide 'strategy-experiment-velocity-context)