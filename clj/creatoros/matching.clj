;; creatoros/matching.clj — product-creator matching engine
(ns creatoros.matching
  (:require [creatoros.scoring :as scoring]
            [creatoros.profit :as profit]))

(def ^:private category-thresholds
  {:micro  0.40 :mid 0.50 :macro 0.55 :agency 0.60})

(def ^:private country-multipliers
  {"US" 1.0 "UK" 0.85 "DE" 0.80 "FR" 0.75
   "CA" 0.80 "AU" 0.80
   "ID" 0.35 "TH" 0.30 "VN" 0.25 "PH" 0.25
   "BR" 0.40 "MX" 0.35
   "SA" 0.55 "AE" 0.60})

(defn creator-tier
  [follower-count]
  (when (and (number? follower-count) (>= follower-count 0))
    (cond (< follower-count 10000) :micro
          (< follower-count 500000) :mid
          (< follower-count 5000000) :macro
          :else :agency)))

(defn score-product
  [product cogs fees]
  (let [scores {:demand      (scoring/demand-score (:bsr product) (:revenue product))
                :margin      (scoring/margin-score
                              (profit/margin (:price product) cogs fees))
                :competition (scoring/competition-score (:review-count product))
                :trend       (scoring/trend-score (:bsr-change product))
                :community   (scoring/community-score (:reddit-mentions product) (:sentiment product))}
        composite (scoring/composite-score scores)]
    (assoc product
           :scores scores
           :composite (:score composite)
           :grade (:grade composite)
           :cogs (double cogs)
           :fees (double fees)
           :break-even (double (profit/break-even cogs fees 0.30)))))

(defn match
  [creator products]
  (let [tier (creator-tier (:followers creator))
        min-score (get category-thresholds tier 0.50)
        multiplier (get country-multipliers (:country creator) 1.0)
        default-cogs (profit/landed-cost 8.0 5.5 0.08 1)
        scored (for [p products
                     :let [fees (profit/fba-fee (:price p) (:weight-lbs p) (:size-tier p) (:category p))
                           scored-p (score-product p default-cogs fees)]
                     :when (>= (:composite scored-p) min-score)]
                 (assoc scored-p :revenue-potential (* (:revenue p) multiplier)))]
    (->> scored (sort-by :composite >) (take 5) vec)))
