(ns ov5.pipeline.process
  "Process/spawn/pgrep/kill helpers for the pipeline.
   All subprocess calls set TMPDIR=/tmp for emacsclient socket discovery."
  (:require [babashka.process :as p]
            [clojure.string :as str]))

;; ---- common ----

(def ^:private default-env
  {"TMPDIR" "/tmp"})

(defn- extra-env
  "Extra env merged with default TMPDIR=/tmp"
  ([]
   default-env)
  ([extra]
   (merge default-env extra)))

(def ^:private default-opts
  {:out :string
   :err :string
   :env (extra-env)})

;; ---- shell helpers ----

(defn sh
  "Run a command with default options. Returns babashka.process result map
   with :out, :err, :exit keys."
  [& args]
  (apply p/shell (merge default-opts {:continue true}) args))

(defn sh-out
  "Run command and return trimmed stdout string."
  [& args]
  (str/trim (:out (apply sh args))))

(defn sh-lines
  "Run command and return stdout as a vector of lines."
  [& args]
  (str/split-lines (apply sh-out args)))

(defn sh-ok?
  "Run command and return true if exit code is 0."
  [& args]
  (= 0 (:exit (apply sh args))))

(defn exec!
  "Execute a command and raise if non-zero exit."
  [& args]
  (let [proc (apply p/process (merge default-opts {:continue false}) args)
        {:keys [exit out err]} @proc]
    (when (not= 0 exit)
      (throw (ex-info (str "Command failed with exit " exit ": " (str/join " " args))
                      {:exit exit :out out :err err})))
    (str/trim out)))

;; ---- pgrep / process discovery ----

(defn pgrep
  "Run pgrep -f <pattern> and return a vector of PID strings.
   Returns empty vector if pgrep not found or no matches."
  [pattern]
  (let [result (apply sh "pgrep" "-f" pattern)]
    (if (= 0 (:exit result))
      (filterv (comp not str/blank?)
               (str/split-lines (str/trim (:out result))))
      [])))

;; ---- kill helpers ----

(defn kill-pid
  "Send signal to a process by PID string. Returns true if successful."
  ([pid]
   (kill-pid pid "KILL"))
  ([pid signal]
   (try
     (let [sig (if (keyword? signal) (name signal) (str signal))]
       (= 0 (:exit (apply sh "kill" (str "-" sig) pid))))
     (catch Exception _
       false))))

(defn kill-by-pattern!
  "Find processes matching pattern, send SIGKILL, wait 2s, retry survivors.
   Returns {:killed N :survivors []}."
  [pattern & {:keys [wait-ms] :or {wait-ms 2000}}]
  (let [pids (pgrep pattern)]
    (if (empty? pids)
      {:killed 0 :survivors []}
      (do
        (doseq [pid pids]
          (kill-pid pid "KILL"))
        (Thread/sleep wait-ms)
        (let [survivors (pgrep pattern)]
          (if (empty? survivors)
            {:killed (count pids) :survivors []}
            (do
              (doseq [pid survivors]
                (kill-pid pid "KILL"))
              (Thread/sleep 2000)
              (let [final-survivors (pgrep pattern)]
                {:killed (- (count pids) (count final-survivors))
                 :survivors final-survivors}))))))))

(defn process-alive?
  "Check if a PID is a live process."
  [pid]
  (let [pid-num (try (Long/parseLong (str pid))
                     (catch NumberFormatException _ nil))]
    (if pid-num
      (when-let [ph (-> (java.lang.ProcessHandle/of pid-num) .orElse nil)]
        (.isAlive ph))
      false)))

(defn wait-for-exit
  "Wait up to timeout-ms for a process to exit. Returns :exited or :timeout."
  [pid timeout-ms]
  (let [deadline (+ (System/currentTimeMillis) timeout-ms)]
    (loop []
      (if (not (process-alive? pid))
        :exited
        (if (< (System/currentTimeMillis) deadline)
          (do (Thread/sleep 200) (recur))
          :timeout)))))
