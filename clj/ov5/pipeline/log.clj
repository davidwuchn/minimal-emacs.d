(ns ov5.pipeline.log
  "Pipeline logging, log rotation, and lock file helpers.
   Preserves the exact [pipeline HH:MM:SS] log-line format so existing
   parsers keep working."
  (:require [clojure.java.io :as io]
            [clojure.string :as str]))

;; ---- paths ----

(defonce ^:private project-root*
  (atom (or (System/getenv "PIPELINE_PROJECT_ROOT")
            (System/getProperty "user.dir"))))

(defn set-project-root!
  "Set the project root for path resolution."
  [path]
  (reset! project-root* path))

(defn project-root
  "Resolve the project root directory."
  []
  @project-root*)

(defn log-dir
  "Resolve the log directory: default <project-root>/var/tmp/cron"
  []
  (or (System/getenv "LOG_DIR")
      (str (project-root) "/var/tmp/cron")))

(defn pipeline-log-path
  "Resolve the pipeline log file path."
  []
  (or (System/getenv "PIPELINE_LOG")
      (str (log-dir) "/pipeline.log")))

;; ---- logging ----

(defonce ^:private log-file* (atom nil))

(defn- ensure-log-dir
  []
  (let [d (log-dir)]
    (.mkdirs (io/file d))))

(defn- write-log-line
  "Append line to the pipeline log file."
  [line]
  (ensure-log-dir)
  (let [f (pipeline-log-path)]
    (spit (io/file f) (str line "\n") :append true)))

(defn log
  "Log a formatted message to stdout and the pipeline log file.
   Format: [pipeline HH:MM:SS] msg"
  [& msgs]
  (let [ts (.format (java.time.LocalTime/now)
                     (java.time.format.DateTimeFormatter/ofPattern "HH:mm:ss"))
        msg (str/join " " (map str msgs))
        line (str "[pipeline " ts "] " msg)]
    (println line)
    (try
      (write-log-line line)
      (catch Exception _
        nil))))

(defn logf
  "Log a format-string message. (logf \"thing: %s\" val)"
  [fmt & args]
  (apply log (apply format fmt args)))

;; ---- log rotation ----

(defn shift-rotate
  "Rename file.1 → file.2, file.2 → file.3, file → file.1, then truncate.
   Keeps at most 3 rotated copies."
  [f]
  (let [f-str (str f)
        f-3 (str f-str ".3")
        f-2 (str f-str ".2")
        f-1 (str f-str ".1")]
    (when (.exists (io/file f-3))
      (io/delete-file (io/file f-3) true))
    (when (.exists (io/file f-2))
      (.renameTo (io/file f-2) (io/file f-3)))
    (when (.exists (io/file f-1))
      (.renameTo (io/file f-1) (io/file f-2)))
    (when (.exists (io/file f))
      (.renameTo (io/file f) (io/file f-1)))
    (spit (io/file f) "")))

(defn log-rotate
  "Rotate a log file at path if it exceeds max-bytes (default 102400).
   Keeps at most 3 rotated copies: .1 (newest), .2, .3 (oldest)."
  ([filepath] (log-rotate filepath 102400))
  ([filepath max-bytes]
   (let [f (io/file filepath)]
     (when (.exists f)
       (let [size (.length f)]
         (when (>= size max-bytes)
           (shift-rotate f)
           (println (str "[pipeline "
                         (.format (java.time.LocalTime/now)
                                  (java.time.format.DateTimeFormatter/ofPattern "HH:mm:ss"))
                         "] Rotated " (.getName f) " (" size " bytes → .1)"))))))))

;; ---- lock file helpers ----

(defn current-pid
  "Return the current process PID as a long."
  []
  (.pid (java.lang.ProcessHandle/current)))

(def ^:private lock-shutdown-hooks (atom []))

(defn acquire-lock!
  "Acquire a PID-based lock file. If the lock exists and the owning process
   is alive, returns :already-locked. Otherwise writes current PID to lock-path,
   registers a JVM shutdown hook to clean it up, and returns :acquired."
  [lock-path]
  (let [f (io/file lock-path)
        lock-str (try (str/trim (slurp f)) (catch Exception _ nil))]
    (when (and lock-str (not (str/blank? lock-str)))
      (try
        (let [pid (Long/parseLong lock-str)]
          (when-let [ph (-> (java.lang.ProcessHandle/of pid) .orElse nil)]
            (when (.isAlive ph)
              (log "Pipeline already running (PID" pid "), skipping")
              (System/exit 0))))
        (catch NumberFormatException _ nil)))
    (.mkdirs (.getParentFile f))
    (spit f (str (current-pid)))
    (let [hook (Thread. (fn []
                          (try
                            (when (= (str (current-pid))
                                     (try (str/trim (slurp (io/file lock-path)))
                                          (catch Exception _ nil)))
                              (io/delete-file (io/file lock-path) true))
                            (catch Exception _ nil))))]
      (.addShutdownHook (Runtime/getRuntime) hook)
      (swap! lock-shutdown-hooks conj hook))
    :acquired))

(defn release-lock!
  "Release the lock file if current PID owns it."
  [lock-path]
  (let [f (io/file lock-path)]
    (when (.exists f)
      (let [lock-str (try (str/trim (slurp f)) (catch Exception _ nil))]
        (when (and lock-str
                   (try (= (current-pid) (Long/parseLong lock-str))
                        (catch NumberFormatException _ false)))
          (io/delete-file f true))))))
