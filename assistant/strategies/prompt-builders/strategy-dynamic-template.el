;;; strategy-dynamic-template.el --- Dynamic template selection based on code characteristics -*- lexical-binding: t; -*-
;; Hypothesis: Selecting template architecture based on computed code complexity improves focus
;; Axis: A

(require 'gptel-tools-agent-prompt-build)

(defun strategy-dynamic-template-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt using dynamic template selection based on TARGET characteristics."
  (let* ((char-count (length (with-temp-buffer (ignore-errors (insert-file-contents target)) (buffer-string))))
         (line-count (with-temp-buffer (insert-file-contents target) (count-lines (point-min) (point-max))))
         (complexity-score (/ char-count (max 1 line-count)))
         (template-variant (cond
                            ((> complexity-score 200) "verbose")
                            ((> complexity-score 100) "standard")
                            (t "concise")))
         (base-prompt (gptel-auto-experiment-build-prompt
                      target experiment-id max-experiments analysis baseline previous-results)))
    (concat base-prompt
            (format "\n\n;; Template variant: %s (complexity ratio: %.1f chars/line)"
                    template-variant complexity-score)
            (pcase template-variant
              ("verbose" "\n;; PRIORITY: Provide detailed explanations for each change")
              ("concise" "\n;; PRIORITY: Focus on minimal, targeted modifications")
              (_ "")))))

(defun strategy-dynamic-template-get-metadata ()
  (list :name "dynamic-template"
        :version "1.0"
        :hypothesis "Selecting template architecture based on computed code complexity improves focus"
        :axis "A"
        :components ["template-selection" "complexity-metrics"]))

(provide 'strategy-dynamic-template)