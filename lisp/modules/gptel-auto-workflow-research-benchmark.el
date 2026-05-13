;;; gptel-auto-workflow-research-benchmark.el --- Benchmark research strategies -*- lexical-binding: t; -*-

;; Reuse benchmark infrastructure for AutoTTS-style research evolution.
;; Treats research sessions as benchmark experiments with strategy comparison.

;;; Commentary:
;; Instead of building separate AutoTTS system, reuse existing benchmark:
;; - gptel-benchmark-call-subagent for researcher calls
;; - Eight Keys scoring for research quality
;; - TSV results for replay store
;; - Strategy harness for strategy evolution

;;; Code:

(require 'cl-lib)

(defvar gptel-auto-workflow--research-strategies
  '("own-repos-first" "deep-external" "quick-own-only" "topic-specific")
  "Available research strategies to benchmark.")

(defvar gptel-auto-workflow--research-benchmark-results nil
  "Accumulator for research benchmark results.")

(defun gptel-auto-workflow--benchmark-research-strategy (strategy topic callback)
  "Benchmark single research STRATEGY on TOPIC.
Calls CALLBACK with result plist."
  (let* ((strategy-prompt (gptel-auto-workflow--format-research-strategy-prompt strategy topic))
         (start-time (float-time)))
    (message "[research-benchmark] Testing strategy '%s' on topic '%s'" strategy topic)
    (gptel-benchmark-call-subagent
     'researcher
     (format "Research benchmark: %s" strategy)
     strategy-prompt
     (lambda (result)
       (let* ((duration (- (float-time) start-time))
              (output (if (stringp result) result (format "%s" result)))
              (output-len (length output))
              (tokens (* output-len 0.25))
              (quality (gptel-auto-workflow--score-research-output output))
              (efficiency (/ quality (max tokens 1))))
         (message "[research-benchmark] %s: quality=%.2f tokens=%.0f efficiency=%.4f"
                  strategy quality tokens efficiency)
         (funcall callback
                  (list :strategy strategy
                        :topic topic
                        :quality quality
                        :tokens tokens
                        :efficiency efficiency
                        :duration duration
                        :output-len output-len
                        :output output)))))))

(defun gptel-auto-workflow--score-research-output (output)
  "Score research output quality (0-1).
Uses heuristics based on AutoTTS paper:
- URLs present = higher score
- Structured format = higher score
- Specific techniques = higher score
- No generic advice = higher score"
  (let ((score 0.0))
    (when (string-match-p "https?://" output)
      (setq score (+ score 0.2)))
    (when (string-match-p "## .*\\n" output)
      (setq score (+ score 0.2)))
    (when (string-match-p "```" output)
      (setq score (+ score 0.2)))
    (when (string-match-p "\\*\\*" output)
      (setq score (+ score 0.15)))
    (let ((len (length output)))
      (cond ((> len 3000) (setq score (+ score 0.15)))
            ((> len 1000) (setq score (+ score 0.1)))
            (t (setq score (+ score 0.05)))))
    (unless (string-match-p "use AI\\|improve code\\|better" output)
      (setq score (+ score 0.1)))
    score))

(defun gptel-auto-workflow--format-research-strategy-prompt (strategy topic)
  "Format research prompt with specific STRATEGY for TOPIC."
  (let ((strategy-guidance (gptel-auto-workflow--load-strategy-as-text strategy)))
    (format "## Research Task\n\nTopic: %s\nStrategy: %s\n\n%s\n\n## Instructions\n\n1. Follow the strategy phases EXACTLY\n2. Track your confidence after each phase (0-1)\n3. Stop early if confidence > 0.7 and you have 2+ insights\n4. Return structured output with URLs and code examples\n5. END your response with JSON metadata:\n```json\n{\n  \"strategy_used\": \"%s\",\n  \"phases_completed\": [\"search\", \"fetch\"],\n  \"confidence_final\": 0.8,\n  \"insights_count\": 3,\n  \"tokens_estimate\": 3500\n}\n```"
            topic strategy strategy-guidance strategy)))

(defun gptel-auto-workflow--load-strategy-as-text (strategy)
  "Load strategy definition as text guidance."
  (let ((strategy-file (expand-file-name
                        (format "assistant/skills/researcher-prompt/strategies/%s.json"
                                strategy)
                        (gptel-auto-workflow--worktree-base-root))))
    (if (file-exists-p strategy-file)
        (with-temp-buffer
          (insert-file-contents strategy-file)
          (let ((data (json-read)))
            (format "**Strategy**: %s\n**Description**: %s\n**Phases**: %s"
                    (cdr (assoc 'name data))
                    (cdr (assoc 'description data))
                    (mapconcat (lambda (p) (cdr (assoc 'name p)))
                               (cdr (assoc 'phases data)) " → "))))
      (format "Strategy '%s' not found. Use default approach." strategy))))

(defun gptel-auto-workflow--benchmark-all-research-strategies (topic callback)
  "Benchmark all research strategies on TOPIC.
Calls CALLBACK with best strategy name."
  (setq gptel-auto-workflow--research-benchmark-results nil)
  (let ((strategies gptel-auto-workflow--research-strategies)
        (results nil)
        (remaining 0))
    (setq remaining (length strategies))
    (dolist (strategy strategies)
      (gptel-auto-workflow--benchmark-research-strategy
       strategy topic
       (lambda (result)
         (push result results)
         (setq remaining (1- remaining))
         (when (<= remaining 0)
           (let* ((best (car (sort results
                                   (lambda (a b)
                                     (> (plist-get a :efficiency)
                                        (plist-get b :efficiency))))))
                  (best-strategy (plist-get best :strategy)))
             (message "[research-benchmark] Best strategy: %s (efficiency=%.4f)"
                      best-strategy (plist-get best :efficiency))
             (setq gptel-auto-workflow--research-benchmark-results results)
             (funcall callback best-strategy))))))))

(defun gptel-auto-workflow--evolve-research-strategy ()
  "Evolve research strategy using benchmark results.
Runs after pipeline completes to pick best strategy for next run."
  (when gptel-auto-workflow--research-benchmark-results
    (let* ((results gptel-auto-workflow--research-benchmark-results)
           (strategies (make-hash-table :test 'equal)))
      (dolist (r results)
        (let* ((name (plist-get r :strategy))
               (existing (gethash name strategies '(0 0 0))))
          (puthash name
                   (list (+ (nth 0 existing) (plist-get r :quality))
                         (+ (nth 1 existing) (plist-get r :tokens))
                         (1+ (nth 2 existing)))
                   strategies)))
      (let ((best nil)
            (best-score 0))
        (maphash (lambda (name stats)
                   (let ((avg-quality (/ (nth 0 stats) (nth 2 stats)))
                         (avg-tokens (/ (nth 1 stats) (nth 2 stats)))
                         (score (/ (nth 0 stats) (max (nth 1 stats) 1))))
                     (when (> score best-score)
                       (setq best name
                             best-score score))
                     (message "[research-evolve] %s: avg-quality=%.2f avg-tokens=%.0f score=%.4f"
                              name avg-quality avg-tokens score)))
                 strategies)
        (when best
          (message "[research-evolve] Evolved to strategy: %s" best)
          (setq gptel-auto-workflow--active-strategy best))))))

(defun gptel-auto-workflow--load-research-traces ()
  "Load all research traces from trace directory.
Returns list of trace plists."
  (let ((trace-dir (expand-file-name "var/tmp/research-traces"
                                     (gptel-auto-workflow--worktree-base-root)))
        (traces nil))
    (when (file-directory-p trace-dir)
      (dolist (file (directory-files trace-dir t "\\.json$"))
        (condition-case err
            (let ((json-object-type 'plist))
              (with-temp-buffer
                (insert-file-contents file)
                (push (json-read) traces)))
          (error (message "[autotts] Failed to load trace %s: %s"
                         (file-name-nondirectory file) err)))))
    traces))

(defun gptel-auto-workflow--evolve-controller-from-traces (traces)
  "AutoTTS-style controller evolution from research traces.
Analyzes traces to update controller parameters.
TRACES is list of trace plists."
  (let ((own-repo-success 0)
        (own-repo-total 0)
        (external-success 0)
        (external-total 0)
        (total-tokens 0)
        (total-output 0))
    (dolist (trace traces)
      (let ((source (plist-get trace :source))
            (output-length (or (plist-get trace :output-length) 0))
            (tokens-used (or (plist-get trace :tokens-used) 0))
            (has-urls (plist-get trace :has-urls))
            (confidence (or (plist-get trace :confidence) 0)))
        (setq total-tokens (+ total-tokens tokens-used))
        (setq total-output (+ total-output output-length))
        (cond
         ((string= source "own-repo")
          (setq own-repo-total (1+ own-repo-total))
          (when (and has-urls (> output-length 1000))
            (setq own-repo-success (1+ own-repo-success))))
         (t
          (setq external-total (1+ external-total))
          (when (and has-urls (> output-length 1000))
            (setq external-success (1+ external-success)))))))
    ;; Calculate new priorities based on success rates
    (let* ((own-rate (if (> own-repo-total 0)
                        (/ (float own-repo-success) own-repo-total)
                      0.5))
           (external-rate (if (> external-total 0)
                             (/ (float external-success) external-total)
                           0.3))
           (avg-output (if (> (length traces) 0)
                          (/ (float total-output) (length traces))
                        2000))
           ;; Evolve controller config
           (new-config
            (list
             :own-repo-priority (min 0.95 (+ 0.7 (* 0.25 own-rate)))
             :fork-priority 0.4
             :external-priority (max 0.05 (+ 0.15 (* 0.15 external-rate)))
             :web-priority 0.05
             :min-confidence-stop (if (> avg-output 2500) 0.65 0.75)
             :max-tokens-budget 8000
             :min-insights-for-stop 2
             :stagnation-window 2
             :evolved-at (format-time-string "%Y-%m-%dT%H:%M:%SZ")
             :based-on-traces (length traces)
             :own-repo-stats (list :success own-repo-success :total own-repo-total
                                  :rate own-rate)
             :external-stats (list :success external-success :total external-total
                                   :rate external-rate))))
      (message "[autotts] Controller evolution: own-repo %.0f%% (%d/%d), external %.0f%% (%d/%d)"
               (* 100 own-rate) own-repo-success own-repo-total
               (* 100 external-rate) external-success external-total)
      new-config)))

(defun gptel-auto-workflow--save-evolved-controller (controller-config)
  "Save evolved controller configuration to disk.
CONTROLLER-CONFIG is a plist with controller parameters."
  (let ((controller-file (expand-file-name "var/tmp/researcher-controller.json"
                                          (gptel-auto-workflow--worktree-base-root))))
    (make-directory (file-name-directory controller-file) t)
    (with-temp-file controller-file
      (insert (json-encode controller-config)))
    (message "[autotts] Saved evolved controller: %s" controller-file)))

(defvar gptel-auto-workflow--controller-evolution-history nil
  "List of past controller evolution records.
Each record is a plist: (:timestamp :objective :config :traces-count).
Used for convergence detection to prevent overfitting.
Loaded from disk at startup, saved after each evolution.")

(defcustom gptel-auto-workflow-convergence-window 3
  "Number of generations to look back for convergence detection.
If objective hasn't improved in this many generations, evolution stops.
AutoTTS: Prevents overfitting controller to historical traces."
  :type 'integer
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-convergence-threshold 0.01
  "Minimum improvement threshold to consider evolution meaningful.
If objective improvement is below this, count as plateau.
AutoTTS: Ignore tiny fluctuations that don't represent real progress."
  :type 'float
  :group 'gptel-tools-agent)

(defun gptel-auto-workflow--load-evolution-history ()
  "Load evolution history from disk.
Returns list of evolution records."
  (let ((history-file (expand-file-name "var/tmp/controller-evolution-history.json"
                                        (gptel-auto-workflow--worktree-base-root))))
    (if (file-exists-p history-file)
        (condition-case err
            (with-temp-buffer
              (insert-file-contents history-file)
              (let ((json-object-type 'plist))
                (json-read)))
          (error
           (message "[autotts] Failed to load evolution history: %s" err)
           nil))
      nil)))

(defun gptel-auto-workflow--save-evolution-history (history)
  "Save evolution HISTORY to disk."
  (let ((history-file (expand-file-name "var/tmp/controller-evolution-history.json"
                                        (gptel-auto-workflow--worktree-base-root))))
    (make-directory (file-name-directory history-file) t)
    (with-temp-file history-file
      (insert (json-encode history)))
    (message "[autotts] Saved evolution history: %d generations" (length history))))

(defun gptel-auto-workflow--calculate-evolution-objective (traces config)
  "Calculate objective value for evolution from TRACES and CONFIG.
Higher is better. Combines:
- Source success rates (weighted by priorities)
- Average confidence
- Token efficiency (output per token)
- Trace diversity (own-repo vs external balance)"
  (let ((own-success 0)
        (own-total 0)
        (ext-success 0)
        (ext-total 0)
        (total-confidence 0)
        (total-tokens 0)
        (total-output 0))
    (dolist (trace traces)
      (let ((source (plist-get trace :source))
            (output-length (or (plist-get trace :output-length) 0))
            (tokens (or (plist-get trace :tokens-used) 1))
            (confidence (or (plist-get trace :confidence) 0))
            (has-urls (plist-get trace :has-urls)))
        (setq total-confidence (+ total-confidence confidence))
        (setq total-tokens (+ total-tokens tokens))
        (setq total-output (+ total-output output-length))
        (if (string= source "own-repo")
            (progn
              (setq own-total (1+ own-total))
              (when (and has-urls (> output-length 1000))
                (setq own-success (1+ own-success))))
          (setq ext-total (1+ ext-total))
          (when (and has-urls (> output-length 1000))
            (setq ext-success (1+ ext-success))))))
    (let* ((own-rate (if (> own-total 0) (/ (float own-success) own-total) 0))
           (ext-rate (if (> ext-total 0) (/ (float ext-success) ext-total) 0))
           (avg-confidence (if (> (length traces) 0) (/ (float total-confidence) (length traces)) 0))
           (token-efficiency (if (> total-tokens 0) (/ (float total-output) total-tokens) 0))
           (own-priority (or (plist-get config :own-repo-priority) 0.7))
           (ext-priority (or (plist-get config :external-priority) 0.15))
           ;; Weighted objective: prioritize high success rate on high-priority sources
           (objective (+ (* own-rate own-priority 2.0)
                        (* ext-rate ext-priority 1.0)
                        (* avg-confidence 0.5)
                        (* (min token-efficiency 2.0) 0.25))))
      (message "[autotts] Objective: own=%.2f ext=%.2f conf=%.2f eff=%.2f → %.3f"
               own-rate ext-rate avg-confidence token-efficiency objective)
      objective)))

(defun gptel-auto-workflow--detect-convergence (history new-objective)
  "Detect if evolution has converged (plateaued).
HISTORY is list of past evolution records.
NEW-OBJECTIVE is the current generation's objective.
Returns t if converged (should stop evolving), nil otherwise.
AutoTTS: Stop evolution when no meaningful improvement for N generations."
  (let ((window gptel-auto-workflow-convergence-window)
        (threshold gptel-auto-workflow-convergence-threshold))
    (if (< (length history) window)
        ;; Not enough history yet
        (progn
          (message "[autotts] Convergence: insufficient history (%d < %d)"
                   (length history) window)
          nil)
      ;; Check last N generations for improvement
      (let* ((recent (last history window))
             (best-in-window (apply #'max
                                    (mapcar (lambda (r)
                                              (or (plist-get r :objective) 0))
                                            recent)))
             (improvement (- new-objective best-in-window)))
        (if (> improvement threshold)
            (progn
              (message "[autotts] Convergence: improving (+%.4f > %.4f)"
                       improvement threshold)
              nil)
          (progn
            (message "[autotts] Convergence: PLATEAU detected (%.4f ≤ %.4f over %d gens). Stopping evolution."
                     improvement threshold window)
            t))))))

(defun gptel-auto-workflow--record-evolution (history objective config traces-count)
  "Record evolution generation to HISTORY.
Returns updated history list."
  (let ((record (list :timestamp (format-time-string "%Y-%m-%dT%H:%M:%SZ")
                      :objective objective
                      :config config
                      :traces-count traces-count)))
    (append history (list record))))

(defun gptel-auto-workflow--run-autotts-evolution ()
  "Run full AutoTTS-style evolution cycle with convergence detection.
1. Load traces
2. Check convergence (skip if plateaued)
3. Evolve controller from traces
4. Save evolved controller
5. Record evolution history
6. Update active strategy from benchmark results."
  (message "[autotts] Starting evolution cycle...")
  ;; Step 1: Load traces
  (let* ((traces (gptel-auto-workflow--load-research-traces))
         (history (gptel-auto-workflow--load-evolution-history)))
    (message "[autotts] Loaded %d traces, %d past generations"
             (length traces) (length history))
    (when traces
      ;; Step 2: Check convergence BEFORE evolving
      (let* ((current-config (gptel-auto-workflow--load-autotts-controller))
             (current-objective (gptel-auto-workflow--calculate-evolution-objective
                                 traces current-config)))
        (if (gptel-auto-workflow--detect-convergence history current-objective)
            (message "[autotts] Evolution converged. Skipping to prevent overfit.")
          ;; Step 3: Evolve controller
          (let ((new-config (gptel-auto-workflow--evolve-controller-from-traces traces)))
            ;; Step 4: Calculate new objective
            (let ((new-objective (gptel-auto-workflow--calculate-evolution-objective
                                  traces new-config)))
              ;; Step 5: Save controller
              (gptel-auto-workflow--save-evolved-controller new-config)
              ;; Step 6: Record evolution
              (setq history (gptel-auto-workflow--record-evolution
                             history new-objective new-config (length traces)))
              (gptel-auto-workflow--save-evolution-history history)
              ;; Step 7: Joint optimization - update SKILL.md with evolved controller
              (gptel-auto-workflow--update-skill-with-controller new-config)
              ;; Step 8: Update active strategy from offline benchmark (0 LLM calls)
              ;; Uses trace replay instead of expensive LLM-based benchmark
              (gptel-auto-workflow--run-offline-evolution)
              ;; Step 9: Generate knowledge synthesis
              (gptel-auto-workflow--synthesize-research-knowledge traces))))))))

(defun gptel-auto-workflow--synthesize-research-knowledge (traces)
  "Self-evolution layer: synthesize knowledge from traces.
Extract topic performance and source effectiveness."
  (let ((topic-perf (make-hash-table :test 'equal))
        (source-perf (make-hash-table :test 'equal)))
    (dolist (trace traces)
      (let ((strategy (plist-get trace :strategy))
            (source (plist-get trace :source))
            (output-length (or (plist-get trace :output-length) 0))
            (confidence (or (plist-get trace :confidence) 0)))
        ;; Track strategy performance
        (let ((existing (gethash strategy topic-perf '(0 0 0))))
          (puthash strategy
                   (list (+ (nth 0 existing) (if (> output-length 1000) 1 0))
                         (+ (nth 1 existing) 1)
                         (+ (nth 2 existing) confidence))
                   topic-perf))
        ;; Track source performance
        (let ((existing (gethash source source-perf '(0 0 0))))
          (puthash source
                   (list (+ (nth 0 existing) (if (> output-length 1000) 1 0))
                         (+ (nth 1 existing) 1)
                         (+ (nth 2 existing) confidence))
                   source-perf))))
    ;; Log synthesis
    (message "[autotts] Knowledge synthesis:")
    (message "[autotts]  Strategies:")
    (maphash (lambda (name stats)
               (let ((rate (if (> (nth 1 stats) 0)
                              (/ (float (nth 0 stats)) (nth 1 stats))
                            0)))
                 (message "[autotts]    %s: %.0f%% success (%d/%d)"
                          name (* 100 rate) (nth 0 stats) (nth 1 stats))))
             topic-perf)
    (message "[autotts]  Sources:")
    (maphash (lambda (name stats)
               (let ((rate (if (> (nth 1 stats) 0)
                              (/ (float (nth 0 stats)) (nth 1 stats))
                            0)))
                 (message "[autotts]    %s: %.0f%% success (%d/%d)"
                          name (* 100 rate) (nth 0 stats) (nth 1 stats))))
              source-perf)))

(defun gptel-auto-workflow--update-skill-with-controller (controller-config)
  "Update researcher SKILL.md with evolved CONTROLLER-CONFIG.
Joint optimization: merge controller priorities into skill prompt
so researcher sees evolved guidance in real-time.
Called after controller evolution to keep skill + controller in sync."
  (let ((skill-file (expand-file-name
                     "assistant/skills/researcher-prompt/SKILL.md"
                     (gptel-auto-workflow--worktree-base-root))))
    (when (file-exists-p skill-file)
      (condition-case err
          (let* ((skill-content (with-temp-buffer
                                  (insert-file-contents skill-file)
                                  (buffer-string)))
                 ;; Build updated strategy guidance from controller config
                 (own-priority (* 100 (or (plist-get controller-config :own-repo-priority) 0.7)))
                 (ext-priority (* 100 (or (plist-get controller-config :external-priority) 0.15)))
                 (stop-threshold (* 100 (or (plist-get controller-config :min-confidence-stop) 0.7)))
                 (budget (or (plist-get controller-config :max-tokens-budget) 8000))
                 (evolved-at (or (plist-get controller-config :evolved-at) "unknown"))
                 (based-on (or (plist-get controller-config :based-on-traces) 0))
                 (new-guidance
                  (format "**Evolved Controller Config** (updated %s from %d traces):\n\n- Own repo priority: %.0f%%\n- External priority: %.0f%%\n- Stop threshold: %.0f%% confidence\n- Token budget: %d\n\n**Decision Rules**:\n1. If confidence > %.0f%% + have URLs → STOP early\n2. If output < 1000 chars → CONTINUE searching\n3. If > %d tokens → CUT (return what you have)\n4. Check own repos (davidwuchn/*) FIRST before external\n\n*This guidance auto-evolves after each pipeline run.*"
                          evolved-at based-on
                          own-priority ext-priority
                          stop-threshold budget
                          stop-threshold budget)))
            ;; Replace strategy guidance section
            (let ((updated-content
                   (if (string-match "{{strategy-guidance}}" skill-content)
                       (replace-match new-guidance t t skill-content)
                     ;; If no template var, append before Instructions section
                     (if (string-match "## Instructions" skill-content)
                         (replace-match
                          (concat "## Strategy Guidance (Auto-Evolved)\n\n" new-guidance "\n\n## Instructions")
                          t t skill-content)
                       skill-content))))
              (with-temp-file skill-file
                (insert updated-content))
              (message "[autotts] Updated SKILL.md with evolved controller (own=%.0f%% ext=%.0f%%)"
                       own-priority ext-priority)))
        (error
         (message "[autotts] Failed to update SKILL.md: %s" err))))))

;;; ─── Offline Trace Replay Benchmark (0 LLM calls) ───

(defun gptel-auto-workflow--offline-benchmark-strategies ()
  "Benchmark all strategies offline against historical traces.
AutoTTS Replay Store: evaluates strategies without LLM calls.
Scores each trace as if produced by different strategies.
Returns list of strategy performance plists.
Faster than `benchmark-all-research-strategies` which calls LLMs."
  (let ((traces (gptel-auto-workflow--load-research-traces))
        (strategies gptel-auto-workflow--research-strategies)
        (results nil))
    (message "[autotts] Offline benchmark: %d traces, %d strategies"
             (length traces) (length strategies))
    (dolist (strategy strategies)
      (let ((strategy-score 0.0)
            (strategy-tokens 0)
            (trace-count 0))
        (dolist (trace traces)
          (let* ((source (plist-get trace :source))
                 (output-len (or (plist-get trace :output-length) 0))
                 (tokens (or (plist-get trace :tokens-used) 1))
                 (has-urls (plist-get trace :has-urls))
                 (confidence (or (plist-get trace :confidence) 0))
                 (step-count (or (plist-get trace :step-count) 1))
                 ;; Simulate strategy behavior on this trace
                 (simulated-quality
                  (cond
                   ;; own-repos-first: high score for own-repo traces
                   ((string= strategy "own-repos-first")
                    (if (string= source "own-repo")
                        (+ 0.4 (* confidence 0.4) (if has-urls 0.2 0))
                      (+ 0.1 (* confidence 0.2) (if has-urls 0.1 0))))
                   ;; deep-external: high score for external traces with depth
                   ((string= strategy "deep-external")
                    (if (string= source "external")
                        (+ 0.3 (* confidence 0.3) (if has-urls 0.2 0) (* step-count 0.02))
                      (+ 0.2 (* confidence 0.3) (if has-urls 0.1 0))))
                   ;; quick-own-only: only own-repo, penalize external
                   ((string= strategy "quick-own-only")
                    (if (string= source "own-repo")
                        (+ 0.5 (* confidence 0.3) (if has-urls 0.2 0))
                      0.05))
                   ;; topic-specific: assume medium performance everywhere
                   (t
                    (+ 0.25 (* confidence 0.3) (if has-urls 0.15 0))))))
            (setq strategy-score (+ strategy-score simulated-quality))
            (setq strategy-tokens (+ strategy-tokens tokens))
            (setq trace-count (1+ trace-count))))
        ;; Calculate efficiency
        (let ((avg-quality (if (> trace-count 0) (/ strategy-score trace-count) 0))
              (avg-tokens (if (> trace-count 0) (/ strategy-tokens trace-count) 1)))
          (push (list :strategy strategy
                      :quality avg-quality
                      :tokens avg-tokens
                      :efficiency (/ avg-quality (max avg-tokens 1))
                      :traces trace-count
                      :offline t)
                results)
          (message "[autotts] Offline: %s quality=%.2f tokens=%.0f efficiency=%.4f (%d traces)"
                   strategy avg-quality avg-tokens
                   (/ avg-quality (max avg-tokens 1)) trace-count))))
    ;; Sort by efficiency
    (setq results (sort results
                        (lambda (a b)
                          (> (plist-get a :efficiency)
                             (plist-get b :efficiency)))))
    (message "[autotts] Offline benchmark complete. Best: %s"
             (plist-get (car results) :strategy))
    results))

;;; ─── Trace Outcome Tracking (Reward Signal Bridge) ───

(defun gptel-auto-workflow--update-trace-outcomes (experiment)
  "Update trace files with experiment outcome.
EXPERIMENT is a plist with :research-hash and :kept fields.
Called from experiment logging to link research → experiment results."
  (let ((research-hash (plist-get experiment :research-hash))
        (kept (plist-get experiment :kept))
        (target (plist-get experiment :target))
        (score-after (plist-get experiment :score-after)))
    (when (and research-hash (not (equal research-hash "none")))
      (let ((trace-dir (expand-file-name "var/tmp/research-traces"
                                          (gptel-auto-workflow--worktree-base-root)))
            (updated nil))
        (when (file-directory-p trace-dir)
          (dolist (file (directory-files trace-dir t "\\.json$"))
            (when (and (not updated)
                       (string-match-p research-hash (file-name-nondirectory file)))
              (condition-case err
                  (let ((json-object-type 'plist))
                    (with-temp-buffer
                      (insert-file-contents file)
                      (let* ((trace (json-read))
                             (outcomes (plist-get trace :outcomes))
                             (new-outcome
                              (list :target target
                                    :kept (if kept t nil)
                                    :score-after (or score-after 0)
                                    :timestamp (format-time-string "%Y-%m-%dT%H:%M:%SZ"))))
                        (setq trace (plist-put trace :outcomes
                                               (append (or outcomes nil)
                                                       (list new-outcome))))
                        (erase)
                        (insert (json-encode trace))
                        (write-region (point-min) (point-max) file))
                      (message "[autotts] Linked trace %s → %s (%s)"
                               research-hash target (if kept "kept" "discarded"))
                      (setq updated t)))
                (error
                 (message "[autotts] Failed to update trace outcome: %s" err))))))))))

(defvar gptel-auto-workflow--trace-outcome-hooks nil
  "List of functions to call when trace outcomes are updated.
Each function receives the updated trace plist.")

(defun gptel-auto-workflow--run-offline-evolution ()
  "Run lightweight offline evolution using trace replay.
No LLM calls. Fast. Good for convergence testing.
Updates active strategy from offline benchmark results."
  (message "[autotts] Running offline evolution (no LLM calls)...")
  (let ((results (gptel-auto-workflow--offline-benchmark-strategies)))
    (when results
      (let ((best (car results)))
        (setq gptel-auto-workflow--active-strategy
              (plist-get best :strategy))
        (message "[autotts] Offline evolved to strategy: %s (eff=%.4f)"
                 (plist-get best :strategy)
                 (plist-get best :efficiency))
        ;; Store results for joint optimization
        (setq gptel-auto-workflow--research-benchmark-results results)
        best))))

(provide 'gptel-auto-workflow-research-benchmark)

;;; gptel-auto-workflow-research-benchmark.el ends here
