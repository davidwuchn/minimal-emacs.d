;;; strategy-recency-weighted-guidance.el --- Recency-weighted historical filtering -*- lexical-binding: t; -*-
;; Hypothesis: Weighting historical recommendations by recency and score delta focuses the AI on recently validated improvements rather than treating all past experiments equally.
;; Axis: D
;;
;; IMPORTANT: Use a MEANINGFUL name replacing NAME (e.g., strategy-weighted-skills,
;; strategy-outcome-reasoning, not strategy-evolved-0006).
;; The name should describe the core mechanism in 2-4 hyphenated words.

(require 'gptel-tools-agent-prompt-build)

(defun strategy-recency-weighted-guidance-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt for TARGET using recency-weighted historical guidance."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (weighted-recs
          (mapcar (lambda (res)
                    (let ((exp-id (or (plist-get res :experiment-id) 0))
                          (score (or (plist-get res :score) baseline)))
                      (list :weight (- experiment-id exp-id)
                            :delta (- score baseline)
                            :rec (plist-get res :recommendations))))
                  previous-results))
         (sorted-recs (sort weighted-recs (lambda (a b) (> (plist-get a :weight) (plist-get b :weight)))))
         (top-recs (let ((count 0) (result nil))
                     (dolist (item sorted-recs (nreverse result))
                       (when (< count 3)
                         (push item result)
                         (setq count (1+ count))))))
         (guidance-text ""))
    (dolist (item top-recs)
      (let ((rec (plist-get item :rec)))
        (when rec
          (setq guidance-text (concat guidance-text "\n- " (format "%s" rec))))))
    (concat base-prompt "\n\n;; Recency-Weighted Historical Guidance\n" guidance-text)))

(defun strategy-recency-weighted-guidance-get-metadata ()
  "Return metadata for this strategy."
  (list :name "recency-weighted-guidance"
        :version "1.0"
        :hypothesis "Weighting historical recommendations by recency and score delta focuses the AI on recently validated improvements rather than treating all past experiments equally."
        :axis "D"
        :components ["variable-computation" "historical-filtering" "weighting-scheme"]))

(provide 'strategy-recency-weighted-guidance)