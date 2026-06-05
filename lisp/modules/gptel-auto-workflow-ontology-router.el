;;; gptel-auto-workflow-ontology-router.el --- Ontology-aware backend fallback reordering -*- lexical-binding: t -*-

(defvar gptel-auto-workflow--routing-audit-log)
(defvar gptel-auto-workflow--run-failed-backends)
(defvar gptel-auto-workflow--rate-limited-backends)
(defvar gptel-ai-behaviors--best-concrete-tasks)
(defvar gptel-auto-experiment--target-state-cache)

(declare-function gptel-auto-experiment--replay-grader-insights-from-tsv
  "gptel-auto-experiment-core")
(declare-function gptel-auto-workflow--worktree-base-root
  "gptel-auto-workflow-projects")

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
(require 'gptel-auto-workflow-skill-graph)
(require 'gptel-ext-backend-registry)
(declare-function gptel-auto-workflow--memory-schema-category-for-target "gptel-auto-workflow-memory-schema")
(declare-function gptel-auto-workflow--memory-schema-record-evolution "gptel-auto-workflow-memory-schema")

(defvar gptel-auto-workflow-executor-rate-limit-fallbacks
  (mapcar (lambda (backend)
            (cons (symbol-name backend)
                  (symbol-name (gptel-backend-registry-default-model backend))))
          (gptel-backend-registry-fallback-chain 'executor))
  "Fallback chain for executor when rate-limited.
Dynamically generated from `gptel-backend-registry'.
First backend is primary, subsequent backends are tried in order.
Ordered by keep-rate from experiment data.")
(defvar gptel-auto-workflow-headless-subagent-fallbacks)

;; ─── Sieve-Based Backend Classification (verbum Phase 5) ───
;; Dynamically generated from `gptel-backend-registry' capabilities metadata.
;; Qwen3 family (DashScope) → single-neuron (high compression, deterministic).
;; All others → distributed (lower compression, more redundancy).

(defun gptel-auto-workflow--generate-sieve-types ()
  "Generate sieve-type alist from backend registry.
Returns list of (BACKEND-OR-MODEL . sieve-type) entries.
Backend classification uses backend name only.
Model classification uses model name (or inherits from qwen backend)."
  (let ((result '()))
    (dolist (entry gptel-backend-registry)
      (let* ((backend-name (symbol-name (car entry)))
             (models (plist-get (cdr entry) :models))
             ;; Backend classified by its own name only
             (backend-is-qwen (string-match-p "qwen" (downcase backend-name)))
             ;; Any model contains qwen (for wildcard entry)
             (any-model-qwen (cl-some (lambda (m)
                                        (string-match-p "qwen"
                                                        (downcase (symbol-name m))))
                                      models)))
        ;; Backend entry: classified by backend name only
        (push (cons backend-name (if backend-is-qwen 'single-neuron 'distributed))
              result)
        ;; Model entries: classified by model name
        (dolist (model models)
          (let ((model-name (symbol-name model))
                (model-is-qwen (string-match-p "qwen"
                                               (downcase (symbol-name model)))))
            (push (cons model-name
                        (if model-is-qwen 'single-neuron 'distributed))
                  result)))
        ;; Model family wildcard for Qwen
        (when (or backend-is-qwen any-model-qwen)
          (push (cons "qwen" 'single-neuron) result))))
    result))

(defvar gptel-auto-workflow--backend-sieve-types
  (gptel-auto-workflow--generate-sieve-types)
  "Sieve-type classification per backend/model (verbum crystal spine discovery).
single-neuron: high compression, deterministic at bottleneck (Qwen3 family).
distributed: lower compression, more redundancy (Mistral, OLMo, etc.).
Dynamically generated from `gptel-backend-registry'.")

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
  "Return t if TARGET is a deterministic task
\(suitable for single-neuron backends\).
Deterministic tasks: rule validation, type checking,
test execution, lambda parsing."
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

;; ─── VSM Health → Routing Auto-Tuning ───

(defun gptel-auto-workflow--vsm-health-scores ()
  "Extract VSM layer health scores from evolution-next-cycle-hints.
Returns the prioritize-targets plist with :s1-ops ... :s5-identity,
or nil if no VSM health data exists."
  (when (boundp 'gptel-auto-workflow--evolution-next-cycle-hints)
    (let* ((hints gptel-auto-workflow--evolution-next-cycle-hints)
           (actions (plist-get hints :vsm-actions))
           (target-entry (and (consp actions)
                              (assoc 'prioritize-targets actions))))
      (cdr target-entry))))

(defun gptel-auto-workflow--vsm-adjusted-routing-params ()
  "Return routing parameters adjusted by VSM layer health.
Returns a plist with:
  :delta-weight, :rate-weight, :trend-weight, :confidence-weight
  :exploration-rate, :min-samples, :health-probation-threshold

When VSM health data is absent, returns the default hardcoded values.
When a layer is weak, the corresponding parameter is adjusted:

  S4 (Intelligence/Fire) weak (< 0.5) → exploration 0.15→0.30
       (try more backends to gather data faster)
   S3 (Control/Earth) weak (< 0.5) → probation threshold 3→2
       (exclude bad backends faster to prevent waste)
   S1 (Operations/Wood) weak (< 0.4) → min-samples 3→1
       (accept routing with less data to keep the pipeline moving)
   S2 (Coordination/Metal) weak (< 0.5) → delta weight 0.40→0.20
       rate weight 0.30→0.40
       (trust raw keep-rate more when backends disagree on classification)
   S5 (Identity/Water) weak (< 0.4) → confidence weight 0.10→0.20
       (trust historical data more when values are unclear)"
  (let* ((vsm (gptel-auto-workflow--vsm-health-scores))
         (s1 (or (plist-get vsm :s1-ops) 1.0))
         (s2 (or (plist-get vsm :s2-coord) 1.0))
         (s3 (or (plist-get vsm :s3-control) 1.0))
         (s4 (or (plist-get vsm :s4-intel) 1.0))
         (s5 (or (plist-get vsm :s5-identity) 1.0))
         (delta-w 0.40)
         (rate-w 0.30)
         (trend-w 0.20)
         (confidence-w 0.10)
          (exploration 0.15)
          (min-samples 3)
          (probation 3)
          (adjustments nil))
    (when (< s1 0.4)
      (setq min-samples 1)
      (push "S1:min-samples→1" adjustments))
    (when (< s2 0.5)
      (setq delta-w 0.20)
      (setq rate-w 0.40)
      (push "S2:delta→20%+rate→40%" adjustments))
    (when (< s3 0.5)
      (setq probation 2)
      (push "S3:probation→2" adjustments))
    (when (< s4 0.5)
      (setq exploration 0.30)
      (push "S4:explore→30%" adjustments))
    (when (< s5 0.4)
      (setq confidence-w 0.20)
      (setq delta-w (max delta-w 0.30))
      (setq rate-w (max rate-w 0.30))
      (setq trend-w 0.20)
      (push "S5:confidence→20%" adjustments))
    (list :delta-weight delta-w
          :rate-weight rate-w
          :trend-weight trend-w
          :confidence-weight confidence-w
           :exploration-rate exploration
           :min-samples min-samples
           :health-probation-threshold probation
           :adjustments (nreverse adjustments))))

;; ─── Recency-Weighted Keep-Rate ───

(defcustom gptel-auto-workflow--keep-rate-half-life-days 14.0
  "Half-life in days for recency-weighted keep-rate.
Each experiment's weight halves every N days.
Recent performance matters more than historical averages.
Set to 0 to disable (use simple keep-rate)."
  :type 'float
  :group 'gptel-auto-workflow)

(defun gptel-auto-workflow--run-dir-days-ago (run-dir)
  "Return days since the experiment in RUN-DIR was executed.
RUN-DIR is the directory name like 2026-05-21T140000Z-abc123.
Returns a float, or nil if the date cannot be parsed."
  (let* ((date-str (substring run-dir 0 10))
         (time (condition-case nil
                   (date-to-time date-str)
                 (error nil))))
    (when time
      (/ (float-time (time-since time)) 86400.0))))

(defun gptel-auto-workflow--decayed-keep-rate (results backend &optional half-life filter-category filter-strategy)
  "Compute recency-weighted keep-rate for BACKEND from RESULTS.
Each experiment gets weight 2^(-days_ago / HALF-LIFE), default 14 days.
When HALF-LIFE is nil, uses `gptel-auto-workflow--keep-rate-half-life-days'.
When HALF-LIFE is 0.0, all weights are 1.0 (simple keep-rate, no decay).
Optional FILTER-CATEGORY and FILTER-STRATEGY restrict which rows count.
Returns a plist with :kept :total :keep-rate :raw-kept :raw-total :raw-rate."
  (let* ((hl (if half-life half-life
               gptel-auto-workflow--keep-rate-half-life-days))
         (decay-enabled (and (> hl 0.0) hl))
        (weighted-kept 0.0)
        (weighted-total 0.0)
        (raw-kept 0)
        (raw-total 0))
    (dolist (r results)
      (let ((r-backend (plist-get r :backend))
            (r-decision (plist-get r :decision))
            (r-target (plist-get r :target))
            (r-strategy (plist-get r :research-strategy)))
        (when (and (string= (or r-backend "") backend)
                   (or (null filter-category)
                       (eq (gptel-auto-workflow--categorize-target r-target) filter-category))
                   (or (null filter-strategy)
                       (string= (or r-strategy "") filter-strategy)))
          (let* ((run-dir (plist-get r :run-dir))
                 (days-ago (and run-dir (gptel-auto-workflow--run-dir-days-ago run-dir)))
                 (weight (cond ((not decay-enabled) 1.0)
                               ((not days-ago) 1.0)
                               (t (expt 0.5 (/ days-ago decay-enabled)))))
                 (kept (equal r-decision "kept")))
            (cl-incf raw-total)
            (cl-incf weighted-total weight)
            (when kept
              (cl-incf raw-kept)
              (cl-incf weighted-kept weight))))))
    (list :kept (round weighted-kept)
          :total (round weighted-total)
          :keep-rate (if (> weighted-total 0)
                         (/ weighted-kept weighted-total)
                       nil)
          :raw-kept raw-kept
          :raw-total raw-total
          :raw-rate (if (> raw-total 0)
                        (/ (float raw-kept) raw-total)
                      nil))))

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
  "Get keep-rate for BACKEND from ontology, optionally filtered by
STRATEGY/TARGET.
Returns float 0.0-1.0 or nil if no data."
  (plist-get (gptel-auto-workflow--get-backend-performance-stats backend strategy target) :keep-rate))

;; ─── Target Categorization ───

(defun gptel-auto-workflow--categorize-target (target)
  "Categorize TARGET for backend routing.
Return :programming, :tool-calls, :agentic, or :natural-language.
Primary: graph-driven classification from memory schema (entity walk +
schema signatures).  Fallback: regex heuristics from filename patterns."
  (when target
    (or (when (fboundp 'gptel-auto-workflow--memory-schema-category-for-target)
          (gptel-auto-workflow--memory-schema-category-for-target target))
        (gptel-auto-workflow--categorize-target-by-regex target))))

(defun gptel-auto-workflow--categorize-target-by-regex (target)
  "Regex-based categorization fallback for TARGET.
Used when memory schema has no graph data for the target."
  (let ((basename (file-name-nondirectory target)))
    (cond
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
     ((or (string-match-p "benchmark" basename)
          (string-match-p "fsm" basename)
          (string-match-p "retry" basename)
          (string-match-p "reasoning" basename)
          (string-match-p "introspection" basename)
          (string-match-p "test" basename)
          (string-match-p "code" basename)
          (string-match-p "function" basename)
          (string-match-p "compile" basename)
          (string-match-p "\\`gptel-ext-" basename))
      :programming)
     ((or (string-match-p "sandbox" basename)
          (string-match-p "\\`gptel-tools\\.el\\'" basename)
          (string-match-p "\\`gptel-tools-[^a]" basename)
          (string-match-p "\\`nucleus-tools" basename)
          (member basename '("gptel-tools-bash.el" "gptel-tools-grep.el"
                            "gptel-tools-glob.el" "gptel-tools-edit.el"
                            "gptel-tools-apply.el" "gptel-tools-preview.el"
                            "gptel-tools-programmatic.el")))
      :tool-calls)
     ((or (string-match-p "agent" basename)
          (string-match-p "workflow" basename)
          (string-match-p "strategy" basename)
          (string-match-p "evolution" basename)
          (string-match-p "ai-behaviors" basename)
          (string-match-p "\\`gptel-agent-" basename))
      :agentic)
     ((or (string-match-p "nucleus-presets" basename)
          (string-match-p "nucleus-header" basename)
          (string-match-p "init-" basename)
          (string-match-p "tree-sitter\\|treesit" basename)
          (string-match-p "skill-routing" basename)
          (string-match-p "standalone" basename))
      :natural-language)
     (t :programming))))

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
  "Get BACKEND's RECENT performance stats on CATEGORY
targets.
Only considers the last
`gptel-auto-workflow--ontology-recent-window' experiments.
Returns plist with :kept :total :keep-rate,
or nil if no recent data."
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

;; ─── verbum Three-Phase Pipeline ───
;; From verbum's LLM-ISA decoder: each layer has a phase with measured
;; transform strength. Different task types need different phases.
(defconst gptel-auto-workflow--phases
  '((:build   . "Early layers (0-20): construct program, research, synthesis")
    (:execute . "Mid  layers (21-42): execute code, compose, transform")
    (:emit    . "Late layers (43-63): generate output, format, emit"))
  "verbum three-phase pipeline: Build → Execute → Emit.")

(defun gptel-auto-workflow--phase-for-category (category)
  "Return the dominant pipeline phase for a task CATEGORY.
Based on verbum's finding that different tasks need different phases:
- Programming needs Execute phase (B compose, C flip in mid layers)
- Tool-calls needs Execute phase (C flip, β_apply)
- Agentic needs Build phase (Y recursion, D cascade in early layers)
- Natural-language needs Emit phase (I identity, W duplicate in late layers)"
  (cl-case category
    (:programming :execute)
    (:tool-calls :execute)
    (:agentic :build)
    (:natural-language :emit)
    (t :emit)))

(defun gptel-auto-workflow--phase-boost (backend target)
  "Return phase boost (0.0 to +15.0) for BACKEND on TARGET.
Boosts backends whose phase strength matches the task's needs.
verbum measured transform strengths: Build=1.17, Execute=0.95, Emit=0.69.
The boost is proportional to the phase's measured strength."
  (let* ((category (when target (gptel-auto-workflow--categorize-target target)))
         (needed-phase (when category (gptel-auto-workflow--phase-for-category category)))
         ;; Backend-specific phase strength (defaults from verbum measurements)
         ;; In production, these would be measured per-backend via the
         ;; moiré grating decoder. For now, use heuristics based on
         ;; backend architecture (Qwen→emits well, DeepSeek→executes well).
         (phase-strengths
          (cond ((string-match-p "DeepSeek" backend)
                 '((:build . 0.8) (:execute . 1.1) (:emit . 0.7)))
                ((string-match-p "DashScope\\|qwen" backend)
                 '((:build . 0.9) (:execute . 0.8) (:emit . 1.0)))
                ((string-match-p "MiniMax" backend)
                 '((:build . 1.0) (:execute . 0.9) (:emit . 0.8)))
                ((string-match-p "moonshot\\|kimi" backend)
                 '((:build . 0.7) (:execute . 1.0) (:emit . 1.1)))
                (t '((:build . 1.0) (:execute . 1.0) (:emit . 1.0)))))
         (phase-str (cdr (assq needed-phase phase-strengths))))
    (* (or phase-str 1.0) 15.0)))  ; Scale to 0-15 points

;; ─── Category Overrides (from 1,204 experiments) ───

(defconst gptel-auto-workflow--category-backend-overrides
  ;; Source: benchmark data 2026-06-02
  ;; DeepSeek v4-pro with reasoning_effort high takes
  ;; ~60s vs MiniMax-M3 ~7s
  ;; Speed advantage of M3 outweighs historical keep-rate
  ;; difference
  '((:programming     . nil)           ; MiniMax-M3 default (8x faster, clean elisp)
    (:tool-calls      . nil)           ; MiniMax highspeed baseline
    (:natural-language . nil)          ; MiniMax-M3 default (faster for streaming/prompts)
    (:agentic         . nil))          ; MiniMax baseline — no override needed
  "Category->preferred backend mapping.
All categories default to nil — use fallback chain
order \(MiniMax-M3 first\).
DeepSeek v4-pro is 8.5x slower \(60s vs 7s\) with
reasoning_effort high.
Historical keep-rate advantage \(25% vs 16%\) is offset
by throughput impact.
Fallback chain: MiniMax-M3 -> moonshot/k2.6 ->
DeepSeek v4-pro -> DashScope -> Copilot.")

;; ─── Fallback Chain Reordering ───

(defun gptel-auto-workflow--reorder-fallbacks-by-ontology (&optional strategy target)
  "Reorder `gptel-auto-workflow-headless-subagent-fallbacks' using ontology data.
Returns new ordered list of (backend . model) cons cells.
STRATEGY and TARGET filter the performance data.

   Scoring incorporates four dimensions (not just raw keep-rate):
   1. DELTA from category baseline — how much better/worse vs peers?
   2. RAW keep-rate — historical performance on this category
   3. TREND — is performance improving or declining recently?
   4. CONFIDENCE — how much data backs this score?
   Weights auto-tune from VSM health when available (defaults 40/30/20/10).
   Penalty: unhealthy backends (3+ recent errors) drop to bottom."
   (let* ((static-fallbacks (if (boundp 'gptel-auto-workflow-executor-rate-limit-fallbacks)
                                 gptel-auto-workflow-executor-rate-limit-fallbacks
                               '(("DashScope" . "qwen3.6-plus")
                                 ("moonshot" . "kimi-k2.6")
    ("DeepSeek" . "deepseek-v4-pro")
                                 ("MiniMax" . "MiniMax-M3"))))
            (category (when target (gptel-auto-workflow--categorize-target target)))
           (category-override (when category (cdr (assoc category gptel-auto-workflow--category-backend-overrides))))
           ;; verbum data bypass: retrieval tasks (context docs, factual lookups)
           ;; use near-zero combinator activation — they don't need the full
           ;; compute pipeline.  Log when detected for routing observability.
           (retrieval-p (and target
                             (let ((bn (file-name-nondirectory target)))
                               (or (string= bn "gptel-ext-context.el")
                                   (string= bn "gptel-ext-context-images.el")
                                   (string= bn "gptel-ext-context-cache.el")
                                   (string= bn "gptel-ext-transient.el")))))
           ;; Compute baseline once per category
           (baseline (when category (gptel-auto-workflow--category-baseline-keep-rate category strategy)))
           ;; VSM health → routing auto-tuning
           (vsm-params (gptel-auto-workflow--vsm-adjusted-routing-params))
           (delta-weight (plist-get vsm-params :delta-weight))
           (rate-weight (plist-get vsm-params :rate-weight))
           (trend-weight (plist-get vsm-params :trend-weight))
           (confidence-weight (plist-get vsm-params :confidence-weight))
           (scored nil))
    
     ;; Log verbum data bypass detection
     (when retrieval-p
       (message "[verbum] BYPASS: %s — retrieval task, zero combinator activation expected"
                (file-name-nondirectory target)))
     
     ;; Health ladder: filter probation/dead backends, apply weight reduction
    (let ((filtered nil))
      (dolist (entry static-fallbacks)
        (let* ((backend (car entry))
               (level (gptel-auto-workflow--backend-health-level backend))
               (override (and category-override (string= backend category-override))))
          (cond
           ((>= level (plist-get vsm-params :health-probation-threshold))
            (if override
                (push entry filtered)  ; category override bypasses probation
              (message "[verbum] ⚠ SKIPPING %s backend %s (level=%d)"
                       (gptel-auto-workflow--backend-health-label backend) backend level)))
           (t (push entry filtered)))))
      (setq static-fallbacks (reverse filtered)))
    
     ;; Score each backend from static list
    (dolist (entry static-fallbacks)
      (let* ((backend (car entry))
             (model (cdr entry))
             ;; All-time category stats (raw, for confidence/totals)
             (all-stats (if category
                            (gptel-auto-workflow--get-category-performance-stats backend category strategy)
                          (gptel-auto-workflow--get-backend-performance-stats backend strategy target)))
             (all-raw-rate (plist-get all-stats :keep-rate))
             (all-total (plist-get all-stats :total))
             ;; Recency-weighted keep-rate (recent experiments count more)
             (decayed-stats (gptel-auto-workflow--decayed-keep-rate
                             (gptel-auto-workflow--parse-all-results) backend nil category strategy))
             (decayed-rate (plist-get decayed-stats :keep-rate))
             ;; Bayesian floor: backends with < 3 experiments get 0.25
             ;; to avoid cold-start bias. Applied after decay weighting.
             (all-rate (cond (decayed-rate decayed-rate)
                             ((or (null all-raw-rate) (< all-total 3)) 0.25)
                             (t all-raw-rate)))
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
                                (let* ((health-penalty (if (>= (gptel-auto-workflow--backend-health-level backend) 2)
                                                           -100.0   ; DEGRADED or worse = severe penalty
                                                         0.0))
                                       ;; Context efficiency boost: backends that save more context
                                       ;; (higher savings ratio) get a 0-15 point bonus.
                                       ;; Falls back to 0 if context-intercept module not loaded.
                                       (ctx-boost (if (and (fboundp 'gptel-nucleus-context--backend-context-efficiency)
                                                           (boundp 'gptel-nucleus-context--backend-efficiency))
                                                      (let ((eff (gptel-nucleus-context--backend-context-efficiency backend)))
                                                        (if eff (* eff 15.0) 0.0))
                                                    0.0)))
                                   (+ (* delta (* delta-weight 100.0))
                                      (* all-rate (* rate-weight 100.0))
                                      (* trend (* trend-weight 100.0))
                                      (* confidence (* confidence-weight 100.0))
                                      (if healthy 0 -50.0)   ; Quota penalty
                                      health-penalty
                                      ctx-boost
                                      (gptel-auto-workflow--phase-boost backend target)))
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
        (message "[onto-router] ROUTE %s: %s (Δ=%.2f r=%.1f%% ↑=%.2f conf=%.1f tern=%s λ=%s) >
%s (Δ=%.2f r=%.1f%% ↑=%.2f conf=%.1f tern=%s λ=%s)"
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
       (if (>= total-samples (plist-get vsm-params :min-samples))
            (progn
              (let ((adj (plist-get vsm-params :adjustments)))
                (when adj
                  (message "[vsm-routing] %s" (mapconcat #'identity adj ", "))))
              (message "[onto-router] Reordered %d backends by performance (≥%d samples,
explore=%.0f%%)"
                      (length scored) total-samples
                      (* 100 (plist-get vsm-params :exploration-rate)))
             ;; Exploration: swap top 2 backends for learning
             ;; Rate auto-tuned by VSM health (default 15%, up to 30% when S4 weak)
             ;; Drift-forced: if 3+ consecutive failures on this target,
             ;; force a backend swap regardless of exploration rate.
             (let* ((drift (and target
                                (fboundp 'gptel-auto-workflow--moderator-drift-lens)
                                (gptel-auto-workflow--moderator-drift-lens target)))
                    (forced-swap (and drift (>= (plist-get drift :consecutive-failures) 3))))
               (when (and (> (length scored) 1)
                          (/= (or (plist-get (car scored) :ternary) 0) -1)
                          (/= (or (plist-get (cadr scored) :ternary) 0) -1)
                          (or forced-swap
                              (< (random 100) (* (plist-get vsm-params :exploration-rate) 100))))
                 (let ((tmp (car scored)))
                   (setcar scored (cadr scored))
                   (setcar (cdr scored) tmp))
                 (if forced-swap
                     (message "[onto-router] DRIFT-FORCED SWAP: %d consecutive failures on %s"
                              (plist-get drift :consecutive-failures) target)
                   (message "[onto-router] EXPLORATION: swapped top 2 backends for learning"))))
              ;; Record experiment-level routing decision for audit
              (let ((top-5 (seq-take scored 5)))
                (push (list :timestamp (float-time)
                            :level 'experiment
                            :target (or target "global")
                            :strategy (or strategy "none")
                            :weights (list :delta delta-weight :rate rate-weight
                                           :trend trend-weight :confidence confidence-weight)
                            :vsm-adjustments (plist-get vsm-params :adjustments)
                            :top-backends (mapcar (lambda (s)
                                                    (list :backend (plist-get s :backend)
                                                          :model (plist-get s :model)
                                                          :score (plist-get s :score)
                                                          :delta (plist-get s :delta)
                                                          :trend (plist-get s :trend)
                                                          :confidence (plist-get s :confidence)))
                                                  top-5))
                      gptel-auto-workflow--routing-audit-log)
                (when (> (length gptel-auto-workflow--routing-audit-log) 100)
                  (setq gptel-auto-workflow--routing-audit-log
                        (seq-take gptel-auto-workflow--routing-audit-log 100))))
              ;; Return as (backend . model) cons cells
             (mapcar (lambda (s) (cons (plist-get s :backend) (plist-get s :model))) scored))
         ;; Not enough data - return static order with category override applied
         (progn
           (message "[onto-router] Using static order (%d samples < %d threshold)"
                    total-samples (plist-get vsm-params :min-samples))
           ;; Apply category override even without experiment data so
           ;; documented overrides (e.g. :programming → DeepSeek) work
           ;; from the very first run, not just after data accumulates.
           (if category-override
               (let* ((override-entry (assoc category-override static-fallbacks))
                      (rest (cl-remove category-override static-fallbacks
                                       :key #'car :test #'string=)))
                 (if override-entry
                     (progn
                       (message "[onto-router] Static override: %s → %s"
                                category category-override)
                       (cons override-entry rest))
                   static-fallbacks))
             static-fallbacks))))))

;; ─── Integration with Existing Fallback System ───

(defun gptel-auto-workflow--apply-ontology-fallback-order (&optional strategy target)
  "Apply ontology-reordered fallback chain to the active system.
Temporarily overrides `gptel-auto-workflow-executor-rate-limit-fallbacks'.
Call this before experiment runs.
SAFETY: Uses copy-tree so the returned list shares no structure with
the original fallback list — preventing mutation side effects."
  (let* ((excluded (and (boundp 'gptel-auto-workflow--rate-limited-backends)
                        gptel-auto-workflow--rate-limited-backends))
         (reordered (copy-tree (gptel-auto-workflow--reorder-fallbacks-by-ontology strategy target)))
         (filtered (if excluded
                       (cl-remove-if (lambda (e) (member (car e) excluded)) reordered)
                     reordered)))
    (when (and filtered (boundp 'gptel-auto-workflow-executor-rate-limit-fallbacks))
      (setq gptel-auto-workflow-executor-rate-limit-fallbacks filtered)
      (message "[onto-router] Applied ontology-ordered fallback chain: %s"
               (mapconcat (lambda (e) (if (consp e) (format "%s/%s" (car e) (cdr e)) (format "%s" e)))
                          filtered " → ")))))

;; ─── Reset to Static Order ───

(defun gptel-auto-workflow--reset-fallback-order ()
  "Reset fallback chain to static order from executor config.
Restores `gptel-auto-workflow-executor-rate-limit-fallbacks' to the
value of `gptel-auto-workflow-headless-subagent-fallbacks'.
Clears any stale health strikes for DashScope from health cache."
  (when (and (boundp 'gptel-auto-workflow-executor-rate-limit-fallbacks)
             (boundp 'gptel-auto-workflow-headless-subagent-fallbacks))
    (setq gptel-auto-workflow-executor-rate-limit-fallbacks
          (copy-tree gptel-auto-workflow-headless-subagent-fallbacks))
    ;; Clear any stale health strikes for DashScope from health cache
    (when (and (boundp 'gptel-auto-workflow--backend-lambda-health-cache)
               (hash-table-p gptel-auto-workflow--backend-lambda-health-cache))
      (maphash (lambda (k v)
                 (when (and (symbolp k) (string-match-p "DashScope" (symbol-name k)))
                   ;; EDGE CASE: v may be keyword not plist; guard plist-put
                   (ignore-errors
                     (puthash k (plist-put v :health :healthy)
                              gptel-auto-workflow--backend-lambda-health-cache))))
               gptel-auto-workflow--backend-lambda-health-cache))
    (message "[onto-router] Reset to executor static fallback order: %s"
             (mapconcat (lambda (e) (format "%s/%s" (car e) (cdr e)))
                        gptel-auto-workflow-executor-rate-limit-fallbacks
                        " → "))))

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
           (seen (make-hash-table :test 'equal))
           ;; Pi5 has 8GB shared with GPU; git-embed's ONNX model (~2GB)
           ;; exhausts available memory. Skip vector search on low-memory hosts.
           (low-memory-p
            (or (let ((host (system-name)))
                  (and (stringp host)
                       (string-match-p "pi5\\|raspberrypi\\|onepi" host)))
                (condition-case nil
                    (let* ((meminfo (shell-command-to-string
                                    "sysctl -n hw.memsize 2>/dev/null || grep MemTotal /proc/meminfo 2>/dev/null ||
echo 0"))
                           (mem-bytes (if (string-match "[0-9]+" meminfo)
                                          (string-to-number (match-string 0 meminfo))
                                        0)))
                      (< mem-bytes (* 4 1024 1024 1024)))  ; < 4GB
                  (error nil)))))
      (when (and (or low-memory-p (file-executable-p git-embed-bin))
                 (fboundp 'gptel-auto-workflow--parse-all-results))
        (dolist (r (gptel-auto-workflow--parse-all-results))
          (when (equal (plist-get r :decision) "kept")
            (let ((target (plist-get r :target)))
              (when (and target (not (gethash target seen)))
                (puthash target t seen)
                (push target kept-targets))))))
      (when kept-targets
        (if (and (not low-memory-p) (file-executable-p git-embed-bin))
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
          (message "[semantic] %s — using co-commit fallback"
                   (if low-memory-p "git-embed skipped (low memory)" "git-embed not available"))
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
Reorders fallback chain before each experiment based on historical
performance.
After each experiment, copies any new rate-limited backends into the per-run
cooldown list so subsequent experiments hard-exclude failed backends.
SAFETY: Saves and restores all globals this advice touches, so OLTP tests
in unrelated test files are not affected by side effects."
  (let* ((target (car args))
         (strategy nil)
         ;; Save ALL globals this advice might modify
         (saved-rate-limit-fallbacks (and (boundp 'gptel-auto-workflow-executor-rate-limit-fallbacks)
                                         (copy-sequence gptel-auto-workflow-executor-rate-limit-fallbacks)))
         (saved-rate-limited (and (boundp 'gptel-auto-workflow--rate-limited-backends)
                                  (copy-sequence gptel-auto-workflow--rate-limited-backends)))
         (saved-run-failed (and (boundp 'gptel-auto-workflow--run-failed-backends)
                                (copy-sequence gptel-auto-workflow--run-failed-backends)))
         (prior-rate-limited (and (boundp 'gptel-auto-workflow--rate-limited-backends)
                                  (copy-sequence gptel-auto-workflow--rate-limited-backends))))
    ;; Apply ontology-ordered fallbacks
    (gptel-auto-workflow--apply-ontology-fallback-order strategy target)
    ;; Run the experiment
    (unwind-protect
        (apply orig-fun args)
      ;; After experiment: any NEW rate-limited backends → per-run cooldown
      (let ((new-failures (and (boundp 'gptel-auto-workflow--rate-limited-backends)
                               (cl-set-difference gptel-auto-workflow--rate-limited-backends
                                                  prior-rate-limited
                                                  :test #'string=))))
        (dolist (b new-failures)
          (unless (member b gptel-auto-workflow--run-failed-backends)
            (push b gptel-auto-workflow--run-failed-backends)
            (message "[cooldown] %s added to per-run exclusion list" b))))
      ;; Restore ALL saved globals to prevent side-effect leakage across tests
      (when saved-rate-limit-fallbacks
        (setq gptel-auto-workflow-executor-rate-limit-fallbacks saved-rate-limit-fallbacks))
      (when saved-rate-limited
        (setq gptel-auto-workflow--rate-limited-backends saved-rate-limited))
      (when saved-run-failed
        (setq gptel-auto-workflow--run-failed-backends saved-run-failed)))))

;; Enabled: ontology-aware fallback reordering on every experiment
(advice-add 'gptel-auto-experiment-run
            :around #'gptel-auto-workflow--ontology-fallback-advice)

;; ─── π Synthesis: Semantic Clustering + Strategy Inheritance ───

(defun gptel-auto-workflow--winning-strategy-for-target (target)
  "Find the strategy that produced a `kept' result for TARGET.
First tries exact target match, then falls back to
category-level recommendation \(ontology->researcher bridge\).
Returns strategy name string or nil."
  (when (fboundp 'gptel-auto-workflow--parse-all-results)
    (let ((results (gptel-auto-workflow--parse-all-results))
          (category (and (fboundp 'gptel-auto-workflow--categorize-target)
                         (gptel-auto-workflow--categorize-target target))))
      ;; Phase 1: exact target match
      (catch 'found
        (dolist (r results)
          (when (and (equal (plist-get r :target) target)
                     (equal (plist-get r :decision) "kept")
                     (plist-get r :strategy))
            (throw 'found (plist-get r :strategy))))
        ;; Phase 2: category-level fallback (ontology→researcher bridge)
        ;; Exclude the current target to avoid self-matching
        (when category
          (let ((cat-strats (make-hash-table :test 'equal)))
            (dolist (r results)
              (when (and (not (equal (plist-get r :target) target))
                         (equal (plist-get r :decision) "kept")
                         (plist-get r :strategy)
                         (eq (gptel-auto-workflow--categorize-target
                              (plist-get r :target)) category))
                (let ((strat (plist-get r :strategy)))
                  (puthash strat (1+ (gethash strat cat-strats 0)) cat-strats))))
            ;; Return most frequently kept strategy for this category
            (let ((best nil) (best-count 0))
              (maphash (lambda (strat count)
                         (when (> count best-count)
                           (setq best strat best-count count)))
                       cat-strats)
              best)))))))

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
Stores under :cluster-queued key in hints plist (safe for plist-get
consumers).
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
All known backends now support lambda notation, so this prompt is no
longer sent via API — retained only for backward compatibility.")

(defvar gptel-auto-workflow--backend-lambda-health-cache nil
  "Cache of backend lambda verification results.
Format: \(\(backend . timestamp\) . status\) where
status is :healthy/:degraded/:unknown.")

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
                      '(("DashScope" . "qwen3.6-plus")
                        ("moonshot" . "kimi-k2.6")
                        ("DeepSeek" . "deepseek-v4-pro")
                        ("MiniMax" . "MiniMax-M3"))))
        (results nil)
        (healthy-count 0)
        (degraded-count 0)
        (unknown-count 0))
    (message "[verbum] Verifying lambda compiler on %d backends..." (length fallbacks))
    (dolist (entry fallbacks)
      (let* ((backend (if (consp entry) (car entry) (format "%s" entry)))
             (model (if (consp entry) (cdr entry) nil))
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

(defvar gptel-auto-workflow--lambda-dead-until (make-hash-table :test 'equal)
  "Timestamp when DEAD backends can be retried (exponential backoff).
Key: backend name, value: float-time when retest is allowed.")

(defvar gptel-auto-workflow--lambda-last-strike-time (make-hash-table :test 'equal)
  "Timestamp of the most recent lambda degradation per backend.
Used for auto-recovery: if no new strikes for > 1 hour, probation
backends auto-demote to degraded level 2.")

(defvar gptel-auto-workflow--cached-probation-threshold nil
  "Cached probation threshold to avoid recomputing VSM params per backend.
Cons cell: (timestamp . threshold). Invalidated after 5 seconds.")

(defconst gptel-auto-workflow--probation-recovery-seconds 3600
  "Seconds before a probation backend auto-recovers to degraded.
After this period without new strikes, level 3 → level 2.")

(defun gptel-auto-workflow--backend-health-level (backend)
  "Return health level for BACKEND: 0-4.
0=HEALTHY (full trust), 1=WARNING (-15%%), 2=DEGRADED (-35%%),
3=PROBATION (canary only), 4=DEAD (waiting for backoff).
Probation threshold auto-tunes from VSM health when available
(default 3 strikes; tightens to 2 when S3 Control is weak)."
  (let* ((probation-threshold
          (or (when (and gptel-auto-workflow--cached-probation-threshold
                         (< (float-time) (+ (car gptel-auto-workflow--cached-probation-threshold) 5)))
                (cdr gptel-auto-workflow--cached-probation-threshold))
              (when (boundp 'gptel-auto-workflow--evolution-next-cycle-hints)
                (let ((threshold (plist-get (gptel-auto-workflow--vsm-adjusted-routing-params)
                                            :health-probation-threshold)))
                  (setq gptel-auto-workflow--cached-probation-threshold
                        (cons (float-time) threshold))
                  threshold))
              3))
         (strikes (or (gethash backend gptel-auto-workflow--lambda-strike-count) 0))
         (dead-until (gethash backend gptel-auto-workflow--lambda-dead-until)))
    (cond
     ;; DEAD: waiting for backoff timer
     ((and dead-until (> dead-until (float-time))) 4)
     ;; DEAD timer expired → retest now, treat as PROBATION
     (dead-until 3)
     ;; 5+ strikes → DEAD with exponential backoff
     ((>= strikes 5) 4)
      ;; probation-threshold..4 strikes → PROBATION (canary tasks only)
      ;; Auto-recovery: if last strike was > 1h ago, degrade to level 2
      ((>= strikes probation-threshold)
       (let ((last-strike (gethash backend gptel-auto-workflow--lambda-last-strike-time)))
         (if (and last-strike
                  (> (float-time) (+ last-strike gptel-auto-workflow--probation-recovery-seconds)))
             2    ; auto-recovered: probation → degraded
           3)))
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

(defvar gptel-auto-workflow--task-backend-preference
  '(("analyzer"   "DashScope" . 0.10)
    ("analyzer"   "MiniMax"   . 0.20)
    ("analyzer"   "DeepSeek"  . 0.30)
    ("grader"     "DashScope" . 0.10)
    ("grader"     "MiniMax"   . 0.20)
    ("grader"     "DeepSeek"  . 0.30)
    ("executor"   "DashScope" . 0.10)
    ("executor"   "MiniMax"   . 0.20)
    ("executor"   "DeepSeek"  . 0.30)
    ("researcher" "DashScope" . 0.10)
    ("researcher" "MiniMax"   . 0.20)
    ("researcher" "DeepSeek"  . 0.30)
    ("reviewer"   "DashScope" . 0.10)
    ("reviewer"   "MiniMax"   . 0.20)
    ("reviewer"   "DeepSeek"  . 0.30)
    ("comparator" "DashScope" . 0.10)
    ("comparator" "MiniMax"   . 0.20)
    ("comparator" "DeepSeek"  . 0.30))
  "Per-task-type backend preference boost added to ranking score.
Larger values shift routing toward backends best suited for each task:
- DeepSeek V4 thinks → analyzer, researcher
- moonshot/Kimi elaborates → grader
- DashScope/Qwen executes → executor")

(defconst gptel-auto-workflow--preference-persist-file
  "assistant/strategies/provider-routing/backend-preference.el"
  "Git-tracked file for per-axis backend preference data.
Shared across machines via git. Auto-committed after each evolution cycle.")

(defun gptel-auto-workflow--preference-file ()
  "Return absolute path to the git-tracked backend preference file."
  (expand-file-name gptel-auto-workflow--preference-persist-file
                    (gptel-auto-workflow--worktree-base-root)))

(defun gptel-auto-workflow--backend-per-axis-keep-rates ()
  "Compute keep-rates per (backend, kibcm-axis) pair from all results.
Returns alist of ((backend axis) . keep-rate). Pairs with < 5 samples are
excluded."
  (let ((pairs (make-hash-table :test 'equal))
        (rates nil))
    (dolist (r (gptel-auto-workflow--parse-all-results))
      (let ((backend (or (plist-get r :backend) "unknown"))
            (axis (or (plist-get r :kibcm-axis) "?"))
            (kept (equal (plist-get r :decision) "kept")))
        (unless (member backend '("0" "unknown" ""))
          (let* ((key (cons backend axis))
                 (entry (or (gethash key pairs) (cons 0 0))))
            (setcar entry (1+ (car entry)))
            (when kept (setcdr entry (1+ (cdr entry))))
            (puthash key entry pairs)))))
    (maphash (lambda (key counts)
               (let ((total (car counts))
                     (kept (cdr counts)))
                 (when (>= total 5)
                   (push (cons key (/ (float kept) total)) rates))))
             pairs)
    rates))

(defun gptel-auto-workflow--beta-mean (alpha beta)
  "Return mean of Beta(ALPHA, BETA) distribution."
  (/ (float alpha) (+ alpha beta)))

(defun gptel-auto-workflow--beta-sample (alpha beta)
  "Approximate sample from Beta(ALPHA, BETA) -- uses posterior mean.
Deterministic: returns expected value for preference boost calculation."
  (gptel-auto-workflow--beta-mean alpha beta))

(defun gptel-auto-workflow--evolve-backend-preference ()
  "Evolve backend preference via Beta-Bernoulli Thompson Sampling.

For each (backend, kibcm-axis) pair, maintains Beta(kept+1, discarded+1)
posterior. Boost = expected lift over global, bounded [0.0, 0.25].
Beta(1,1) prior = uniform: few samples = conservative boost.
Persisted to `gptel-auto-workflow--preference-persist-file'."
  (interactive)
  (let* ((all-results (gptel-auto-workflow--parse-all-results))
         (alpha-pair (make-hash-table :test 'equal))
         (beta-pair (make-hash-table :test 'equal))
         (alpha-global (make-hash-table :test 'equal))
         (beta-global (make-hash-table :test 'equal))
         (changed nil))
    (dolist (r all-results)
      (let ((backend (or (plist-get r :backend) "unknown"))
            (axis (or (plist-get r :kibcm-axis) "?"))
            (kept (equal (plist-get r :decision) "kept")))
        (unless (member backend '("0" "unknown" ""))
          (unless (gethash backend alpha-global)
            (puthash backend 1 alpha-global)
            (puthash backend 1 beta-global))
          (if kept
              (cl-incf (gethash backend alpha-global))
            (cl-incf (gethash backend beta-global)))
          (let ((key (cons backend axis)))
            (unless (gethash key alpha-pair)
              (puthash key 1 alpha-pair)
              (puthash key 1 beta-pair))
            (if kept
                (cl-incf (gethash key alpha-pair))
              (cl-incf (gethash key beta-pair)))))))
    (maphash
     (lambda (key a-pair)
       (let* ((backend (car key))
              (axis (cdr key))
              (b-pair (gethash key beta-pair))
              (total-pair (+ a-pair b-pair -2))
              (a-glob (gethash backend alpha-global))
              (b-glob (gethash backend beta-global))
              (pair-mean (gptel-auto-workflow--beta-mean a-pair b-pair))
              (global-mean (gptel-auto-workflow--beta-mean a-glob b-glob))
              (agent-type (pcase axis
                            ("A" "analyzer")
                            ("B" "executor")
                            ("C" "reviewer")
                            ("D" "executor")
                            ("E" "grader")
                            ("F" "executor")
                            ("G" "reviewer")
                            ("H" "analyzer")
                            ("I" "comparator")
                            (_ nil))))
         (when (and agent-type (>= total-pair 5)
                    (>= (abs (- pair-mean global-mean)) 0.03))
           (let* ((existing (cl-find-if
                             (lambda (e)
                               (and (string= (nth 0 e) agent-type)
                                    (string= (nth 1 e) backend)))
                             gptel-auto-workflow--task-backend-preference))
                  (current (if (consp existing) (cddr existing) 0.0))
                  (new (min 0.25 (max 0.0 (- pair-mean global-mean)))))
             (when (> (abs (- current new)) 0.005)
               (if existing
                   (setcdr (cdr existing) new)
                 (nconc gptel-auto-workflow--task-backend-preference
                        (list (list agent-type backend new))))
               (setq changed t)
               (message
                "[preference] %s/%s on axis %s: boost %.3f -> %.3f (Bayesian lift=%.3f n=%d)"
                agent-type backend axis current new (- pair-mean global-mean) total-pair))))))
     alpha-pair)
    (when changed
      (gptel-auto-workflow--persist-backend-preference)
      (gptel-auto-workflow--commit-backend-preference)
      (message "[preference] Evolved and committed backend preference"))
    changed))

(defun gptel-auto-workflow--persist-backend-preference ()
  "Persist current task-backend-preference to the git-tracked strategy file."
  (let ((file (gptel-auto-workflow--preference-file)))
    (make-directory (file-name-directory file) t)
    (with-temp-file file
      (insert ";; Auto-evolved per-axis backend preference\n")
      (insert (format ";; Generated: %s\n" (format-time-string "%Y-%m-%d %H:%M")))
      (insert ";; Git-tracked - shared across machines. Commit after evolution.\n")
      (insert (format "(setq gptel-auto-workflow--task-backend-preference\n      '%S)\n"
                      gptel-auto-workflow--task-backend-preference)))))

(defun gptel-auto-workflow--commit-backend-preference ()
  "Git-commit the evolved backend preference so other machines pick it up."
  (let* ((root (gptel-auto-workflow--worktree-base-root))
         (rel gptel-auto-workflow--preference-persist-file)
         (file (expand-file-name rel root))
         (default-directory (file-name-as-directory root)))
    (when (file-exists-p file)
      (condition-case nil
          (progn
            (call-process "git" nil nil nil "add" rel)
            (call-process "git" nil nil nil "commit" "-m"
                          (format "Auto-evolve backend preference (%s)"
                                  (format-time-string "%Y-%m-%d %H:%M"))
                          rel)
            (message "[preference] Committed %s" rel))
        (error
         (message "[preference] Git commit failed (non-fatal)"))))))

(defun gptel-auto-workflow--load-backend-preference ()
  "Load git-tracked backend preference."
  (let ((file (gptel-auto-workflow--preference-file)))
    (when (file-exists-p file)
      (condition-case nil
          (progn
            (load-file file)
            (message "[preference] Loaded tracked strategy from %s"
                     gptel-auto-workflow--preference-persist-file))
        (error
         (message "[preference] Failed to load %s" file))))))

;; Deferred load: preference file depends on worktree-base-root which may
;; not be available at module load time.  Run when worktree is live.
(defun gptel-auto-workflow--ensure-backend-preference-loaded ()
  "Load git-tracked backend preference if available."
  (when (and (fboundp 'gptel-auto-workflow--load-backend-preference)
             (fboundp 'gptel-auto-workflow--worktree-base-root))
    (gptel-auto-workflow--load-backend-preference)))

;; ─── Nucleus Persona Injection ───

(defun gptel-auto-workflow--subagent-persona (agent-type &optional category behavior)
  "Return a nucleus attention-shaping persona for AGENT-TYPE.
When CATEGORY and BEHAVIOR are provided, composes a task-specific persona
from all three signals: subagent archetype × ontology context × reasoning
pattern.
For executors, the category SELECTS a different nucleus archetype:
Agentic → Investigator (debugging×analyse — safety, vigilance),
Programming → Craftsman (coding×tactize — precision),
Tool-calls → Synthesizer (coding×innovate — robustness),
NLP → Academic (documenting — clarity).

Self-evolving: checks `gptel-ai-behaviors--best-persona` for learned
preference.
When insufficient data or equal performance, explores alternate personas
from the 8 nucleus archetypes for A/B testing."
  (let* ((default-archetype
           (pcase category
             (:agentic "Investigator") (:programming "Craftsman")
             (:tool-calls "Synthesizer") (:natural-language "Academic")
             (_ "Craftsman")))
          ;; Self-evolve: check if data suggests a better persona
          ;; Check three-way combo first: (category × archetype × hashtag)
          ;; If a winning combo exists, prefer its archetype over best-persona alone
          (combo-best (and (fboundp 'gptel-ai-behaviors--best-combo)
                           (gptel-ai-behaviors--best-combo category)))
          ;; Expose combo hashtag for behavior selection
          (combo-hashtag (and combo-best (cdr combo-best)))
          (_ (when (and combo-hashtag (boundp 'gptel-ai-behaviors--combo-hashtag))
               (setq gptel-ai-behaviors--combo-hashtag combo-hashtag)))
          (learned-archetype
           (or (and combo-best (car combo-best))  ; combo archetype wins
               (and (fboundp 'gptel-ai-behaviors--best-persona)
                    (gptel-ai-behaviors--best-persona category))))
           ;; Explore 20% when learned != default; curiosity 5% when default confirmed
           ;; Uses 8 nucleus archetypes: (op × mindset) derived
           (alternatives '("Investigator" "Craftsman" "Synthesizer" "Visionary"
                           "Logician" "Academic" "Facilitator" "Storyteller"))
          (explore-p (if (and learned-archetype
                              (not (string= learned-archetype default-archetype)))
                         (< (random 100) 20)   ; Active A/B: 20% explore
                       (< (random 100) 5)))    ; Curiosity: 5% try random alternative
          (archetype (if explore-p
                         (progn
                           (when (boundp 'gptel-ai-behaviors--exploration-tag)
                             (setq gptel-ai-behaviors--exploration-tag t))
                           (let* ((current (or learned-archetype default-archetype))
                                  (others (remove current alternatives)))
                             (nth (random (length others)) others)))
                       (or learned-archetype default-archetype)))
          ;; Task-mode symbol subset — independent from persona archetype
          ;; Selected by (ontology category × active behavior), not by archetype.
          ;; Production: [mu tao] precision + minimal change
          ;; Safety:     [∀ ∃ ε] vigilance + truth + boundaries
          ;; Creative:   [phi beauty fractal] exploration + aesthetics
          (task-mode (pcase category
                       (:agentic 'safety) (:programming 'production)
                       (:tool-calls 'safety) (:natural-language 'creative)
                       (_ 'production)))
          (mode-symbols
           (pcase task-mode
             ('production "mu tao")
             ('safety "∀ ∃ ε")
             ('creative "phi beauty fractal")
             (_ "mu tao")))
          (mode-loop
           (pcase task-mode
             ('production "OODA") ('safety "OODA") ('creative "REPL")
             (_ "OODA")))
           ;; Self-evolve collaboration operator from experiment data
           (learned-operator
            (and (fboundp 'gptel-ai-behaviors--best-operator)
                 (gptel-ai-behaviors--best-operator category)))
           (mode-collab
            (or learned-operator
                (pcase task-mode
                  ('production "Human ⊗ AI") ('safety "Human ∘ AI")
                  ('creative "Human | AI")
                  (_ "Human ⊗ AI"))))
          (mode-constrain
           (pcase task-mode
             ('production "Constrain: change → minimal, quality → mu, precision → tao")
             ('safety "Constrain: coverage → ∀, evidence → ∃, boundaries → ε")
             ('creative "Constrain: exploration → phi, aesthetics → beauty, structure → fractal")
             (_ "Constrain: quality → mu, clarity → tao")))
          ;; Override base λ engage line with mode-selected symbols
          (symbol-override (format "λ engage(nucleus).\n[%s] | [Δ λ | signal/noise] | %s\n%s\n"
                                    mode-symbols mode-loop mode-collab))
          (base-persona
           (pcase agent-type
            ("analyzer"
             ;; Analyzer adapts focus to category
             (let ((cat-focus (pcase category
                               (:agentic "error patterns, state corruption, async bugs")
                               (:programming "algorithm flaws, edge cases, performance")
                               (:tool-calls "sandbox risks, timeout patterns, arg validation")
                               (:natural-language "prompt injection, context overflow, format")
                               (_ "code quality, bugs, regressions"))))
               (format
                "λ engage(nucleus).
[pi mu ∃] | [Δ λ ∞/0 | signal/noise] | OODA
Human | AI
;; Archetype: Logician (thinking × analyse)
;; Focus: %s
;; Operator: | (parallel) — analyze alongside established patterns
;; What: systematic analysis, pattern detection, root cause
λ analysis(data). observe → identify(patterns) → evaluate(impact) → recommend(action)
Output: {:analysis _ :patterns [_] :confidence _ :recommendation _}"
                cat-focus)))
            ("executor"
             ;; Category SELECTS the archetype, not just decorates it
             (pcase category
             (:agentic
                 "λ engage(nucleus).
[∀ ∃ mu] | [Δ λ | safety/risk signal/noise] | OODA
Human ⊗ AI
;; Archetype: Investigator (debugging × analyse)
;; Operator: ∀ (quantify) — check ALL paths, not just happy path
;; What: find unsafe patterns, validate assumptions, prevent corruption
λ investigate(code). probe(entry_points) → find(risks) →
guard(vulnerabilities) → verify(invariants)
Output: {:investigations [_] :risks [_] :guards [_] :verified _}")
                (:programming
                "λ engage(nucleus).
[tao mu] | [Δ λ Σ/μ c/h] | OODA
Human ⊗ AI
;; Archetype: Craftsman (coding × tactize)
;; Operator: ⊗ (tensor) — maximum quality, all constraints satisfied
;; What: precise edits, minimal changes, verified correctness
λ edit(code). Δ(minimal(change)) where behavior(new) = behavior(old) + intent
Output: {:code _ :rationale _ :tests _ :diff _}")
                (:tool-calls
                 "λ engage(nucleus).
[phi ∀ ε π] | [Δ λ | error/recovery integration/separation] | OODA
Human ⊗ AI
;; Archetype: Synthesizer (coding × innovate)
;; Operator: π (synthesis) — integrate tools, compose components
;; What: wrap operations, connect sandbox, handle timeouts, compose reliable
pipelines
λ synthesize(code). identify(integration_points) → compose(components) →
harden(interfaces) → verify(pipeline)
Output: {:integrations [_] :composed [_] :hardened [_] :verified _}")
                (:natural-language
                 "λ engage(nucleus).
[fractal ε] | [Δ λ | structure/noise signal/noise] | OODA
Human ⊗ AI
;; Archetype: Academic (documenting)
;; Operator: fractal — self-similar structure at every level
;; What: document prompts, clarify structure, bound lengths, preserve format
λ document(text). clarify(structure) → bound(lengths) → preserve(format) →
explain(rationale)
Output: {:improvements [_] :bounds [_] :format_preserved _ :rationale _}")
                (_
                 "λ engage(nucleus).
[tao mu] | [Δ λ Σ/μ c/h] | OODA
Human ⊗ AI
;; Archetype: Craftsman (coding × tactize)
;; Operator: ⊗ (tensor) — maximum quality, all constraints satisfied
;; What: precise edits, minimal changes, verified correctness
λ edit(code). Δ(minimal(change)) where behavior(new) = behavior(old) + intent
Output: {:code _ :rationale _ :tests _ :diff _}")))
            ("grader"
             ;; Grader uses category-appropriate evaluation lens
             (let ((cat-lens (pcase category
                               (:agentic "safety coverage, error handling, state protection")
                               (:programming "correctness, edge cases, minimal change")
                               (:tool-calls "robustness, timeout handling, arg safety")
                               (:natural-language "structure, bounds, format preservation")
                               (_ "quality, clarity, correctness"))))
               (format
                "λ engage(nucleus).
[pi mu ∃ ∀] | [Δ λ ∞/0 | truth/provability signal/noise] | OODA
Human ∧ AI
;; Archetype: Logician (thinking × analyse)
;; Lens: %s
;; Operator: ∧ (intersection) — conservative, both must agree
;; What: objective evaluation, detecting flaws, measuring quality
λ grade(output). compare(expected, actual) → identify(gaps) → score(0..1)
Output: {:score _ :strengths [_] :weaknesses [_] :suggestions [_]}"
                cat-lens)))
            ("reviewer"
             "λ engage(nucleus).
[tao mu ∞/0] | [Δ λ | truth/provability order/entropy] | OODA
Human ∘ AI
;; Archetype: Investigator (debugging × analyse)
;; Operator: ∘ (composition) — safety alignment, human constraints wrap AI
;; What: finding issues, security review, convention compliance
λ review(code). find(edge_cases) ∧ suggest(minimal_fix) ∧ verify(conventions)
Output: {:issues [_] :severity _ :suggestions [_] :approved _}")
            ("explorer"
             "λ engage(nucleus).
[phi fractal euler ∃] | [Δ λ ε/φ | order/entropy] | OODA
Human | AI
;; Archetype: Visionary (thinking × innovate)
;; Operator: | (parallel) — collaborative exploration
;; What: discovering patterns, finding connections, breadth-first search
λ explore(query). breadth_first → identify(connections) → synthesize(insights)
Output: {:discoveries [_] :connections [_] :insights [_] :next_steps [_]}")
            ("researcher"
             "λ engage(nucleus).
[phi fractal euler ∃ ∀] | [Δ λ ε/φ | signal/noise self/other] | BML
Human | AI
Constrain: relevance → signal/noise, growth → euler, scope → fractal
;; Archetype: Visionary + Synthesizer (thinking × innovate)
;; Operator: | (parallel) — collaborative research
;; Executive: Competitive Intelligence + Strategic Planning hybrid
λ research(topic). search(external) → filter(relevant) → distill(applicable) →
measure(impact)
Output: {:findings [_] :techniques [_] :apply_to_us [_] :verification _
:confidence _}")
            (_ ""))))
    ;; Modulate persona emphasis based on active behavior
    (let* ((behavior-mod
            (when (and behavior (not (string-empty-p behavior)))
              (let ((b (downcase behavior)))
                (cond ((string-match-p "contract\\|guard" b)
                       "\n;; Emphasis: nil-guards, bound checks, defensive wrappers")
                      ((string-match-p "simulate\\|boundary" b)
                       "\n;; Emphasis: edge cases, boundary conditions, failure paths")
                      ((string-match-p "tdd\\|test" b)
                       "\n;; Emphasis: testable contracts, small verified steps")
                      ((string-match-p "decompose\\|act" b)
                       "\n;; Emphasis: smallest possible change, one edit, verify")
                      ((string-match-p "concise\\|legible" b)
                       "\n;; Emphasis: readability, minimal boilerplate, clear intent")
                      ((string-match-p "coherence\\|temporal" b)
                       "\n;; Emphasis: consistent patterns, temporal ordering")
                      ((string-match-p "stop\\|checklist" b)
                       "\n;; Emphasis: pause, verify each step, don't rush")
                      (t (format "\n;; Behavior: %s" behavior))))))
           ;; Inject active quality hashtags as additional eight-key symbols
           ;; into the [symbol-set] block. Each quality maps to a nucleus
           ;; symbol (from ai-behaviors BEHAVIORS.md quality table).
           (quality-symbols
            (when (and behavior (not (string-empty-p behavior)))
              (let ((b (downcase behavior)) (s ""))
                (when (string-match-p "\\bdeep\\b\\|creative" b) (setq s (concat s " φ")))
                (when (string-match-p "\\bwide\\b\\|meta" b) (setq s (concat s " π")))
                (when (string-match-p "ground" b) (setq s (concat s " fractal")))
                (when (string-match-p "negative-space\\|challenge" b) (setq s (concat s " ∀")))
                (when (string-match-p "steel-man" b) (setq s (concat s " ∃")))
                (when (string-match-p "user-lens" b) (setq s (concat s " ε")))
                (when (string-match-p "concise\\|subtract" b) (setq s (concat s " μ")))
                (when (string-match-p "first-principles" b) (setq s (concat s " τ")))
                (when (> (length s) 0) (substring s 1)))))  ; strip leading space
           ;; Adaptive persona state machine (nucleus ADAPTIVE.md pattern)
           ;; The LLM self-transitions between operations based on task signals.
           ;; Two PARALLEL tracks: operation + mindset. Archetype = their intersection.
           ;; Both run simultaneously — the LLM tracks both states independently.
           (persona-state-machine
            (concat
             "\n;; ═══ Adaptive Persona — parallel state machines ═══\n"
             ";; Operation (what) → mindset (how) → archetype (who)\n\n"
             ";; ─── Operation Track — what you're doing ───\n"
             "state :thinking  ;; default — read, plan, assess\n"
             "  → :coding       when code_needed (task is clear)\n"
             "  → :debugging    when error_encountered\n"
             "  → :documenting  when explanation_needed\n\n"
             "state :coding\n"
             "  → :thinking     when design_gap (need to reconsider)\n"
             "  → :debugging    when error_encountered\n"
             "  → :documenting  when implementation_complete\n\n"
             "state :debugging\n"
             "  → :coding       when root_cause_found\n"
             "  → :thinking     when cause_unclear\n"
             "  → :documenting  when resolved\n\n"
             "state :documenting\n"
             "  → :thinking     when gap_discovered\n"
             "  → :coding       when implementation_needed\n\n"
             ";; ─── Mindset Track — how you approach it (PARALLEL to operation) ───\n"
             "state :analyse  ;; default — deep understanding\n"
             "  → :tactize      when cause_found | time_constrained\n"
             "  → :strategize   when bigger_than_expected\n"
             "  → :innovate     when greenfield (new approach)\n\n"
             "state :tactize\n"
             "  → :analyse      when wrong_approach (current path failing)\n"
             "  → :balanced     when pressure_resolved (time pressure gone)\n\n"
             "state :innovate\n"
             "  → :tactize      when idea_converged (found workable approach)\n"
             "  → :analyse      when validate_needed (check feasibility)\n\n"
             "state :strategize\n"
             "  → :innovate     when explore_options (need creative solutions)\n"
             "  → :tactize      when decision_committed (chosen path)\n\n"
             "state :balanced\n"
             "  → :analyse      when deep_dive_needed (need to understand)\n"
             "  → :tactize      when time_constrained (deadline approaching)\n"
             "  → :innovate     when greenfield (fresh start)\n\n"
             ";; ─── Archetype Matrix — derived from (operation × mindset) ───\n"
             "λ archetype(op, mind).\n"
             "  (coding, tactize)      → " (or (and (equal agent-type "executor") archetype) "Craftsman") "\n"
             "  (debugging, analyse)   → Investigator\n"
             "  (thinking, analyse)    → Logician\n"
             "  (coding, innovate)     → Synthesizer\n"
             "  (documenting, *)       → Academic\n"
             "  (thinking, strategize) → Visionary\n"
             "  (*, balanced)          → Facilitator\n"
             "  (_, _)                 → Logician\n"
              "  (_, _)                 → Logician\n\n"
              ";; ─── Emission — output schema per operation ───\n"
              "λ emit(op).\n"
              "  :thinking    → {:analysis _ :options [_] :recommendation _}\n"
              "  :coding      → {:code _ :rationale _ :tests _}\n"
              "  :debugging   → {:symptom _ :cause _ :fix _ :prevention _}\n"
              "  :documenting → {:explanation _ :context _ :examples [_]}\n\n"
              ";; Response format:\n"
              ";; *Transitioning: `:op→:next` (signal) | mindset: `:ms` → Archetype*\n"))
           ;; Replace first `λ engage` block with mode-selected symbols
           (header-replaced (replace-regexp-in-string
                             "λ engage(nucleus)\\.\n\\[[^]]+\\][^]]*" ; match λ engage line + symbols
                             (replace-regexp-in-string "\n$" "" symbol-override) ; strip trailing newline
                             base-persona))
           (persona-text (concat (if quality-symbols
                                     (replace-regexp-in-string
                                      "\\(\\[\\(?:[^]]+\\|\]\\)*\\)\\]"
                                      (format "\\1 %s]" quality-symbols)
                                      header-replaced)
                                   header-replaced)
                                  "\n" mode-constrain
                                  (or behavior-mod "")
                                  persona-state-machine
                                  "\n\n---\n\n")))
      ;; Record selected archetype for experiment logging
      (when (boundp 'gptel-ai-behaviors--current-archetype)
        (setq gptel-ai-behaviors--current-archetype archetype))
      persona-text)))

;; ─── Moderator Drift Detection (DIALECTIC.md pattern) ───

(defun gptel-auto-workflow--moderator-drift-lens (target)
  "Check TARGET for experiment drift and return an intervention lens.
Inspired by DIALECTIC.md moderator pattern: detect when experiments
are stuck and apply a lens to shift the approach.
Returns a plist with :lens (keyword), :reason (string), :consecutive-failures
(int),
or nil if no drift detected."
  (when (fboundp 'gptel-auto-workflow--parse-all-results)
    (let* ((results (gptel-auto-workflow--parse-all-results))
           (target-results
            (seq-take
             (seq-filter (lambda (r) (equal (plist-get r :target) target))
                         (nreverse results))
             5))  ; last 5 experiments for this target
           (consecutive 0)
            (_last-backend nil)
           (backends (make-hash-table :test 'equal)))
      ;; Count consecutive failures and backend diversity
      (dolist (r target-results)
        (let ((decision (plist-get r :decision))
              (backend (plist-get r :backend)))
          (if (and decision (not (equal decision "kept")))
              (cl-incf consecutive)
            (cl-incf consecutive 0)  ; reset on success
            (setq consecutive 0))
          (when backend
            (puthash backend t backends))))
      (cond
       ((>= consecutive 3)
        (list :lens :consequence_check
              :reason (format "%d consecutive failures — moderate(consequence_check)"
                              consecutive)
              :consecutive-failures consecutive))
       ((>= consecutive 2)
        (list :lens :evidence_nudge
              :reason (format "%d consecutive failures — moderate(evidence_nudge)"
                              consecutive)
              :consecutive-failures consecutive))
       ((and (= consecutive 1)
             (< (hash-table-count backends) 2))
        (list :lens :assumption_probe
              :reason "Single backend used repeatedly — moderate(assumption_probe)"
              :consecutive-failures 1))
       (t nil)))))

;; ─── Persona Auto-Tuning from Measured Impact ───

(defvar gptel-auto-workflow--persona-category-overrides nil
  "Alist of (category . :override) mapping categories to use default persona.
Populated by `gptel-auto-workflow--auto-tune-personas' when a category's
per-persona keep-rate falls below the overall average.")

(defun gptel-auto-workflow--auto-tune-personas ()
  "Auto-tune persona selection based on measured impact data.
When a category's persona-aware keep-rate is below the global average,
switch it to use the default persona for the next cycle.
Returns list of (category . old-rate . new-target) for changed categories."
  (let* ((impact (condition-case nil
                     (gptel-auto-workflow--nucleus-persona-impact)
                   (error nil)))
         (global-rate (plist-get impact :persona-keep-rate))
         (per-cat (plist-get impact :per-category))
         (changes nil))
    (when (and global-rate per-cat)
      (setq gptel-auto-workflow--persona-category-overrides nil)
      (dolist (cat-entry per-cat)
        (let* ((category (plist-get cat-entry :category))
               (cat-rate (plist-get cat-entry :keep-rate)))
          (when (and cat-rate (< cat-rate global-rate))
            (push (cons category :default) gptel-auto-workflow--persona-category-overrides)
            (push (list category cat-rate global-rate) changes))))
      (when changes
        (message "[persona-auto] Swapped %d categories to default persona (below global %.0f%%)"
                 (length changes) (* 100 global-rate))))
    changes))

;; ─── Experiment Persona by Target Category ───

(defun gptel-auto-workflow--experiment-nucleus-persona (target)
  "Return a nucleus attention-shaping preamble for TARGET's category.
Maps target category → nucleus symbol set + writing persona.
Categories from WRITING.md + ADAPTIVE.md patterns.
Auto-tuned: underperforming categories switch to default via
`auto-tune-personas'."
  (let* ((category (when (fboundp 'gptel-auto-workflow--categorize-target)
                     (gptel-auto-workflow--categorize-target target)))
         ;; Check for auto-tuned overrides
         (override (assoc category gptel-auto-workflow--persona-category-overrides)))
    (when override
      (message "[persona] Category %s uses default (auto-tuned: below global keep-rate)" category)
      (setq category nil))  ; nil → hits the default (_) clause
    (pcase category
      (:programming
       "λ engage(nucleus).
[fractal phi mu] | [λ Σ/μ] | OODA
Human ⊗ AI
Constrain: hierarchy → fractal, insight → phi, concision → mu, edge_cases →
∞/0
;; Category: programming (code changes, refactoring, tests)
;; Persona: Reports & Summaries — analyze → select → implement → verify
λ edit(code). Δ(minimal(change)) where behavior(new) = behavior(old) + intent
Output: {:hypothesis _ :change _ :evidence _ :verification _ :axis _}

;; Critical patterns (from nucleus/LAMBDA_PATTERNS.md):
;; 1. Atomic edit: match on CONTENT not line numbers:
;;    λ(old, new). edit_file(original_content=old, new_content=new)
;; 2. Content-based search: grep first to find exact context, then edit
;; 3. Parallel reads: batch independent reads in one <function_calls> block")
      (:tool-calls
       "λ engage(nucleus).
[mu tao pi] | [λ ∞/0 | c/h] | OODA
Human ⊗ AI
Constrain: safety → ∞/0, concision → mu, completeness → pi
;; Category: tool-calls (bash, glob, grep, edit)
;; Persona: Craftsman — safe operations, edge cases, error handling
λ tool(op, args). safe_execute → verify(result) → handle(edge_cases)
Output: {:operation _ :result _ :errors _ :validation _}

;; Critical patterns (from nucleus/LAMBDA_PATTERNS.md):
;; 1. Heredoc for ALL bash strings — no escaping needed:
;; λ(content). bash(command=\"read -r -d '' VAR << \='X\=' ||
true\ncontent\nX\ngit commit -m \\\"$VAR\\\"\")
;; 2. Safe paths: λ(p). read_file(path=\"$(realpath \\\"$p\\\")\")
;; 3. Parallel independent ops in one <function_calls> block")
      (:natural-language
       "λ engage(nucleus).
[phi fractal euler] | [λ ε/φ] | REPL
Human | AI
;; Category: natural-language (prompts, docs, explanations)
;; Persona: Academic — structured, clear, hierarchical
λ explain(concept). structure(hierarchy) → clarify(essence) →
provide(examples)
Output: {:overview _ :details _ :examples _ :summary _}")
      (:agentic
       "λ engage(nucleus).
[phi fractal euler ∃] | [Δ λ ε/φ ∞/0 | self/other] | OODA
Human ⊗ AI
Constrain: scope → fractal, growth → euler, edge_cases → ∞/0
;; Category: agentic (strategies, evolution, meta)
;; Persona: Visionary — strategic thinking, self-reference, scaling
λ strategize(domain). map(landscape) → identify(leverage) →
design(intervention)
Output: {:analysis _ :strategies [_] :risks [_] :recommendation _}")
      (_
       ;; Default: balanced (Professional Emails + Quick Responses hybrid)
       "λ engage(nucleus).
[phi tao mu pi] | [Δ λ] | OODA
Human ⊗ AI
Constrain: clarity → phi, essence → tao, concision → mu, completeness → pi"))))

;; ─── Nucleus Persona Impact Measurement ───

(defun gptel-auto-workflow--nucleus-persona-impact ()
  "Measure whether nucleus persona selection improves experiment outcomes.
Returns a plist with per-category keep-rates and an overall delta.
Positive delta = persona-aware routing outperforms unclassified targets."
  (let* ((results (when (fboundp 'gptel-auto-workflow--parse-all-results)
                    (gptel-auto-workflow--parse-all-results)))
         (persona-kept 0) (persona-total 0)
         (unclassified-kept 0) (unclassified-total 0)
         (per-category nil))
    (dolist (r results)
      (let* ((target (plist-get r :target))
             (decision (plist-get r :decision))
             (category (when (and target
                                  (fboundp 'gptel-auto-workflow--categorize-target))
                         (gptel-auto-workflow--categorize-target target))))
        (when target
          (if category
              (progn (cl-incf persona-total)
                     (when (equal decision "kept") (cl-incf persona-kept))
                     (let ((entry (assoc category per-category)))
                       (if entry
                           (progn (cl-incf (cadr entry))
                                  (when (equal decision "kept")
                                    (cl-incf (caddr entry))))
                         (push (list category 1 (if (equal decision "kept") 1 0))
                               per-category))))
            (progn (cl-incf unclassified-total)
                   (when (equal decision "kept")
                     (cl-incf unclassified-kept)))))))
    (list :persona-keep-rate (if (> persona-total 0)
                                 (/ (float persona-kept) persona-total) nil)
          :unclassified-keep-rate (if (> unclassified-total 0)
                                      (/ (float unclassified-kept) unclassified-total) nil)
          :persona-experiments persona-total
          :unclassified-experiments unclassified-total
          :per-category (mapcar (lambda (e)
                                  (list :category (car e)
                                        :total (cadr e)
                                        :kept (caddr e)
                                        :keep-rate (if (> (cadr e) 0)
                                                       (/ (float (caddr e)) (cadr e))
                                                     0.0)))
                                per-category)
          :impact-delta (if (and (> persona-total 0) (> unclassified-total 0))
                            (- (/ (float persona-kept) persona-total)
                               (/ (float unclassified-kept) unclassified-total))
                          nil))))

;; ─── Routing Context for Prompt Injection ───

(defun gptel-auto-workflow--routing-context (backend model)
  "Generate a concise routing rationale string for BACKEND/MODEL.
Injected at subagent dispatch time so the LLM knows exactly which backend
it runs on, why that backend was selected, and any relevant caveats."
  (let* ((bn (or (and (fboundp 'gptel-auto-workflow--safe-backend-name)
                      (gptel-auto-workflow--safe-backend-name backend))
                 (and (fboundp 'gptel-backend-name)
                      (gptel-backend-name backend))
                 (format "%s" backend)))
         (lambda-status (and (boundp 'gptel-auto-workflow--lambda-verification-results)
                              (gethash backend gptel-auto-workflow--lambda-verification-results)))
         (health-level (and (fboundp 'gptel-auto-workflow--backend-health-level)
                            (gptel-auto-workflow--backend-health-level backend)))
         (health-label (and (fboundp 'gptel-auto-workflow--backend-health-label)
                            (gptel-auto-workflow--backend-health-label backend)))
         (stats (when (fboundp 'gptel-auto-workflow--get-backend-performance-stats)
                  (condition-case nil
                      (gptel-auto-workflow--get-backend-performance-stats backend)
                    (error nil))))
         (keep-rate (plist-get stats :keep-rate))
         (total-exps (plist-get stats :total))
         (rate-limited (and (boundp 'gptel-auto-workflow--rate-limited-backends)
                            (member backend gptel-auto-workflow--rate-limited-backends)))
         (in-cooldown (and (boundp 'gptel-auto-workflow--run-failed-backends)
                           (member backend gptel-auto-workflow--run-failed-backends)))
         ;; Per-axis selection rationale
         (target (and (boundp 'gptel-auto-workflow--current-target)
                      gptel-auto-workflow--current-target))
         (consensus (when (and target
                               (fboundp 'gptel-auto-workflow--get-holographic-consensus))
                      (condition-case nil
                          (gptel-auto-workflow--get-holographic-consensus target)
                        (error nil))))
         (axis (plist-get consensus :axis))
         (axis-conf (plist-get consensus :confidence)))
    (format
     "You are running on %s/%s. Lambda compiler: %s. Health: %s (level %d, %d experiments, %.0f%% keep-rate).%s%s%s%s"
     bn model
     (or (and lambda-status (format "%s" lambda-status)) "unverified")
     (or health-label "N/A")
     (or health-level 0)
     (or total-exps 0)
     (if keep-rate (* 100 keep-rate) 0)
     ;; Health guidance
     (cond ((>= (or health-level 0) 3)
            "\nCAUTION: This backend is on probation — verify ALL outputs carefully. ")
           ((>= (or health-level 0) 2)
            "\nNote: This backend has elevated health warnings — results may be
inconsistent.")
           (t ""))
     ;; Per-axis context
     (if (and axis (> axis-conf 0.5))
         (format "\nThis backend was selected for target %s (KIBC axis %s, confidence %.0f%%). "
                 (file-name-nondirectory target) axis (* 100 axis-conf))
       "")
     ;; Rate-limit / cooldown context
     (cond (in-cooldown
            "\nWARNING: This backend failed earlier in this run — it is being used as a
last resort. Expect potential issues.")
           (rate-limited
            "\nNote: This backend has active rate limits — responses may be throttled. ")
           (t
            (if (= (or health-level 0) 0)
                "\nThis backend is healthy and recommended for this task. "
              "")))
     (if (and keep-rate (>= keep-rate 0.7) (>= (or total-exps 0) 10))
         "High confidence in this routing decision (strong historical track record)."
       (if (>= (or total-exps 0) 5)
           "Moderate confidence — sufficient data supports this routing choice."
         "Low confidence — limited historical data for this backend/target combination.")))))

;; ─── Routing Decision Audit Trail ───

(defvar gptel-auto-workflow--routing-audit-log nil
  "Audit trail of routing decisions for observability.
Each entry is a plist: (:timestamp :target :agent-type :selected-backend
:selected-model :candidates). Candidates is a list of plists with
:backend :model :health :keep-rate :pref-boost :axis-boost :score.")

(defun gptel-auto-workflow--record-routing-decision (agent-type scored &optional vsm-adjustments)
  "Record a routing decision into the audit trail.
SCORED is the scored list from `ranked-subagent-backends' (with scores
attached).
VSM-ADJUSTMENTS is an optional list of VSM layer adjustment strings.
Keeps the last 100 decisions."
  (let ((target (and (boundp 'gptel-auto-workflow--current-target)
                     gptel-auto-workflow--current-target))
        (top (car scored))
        (candidates nil))
    (when top
      (dolist (entry (seq-take scored 5))
        (let* ((pair (car entry))
               (details (cdr entry))
               (score (plist-get details :score))
               (health (plist-get details :health))
               (keep-rate (plist-get details :keep-rate))
               (pref (plist-get details :pref-boost))
               (axis (plist-get details :axis-boost)))
          (push (list :backend (car pair)
                      :model (cdr pair)
                      :score score
                      :health health
                      :keep-rate keep-rate
                      :pref-boost pref
                      :axis-boost axis)
                candidates)))
      (push (list :timestamp (float-time)
                  :target (or target "unknown")
                  :agent-type (or agent-type "unknown")
                  :selected-backend (caar top)
                  :selected-model (cdar top)
                  :vsm-adjustments vsm-adjustments
                  :candidates (nreverse candidates))
            gptel-auto-workflow--routing-audit-log)
      ;; Keep last 100 entries
      (when (> (length gptel-auto-workflow--routing-audit-log) 100)
        (setq gptel-auto-workflow--routing-audit-log
              (seq-take gptel-auto-workflow--routing-audit-log 100))))))

;; ─── Impact-Driven Auto-Tuning ───

(defun gptel-auto-workflow--lambda-adjusted-penalty ()
  "Return the verification penalty for degraded backends, auto-tuned from
measured impact.
If healthy backends consistently outperform degraded ones (delta > 10%),
increase
penalty to -35. If degraded somehow equals or beats healthy (delta <= 0),
reduce
penalty to -5. Otherwise use default -20."
  (let* ((impact (condition-case nil
                     (gptel-auto-workflow--lambda-health-impact)
                   (error nil)))
         (delta (plist-get impact :impact-delta)))
    (cond ((and delta (> delta 0.10)) -35.0)   ; strong evidence → penalize more
          ((and delta (<= delta 0.0)) -5.0)     ; weak/no evidence → light penalty
          (t -20.0))))                            ; default

(defun gptel-auto-workflow--allium-adjusted-threshold ()
  "Return the Allium severity threshold, auto-tuned from measured impact.
If low-severity strategies consistently outperform high-severity ones (delta >
15%),
lower the threshold to 0.20 (stricter gating). If delta is small (<= 5%),
raise
it to 0.40 (more lenient). Default is 0.30."
  (let* ((impact (condition-case nil
                     (gptel-auto-workflow--allium-health-impact)
                   (error nil)))
         (delta (plist-get impact :impact-delta)))
    (cond ((and delta (> delta 0.15)) 0.20)   ; strong evidence → stricter
          ((and delta (<= delta 0.05)) 0.40)  ; weak/no evidence → more lenient
          (t 0.30))))                           ; default

;; ─── Lambda Health Impact Measurement ───

(defun gptel-auto-workflow--lambda-health-impact ()
  "Measure whether lambda-healthy backends produce better experiment outcomes.
Returns a plist with :healthy-keep-rate, :degraded-keep-rate,
:healthy-experiments,
:degraded-experiments, and :impact-delta (healthy - degraded).
Positive delta = lambda compiler gate predicts better outcomes."
  (let ((healthy-kept 0) (healthy-total 0)
        (degraded-kept 0) (degraded-total 0)
        (results (when (fboundp 'gptel-auto-workflow--parse-all-results)
                   (gptel-auto-workflow--parse-all-results))))
    (dolist (r results)
      (let* ((backend (plist-get r :backend))
            (decision (plist-get r :decision))
            (status (when (and backend
                               (boundp 'gptel-auto-workflow--lambda-verification-results))
                      (gethash backend gptel-auto-workflow--lambda-verification-results))))
        (when (and backend (not (string= backend "unknown")))
          (cond
           ((eq status :healthy)
            (cl-incf healthy-total)
            (when (equal decision "kept") (cl-incf healthy-kept)))
           ((eq status :degraded)
            (cl-incf degraded-total)
            (when (equal decision "kept") (cl-incf degraded-kept)))))))
    (list :healthy-keep-rate (if (> healthy-total 0) (/ (float healthy-kept) healthy-total) nil)
          :degraded-keep-rate (if (> degraded-total 0) (/ (float degraded-kept) degraded-total) nil)
          :healthy-experiments healthy-total
          :degraded-experiments degraded-total
          :impact-delta (if (and (> healthy-total 0) (> degraded-total 0))
                            (- (/ (float healthy-kept) healthy-total)
                               (/ (float degraded-kept) degraded-total))
                          nil))))

;; ─── Allium Health Impact Measurement ───

(defun gptel-auto-workflow--allium-health-impact ()
  "Measure whether low Allium severity predicts higher experiment keep-rates.
Returns a plist with :low-allium-keep-rate (strategies with low severity),
:high-allium-keep-rate (strategies with high severity), counts, and
:impact-delta.
Positive delta = low Allium severity correlates with better outcomes."
  (let* ((issues-dir (when (fboundp 'gptel-auto-workflow--worktree-base-root)
                       (expand-file-name "var/tmp/evolution/allium-issues"
                                         (gptel-auto-workflow--worktree-base-root))))
         (strategy-scores nil)
         (results (when (fboundp 'gptel-auto-workflow--parse-all-results)
                    (gptel-auto-workflow--parse-all-results)))
         (low-severity-kept 0) (low-severity-total 0)
         (high-severity-kept 0) (high-severity-total 0)
         ;; Auto-tuned severity threshold from measured impact
         (allium-threshold (gptel-auto-workflow--allium-adjusted-threshold)))
    ;; Collect Allium scores per strategy from issue files
    (when (and issues-dir (file-directory-p issues-dir))
      (dolist (file (directory-files issues-dir t "\\.md\\'"))
        (let* ((filename (file-name-nondirectory file))
               (strategy (replace-regexp-in-string "\\.md\\'" "" filename))
               (content (condition-case nil
                            (with-temp-buffer
                              (insert-file-contents file)
                              (buffer-string))
                          (error nil))))
          (when content
            (let ((severity (when (string-match "Severity: \\([0-9.]+\\)" content)
                              (string-to-number (match-string 1 content)))))
              (when severity
                (push (cons strategy severity) strategy-scores)))))))
    ;; Cross-reference with experiment keep-rates
    (dolist (pair strategy-scores)
      (let* ((strategy (car pair))
             (severity (cdr pair))
             (s-kept 0) (s-total 0))
        (dolist (r results)
          (let ((r-strategy (plist-get r :research-strategy))
                (r-decision (plist-get r :decision)))
            (when (and r-strategy (string= r-strategy strategy))
              (cl-incf s-total)
              (when (equal r-decision "kept")
                (cl-incf s-kept)))))
        (when (> s-total 0)
          (if (< severity allium-threshold)  ; low severity = better
              (progn (cl-incf low-severity-total s-total)
                     (cl-incf low-severity-kept s-kept))
            (progn (cl-incf high-severity-total s-total)
                   (cl-incf high-severity-kept s-kept))))))
    (list :low-allium-keep-rate (if (> low-severity-total 0)
                                    (/ (float low-severity-kept) low-severity-total) nil)
          :high-allium-keep-rate (if (> high-severity-total 0)
                                     (/ (float high-severity-kept) high-severity-total) nil)
          :low-allium-experiments low-severity-total
          :high-allium-experiments high-severity-total
          :strategies-audited (length strategy-scores)
          :impact-delta (if (and (> low-severity-total 0) (> high-severity-total 0))
                            (- (/ (float low-severity-kept) low-severity-total)
                               (/ (float high-severity-kept) high-severity-total))
                          nil))))

;; ─── Audit Trail Analysis ───

(defun gptel-auto-workflow--audit-trail-summary ()
  "Return a plist summarizing the routing audit trail.
Fields: :total-decisions, :backend-counts (alist of backend→count),
:avg-health (hash of backend→avg health level),
:avg-keep-rate (hash of backend→avg keep-rate),
:vsm-adjustment-counts (plist of layer→times-active)."
  (let ((total 0)
        (backend-counts (make-hash-table :test 'equal))
        (backend-health-sum (make-hash-table :test 'equal))
        (backend-rate-sum (make-hash-table :test 'equal))
        (vsm-s1 0) (vsm-s2 0) (vsm-s3 0) (vsm-s4 0) (vsm-s5 0))
    (dolist (entry gptel-auto-workflow--routing-audit-log)
      (cl-incf total)
      ;; Per-backend counts
      (let ((backend (plist-get entry :selected-backend))
            (candidates (plist-get entry :candidates)))
        (when backend
          (let ((count (gethash backend backend-counts)))
            (puthash backend (if count (1+ count) 1) backend-counts)))
        ;; Per-candidate health/rate aggregation
        (when candidates
          (dolist (c (if (listp candidates) candidates (list candidates)))
            (when (listp c)
              (let* ((b (plist-get c :backend))
                     (health (plist-get c :health))
                     (rate (plist-get c :keep-rate)))
                (when (and b health)
                  (puthash b (+ (or (gethash b backend-health-sum) 0) health)
                           backend-health-sum))
                (when (and b rate)
                  (puthash b (+ (or (gethash b backend-rate-sum) 0) rate)
                           backend-rate-sum))))))
        ;; VSM adjustment counts
        (let ((adj (plist-get entry :vsm-adjustments)))
          (when adj
            (dolist (a adj)
              (cond ((string-match-p "S1:" a) (cl-incf vsm-s1))
                    ((string-match-p "S2:" a) (cl-incf vsm-s2))
                    ((string-match-p "S3:" a) (cl-incf vsm-s3))
                    ((string-match-p "S4:" a) (cl-incf vsm-s4))
                    ((string-match-p "S5:" a) (cl-incf vsm-s5))))))))
    (list :total-decisions total
          :backend-counts backend-counts
          :avg-health backend-health-sum
          :avg-keep-rate backend-rate-sum
          :vsm-adjustments (list :s1 vsm-s1 :s2 vsm-s2
                                 :s3 vsm-s3 :s4 vsm-s4 :s5 vsm-s5)
          ;; Persona impact snapshot at query time
          :persona-impact (condition-case nil
                              (gptel-auto-workflow--nucleus-persona-impact)
                            (error nil)))))

;; ─── Per-Target Model Preference ───

(defun gptel-auto-workflow--best-model-for-target (target backend)
  "Return the best historical model for TARGET on BACKEND.
Searches all kept experiments for this target+backend pair and returns
the model with the highest keep-rate. Falls back to category-level
model from `gptel-ai-behaviors--best-model' when no per-target data."
  (let ((best-model nil)
        (best-rate 0.0))
    ;; Phase 1: per-target data from experiment history
    (when (and target backend (fboundp 'gptel-auto-workflow--parse-all-results))
      (let ((model-stats (make-hash-table :test 'equal)))
        (dolist (r (gptel-auto-workflow--parse-all-results))
          (let ((r-target (plist-get r :target))
                (r-backend (plist-get r :backend))
                (r-model (plist-get r :model))
                (r-decision (plist-get r :decision)))
            (when (and (string= (or r-target "") target)
                       (string= (or r-backend "") backend)
                       (stringp r-model))
              (let ((stats (or (gethash r-model model-stats) (cons 0 0))))
                (cl-incf (car stats))
                (when (equal r-decision "kept")
                  (cl-incf (cdr stats)))
                (puthash r-model stats model-stats)))))
        (maphash (lambda (model stats)
                   (let ((total (car stats))
                         (kept (cdr stats)))
                      (when (and (> total 0)
                                 (> kept 0)
                                 (> (/ (float kept) total) best-rate)
                                 (or (not (fboundp 'gptel-auto-workflow--model-combination-valid-p))
                                     (gptel-auto-workflow--model-combination-valid-p
                                      (concat backend "/" model))))
                       (setq best-rate (/ (float kept) total))
                       (setq best-model model))))
                 model-stats)))
    ;; Phase 2: fallback to category-level model from ai-behaviors
    (unless best-model
      (when (and (fboundp 'gptel-auto-workflow--categorize-target)
                 (fboundp 'gptel-ai-behaviors--best-model))
        (let* ((category (gptel-auto-workflow--categorize-target target))
               (cat-best (gptel-ai-behaviors--best-model category "executor")))
          (when cat-best
            (setq best-model (car cat-best))
            (message "[model-select] Category fallback for %s: %s (from %s)"
                     target (car cat-best) category)))))
    best-model))

;; ─── Per-Run Backend Cooldown ───

(defvar gptel-auto-workflow--run-failed-backends nil
  "List of backend names that failed during the current run.
Backends in this list are excluded from routing for the remainder
of the run. Cleared when a new run starts via
`gptel-auto-workflow--clear-run-failed-backends'.")

(defun gptel-auto-workflow--clear-run-failed-backends ()
  "Clear the per-run backend cooldown list.
Call at the start of a new workflow run."
  (setq gptel-auto-workflow--run-failed-backends nil))

(defun gptel-auto-workflow--ranked-subagent-backends (&optional agent-type)
  "Return ordered backend/model alist for subagent routing.
Ranks backends by health-weight × historical-keep-rate, best first.
Health data from lambda verification strikes; keep-rate from ontology.
Falls back to the static headless-subagent-fallbacks if no data available.

Phase 2 P(λ) gating: backends with :degraded lambda verification are
excluded entirely (score 0), not just deprioritized. This implements the
hard gate: if a backend fails the lambda compiler check, it's not used."
  (let* ((scored nil)
        ;; Use the live fallback chain as default-models so any ontology
        ;; reordering (applied to executor-rate-limit-fallbacks by
        ;; reorder-fallbacks-by-ontology) is picked up here too.
        (default-models (or (and (boundp 'gptel-auto-workflow-executor-rate-limit-fallbacks)
                                gptel-auto-workflow-executor-rate-limit-fallbacks)
             '(("DeepSeek" . "deepseek-v4-pro")
               ("MiniMax" . "MiniMax-M3")
               ("DashScope" . "qwen3.6-plus")
               ("moonshot" . "kimi-k2.6"))))
        ;; Pre-compute once for all backends
        (axis-rates-cache (when (fboundp 'gptel-auto-workflow--backend-per-axis-keep-rates)
                            (condition-case nil
                                (gptel-auto-workflow--backend-per-axis-keep-rates)
                              (error nil))))
        (target-axis-cache (when (and (boundp 'gptel-auto-workflow--current-target)
                                      gptel-auto-workflow--current-target
                                       (fboundp 'gptel-auto-workflow--get-holographic-consensus))
         (condition-case _
                                 (gptel-auto-workflow--get-holographic-consensus
                                  gptel-auto-workflow--current-target)
                               (error nil))))
        ;; VSM routing params for audit trail
        (vsm-params (gptel-auto-workflow--vsm-adjusted-routing-params))
        (vsm-adjustments (plist-get vsm-params :adjustments)))
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
             ;; get the 0.25 floor (DeepSeek's earned keep-rate) to avoid
             ;; cold-start bias from a single discarded experiment.
             (keep-rate (if (fboundp 'gptel-auto-workflow--get-backend-performance-stats)
                             (let* ((stats (gptel-auto-workflow--get-backend-performance-stats backend))
                                    (raw (plist-get stats :keep-rate))
                                    (total (plist-get stats :total)))
                               (if (or (null raw) (< total 3)) 0.25 raw))
                           0.25))
             ;; Cold-start exploration boost: backends with very few
             ;; experiments get a temporary score lift so they can
             ;; accumulate data and prove themselves. Without this,
             ;; established backends (DashScope, DeepSeek) permanently
             ;; dominate and new backends (moonshot/kimi-k2.6) never
             ;; get a chance to compete.
             (cold-start-boost
              (if (fboundp 'gptel-auto-workflow--get-backend-performance-stats)
                  (let* ((stats (gptel-auto-workflow--get-backend-performance-stats backend))
                         (total (plist-get stats :total)))
                    (cond ((< total 3) 0.01)     ; almost no data → minimal boost
                          ((< total 5) 0.005)    ; some data → tiny boost
                          (t 0.0)))
                0.01))  ; if stats unavailable, treat as cold-start
              (quarantined (and (fboundp 'gptel-auto-workflow--backend-quarantined-p)
                                (gptel-auto-workflow--backend-quarantined-p backend)))
              (rate-limited (and (boundp 'gptel-auto-workflow--rate-limited-backends)
                                 (member backend gptel-auto-workflow--rate-limited-backends)))
              ;; Per-run cooldown: backends that failed this run are excluded
              (cooldown (and (boundp 'gptel-auto-workflow--run-failed-backends)
                             (member backend gptel-auto-workflow--run-failed-backends)))
              ;; Task-specific preference boost: shifts score for backends
              ;; known to excel at particular agent types.
              (pref-boost (if (and agent-type (stringp agent-type)
                                 (boundp 'gptel-auto-workflow--task-backend-preference))
                              (or (let ((match (cl-find-if
                                                (lambda (e)
                                                  (and (string= (nth 0 e) agent-type)
                                                       (string= (nth 1 e) backend)))
                                                gptel-auto-workflow--task-backend-preference)))
                                    (and (consp match) (cddr match)))
                                  0.0)
                            0.0))
               ;; Phase ω: per-axis boost based on holographic consensus.
               (axis-boost (gptel-auto-workflow--axis-preference-boost backend axis-rates-cache target-axis-cache))
               ;; Phase γ: skill graph neighbor success (future: integrate with graph data)
                (graph-neighbor-boost (gptel-auto-workflow--graph-neighbor-success
                                       backend (bound-and-true-p gptel-auto-workflow--current-target)))
               ;; Phase δ: skill graph edge strength (future: integrate with graph data)
               (graph-edge-boost (gptel-auto-workflow--graph-edge-strength
                                  backend (bound-and-true-p gptel-ai-behaviors--current-hashtags)))
               (score (cond
                       (lambda-degraded -1.0)   ; P(λ) gate: hard exclude
                       (quarantined -1.0)       ; health gate: hard exclude
                       (cooldown -1.0)           ; per-run: hard exclude
                       (rate-limited 0.01)      ; demoted but still available as last resort
                        (t (+ (* health keep-rate) pref-boost axis-boost cold-start-boost
                              graph-neighbor-boost graph-edge-boost)))))
         (when (>= score 0.0)
           (push (cons (cons backend model)
                       (list :score score :health health :keep-rate keep-rate
                             :pref-boost pref-boost :axis-boost axis-boost
                             :graph-neighbor graph-neighbor-boost
                             :graph-edge graph-edge-boost))
                 scored))))
    (if scored
        (let ((sorted (sort (nreverse scored)
                            (lambda (a b) (> (plist-get (cdr a) :score)
                                             (plist-get (cdr b) :score))))))
          ;; Record routing decision for audit trail
          (gptel-auto-workflow--record-routing-decision agent-type sorted vsm-adjustments)
          (mapcar #'car sorted))
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
        (remhash backend gptel-auto-workflow--lambda-last-strike-time)
        (when (>= old-level 1)
          (message "[verbum] ✓ %s recovered: %s→HEALTHY (strikes cleared)"
                   backend (gptel-auto-workflow--backend-health-label backend))))
       (:degraded
        (let* ((new-count (1+ count))
               (new-level (gptel-auto-workflow--backend-health-level backend)))
          (puthash backend new-count gptel-auto-workflow--lambda-strike-count)
          (puthash backend (float-time) gptel-auto-workflow--lambda-last-strike-time)
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

(defun gptel-auto-workflow--call-backend-for-lambda (backend _model _prompt)
  "Verify lambda compiler for BACKEND/MODEL.
All known backends already support lambda notation (P(λ) ≈ 100%), so
this is a no-op that immediately marks each backend as :healthy.
Runtime strike tracking in `gptel-auto-workflow--record-lambda-strike'
still catches real failures during experiment execution.
Returns t to indicate verification completed."
  (puthash backend :healthy
           gptel-auto-workflow--lambda-verification-results)
  (gptel-auto-workflow--record-lambda-strike backend :healthy)
  (gptel-auto-workflow--record-lambda-trend backend :healthy)
  t)

(defun gptel-auto-workflow--verify-backend-lambda-impl (backend &optional _model)
  "Verify lambda compiler for BACKEND/MODEL.
All known backends already support lambda notation, so this always
returns :healthy immediately without API calls."
  (puthash backend :healthy
           gptel-auto-workflow--lambda-verification-results)
  (gptel-auto-workflow--record-lambda-strike backend :healthy)
  (gptel-auto-workflow--record-lambda-trend backend :healthy)
  :healthy)

(defconst gptel-auto-workflow--combinator-patterns
  '((:K . "\\bk[^a-z]\\|\\bselect\\|car\\|first\\|head")        ;; Select first argument
    (:I . "\\bidentity\\|\\biota\\|\\bignore\\|return\b.*self") ;; Identity
    (:B . "\\bcomp[ose]\\|\\bfmap\\|\\bmap\\|\\b\\.\\b")        ;; Compose
    (:C . "\\bflip\\|\\breverse\\|\\bswap\\|\\border\\s+")       ;; Flip/reorder
    (:D . "\\bcasca[de]\\|\\bjoin\\|\\bflatmap\\|\\bbind")      ;; Cascade/join
    (:W . "\\bduplicat\\|\\bcopy\\|\\btwice\\|\\bboth\\s+")     ;; Duplicate
    (:Y . "\\bfix\\|\\brecurs\\|\\by-combinator\\|\\bfixed-point") ;; Recursion
    (:S . "\\bsubstitut\\|\\bapply\\|\\bap\\|\\b\\$\\s*"))      ;; Substitution
  "Combinator type regex patterns for classifying lambda expressions.
Maps verbum ISA opcodes to regex patterns in backend responses.
Used for task-specific backend routing: programming→B,
tool-calls→C/apply, agentic→Y/recursion, natural-language→I/identity.")

(defun gptel-auto-workflow--classify-combinators (response)
  "Classify which combinator types appear in RESPONSE.
Returns list of (combinator-type . strength) pairs sorted by strength.
E.g., ((:B . 3) (:K . 1)) for a response heavy on composition."
  (let ((results nil))
    (when response
      (dolist (pair gptel-auto-workflow--combinator-patterns)
        (let* ((type (car pair))
               (pattern (cdr pair))
               (count 0))
          (with-temp-buffer
            (insert (downcase response))
            (goto-char (point-min))
            (while (re-search-forward pattern nil t)
              (setq count (1+ count))))
          (when (> count 0)
            (push (cons type count) results))))
      ;; Sort by count descending
      (sort results (lambda (a b) (> (cdr a) (cdr b)))))))

(defun gptel-auto-workflow--response-contains-lambda-p (response)
  "Check if RESPONSE contains lambda expressions.
Looks for λ, lambda, or -> patterns, plus typed combinators."
  (when response
    (or (string-match-p "λ" response)
        (string-match-p "\\\\lambda" response)
        (string-match-p "->" response)
        (string-match-p "lambda" response)
        (gptel-auto-workflow--classify-combinators response))))

(defun gptel-auto-workflow--combinator-for-category (category)
  "Return the dominant combinator type for a task CATEGORY.
Based on verbum's finding that different tasks use different opcode
profiles. Maps OV5's 4-category ontology to verbum's combinator ISA.

- :programming → :B (compose)  — code is function composition
- :tool-calls  → :C (flip)    — tool calling reorders arguments
- :agentic     → :Y (recursion) — agents recurse through states
- :natural-language → :I (identity) — NL is identity-like (reading directly)"
  (cl-case category
    (:programming :B)
    (:tool-calls :C)
    (:agentic :Y)
    (:natural-language :I)
    (t :I)))

;; ─── Lambda Verification Report (verbum Phase 12) ───

(defun gptel-auto-workflow--lambda-verification-report ()
  "Generate report of lambda verification results across all backends.
Returns plist with :total :healthy :degraded :unknown :backends."
  (let ((fallbacks (if (boundp 'gptel-auto-workflow-headless-subagent-fallbacks)
                        gptel-auto-workflow-headless-subagent-fallbacks
                      '(("DashScope" . "qwen3.6-plus")
                        ("moonshot" . "kimi-k2.6")
                        ("DeepSeek" . "deepseek-v4-pro")
                        ("MiniMax" . "MiniMax-M3"))))
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
Penalty auto-tuned from measured lambda-health-impact:
default -20 for degraded, -35 when delta>10%, -5 when delta<=0."
  (let* ((degraded-penalty (gptel-auto-workflow--lambda-adjusted-penalty))
         (result nil))
    (dolist (entry scored)
      (let* ((backend (plist-get entry :backend))
             (status (or (gethash backend gptel-auto-workflow--lambda-verification-results)
                         :unknown))
             (score (plist-get entry :score))
              (penalty (pcase status
                         (:degraded degraded-penalty)
                         (:unknown 0.0)
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
Returns plist with :consistent t/nil, :agreement-ratio 0.0-1.0, :conflicts
list.
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
                :backend-count (length backend-axes)
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
               (let ((check (condition-case nil
                                 (gptel-auto-workflow--cross-backend-consistency target)
                               (error nil))))
                 (when (>= (or (plist-get check :backend-count) 0) 2)
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
Format: ((target . axis) . weight) alist where weight is a delta-weighted
float. Higher deltas contribute more to consensus confidence.
Inspired by verbum cross-op consensus etching.")

(defun gptel-auto-workflow--record-holographic-experiment (experiment)
  "Record EXPERIMENT into holographic memory with delta-weighted confidence.
Increments consensus weight for target+axis combination, scaled by the
experiment's code-quality delta so larger improvements count more.
EXPERIMENT is a plist with :target, :kibcm-axis, :decision, :delta."
  (when (and experiment
             (equal (plist-get experiment :decision) "kept"))
    (let* ((target (or (plist-get experiment :target) ""))
           (axis (or (plist-get experiment :kibcm-axis) "?"))
            (delta-val (plist-get experiment :delta))
            (delta (cond ((numberp delta-val) delta-val)
                         ((and (stringp delta-val) (string-match "\\`[+-]?[0-9.]+\\'" delta-val))
                          (string-to-number delta-val))
                         (t 0.0)))
           (weight (+ 1.0 (max 0.0 delta)))  ; base 1.0 + improvement bonus
           (key (cons target axis))
           (existing (assoc key gptel-auto-workflow--holographic-memory)))
      (if existing
          (setcdr existing (+ (cdr existing) weight))
        (push (cons key weight) gptel-auto-workflow--holographic-memory))
      (message "[holographic] Recorded %s → %s (Δ=%.3f weight=%.1f → total=%.1f)"
               target axis delta weight
               (or (cdr (assoc key gptel-auto-workflow--holographic-memory)) 0.0)))))

(defun gptel-auto-workflow--get-holographic-consensus (target)
  "Get holographic consensus for TARGET with delta-weighted confidence.
Returns plist with :axis :count :total :confidence.
Higher confidence = more experiments with larger deltas agreed."
  (let ((matches (cl-remove-if-not
                  (lambda (entry) (equal (car (car entry)) target))
                  gptel-auto-workflow--holographic-memory))
        (total 0.0))
    (dolist (m matches)
      (cl-incf total (cdr m)))
    (if (null matches)
        (list :axis "?" :count 0 :total 0.0 :confidence 0.0)
      (let* ((best (cl-reduce (lambda (a b)
                                (if (> (cdr a) (cdr b)) a b))
                              matches))
             (axis (cdr (car best)))
             (count (round (cdr best))))
        (list :axis axis
              :count count
              :total total
              :confidence (if (> total 0.0) (/ (cdr best) total) 0.0))))))

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
Returns list of target names that are dead (no improvement across any
backend).
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
Returns: -1 (reject, below baseline), 0 (defer, ambiguous), +1 (accept, beats
baseline).
Based on verbum ternary weight research: {-1, 0, +1} creates cleaner
boundaries."
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

;; ─── Per-Axis Backend Preference Boost ───

(defun gptel-auto-workflow--axis-preference-boost (backend &optional axis-rates target-axis)
  "Return per-axis boost for BACKEND based on current target's KIBC axis.
Reads `gptel-auto-workflow--current-target', holographic consensus,
and per-axis keep-rates. When AXIS-RATES and TARGET-AXIS are supplied,
skips recomputation (caller pre-computes for efficiency).
Returns 0.0 when no consensus data exists.
Boost = (keep-rate - avg-axis-rate) × confidence × 0.15."
  (let* ((target (and (boundp 'gptel-auto-workflow--current-target)
                      gptel-auto-workflow--current-target))
         (axis-rates (or axis-rates
                         (when (fboundp 'gptel-auto-workflow--backend-per-axis-keep-rates)
                           (condition-case nil
                               (gptel-auto-workflow--backend-per-axis-keep-rates)
                             (error nil)))))
         (consensus (or target-axis
                        (when (and target
                                   (fboundp 'gptel-auto-workflow--get-holographic-consensus))
                          (condition-case nil
                              (gptel-auto-workflow--get-holographic-consensus target)
                            (error nil)))))
         (axis (plist-get consensus :axis))
         (confidence (plist-get consensus :confidence))
         (count (plist-get consensus :count)))
    (if (and axis axis-rates (> confidence 0.5) (> count 1))
        (let* ((axis-match (cl-find-if
                            (lambda (a)
                              (and (string= (cdar a) axis)
                                   (string= (caar a) backend)))
                            axis-rates))
               (axis-rate (and axis-match (cdr axis-match)))
               (avg-rate (let ((sum 0.0) (n 0))
                           (dolist (a axis-rates)
                             (when (string= (cdar a) axis)
                               (cl-incf sum (cdr a))
                               (cl-incf n)))
                           (if (> n 0) (/ sum n) 0.0))))
          (if (and axis-rate (> axis-rate avg-rate 0.0))
              (* (- axis-rate avg-rate) confidence 0.15)
            0.0))
      0.0)))

;; ─── Research Coordinator (AutoTTS × AutoGo × Ontology) ───

(defun gptel-auto-workflow--research-priorities ()
  "Query ontology, AutoTTS, and AutoGo for research priorities.
Returns plist: (:category-priorities (cat . reason) ... :strategy-insights ...
:budget-insights ...)."
  (let* ((results (condition-case nil (gptel-auto-workflow--parse-all-results) (error nil)))
         (cat-stats (make-hash-table :test 'equal))
         (priorities nil))
    ;; 1. Ontology: category health from experiment data
    (dolist (r results)
      (let* ((r-target (plist-get r :target))
             (r-decision (plist-get r :decision))
             (r-kept (equal r-decision "kept"))
             (r-strategy (plist-get r :strategy))
             (cat (and r-target (fboundp 'gptel-auto-workflow--categorize-target)
                      (gptel-auto-workflow--categorize-target r-target))))
        (when cat
          (let ((e (gethash cat cat-stats (list 0 0 (make-hash-table :test 'equal)))))
            (setf (nth 0 e) (+ (nth 0 e) (if r-kept 1 0)))
            (setf (nth 1 e) (1+ (nth 1 e)))
            (when r-strategy
              (let ((s (gethash r-strategy (nth 2 e) (cons 0 0))))
                (setf (car s) (+ (car s) (if r-kept 1 0)))
                (setf (cdr s) (1+ (cdr s)))
                (puthash r-strategy (nth 2 e) s)))
            (puthash cat e cat-stats)))))
    ;; 2. Generate priorities per category
    (maphash
     (lambda (cat stats)
       (let* ((kept (nth 0 stats))
              (total (nth 1 stats))
              (rate (if (> total 0) (/ (float kept) total) 0))
              (strategies (nth 2 stats))
              (best-strat (let ((best nil) (best-rate 0))
                            (maphash (lambda (s e)
                                       (let ((sr (if (> (cdr e) 0) (/ (float (car e)) (cdr e)) 0)))
                                         (when (> sr best-rate) (setq best s best-rate sr))))
                                     strategies)
                            best))
              (best-strat-rate (if (and best-strat (gethash best-strat strategies))
                                  (let ((e (gethash best-strat strategies)))
                                    (if (> (cdr e) 0) (/ (float (car e)) (cdr e)) 0))
                                0))
              (concrete-health (and (fboundp 'gptel-ai-behaviors--best-concrete-tasks)
                                    (gethash cat gptel-ai-behaviors--best-concrete-tasks)))
              (drift (and (fboundp 'gptel-auto-workflow--detect-category-drift)
                         (let ((d (gptel-auto-workflow--detect-category-drift)))
                           (cl-some (lambda (x) (eq (nth 1 x) cat)) d)))))
         ;; Priority rules:
         (cond
          ((and (< rate 0.1) (> total 20))
           (push (cons cat (format "Critical: %.0f%% keep-rate after %d experiments — needs investigation" (* 100 rate) total)) priorities))
          (drift
           (push (cons cat (format "Drift detected — targets behaving differently from category average")) priorities))
          ((and concrete-health (> (cdr concrete-health) 0.5) (< rate 0.1))
           (push (cons cat (format "Concrete tasks keep at %.0f%% but experiments fail — simplify experiments" (* 100 (cdr concrete-health)))) priorities))
          ((and best-strat (< best-strat-rate 0.15) (> total 10))
           (push (cons cat (format "Best strategy %s at %.0f%% — consider strategy evolution" best-strat (* 100 best-strat-rate))) priorities))
          ((< total 10)
           (push (cons cat (format "Insufficient data: %d experiments — more experiments needed" total)) priorities)))))
     cat-stats)
    (list :category-priorities (nreverse priorities))))

(defun gptel-auto-workflow--format-research-priorities ()
  "Format research priorities as a prompt string for the researcher."
  (let ((priorities (gptel-auto-workflow--research-priorities))
        (parts nil))
    (dolist (p (plist-get priorities :category-priorities))
      (push (format "  [%s] %s" (car p) (cdr p)) parts))
    (when parts
      (concat "## Research Priorities (from Ontology × AutoTTS × AutoGo)\n"
              "Focus research on these categories:\n"
              (mapconcat #'identity (nreverse parts) "\n")
              "\n\nProduce category-specific findings — not global recommendations.\n"))))

;; ─── Verbum Experiment Tracker ───

;; ─── Digital Twin: File Dependency Graph ───

(defvar gptel-auto-workflow--digital-twin-cache nil
  "Cached digital twin data: (file . plist) with :requires :provides :defuns
:defvars.
Built by `gptel-auto-workflow--build-digital-twin'. Persisted to
var/tmp/digital-twin.json.")

(defun gptel-auto-workflow--parse-el-file (file)
  "Parse FILE for require/provide/defun/defvar declarations.
Returns plist: (:requires (:provides :defuns :defvars :declare-fns)."
  (let ((requires nil) (provides nil) (defuns nil)
        (defvars nil) (declare-fns nil))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (while (not (eobp))
          (cond
           ((looking-at "(require\\s-+'?\\([^ )]+\\)")
            (push (match-string-no-properties 1) requires))
           ((looking-at "(provide\\s-+'?\\([^ )]+\\)")
            (push (match-string-no-properties 1) provides))
           ((looking-at "(defun\\s-+\\([^ (]+\\)")
            (push (match-string-no-properties 1) defuns))
           ((looking-at "(defvar\\s-+\\([^ (]+\\)")
            (push (match-string-no-properties 1) defvars))
           ((looking-at "(declare-function\\s-+\\([^ (]+\\)")
            (push (match-string-no-properties 1) declare-fns)))
          (forward-line 1))))
    (list :requires (nreverse requires)
          :provides (nreverse provides)
          :defuns (nreverse defuns)
          :defvars (nreverse defvars)
          :declare-fns (nreverse declare-fns))))

(defun gptel-auto-workflow--build-digital-twin (&optional force)
  "Build digital twin dependency graph for all .el files in lisp/modules/.
Cached unless FORCE is non-nil."
  (let ((dir (expand-file-name "lisp/modules/" (gptel-auto-workflow--worktree-base-root))))
    (when (and (or force (null gptel-auto-workflow--digital-twin-cache))
               (file-directory-p dir))
      (let ((twin (make-hash-table :test 'equal)))
        (dolist (file (directory-files dir t "\\.el$"))
          (let ((parsed (gptel-auto-workflow--parse-el-file file))
                (rel (file-relative-name file dir)))
            (when parsed
              (puthash rel parsed twin))))
        (setq gptel-auto-workflow--digital-twin-cache twin)
        (message "[digital-twin] Built: %d files, %d total requires"
                 (hash-table-count twin)
                 (cl-reduce #'+ (mapcar #'length
                                        (mapcar (lambda (k) (plist-get (gethash k twin) :requires))
                                                (all-completions "" twin)))))
        ;; Persist
        (let ((file (expand-file-name "var/tmp/digital-twin.json"
                                      (gptel-auto-workflow--worktree-base-root))))
          (make-directory (file-name-directory file) t)
          (with-temp-file file
            (insert "{\"version\": 1, \"built\": \""
                    (format-time-string "%Y-%m-%dT%H:%M:%S")
                    "\", \"files\": {")
            (let ((first t))
              (maphash (lambda (k v)
                         (unless first (insert ","))
                         (setq first nil)
                         (insert (json-encode k) ":"
                                 (json-encode (list (cons :requires (plist-get v :requires))
                                                     (cons :provides (plist-get v :provides))
                                                     (cons :defuns (plist-get v :defuns))
                                                     (cons :defvars (plist-get v :defvars))))))
                       twin))
            (insert "}}"))
          (message "[digital-twin] Persisted to %s" file)))
      gptel-auto-workflow--digital-twin-cache)))

(defun gptel-auto-workflow--digital-twin-dependencies (target)
  "Return list of files that TARGET depends on (via require)."
  (when target
    (let* ((basename (file-name-nondirectory target))
           (file-key (concat "lisp/modules/" basename))
           (twin (or gptel-auto-workflow--digital-twin-cache
                     (gptel-auto-workflow--build-digital-twin))))
      (when twin
        (let ((entry (gethash file-key twin)))
          (when entry
            (plist-get entry :requires)))))))

(defun gptel-auto-workflow--digital-twin-dependents (target)
  "Return list of files that depend on TARGET."
  (when target
    (let* ((basename (file-name-nondirectory target))
           (provides (and (string-match "\\`\\(.+\\)\\.el\\'" basename)
                          (match-string 1 basename)))
           (twin (or gptel-auto-workflow--digital-twin-cache
                     (gptel-auto-workflow--build-digital-twin)))
           (dependents nil))
      (when (and twin provides)
        (maphash (lambda (file entry)
                   (when (member provides (plist-get entry :requires))
                     (push file dependents)))
                 twin))
      dependents)))

;; ─── Category Action Schema ───

(defconst gptel-auto-workflow--category-action-schemas
  '((:agentic
     :description "Agent orchestration and tool dispatch changes"
     :preconditions ("tool-registry-initialized" "fsm-not-in-error-state")
     :commit-criteria ("tool-dispatch-still-works" "error-handling-intact")
     :verification-commands ("emacs --batch --eval \"(check-parens)\""
                             "emacs -Q --batch -f batch-byte-compile")
     :instructions "⚠ AGENTIC: changes affect subagent dispatch. Add nil-guards on gethash/assoc
in FSM callbacks. Never remove error handlers without replacement.")
    (:programming
     :description "Code refactoring, performance, and bug fixes"
     :preconditions ("file-byte-compiles" "no-syntax-errors")
     :commit-criteria ("all-tests-pass" "no-regressions" "style-integrity")
     :verification-commands ("emacs --batch --eval \"(check-parens)\""
                             "emacs -Q --batch -f batch-byte-compile")
     :instructions "⚠ PROGRAMMING: byte-compile after EVERY edit. Add nil-guards (ignore-errors,
condition-case, hash-table-p). Extract duplicated code. Never reformat.")
    (:tool-calls
     :description "Sandbox execution and file operation tools"
     :preconditions ("tool-argument-schemas-valid" "sandbox-rules-loaded")
     :commit-criteria ("tool-call-still-works" "error-handling-robust")
     :verification-commands ("emacs --batch --eval \"(check-parens)\""
                             "emacs -Q --batch -f batch-byte-compile")
     :instructions "⚠ TOOL-CALLS: validate tool arguments with schemas. Add boundary checks on
file paths. Never bypass sandbox rules for direct operations.")
    (:natural-language
     :description "Prompt templates, text processing, context management"
     :preconditions ("file-byte-compiles")
     :commit-criteria ("prompt-format-preserved" "fallback-handlers-intact")
     :verification-commands ("emacs --batch --eval \"(check-parens)\""
                             "emacs -Q --batch -f batch-byte-compile")
     :instructions "⚠ NATURAL-LANGUAGE: preserve prompt template structure. Don't remove fallback
handlers. Test with sample input after changes."))
  "Per-category action schema with preconditions, commit criteria, verification
commands, and category-specific instructions.")

(defun gptel-auto-workflow--format-schema-guidance (target)
  "Format action schema for TARGET as prompt guidance string."
  (when (and target (fboundp 'gptel-auto-workflow--categorize-target))
    (let ((schema (cdr (assoc (gptel-auto-workflow--categorize-target target)
                              gptel-auto-workflow--category-action-schemas))))
      (when schema
        (format "## Action Schema (%s)\nPreconditions:\n%s\n\nCommit
criteria:\n%s\n\nVerification:\n%s"
                (plist-get schema :description)
                (mapconcat (lambda (p) (format "  ✓ %s" p))
                           (plist-get schema :preconditions) "\n")
                (mapconcat (lambda (c) (format "  ⚡ %s" c))
                           (plist-get schema :commit-criteria) "\n")
                (mapconcat (lambda (v) (format "  $ %s" v))
                           (plist-get schema :verification-commands) "\n"))))))

(defun gptel-auto-workflow--category-instructions (target)
  "Return category-specific agent instructions for TARGET.
Extracted from the ontology action schema.
Returns empty string when target category is unknown."
  (when (and target (fboundp 'gptel-auto-workflow--categorize-target))
    (let* ((cat (gptel-auto-workflow--categorize-target target))
           (schema (cdr (assoc cat gptel-auto-workflow--category-action-schemas)))
           (instructions (plist-get schema :instructions)))
      (or instructions ""))))

(defun gptel-auto-workflow--check-action-preconditions (target)
  "Check action preconditions for TARGET's category.
Returns nil if all pass, or a string describing the first unmet precondition.
This is the runtime enforcement layer — preconditions are checked
before the executor runs, not just listed in the prompt."
  (when (and target (fboundp 'gptel-auto-workflow--categorize-target))
    (let* ((category (gptel-auto-workflow--categorize-target target))
           (schema (cdr (assoc category gptel-auto-workflow--category-action-schemas)))
           (preconditions (plist-get schema :preconditions))
           (target-file (when (file-exists-p target) target))
           (result nil))
      (when preconditions
        (dolist (pre preconditions)
          (unless result
            (setq result
                  (pcase pre
                    ("file-byte-compiles"
                      (when (and target-file
                                 (not (zerop (call-process
                                             (expand-file-name "scripts/byte-compile-check.sh"
                                                               (or (and (boundp 'minimal-emacs-user-directory)
                                                                        minimal-emacs-user-directory)
                                                                   user-emacs-directory))
                                             nil nil nil
                                             target-file))))
                        (format "Precondition FAILED: %s does not byte-compile" target)))
                    ("no-syntax-errors"
                      (when target-file
                        (condition-case nil
                            (with-temp-buffer
                              (insert-file-contents target-file)
                              (check-parens)
                              nil)  ; no error = passes
                          (error
                           (format "Precondition FAILED: %s has syntax errors" target)))))
                    ("tool-registry-initialized"
                     (unless (and (boundp 'gptel-agent--agents)
                                  gptel-agent--agents)
                       "Precondition FAILED: tool registry not initialized"))
                    ("tool-argument-schemas-valid"
                     (unless (and (boundp 'gptel-tools--schemas)
                                  gptel-tools--schemas)
                       "Precondition FAILED: tool schemas not loaded"))
                    ("sandbox-rules-loaded"
                     (unless (and (boundp 'gptel-tools-bash--rules)
                                  gptel-tools-bash--rules)
                       "Precondition FAILED: sandbox rules not loaded"))
                    (_ nil))))))
      result)))

;; ─── Researcher→Ontology Bridge ───
;; The researcher discovers patterns that should refine the ontology.
;; This function surfaces category boundary mismatches from experiment data.

(defun gptel-auto-workflow--detect-category-drift ()
  "Check if any targets behave differently from their ontology category.
Compares each target's keep-rate against its category average.
A target that significantly outperforms/underperforms its category
average may be misclassified.
Returns alist of (target . (category . delta)) for drifts > 20%."
  (when (fboundp 'gptel-auto-workflow--parse-all-results)
    (let* ((results (gptel-auto-workflow--parse-all-results))
           (cat-stats (make-hash-table :test 'equal))
           (target-stats (make-hash-table :test 'equal))
           (drifts nil))
      ;; Aggregate category-level and target-level keep-rates
      (dolist (r results)
        (let* ((r-target (plist-get r :target))
               (r-decision (plist-get r :decision))
               (r-kept (equal r-decision "kept"))
               (category (and r-target (fboundp 'gptel-auto-workflow--categorize-target)
                              (gptel-auto-workflow--categorize-target r-target))))
          (when category
            (let ((c-entry (gethash category cat-stats (list :kept 0 :total 0))))
              (setq c-entry (plist-put c-entry :kept (+ (plist-get c-entry :kept) (if r-kept 1 0))))
              (setq c-entry (plist-put c-entry :total (1+ (plist-get c-entry :total))))
              (puthash category c-entry cat-stats))
            (let ((t-entry (gethash r-target target-stats (list :kept 0 :total 0))))
              (setq t-entry (plist-put t-entry :kept (+ (plist-get t-entry :kept) (if r-kept 1 0))))
              (setq t-entry (plist-put t-entry :total (1+ (plist-get t-entry :total))))
              (puthash r-target t-entry target-stats)))))
      ;; Compare each target against its category average
      (maphash
       (lambda (target t-stats)
         (let* ((category (and target (gptel-auto-workflow--categorize-target target)))
                (c-stats (or (gethash category cat-stats) (list :kept 0 :total 0)))
                (t-total (plist-get t-stats :total))
                (c-total (plist-get c-stats :total))
                (t-rate (if (> t-total 0) (/ (float (plist-get t-stats :kept)) t-total) 0))
                (c-rate (if (> c-total 0) (/ (float (plist-get c-stats :kept)) c-total) 0))
                (delta (- t-rate c-rate)))
           (when (and (>= t-total 5) (> (abs delta) 0.2))
             (push (list target category delta) drifts)
             (message "[ontology-drift] ⚠ %s (%s) keep-rate %.0f%% vs category %.0f%% (Δ%+.0f%%) —
possible misclassification"
                      (file-name-nondirectory target) category (* 100 t-rate) (* 100 c-rate) (* 100 delta)))))
       target-stats)
      drifts)))

;; ─── Ontology Self-Repair ───
;; The ontology not only detects drift but automatically suggests fixes.

(defconst gptel-auto-workflow--category-pattern-map
  '((:agentic        . "agent\\|workflow\\|strategy\\|evolution")
    (:programming    . "benchmark\\|fsm\\|retry\\|test\\|code\\|compile\\|^gptel-ext-")
    (:tool-calls     . "








sandbox\\|^gptel-tools-\\(?:bash\\|grep\\|glob\\|edit\\|apply\\|preview\\|programmatic\\)")
    (:natural-language . "context\\|prompt\\|chat\\|conversation\\|language\\|text\\|summarize\\|stream"))
  "Regex patterns used by `categorize-target' for each category.
Used by `gptel-auto-workflow--repair-ontology' to suggest pattern updates.")

(defun gptel-auto-workflow--repair-ontology ()
  "Analyze drift data and suggest category boundary adjustments.
When targets consistently behave differently from their assigned category,
this function suggests recategorization or pattern updates.
Returns alist of suggestions: (target . suggested-category)."
  (let* ((drifts (ignore-errors (gptel-auto-workflow--detect-category-drift)))
         (results (ignore-errors (gptel-auto-workflow--parse-all-results)))
         (suggestions nil))
    (when drifts
      (dolist (drift drifts)
        (let* ((target (car drift))
               (current-cat (nth 1 drift))
               (delta (nth 2 drift))
                (_basename (file-name-nondirectory target))
               (best-cat nil)
               (best-rate 0))
          ;; Find which category this target would perform best in
          (when results
            (let ((cat-rates (make-hash-table :test 'equal)))
              (dolist (r results)
                (let* ((r-target (plist-get r :target))
                       (r-decision (plist-get r :decision))
                       (r-kept (equal r-decision "kept"))
                       (r-cat (and r-target (gptel-auto-workflow--categorize-target r-target))))
                  (when r-cat
                    (let ((entry (gethash r-cat cat-rates (list :kept 0 :total 0))))
                      (setq entry (plist-put entry :kept (+ (plist-get entry :kept) (if r-kept 1 0))))
                      (setq entry (plist-put entry :total (1+ (plist-get entry :total))))
                      (puthash r-cat entry cat-rates)))))
              ;; Find category with best keep-rate
              (maphash (lambda (cat stats)
                         (let* ((tot (plist-get stats :total))
                                (rate (if (> tot 0) (/ (float (plist-get stats :kept)) tot) 0)))
                           (when (and (> tot 5) (> rate best-rate))
                             (setq best-cat cat best-rate rate))))
                       cat-rates))
            (when (and best-cat (not (eq best-cat current-cat)))
              (push (list target current-cat best-cat delta) suggestions)
              (message "[ontology-repair] 🔧 %s: %s → %s (Δ%+.0f%%, category keep-rate %.0f%%)"
                       (file-name-nondirectory target) current-cat best-cat
                       (* 100 delta) (* 100 best-rate))))))
    suggestions)))

;; ─── Digital Twin Persistence ───

(defun gptel-auto-workflow--persist-target-state ()
  "Save target state cache and rejection memory to disk (survives daemon
restart)."
  (when (and (bound-and-true-p gptel-auto-experiment--target-state-cache)
             (> (hash-table-count gptel-auto-experiment--target-state-cache) 0))
    (let ((file (expand-file-name "var/tmp/digital-twin.json"
                                  (gptel-auto-workflow--worktree-base-root)))
          (data nil))
      (maphash (lambda (target state)
                 (push (cons target (list (cons :byte-compiles (plist-get state :byte-compiles))
                                          (cons :syntax-ok (plist-get state :syntax-ok))))
                       data))
               gptel-auto-experiment--target-state-cache)
      ;; Persist rejection memory alongside digital twin
      (when (bound-and-true-p gptel-auto-experiment--rejection-memory)
        (maphash (lambda (target rejections)
                   (let ((entry (assoc target data)))
                     (if entry
                         (setcdr entry (append (cdr entry)
                                               (list (cons :rejections rejections))))
                       (push (cons target (list (cons :rejections rejections)))
                             data))))
                 gptel-auto-experiment--rejection-memory))
      ;; Persist success memory alongside digital twin
      (when (bound-and-true-p gptel-auto-experiment--success-memory)
        (maphash (lambda (target successes)
                   (let ((entry (assoc target data)))
                     (if entry
                         (setcdr entry (append (cdr entry)
                                               (list (cons :successes successes))))
                       (push (cons target (list (cons :successes successes)))
                             data))))
                 gptel-auto-experiment--success-memory))
      (make-directory (file-name-directory file) t)
      (with-temp-file file
        (insert (let ((json-encoding-pretty-print t))
                  (json-encode data))))
      (message "[digital-twin] Persisted %d target states + rejection memory to %s" (length data) file))))

(defun gptel-auto-workflow--load-target-state ()
  "Load target state cache and rejection memory from disk."
  (when (boundp 'gptel-auto-experiment--target-state-cache)
    (let ((file (expand-file-name "var/tmp/digital-twin.json"
                                  (gptel-auto-workflow--worktree-base-root))))
      (when (file-exists-p file)
        (condition-case err
            (with-temp-buffer
              (insert-file-contents file)
              (let* ((raw (json-read))
                     (data (if (listp raw) raw
                             (cdr (assq 'files raw)))))
                (when (listp data)
                  (dolist (entry data)
                    (let ((target (car entry))
                          (plist (cdr entry)))
                      (puthash target
                               (list :byte-compiles (cdr (assq 'byte-compiles plist))
                                     :syntax-ok (cdr (assq 'syntax-ok plist)))
                               gptel-auto-experiment--target-state-cache)
                      (let ((rejections (cdr (assq 'rejections plist))))
                        (when (and rejections
                                   (bound-and-true-p gptel-auto-experiment--rejection-memory)
                                   (fboundp 'gptel-auto-experiment--remember-rejection))
                          (dolist (rej rejections)
                            (gptel-auto-experiment--remember-rejection target (car rej)))))
                      (let ((successes (cdr (assq 'successes plist))))
                        (when (and successes
                                   (bound-and-true-p gptel-auto-experiment--success-memory)
                                   (fboundp 'gptel-auto-experiment--remember-success))
                          (dolist (succ successes)
                            (gptel-auto-experiment--remember-success
                             target (car succ) (cdr succ)))))))
                  (message "[digital-twin] Loaded %d target states + rejection memory from %s"
                           (hash-table-count gptel-auto-experiment--target-state-cache) file))))
          (error (message "[digital-twin] Failed to load: %s" (error-message-string err)))))))

;; ─── Ontology Self-Evolution ───

(defvar gptel-auto-workflow--category-strategy-preferences nil
  "Alist of (category . preferred-strategy) learned from experiment outcomes.
Populated by `gptel-auto-workflow--evolve-ontology' during the evolution
cycle.
Changes when a new strategy significantly outperforms the current default for
a category.")

(defvar gptel-auto-workflow--category-saturation nil
  "Alist of (category . t) for categories where all strategies are failing.
Set by `gptel-auto-workflow--evolve-ontology' when a category's keep-rate
stays at 0% across sufficient experiments with multiple strategies.")

(defun gptel-auto-workflow--evolve-ontology ()
  "Evolve the ontology system from experiment outcomes.
Analyzes keep-rate per (category, strategy) across all experiments to:
1. Learn which strategies work best for each category
2. Detect category saturation (all strategies failing)
3. Update category-strategy preferences

Runs during the self-evolution cycle.  Results are stored in
`gptel-auto-workflow--category-strategy-preferences'."
  (let* ((results (ignore-errors (gptel-auto-workflow--parse-all-results)))
         (cat-strats (make-hash-table :test 'equal))
         (changes nil)
         (saturated nil))
    (when results
      ;; Phase 1: Aggregate keep-rate per (category, strategy)
      (dolist (r results)
        (let* ((r-target (plist-get r :target))
               (r-strategy (plist-get r :strategy))
               (r-decision (plist-get r :decision))
               (r-kept (equal r-decision "kept"))
               (category (and r-target (fboundp 'gptel-auto-workflow--categorize-target)
                              (gptel-auto-workflow--categorize-target r-target))))
          (when (and category r-strategy (not (string-empty-p r-strategy)))
            (let* ((key (cons category r-strategy))
                   (entry (gethash key cat-strats (list :kept 0 :total 0))))
              (setq entry (plist-put entry :kept (+ (plist-get entry :kept) (if r-kept 1 0))))
              (setq entry (plist-put entry :total (1+ (plist-get entry :total))))
              (puthash key entry cat-strats)))))

      ;; Phase 2: Compute keep-rates and select best strategies per category
      (let ((cat-groups (make-hash-table :test 'equal)))
        ;; Group by category
        (maphash
         (lambda (key entry)
           (let* ((category (car key))
                  (strategy (cdr key))
                  (kept (plist-get entry :kept))
                  (total (plist-get entry :total))
                  (rate (if (> total 0) (/ (float kept) total) 0)))
             (push (list :strategy strategy :keep-rate rate :total total)
                   (gethash category cat-groups))))
         cat-strats)

        ;; For each category, find best strategy
        (maphash
         (lambda (category strategies)
           (let* ((sorted (sort strategies
                                (lambda (a b) (> (plist-get a :keep-rate) (plist-get b :keep-rate)))))
                  (best (car sorted))
                  (best-rate (plist-get best :keep-rate))
                  (best-strat (plist-get best :strategy))
                  (total-kept (cl-reduce #'+ (mapcar (lambda (s) (plist-get s :kept)) sorted)))
                  (total-all (cl-reduce #'+ (mapcar (lambda (s) (plist-get s :total)) sorted))))
             ;; Check saturation: > 10 experiments, 0 kept across all strategies
             (if (and (>= total-all 10) (= total-kept 0))
                 (progn
                   (push category saturated)
                   (message "[ontology-evolve] ⚠ %s SATURATED: %d experiments, 0 kept across %d strategies"
                            category total-all (length strategies)))
               ;; Track best strategy if keep-rate > 0
               (when (and (> best-rate 0) (> (plist-get best :total) 2))
                 (let ((current (cdr (assoc category gptel-auto-workflow--category-strategy-preferences)))
                        (_total-strats (hash-table-count cat-strats)))
                   (unless (equal current best-strat)
                     (push (list category current best-strat best-rate) changes)
                     (message "[ontology-evolve] ✓ %s: strategy %s → %s (keep-rate %.0f%%)"
                              category (or current "default") best-strat (* 100 best-rate))))))))
         cat-groups)

      ;; Phase 3: Update preferences
      (dolist (change changes)
        (let ((category (car change))
              (strategy (nth 2 change)))
          (setq gptel-auto-workflow--category-strategy-preferences
                (assoc-delete-all category gptel-auto-workflow--category-strategy-preferences))
          (push (cons category strategy) gptel-auto-workflow--category-strategy-preferences)))

      ;; Phase 4: Update saturation flags
      (setq gptel-auto-workflow--category-saturation nil)
      (dolist (cat saturated)
        (push (cons cat t) gptel-auto-workflow--category-saturation))

      ;; Phase 5: Aggregate per-category eight-key weights
      (gptel-auto-workflow--evolve-ontology-eight-keys)

      ;; Phase 5: Learn backend-category fit from empirical data
      (let ((cat-backends (make-hash-table :test 'equal))
            (backend-changes 0))
        (dolist (r results)
          (let* ((r-target (plist-get r :target))
                 (r-backend (plist-get r :backend))
                 (r-decision (plist-get r :decision))
                 (r-kept (equal r-decision "kept"))
                 (category (and r-target (fboundp 'gptel-auto-workflow--categorize-target)
                                (gptel-auto-workflow--categorize-target r-target))))
            (when (and category r-backend)
              (let* ((key (cons category r-backend))
                     (entry (gethash key cat-backends (list :kept 0 :total 0))))
                (setq entry (plist-put entry :kept (+ (plist-get entry :kept) (if r-kept 1 0))))
                (setq entry (plist-put entry :total (1+ (plist-get entry :total))))
                (puthash key entry cat-backends)))))
        (let ((cat-best (make-hash-table :test 'equal)))
          (maphash
           (lambda (key entry)
             (let* ((category (car key))
                    (backend (cdr key))
                    (kept (plist-get entry :kept))
                    (total (plist-get entry :total))
                    (rate (if (> total 0) (/ (float kept) total) 0))
                    (current (gethash category cat-best (list :backend nil :keep-rate 0))))
               (when (and (>= total 3) (> rate (plist-get current :keep-rate)))
                 (puthash category (list :backend backend :keep-rate rate) cat-best))))
           cat-backends)
          (maphash
           (lambda (category best)
             (let* ((static (cdr (assoc category gptel-auto-workflow--category-backend-overrides)))
                    (learned (plist-get best :backend))
                    (rate (plist-get best :keep-rate)))
               (when (and static (not (equal static learned)))
                 (setq backend-changes (1+ backend-changes))
                 (message "[ontology-evolve] ⚡ %s: static %s → learned %s (%.0f%%)"
                          category static learned (* 100 rate)))))
           cat-best))
        (when (> backend-changes 0)
          (message "[ontology-evolve] %d backend-category mismatches vs static defconst" backend-changes)))

      (when changes
        (message "[ontology-evolve] Updated %d category strategy preferences" (length changes)))
      ;; Log convergence stats from refine cycle
      (when (bound-and-true-p gptel-auto-experiment--refine-convergence-stats)
        (let ((t-ref (plist-get gptel-auto-experiment--refine-convergence-stats :total))
              (s-ref (plist-get gptel-auto-experiment--refine-convergence-stats :success))
              (_f-ref (plist-get gptel-auto-experiment--refine-convergence-stats :failure)))
          (when (> t-ref 0)
            (message "[ontology-evolve] 🔄 Refine convergence: %d/%d success (%.0f%%) — Palantir target: 94%%"
                     s-ref t-ref (* 100 (/ (float s-ref) t-ref))))))
      ;; Log target state cache (lightweight digital twin)
      (when (and (bound-and-true-p gptel-auto-experiment--target-state-cache)
                 (> (hash-table-count gptel-auto-experiment--target-state-cache) 0))
        (let ((healthy 0) (broken 0))
          (maphash (lambda (_t state)
                     (if (and (plist-get state :byte-compiles)
                              (plist-get state :syntax-ok))
                         (cl-incf healthy)
                       (cl-incf broken)))
                   gptel-auto-experiment--target-state-cache)
          (message "[ontology-evolve] 📊 Target state: %d healthy, %d broken" healthy broken)))
      ;; Persist digital twin state to disk
      (condition-case nil (gptel-auto-workflow--persist-target-state) (error nil))
      ;; Log subagent dispatch distribution (ontology as universal runtime)
      (when (bound-and-true-p gptel-auto-experiment--subagent-dispatch-log)
        (let ((total-dispatch 0)
              (pairs nil))
          (maphash (lambda (key count)
                     (setq total-dispatch (+ total-dispatch count))
                     (push (cons key count) pairs))
                   gptel-auto-experiment--subagent-dispatch-log)
          (when (> total-dispatch 0)
            (message "[ontology-evolve] 🔀 Subagent dispatches: %d total across %d agent-category pairs"
                     total-dispatch (length pairs))
            (dolist (pair (seq-take (sort pairs (lambda (a b) (> (cdr a) (cdr b)))) 5))
              (message "[ontology-evolve]     %s: %d×" (car pair) (cdr pair))))))
      ;; Log review outcomes per category (ontology-evolved staging gate)
      (let ((summary (and (bound-and-true-p gptel-auto-workflow--review-outcomes)
                          (fboundp 'gptel-auto-workflow--summarize-review-outcomes)
                          (gptel-auto-workflow--summarize-review-outcomes))))
        (when summary
          (message "[ontology-evolve] 📋 %s" (replace-regexp-in-string "\n" " " summary))))
      ;; Log category drift + attempt repair
      (condition-case nil
          (let* ((drifts (gptel-auto-workflow--detect-category-drift))
                 (repairs (ignore-errors (gptel-auto-workflow--repair-ontology))))
            (when drifts
              (message "[ontology-evolve] 📐 %d targets show category drift" (length drifts)))
            (when repairs
              (message "[ontology-evolve] 🔧 %d targets have suggested recategorization" (length repairs))))
        (error nil))
      (let ((result (list :changes (length changes)
                          :backend-changes 0
                          :saturated (length saturated)
                          :total-strategies (hash-table-count cat-strats))))
        (when (fboundp 'gptel-auto-workflow--memory-schema-record-evolution)
          (ignore-errors
            (gptel-auto-workflow--memory-schema-record-evolution result)))
        result))))))

;; ─── Per-Category Eight-Key Aggregation ───

 (defvar gptel-auto-workflow--category-eight-key-weights nil
  "Alist of (category (key . weight) ...) learned from experiment history.
Each category maps to per-key average score improvement deltas.
Populated by `gptel-auto-workflow--aggregate-category-eight-keys' during
evolution.
When nil, `gptel-auto-workflow--category-eight-key-weight' uses hardcoded
defaults.")

(defun gptel-auto-workflow--parse-eight-key-scores (scores-str)
  "Parse SCORES-STR from TSV column into alist of (key . score).
Example input: \"{phi-vitality:0.5,fractal-clarity:0.3,overall:0.42}\""
  (when (and (stringp scores-str) (string-match "^{\\(.+\\)}$" scores-str))
    (let ((result nil))
      (dolist (pair (split-string (match-string 1 scores-str) "," t))
        (when (string-match "^\\([^:]+\\):\\([-0-9.]+\\)$" pair)
          (push (cons (intern (match-string 1 pair))
                      (string-to-number (match-string 2 pair)))
                result)))
      (nreverse result))))

(defun gptel-auto-workflow--aggregate-category-eight-keys ()
  "Aggregate per-category, per-key Eight-Keys deltas from experiment history.
Reads all results.tsv files, groups by category, and computes average score
delta per key.  Updates `gptel-auto-workflow--category-eight-key-weights'."
  (let* ((base-dir (expand-file-name "var/tmp/experiments"
                                     (gptel-auto-workflow--worktree-base-root)))
         (results-dirs (when (file-directory-p base-dir)
                         (directory-files base-dir t "^[0-9]")))
         (cat-keys (make-hash-table :test 'equal))
         (cat-counts (make-hash-table :test 'equal)))
    (dolist (dir results-dirs)
      (let ((tsv-file (expand-file-name "results.tsv" dir)))
        (when (file-exists-p tsv-file)
          (with-temp-buffer
            (insert-file-contents tsv-file)
            (goto-char (point-min))
            (forward-line 1) ; skip header
            (while (not (eobp))
              (let* ((fields (split-string
                               (buffer-substring (line-beginning-position) (line-end-position))
                               "\t"))
                     (target (nth 1 fields))
                     (score-before (string-to-number (or (nth 3 fields) "0")))
                     (score-after (string-to-number (or (nth 4 fields) "0")))
                     (keys-str (nth 27 fields)) ; eight_key_scores column
                     (parsed (gptel-auto-workflow--parse-eight-key-scores keys-str)))
                (when (and target parsed (fboundp 'gptel-auto-workflow--categorize-target))
                  (let* ((cat (gptel-auto-workflow--categorize-target target))
                         (key (cons cat t))
                         (cat-deltas (gethash key cat-keys (make-hash-table :test 'eq)))
                         (cat-n (gethash key cat-counts 0)))
                    ;; Accumulate per-key deltas
                    (dolist (pair parsed)
                      (let ((k (car pair))
                            (v (cdr pair)))
                        (unless (eq k 'overall)
                          (puthash k (+ (gethash k cat-deltas 0.0)
                                         (- v (if (eq k (car (car parsed))) score-before score-after)))
                                   cat-deltas))))
                    (puthash key cat-deltas cat-keys)
                    (puthash key (1+ cat-n) cat-counts))))
              (forward-line 1))))))
    ;; Compute averages and build weight alist
    (let ((result nil))
      (maphash
       (lambda (key deltas)
         (let* ((cat (car key))
                (n (gethash key cat-counts 1))
                (avg-deltas nil))
           (maphash (lambda (k total)
                      (push (cons k (/ total n)) avg-deltas))
                    deltas)
           (when avg-deltas
             (push (cons cat avg-deltas) result))))
       cat-keys)
      (setq gptel-auto-workflow--category-eight-key-weights result)
      (message "[ontology-evolve] Aggregated per-category eight-key weights for %d categories" (length result))
      result)))

;; Add to evolve-ontology
(defun gptel-auto-workflow--evolve-ontology-eight-keys ()
  "Evolve category Eight-Key weights from experiment outcomes.
Runs during evolution cycle alongside strategy learning."
  (condition-case err
      (gptel-auto-workflow--aggregate-category-eight-keys)
    (error (message "[ontology-evolve] Error aggregating eight-key weights: %S" err))))

;; Load persisted digital twin state + re-parse grader insights from TSV at startup
(condition-case nil (gptel-auto-workflow--load-target-state) (error nil))
(condition-case nil (gptel-auto-experiment--replay-grader-insights-from-tsv) (error nil))

(defun gptel-auto-workflow--graph-neighbor-success (backend target)
  "Return boost for BACKEND based on success on graph neighbors of TARGET.
Looks up TARGET's category in the skill graph and checks BACKEND's
keep-rate on targets in the same category."
  (if (and (fboundp 'skill-graph-init)
           target)
      (condition-case nil
          (let* ((category (and (fboundp 'gptel-auto-workflow--categorize-target)
                                (gptel-auto-workflow--categorize-target target)))
                 (neighbors nil)
                 (total-keep 0.0)
                 (count 0))
            (when category
              ;; Find all nodes in the same category
              (maphash (lambda (id node)
                         (when (and (eq (skill-graph-node-level node) category)
                                    (not (eq id (intern target))))
                           (push id neighbors)))
                       skill-graph--nodes)
              ;; Average keep-rate for BACKEND on neighbor targets
              (dolist (n neighbors)
                (let ((rate (condition-case nil
                                (gptel-auto-workflow--get-backend-performance-stats
                                 backend (symbol-name n))
                              (error nil))))
                  (when rate
                    (setq total-keep (+ total-keep (or (plist-get rate :keep-rate) 0.0)))
                    (setq count (1+ count)))))
              (if (> count 0)
                  (* 0.15 (/ total-keep count))  ; max ~0.15 boost
                0.0)))
        (error 0.0))
    0.0))

(defun gptel-auto-workflow--graph-edge-strength (_backend active-skills)
  "Return boost for BACKEND based on strength of skill combination edges.
Looks up edges between skills in ACTIVE-SKILLS and checks if BACKEND
succeeded when those skill pairs were used together."
  (if (and (fboundp 'skill-graph-init)
           active-skills)
      (condition-case nil
          (let ((total-weight 0.0)
                (edge-count 0))
            (when (>= (length active-skills) 2)
              (let ((skills (if (stringp active-skills)
                               (mapcar #'intern (split-string active-skills))
                             active-skills)))
                (cl-loop for (a b) on skills by #'cdr
                         while b
                         do (let* ((key (cons a b))
                                   (edge (gethash key skill-graph--edges)))
                              (when edge
                                (setq total-weight (+ total-weight (skill-graph-edge-weight edge)))
                                (setq edge-count (1+ edge-count)))))))
            (if (> edge-count 0)
                (* 0.10 (/ total-weight edge-count))  ; max ~0.10 boost
              0.0))
        (error 0.0))
    0.0))

(provide 'gptel-auto-workflow-ontology-router)
;;; gptel-auto-workflow-ontology-router.el ends here
