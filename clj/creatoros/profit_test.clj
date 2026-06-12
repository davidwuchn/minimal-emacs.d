(ns creatoros.profit-test
  (:require [clojure.test :refer [deftest is testing]]
            [creatoros.profit :as sut]))

(deftest test-fba-fee-standard
  (testing "Standard size beauty product"
    (is (= 12.63 (sut/fba-fee 29.99 1.5 :standard :beauty)))))

(deftest test-fba-fee-rejects-negative
  (testing "Negative price returns nil"
    (is (nil? (sut/fba-fee -1 1.0 :small :beauty)))))

(deftest test-landed-cost
  (testing "Landed cost for single unit"
    (is (= 13.50 (sut/landed-cost 8.00 5.50 0.08 1)))))

(deftest test-break-even
  (testing "Break-even at 30% margin"
    (is (= 22.15 (sut/break-even 9.00 6.50 0.30)))))

(deftest test-margin
  (testing "Profit margin calculation"
    (is (= 0.3 (sut/margin 29.99 14.50 6.50)))))
