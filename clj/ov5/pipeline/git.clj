(ns ov5.pipeline.git
  "Git sync operations: stash scoped to auto-generated directories,
   unmerged-path cleanup, fetch+rebase for bootstrap, and safe stash pop/drop."
  (:require [ov5.pipeline.log :as log]
            [ov5.pipeline.process :as proc :refer [sh-out sh-ok? sh-lines]]
            [clojure.string :as str]
            [clojure.java.io :as io]))

;; ---- configuration ----

(def auto-gen-dirs
  "Directories that contain auto-generated content. Changes inside these
   are stashed, cleared on conflict, and upstream-dominant on pull."
  ["mementum/knowledge/"
   "mementum/memories/"
   "assistant/skills/"
   "assistant/strategies/"])

(defn- default-repo
  "Default repo path from project root. Can be overridden."
  []
  (or (System/getenv "PIPELINE_PROJECT_ROOT")
      (System/getProperty "user.dir")))

;; ---- git command helpers ----

(defn- git
  "Run a git command in repo and return process result map."
  [repo & args]
  (let [full-args (into ["git" "-C" repo] (map str args))]
    (apply proc/sh full-args)))

(defn- git-out
  "Run a git command and return trimmed stdout."
  [repo & args]
  (apply sh-out "git" "-C" repo (map str args)))

(defn- git-ok?
  "Run a git command and return true if exit=0."
  [repo & args]
  (apply sh-ok? "git" "-C" repo (map str args)))

;; ---- unmerged paths ----

(defn- raw-unmerged-paths
  "Return a set of file paths that are currently unmerged (diff-filter=U)."
  [repo]
  (let [result (git repo "diff" "--name-only" "--diff-filter=U")]
    (if (= 0 (:exit result))
      (set (filter (comp not str/blank?) (str/split-lines (str/trim (:out result)))))
      #{})))

(defn has-unmerged-paths?
  "Return true if the repo has unmerged (conflict) paths."
  [repo]
  (boolean (seq (raw-unmerged-paths repo))))

(defn only-auto-gen-paths?
  "Return true if all given paths are inside auto-generated directories."
  [paths]
  (every? (fn [p]
            (some #(str/starts-with? p %) auto-gen-dirs))
          paths))

(defn clear-auto-generated-unmerged-paths!
  "Clear unmerged paths that belong to auto-generated directories.
   If non-auto-gen unmerged paths remain, log warning and return false."
  ([]
   (clear-auto-generated-unmerged-paths! (default-repo)))
  ([repo]
   (let [unmerged (raw-unmerged-paths repo)]
     (cond
       ;; No conflicts at all
       (empty? unmerged)
       true

       ;; All conflicts are in auto-gen dirs — safe to clear
       (only-auto-gen-paths? unmerged)
       (do
         (log/log "Clearing auto-generated merge conflicts before git sync")
         (git repo "merge" "--abort")
         (doseq [d auto-gen-dirs]
           (git-out repo "checkout" "HEAD" "--" d))
         (apply git repo "clean" "-fd" "--" auto-gen-dirs)
         (not (has-unmerged-paths? repo)))

       ;; Non-auto-gen conflicts present — do NOT clear
       :else
       (do
         (log/log "WARNING: non-auto-generated merge conflicts remain; skipping git sync")
         (doseq [p unmerged]
           (log/logf "[pipeline conflict] %s" p))
         false)))))

;; ---- stash helpers ----

(defn- stash-auto-gen!
  "Stash only auto-generated directory changes.
   Returns {:status :stashed | :none | :error, :output str}"
  ([repo label]
   (let [ts (System/currentTimeMillis)
         stash-msg (str label "-" ts)
         args (into ["git" "-C" repo "stash" "push" "--include-untracked"
                     "-m" stash-msg "--"]
                    auto-gen-dirs)
         result (apply proc/sh args)
         out (str/trim (:out result))
         err (str/trim (:err result))
         combined (str out "\n" err)]
     (cond
       (or (str/includes? combined "No local changes to save")
           (and (zero? (:exit result)) (str/blank? combined)))
       {:status :none :output combined}

       (or (str/includes? combined "Saved working directory")
           (str/includes? combined "Saved working tree"))
       {:status :stashed :output combined}

       :else
       {:status :error :output combined}))))

(defn- stash-pop!
  "Pop the most recent stash. If pop fails, drop the stash.
   Returns :popped or :dropped-or-skipped"
  [repo]
  (if (git-ok? repo "stash" "pop")
    :popped
    (do
      (log/log "WARNING: stash pop failed; dropping only the auto-gen stash")
      (git repo "stash" "drop")
      :dropped-or-skipped)))

;; ---- git sync ----

(defn git-sync-latest!
  "Full git sync with auto-gen-dir-scoped stash.
   1. Clear auto-generated unmerged paths.
   2. Stash only auto-gen dirs.
   3. git pull --rebase.
   4. Pop stash (safe: only auto-gen dirs, drop on conflict).
   label and stash-label are used in log messages."
  ([label stash-label]
   (git-sync-latest! (default-repo) label stash-label))
  ([repo label stash-label]
   (when-not (clear-auto-generated-unmerged-paths! repo)
     ;; non-auto-gen conflicts remain, log but don't throw
     (log/log "WARNING: skipping git sync due to non-auto-gen merge conflicts")
     :skipped)
   (let [stash-result (stash-auto-gen! repo stash-label)]
     (when (= :error (:status stash-result))
       (log/log "WARNING: git stash (auto-gen only) failed during" label "; continuing without stash pop")
       (log/logf "%s" (:output stash-result)))
     ;; Abort any lingering merge, then pull --rebase
     (git repo "merge" "--abort")
     ;; Reset auto-gen dirs to HEAD before pull (defensive)
     (doseq [d auto-gen-dirs]
       (git-out repo "checkout" "HEAD" "--" d))
     (doseq [d auto-gen-dirs]
       (git-out repo "clean" "-fd" "--" d))
     ;; Pull
     (let [pull-result (git repo "pull" "--rebase")]
       (when (not= 0 (:exit pull-result))
         (log/log "WARNING:" label "git pull failed")))
     ;; Pop stash if we created one
     (when (= :stashed (:status stash-result))
       (stash-pop! repo))
     :synced)))

;; ---- bootstrap: fetch + rebase + re-exec detection ----

(defn fetch-and-rebase!
  "Fetch origin/main, rebase onto it (stashing auto-gen dirs first).
   Returns :head-changed if rebase moved HEAD, :up-to-date otherwise.
   Caller should re-exec if HEAD changed."
  ([]
   (fetch-and-rebase! (default-repo)))
  ([repo]
   (let [head-before (try (sh-out "git" "-C" repo "rev-parse" "HEAD")
                          (catch Exception _ ""))]
     ;; Fetch
     (git repo "fetch" "origin" "main")
     ;; Stash auto-gen
     (git-out repo "stash" "-q")
     ;; Reset auto-gen dirs
     (doseq [d auto-gen-dirs]
       (git-out repo "checkout" "HEAD" "--" d))
     ;; Rebase
     (git repo "rebase" "origin/main")
     ;; Pop stash
     (git-out repo "stash" "pop" "-q")
     ;; Check if HEAD moved
     (let [head-after (try (sh-out "git" "-C" repo "rev-parse" "HEAD")
                           (catch Exception _ ""))]
       (if (and (not (str/blank? head-before))
                (not= head-before head-after))
         :head-changed
         :up-to-date)))))
