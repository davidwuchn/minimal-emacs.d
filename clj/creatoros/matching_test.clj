(ns creatoros.matching-test
  (:require [clojure.test :refer [deftest is]]
            [creatoros.matching :as sut]))

(def sample-products
  [{:id "prod-1" :bsr 5000 :revenue 50000 :price 29.99 :weight-lbs 1.5
    :size-tier :standard :category :beauty :review-count 684
    :reddit-mentions 50 :sentiment 0.8 :bsr-change 45}
   {:id "prod-2" :bsr 15000 :revenue 20000 :price 19.99 :weight-lbs 0.5
    :size-tier :small :category :beauty :review-count 120
    :reddit-mentions 10 :sentiment 0.3 :bsr-change -5}
   {:id "prod-3" :bsr 2000 :revenue 80000 :price 49.99 :weight-lbs 2.0
    :size-tier :standard :category :electronics :review-count 2000
    :reddit-mentions 5 :sentiment -0.2 :bsr-change 80}])

(def sample-creator
  {:niche :beauty :followers 280000 :country "US"})

(deftest test-creator-tier-micro
  (is (= :micro (sut/creator-tier 5000))))

(deftest test-creator-tier-mid
  (is (= :mid (sut/creator-tier 100000))))

(deftest test-creator-tier-macro
  (is (= :macro (sut/creator-tier 1000000))))

(deftest test-match-returns-ranked
  (let [results (sut/match sample-creator sample-products)]
    (is (vector? results))
    (is (<= (count results) 5))
    (is (apply >= (map :composite results)))))

(deftest test-match-filters-below-threshold
  (let [results (sut/match (assoc sample-creator :followers 500000) sample-products)]
    (is (every? #(>= (:composite %) 0.45) results))))

(deftest test-match-includes-metrics
  (let [results (sut/match sample-creator sample-products)]
    (is (every? :cogs results))
    (is (every? :fees results))
    (is (every? :grade results))
    (is (every? :revenue-potential results))))
