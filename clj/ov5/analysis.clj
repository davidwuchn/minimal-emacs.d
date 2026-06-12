(ns ov5.analysis
  "Markov-chain pipeline statechart analysis against the Datahike store.
   Secondary analytics path — the primary 423-line Elisp statechart stays.
   Reads from the same Datahike schema defined in world_store.clj.

   Pipeline gates (11-gate Markov chain):
     roi-preflight → quota-precondition → executor → hypothesis-uniqueness
     → validation → grader → decision → complexity → commit → staging → merge

   Absorbing: :kept (passed all) and :discarded (abstract absorbing state)."
  (:require [ov5.world-store :as ws]))

;; ═══════════════════════════════════════════════════════════════════════════════
;; Schema Extension
;; ═══════════════════════════════════════════════════════════════════════════════

(def fail-gate-schema
  "Additional attribute to track which gate rejected each experiment."
  [{:db/ident       :experiment/fail-gate
    :db/valueType   :db.type/keyword
    :db/cardinality :db.cardinality/one}])

(defn ensure-schema
  "Ensure the :experiment/fail-gate attribute exists in the store.
   Idempotent — safe to call multiple times."
  []
  (when (ws/connected?)
    (try (ws/transact fail-gate-schema)
         (catch Exception _ nil))))

;; ═══════════════════════════════════════════════════════════════════════════════
;; Gate Definitions
;; ═══════════════════════════════════════════════════════════════════════════════

(def pipeline-gates
  "Ordered vector of pipeline gate names (transient states in the Markov chain)."
  [:roi-preflight
   :quota-precondition
   :executor
   :hypothesis-uniqueness
   :validation
   :grader
   :decision
   :complexity
   :commit
   :staging
   :merge])

(def decision->fail-gate
  "Map from decision label string to the gate keyword that rejected it.
   Matches the Elisp gptel-auto-workflow--decision-to-fail-gate mapping.
   Unknown decisions fall back to :executor."
  {"roi-below-threshold"           :roi-preflight
   "all-backends-quota-exhausted"  :quota-precondition
   "precondition-blocked"          :quota-precondition
   "api-error"                     :quota-precondition
   "tool-error"                    :quota-precondition
   "executor-timeout"              :executor
   "timeout"                       :executor
   "executor-prompt-empty"         :executor
   "executor-callback-missing"     :executor
   "empty-prompt"                  :executor
   "worktree-creation-failed"      :executor
   "duplicate-hypothesis"          :hypothesis-uniqueness
   "repeated-focus-symbol"         :hypothesis-uniqueness
   "inspection-thrash"             :hypothesis-uniqueness
   "validation-failed"             :validation
   "validation-hard-block"         :validation
   "grader-failed"                 :grader
   "grader-rejected"               :grader
   "retry-grade-rejected"          :grader
   "retry-grade-failed"            :grader
   "discarded"                     :decision
   "grader-bypass-commit-failed"   :commit
   "experiment-commit-failed"      :commit
   "scope-creep-blocked"           :staging
   "staging-flow-failed"           :staging
   "staging-merge-failed"          :staging
   "staging-verification-failed"   :staging
   "review-failed-max-retries"     :staging
   "optimize-push-failed"          :staging
   "fix-failed"                    :merge})

;; ═══════════════════════════════════════════════════════════════════════════════
;; Classification
;; ═══════════════════════════════════════════════════════════════════════════════

(defn classify-fail-gate
  "Return the gate keyword that rejected this decision, or nil if kept.
   `decision` may be a keyword or string.
   Unknown decisions fall back to :executor (matching Elisp behavior)."
  [decision]
  (let [s (if (keyword? decision) (name decision) (str decision))]
    (if (= s "kept")
      nil
      (get decision->fail-gate s :executor))))

;; ═══════════════════════════════════════════════════════════════════════════════
;; Core Statistics
;; ═══════════════════════════════════════════════════════════════════════════════

(defn- gate-accumulate
  "Reduce function: accumulate one experiment into per-gate counters.
   `acc` is the accumulator map; `exp` is an experiment entity.
   Returns updated accumulator."
  [acc exp]
  (let [decision      (:experiment/decision exp)
        decision-str  (if (keyword? decision) (name decision) (str decision))]
    (case decision-str
      ;; Passed all gates — increment :passed for every gate.
      "kept"
      (reduce (fn [a g] (update-in a [:gate-acc g :passed] inc))
              (update acc :kept inc)
              pipeline-gates)

      ;; Transient state — exclude from statistics entirely.
      "staging-pending"
      acc

      ;; All other rejection decisions — find the fail gate, mark prior gates
      ;; as passed, the fail gate as failed, and subsequent gates as unreached.
      (let [fail-gate (classify-fail-gate decision-str)
            acc'      (update acc :discarded inc)]
        (if fail-gate
          (let [gate-vec (vec pipeline-gates)
                fail-idx (.indexOf gate-vec fail-gate)]
            (if (neg? fail-idx)
              acc'   ;; safety: gate not found (shouldn't happen with :executor fallback)
              (reduce-kv (fn [a idx g]
                           (cond
                             (< idx fail-idx) (update-in a [:gate-acc g :passed] inc)
                             (= idx fail-idx) (update-in a [:gate-acc g :failed] inc)
                             :else             (update-in a [:gate-acc g :unreached] inc)))
                         acc'
                         gate-vec)))
          acc')))))

(defn- compute-gate-stats
  "Compute per-gate pass/fail statistics from a sequence of experiment entities.
   Returns the same map structure as statechart-stats."
  [exps]
  (let [exps     (or exps [])
        init-acc {:kept      0
                  :discarded 0
                  :gate-acc  (zipmap pipeline-gates
                                     (repeat {:passed    0
                                              :failed    0
                                              :unreached 0}))}
        acc      (reduce gate-accumulate init-acc exps)
        gates    (mapv (fn [g]
                         (let [{:keys [passed failed unreached]} (get-in acc [:gate-acc g])
                               entered (+ passed failed)
                               p-pass  (if (pos? entered)
                                         (double (/ passed entered))
                                         1.0)
                               p-fail  (- 1.0 p-pass)]
                           {:name      g
                            :entered   entered
                            :passed    passed
                            :failed    failed
                            :unreached unreached
                            :p-pass    p-pass
                            :p-fail    p-fail}))
                       pipeline-gates)
        keep-rate (double (reduce * 1 (map :p-pass gates)))]
    {:gates       gates
     :total       (count exps)
     :kept        (:kept acc)
     :discarded   (:discarded acc)
     :keep-rate   keep-rate
     :computed-at (java.util.Date.)}))

(defn statechart-stats
  "Compute per-gate pass/fail statistics from all experiments in the store.
   Returns a map: {:gates [{:name :gate :entered N :passed N :failed N
                             :unreached N :p-pass float} ...]
                   :total N :kept N :discarded N :keep-rate float
                   :computed-at inst}"
  []
  (if (ws/connected?)
    (compute-gate-stats (ws/all-experiments))
    {:gates       []
     :total       0
     :kept        0
     :discarded   0
     :keep-rate   0.0
     :computed-at (java.util.Date.)}))

;; ═══════════════════════════════════════════════════════════════════════════════
;; Analysis Functions
;; ═══════════════════════════════════════════════════════════════════════════════

(defn bottleneck
  "Return the gate with the lowest P(pass|gate), or nil if no gate data."
  []
  (let [gates (:gates (statechart-stats))]
    (when (seq gates)
      (:name (apply min-key :p-pass gates)))))

(def phi
  "Golden ratio constant for φ-test."
  1.618033988749895)

(defn phi-test
  "Test whether keep-rate follows φ-related decay: keep_rate_max ≈ φ^(-n/(n+1)).
   Returns {:phi 1.618 :n-gates 11 :phi-max float :actual float
            :deviation float :deviation-pct float}"
  []
  (let [stats         (statechart-stats)
        n-gates       (count pipeline-gates)
        phi-max       (Math/pow phi (/ (- n-gates) (inc n-gates)))
        actual        (:keep-rate stats)
        deviation     (- phi-max actual)
        deviation-pct (if (pos? phi-max)
                        (* 100.0 (/ deviation phi-max))
                        0.0)]
    {:phi           phi
     :n-gates       n-gates
     :phi-max       phi-max
     :actual        actual
     :deviation     deviation
     :deviation-pct deviation-pct}))

(def ^:private ms-per-day
  "Milliseconds in one day, for time-window calculations."
  (* 24 60 60 1000))

(defn- experiments-since
  "Return experiments from `exps` whose :experiment/timestamp is after `cutoff`."
  [exps cutoff]
  (filter (fn [e]
            (when-let [ts (:experiment/timestamp e)]
              (try (.after ts cutoff)
                   (catch Exception _ false))))
          exps))

(defn drift-check
  "Compare recent vs. historical p-pass per gate. Flag drops > 10 percentage points.
   `days-recent` — window size for current baseline (e.g., 7)
   `days-historical` — window size for historical baseline (e.g., 30)
   Returns {:drifted bool
            :drifted-gates [{:gate :name :current-p float :historical-p float
                             :delta float :alert str} ...]}"
  [days-recent days-historical]
  (if-not (ws/connected?)
    {:drifted false :drifted-gates []}
    (let [now-ms        (System/currentTimeMillis)
          recent-cutoff (java.util.Date. (- now-ms (* days-recent ms-per-day)))
          hist-cutoff   (java.util.Date. (- now-ms (* days-historical ms-per-day)))
          all-exps      (ws/all-experiments)
          recent-exps   (experiments-since all-exps recent-cutoff)
          hist-exps     (experiments-since all-exps hist-cutoff)
          recent-stats  (compute-gate-stats recent-exps)
          hist-stats    (compute-gate-stats hist-exps)
          recent-gm     (into {} (map (fn [g] [(:name g) g]) (:gates recent-stats)))
          hist-gm       (into {} (map (fn [g] [(:name g) g]) (:gates hist-stats)))
          threshold     -0.10]
      (reduce (fn [result gate]
                (let [rg           (get recent-gm gate)
                      hg           (get hist-gm gate)
                      current-p    (if rg (:p-pass rg) 1.0)
                      historical-p (if hg (:p-pass hg) 1.0)
                      delta        (- current-p historical-p)
                      alert        (when (< delta threshold)
                                     (format "DRIFT: %s P(pass) dropped from %.3f to %.3f (Δ=%.3f)"
                                             (name gate) historical-p current-p delta))]
                  (if alert
                    (-> result
                        (assoc :drifted true)
                        (update :drifted-gates conj {:gate         gate
                                                     :current-p    current-p
                                                     :historical-p historical-p
                                                     :delta        delta
                                                     :alert        alert}))
                    result)))
              {:drifted false :drifted-gates []}
              pipeline-gates))))

;; ═══════════════════════════════════════════════════════════════════════════════
;; Reporting
;; ═══════════════════════════════════════════════════════════════════════════════

(defn analysis-report
  "Full analysis report as a human-readable string, suitable for display."
  []
  (let [stats (statechart-stats)
        bn    (bottleneck)
        phi-r (phi-test)
        sb    (StringBuilder.)]
    (.append sb "=== Pipeline Statechart Analysis ===\n")
    (.append sb (format "Total experiments: %d\n" (:total stats)))
    (.append sb (format "Expected keep-rate: %.2f%%\n" (* 100.0 (:keep-rate stats))))
    (.append sb (format "φ keep-rate max (n=%d): %.4f  deviation: %+.4f (%.2f%%)\n"
                        (:n-gates phi-r)
                        (:phi-max phi-r)
                        (:deviation phi-r)
                        (:deviation-pct phi-r)))
    (when bn
      (.append sb (format "Bottleneck gate: %s\n" (name bn))))
    (.append sb "\nPer-gate transition probabilities:\n")
    (.append sb (format "  %-25s %8s %10s %10s\n"
                        "Gate" "P(pass)" "Entered" "Failed"))
    (.append sb (format "  %-25s %8s %10s %10s\n"
                        "────" "──────" "───────" "──────"))
    (doseq [g (:gates stats)]
      (.append sb (format "  %-25s %8.3f %10d %10d\n"
                          (name (:name g))
                          (:p-pass g)
                          (:entered g)
                          (:failed g))))
    (.toString sb)))

(defn analyze-for-elisp
  "Run full analysis and serialize as an Elisp-readable plist vector.
   Returns [:analysis [:kept N :discarded N :keep-rate float ...]]
   Gate keyword values are converted to strings for Elisp compatibility."
  []
  (let [stats      (statechart-stats)
        bn         (bottleneck)
        phi-r      (phi-test)
        gate-plists (mapv (fn [g]
                            [:name      (name (:name g))
                             :entered   (:entered g)
                             :passed    (:passed g)
                             :failed    (:failed g)
                             :unreached (:unreached g)
                             :p-pass    (:p-pass g)
                             :p-fail    (:p-fail g)])
                          (:gates stats))]
    [:analysis
     [:kept              (:kept stats)
      :discarded         (:discarded stats)
      :keep-rate         (:keep-rate stats)
      :total             (:total stats)
      :bottleneck        (if bn (name bn) nil)
      :phi               (:phi phi-r)
      :n-gates           (:n-gates phi-r)
      :phi-max           (:phi-max phi-r)
      :phi-deviation     (:deviation phi-r)
      :phi-deviation-pct (:deviation-pct phi-r)
      :gates             gate-plists
      :computed-at       (str (:computed-at stats))]]))

;; ═══════════════════════════════════════════════════════════════════════════════
;; Maintenance
;; ═══════════════════════════════════════════════════════════════════════════════

(defn backfill-fail-gates
  "Backfill :experiment/fail-gate for all experiments that lack it.
   Computes fail-gate from :experiment/decision using classify-fail-gate.
   Safe to run multiple times — skips already-backfilled experiments.
   Returns the number of experiments backfilled."
  []
  (when (ws/connected?)
    (ensure-schema)
    (let [exps            (ws/all-experiments)
          needs-backfill  (filter #(not (:experiment/fail-gate %)) exps)]
      (doseq [e needs-backfill]
        (let [decision  (:experiment/decision e)
              fail-gate (classify-fail-gate decision)
              db-id     (:db/id e)]
          (when (and db-id fail-gate)
            (ws/transact [{:db/id               db-id
                           :experiment/fail-gate fail-gate}]))))
      (count needs-backfill))))
