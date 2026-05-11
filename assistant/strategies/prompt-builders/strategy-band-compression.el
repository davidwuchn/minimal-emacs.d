;;; strategy-band-compression.el --- Priority-band adaptive compression -*- lexical-binding: t; -*-
;; Hypothesis: Prompt sections have different criticality; band-based compression preserves high-value sections while aggressively compressing low-value ones.
;; Axis: F (Adaptive compression)
;;
(require 'gptel-tools-agent-prompt-build)

(defvar strategy-band-compression--band-map
  '(("{{TASK_DESCRIPTION}}" . critical)
    ("{{CONSTRAINTS}}" . high)
    ("{{EXAMPLES}}" . medium)
    ("{{CONTEXT}}" . low)
    ("{{FAILURE_PATTERNS}}" . high)
    ("{{SKILLS}}" . medium)
    ("{{GUIDANCE}}" . high)))

(defun strategy-band-compression-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with priority-band based adaptive compression."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (compressed (strategy-band-comp--compress-by-bands base-prompt)))
    compressed))

(defun strategy-band-comp--compress-by-bands (prompt)
  "Apply band-specific compression ratios to sections in PROMPT."
  (let ((result prompt))
    (dolist (band-entry strategy-band-compression--band-map)
      (let* ((section (car band-entry))
             (priority (cdr band-entry))
             (ratio (pcase priority
                      ('critical 1.0)
                      ('high 0.85)
                      ('medium 0.6)
                      ('low 0.35)
                      (_ 0.5))))
        (when (string-match section result)
          (let ((start (match-beginning 0))
                (section-end (progn (goto-char (match-end 0))
                                   (search-forward "}}" nil t)
                                   (point))))
            (goto-char start)
            (let* ((section-text (buffer-substring-no-properties start section-end))
                   (compressed-section (gptel-auto-workflow--adapt-prompt-compression
                                        section-text ratio)))
              (setq result (concat (substring result 0 start)
                                   compressed-section
                                   (substring result section-end))))))))
    result))

(defun strategy-band-compression-get-metadata ()
  (list :name "band-compression"
        :version "1.0"
        :hypothesis "Priority-band compression preserves critical sections while aggressively compressing low-value ones"
        :axis "F"
        :components ["adaptive-compression" "priority-bands"]))

(provide 'strategy-band-compression)