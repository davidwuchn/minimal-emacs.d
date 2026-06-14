(ns ov5.world-store.context
  "Context unification for OV5 World Store.
   Merges .edn sidecars, approval history, and risk patterns into
   unified experiment entities."
  (:require [clojure.java.io :as io]
            [clojure.edn :as edn]
            [ov5.world-store :as ws]))

;; -----------------------------------------------------------------------------
;; Schema extensions for context/approval/risk

(def context-schema
  "Additional schema attributes for context, approval, and risk."
  [{:db/ident :context/business-rationale
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}
   {:db/ident :context/causal-chain
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}
   {:db/ident :context/decision-rationale
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}
   {:db/ident :context/learned
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}
   {:db/ident :context/expected-impact
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}
   {:db/ident :context/observed-impact
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}
   {:db/ident :approval/type
    :db/valueType :db.type/keyword
    :db/cardinality :db.cardinality/one}
   {:db/ident :approval/timestamp
    :db/valueType :db.type/string
    :db/cardinality :db.cardinality/one}
   {:db/ident :risk/scope-factor
    :db/valueType :db.type/double
    :db/cardinality :db.cardinality/one}
   {:db/ident :risk/complexity-factor
    :db/valueType :db.type/double
    :db/cardinality :db.cardinality/one}
   {:db/ident :risk/confidence
    :db/valueType :db.type/double
    :db/cardinality :db.cardinality/one}])

(defn ensure-context-schema
  "Ensure context schema is present in the store."
  []
  (when-let [conn @ws/store-conn]
    (try
      (ws/transact context-schema)
      (catch Exception _ nil))))

;; -----------------------------------------------------------------------------
;; Context sidecar parsing

(defn- plist->map
  "Convert a plist (list of alternating key-value pairs) to a map."
  [plist]
  (if (and (sequential? plist) (even? (count plist)))
    (apply hash-map plist)
    plist))

(defn- read-sexp
  "Read an EDN sexp from a file, converting plists to maps.
   Handles both single plist and list of plists."
  [path]
  (try
    (let [data (edn/read-string (slurp path))]
      (cond
        ;; List of plists: each element is itself sequential
        (and (sequential? data) (sequential? (first data)))
        (map plist->map data)
        ;; Single plist: even-length sequential
        (and (sequential? data) (even? (count data)))
        (plist->map data)
        ;; Plain data
        :else data))
    (catch Exception e
      (println (str "[context] ERROR reading " path ": " (.getMessage e)))
      nil)))

(defn- extract-context-attrs
  "Extract context attributes from a sidecar plist."
  [data]
  (let [{:keys [business-rationale causal-chain decision-rationale
                learned expected-impact observed-impact]} data]
    (into {} (filter val
              {:context/business-rationale business-rationale
               :context/causal-chain (when causal-chain (str causal-chain))
               :context/decision-rationale decision-rationale
               :context/learned learned
               :context/expected-impact expected-impact
               :context/observed-impact observed-impact}))))

(defn unify-context-sidecar
  "Unify a single context sidecar file into the store.
   Matches experiment by :target field."
  [path]
  (when-let [data (read-sexp path)]
    (let [target (:target data)
          attrs (extract-context-attrs data)]
      (if (and target (seq attrs))
        (let [experiments (ws/experiments-by-target target)]
          (if (seq experiments)
            (do
              (doseq [exp experiments]
                (ws/transact [(assoc attrs :db/id (:db/id exp))]))
              {:matched (count experiments) :target target})
            {:matched 0 :target target :reason "no experiments found"}))
        {:matched 0 :target target :reason "no attrs extracted"}))))

(defn unify-all-context-sidecars
  "Unify all context sidecars from `dir`."
  [dir]
  (ensure-context-schema)
  (let [files (->> (file-seq (io/file dir))
                    (filter #(.endsWith (.getName %) ".edn"))
                   (map #(.getAbsolutePath %))
                   (sort))
        results (atom {:files 0 :matched 0 :unmatched 0 :errors []})]
    (println (str "[context] Found " (count files) " context sidecars"))
    (doseq [f files]
      (let [result (unify-context-sidecar f)]
        (swap! results update :files inc)
        (if (> (:matched result) 0)
          (swap! results update :matched + (:matched result))
          (swap! results update :unmatched inc))))
    (println (str "[context] DONE: " @results))
    @results))

;; -----------------------------------------------------------------------------
;; Approval history parsing

(defn- extract-approval-attrs
  "Extract approval attributes from an approval record."
  [record]
  (let [{:keys [approval-type timestamp risk-score]} record]
    (into {} (filter val
              {:approval/type approval-type
               :approval/timestamp timestamp
               :experiment/risk-score risk-score}))))

(defn unify-approval-history
  "Unify approval history file into the store.
   Matches by :experiment-id and :target."
  [path]
  (ensure-context-schema)
  (when-let [records (read-sexp path)]
    (let [results (atom {:matched 0 :unmatched 0})]
      (doseq [record records]
        (let [exp-id (:experiment-id record)
              target (:target record)
              attrs (extract-approval-attrs record)]
          (if (and exp-id target)
            ;; Find experiment by target (experiment-id alone is not unique after namespacing)
            (let [experiments (ws/experiments-by-target target)]
              (if (seq experiments)
                (do
                  (doseq [exp experiments]
                    (ws/transact [(assoc attrs :db/id (:db/id exp))]))
                  (swap! results update :matched + (count experiments)))
                (swap! results update :unmatched inc)))
            (swap! results update :unmatched inc))))
      (println (str "[context] Approval history: " @results))
      @results)))

;; -----------------------------------------------------------------------------
;; Risk pattern parsing

(defn- extract-risk-attrs
  "Extract risk attributes from a risk pattern record."
  [record]
  (let [factors (:risk-factors record)
        {:keys [scope-factor complexity-factor]} factors]
    (into {} (filter val
              {:risk/scope-factor scope-factor
               :risk/complexity-factor complexity-factor
               :risk/confidence (:confidence record)}))))

(defn unify-risk-patterns
  "Unify risk patterns file into the store.
   Matches by target path (:pattern-name)."
  [path]
  (ensure-context-schema)
  (when-let [records (read-sexp path)]
    (let [results (atom {:matched 0 :unmatched 0})]
      (doseq [record records]
        (let [target (:pattern-name record)
              attrs (extract-risk-attrs record)]
          (if target
            (let [experiments (ws/experiments-by-target target)]
              (if (seq experiments)
                (do
                  (doseq [exp experiments]
                    (ws/transact [(assoc attrs :db/id (:db/id exp))]))
                  (swap! results update :matched + (count experiments)))
                (swap! results update :unmatched inc)))
            (swap! results update :unmatched inc))))
      (println (str "[context] Risk patterns: " @results))
      @results)))

;; -----------------------------------------------------------------------------
;; Unified entity

(defn unified-entity
  "Look up a unified experiment entity by target path.
   Returns the experiment with all context, approval, and risk data."
  [target]
  (first (ws/experiments-by-target target)))

;; -----------------------------------------------------------------------------
;; Batch unification

(defn unify-all
  "Unify all context data from default locations."
  []
  (let [context-results (unify-all-context-sidecars "var/context")
        approval-results (unify-approval-history "var/approval-history.edn")
        risk-results (unify-risk-patterns "var/risk-patterns.edn")]
    {:context context-results
     :approval approval-results
     :risk risk-results}))
