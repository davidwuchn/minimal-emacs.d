;;; strategy-file-size-adaptation.el --- Guidance complexity matched to measured file size -*- lexical-binding: t; -*-
;; Hypothesis: Tailoring guidance complexity to measured file size provides better task framing
;; Axis: D

(require 'gptel-tools-agent-prompt-build)

(defun strategy-file-size-adaptation-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with file-size-adapted guidance."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (metrics (size--compute-file-metrics target))
         (guidance (size--format-adapted-guidance metrics)))
    (concat base-prompt "\n\n" guidance)))

(defun size--compute-file-metrics (target)
  "Compute size metrics for TARGET file."
  (when (and target (file-exists-p target) (not (file-directory-p target)))
    (let ((size (nth 7 (file-attributes target)))
          (lines (condition-case nil
                     (with-temp-buffer
                       (insert-file-contents target)
                       (count-lines (point-min) (point-max)))
                   (error 0))))
      (list :bytes size
            :lines lines
            :size-class (cond
                          ((> lines 500) 'large)
                          ((> lines 150) 'medium)
                          (t 'small))))))

(defun size--format-adapted-guidance (metrics)
  "Format adapted guidance based on METRICS."
  (when metrics
    (let* ((size-class (plist-get metrics :size-class))
           (lines (plist-get metrics :lines))
           (guidance
            (pcase size-class
              ('small (format ";; SMALL FILE (%d lines): Focus on precision and minimal surface area changes." lines))
              ('medium (format ";; MEDIUM FILE (%d lines): Maintain consistent patterns across all modified sections." lines))
              ('large (format ";; LARGE FILE (%d lines): Prioritize modular changes and clear boundary separation." lines))
              (_ ""))))
      guidance)))

(defun strategy-file-size-adaptation-get-metadata ()
  "Return metadata."
  (list :name "file-size-adaptation"
        :version "1.0"
        :hypothesis "Tailoring guidance complexity to measured file size provides better task framing"
        :axis "D"
        :components ["file-metrics" "size-classification" "adaptive-guidance"]))

(provide 'strategy-file-size-adaptation)