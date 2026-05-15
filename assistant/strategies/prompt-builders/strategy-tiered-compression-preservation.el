;;; strategy-tiered-compression-preservation.el --- Priority-based compression tiers -*- lexical-binding: t; -*-
;; Hypothesis: Tiered compression preserving high-impact sections improves code improvement quality
;; Axis: F
;;
(require 'gptel-tools-agent-prompt-build)

(defun strategy-tiered-compression-preservation-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with tiered compression preserving high-impact sections."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                        target experiment-id max-experiments analysis baseline previous-results))
          (tiered-guidance (strategy-tiered-compression-preservation--build-tiered-guidance
                            previous-results)))
    (concat base-prompt tiered-guidance)))

(defun strategy-tiered-compression-preservation--build-tiered-guidance (previous-results)
  "Build tiered guidance based on historical section impact.
Tier 1 (critical): Never compress - core instructions
Tier 2 (high): Light compression - success-pattern guidance
Tier 3 (moderate): Standard compression - examples
Tier 4 (low): Heavy compression - supplementary info"
  (let* ((tier1 ";; TIER 1 - CRITICAL (always preserve):\n- Core improvement objective\n- Failure pattern definitions")
         (tier2 (strategy-tiered-compression-preservation--format-tier2 previous-results))
         (tier3 ";; TIER 3 - MODERATE (apply standard compression):\n- Prior successful examples"))
    (format "\n\n;; Tiered compression guidance\n%s\n\n%s\n\n%s"
            tier1
            (or tier2 ";; TIER 2 - HIGH: Dynamic based on experiment progress")
            tier3)))

(defun strategy-tiered-compression-preservation--format-tier2 (previous-results)
  "Format tier 2 guidance from previous successful strategies."
  (when previous-results
    (let ((successes (cl-remove-if-not (lambda (r)
                                        (> (or (plist-get r :score) 0) 0.5))
                                      previous-results)))
      (when successes
        (format ";; TIER 2 - HIGH (preserve successful patterns):\n- %s"
                (mapconcat (lambda (s)
                            (format "%s approach" (or (plist-get s :strategy) "Unknown")))
                          (last successes (min 2 (length successes)))
                          "\n- "))))))

(defun strategy-tiered-compression-preservation-get-metadata ()
  (list :name "tiered-compression-preservation"
        :version "1.0"
        :hypothesis "Tiered compression preserving high-impact sections improves code improvement quality"
        :axis "F"
        :components ["compression-tiers" "impact-prioritization"]))

(provide 'strategy-tiered-compression-preservation)
