;; creatoros/demo.clj — end-to-end demo: fetch → score → match → display
(ns creatoros.demo
  (:require [creatoros.sources :as src]
            [creatoros.matching :as match]))

(defn print-product [p i]
  (println (str "  " (inc i) ". " (:id p)))
  (println (str "     Grade: " (name (:grade p)) " | Score: " (format "%.2f" (:composite p))))
  (println (str "     Price: $" (:price p) " | Margin: "
                (format "%.0f%%" (* 100 (double (/ (- (:price p) (:cogs p) (:fees p)) (:price p)))))))
  (println (str "     Cost: $" (format "%.2f" (:cogs p)) " | FBA: $" (format "%.2f" (:fees p))))
  (println (str "     Revenue potential: $" (format "%.0f" (:revenue-potential p))))
  (when (:supplier p)
    (println (str "     Supplier: " (:supplier p) " (MOQ: " (:moq p) ")")))
  (println))

(defn -main [& args]
  (let [niche (keyword (or (first args) "beauty"))
        followers (try (Long/parseLong (or (second args) "280000")) (catch Exception _ 280000))
        country (or (nth args 2) "US")
        creator {:niche niche :followers followers :country country}
        products (src/fetch-products :category niche)
        matches (match/match creator products)]
    (println (str "\n=== CreatorOS Demo ===\n"))
    (println (str "Creator: " followers " followers, niche: " (name niche) ", country: " country))
    (println (str "Products found: " (count products) " in category"))
    (println (str "Matches: " (count matches) "\n"))
    (doseq [i (range (count matches))]
      (print-product (nth matches i) i))
    (println "=== Demo complete ===\n")))

(when (= *file* (System/getProperty "babashka.file"))
  (apply -main *command-line-args*))
