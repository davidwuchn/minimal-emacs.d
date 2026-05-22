;;; strategy-complexity-compression.el --- Complexity-driven compression -*- lexical-binding: t; -*-
;; Hypothesis: High-complexity code benefits from more aggressive compression to focus on critical sections.
;; Axis: F (Adaptive compression)
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-complexity-compression-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with complexity-driven compression for TARGET."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (file-size (when (file-exists-p target)
                      (nth 7 (file-attributes target))))
         (complexity-level (cond
                            ((or (null file-size) (< file-size 5000)) 'low)
                            ((< file-size 50000) 'medium)
                            (t 'high)))
         (compression-factor (pcase complexity-level
                                ('low 1.0)
                                ('medium 0.8)
                                ('high 0.5)))
         (compression-note (format ";; Compression factor: %.1f (complexity: %s)"
                                   compression-factor complexity-level)))
    (concat base-prompt "\n\n" compression-note)))

(defun strategy-complexity-compression-get-metadata ()
  (list :name "complexity-compression"
        :version "1.0"
        :hypothesis "High-complexity code benefits from more aggressive compression to maintain focus"
        :axis "F"
        :components ["complexity-metrics" "adaptive-compression"]))

(provide 'strategy-complexity-compression)