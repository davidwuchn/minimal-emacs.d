(ns ov5.pipeline.parse-args-test
  (:require [clojure.test :refer [deftest is testing]]
            [clojure.string :as str]))

(defn- get-parse-args-docstring []
  (let [source (slurp "clj/ov5/pipeline.clj")
        match (re-find #"defn- parse-args\s*\"([^\"]+)\"" source)]
    (second match)))

(defn- get-parse-args-flags []
  (let [source (slurp "clj/ov5/pipeline.clj")
        result (re-seq #"--\S+\"\s*\(assoc acc :(\S+)" source)]
    (map second result)))

(deftest docstring-mentions-dry-run
  (is (str/includes? (get-parse-args-docstring) ":dry-run")))

(deftest docstring-matches-implementation-flags
  (doseq [key (get-parse-args-flags)]
    (is (str/includes? (get-parse-args-docstring) (str ":" key)))))
