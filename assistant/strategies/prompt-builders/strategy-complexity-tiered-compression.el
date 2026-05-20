;;; strategy-complexity-tiered-compression.el --- Adaptive compression by file complexity -*- lexical-binding: t; -*-
;; Hypothesis: Different compression strategies based on file complexity tiers produce better prompts than uniform compression.
;; Axis: D (Variable computation) and F (Adaptive compression)

(require 'gptel-tools-agent-prompt-build)

(defun strategy-complexity-tiered-compression-build-prompt (target experiment-id max-experiments analysis baseline previous-results)
  "Build prompt with complexity-based adaptive compression for TARGET."
  (let* ((base-prompt (gptel-auto-experiment-build-prompt
                       target experiment-id max-experiments analysis baseline previous-results))
         (complexity-tier (compute-file-complexity-tier target))
         (compression-strategy (select-compression-for-tier complexity-tier))
         (compression-guidance (generate-compression-guidance complexity-tier compression-strategy)))
    (concat base-prompt "\n\n;; Complexity-tiered compression\n" compression-guidance)))

(defun compute-file-complexity-tier (target)
  "Compute complexity tier for TARGET using AST-based metrics."
  (let* ((buffer (or (get-file-buffer target) (find-file-noselect target)))
         (ast-depth 0)
         (defun-count 0)
         (feature-count 0)
         (line-count (with-current-buffer buffer (count-lines (point-min) (point-max)))))
    (when buffer
      (with-current-buffer buffer
        (goto-char (point-min))
        (while (re-search-forward (rx (or "defun" "defmacro" "defgeneric" "cl-defun")) nil t)
          (setq defun-count (1+ defun-count)))
        (goto-char (point-min))
        (while (re-search-forward (rx (or "require" "use-package")) nil t)
          (setq feature-count (1+ feature-count)))
        (setq ast-depth (min 10 (/ (+ defun-count feature-count) 2)))))
    (cond
     ((> line-count 500) :complex)
     ((> line-count 200) :moderate)
     ((> defun-count 20) :dense)
     (t :simple))))

(defun select-compression-for-tier (tier)
  "Select compression strategy based on complexity tier."
  (pcase tier
    (:complex 'aggressive-summary)
    (:moderate 'selective-detail)
    (:dense 'function-focused)
    (_ 'minimal)))

(defun generate-compression-guidance (tier strategy)
  "Generate compression guidance based on tier and strategy."
  (format "Compression approach: %s (tier: %s)
- Focus on essential function signatures and critical logic paths
- Preserve error-handling patterns and edge case handling
- Summarize repetitive code sections rather than including verbatim"
          strategy (symbol-name tier)))

(defun strategy-complexity-tiered-compression-get-metadata ()
  (list :name "complexity-tiered-compression"
        :version "1.0"
        :hypothesis "Different compression strategies based on file complexity tiers produce better prompts than uniform compression."
        :axis "D/F"
        :components ["complexity-metrics" "tiered-compression"]))

(provide 'strategy-complexity-tiered-compression)