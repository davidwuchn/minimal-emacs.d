;;; strategy-diversity-encouragement.el --- Promote exploration diversity based on prior results -*- lexical-binding: t; -*-
;; Hypothesis: Analyzing past approaches and explicitly discouraging repetition fosters innovation.
;; Axis: D
;;
;; IMPORTANT: Use a MEANINGFUL name replacing NAME (e.g., strategy-weighted-skills,
;; strategy-outcome-reasoning, not strategy-evolved-0006).
;; The name should describe the core mechanism in 2-4 hyphenated words.

(require 'gptel-tools-agent-prompt-build)

(defun strategy-diversity-encouragement-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Inject diversity guidance by identifying repetitive patterns in previous experiments."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (past-strategies (mapcar (lambda (res)
                                   (plist-get res :strategy-used))
                                 previous-results))
         (strategy-counts (cl-reduce (lambda (acc s)
                                       (if s
                                           (cons (cons s (1+ (or (cdr (assoc s acc)) 0))) acc)
                                         acc))
                                     past-strategies
                                    :initial-value nil))
         (most-used (car (sort strategy-counts
                              (lambda (a b) (> (cdr a) (cdr b))))))
         (diversity-message (if most-used
                               (format "\n\n;; DIVERSITY NOTE: You have used '%s' %d time(s) before. Try a fundamentally different approach this time."
                                       (car most-used) (cdr most-used))
                              "\n\n;; DIVERSITY NOTE: Previous strategies not available; explore new ideas.")))
    (concat base-prompt diversity-message)))

(defun strategy-diversity-encouragement-get-metadata ()
  "Return metadata for this strategy."
  (list :name "diversity-encouragement"
        :version "1.0"
        :hypothesis "Explicit diversity prompts reduce repetition and improve exploration"
        :axis "D"
        :components ["diversity" "variable-computation"]))

(provide 'strategy-diversity-encouragement)