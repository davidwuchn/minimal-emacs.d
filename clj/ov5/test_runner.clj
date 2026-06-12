;; ov5/test_runner.clj — Clojure test runner for OV5 experiment loop
;; Usage: bb -f clj/ov5/test_runner.clj
;; Scans clj/ for *_test.clj files, loads them, runs clojure.test, exits with code.

(require 'clojure.test)
(require 'clojure.java.io)
(require 'clojure.string)

(def test-dir (clojure.java.io/file "clj"))

(defn- find-test-files [dir]
  (let [pattern #".*_test\.clj$"]
    (->> (file-seq dir)
         (filter #(.isFile %))
         (map #(.getPath %))
         (filter #(re-matches pattern %))
         (sort))))

(defn- ns-from-file [f]
  (-> f
      (clojure.string/replace #"^clj/" "")
      (clojure.string/replace #"/" ".")
      (clojure.string/replace #"_" "-")
      (clojure.string/replace #"\.clj$" "")
      (symbol)))

(let [files (find-test-files test-dir)]
  (println (str "Found " (count files) " test file(s): " (pr-str files)))
  (if (empty? files)
    (do (println "0 tests, 0 failures, 0 errors.") (System/exit 0))
    (let [loaded-ns (atom [])]
      (doseq [f files]
        (let [ns-sym (ns-from-file f)]
          (println (str "Loading " f " (" ns-sym ")"))
          (try
            (require ns-sym)
            (swap! loaded-ns conj ns-sym)
            (catch Exception e
              (println (str "ERROR loading " f ": " (.getMessage e)))))))
      (if (empty? @loaded-ns)
        (do (println "0 tests, 0 failures, 0 errors.") (System/exit 0))
        (let [results (apply clojure.test/run-tests @loaded-ns)
              total (+ (:pass results) (:fail results) (:error results))]
          (println (str "\nRan " total " tests containing "
                        (+ (:pass results) (:fail results) (:error results)) " assertions."))
          (println (str (:fail results) " failures, " (:error results) " errors."))
          (System/exit (if (zero? (+ (:fail results) (:error results))) 0 1)))))))
