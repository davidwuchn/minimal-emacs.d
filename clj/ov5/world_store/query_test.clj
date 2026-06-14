;; ov5/world_store/query_test.clj — TDD tests for World Store query layer
;;
;; Tests the missing query functions that the Elisp test suite
;; (test-world-store-query.el) calls.  The Elisp test fails on:
;;   - experiments-by-filters
;;   - backend-strategy-target-stats
;;   - recent-experiments
;;   - experiments-by-strategy-and-target
;;
;; These Clojure tests verify the implementation directly so we can
;; iterate on the Clojure side without needing a brepl+nREPL+Datahike
;; connection for every change.

(ns ov5.world-store.query-test
  (:require [clojure.test :refer [deftest is testing use-fixtures]]
            [ov5.world-store.query :as q]
            [ov5.world-store :as ws]))

;; Skip all tests when the Datahike pod is unavailable (e.g. macOS aarch64).
(use-fixtures :once
  (fn [tests]
    (if (ws/datahike-pod-available?)
      (tests)
      (println "[query-test] SKIP: Datahike pod unavailable"))))

;; ═══════════════════════════════════════════════════════════════════════════
;; Unit tests: behavior with mocked query function
;; ═══════════════════════════════════════════════════════════════════════════

(defn with-mock-query
  "Run BODY with ws/query replaced by MOCK-FN.  Returns BODY's value."
  [mock-fn body-fn]
  (let [original (resolve 'ws/query)]
    (try
      (with-redefs [ws/query mock-fn]
        (body-fn))
      (finally
        (when original
          (alter-var-root original (constantly original)))))))

(deftest test-experiments-by-filters-returns-pull-results
  (testing "experiments-by-filters calls ws/query and returns results"
    (let [captured-args (atom nil)]
      (with-mock-query
       (fn [q & args]
         (reset! captured-args {:q q :args args})
         [{:experiment/id "e1" :experiment/backend "MiniMax"}])
       (fn []
         (let [result (q/experiments-by-filters {:experiment/backend "MiniMax"})]
           (is (= 1 (count result)))
           (is (= "e1" (:experiment/id (first result))))
           (is (= :find (first (:q @captured-args)))))))
      (is (vector? (:q @captured-args))))))

(deftest test-experiments-by-filters-empty-filter-map
  (testing "Empty filter map should not query — return []"
    (let [called? (atom false)]
      (with-mock-query
       (fn [_ & _] (reset! called? true) [])
       (fn []
         (let [result (q/experiments-by-filters {})]
           (is (= [] result))
           (is (false? @called?))))))))

(deftest test-experiments-by-filters-multiple-attrs
  (testing "Multi-attr filter passes all attrs to ws/query"
    (let [captured (atom nil)]
      (with-mock-query
       (fn [q & _]
         (reset! captured q)
         [{:experiment/id "e2"}])
       (fn []
         (q/experiments-by-filters
          {:experiment/backend "MiniMax"
           :experiment/strategy "direct"})
         (let [qvec @captured]
           ;; Both :where clauses should be present
           (is (some #(and (sequential? %) (= :experiment/backend (second %))) qvec))
           (is (some #(and (sequential? %) (= :experiment/strategy (second %))) qvec))))))))

(deftest test-backend-strategy-target-stats-keep-rate
  (testing "Keep-rate calculation: 2 kept out of 3 = 0.666..."
    (with-mock-query
     (fn [_ & _]
       [{:experiment/decision :kept}
        {:experiment/decision "kept"}
        {:experiment/decision :discarded}])
     (fn []
       (let [stats (q/backend-strategy-target-stats "MiniMax")]
         (is (= 2 (:kept stats)))
         (is (= 3 (:total stats)))
         (is (< 0.66 (:keep-rate stats) 0.67)))))))

(deftest test-backend-strategy-target-stats-with-strategy
  (testing "Strategy filter is passed through"
    (let [captured (atom nil)]
      (with-mock-query
       (fn [_ & _] (reset! captured :called) [{:experiment/decision :kept}])
       (fn []
         (q/backend-strategy-target-stats "MiniMax" "direct")
         (is (= :called @captured)))))))

(deftest test-recent-experiments-returns-n-most-recent
  (testing "Sorts by :experiment/id descending, takes N"
    (with-mock-query
     (fn [_ & _]
       [{:experiment/id "2026-01-01-run-1"}
        {:experiment/id "2026-06-12-run-3"}
        {:experiment/id "2026-03-15-run-2"}])
     (fn []
       (let [recent (q/recent-experiments 2)]
         (is (= 2 (count recent)))
         (is (= "2026-06-12-run-3" (:experiment/id (first recent))))
         (is (= "2026-03-15-run-2" (:experiment/id (second recent)))))))))

(deftest test-recent-experiments-fewer-than-n
  (testing "Returns all when fewer than N exist"
    (with-mock-query
     (fn [_ & _]
       [{:experiment/id "2026-01-01-run-1"}])
     (fn []
       (let [recent (q/recent-experiments 10)]
         (is (= 1 (count recent))))))))

(deftest test-experiments-by-strategy-and-target
  (testing "Both filters applied"
    (let [captured (atom nil)]
      (with-mock-query
       (fn [qvec & _]
         (reset! captured qvec)
         [{:experiment/id "e1" :experiment/strategy "direct" :experiment/target "foo.el"}])
       (fn []
         (let [result (q/experiments-by-strategy-and-target "direct" "foo.el")]
           (is (= 1 (count result)))
           (is (some #(and (sequential? %) (= :experiment/strategy (second %))) @captured))
           (is (some #(and (sequential? %) (= :experiment/target (second %))) @captured))))))))
