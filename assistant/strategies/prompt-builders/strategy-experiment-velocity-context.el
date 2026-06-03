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
  "Apply aggressive compression: keep high-signal sections for early exploration.
ASSUMPTION: Executor needs concrete directives plus failure context to act.
BEHAVIOR: Preserves Task, Code, Failure patterns, Guidance, plus
previous experiment analysis and weakest keys for actionable direction.
EDGE CASE: If no sections match, returns original prompt with warning.
TEST: Grep for `Compressed: early-stage` in output; verify kept sections present."
  (let* ((sections (split-string prompt "\n\n"))
         ;; ASSUMPTION: These sections provide minimum viable context for executor
         (keep-sections '("Task" "Code under analysis" "Failure patterns" "Guidance"
                          "previous experiment" "Weakest Keys" "Suggested Hypothesis"
                          "RELEVANT PAST" "Moderator Intervention"))
         (compressed (cl-loop for section in sections
                              when (cl-some (lambda (k) (string-match-p (regexp-quote k) section)) keep-sections)
                              collect section)))
    ;; EDGE CASE: If compression removed everything, fall back to original
    (if (and compressed (> (length compressed) 0))
        (format "%s\n\n;; [Compressed: early-stage focus on core patterns + failure context]"
                (string-join compressed "\n\n"))
      prompt)))

(defun compress-moderate (prompt)
  "Apply moderate compression: summarize older experiments, keep recent patterns.
ASSUMPTION: Mid-stage needs more context than early but less than late.
BEHAVIOR: Keeps all sections but truncates verbose experiment details.
TEST: Output should be shorter than input but retain all section headers."
  (let* ((sections (split-string prompt "\n\n"))
         (compressed (cl-loop for section in sections
                              collect
                              (cond
                               ;; Summarize old experiment details
                               ((string-match-p "\\(Experiment [0-9]+ details\\|#[0-9]+ result\\)" section)
                                (let ((first-line (car (split-string section "\n"))))
                                  (concat first-line "\n[Summarized: see full logs for details]")))
                               ;; Keep everything else intact
                               (t section)))))
    (string-join compressed "\n\n")))

(defun summarize-pattern-history (prompt)
  "Extract key failure patterns from PROMPT for summary.
ASSUMPTION: Pattern headers contain actionable failure categories.
BEHAVIOR: Scans for failure-related sections and extracts category names.
TEST: Returns non-empty string when prompt contains failure patterns."
  (let* ((sections (split-string prompt "\n\n"))
         (failure-sections (cl-loop for section in sections
                                    when (string-match-p "\\(Failure\\|failure\\|pattern\\)" section)
                                    collect section))
         (summary-lines (cl-loop for section in failure-sections
                                 for lines = (split-string section "\n")
                                 for header = (car lines)
                                 when header
                                 collect (format "- %s" (substring header 0 (min 80 (length header)))))))
    (if summary-lines
        (concat ";; [Pattern summary]\n" (string-join summary-lines "\n"))
      ";; [Pattern summary: no failure patterns detected]")))

(defun strategy-experiment-velocity-context-get-metadata ()
  "Return metadata for this strategy."
  (list :name "experiment-velocity-context"
        :version "1.0"
        :hypothesis "Varying context granularity based on experiment progress balances exploration vs exploitation"
        :axis "F"
        :components ["stage-awareness" "velocity-compression" "temporal-context"]))

(provide 'strategy-experiment-velocity-context)
