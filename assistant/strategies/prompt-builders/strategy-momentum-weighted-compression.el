;;; strategy-momentum-weighted-compression.el --- Momentum-based adaptive compression -*- lexical-binding: t; -*-
;; Hypothesis: Compression strategy should dynamically shift based on experiment momentum rather than file size alone.
;; Axis: F (Adaptive compression)

(require 'gptel-tools-agent-prompt-build)

(defun strategy-momentum-weighted-compression-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt using momentum-weighted compression strategy.
High momentum (improving rapidly) → preserve more context.
Low momentum (plateau/stagnating) → use aggressive guidance compression."
  (let* ((momentum (compute-experiment-momentum previous-results))
         (compression-mode (cond
                            ((> momentum 0.3) 'preserve-context)
                            ((> momentum 0) 'balanced)
                            ((> momentum -0.3) 'guided-focus)
                            (t 'aggressive-guidance)))
         (base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (momentum-guidance (format "\n\n;; Momentum-Adaptive Guidance (momentum: %.2f, mode: %s)\n;; %s"
                                    momentum compression-mode
                                    (get-compression-guidance compression-mode))))
    (concat base-prompt momentum-guidance)))

(defun compute-experiment-momentum (results)
  "Compute momentum from recent experiments. Returns value between -1 and 1.
Positive = improving, negative = stagnating/declining."
  (if (< (length results) 2)
      0.0
    (let* ((recent (take 5 results))
           (deltas (mapcar (lambda (r)
                             (let ((score (or (plist-get r :score) 0))
                                   (base (or (plist-get r :baseline) 0)))
                               (if (= base 0) 0
                                 (/ (- score base) base))))
                           recent)))
      (if deltas
          (/ (apply '+ deltas) (float (length deltas)))
        0.0))))

(defun get-compression-guidance (mode)
  "Return compression guidance string for MODE."
  (pcase mode
    ('preserve-context "High momentum detected. Preserve full context and explore broadly.")
    ('balanced "Moderate momentum. Balance exploration with targeted guidance.")
    ('guided-focus "Low momentum. Focus on high-impact changes and reduce verbose context.")
    ('aggressive-guidance "Stagnation detected. Use strict guidance patterns and minimal context.")
    (_ "Default compression applied.")))

(defun strategy-momentum-weighted-compression-get-metadata ()
  (list :name "momentum-weighted-compression"
        :version "1.0"
        :hypothesis "Compression strategy should shift dynamically based on experiment momentum rather than file characteristics alone."
        :axis "F"
        :components ["momentum-computation" "adaptive-compression" "experiment-trajectory"]))

(provide 'strategy-momentum-weighted-compression)