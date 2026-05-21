;;; gptel-auto-workflow-ontology-router.el --- Ontology-aware backend fallback reordering -*- lexical-binding: t -*-

;; Copyright (C) 2024-2026  Self-Evolving Emacs Project

;; Author: Self-Evolving System
;; Keywords: ontology, backend, routing, fallback, reordering

;;; Commentary:

;; Enhance existing headless fallback chain with ontology-aware reordering.
;; Uses `gptel-auto-workflow-headless-subagent-fallbacks' as source of truth,
;; reorders based on historical performance per task type.
;;
;; No new backends are added - only the ORDER is optimized.
;; Falls back to static order when insufficient data.

;;; Code:

(require 'gptel-auto-workflow-evolution)

(defvar gptel-auto-workflow-executor-rate-limit-fallbacks)
(defvar gptel-auto-workflow-headless-subagent-fallbacks)

(defcustom gptel-auto-workflow--ontology-reorder-min-samples 3
  "Minimum experiments before reordering fallback chain.
Below this, use the static headless fallback order."
  :type 'integer
  :group 'gptel-auto-workflow)

(defcustom gptel-auto-workflow--ontology-reorder-exploration-rate 0.15
  "Probability of trying non-optimal backend for learning (15%).
Ensures all backends get samples for fair comparison."
  :type 'float
  :group 'gptel-auto-workflow)

;; ─── Performance Lookup ───

(defun gptel-auto-workflow--get-backend-performance-stats (backend &optional strategy target)
  "Get performance stats for BACKEND, optionally filtered by STRATEGY/TARGET.
Returns plist with :kept :total :keep-rate."
  (let ((results (gptel-auto-workflow--parse-all-results))
        (kept 0)
        (total 0))
    (dolist (r results)
      (let ((r-backend (or (plist-get r :backend) "unknown"))
            (r-strategy (plist-get r :strategy))
            (r-target (plist-get r :target))
            (r-decision (plist-get r :decision)))
        (when (string= r-backend backend)
          (when (or (null strategy) (string= r-strategy strategy))
            (when (or (null target) (string= r-target target))
              (setq total (1+ total))
              (when (equal r-decision "kept")
                (setq kept (1+ kept))))))))
    (list :kept kept
          :total total
          :keep-rate (if (> total 0) (/ (float kept) total) nil))))

(defun gptel-auto-workflow--get-backend-keep-rate (backend &optional strategy target)
  "Get keep-rate for BACKEND from ontology, optionally filtered by STRATEGY/TARGET.
Returns float 0.0-1.0 or nil if no data."
  (plist-get (gptel-auto-workflow--get-backend-performance-stats backend strategy target) :keep-rate))

;; ─── Target Categorization ───

(defun gptel-auto-workflow--categorize-target (target)
  "Categorize TARGET for backend routing.
Return :programming, :tool-calls, :agentic, or :natural-language.
Categories based on module purpose from historical experiment analysis."
  (when target
    (let ((basename (file-name-nondirectory target)))
      (cond
       ;; Natural-language: context, prompts, chat, conversation, text processing
       ((or (string-match-p "context" basename)
            (string-match-p "prompt" basename)
            (string-match-p "chat" basename)
            (string-match-p "conversation" basename)
            (string-match-p "language" basename)
            (string-match-p "text" basename)
            (string-match-p "summarize" basename)
            (string-match-p "stream" basename)
            (member basename '("gptel-ext-context.el" "gptel-ext-context-images.el"
                              "gptel-ext-context-cache.el" "gptel-ext-streaming.el"
                              "gptel-ext-transient.el")))
        :natural-language)
       ;; Programming: code, benchmarks, FSM, tests, reasoning, compilation
       ((or (string-match-p "benchmark" basename)
            (string-match-p "fsm" basename)
            (string-match-p "retry" basename)
            (string-match-p "reasoning" basename)
            (string-match-p "introspection" basename)
            (string-match-p "test" basename)
            (string-match-p "code" basename)
            (string-match-p "compile" basename)
            (string-match-p "\\`gptel-ext-" basename))
        :programming)
       ;; Tool-calls: sandbox, tool execution, bash, grep, glob
       ((or (string-match-p "sandbox" basename)
            (string-match-p "\\`gptel-tools-[^a]" basename)  ; tools-* but not tools-agent*
            (member basename '("gptel-tools-bash.el" "gptel-tools-grep.el"
                              "gptel-tools-glob.el" "gptel-tools-edit.el"
                              "gptel-tools-apply.el" "gptel-tools-preview.el"
                              "gptel-tools-programmatic.el")))
        :tool-calls)
       ;; Agentic: agent orchestration, workflow, evolution, strategy
       ((or (string-match-p "agent" basename)
            (string-match-p "workflow" basename)
            (string-match-p "strategy" basename)
            (string-match-p "evolution" basename))
        :agentic)
       ;; Default: natural-language (conservative, many gptel features are NL)
       (t :natural-language)))))

;; ─── Category-Level Performance Aggregation ───

(defun gptel-auto-workflow--get-category-performance-stats (backend category &optional strategy)
  "Get BACKEND performance stats on CATEGORY targets.
Optionally filter by STRATEGY.
Aggregates across all targets matching CATEGORY.
Returns plist with :kept :total :keep-rate."
  (let ((results (gptel-auto-workflow--parse-all-results))
        (kept 0)
        (total 0))
    (dolist (r results)
      (let ((r-backend (or (plist-get r :backend) "unknown"))
            (r-target (plist-get r :target))
            (r-strategy (plist-get r :strategy))
            (r-decision (plist-get r :decision)))
        (when (and (string= r-backend backend)
                   (eq (gptel-auto-workflow--categorize-target r-target) category)
                   (or (null strategy) (string= r-strategy strategy)))
          (setq total (1+ total))
          (when (equal r-decision "kept")
            (setq kept (1+ kept))))))
    (list :kept kept
          :total total
          :keep-rate (if (> total 0) (/ (float kept) total) nil))))

;; ─── Category Overrides (from 1,204 experiments) ───

(defconst gptel-auto-workflow--category-backend-overrides
  ;; Source: 1,204 experiments analyzed 2026-05-21
  ;; Category where specific backend outperforms MiniMax baseline (20.5%)
  '((:programming     . "DeepSeek")   ; FSM 40%, benchmark-memory 33.3%, tests 25%, retry 25%, introspection 20%
    (:tool-calls      . nil)           ; MiniMax highspeed baseline — CF-Gateway data inconclusive (25% sandbox n=small)
    (:natural-language . "DeepSeek")  ; context, prompts, streaming — NL reasoning
    (:agentic         . nil))          ; MiniMax baseline — no override needed
  "Category→preferred backend mapping.
Programming → DeepSeek (higher keep rate on code/benchmark targets).
Tool-calls → nil (use MiniMax highspeed default).
Natural-language → DeepSeek (strong NL reasoning).
Agentic → nil (use default ontology ordering, MiniMax is baseline).")

;; ─── Fallback Chain Reordering ───

(defun gptel-auto-workflow--reorder-fallbacks-by-ontology (&optional strategy target)
  "Reorder `gptel-auto-workflow-headless-subagent-fallbacks' using ontology data.
Returns new ordered list of (backend . model) cons cells.
STRATEGY and TARGET filter the performance data."
  (let* ((static-fallbacks (if (boundp 'gptel-auto-workflow-headless-subagent-fallbacks)
                               gptel-auto-workflow-headless-subagent-fallbacks
                             '(("MiniMax" . "minimax-m2.7-highspeed")
                               ("moonshot" . "kimi-k2.6")
                               ("DashScope" . "qwen3.6-plus")
                               ("DeepSeek" . "deepseek-v4-flash")
                               ("CF-Gateway" . "@cf/openai/gpt-oss-120b"))))
         (category (when target (gptel-auto-workflow--categorize-target target)))
         (category-override (when category (cdr (assoc category gptel-auto-workflow--category-backend-overrides))))
         (scored nil))
    
    ;; Score each backend from static list
    (dolist (entry static-fallbacks)
      (let* ((backend (car entry))
             (model (cdr entry))
             ;; Use category-level stats if available, otherwise target-level
             (stats (if category
                        (gptel-auto-workflow--get-category-performance-stats backend category strategy)
                      (gptel-auto-workflow--get-backend-performance-stats backend strategy target)))
             (keep-rate (plist-get stats :keep-rate))
             (total (plist-get stats :total))
             (score (if keep-rate
                        (+ (* keep-rate 100)  ; Weighted by keep-rate
                           (if (> total 0) 1 0))
                      -1)))  ; No data = low priority
        (push (list :backend backend :model model :score score :rate keep-rate :total total) scored)))
    
    ;; Apply category override if available
    (when category-override
      (setq scored (mapcar (lambda (s)
                             (if (string= (plist-get s :backend) category-override)
                                 (plist-put s :score 9999.0)  ; Boost to top
                               s))
                           scored))
      (message "[onto-router] CATEGORY OVERRIDE: %s (%s) → %s"
               category target category-override))
    
    ;; Sort by score descending
    (setq scored (sort scored (lambda (a b) (> (plist-get a :score) (plist-get b :score)))))
    
    ;; Check if we have enough data to trust the reordering
    ;; Count total experiments across all backends
    (let ((total-samples (cl-reduce #'+ scored
                                    :key (lambda (s) (or (plist-get s :total) 0))
                                    :initial-value 0)))
      (if (>= total-samples gptel-auto-workflow--ontology-reorder-min-samples)
          (progn
            (message "[onto-router] Reordered %d backends by performance (≥%d samples)"
                     (length scored) total-samples)
            ;; Exploration: 15% chance to swap first two for learning
            (when (and (> (length scored) 1)
                       (< (random 100) (* gptel-auto-workflow--ontology-reorder-exploration-rate 100)))
              (let ((tmp (car scored)))
                (setcar scored (cadr scored))
                (setcar (cdr scored) tmp))
              (message "[onto-router] EXPLORATION: swapped top 2 backends for learning"))
            ;; Return as (backend . model) cons cells
            (mapcar (lambda (s) (cons (plist-get s :backend) (plist-get s :model))) scored))
        ;; Not enough data - return static order
        (progn
          (message "[onto-router] Using static order (%d samples < %d threshold)"
                   total-samples gptel-auto-workflow--ontology-reorder-min-samples)
          static-fallbacks)))))

;; ─── Integration with Existing Fallback System ───

(defun gptel-auto-workflow--apply-ontology-fallback-order (&optional strategy target)
  "Apply ontology-reordered fallback chain to the active system.
Temporarily overrides `gptel-auto-workflow-executor-rate-limit-fallbacks'.
Call this before experiment runs."
  (let ((reordered (gptel-auto-workflow--reorder-fallbacks-by-ontology strategy target)))
    (when (and reordered (boundp 'gptel-auto-workflow-executor-rate-limit-fallbacks))
      (setq gptel-auto-workflow-executor-rate-limit-fallbacks reordered)
      (message "[onto-router] Applied ontology-ordered fallback chain: %s"
               (mapconcat (lambda (e) (format "%s/%s" (car e) (cdr e))) reordered " → ")))))

;; ─── Reset to Static Order ───

(defun gptel-auto-workflow--reset-fallback-order ()
  "Reset fallback chain to static order from headless config."
  (when (boundp 'gptel-auto-workflow-headless-subagent-fallbacks)
    (setq gptel-auto-workflow-executor-rate-limit-fallbacks
          gptel-auto-workflow-headless-subagent-fallbacks)
    (message "[onto-router] Reset to static fallback order")))

;; ─── Semantic Similarity Target Discovery ───

(defun gptel-auto-workflow--semantic-target-suggestions (&optional max-suggestions min-score)
  "Suggest experiment targets based on semantic similarity to kept targets.
Queries git-embed for files similar to recently kept experiment targets.
Returns list of target file paths (strings) or nil.
MAX-SUGGESTIONS limits results (default 5).
MIN-SCORE is similarity threshold (default 0.60)."
  (let ((suggestions nil)
        (count 0)
        (max (or max-suggestions 5))
        (threshold (or min-score 0.60)))
    (when (fboundp 'gptel-auto-workflow--semantic-similarity-edges)
      (let ((edges (gptel-auto-workflow--semantic-similarity-edges threshold)))
        (dolist (edge edges)
          (when (< count max)
            (let ((target (plist-get edge :target)))
              (when (and target
                         (not (member target suggestions))
                         (file-exists-p target))
                (push target suggestions)
                (setq count (1+ count))))))
        (nreverse suggestions)))))

(defun gptel-auto-workflow--semantic-targets-for-category (category &optional max-suggestions)
  "Suggest targets in CATEGORY based on semantic similarity.
Returns list of target paths that are semantically similar to kept targets
AND match CATEGORY.
MAX-SUGGESTIONS limits results (default 5)."
  (let ((suggestions (gptel-auto-workflow--semantic-target-suggestions max-suggestions))
        (filtered nil))
    (dolist (target suggestions)
      (when (eq (gptel-auto-workflow--categorize-target target) category)
        (push target filtered)))
    (nreverse filtered)))

;; ─── Advice Integration ───

(defun gptel-auto-workflow--ontology-fallback-advice (orig-fun &rest args)
  "Advice around experiment runner to apply ontology fallback ordering.
Reorders fallback chain before each experiment based on historical performance."
  (let* ((target (car args))
         (strategy (if (> (length args) 4) (nth 4 args) nil)))
    ;; Apply ontology-ordered fallbacks
    (gptel-auto-workflow--apply-ontology-fallback-order strategy target)
    ;; Run the experiment
    (unwind-protect
        (apply orig-fun args)
      ;; Reset to static order after experiment
      (gptel-auto-workflow--reset-fallback-order))))

;; Enabled: ontology-aware fallback reordering on every experiment
(advice-add 'gptel-auto-experiment-run
            :around #'gptel-auto-workflow--ontology-fallback-advice)

(provide 'gptel-auto-workflow-ontology-router)
;;; gptel-auto-workflow-ontology-router.el ends here
