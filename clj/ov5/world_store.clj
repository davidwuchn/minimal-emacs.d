(ns ov5.world-store
  "Core World Store namespace for OV5.
   Provides CRUD operations over Datahike."
  (:require [babashka.pods :as pods]))

;; ── Pod loading ──────────────────────────────────────────────────────────
;; Try to load the datahike pod. On unsupported platforms (e.g. macOS aarch64)
;; the download will fail; we catch the error and degrade gracefully.
;;
;; Functions use the `d*` helper below instead of `d/...` directly because
;; babashka's SCI compiler resolves namespace aliases during analysis (before
;; evaluation), so `d/` forms would fail to compile when the pod is unavailable.
;; `d*` uses `requiring-resolve` at runtime, avoiding compile-time resolution.
(def ^:private pod-ok?
  (try
    (pods/load-pod 'replikativ/datahike "0.8.1697")
    true
    (catch Throwable t
      (binding [*out* *err*]
        (println "[world-store] Datahike pod unavailable:" (.getMessage t)
                 "- degrading gracefully"))
      false)))

(defn- d*
  "Dynamically resolve and call a datahike.pod function.
   Returns nil when pod is unavailable (guarded by pod-ok?)."
  [fn-name & args]
  (when pod-ok?
    (let [f (requiring-resolve (symbol "datahike.pod" (name fn-name)))]
      (apply f args))))

(defn datahike-pod-available?
  "Returns true if the Datahike pod loaded successfully.
   Used by tests to skip when the pod is unavailable."
  []
  pod-ok?)

;; -----------------------------------------------------------------------------
;; State

(defonce ^:private store-conn (atom nil))
(defonce ^:private store-config (atom nil))

;; -----------------------------------------------------------------------------
;; Schema

(def base-schema
  "Full schema for experiment entities, backends, strategies, targets.
   All experiments attributes are :db.cardinality/one.
   Only :experiment/id has :db/unique :db.unique/identity."
  [{:db/ident :experiment/id
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one
    :db/unique :db.unique/identity}
   {:db/ident :experiment/target
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/hypothesis
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/score-before
    :db/valueType :db.type/double
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/score-after
    :db/valueType :db.type/double
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/code-quality
    :db/valueType :db.type/double
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/delta
    :db/valueType :db.type/double
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/decision
    :db/valueType :db.type/keyword
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/duration
    :db/valueType :db.type/long
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/grader-quality
    :db/valueType :db.type/double
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/grader-reason
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/comparator-reason
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/analyzer-patterns
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/agent-output
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/output-chars
    :db/valueType :db.type/long
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/backend
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/prompt-chars
    :db/valueType :db.type/long
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/sections-included
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/exploration-axis
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/candidate-scores
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/strategy
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/research-strategy
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/research-hash
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/research-quality
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/controller-decision
    :db/valueType :db.type/keyword
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/kibcm-axis
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/model
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/eight-key-scores
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/skills
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/edit-mode
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/cost-usd
    :db/valueType :db.type/double
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/effort-level
    :db/valueType :db.type/keyword
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/prod-error-rate-before
    :db/valueType :db.type/double
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/prod-error-rate-after
    :db/valueType :db.type/double
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/prod-error-rate-delta
    :db/valueType :db.type/double
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/user-satisfaction-delta
    :db/valueType :db.type/double
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/support-tickets-reduced
    :db/valueType :db.type/long
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/business-value-score
    :db/valueType :db.type/double
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/risk-score
    :db/valueType :db.type/double
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/complexity-before
    :db/valueType :db.type/double
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/complexity-after
    :db/valueType :db.type/double
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/lines-removed
    :db/valueType :db.type/long
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/understanding-score
    :db/valueType :db.type/double
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/diversity
    :db/valueType :db.type/double
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/persona-category
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/persona-archetype
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/research-context
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}
   ;; Gate scores (11 elements, stored individually as doubles)
   {:db/ident :experiment/gate-score-0
    :db/valueType :db.type/double
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/gate-score-1
    :db/valueType :db.type/double
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/gate-score-2
    :db/valueType :db.type/double
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/gate-score-3
    :db/valueType :db.type/double
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/gate-score-4
    :db/valueType :db.type/double
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/gate-score-5
    :db/valueType :db.type/double
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/gate-score-6
    :db/valueType :db.type/double
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/gate-score-7
    :db/valueType :db.type/double
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/gate-score-8
    :db/valueType :db.type/double
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/gate-score-9
    :db/valueType :db.type/double
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/gate-score-10
    :db/valueType :db.type/double
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/timestamp
    :db/valueType :db.type/instant
    :db/cardinality :db.cardinality/one}
   {:db/ident :backend/name
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one
    :db/unique :db.unique/identity}
   {:db/ident :strategy/name
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one
    :db/unique :db.unique/identity}
   {:db/ident :target/path
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one
    :db/unique :db.unique/identity}])

;; -----------------------------------------------------------------------------
;; Connection

(defn- path-to-uuid
  "Generate a deterministic UUID from a path string."
  [path]
  (let [bytes (.getBytes path java.nio.charset.StandardCharsets/UTF_8)
        hash (java.security.MessageDigest/getInstance "MD5")
        digest (.digest hash bytes)]
    (java.util.UUID/nameUUIDFromBytes digest)))

(defn connect-to-path
  "Connect to a Datahike store at `db-path`. Creates store if it doesn't exist.
   Returns [conn config] without setting global state.
   Returns [nil nil] when the Datahike pod is unavailable."
  [db-path]
  (when pod-ok?
    (let [uuid (path-to-uuid db-path)
          cfg {:store {:backend :file
                       :id uuid
                       :path db-path}
               :keep-history? true
               :schema-flexibility :read}]
      (when-not (d* 'database-exists? cfg)
        (d* 'create-database cfg))
      (let [conn (d* 'connect cfg)]
        ;; Ensure schema is present (idempotent upsert)
        (try
          (d* 'transact conn base-schema)
          (catch Exception _
            ;; Schema may already exist; that's fine
            nil))
        [conn cfg]))))

(defn connect
  "Connect to a Datahike store at `path`. Creates store if it doesn't exist.
   Returns the connection."
  [path]
  (let [[conn cfg] (connect-to-path path)]
    (reset! store-conn conn)
    (reset! store-config cfg)
    conn))

(defn disconnect
  "Disconnect from the current store.
   Returns nil when the Datahike pod is unavailable."
  []
  (when pod-ok?
    (when-let [conn @store-conn]
      (d* 'release-db (d* 'db conn))
      (reset! store-conn nil)
      (reset! store-config nil)
      true)))

(defn connected?
  "Return true if a store connection is active."
  []
  (some? @store-conn))

(defn set-store-conn!
  "Internal: replace the store connection. Used by branch switching."
  [conn]
  (reset! store-conn conn))

;; -----------------------------------------------------------------------------
;; CRUD

(defn transact
  "Transact `data` (vector of maps) into the store.
   Returns the transaction report, or nil when the pod is unavailable."
  [data]
  (when pod-ok?
    (when-let [conn @store-conn]
      (d* 'transact conn data))))

(defn query
  "Run a Datalog `q` query against the current store.
   `q` is a quoted Datalog vector. Optional `args` for additional inputs.
   Returns nil when the Datahike pod is unavailable."
  [q & args]
  (when pod-ok?
    (when-let [conn @store-conn]
      (let [db (d* 'db conn)]
        (if (seq args)
          (apply d* 'q q db args)
          (d* 'q q db))))))

(defn entity
  "Look up entity by `attr` and `val`. Returns the entity as a plain map.
   Example: (entity :experiment/id \"exp-123\")
   Returns nil when the Datahike pod is unavailable."
  [attr val]
  (when pod-ok?
    (when-let [conn @store-conn]
      (let [db (d* 'db conn)
            result (d* 'q '[:find (pull ?e [*]) :in $ ?attr ?val
                          :where [?e ?attr ?val]]
                        db attr val)]
        (first (first result))))))

(defn all-experiments
  "Return all experiment entities."
  []
  (query '[:find [(pull ?e [*]) ...] :where [?e :experiment/id _]]))

(defn transact-experiment
  "Transact a single experiment map into the store.
   If RUN-ID is non-nil, prefixes :experiment/id with \"run-id#\" to ensure
   global uniqueness (e.g. \"2026-06-13T12:00:00Z-abc1#exp-001\").
   Returns the transaction report."
  ([experiment-map] (transact-experiment nil experiment-map))
  ([run-id experiment-map]
   (let [entity (if run-id
                  (update experiment-map :experiment/id
                          #(str run-id "#" %))
                  experiment-map)]
     (transact [entity]))))

(defn experiments-by-target
  "Return all experiments for a given target path."
  [target-path]
  (query '[:find [(pull ?e [*]) ...] :in $ ?target
           :where [?e :experiment/target ?target]]
         target-path))

(defn experiments-by-backend
  "Return all experiments for a given backend name."
  [backend-name]
  (query '[:find [(pull ?e [*]) ...] :in $ ?backend
           :where [?e :experiment/backend ?backend]]
         backend-name))

(defn experiments-by-decision
  "Return all experiments with a given decision keyword."
  [decision]
  (query '[:find [(pull ?e [*]) ...] :in $ ?decision
           :where [?e :experiment/decision ?decision]]
         decision))

(defn experiments-by-decision-and-age
  "Return experiments with DECISION (:db.type/keyword) where the
   :experiment/id timestamp prefix is > MIN-AGE-HOURS ago and
   < MAX-AGE-HOURS ago.  Both age params are floats in hours.
   Returns coll of entity maps (empty if none match)."
  [decision min-age-hours max-age-hours]
  (let [all (experiments-by-decision decision)
        now-ms (System/currentTimeMillis)
        min-cutoff (- now-ms (* min-age-hours 3600000))
        max-cutoff (- now-ms (* max-age-hours 3600000))]
    (filter (fn [e]
              (when-let [id (:experiment/id e)]
                (when-let [m (re-find #"^(\d{4}-\d{2}-\d{2}T\d{2}\d{2}\d{2})Z" id)]
                  (let [ts (try (-> (java.text.SimpleDateFormat. "yyyy-MM-dd'T'HHmmss")
                                    (.parse (m 1))
                                    .getTime)
                                (catch Exception _ nil))]
                    (and ts
                         (< ts min-cutoff)
                         (> ts max-cutoff))))))
            all)))

(defn kept-experiment-count
  "Return count of experiments with decision :kept."
  []
  (count (experiments-by-decision :kept)))

(defn kept-target-count
  "Return count of distinct targets with at least one kept experiment."
  []
  (let [kept (experiments-by-decision :kept)
        targets (set (map :experiment/target kept))]
    (count targets)))

(defn experiments-by-strategy
  "Return all experiments for a given strategy name."
  [strategy-name]
  (query '[:find [(pull ?e [*]) ...] :in $ ?strategy
           :where [?e :experiment/strategy ?strategy]]
         strategy-name))

;; -----------------------------------------------------------------------------
;; Metrics

(defn experiment-count
  "Return total number of experiments in the store."
  []
  (count (all-experiments)))

(defn backend-keep-rate
  "Return keep rate for a backend as a float [0,1]."
  [backend-name]
  (let [all (experiments-by-backend backend-name)
        kept (filter #(let [d (:experiment/decision %)]
                        (or (= :kept d) (= "kept" d)))
                      all)]
    (if (seq all)
      (float (/ (count kept) (count all)))
      0.0)))

;; -----------------------------------------------------------------------------
;; Serialization

(defn entities-to-readable
  "Convert a coll of entity maps into Elisp-readable plist vectors.
   Each entity becomes a vector of alternating keywords and values.
   Keywords have no namespace prefix.  Keyword values (:kept) become strings.
   Always includes a :timestamp field: uses :experiment/timestamp if present,
   otherwise derives it from :experiment/id (the run-id prefix is ISO 8601).
   Returns: [[:id \"t1\" :backend \"MiniMax\" :timestamp \"2026-06-...\" ...] ...]"
  [entities]
  (mapv (fn [e]
           (let [ts (or (:experiment/timestamp e)
                        (:experiment/id e))
                 e' (-> e
                       (dissoc :db/id)
                       (assoc :experiment/timestamp (str ts)))]
             (vec (mapcat (fn [[k v]]
                            [(keyword (name k))
                             (if (keyword? v) (name v) v)])
                          e'))))
         entities))

;; Ensure query namespace is available in the brepl session
(try (load-file "clj/ov5/world_store/query.clj")
     (catch Exception _ nil))

;; Ensure branch namespace is available in the brepl session
(try (load-file "clj/ov5/world_store/branch.clj")
     (catch Exception _ nil))

;; -----------------------------------------------------------------------------
;; Elisp Bridge Convenience

(defn all-experiments-readable
  "Return all experiments as Elisp-readable plist vectors.
   Calls entities-to-readable on all-experiments."
  []
  (entities-to-readable (all-experiments)))

(defn staging-pending-by-age
  "Return staging-pending experiments within [MIN-H max-H] range."
  [min-hours max-hours]
  (entities-to-readable
   (experiments-by-decision-and-age :staging-pending min-hours max-hours)))
