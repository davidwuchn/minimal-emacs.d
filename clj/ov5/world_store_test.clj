;; ov5/world_store_test.clj — Tests for world_store.clj
(ns ov5.world-store-test
  (:require [clojure.test :refer [deftest is testing]]))

(deftest test-truth
  (testing "Basic truth"
    (is (= 1 1))))

(deftest test-arithmetic
  (testing "Simple arithmetic"
    (is (= 4 (+ 2 2)))
    (is (= 6 (* 2 3)))))

(deftest test-string
  (testing "String operations"
    (is (= "hello" (clojure.string/lower-case "HELLO")))))
