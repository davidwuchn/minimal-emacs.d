(ns ov5.world-store
  "Core World Store namespace for OV5.
   Provides CRUD operations over Datahike."
  (:require [babashka.pods :as pods]))

(pods/load-pod 'replikativ/datahike "0.8.1697")

(require '[datahike.pod :as d])

;; -----------------------------------------------------------------------------
;; State

(defonce ^:private store-conn (atom nil))
(defonce ^:private store-config (atom nil))

;; -----------------------------------------------------------------------------
;; Schema

(def base-schema
  "Minimal schema for Phase 1: experiment, backend, strategy, target."
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
   {:db/ident :experiment/decision
    :db/valueType :db.type/keyword
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/backend
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}
   {:db/ident :experiment/strategy
    :db/valueType :db.type/string
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

(defn connect
  "Connect to a Datahike store at `path`. Creates store if it doesn't exist.
   Returns the connection."
  [path]
  (let [uuid (path-to-uuid path)
        cfg {:store {:backend :file
                     :id uuid
                     :path path}
             :keep-history? true
             :schema-flexibility :read}]
    (when-not (d/database-exists? cfg)
      (d/create-database cfg))
    (let [conn (d/connect cfg)]
      ;; Ensure schema is present (idempotent upsert)
      (try
        (d/transact conn base-schema)
        (catch Exception _
          ;; Schema may already exist; that's fine
          nil))
      (reset! store-conn conn)
      (reset! store-config cfg)
      conn)))

(defn disconnect
  "Disconnect from the current store."
  []
  (when-let [conn @store-conn]
    (d/release-db (d/db conn))
    (reset! store-conn nil)
    (reset! store-config nil)
    true))

(defn connected?
  "Return true if a store connection is active."
  []
  (some? @store-conn))

;; -----------------------------------------------------------------------------
;; CRUD

(defn transact
  "Transact `data` (vector of maps) into the store.
   Returns the transaction report."
  [data]
  (when-let [conn @store-conn]
    (d/transact conn data)))

(defn query
  "Run a Datalog `q` query against the current store.
   `q` is a quoted Datalog vector. Optional `args` for additional inputs."
  [q & args]
  (when-let [conn @store-conn]
    (let [db (d/db conn)]
      (if (seq args)
        (apply d/q q db args)
        (d/q q db)))))

(defn entity
  "Look up entity by `attr` and `val`. Returns the entity as a plain map.
   Example: (entity :experiment/id \"exp-123\")"
  [attr val]
  (when-let [conn @store-conn]
    (let [db (d/db conn)
          result (d/q '[:find (pull ?e [*]) :in $ ?attr ?val
                        :where [?e ?attr ?val]]
                      db attr val)]
      (first (first result)))))

(defn all-experiments
  "Return all experiment entities."
  []
  (query '[:find [(pull ?e [*]) ...] :where [?e :experiment/id _]]))

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
