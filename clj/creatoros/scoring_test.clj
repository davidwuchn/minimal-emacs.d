(ns creatoros.scoring-test
  (:require [clojure.test :refer [deftest is testing]]
            [creatoros.scoring :as sut]))

(deftest test-normalize-midrange
  (testing "Normalize 50 in range 0-100"
    (is (== 0.5 (double (sut/normalize 50 0 100))))))

(deftest test-normalize-bounds
  (testing "Normalize at bounds"
    (is (== 0.0 (double (sut/normalize 0 0 100))))
    (is (== 1.0 (double (sut/normalize 100 0 100))))))

(deftest test-demands-score-valid
  (testing "Demand score for healthy product"
    (let [score (sut/demand-score 5000 50000)]
      (is (> score 0.4))
      (is (< score 0.9)))))

(deftest test-margin-score-high
  (testing "Margin score for 60% margin"
    (is (= 1.0 (sut/margin-score 0.60)))))

(deftest test-margin-score-low
  (testing "Margin score for 15% margin"
    (is (< (sut/margin-score 0.15) 0.3))))

(deftest test-competition-score-low-barrier
  (testing "Competition score for low review count"
    (is (= 0.9 (sut/competition-score 150)))))

(deftest test-competition-score-high-barrier
  (testing "Competition score for very high review count"
    (is (= 0.1 (sut/competition-score 8000)))))

(deftest test-trend-score-rising
  (testing "Trend score for strongly rising product"
    (is (= 1.0 (sut/trend-score 60)))))

(deftest test-community-score-good
  (testing "Community score for well-received product"
    (let [score (sut/community-score 50 0.8)]
      (is (> score 0.5)))))

(deftest test-composite-a-grade
  (testing "Composite score for strong product"
    (let [result (sut/composite-score {:demand 0.8 :margin 0.9 :competition 0.9 :trend 0.8 :community 0.7})]
      (is (= :A (:grade result)))
      (is (> (:score result) 0.75)))))

(deftest test-composite-d-grade
  (testing "Composite score for weak product"
    (let [result (sut/composite-score {:demand 0.1 :margin 0.1 :competition 0.1 :trend 0.1 :community 0.1})]
      (is (= :F (:grade result)))
      (is (< (:score result) 0.20)))))
