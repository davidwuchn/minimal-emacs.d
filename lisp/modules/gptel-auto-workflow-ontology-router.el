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

;; ─── Sieve-Based Backend Classification (verbum Phase 5) ───

(defvar gptel-auto-workflow--backend-sieve-types
  '(("DashScope" . single-neuron)          ; Backend name
    ("qwen3.6-plus" . single-neuron)       ; Model name: Qwen3 family
    ("qwen" . single-neuron)               ; Model family
    ("moonshot" . distributed)             ; Backend name
    ("kimi-k2.6" . distributed)            ; Model name
    ("DeepSeek" . distributed)             ; Backend name
    ("deepseek-v4-flash" . distributed)    ; Model name
    ("MiniMax" . distributed)              ; Backend name
    ("minimax-m2.7-highspeed" . distributed) ; Model name
    ("CF-Gateway" . distributed)           ; Backend name
    ("@cf/openai/gpt-oss-120b" . distributed)) ; Model name
  "Sieve-type classification per backend/model (verbum crystal spine discovery).
single-neuron: high compression, deterministic at bottleneck (Qwen3 family).
distributed: lower compression, more redundancy (Mistral, OLMo, etc.).")

(defun gptel-auto-workflow--backend-sieve-type (backend-or-model)
  "Return sieve-type for BACKEND-OR-MODEL: single-neuron or distributed.
Looks up by backend name first, then model name.
Based on verbum crystal spine research (sessions 109-112)."
  (or (cdr (assoc backend-or-model gptel-auto-workflow--backend-sieve-types))
      ;; Try to match partial model name (e.g., "qwen" in "qwen3.6-plus")
      (cl-some (lambda (entry)
                 (when (string-match-p (car entry) backend-or-model)
                   (cdr entry)))
               gptel-auto-workflow--backend-sieve-types)
      'distributed))  ; Default to distributed for unknown backends

(defun gptel-auto-workflow--target-deterministic-p (target)
  "Return t if TARGET is a deterministic task (suitable for single-neuron backends).
Deterministic tasks: rule validation, type checking, test execution, λ parsing."
  (when target
    (let ((basename (file-name-nondirectory target)))
      (or
       ;; Validation, checking, testing = deterministic
       (string-match-p "validat" basename)
       (string-match-p "test" basename)
       (string-match-p "check" basename)
       (string-match-p "verify" basename)
       ;; Type system = deterministic
       (string-match-p "type" basename)
       ;; Rule-based = deterministic
       (string-match-p "rule" basename)
       ;; Math kernel = deterministic
       (string-match-p "kernel" basename)
       ;; Benchmark = deterministic measurement
       (string-match-p "benchmark" basename)
       ;; FSM = deterministic state machine
       (string-match-p "fsm" basename)))))

(defun gptel-auto-workflow--apply-sieve-routing (scored target)
  "Apply sieve-based routing to SCORED backends for TARGET.
Boosts single-neuron backends for deterministic tasks.
Boosts distributed backends for creative/exploratory tasks.
Returns modified scored list."
  (when target
    (let ((is-deterministic (gptel-auto-workflow--target-deterministic-p target))
          (result nil))
      (dolist (entry scored)
        (let* ((backend (plist-get entry :backend))
               (model (plist-get entry :model))
               ;; Check both backend name and model name for sieve type
               (sieve-type-backend (gptel-auto-workflow--backend-sieve-type backend))
               (sieve-type-model (when model (gptel-auto-workflow--backend-sieve-type model)))
               (sieve-type (if (eq sieve-type-backend 'single-neuron) 'single-neuron
                            (if (eq sieve-type-model 'single-neuron) 'single-neuron
                              (or sieve-type-backend 'distributed))))
               (score (plist-get entry :score))
               ;; Boost matching backends by 10 points
               (boost (if (and is-deterministic (eq sieve-type 'single-neuron))
                          10.0
                        (if (and (not is-deterministic) (eq sieve-type 'distributed))
                            10.0
                          0.0)))
               (new-score (+ score boost)))
          (when (> boost 0)
            (message "[sieve] %s/%s %s for %s task (+%.0f)"
                     backend model
                     (if is-deterministic "boosted" "preferred")
                     (if is-deterministic "deterministic" "creative")
                     boost))
          (push (plist-put entry :score new-score) result)))
      (nreverse result))))

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
    
    ;; Health ladder: filter probation/dead backends, apply weight reduction
    (let ((filtered nil))
      (dolist (entry static-fallbacks)
        (let* ((backend (car entry))
               (level (gptel-auto-workflow--backend-health-level backend))
               (override (and category-override (string= backend category-override))))
          (cond
           ((>= level 3)
            (if override
                (push entry filtered)  ; category override bypasses probation
              (message "[verbum] ⚠ SKIPPING %s backend %s (level=%d)"
                       (gptel-auto-workflow--backend-health-label backend) backend level)))
           (t (push entry filtered)))))
      (setq static-fallbacks (nreverse filtered)))
    
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
    
    ;; Apply ternary decisions (verbum Phase 1): reject backends below baseline
    (when baseline
      (setq scored (gptel-auto-workflow--apply-ternary-routing scored baseline))
      ;; Log ternary decisions for observability
      (dolist (s scored)
        (let ((ternary (plist-get s :ternary)))
          (when (= ternary -1)
            (message "[ternary] REJECTED %s (rate=%.1f%% < baseline=%.1f%%)"
                     (plist-get s :backend)
                     (* (or (plist-get s :rate) 0) 100)
                     (* baseline 100))))))
    
    ;; Apply sieve-based routing (verbum Phase 5): boost matching backends
    (when target
      (setq scored (gptel-auto-workflow--apply-sieve-routing scored target)))
    
    ;; Apply holographic consensus boost (verbum Phase 8): boost backends
    ;; that perform well on the consensus KIBC axis for this target
    (when target
      (setq scored (gptel-auto-workflow--apply-holographic-boost scored target)))
    
    ;; Apply lambda verification penalty (verbum Phase 12): penalize
    ;; degraded backends to avoid routing to backends without lambda compiler
    (setq scored (gptel-auto-workflow--apply-verification-penalty scored))
    
    ;; Sort by score descending, but ternary -1 always at bottom
    (setq scored (sort scored
                       (lambda (a b)
                         (let ((ta (or (plist-get a :ternary) 0))
                               (tb (or (plist-get b :ternary) 0)))
                           (if (/= ta tb)
                               (> ta tb)  ; +1 > 0 > -1
                             (> (plist-get a :score) (plist-get b :score)))))))
    
    ;; Log rich routing decision for observability
    (when (> (length scored) 1)
      (let ((top (car scored))
            (second (cadr scored)))
        (message "[onto-router] ROUTE %s: %s (Δ=%.2f r=%.1f%% ↑=%.2f conf=%.1f tern=%s λ=%s) > %s (Δ=%.2f r=%.1f%% ↑=%.2f conf=%.1f tern=%s λ=%s)"
                 (or category "global")
                 (plist-get top :backend)
                 (plist-get top :delta)
                 (* (or (plist-get top :rate) 0) 100)
                 (plist-get top :trend)
                 (plist-get top :confidence)
                 (pcase (plist-get top :ternary) (+1 "ACCEPT") (0 "DEFER") (-1 "REJECT"))
                 (pcase (gptel-auto-workflow--backend-lambda-trend (plist-get top :backend)) (-1 "↓") (1 "↑") (_ "→"))
                 (plist-get second :backend)
                 (plist-get second :delta)
                 (* (or (plist-get second :rate) 0) 100)
                 (plist-get second :trend)
                 (plist-get second :confidence)
                 (pcase (plist-get second :ternary) (+1 "ACCEPT") (0 "DEFER") (-1 "REJECT"))
                 (pcase (gptel-auto-workflow--backend-lambda-trend (plist-get second :backend)) (-1 "↓") (1 "↑") (_ "→")))))
    
    ;; Check if we have enough data to trust the reordering
    (let ((total-samples (cl-reduce #'+ scored
                                     :key (lambda (s) (or (plist-get s :total) 0))
                                     :initial-value 0)))
      (if (>= total-samples gptel-auto-workflow--ontology-reorder-min-samples)
          (progn
            (message "[onto-router] Reordered %d backends by performance (≥%d samples)"
                     (length scored) total-samples)
            ;; Exploration: 15% chance to swap first two for learning
            ;; Skip exploration if either top backend is rejected (ternary -1)
            (when (and (> (length scored) 1)
                       (/= (or (plist-get (car scored) :ternary) 0) -1)
                       (/= (or (plist-get (cadr scored) :ternary) 0) -1)
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
                            (string= (plist-get e :source) (plist-get e :target))
                            ;; Filter non-code paths when they look like real paths
                            (and (string-match-p "/" (plist-get e :target))
                                 (not (string-match-p "\\`lisp/modules/.*\\.el\\'" (plist-get e :target))))))
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
        (if (file-executable-p git-embed-bin)
            ;; Primary: git-embed vector similarity (nomic-embed-text-v1.5)
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
                (error nil)))
          ;; Fallback: git co-commit Jaccard similarity (no embedding model needed)
          (message "[semantic] git-embed not available — using co-commit fallback")
          (let ((fallback-threshold (max 0.10 (/ threshold 3.0))))  ; co-commit scores are lower
            (condition-case nil
                (let ((co-occur (make-hash-table :test 'equal))
                      (file-counts (make-hash-table :test 'equal))
                      (source-set (make-hash-table :test 'equal)))
                ;; Mark kept targets as sources for edge filtering
                (dolist (s kept-targets) (puthash s t source-set))
                (with-temp-buffer
                  (let ((default-directory root))
                    (call-process "git" nil t nil
                                  "log" "--name-only" "--pretty=format:"
                                  "--diff-filter=AM" "-n" "200"))
                  (goto-char (point-min))
                  (let ((commit-files nil))
                    (while (not (eobp))
                      (let ((line (string-trim
                                   (buffer-substring (point) (line-end-position)))))
                        (forward-line 1)
                        (if (string-empty-p line)
                            (progn
                              (when commit-files
                                (dolist (a commit-files)
                                  (cl-incf (gethash a file-counts 0))
                                  (dolist (b commit-files)
                                    (unless (string= a b)
                                      (let* ((key (if (string< a b) (cons a b) (cons b a)))
                                             (prev (gethash key co-occur 0)))
                                        (puthash key (1+ prev) co-occur))))))
                              (setq commit-files nil))
                          (when (string-match-p "\\`lisp/modules/.*\\.el\\'" line)
                            (push line commit-files)))))))
                (maphash
                 (lambda (key co-count)
                   (let* ((a (car key)) (b (cdr key))
                          (a-total (gethash a file-counts 0))
                          (b-total (gethash b file-counts 0))
                          (union-size (+ a-total b-total (- co-count)))
                          (score (if (> union-size 0)
                                     (/ (float co-count) union-size)
                                   0.0)))
                     (when (and (>= score fallback-threshold)
                               (or (gethash a source-set)
                                   (gethash b source-set)))
                       (push (list :source a :target b :score score) edges))))
                 co-occur))
             (error (message "[semantic] Co-commit fallback failed — returning nil"))))))
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
         (strategy nil))
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

;; ─── Verbum Integration: Lambda Verification ───

(defvar gptel-auto-workflow--lambda-gate-prompt
  "Convert the following prose to a lambda expression.\n\nProse: A function that takes a number and returns its square.\n\nLambda:"
  "Gate prompt to test if backend exhibits lambda compiler.
Based on verbum research: P(λ)=90.7% indicates compiler present.")

(defvar gptel-auto-workflow--backend-lambda-health-cache nil
  "Cache of backend lambda verification results.
Format: ((backend . timestamp) . status) where status is :healthy/:degraded/:unknown.")

(defun gptel-auto-workflow--verify-backend-lambda (backend)
  "Check if BACKEND exhibits lambda compiler (verbum Phase 2).
Returns :healthy, :degraded, or :unknown.
Caches results for 1 hour to avoid repeated API calls.
Uses fallback chain if BACKEND is nil (verifies all backends)."
  (if (null backend)
      ;; Verify all backends in fallback chain
      (gptel-auto-workflow--verify-all-backends-lambda)
    ;; Verify single backend
    (let* ((cache-key (cons backend (format-time-string "%Y-%m-%d-%H")))
           (cached (assoc cache-key gptel-auto-workflow--backend-lambda-health-cache)))
      (if cached
          (cdr cached)
        ;; Attempt verification via fallback chain
        (let ((status (gptel-auto-workflow--verify-backend-lambda-impl backend)))
          (push (cons cache-key status) gptel-auto-workflow--backend-lambda-health-cache)
          (message "[verbum] Lambda health for %s: %s" backend status)
          status)))))

(defun gptel-auto-workflow--verify-all-backends-lambda ()
  "Verify lambda compiler presence for all backends in fallback chain.
Returns plist with :overall status and per-backend results."
  (let ((fallbacks (if (boundp 'gptel-auto-workflow-headless-subagent-fallbacks)
                       gptel-auto-workflow-headless-subagent-fallbacks
                     '(("MiniMax" . "minimax-m2.7-highspeed")
                       ("moonshot" . "kimi-k2.6")
                       ("DashScope" . "qwen3.6-plus")
                       ("DeepSeek" . "deepseek-v4-flash")
                       ("CF-Gateway" . "@cf/openai/gpt-oss-120b"))))
        (results nil)
        (healthy-count 0)
        (degraded-count 0)
        (unknown-count 0))
    (message "[verbum] Verifying lambda compiler on %d backends..." (length fallbacks))
    (dolist (entry fallbacks)
      (let* ((backend (car entry))
             (model (cdr entry))
             (status (gptel-auto-workflow--verify-backend-lambda-impl backend model)))
        (push (cons backend status) results)
        (pcase status
          (:healthy (cl-incf healthy-count))
          (:degraded (cl-incf degraded-count))
          (:unknown (cl-incf unknown-count)))))
    (let ((overall (cond
                    ((> degraded-count 0) :degraded)
                    ((> unknown-count 0) :unknown)
                    (t :healthy))))
      (message "[verbum] Lambda verification complete: %d healthy, %d degraded, %d unknown → %s"
               healthy-count degraded-count unknown-count overall)
      (list :overall overall
            :healthy healthy-count
            :degraded degraded-count
            :unknown unknown-count
            :backends (nreverse results)))))

(defvar gptel-auto-workflow--lambda-verification-results (make-hash-table :test 'equal)
  "Hash table storing async lambda verification results.
Keys are backend names, values are :healthy/:degraded/:unknown.")

(defvar gptel-auto-workflow--lambda-strike-count (make-hash-table :test 'equal)
  "Consecutive degraded lambda checks per backend.
Reset to 0 when :healthy. Quarantine at >= 3 strikes.")

(defvar gptel-auto-workflow--lambda-strike-count (make-hash-table :test 'equal)
  "Consecutive degraded lambda checks per backend.
Reset to 0 when :healthy.")

(defvar gptel-auto-workflow--lambda-dead-until (make-hash-table :test 'equal)
  "Timestamp when DEAD backends can be retried (exponential backoff).
Key: backend name, value: float-time when retest is allowed.")

(defun gptel-auto-workflow--backend-health-level (backend)
  "Return health level for BACKEND: 0-4.
0=HEALTHY (full trust), 1=WARNING (-15%%), 2=DEGRADED (-35%%),
3=PROBATION (canary only), 4=DEAD (waiting for backoff)."
  (let ((strikes (or (gethash backend gptel-auto-workflow--lambda-strike-count) 0))
        (dead-until (gethash backend gptel-auto-workflow--lambda-dead-until)))
    (cond
     ;; DEAD: waiting for backoff timer
     ((and dead-until (> dead-until (float-time))) 4)
     ;; DEAD timer expired → retest now, treat as PROBATION
     (dead-until 3)
     ;; 5+ strikes → DEAD with exponential backoff
     ((>= strikes 5) 4)
     ;; 3-4 strikes → PROBATION (canary tasks only)
     ((>= strikes 3) 3)
     ;; 2 strikes → DEGRADED (reduced weight)
     ((>= strikes 2) 2)
     ;; 1 strike → WARNING (slight penalty)
     ((>= strikes 1) 1)
     ;; 0 strikes → HEALTHY
     (t 0))))

(defun gptel-auto-workflow--backend-health-weight (backend)
  "Return routing weight multiplier [0.0-1.0] for BACKEND based on health level.
0=1.0, 1=0.85, 2=0.65, 3=0.0 (probation), 4=0.0 (dead)."
  (pcase (gptel-auto-workflow--backend-health-level backend)
    (0 1.0)   ; HEALTHY
    (1 0.85)  ; WARNING
    (2 0.65)  ; DEGRADED
    (_ 0.0))) ; PROBATION or DEAD = no routing

(defun gptel-auto-workflow--backend-health-label (backend)
  "Return human-readable health label for BACKEND."
  (pcase (gptel-auto-workflow--backend-health-level backend)
    (0 "HEALTHY") (1 "WARNING") (2 "DEGRADED") (3 "PROBATION") (_ "DEAD")))

(defun gptel-auto-workflow--backend-quarantined-p (backend)
  "Return t if BACKEND is probation or worse (health level >= 3)."
  (>= (gptel-auto-workflow--backend-health-level backend) 3))

(defun gptel-auto-workflow--ranked-subagent-backends ()
  "Return ordered backend/model alist for subagent routing.
Ranks backends by health-weight × historical-keep-rate, best first.
Health data from lambda verification strikes; keep-rate from ontology.
Falls back to the static headless-subagent-fallbacks if no data available.

Phase 2 P(λ) gating: backends with :degraded lambda verification are
excluded entirely (score 0), not just deprioritized. This implements the
hard gate: if a backend fails the lambda compiler check, it's not used."
  (let ((scored nil)
        ;; Use the live fallback chain as default-models so any ontology
        ;; reordering (applied to executor-rate-limit-fallbacks by
        ;; reorder-fallbacks-by-ontology) is picked up here too.
        (default-models (or (and (boundp 'gptel-auto-workflow-executor-rate-limit-fallbacks)
                                gptel-auto-workflow-executor-rate-limit-fallbacks)
                            '(("MiniMax" . "minimax-m2.7-highspeed")
                              ("DeepSeek" . "deepseek-v4-flash")
                              ("DashScope" . "qwen3.6-plus")
                              ("moonshot" . "kimi-k2.6")
                              ("CF-Gateway" . "@cf/openai/gpt-oss-120b")))))
    (dolist (entry default-models)
      (let* ((backend (car entry))
             (model (cdr entry))
             ;; P(λ) gate: hard-exclude backends that fail lambda verification
             (lambda-status (and (boundp 'gptel-auto-workflow--lambda-verification-results)
                                 (gethash backend gptel-auto-workflow--lambda-verification-results)))
             (lambda-degraded (eq lambda-status :degraded))
             (health (if (fboundp 'gptel-auto-workflow--backend-health-weight)
                         (gptel-auto-workflow--backend-health-weight backend)
                       1.0))
             ;; Bayesian-smoothed keep-rate: backends with < 3 experiments
             ;; get the default 0.2 floor to avoid cold-start bias from
             ;; a single discarded experiment tanking their rank.
             (keep-rate (if (fboundp 'gptel-auto-workflow--get-backend-performance-stats)
                             (let* ((stats (gptel-auto-workflow--get-backend-performance-stats backend))
                                    (raw (plist-get stats :keep-rate))
                                    (total (plist-get stats :total)))
                               (if (or (null raw) (< total 3)) 0.2 raw))
                           0.2))
              (quarantined (and (fboundp 'gptel-auto-workflow--backend-quarantined-p)
                                (gptel-auto-workflow--backend-quarantined-p backend)))
              (rate-limited (and (boundp 'gptel-auto-workflow--rate-limited-backends)
                                 (member backend gptel-auto-workflow--rate-limited-backends)))
              (score (cond
                      (lambda-degraded -1.0)   ; P(λ) gate: hard exclude
                      (quarantined -1.0)       ; health gate: hard exclude
                      (rate-limited 0.01)      ; demoted but still available as last resort
                      (t (* health keep-rate)))))
        (when (>= score 0.0)
          (push (cons (cons backend model) score) scored))))
    (if scored
        ;; nreverse: push reverses, restore original order so stable sort
        ;; preserves the default-models order (DashScope first) as tiebreaker.
        (mapcar #'car (sort (nreverse scored) (lambda (a b) (> (cdr a) (cdr b)))))
      default-models)))

(defvar gptel-auto-workflow--conflicted-targets nil
  "Alist of (target . ratio) for targets with <50%% backend agreement.
Populated by Phase 6 consistency check. Targets are deferred until
next cycle to let backends stabilize.")

(defun gptel-auto-workflow--target-conflicted-p (target)
  "Return non-nil if TARGET has <50%% backend agreement (deferred)."
  (cdr (assoc target gptel-auto-workflow--conflicted-targets)))

(defun gptel-auto-workflow--record-lambda-strike (backend status)
  "Record lambda verification STATUS for BACKEND with progressive health ladder.
HEALTHY → resets strikes, clears dead timer.
DEGRADED → increments strikes, triggers actions at each level:
  1=WARNING log, 2=DEGRADED log, 3=PROBATION canary, 5=DEAD backoff."
  (let ((count (or (gethash backend gptel-auto-workflow--lambda-strike-count) 0))
        (old-level (gptel-auto-workflow--backend-health-level backend)))
    (pcase status
      (:healthy
       (puthash backend 0 gptel-auto-workflow--lambda-strike-count)
       (remhash backend gptel-auto-workflow--lambda-dead-until)
       (when (>= old-level 1)
         (message "[verbum] ✓ %s recovered: %s→HEALTHY (strikes cleared)"
                  backend (gptel-auto-workflow--backend-health-label backend))))
      (:degraded
       (let* ((new-count (1+ count))
              (new-level (gptel-auto-workflow--backend-health-level backend)))
         (puthash backend new-count gptel-auto-workflow--lambda-strike-count)
         (pcase new-level
           (1 (message "[verbum] ⚠ WARNING %s: 1 strike (lambda degraded)" backend))
           (2 (message "[verbum] ⚠ DEGRADED %s: 2 strikes (routing weight -35%%)" backend))
           (3 (message "[verbum] ⚠ PROBATION %s: 3 strikes — canary tasks only" backend)
              (when (boundp 'gptel-auto-workflow--evolution-next-cycle-hints)
                (setq gptel-auto-workflow--evolution-next-cycle-hints
                      (plist-put gptel-auto-workflow--evolution-next-cycle-hints
                                 :revalidate-champions t))))
           (4 (message "[verbum] ⚠ PROBATION %s: %d strikes — awaiting recovery" backend new-count))
           (5 (let ((backoff 1800))  ; 30 min
                (puthash backend (+ (float-time) backoff) gptel-auto-workflow--lambda-dead-until)
                (message "[verbum] 💀 DEAD %s: %d strikes — retest in %.0fm (exponential backoff)"
                         backend new-count (/ backoff 60.0)))
              (when (boundp 'gptel-auto-workflow--evolution-next-cycle-hints)
                (setq gptel-auto-workflow--evolution-next-cycle-hints
                      (plist-put gptel-auto-workflow--evolution-next-cycle-hints
                                 :revalidate-champions t))))
           (_ (message "[verbum] 💀 DEAD %s: %d strikes — awaiting retest window" backend new-count)))))
      (_
        (message "[verbum] %s lambda status %s — no strike change" backend status)))))

(defvar gptel-auto-workflow--lambda-trend-history (make-hash-table :test 'equal)
  "Ring buffer of last 5 lambda statuses per backend.
Values are lists of (:healthy/:degraded/:unknown). Used for trend detection.")

(defun gptel-auto-workflow--record-lambda-trend (backend status)
  "Record lambda STATUS for BACKEND in trend history (last 5).
Returns trend score: -1 declining, 0 stable, +1 improving."
  (let* ((history (or (gethash backend gptel-auto-workflow--lambda-trend-history) nil))
         (updated (append (seq-take history 4) (list status))))
    (puthash backend updated gptel-auto-workflow--lambda-trend-history)
    ;; Only compute trend when we have enough history
    (when (>= (length updated) 3)
      (let* ((scores (mapcar (lambda (s) (pcase s (:healthy 1) (:degraded -1) (_ 0))) updated))
             (recent (seq-take (reverse scores) 3))  ;; last 3
             (trend (/ (float (apply #'+ recent)) 3.0)))
        (when (< trend -0.5)
          (message "[verbum] ⚠ TREND ALERT: %s lambda declining (%.1f over last %d checks)"
                   backend trend (length recent)))
        (when (> trend 0.5)
          (message "[verbum] ✓ TREND: %s lambda improving (%.1f)" backend trend))
        trend))))

(defun gptel-auto-workflow--backend-lambda-trend (backend)
  "Return trend score for BACKEND: -1 declining, 0 stable, +1 improving.
Returns nil if insufficient history (<3 checks)."
  (let ((history (gethash backend gptel-auto-workflow--lambda-trend-history)))
    (when (and history (>= (length history) 3))
      (let* ((scores (mapcar (lambda (s) (pcase s (:healthy 1) (:degraded -1) (_ 0))) history))
             (recent (seq-take (reverse scores) 3))
             (trend (/ (float (apply #'+ recent)) 3.0)))
        (if (< trend -0.5) -1
          (if (> trend 0.5) 1
            0))))))

(defun gptel-auto-workflow--call-backend-for-lambda (backend model prompt)
  "Call BACKEND with MODEL for lambda verification via API.
Binds `gptel-backend' and `gptel-model' dynamically around `gptel-request'
so each backend gets tested with its own model, not the active one.
Result is stored in `gptel-auto-workflow--lambda-verification-results'.
Returns t if request was initiated, nil on failure."
  (condition-case err
      (progn
        (message "[verbum] Sending lambda gate prompt to %s/%s..." backend model)
        (let ((gptel-backend (when (fboundp 'gptel-get-backend)
                                (condition-case nil
                                    (gptel-get-backend backend)
                                  (error nil))))
              (gptel-model (intern model)))
          (gptel-request prompt
                         :callback (lambda (response info)
                                     (if (null response)
                                         (progn
                                           (message "[verbum] %s returned no response" backend)
                                           (puthash backend :unknown
                                                    gptel-auto-workflow--lambda-verification-results))
                                       (if (gptel-auto-workflow--response-contains-lambda-p response)
                                           (progn
                                             (message "[verbum] %s lambda compiler confirmed ✓" backend)
                                             (puthash backend :healthy
                                                      gptel-auto-workflow--lambda-verification-results)
                                             (gptel-auto-workflow--record-lambda-strike backend :healthy)
                                             (gptel-auto-workflow--record-lambda-trend backend :healthy))
                                         (progn
                                           (message "[verbum] %s no lambda in response" backend)
                                           (puthash backend :degraded
                                                    gptel-auto-workflow--lambda-verification-results)
                                           (gptel-auto-workflow--record-lambda-strike backend :degraded)
                                           (gptel-auto-workflow--record-lambda-trend backend :degraded)))))))
        t)
    (error
     (message "[verbum] API call failed for %s: %s" backend (error-message-string err))
     nil)))

(defun gptel-auto-workflow--verify-backend-lambda-impl (backend model)
  "Verify lambda compiler for BACKEND/MODEL using real API calls.
Returns :healthy, :degraded, or :unknown.
Initiates async verification if no cached result exists."
  (condition-case err
      (let ((cached (gethash backend gptel-auto-workflow--lambda-verification-results)))
        (if cached
            cached
          ;; No cached result: initiate async verification with proper backend/model
          (progn
            (gptel-auto-workflow--call-backend-for-lambda
             backend model gptel-auto-workflow--lambda-gate-prompt)
            :unknown)))
    (error
     (message "[verbum] Lambda verification failed for %s: %s" backend (error-message-string err))
     :unknown)))

(defun gptel-auto-workflow--response-contains-lambda-p (response)
  "Check if RESPONSE contains lambda expressions.
Looks for λ, lambda, or -> patterns.
TODO: Use proper parser when verbum integration complete."
  (when response
    (or (string-match-p "λ" response)
        (string-match-p "\\\\lambda" response)
        (string-match-p "->" response)
        (string-match-p "lambda" response))))

;; ─── Lambda Verification Report (verbum Phase 12) ───

(defun gptel-auto-workflow--lambda-verification-report ()
  "Generate report of lambda verification results across all backends.
Returns plist with :total :healthy :degraded :unknown :backends."
  (let ((fallbacks (if (boundp 'gptel-auto-workflow-headless-subagent-fallbacks)
                       gptel-auto-workflow-headless-subagent-fallbacks
                     '(("MiniMax" . "minimax-m2.7-highspeed")
                       ("moonshot" . "kimi-k2.6")
                       ("DashScope" . "qwen3.6-plus")
                       ("DeepSeek" . "deepseek-v4-flash")
                       ("CF-Gateway" . "@cf/openai/gpt-oss-120b"))))
        (healthy-count 0)
        (degraded-count 0)
        (unknown-count 0)
        (backend-statuses nil))
    (dolist (entry fallbacks)
      (let* ((backend (car entry))
             (status (or (gethash backend gptel-auto-workflow--lambda-verification-results)
                         :unknown)))
        (push (cons backend status) backend-statuses)
        (pcase status
          (:healthy (cl-incf healthy-count))
          (:degraded (cl-incf degraded-count))
          (:unknown (cl-incf unknown-count)))))
    (message "[verbum] Lambda verification report: %d healthy, %d degraded, %d unknown"
             healthy-count degraded-count unknown-count)
    (list :total (length fallbacks)
          :healthy healthy-count
          :degraded degraded-count
          :unknown unknown-count
          :backends (nreverse backend-statuses))))

(defun gptel-auto-workflow--apply-verification-penalty (scored)
  "Apply lambda verification penalty to SCORED backends.
Degraded backends (-20 points) and unknown backends (-5 points).
Healthy backends get no penalty.
Returns modified scored list."
  (let ((result nil))
    (dolist (entry scored)
      (let* ((backend (plist-get entry :backend))
             (status (or (gethash backend gptel-auto-workflow--lambda-verification-results)
                         :unknown))
             (score (plist-get entry :score))
             (penalty (pcase status
                        (:degraded -20.0)
                        (:unknown -5.0)
                        (:healthy 0.0)
                        (_ -5.0)))
             (new-score (+ score penalty)))
        (when (/= penalty 0)
          (message "[verbum] %s penalized %.0f for lambda status: %s"
                   backend (abs penalty) status))
        (push (plist-put entry :score new-score) result)))
    (nreverse result)))

;; ─── Cross-Backend Consistency Checking (verbum Phase 6) ───

(defun gptel-auto-workflow--cross-backend-consistency (target)
  "Check consistency of KIBC classifications for TARGET across backends.
Returns plist with :consistent t/nil, :agreement-ratio 0.0-1.0, :conflicts list.
When backends disagree on KIBC axis, flags as conflict."
  (let ((results (gptel-auto-workflow--parse-all-results))
        (target-results nil))
    ;; Collect all experiments on this target
    (dolist (r results)
      (when (equal (plist-get r :target) target)
        (push r target-results)))
    ;; Group by backend, get most recent KIBC axis per backend
    (let ((backend-axes nil))
      (dolist (r target-results)
        (let* ((backend (or (plist-get r :backend) "unknown"))
               (axis (or (plist-get r :kibcm-axis) "?"))
               (existing (assoc backend backend-axes)))
          (if existing
              ;; Update if this experiment is newer (later in list = newer)
              (setcdr existing axis)
            (push (cons backend axis) backend-axes))))
      ;; Check consistency
      (if (< (length backend-axes) 2)
          (list :consistent t :agreement-ratio 1.0 :conflicts nil
                :message "Only one backend sampled")
        (let* ((axes (mapcar #'cdr backend-axes))
               (unique-axes (cl-remove-duplicates axes :test #'string=))
               (total (length axes))
               (max-count (if unique-axes
                             (apply #'max (mapcar (lambda (u)
                                                    (cl-count u axes :test #'string=))
                                                unique-axes))
                           0))
               (ratio (/ (float max-count) total))
               (conflicts nil))
          ;; Build conflict list for disagreeing backends
          (when (> (length unique-axes) 1)
            (let ((majority-axis (car (cl-sort unique-axes
                                              (lambda (a b)
                                                (> (cl-count a axes :test #'string=)
                                                   (cl-count b axes :test #'string=)))))))
              (dolist (entry backend-axes)
                (unless (string= (cdr entry) majority-axis)
                  (push (list :backend (car entry)
                             :axis (cdr entry)
                             :expected majority-axis)
                        conflicts)))))
          (when (> (length unique-axes) 1)
            (message "[consistency] %s: %d backends, %d unique axes, %.0f%% agreement"
                     target (length backend-axes) (length unique-axes) (* ratio 100)))
          (list :consistent (= (length unique-axes) 1)
                :agreement-ratio ratio
                :conflicts conflicts
                :backend-count (length backend-axes)
                :unique-axes (length unique-axes)))))))

(defun gptel-auto-workflow--check-all-targets-consistency ()
  "Check cross-backend consistency for all targets with multiple backend samples.
Returns plist with :total :consistent :inconsistent :targets."
  (let ((results (gptel-auto-workflow--parse-all-results))
        (targets-seen (make-hash-table :test 'equal))
        (total 0)
        (consistent 0)
        (inconsistent 0)
        (target-reports nil))
    ;; Find all targets with multiple backends
    (dolist (r results)
      (let ((target (plist-get r :target)))
        (when target
          (puthash target t targets-seen))))
    ;; Check each target
    (maphash (lambda (target _)
               (let ((check (gptel-auto-workflow--cross-backend-consistency target)))
                 (when (>= (plist-get check :backend-count) 2)
                   (cl-incf total)
                   (if (plist-get check :consistent)
                       (cl-incf consistent)
                     (cl-incf inconsistent)
                     (push (list :target target
                                :ratio (plist-get check :agreement-ratio)
                                :conflicts (plist-get check :conflicts))
                           target-reports)))))
             targets-seen)
    (message "[consistency] Checked %d targets: %d consistent, %d inconsistent"
             total consistent inconsistent)
    (list :total total
          :consistent consistent
          :inconsistent inconsistent
          :targets (nreverse target-reports))))

;; ─── Holographic Experiment Memory (verbum Phase 7) ───

(defvar gptel-auto-workflow--holographic-memory nil
  "Holographic memory of experiment consensus.
Format: ((target . axis) . consensus-count) alist.
Tracks how many operations (KIBC axes) agreed on each target.
Inspired by verbum cross-op consensus etching.")

(defun gptel-auto-workflow--record-holographic-experiment (experiment)
  "Record EXPERIMENT into holographic memory.
Increments consensus count for target+axis combination.
EXPERIMENT is a plist with :target, :kibcm-axis, :decision."
  (when (and experiment
             (equal (plist-get experiment :decision) "kept"))
    (let* ((target (plist-get experiment :target))
           (axis (or (plist-get experiment :kibcm-axis) "?"))
           (key (cons target axis))
           (existing (assoc key gptel-auto-workflow--holographic-memory)))
      (if existing
          (setcdr existing (1+ (cdr existing)))
        (push (cons key 1) gptel-auto-workflow--holographic-memory))
      (message "[holographic] Recorded %s → %s (consensus: %d)"
               target axis (or (cdr (assoc key gptel-auto-workflow--holographic-memory)) 0)))))

(defun gptel-auto-workflow--get-holographic-consensus (target)
  "Get holographic consensus for TARGET.
Returns plist with :axis :count :total :confidence.
Higher confidence = more operations agreed."
  (let ((matches (cl-remove-if-not
                  (lambda (entry) (equal (car (car entry)) target))
                  gptel-auto-workflow--holographic-memory))
        (total 0))
    (dolist (m matches)
      (setq total (+ total (cdr m))))
    (if (null matches)
        (list :axis "?" :count 0 :total 0 :confidence 0.0)
      (let* ((best (cl-reduce (lambda (a b)
                                (if (> (cdr a) (cdr b)) a b))
                              matches))
             (axis (cdr (car best)))
             (count (cdr best)))
        (list :axis axis
              :count count
              :total total
              :confidence (if (> total 0) (/ (float count) total) 0.0))))))

(defun gptel-auto-workflow--rebuild-holographic-memory ()
  "Rebuild holographic memory from all historical kept experiments.
Called on startup or after major changes."
  (setq gptel-auto-workflow--holographic-memory nil)
  (let ((results (gptel-auto-workflow--parse-all-results)))
    (dolist (r results)
      (when (equal (plist-get r :decision) "kept")
        (gptel-auto-workflow--record-holographic-experiment r))))
  (message "[holographic] Rebuilt memory: %d target-axis pairs"
           (length gptel-auto-workflow--holographic-memory)))

(defun gptel-auto-workflow--holographic-dead-targets (&optional min-attempts max-keep-rate)
  "Find targets with >=MIN-ATTEMPTS across all backends but <=MAX-KEEP-RATE keep.
Returns list of target names that are dead (no improvement across any backend).
Defaults: 5 attempts, 0%% keep-rate."
  (let ((min-att (or min-attempts 5))
        (max-rate (or max-keep-rate 0.0))
        (results (gptel-auto-workflow--parse-all-results))
        (by-target (make-hash-table :test 'equal))
        (dead nil))
    (dolist (r results)
      (let ((target (plist-get r :target))
            (decision (plist-get r :decision)))
        (when target
          (let ((entry (or (gethash target by-target) (cons 0 0))))
            (setcar entry (1+ (car entry)))
            (when (equal decision "kept")
              (setcdr entry (1+ (cdr entry))))
            (puthash target entry by-target)))))
    (maphash (lambda (target entry)
               (let* ((total (car entry))
                     (kept (cdr entry))
                     (rate (if (> total 0) (/ (float kept) total) 0.0)))
                 (when (and (>= total min-att) (<= rate max-rate))
                   (push (cons target rate) dead))))
             by-target)
    (when dead
      (message "[holographic] %d dead targets detected (≥%d attempts, 0%% keep)"
               (length dead) min-att))
    dead))

;; ─── Holographic Consensus Boost (verbum Phase 8) ───

(defun gptel-auto-workflow--apply-holographic-boost (scored target)
  "Apply holographic consensus boost to SCORED backends for TARGET.
If holographic memory shows high consensus (>0.7) for TARGET's KIBC axis,
boost backends that historically perform well on that axis.
Returns modified scored list (or original if no boost applied)."
  (if (null target)
      scored
    (let* ((consensus (gptel-auto-workflow--get-holographic-consensus target))
           (confidence (plist-get consensus :confidence))
           (axis (plist-get consensus :axis)))
      (if (and (> confidence 0.7) (not (string= axis "?")))
          (let ((result nil))
            (dolist (entry scored)
              (let* ((backend (plist-get entry :backend))
                     ;; Check backend's historical performance on this axis
                     (axis-stats (gptel-auto-workflow--get-axis-performance-stats backend axis))
                     (axis-rate (plist-get axis-stats :keep-rate))
                     (score (plist-get entry :score))
                     ;; Boost if backend performs well on consensus axis
                     (boost (if (and axis-rate (> axis-rate 0.5))
                                (* axis-rate 5.0)  ; Up to +5.0 boost
                              0.0))
                     (new-score (+ score boost)))
                (when (> boost 0)
                  (message "[holographic] %s boosted +%.1f for %s (consensus %s, confidence %.0f%%)"
                           backend boost target axis (* confidence 100)))
                (push (plist-put entry :score new-score) result)))
            (nreverse result))
        ;; No boost: return original scored list
        scored))))

(defun gptel-auto-workflow--get-axis-performance-stats (backend axis)
  "Get BACKEND performance stats for experiments with KIBC AXIS.
Returns plist with :kept :total :keep-rate."
  (let ((results (gptel-auto-workflow--parse-all-results))
        (kept 0)
        (total 0))
    (dolist (r results)
      (let ((r-backend (or (plist-get r :backend) "unknown"))
            (r-axis (or (plist-get r :kibcm-axis) "?"))
            (r-decision (plist-get r :decision)))
        (when (and (string= r-backend backend)
                   (string= r-axis axis))
          (setq total (1+ total))
          (when (equal r-decision "kept")
            (setq kept (1+ kept))))))
    (list :kept kept
          :total total
          :keep-rate (if (> total 0) (/ (float kept) total) nil))))

;; ─── Ternary Decision Boundaries (verbum Phase 1) ───

(defun gptel-auto-workflow--backend-ternary-decision (score baseline)
  "Convert continuous SCORE to ternary decision vs BASELINE.
Returns: -1 (reject, below baseline), 0 (defer, ambiguous), +1 (accept, beats baseline).
Based on verbum ternary weight research: {-1, 0, +1} creates cleaner boundaries."
  (cond
   ;; No data or invalid score → defer
   ((or (null score) (null baseline) (< baseline 0))
    0)
   ;; Significantly below baseline (> 5% gap) → reject
   ((< score (- baseline 0.05))
    -1)
   ;; Significantly above baseline (> 5% gap) → accept
   ((> score (+ baseline 0.05))
    +1)
   ;; Within 5% of baseline → defer (ambiguous)
   (t 0)))

(defun gptel-auto-workflow--apply-ternary-routing (scored baseline)
  "Apply ternary decisions to SCORED backends using BASELINE.
Modifies scored plist with :ternary field (-1, 0, +1).
Backends with -1 are moved to bottom regardless of continuous score.
Category overrides (score = 9999.0) are always ACCEPT regardless of rate."
  (let ((result nil))
    (dolist (entry scored)
      (let* ((rate (or (plist-get entry :rate) 0.0))
             (score (plist-get entry :score))
             ;; Category override: score = 9999.0 means forced top → ACCEPT
             (has-override (and score (>= score 9999.0)))
             (ternary (if has-override
                          +1
                        (gptel-auto-workflow--backend-ternary-decision rate baseline))))
        (push (plist-put entry :ternary ternary) result)
        (message "[ternary] %s: rate=%.2f%% → %s%s"
                 (plist-get entry :backend)
                 (* rate 100)
                 (pcase ternary
                   (-1 "REJECT")
                   (0 "DEFER")
                   (+1 "ACCEPT"))
                 (if has-override " [override]" ""))))
    (nreverse result)))

;; ─── Verbum Experiment Tracker ───

(provide 'gptel-auto-workflow-ontology-router)
;;; gptel-auto-workflow-ontology-router.el ends here
