;; ov5/world_store/query.clj — Query layer for World Store
;;
;; Implements the missing query functions that the Elisp test suite
;; (test-world-store-query.el) calls but that have no implementation.
;;
;; Functions exposed:
;;   - experiments-by-filters:   filter map → coll of experiment maps
;;   - backend-strategy-target-stats: 3 args → (:kept :total :keep-rate) plist
;;   - recent-experiments: N → most recent N experiments
;;   - experiments-by-strategy-and-target: 2 args → matching experiments
;;
;; All return values are raw entity maps; serialization to Elisp plists
;; happens in `entities-to-readable` in the parent world_store namespace.

(ns ov5.world-store.query
  "Query layer over ov5.world-store entities.
   Powers the Elisp world-store-query-* functions."
  (:require [ov5.world-store :as ws]))

;; Re-export serializer so the Elisp side can call it after (ns ov5.world-store.query)
(def entities-to-readable ov5.world-store/entities-to-readable)

(defn- build-filter-datalog
  "Build a Datalog query vector matching all (ATTR VAL) pairs in FILTER-MAP.
   Each clause is [?e ATTR VAL], joined with :where.

   Note: we use `list` (not syntax-quote) to construct the Datalog form
   so that `pull` is NOT resolved as a Clojure function at compile time
   but rather passed as a symbol to the Datahike Datalog engine."
  [filter-map]
  (let [where-clauses (mapv (fn [[attr val]] ['?e attr val]) filter-map)]
    (into [:find '[(pull ?e [*]) ...] :where]
          where-clauses)))

(defn experiments-by-filters
  "Return all experiments matching a map of attribute filters.
   FILTER-MAP is a map from namespaced keyword to value.
   Example: {:experiment/backend \"MiniMax\" :experiment/strategy \"direct\"}
   Returns a coll of experiment entity maps (empty if nothing matches or
   if filter-map is empty/nil).

   Implementation note: dispatches via ov5.world-store/query so the
   Datalog form is built/evaluated in the parent namespace where
   `pull` is part of the Datahike query language (not a Clojure fn)."
  [filter-map]
  (if (empty? filter-map)
    []
    (or (ws/query (build-filter-datalog filter-map)) [])))

(defn backend-strategy-target-stats
  "Return {:kept N :total M :keep-rate F} for experiments matching BACKEND,
   optionally further filtered by STRATEGY and TARGET (both optional, may be nil).
   Keep-rate is a float in [0, 1]."
  [backend & [strategy target]]
  (let [filter-map (cond-> {:experiment/backend backend}
                     strategy (assoc :experiment/strategy strategy)
                     target (assoc :experiment/target target))
        matches (experiments-by-filters filter-map)
        total (count matches)
        kept (count (filter (fn [e]
                              (let [d (:experiment/decision e)]
                                (or (= :kept d) (= "kept" d))))
                            matches))
        keep-rate (if (pos? total) (float (/ kept total)) 0.0)]
    {:kept kept :total total :keep-rate keep-rate}))

(defn backend-strategy-target-stats-readable
  "Return a one-row EDN vector for the Elisp bridge.
   Keeps `backend-strategy-target-stats` map-shaped for Clojure callers,
   while giving Emacs a vector shape that round-trips cleanly through `read`."
  [backend & [strategy target]]
  (let [{:keys [kept total keep-rate]}
        (backend-strategy-target-stats backend strategy target)]
    [[:kept kept :total total :keep-rate keep-rate]]))

(defn recent-experiments
  "Return the N most recent experiments, sorted by :experiment/id descending.
   IDs are ISO-8601 prefixed (e.g. \"2026-06-12T14:32:11Z-...-run-id\"),
   so string-descending order on IDs approximates chronological recency."
  [n]
  (let [all (or (ws/query '[:find [(pull ?e [*]) ...]
                            :where [?e :experiment/id _]]) [])
        sorted (sort-by :experiment/id #(compare %2 %1) all)]
    (take n sorted)))

(defn experiments-by-strategy-and-target
  "Return experiments matching both STRATEGY and TARGET."
  [strategy target]
  (experiments-by-filters
   {:experiment/strategy strategy
    :experiment/target target}))
