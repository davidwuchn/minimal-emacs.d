(ns ov5.world-store.branch
  "Branch management for OV5 World Store.
   Implements branch create/switch/merge/promote/list/delete
   using separate Datahike databases per branch and an EDN registry."
  (:require [ov5.world-store :as ws]
            [datahike.pod :as d]))

;; -----------------------------------------------------------------------------
;; State

(def ^:private branch-conn (atom nil))
(def ^:private current-branch-id (atom nil))

;; -----------------------------------------------------------------------------
;; Paths (derived from JVM system property set by Elisp bridge)

(defn- store-paths-root
  "Return the root directory containing the main DB and branches/.
   Reads from JVM system property 'ov5.world-store.directory',
   environment variable OV5_WS_DIR, or defaults to var/world-store."
  []
  (System/getProperty "ov5.world-store.directory"
                      (or (System/getenv "OV5_WS_DIR") "var/world-store")))

(defn- registry-path
  "Return the absolute path to the branch registry EDN file."
  []
  (str (store-paths-root) "/branch-registry.edn"))

(defn- main-db-path
  "Return the path to the main branch database (store root)."
  []
  (store-paths-root))

(defn- branch-db-path
  "Return the path to a branch database."
  [branch-id]
  (str (store-paths-root) "/branches/" branch-id))

;; -----------------------------------------------------------------------------
;; Registry

(defn load-registry
  "Read the branch registry EDN file. Returns {} if file doesn't exist."
  []
  (let [rp (registry-path)]
    (if (.exists (java.io.File. rp))
      (try
        (let [content (slurp rp)]
          (if (string? content)
            (clojure.edn/read-string content)
            {}))
        (catch Exception _ {}))
      {})))

(defn save-registry
  "Write the registry map to EDN file atomically (temp-file + rename)."
  [registry]
  (let [rp (registry-path)
        dir (.getParent (java.io.File. rp))]
    (when dir
      (.mkdirs (java.io.File. dir)))
    (let [tmp (str rp ".tmp")]
      (spit tmp (pr-str registry))
      (.renameTo (java.io.File. tmp) (java.io.File. rp))
      registry)))

;; -----------------------------------------------------------------------------
;; Branch operations

(defn branch-ensure-main
  "Idempotently ensure the main branch exists in the registry.
   If a legacy main/ subdirectory exists, migrate its files to root.
   Returns the registry map (updated if needed)."
  []
  (let [reg (load-registry)]
    (if (contains? reg "main")
      reg
      (let [root-path (store-paths-root)
            root-dir (java.io.File. root-path)
            legacy-dir (java.io.File. (str root-path "/main"))]
        ;; Backward compat: migrate legacy main/ → root
        (when (.exists legacy-dir)
          (doseq [f (.listFiles legacy-dir)]
            (when (.isFile f)
              (.renameTo f (java.io.File. root-path (.getName f)))))
          (.delete legacy-dir))
        (.mkdirs root-dir)
        (let [new-reg (assoc reg "main"
                             {:branch/parent nil
                              :branch/status :active
                              :branch/created-at (str (java.time.Instant/now))})]
          (save-registry new-reg)
          new-reg)))))
 
(declare delete-branch)
 
(defn create-branch
  "Create a new branch DB. branch-id is the branch name.
   parent-branch defaults to \"main\". Extra metadata is merged into registry entry.
   Returns branch-id on success, nil on failure."
  ([branch-id parent-branch & [metadata]]
   (when (and (string? branch-id) (not= branch-id ""))
     ;; Ensure main exists (idempotent, handles auto-migration)
     (branch-ensure-main)
     (let [reg (load-registry)]
       (when (contains? reg branch-id)
         ;; Delete existing branch first for idempotent re-creation
         (delete-branch branch-id))
       (let [db-path (branch-db-path branch-id)]
         ;; Create the branch Datahike DB
         (try
           (let [[conn _cfg] (ws/connect-to-path db-path)]
             (when conn
               (try (d/release-db (d/db conn)) (catch Exception _ nil))))
           (catch Exception e
             (prn :branch-create-error (.getMessage e))
             nil))
         ;; Register the branch
         (let [entry (merge
                      {:branch/parent (or parent-branch "main")
                       :branch/status :active
                       :branch/created-at (str (java.time.Instant/now))}
                      (when (map? metadata) metadata))
               new-reg (assoc (load-registry) branch-id entry)]
           (save-registry new-reg)
           branch-id))))))

(defn switch-branch
  "Switch the current World Store connection to branch-id.
   Disconnects any existing branch connection, then connects to the branch DB.
   For branch-id \"main\", connects to the main DB.
   Returns branch-id on success, nil on failure."
  [branch-id]
  (when (string? branch-id)
    ;; Disconnect current branch connection if any
    (when-let [conn @branch-conn]
      (try
        (d/release-db (d/db conn))
        (catch Exception _ nil))
      (reset! branch-conn nil)
      (ws/set-store-conn! nil))
    ;; Connect to target branch
    (let [db-path (if (= branch-id "main")
                    (main-db-path)
                    (branch-db-path branch-id))]
      (try
        (let [[conn _cfg] (ws/connect-to-path db-path)]
          (reset! branch-conn conn)
          (ws/set-store-conn! conn)
          (reset! current-branch-id branch-id)
          branch-id)
        (catch Exception e
          (prn :branch-switch-error (.getMessage e))
          (reset! current-branch-id nil)
          nil)))))

(defn current-branch
  "Return the current branch-id string, or nil."
  []
  @current-branch-id)

(defn list-branches
  "Return the registry map of all branches as a vector of [branch-id metadata] pairs."
  []
  (vec (load-registry)))

(defn delete-branch
  "Delete a branch. Refuses to delete \"main\".
   Removes DB directory and registry entry.
   Returns true on success, nil on failure."
  [branch-id]
  (when (and (string? branch-id) (not= branch-id "main"))
    ;; Switch away if this is the active branch
    (when (= branch-id @current-branch-id)
      (switch-branch "main"))
    (let [db-path (branch-db-path branch-id)
          db-dir (java.io.File. db-path)]
      ;; Delete DB files recursively
      (when (.exists db-dir)
        (doseq [f (reverse (file-seq db-dir))]
          (try (.delete f) (catch Exception _ nil))))
      ;; Remove from registry
      (let [reg (load-registry)
            new-reg (dissoc reg branch-id)]
        (save-registry new-reg)
        true))))

(defn merge-branch
  "Merge all experiment entities from source-branch into target-branch.
   Uses :db.unique/identity on :experiment/id for idempotent merge.
   Returns the number of new experiment entities transacted."
  [source-branch target-branch]
  (when (and (string? source-branch) (string? target-branch))
    (let [src-path (if (= source-branch "main")
                     (main-db-path)
                     (branch-db-path source-branch))
          tgt-path (if (= target-branch "main")
                     (main-db-path)
                     (branch-db-path target-branch))]
      (try
        ;; Read experiments from source
        (let [[src-conn _] (ws/connect-to-path src-path)
              src-db (d/db src-conn)
              experiments (d/q '[:find [(pull ?e [*]) ...]
                                 :where [?e :experiment/id _]]
                               src-db)
              clean-entities (mapv #(dissoc % :db/id) experiments)]
          (try (d/release-db src-db) (catch Exception _ nil))
          (if (seq clean-entities)
            (let [[tgt-conn _] (ws/connect-to-path tgt-path)
                  tgt-db (d/db tgt-conn)
                  before-count (count (d/q '[:find [?e ...]
                                             :where [?e :experiment/id _]]
                                           tgt-db))]
              (d/transact tgt-conn clean-entities)
              (let [tgt-db2 (d/db tgt-conn)
                    after-count (count (d/q '[:find [?e ...]
                                              :where [?e :experiment/id _]]
                                            tgt-db2))]
                (try (d/release-db tgt-db) (catch Exception _ nil))
                (try (d/release-db tgt-db2) (catch Exception _ nil))
                (- after-count before-count)))
            0))
        (catch Exception e
          (prn :merge-error (.getMessage e))
          0)))))

(defn promote-branch
  "Promote branch-id to become the new main.
   Merges branch experiment data into main, updates the registry:
   old main metadata is archived as main-@<timestamp>, branch metadata
   becomes the new main entry, and the old branch entry is removed.
   Returns true on success, nil on failure."
  [branch-id]
  (when (and (string? branch-id) (not= branch-id "main"))
    (let [reg (load-registry)]
      (when (contains? reg branch-id)
        ;; Disconnect from current branch
        (when-let [conn @branch-conn]
          (try (d/release-db (d/db conn)) (catch Exception _ nil))
          (reset! branch-conn nil)
          (reset! current-branch-id nil))
        ;; Merge branch experiment data into main
        (let [_merged (merge-branch branch-id "main")
              timestamp (str (java.time.Instant/now))
              archive-name (str "main-@" timestamp)]
          ;; Update registry
          (let [new-reg (-> reg
                            ;; Archive old main metadata
                            (assoc archive-name
                                   (assoc (get reg "main" {})
                                          :branch/status :archived
                                          :branch/archived-at timestamp))
                            ;; Promote branch metadata to main
                            (assoc "main"
                                   (assoc (get reg branch-id)
                                          :branch/parent nil
                                          :branch/status :active
                                          :branch/promoted-at timestamp))
                            ;; Remove old branch entry
                            (dissoc branch-id))]
            (save-registry new-reg)
            ;; Switch to new main
            (switch-branch "main")
            true))))))
