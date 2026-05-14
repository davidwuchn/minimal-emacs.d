;;; strategy-reasoning-chain.el --- Two-stage reasoning prompt structure -*- lexical-binding: t; -*-
;; Hypothesis: Explicit analysis-then-improvement reasoning improves systematic code fixes
;; Axis: A

(require 'gptel-tools-agent-prompt-build)

(defun strategy-reasoning-chain-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build two-stage reasoning prompt for TARGET."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (analysis-section (format "\n\n## Stage 1: Analysis\nAnalyze %s and identify:\n1. Specific anti-patterns present\n2. Root causes of each issue\n3. Relationships between issues"
                                   (file-name-nondirectory target)))
         (improvement-section "\n\n## Stage 2: Improvement\nBased on the analysis above, implement specific improvements:\n- Address root causes, not symptoms\n- Prioritize by impact\n- Ensure consistency"))
    (concat base-prompt analysis-section improvement-section)))

(defun strategy-reasoning-chain-get-metadata ()
  (list :name "reasoning-chain"
        :version "1.0"
        :hypothesis "Explicit analysis-then-improvement reasoning improves systematic fixes"
        :axis "A"
        :components ["two-stage-prompt" "chain-of-thought"]))

(provide 'strategy-reasoning-chain)