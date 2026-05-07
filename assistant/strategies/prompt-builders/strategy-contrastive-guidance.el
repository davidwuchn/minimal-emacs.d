;;; strategy-contrastive-guidance.el --- Contrastive failure guidance -*- lexical-binding: t; -*-
;; Hypothesis: Explicitly telling the agent what NOT to do based on prior failures
;; will reduce regression and improve decision quality compared to only showing patterns to follow.
;; Axis: A (Prompt template architecture)
;;
;; Key mechanism: Extract failure reasons and convert to anti-patterns that are
;; prominently displayed in the prompt alongside positive patterns.

(require 'gptel-tools-agent-prompt-build)

(defvar strategy-contrastive-guidance--failure-cache nil
  "Cache of failure reason -> anti-pattern mappings.")

(defun strategy-contrastive-guidance--extract-anti-pattern (failure-reason)
  "Convert a FAILURE-REASON string into an explicit anti-pattern.
Returns a string describing what to AVOID."
  (cond
   ;; Combined score regression
   ((or (string-match-p "combined score regressed" failure-reason)
        (string-match-p "score.*regressed" failure-reason))
    "AVOID: Changes that improve one metric while degrading another. Seek balanced improvements across all metrics.")
   ;; Score tie without improvement
   ((or (string-match-p "score tie without" failure-reason)
        (string-match-p "tie -> A.*Rejected.*tie" failure-reason))
    "AVOID: Submitting changes that result in score ties. Only commit when there's clear positive improvement.")
   ;; Quality maintained without improvement
   ((or (string-match-p "Quality.*→.*Quality" failure-reason)
        (string-match-p "quality maintained" failure-reason))
    "AVOID: Changes that maintain the same quality without improving it. Target quality improvements.")
   ;; Score maintained
   ((string-match-p "Score.*→.*Score" failure-reason)
    "AVOID: Changes that maintain the same score. Aim for score improvement, not just maintenance.")
   ;; No positive combined improvement
   ((string-match-p "without positive combined" failure-reason)
    "AVOID: Changes without measurable combined improvement. Calculate expected combined delta before committing.")
   ;; Inspection thrash
   ((string-match-p "inspection-thrash" failure-reason)
    "AVOID: Too many read-only inspections before writing. After identifying target, make first edit immediately.")
   ;; Default: generic warning
   (t
    (format "AVOID: Pattern '%s' which led to rejection" (substring failure-reason 0 (min 50 (length failure-reason)))))))

(defun strategy-contrastive-guidance--build-anti-patterns (target)
  "Build anti-patterns section for TARGET based on prior failure reasons."
  (let* ((failure-reasons (gptel-auto-experiment--get-common-failure-reasons target 5))
         (anti-patterns
          (when failure-reasons
            (mapcar #'strategy-contrastive-guidance--extract-anti-pattern failure-reasons))))
    (when anti-patterns
      (concat "## Anti-Patterns (What NOT to Do)\n"
              "Based on prior experiment failures:\n\n"
              (mapconcat (lambda (ap) (format "- %s" ap)) anti-patterns "\n")
              "\n\n"
              "CRITICAL: If your proposed change matches any of these patterns, reconsider your approach.\n\n"))))

(defun strategy-contrastive-guidance-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with contrastive failure guidance.
This strategy adds explicit anti-patterns derived from prior failures."
  ;; First build the base prompt
  (let* ((base-prompt (gptel-auto-experiment-build-prompt target experiment-id max-experiments analysis baseline previous-results))
         ;; Get anti-patterns for this target
         (anti-patterns (strategy-contrastive-guidance--build-anti-patterns target))
         ;; Parse out where to insert anti-patterns (before constraints section)
         (insertion-point (or (string-match "## Constraints\n" base-prompt)
                              (string-match "## Objective\n" base-prompt)
                              (string-match "## Instructions\n" base-prompt)
                              (length base-prompt))))
    (if anti-patterns
        (concat (substring base-prompt 0 insertion-point)
                anti-patterns
                (substring base-prompt insertion-point))
      base-prompt)))

(defun strategy-contrastive-guidance-get-metadata ()
  "Return metadata for this strategy."
  (list :name "contrastive-guidance"
        :version "1.0"
        :hypothesis "Explicit anti-patterns derived from prior failures will reduce regressions and improve decision quality"
        :axis "A"
        :created (format-time-string "%Y-%m-%d")
        :parent-strategies '("template-default")
        :components '("contrastive-failure" "anti-pattern-extraction" "guidance-insertion")
        :description "Adds explicit anti-patterns section derived from prior failure reasons."))

;; Register self
(when (fboundp 'gptel-auto-workflow--register-strategy)
  (gptel-auto-workflow--register-strategy
   "contrastive-guidance"
   #'strategy-contrastive-guidance-build-prompt
   (strategy-contrastive-guidance-get-metadata)))

(provide 'strategy-contrastive-guidance)
;;; strategy-contrastive-guidance.el ends here
