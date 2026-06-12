(ns creatoros.profit-test
  (:require [clojure.test :refer [deftest is testing]]
            [creatoros.profit :as sut]))

(deftest test-fba-fee-standard
  (testing "Standard size beauty product"
    (is (< 8.0 (sut/fba-fee 29.99 1.5 :standard :beauty) 9.0))
    (is (= 8.17 (double (/ (Math/round (* 100.0 (sut/fba-fee 29.99 1.5 :standard :beauty))) 100))))))

(deftest test-fba-fee-rejects-negative
  (testing "Negative price returns nil"
    (is (nil? (sut/fba-fee -1 1.0 :small :beauty)))))

(deftest test-landed-cost
  (testing "Landed cost for single unit"
    (is (= 8.0 (sut/landed-cost 8.00 0 0 1)))
    (is (> (sut/landed-cost 8.00 5.50 0.08 1) 13.0))))

(deftest test-break-even
  (testing "Break-even at 30% margin"
    (is (> (sut/break-even 9.00 6.50 0.30) 22.0))
    (is (< (sut/break-even 9.00 6.50 0.30) 23.0))))

(deftest test-margin
  (testing "Profit margin calculation"
    (is (> (sut/margin 29.99 14.50 6.50) 0.29))
    (is (< (sut/margin 29.99 14.50 6.50) 0.31))))