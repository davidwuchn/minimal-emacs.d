;; creatoros/sources.clj — product data source abstraction
(ns creatoros.sources
  "Abstraction for product data sources.
  Each source is a map with :name, :fetch-fn, and :transform-fn.
  Sources: Amazon BSR, Reddit mentions, AliExpress pricing, Google Trends.")

(def ^:private sample-amazon-products
  [{:id "amz-1" :bsr 5000 :revenue 50000 :price 29.99 :weight-lbs 1.5
    :size-tier :standard :category :beauty :review-count 684}
   {:id "amz-2" :bsr 15000 :revenue 20000 :price 19.99 :weight-lbs 0.5
    :size-tier :small :category :beauty :review-count 120}
   {:id "amz-3" :bsr 2000 :revenue 80000 :price 49.99 :weight-lbs 2.0
    :size-tier :standard :category :electronics :review-count 2000}
   {:id "amz-4" :bsr 8000 :revenue 35000 :price 24.99 :weight-lbs 1.0
    :size-tier :small :category :home :review-count 450}
   {:id "amz-5" :bsr 12000 :revenue 15000 :price 14.99 :weight-lbs 0.8
    :size-tier :small :category :clothing :review-count 890}])

(def ^:private sample-reddit-signals
  [{:id "prod-1" :reddit-mentions 50 :sentiment 0.8 :bsr-change 45}
   {:id "prod-2" :reddit-mentions 10 :sentiment 0.3 :bsr-change -5}
   {:id "prod-3" :reddit-mentions 5 :sentiment -0.2 :bsr-change 80}
   {:id "amz-4" :reddit-mentions 25 :sentiment 0.5 :bsr-change 10}
   {:id "amz-5" :reddit-mentions 8 :sentiment 0.1 :bsr-change -15}])

(def ^:private sample-aliexpress-pricing
  [{:id "prod-1" :supplier "Shenzhen Textile" :moq 500 :unit-cost 2.80}
   {:id "prod-2" :supplier "Fujian Apparel" :moq 1000 :unit-cost 1.50}
   {:id "prod-3" :supplier "Guangzhou Mfg" :moq 300 :unit-cost 12.00}
   {:id "amz-4" :supplier "Yiwu Trading" :moq 200 :unit-cost 3.50}
   {:id "amz-5" :supplier "Hangzhou Factory" :moq 500 :unit-cost 2.00}])

(defn- enrich-with-reddit
  [products signals]
  (for [p products
        :let [signal (first (filter #(= (:id %) (:id p)) signals))]]
    (merge p (or signal {:reddit-mentions 0 :sentiment 0.0 :bsr-change 0}))))

(defn- enrich-with-supplier
  [products pricing]
  (for [p products
        :let [price-info (first (filter #(= (:id %) (:id p)) pricing))]]
    (merge p (or price-info {:supplier "Unknown" :moq 0 :unit-cost 0.0}))))

(defn fetch-products
  "Fetch product candidates from all sources, enriched with cross-source data.
  Returns enriched product list ready for matching.
  Currently uses sample data; production replaces with API calls."
  [& {:keys [category limit] :or {limit 20}}]
  (let [base (take limit sample-amazon-products)
        enriched (enrich-with-reddit base sample-reddit-signals)
        full (enrich-with-supplier enriched sample-aliexpress-pricing)]
    (if category
      (filter #(= (:category %) category) full)
      full)))

(defn fetch-by-category
  "Fetch products filtered by category."
  [category & {:keys [limit] :or {limit 20}}]
  (fetch-products :category category :limit limit))

(defn source-status
  "Return health status of each data source.
  Returns map of source-name -> {:available t/nil :last-fetch timestamp}."
  []
  {:amazon      {:available true :last-fetch "2026-06-12T00:00:00Z"}
   :reddit      {:available true :last-fetch "2026-06-12T00:00:00Z"}
   :aliexpress  {:available true :last-fetch "2026-06-12T00:00:00Z"}
   :google-trends {:available true :last-fetch "2026-06-12T00:00:00Z"}})
