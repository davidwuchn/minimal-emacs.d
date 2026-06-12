;; creatoros/profit.clj — FBA-style profit calculator
(ns creatoros.profit)

(defn pick-pack-fee [size-tier]
  (case size-tier
    :small    2.50
    :standard 3.00
    :large    5.00
    :oversize 8.50
    3.00))

(defn weight-handling [weight-lbs size-tier]
  (case size-tier
    :small    (* weight-lbs 0.38)
    :standard (* weight-lbs 0.45)
    :large    (* weight-lbs 0.55)
    :oversize (* weight-lbs 0.75)
    (* weight-lbs 0.45)))

(defn referral-fee [price category]
  (let [rate (get {:beauty 0.15, :electronics 0.08, :home 0.15, :clothing 0.17} category 0.15)]
    (* price rate)))

(defn fba-fee
  "Calculate total FBA fee for a product."
  [price weight-lbs size-tier category]
  (when (and (number? price) (>= price 0)
             (number? weight-lbs) (>= weight-lbs 0))
    (+ (pick-pack-fee size-tier)
       (weight-handling weight-lbs size-tier)
       (referral-fee price category))))

(defn landed-cost
  "Total cost to get product to Amazon warehouse."
  [unit-cost shipping-per-unit duty-rate quantity]
  (when (and (number? unit-cost) (>= unit-cost 0)
             (number? quantity) (> quantity 0))
    (let [shipping (if (> quantity 1) (/ shipping-per-unit quantity) shipping-per-unit)]
      (+ unit-cost shipping (* unit-cost (or duty-rate 0))))))

(defn break-even
  "Minimum selling price to break even at target margin."
  [cogs fba-fee target-margin]
  (when (and (number? cogs) (>= cogs 0)
             (number? fba-fee) (>= fba-fee 0)
             (number? target-margin) (> target-margin 0) (< target-margin 1))
    (double (/ (+ cogs fba-fee) (- 1.0 target-margin)))))

(defn margin
  "Profit margin as a decimal (0.0-1.0)."
  [price cogs fba-fee]
  (when (and (number? price) (> price 0)
             (number? cogs) (>= cogs 0)
             (number? fba-fee) (>= fba-fee 0))
    (let [profit (- price cogs fba-fee)]
      (max 0.0 (double (/ profit price))))))
