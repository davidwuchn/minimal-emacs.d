(ns creatoros.sources-test
  (:require [clojure.test :refer [deftest is testing]]
            [creatoros.sources :as sut]))

(deftest test-fetch-products-returns-collection
  (let [products (sut/fetch-products)]
    (is (sequential? products))
    (is (pos? (count products)))))

(deftest test-fetch-products-respects-limit
  (let [products (sut/fetch-products :limit 3)]
    (is (= 3 (count products)))))

(deftest test-fetch-by-category-filters
  (let [beauty (sut/fetch-by-category :beauty)]
    (is (every? #(= (:category %) :beauty) beauty))))

(deftest test-enriched-products-have-reddit
  (let [products (sut/fetch-products)]
    (is (every? :reddit-mentions products))
    (is (every? :sentiment products))
    (is (every? :bsr-change products))))

(deftest test-enriched-products-have-supplier
  (let [products (sut/fetch-products)]
    (is (every? :supplier products))
    (is (>= (count (filter #(not= "Unknown" (:supplier %)) products)) 1))))

(deftest test-source-status-returns-all-sources
  (let [status (sut/source-status)]
    (is (contains? status :amazon))
    (is (contains? status :reddit))
    (is (contains? status :aliexpress))
    (is (contains? status :google-trends))))
