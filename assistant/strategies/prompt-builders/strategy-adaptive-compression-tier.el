;;; strategy-adaptive-compression-tier.el --- Multi-tier adaptive compression -*- lexical-binding: t; -*-
;; Hypothesis: Using multiple compression tiers with different strategies based on file size produces better context preservation than single-tier compression.
;; Axis: F

(require 'gptel-tools-agent-prompt-build)

(defun strategy-adaptive-compression-tier-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt using multi-tier adaptive compression based on target complexity."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt target experiment-id max-experiments analysis baseline previous-results))
         (file-size (nth 7 (file-attributes target)))
         (compression-tier (strategy-compression-tier--determine-tier file-size))
         (compression-guidance (strategy-compression-tier--build-guidance compression-tier)))
    (concat base-prompt "\n\n;; Compression Strategy (tier " (number-to-string compression-tier) ")\n" compression-guidance)))

(defun strategy-compression-tier--determine-tier (file-size)
  "Determine compression tier based on file size in bytes."
  (cond ((> file-size 50000) 3)
        ((> file-size 20000) 2)
        (t 1)))

(defun strategy-compression-tier--build-guidance (tier)
  "Build compression guidance for the determined tier."
  (pcase tier
    (3 ;; Maximum compression
     (concat "TIER 3: Aggressive compression mode active.\n"
             "- Summarize function purposes without full body\n"
             "- Group related configuration into single descriptions\n"
             "- Omit repetitive patterns; note 'N similar patterns omitted'\n"
             "- Preserve only novel or complex logic in full detail\n"
             "- Prioritize: core algorithms > data structures > utilities"))
    (2 ;; Moderate compression
     (concat "TIER 2: Moderate compression mode active.\n"
             "- Keep function signatures and key logic\n"
             "- Summarize repetitive utility functions\n"
             "- Preserve unique patterns in full\n"
             "- Balance brevity with necessary detail"))
    (1 ;; Minimal compression
     (concat "TIER 1: Minimal compression mode active.\n"
             "- Full context preservation\n"
             "- Only remove obvious redundancy\n"
             "- Maintain all relevant details for thorough analysis"))
    (t "")))

(defun strategy-adaptive-compression-tier-get-metadata ()
  (list :name "adaptive-compression-tier"
        :version "1.0"
        :hypothesis "Multi-tier adaptive compression with tier-specific strategies provides optimal context preservation across diverse file sizes."
        :axis "F"
        :components ["tier-determination" "tier-specific-strategy" "size-thresholds"]))

(provide 'strategy-adaptive-compression-tier)