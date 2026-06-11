(ns ov5.world-store.migration
  "Migrate experiment TSV files into the World Store."
  (:require [clojure.string :as str]
            [ov5.world-store :as ws]))

;; -----------------------------------------------------------------------------
;; Schema mapping

(def column-schemas
  "Map of column count → ordered column names."
  {30 [:experiment_id :target :hypothesis :score_before :score_after
       :code_quality :delta :decision :duration :grader_quality
       :grader_reason :comparator_reason :analyzer_patterns :agent_output
       :output_chars :backend :prompt_chars :sections_included
       :exploration_axis :candidate_scores :strategy :research_strategy
       :research_hash :research_quality :controller_decision :kibcm_axis
       :model :eight_key_scores :skills :edit_mode]
   39 [:experiment_id :target :hypothesis :score_before :score_after
       :code_quality :delta :decision :duration :grader_quality
       :grader_reason :comparator_reason :analyzer_patterns :agent_output
       :output_chars :backend :prompt_chars :sections_included
       :exploration_axis :candidate_scores :strategy :research_strategy
       :research_hash :research_quality :controller_decision :kibcm_axis
       :model :eight_key_scores :skills :edit_mode
       :cost_usd :effort_level :prod_error_rate_before :prod_error_rate_after
       :prod_error_rate_delta :user_satisfaction_delta :support_tickets_reduced
       :business_value_score :risk_score]
   43 [:experiment_id :target :hypothesis :score_before :score_after
       :code_quality :delta :decision :duration :grader_quality
       :grader_reason :comparator_reason :analyzer_patterns :agent_output
       :output_chars :backend :prompt_chars :sections_included
       :exploration_axis :candidate_scores :strategy :research_strategy
       :research_hash :research_quality :controller_decision :kibcm_axis
       :model :eight_key_scores :skills :edit_mode
       :cost_usd :effort_level :prod_error_rate_before :prod_error_rate_after
       :prod_error_rate_delta :user_satisfaction_delta :support_tickets_reduced
       :business_value_score :risk_score
       :complexity_before :complexity_after :lines_removed :understanding_score]})

;; Attribute mapping: TSV column → Datahike attribute
(def attribute-map
  {:experiment_id    :experiment/id
   :target           :experiment/target
   :hypothesis       :experiment/hypothesis
   :score_before     :experiment/score-before
   :score_after      :experiment/score-after
   :code_quality     :experiment/code-quality
   :delta            :experiment/delta
   :decision         :experiment/decision
   :duration         :experiment/duration
   :grader_quality   :experiment/grader-quality
   :grader_reason    :experiment/grader-reason
   :comparator_reason :experiment/comparator-reason
   :analyzer_patterns :experiment/analyzer-patterns
   :agent_output     :experiment/agent-output
   :output_chars     :experiment/output-chars
   :backend          :experiment/backend
   :prompt_chars     :experiment/prompt-chars
   :sections_included :experiment/sections-included
   :exploration_axis :experiment/exploration-axis
   :candidate_scores :experiment/candidate-scores
   :strategy         :experiment/strategy
   :research_strategy :experiment/research-strategy
   :research_hash    :experiment/research-hash
   :research_quality :experiment/research-quality
   :controller_decision :experiment/controller-decision
   :kibcm_axis       :experiment/kibcm-axis
   :model            :experiment/model
   :eight_key_scores :experiment/eight-key-scores
   :skills           :experiment/skills
   :edit_mode        :experiment/edit-mode
   :cost_usd         :experiment/cost-usd
   :effort_level     :experiment/effort-level
   :prod_error_rate_before :experiment/prod-error-rate-before
   :prod_error_rate_after  :experiment/prod-error-rate-after
   :prod_error_rate_delta  :experiment/prod-error-rate-delta
   :user_satisfaction_delta :experiment/user-satisfaction-delta
   :support_tickets_reduced :experiment/support-tickets-reduced
   :business_value_score    :experiment/business-value-score
   :risk_score              :experiment/risk-score
   :complexity_before       :experiment/complexity-before
   :complexity_after        :experiment/complexity-after
   :lines_removed           :experiment/lines-removed
   :understanding_score     :experiment/understanding-score})

;; -----------------------------------------------------------------------------
;; Parsing helpers

(defn- parse-double [s]
  (when (and s (not= s "") (not= s "nil") (not= s "?"))
    (try (Double/parseDouble s)
         (catch Exception _ nil))))

(defn- parse-long [s]
  (when (and s (not= s "") (not= s "nil") (not= s "?"))
    (try (Long/parseLong s)
         (catch Exception _ nil))))

(defn- parse-keyword [s]
  (when (and s (not= s "") (not= s "nil") (not= s "?"))
    (keyword s)))

(defn- parse-string [s]
  (when (and s (not= s "") (not= s "nil"))
    s))

;; Type coercion per attribute
(def attribute-types
  {:experiment/score-before     parse-double
   :experiment/score-after      parse-double
   :experiment/code-quality     parse-double
   :experiment/delta            parse-double
   :experiment/duration         parse-long
   :experiment/grader-quality   parse-double
   :experiment/output-chars     parse-long
   :experiment/prompt-chars     parse-long
   :experiment/decision         parse-keyword
   :experiment/controller-decision parse-keyword
   :experiment/cost-usd         parse-double
   :experiment/effort-level     parse-keyword
   :experiment/prod-error-rate-before  parse-double
   :experiment/prod-error-rate-after   parse-double
   :experiment/prod-error-rate-delta   parse-double
   :experiment/user-satisfaction-delta parse-double
   :experiment/support-tickets-reduced parse-long
   :experiment/business-value-score    parse-double
   :experiment/risk-score              parse-double
   :experiment/complexity-before       parse-double
   :experiment/complexity-after        parse-double
   :experiment/lines-removed           parse-long
   :experiment/understanding-score     parse-double})

;; -----------------------------------------------------------------------------
;; Row parsing

(defn- parse-row
  "Parse a TSV row (vector of strings) into an entity map."
  [cols header]
  (let [col-names (get column-schemas (count cols))]
    (if (nil? col-names)
      (do (println (str "[migration] WARNING: Unknown column count: " (count cols)))
          nil)
      (into {} (for [i (range (count cols))
                     :let [col-name (nth col-names i nil)
                           attr (get attribute-map col-name)
                           raw (nth cols i nil)
                           parser (get attribute-types attr parse-string)
                           val (parser raw)]
                     :when (and attr val)]
                 [attr val])))))

;; -----------------------------------------------------------------------------
;; File migration

(defn- tsv-rows
  "Lazy seq of rows from a TSV file. Each row is a vector of strings."
  [path]
  (with-open [rdr (clojure.java.io/reader path)]
    (doall
     (let [lines (line-seq rdr)]
       (rest lines)))))  ;; skip header

(defn- safe-split
  "Split a TSV line, handling empty fields."
  [line]
  (str/split line #"\t" -1))

(defn- run-id-from-path
  "Extract run ID from TSV file path.
   e.g. .../2026-06-11T110420Z-4a49/results.tsv → 2026-06-11T110420Z-4a49"
  [path]
  (let [dir (.getParentFile (clojure.java.io/file path))]
    (.getName dir)))

(defn- make-unique-id
  "Make experiment ID unique by prefixing with run ID."
  [run-id exp-id]
  (str run-id "#" exp-id))

(defn migrate-file
  "Migrate a single TSV file into the World Store.
   Optional STORE-PATH to connect to a specific store.
   Returns {:transacted n :skipped m :errors [...]}"
  ([path] (migrate-file path nil))
  ([path store-path]
   (when store-path
     (ws/connect store-path))
   (println (str "[migration] Processing: " path))
   (let [run-id (run-id-from-path path)
         lines (with-open [rdr (clojure.java.io/reader path)]
                 (doall (line-seq rdr)))
         header (safe-split (first lines))
         col-count (count header)
         _ (println (str "[migration]   Columns: " col-count "  Run: " run-id))
         rows (map safe-split (rest lines))
         results (atom {:transacted 0 :skipped 0 :errors []})]
     (doseq [row rows]
       (try
         (when-let [entity (parse-row row header)]
           ;; Make experiment ID unique per run
           (let [exp-id (:experiment/id entity)
                 unique-id (make-unique-id run-id exp-id)
                 entity* (assoc entity :experiment/id unique-id)]
             (if (seq entity*)
               (do (ws/transact [entity*])
                   (swap! results update :transacted inc))
               (swap! results update :skipped inc))))
         (catch Exception e
           (swap! results update :errors conj (.getMessage e)))))
     @results)))

;; -----------------------------------------------------------------------------
;; Batch migration

(defn migrate-directory
  "Migrate all results.tsv files under `dir` into the World Store.
   Optional STORE-PATH to connect to a specific store.
   Returns aggregate stats."
  ([dir] (migrate-directory dir nil))
  ([dir store-path]
   (when store-path
     (ws/connect store-path))
   (let [files (->> (file-seq (clojure.java.io/file dir))
                    (filter #(= "results.tsv" (.getName %)))
                    (map #(.getAbsolutePath %))
                    (sort))
         total (atom {:files 0 :transacted 0 :skipped 0 :errors []})]
     (println (str "[migration] Found " (count files) " TSV files"))
     (doseq [f files]
       (let [stats (migrate-file f)]
         (swap! total update :files inc)
         (swap! total update :transacted + (:transacted stats))
         (swap! total update :skipped + (:skipped stats))
         (swap! total update :errors into (:errors stats))))
     (println (str "[migration] DONE: " @total))
     @total)))

(defn migrate-all
  "Migrate all experiments from the default location."
  []
  (migrate-directory "var/tmp/experiments"))
