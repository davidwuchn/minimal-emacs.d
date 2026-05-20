;;; strategy-compression-driven-sectioning.el --- Adaptive section ordering by compression -*- lexical-binding: t; -*-
;; Hypothesis: Reordering sections based on compression ratio preserves critical info
;; Axis: A (Prompt template architecture)
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-compression-driven-sectioning-build-prompt
    (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with compression-adaptive section ordering."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (prompt-len (length base-prompt))
         (compression-target 3000)
         (compression-ratio (/ (float prompt-len) compression-target)))
    (cond
     ((> compression-ratio 2.0)
      (concat base-prompt
              "\n\n;; HIGH COMPRESSION MODE: Prioritizing fix guidance\n"
              ";; Target file context compressed. Core fix patterns emphasized."))
     ((> compression-ratio 1.5)
      (concat base-prompt
              "\n\n;; MODERATE COMPRESSION: Balanced structure"))
     (t
      (concat base-prompt
              "\n\n;; LOW COMPRESSION: Full context available")))))

(defun strategy-compression-driven-sectioning-get-metadata ()
  (list :name "compression-driven-sectioning"
        :version "1.0"
        :hypothesis "Reordering sections based on compression ratio preserves critical info"
        :axis "A"
        :components ["compression-ratio" "adaptive-ordering"]))

(provide 'strategy-compression-driven-sectioning)