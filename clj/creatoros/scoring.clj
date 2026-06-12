;; creatoros/scoring.clj — multi-signal product scoring
(ns creatoros.scoring)

(def ^:private default-weights
  {:demand     0.30
   :margin     0.25
   :competition 0.20
   :trend      0.15
   :community  0.10})

(defn normalize
  "Normalize value to 0.0-1.0 range given min and max."
  [value min-val max-val]
  (when (and (number? value) (number? min-val) (number? max-val)
             (not= max-val min-val))
    (max 0.0 (min 1.0 (/ (- value min-val) (- max-val min-val))))))

(defn demand-score
  "Score based on BSR (lower = better) and monthly revenue."
  [bsr revenue]
  (when (and (number? bsr) (> bsr 0) (number? revenue) (> revenue 0))
    (let [bsr-score (max 0 (- 1.0 (/ (Math/log bsr) 12.0)))
          rev-score (min 1.0 (/ (Math/log revenue) 12.0))]
      (* 0.5 (+ bsr-score rev-score)))))

(defn margin-score
  "Score based on profit margin (0.0-1.0)."
  [margin]
  (when (and (number? margin) (>= margin 0) (<= margin 1.0))
    (if (>= margin 0.60) 1.0
        (if (>= margin 0.30) (* margin 1.2)
            (/ margin 2.0)))))

(defn competition-score
  "Score based on review count (proxy for barrier-to-entry).
  Lower review counts are better for new entrants."
  [review-count]
  (when (and (number? review-count) (>= review-count 0))
    (if (> review-count 5000) 0.1
        (if (> review-count 1000) 0.3
            (if (> review-count 200) 0.6
                0.9)))))

(defn trend-score
  "Score based on BSR change over time. Positive delta = rising = good."
  [bsr-change-percent]
  (when (number? bsr-change-percent)
    (cond
      (> bsr-change-percent 50)  1.0
      (> bsr-change-percent 20)  0.8
      (> bsr-change-percent 0)   0.5
      (> bsr-change-percent -10) 0.3
      :else 0.1)))

(defn community-score
  "Score based on Reddit mention frequency and sentiment."
  [mention-count sentiment]
  (when (and (number? mention-count) (>= mention-count 0)
             (number? sentiment) (>= sentiment -1.0) (<= sentiment 1.0))
    (let [volume (min 1.0 (/ mention-count 100.0))
          sent (+ 1.0 sentiment)]
      (* 0.5 (+ volume (/ sent 2.0))))))

(defn composite-score
  "Weighted composite score for a product: 0.0-1.0.
  Inputs are maps with keys :demand, :margin, :competition, :trend, :community.
  Returns {:score 0.0-1.0 :breakdown {:demand ...} :grade :A..:F}"
  [scores & {:keys [weights] :or {weights default-weights}}]
  (let [breakdown {:demand     (or (:demand scores) 0)
                   :margin     (or (:margin scores) 0)
                   :competition (or (:competition scores) 0)
                   :trend      (or (:trend scores) 0)
                   :community  (or (:community scores) 0)}
        weighted (+ (* (:demand breakdown) (:demand weights))
                    (* (:margin breakdown) (:margin weights))
                    (* (:competition breakdown) (:competition weights))
                    (* (:trend breakdown) (:trend weights))
                    (* (:community breakdown) (:community weights)))
        score (double (min 1.0 weighted))
        grade (cond (>= score 0.75) :A
                    (>= score 0.60) :B
                    (>= score 0.40) :C
                    (>= score 0.20) :D
                    :else :F)]
    {:score score :breakdown breakdown :grade grade}))
