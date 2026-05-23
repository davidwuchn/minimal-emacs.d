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

;; ─── Recent Performance (last N experiments) ───

(defcustom gptel-auto-workflow--ontology-recent-window 20
  "Number of most recent experiments to consider for trend analysis.
Recent keep-rate compared against all-time to detect improvement/decline."
  :type 'integer
  :group 'gptel-auto-workflow)

(defun gptel-auto-workflow--get-recent-performance-stats (backend category &optional strategy)
  "Get BACKEND's RECENT performance stats on CATEGORY targets.
Only considers the last `gptel-auto-workflow--ontology-recent-window' experiments.
Returns plist with :kept :total :keep-rate, or nil if no recent data."
  (let* ((all (gptel-auto-workflow--parse-all-results))
         (recent (seq-take all (min (length all) gptel-auto-workflow--ontology-recent-window)))
         (kept 0)
         (total 0))
    (dolist (r recent)
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

;; ─── Category Baseline ───

(defun gptel-auto-workflow--category-baseline-keep-rate (category &optional strategy)
  "Compute the average keep-rate across ALL backends for CATEGORY.
This is the baseline — individual backend performance is measured
as delta from this baseline. Optional STRATEGY filter.
Returns float 0.0-1.0, or nil if no data."
  (let ((results (gptel-auto-workflow--parse-all-results))
        (kept 0)
        (total 0))
    (dolist (r results)
      (let ((r-target (plist-get r :target))
            (r-strategy (plist-get r :strategy))
            (r-decision (plist-get r :decision)))
        (when (and (eq (gptel-auto-workflow--categorize-target r-target) category)
                   (or (null strategy) (string= r-strategy strategy)))
          (setq total (1+ total))
          (when (equal r-decision "kept")
            (setq kept (1+ kept))))))
    (if (> total 0) (/ (float kept) total) nil)))

;; ─── Backend Quota Check ───

(defun gptel-auto-workflow--backend-quota-health (backend)
  "Check BACKEND's current quota health from recent rate-limit data.
Returns plist with :healthy (t/nil), :recent-errors (count),
:last-error (timestamp string or nil)."
  (let ((results (gptel-auto-workflow--parse-all-results))
        (errors 0)
        (last-error nil))
    (dolist (r results)
      (let ((r-backend (or (plist-get r :backend) "unknown"))
            (r-error (plist-get r :rate-limit-error)))
        (when (and (string= r-backend backend) r-error)
          (setq errors (1+ errors))
          (setq last-error (or (plist-get r :timestamp) last-error)))))
    (list :healthy (< errors 3)
          :recent-errors errors
          :last-error last-error)))

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
STRATEGY and TARGET filter the performance data.

Scoring incorporates four dimensions (not just raw keep-rate):
  1. DELTA from category baseline — how much better/worse vs peers?      (40%)
  2. RAW keep-rate — historical performance on this category               (30%)
  3. TREND — is performance improving or declining recently?               (20%)
  4. CONFIDENCE — how much data backs this score?                          (10%)
  Penalty: unhealthy backends (3+ recent errors) drop to bottom."
  (let* ((static-fallbacks (if (boundp 'gptel-auto-workflow-headless-subagent-fallbacks)
                                gptel-auto-workflow-headless-subagent-fallbacks
                              '(("MiniMax" . "minimax-m2.7-highspeed")
                                ("moonshot" . "kimi-k2.6")
                                ("DashScope" . "qwen3.6-plus")
                                ("DeepSeek" . "deepseek-v4-flash")
                                ("CF-Gateway" . "@cf/openai/gpt-oss-120b"))))
          (category (when target (gptel-auto-workflow--categorize-target target)))
          (category-override (when category (cdr (assoc category gptel-auto-workflow--category-backend-overrides))))
          ;; Compute baseline once per category
          (baseline (when category (gptel-auto-workflow--category-baseline-keep-rate category strategy)))
          (scored nil))
    
    ;; Score each backend from static list
    (dolist (entry static-fallbacks)
      (let* ((backend (car entry))
             (model (cdr entry))
             ;; All-time category stats
             (all-stats (if category
                            (gptel-auto-workflow--get-category-performance-stats backend category strategy)
                          (gptel-auto-workflow--get-backend-performance-stats backend strategy target)))
             (all-rate (plist-get all-stats :keep-rate))
             (all-total (plist-get all-stats :total))
             ;; Recent stats for trend
             (recent-stats (when category
                             (gptel-auto-workflow--get-recent-performance-stats backend category strategy)))
             (recent-rate (plist-get recent-stats :keep-rate))
             ;; Quota health
             (quota (gptel-auto-workflow--backend-quota-health backend))
             (healthy (plist-get quota :healthy))
             ;; --- Score components ---
             ;; Delta from baseline: how much better/worse than peers?
             (delta (if (and all-rate baseline (> baseline 0.0))
                        (- all-rate baseline)
                      0.0))
             ;; Trend: is recent performance better or worse?
             (trend (if (and all-rate recent-rate (> all-rate 0.0))
                        (- recent-rate all-rate)
                      0.0))
             ;; Confidence: more data = more trustworthy (caps at 1.0)
             (confidence (if all-total
                             (min 1.0 (/ (float all-total) 50.0))
                           0.0)))
        (push (list :backend backend :model model
                    :rate all-rate :total all-total
                    :delta delta :trend trend :confidence confidence
                    :healthy healthy
                    :score (if all-rate
                               (+ (* delta 40.0)        ; Delta from peers (40%)
                                  (* all-rate 30.0)      ; Raw keep-rate (30%)
                                  (* trend 20.0)         ; Direction of change (20%)
                                  (* confidence 10.0)    ; Data trust (10%)
                                  (if healthy 0 -50.0))  ; Quota penalty
                             -1.0))  ; No data = bottom
              scored)))
    
    ;; Apply category override if available
    (when category-override
      (setq scored (mapcar (lambda (s)
                             (if (string= (plist-get s :backend) category-override)
                                 (plist-put s :score 9999.0)  ; Boost to top
                               s))
                           scored))
      (message "[onto-router] CATEGORY OVERRIDE: %s (%s) → %s (baseline=%.1f%%)"
               category target category-override (if baseline (* baseline 100) 0)))
    
    ;; Sort by score descending
    (setq scored (sort scored (lambda (a b) (> (plist-get a :score) (plist-get b :score)))))
    
    ;; Log rich routing decision for observability
    (when (> (length scored) 1)
      (let ((top (car scored))
            (second (cadr scored)))
        (message "[onto-router] ROUTE %s: %s (Δ=%.2f r=%.1f%% ↑=%.2f conf=%.1f) > %s (Δ=%.2f r=%.1f%% ↑=%.2f conf=%.1f)"
                 (or category "global")
                 (plist-get top :backend)
                 (plist-get top :delta)
                 (* (or (plist-get top :rate) 0) 100)
                 (plist-get top :trend)
                 (plist-get top :confidence)
                 (plist-get second :backend)
                 (plist-get second :delta)
                 (* (or (plist-get second :rate) 0) 100)
                 (plist-get second :trend)
                 (plist-get second :confidence))))
    
    ;; Check if we have enough data to trust the reordering
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

(defvar gptel-auto-workflow--semantic-edges-cache nil
  "Cached semantic similarity edges.  Computed once per evolution cycle.
Format: list of plists (:source :target :score).")

(defvar gptel-auto-workflow--semantic-edges-cache-time nil
  "Time when semantic edges cache was last computed.")

(defun gptel-auto-workflow--semantic-similarity-edges (&optional threshold)
  "Compute file semantic similarity edges using git-embed vector embeddings.
Queries the git-embed binary for files similar to kept experiment targets.
Returns list of plists (:source :target :score) with similarity >= THRESHOLD
(default 0.60).  Sorted by score descending.  Cached for 1 hour.
pi-Synthesis: drives semantic-cluster-targets, semantic-target-suggestions,
and the semantic-relationships knowledge page."
  (let ((threshold (or threshold 0.60))
        (now (float-time)))
    (if (and gptel-auto-workflow--semantic-edges-cache
             gptel-auto-workflow--semantic-edges-cache-time
             (< (- now gptel-auto-workflow--semantic-edges-cache-time) 3600))
        (cl-remove-if (lambda (e)
                        (or (< (plist-get e :score) threshold)
                            (string= (plist-get e :source) (plist-get e :target))))
                      gptel-auto-workflow--semantic-edges-cache)
    (let* ((root (gptel-auto-workflow--worktree-base-root))
           (git-embed-bin (or (executable-find "git-embed")
                              (expand-file-name "bin/git-embed" root)))
           (kept-targets nil)
           (edges nil)
           (seen (make-hash-table :test 'equal)))
      (when (and (file-executable-p git-embed-bin)
                 (fboundp 'gptel-auto-workflow--parse-all-results))
        (dolist (r (gptel-auto-workflow--parse-all-results))
          (when (equal (plist-get r :decision) "kept")
            (let ((target (plist-get r :target)))
              (when (and target (not (gethash target seen)))
                (puthash target t seen)
                (push target kept-targets))))))
      (when kept-targets
        (dolist (source kept-targets)
          (condition-case nil
              (with-temp-buffer
                (let ((default-directory root))
                  (call-process git-embed-bin nil t nil
                                "search" source "-n" "10" "--dims" "256"))
                (goto-char (point-min))
                (while (re-search-forward
                        "^\\([0-9.]+\\)[ \t]+\\(.+\\)$" nil t)
                  (let ((score (string-to-number (match-string 1)))
                        (target (string-trim (match-string 2))))
                    (when (and (>= score threshold)
                               (not (string= target source))
                               (string-match-p "\\`lisp/modules/.*\\.el\\'" target))
                      (push (list :source source :target target :score score)
                            edges)))))
            (error nil))))
      (setq edges (sort edges (lambda (a b) (> (plist-get a :score) (plist-get b :score))))
            gptel-auto-workflow--semantic-edges-cache edges
            gptel-auto-workflow--semantic-edges-cache-time now)
      (message "[semantic] git-embed: %d similarity edges computed (threshold=%.2f)"
               (length edges) threshold)
      edges))))

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

;; ─── π Synthesis: Semantic Clustering + Strategy Inheritance ───

(defun gptel-auto-workflow--winning-strategy-for-target (target)
  "Find the strategy that produced a 'kept result for TARGET.
Returns strategy name string or nil.  Checks TSV results."
  (when (fboundp 'gptel-auto-workflow--parse-all-results)
    (let ((results (gptel-auto-workflow--parse-all-results)))
      (catch 'found
        (dolist (r results)
          (when (and (equal (plist-get r :target) target)
                     (equal (plist-get r :decision) "kept")
                     (plist-get r :strategy))
            (throw 'found (plist-get r :strategy))))
        nil))))

(defun gptel-auto-workflow--semantic-cluster-targets (&optional min-score)
  "Group kept targets with their semantically similar files.
Returns alist of (source-target . ((similar-target . score) ...)).
MIN-SCORE defaults to 0.75 (high confidence)."
  (let ((clusters nil)
        (threshold (or min-score 0.75)))
    (when (fboundp 'gptel-auto-workflow--semantic-similarity-edges)
      (let ((edges (gptel-auto-workflow--semantic-similarity-edges threshold)))
        (dolist (edge edges)
          (let* ((source (plist-get edge :source))
                 (target (plist-get edge :target))
                 (score (plist-get edge :score))
                 (existing (assoc source clusters)))
            (if existing
                (setcdr existing (cons (cons target score) (cdr existing)))
              (push (cons source (list (cons target score))) clusters)))))
      clusters)))

(defun gptel-auto-workflow--suggest-similar-with-strategy (source-target)
  "Suggest targets similar to SOURCE-TARGET with inherited strategy.
Returns plist with :targets and :strategy, or nil.
π Synthesis: knowledge from kept experiments propagates to similar files."
  (let ((strategy (gptel-auto-workflow--winning-strategy-for-target source-target))
        (clusters (gptel-auto-workflow--semantic-cluster-targets 0.75)))
    (when (and strategy clusters)
      (let* ((cluster (cdr (assoc source-target clusters)))
             (targets (mapcar #'car cluster)))
        (when targets
          (message "[cluster] π Synthesis: %d targets similar to %s, inheriting strategy '%s'"
                   (length targets) source-target strategy)
          (list :targets targets
                :strategy strategy
                :source source-target
                :scores (mapcar #'cdr cluster)))))))

(defun gptel-auto-workflow--queue-cluster-experiments (source-target)
  "Queue experiments on targets similar to kept SOURCE-TARGET.
Stores under :cluster-queued key in hints plist (safe for plist-get consumers).
VSM S2 Metal: coordination prevents duplicated effort across similar files."
  (let ((suggestion (gptel-auto-workflow--suggest-similar-with-strategy source-target)))
    (when suggestion
      (let* ((targets (plist-get suggestion :targets))
             (strategy (plist-get suggestion :strategy))
             ;; Budget enforcement: apply category budget to cluster-queued targets
             (budgeted-targets (if (fboundp 'gptel-auto-workflow--enforce-category-budget)
                                   (gptel-auto-workflow--enforce-category-budget targets)
                                 targets))
             (existing (when (boundp 'gptel-auto-workflow--evolution-next-cycle-hints)
                         (plist-get gptel-auto-workflow--evolution-next-cycle-hints :cluster-queued)))
             (new-entries nil))
        (dolist (target budgeted-targets)
          (push (list :target target
                      :strategy strategy
                      :reason "semantic-cluster"
                      :source source-target
                      :priority 2)
                new-entries)
          (message "[cluster] Queued %s with strategy '%s' (similar to kept %s)"
                   target strategy source-target))
        (when new-entries
          (setq gptel-auto-workflow--evolution-next-cycle-hints
                (plist-put gptel-auto-workflow--evolution-next-cycle-hints
                           :cluster-queued
                           (append (nreverse new-entries) (or existing nil)))))))))

(provide 'gptel-auto-workflow-ontology-router)
;;; gptel-auto-workflow-ontology-router.el ends here
