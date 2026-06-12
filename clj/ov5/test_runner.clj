;; ov5/test_runner.clj — Clojure test runner for OV5 experiment loop
;; Usage: brepl -f clj/ov5/test_runner.clj
;; Scans clj/ for *_test.clj files, loads them, runs clojure.test, exits with code.

(require 'clojure.test)
(require 'clojure.java.io)

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
      (clojure.string/replace #"\.clj$" "")
      (symbol)))

(let [files (find-test-files test-dir)]
  (println (str "Found " (count files) " test file(s): " (pr-str files)))
  (if (empty? files)
    (do (println "0 tests, 0 failures, 0 errors.") (System/exit 0))
    (do
      (doseq [f files]
        (let [ns-sym (ns-from-file f)]
          (println (str "Loading " f " (" ns-sym ")"))
          (try (load-file f)
            (catch Exception e
              (println (str "ERROR loading " f ": " (.getMessage e)))))))
      (let [results (apply clojure.test/run-tests
                           (map ns-from-file files))]
        (let [total (+ (:pass results) (:fail results) (:error results))]
          (println (str "\nRan " total " tests containing "
                        (+ (:pass results) (:fail results) (:error results)) " assertions."))
          (println (str (:fail results) " failures, " (:error results) " errors.")))
        (System/exit (if (zero? (+ (:fail results) (:error results))) 0 1))))))
