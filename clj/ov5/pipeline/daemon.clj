(ns ov5.pipeline.daemon
  "Full port of cron daemon-management actions: status, stop, research,
   evolution, auto-workflow, plus daemon lifecycle (start/stop/check) and
   wait-for-idle polling logic.  Previously handled by run-auto-workflow-cron.sh;
   now invoked directly by the Clojure pipeline orchestrator."
  (:require [ov5.pipeline.log :as log]
            [ov5.pipeline.process :as proc :refer [sh-out sh-ok? sh-lines]]
            [clojure.java.io :as io]
            [clojure.string :as str]
            [babashka.process :as p]))

;; ═══════════════════════════════════════════════════════════════════════════════
;; Helpers
;; ═══════════════════════════════════════════════════════════════════════════════

(defn- uid
  "Current user id as string."
  []
  (try (sh-out "id" "-u") (catch Exception _ "501")))

(def ^:private uid*
  (memoize uid))

(defn- project-root
  "Project root directory."
  []
  (or (System/getenv "PIPELINE_PROJECT_ROOT")
      (System/getProperty "user.dir")))

;; ═══════════════════════════════════════════════════════════════════════════════
;; Socket / path resolution (ported from run-auto-workflow-cron.sh:15-35)
;; ═══════════════════════════════════════════════════════════════════════════════

(defn find-server-socket
  "Find an Emacs server socket by name. Tries candidate paths in order,
   returns the socket path string or nil."
  ([name]
   (find-server-socket name (uid*) (or (System/getenv "XDG_RUNTIME_DIR")
                                       (str "/run/user/" (uid*)))
                       (or (System/getenv "TMPDIR") "/tmp")))
  ([name uid-val runtime-dir tmpdir]
   (let [candidates (distinct
                     (filter some?
                             [(when runtime-dir (str runtime-dir "/emacs/" name))
                              (str tmpdir "/emacs" uid-val "/" name)
                              (str "/tmp/emacs" uid-val "/" name)
                              (str "/run/user/" uid-val "/emacs/" name)]))]
     (some (fn [path]
             (when-let [f (io/file path)]
               (when (and (.exists f)
                          (try
                            ;; check if it's a socket (using stat approximation)
                            (let [result (proc/sh "test" "-S" path)]
                              (= 0 (:exit result)))
                            (catch Exception _ false)))
                 path)))
           candidates))))

;; ═══════════════════════════════════════════════════════════════════════════════
;; Emacsclient / Emacs resolution (ported from lines 103-147)
;; ═══════════════════════════════════════════════════════════════════════════════

(defn resolve-emacsclient
  "Find emacsclient binary. Returns path string or nil."
  []
  (or (try (sh-out "command" "-v" "emacsclient") (catch Exception _ nil))
      (when (.exists (io/file "/opt/homebrew/bin/emacsclient"))
        "/opt/homebrew/bin/emacsclient")
      (when (.exists (io/file "/usr/local/bin/emacsclient"))
        "/usr/local/bin/emacsclient")))

(defn resolve-emacs
  "Find emacs binary. Returns path string or nil."
  []
  (or (try (sh-out "command" "-v" "emacs") (catch Exception _ nil))
      (when (.exists (io/file "/opt/homebrew/bin/emacs"))
        "/opt/homebrew/bin/emacs")
      (when (.exists (io/file "/usr/local/bin/emacs"))
        "/usr/local/bin/emacs")
      (when (.exists (io/file "/Applications/Emacs.app/Contents/MacOS/Emacs"))
        "/Applications/Emacs.app/Contents/MacOS/Emacs")))

;; ═══════════════════════════════════════════════════════════════════════════════
;; Daemon check / lifecycle (ported from lines 627-707, 933-1047)
;; ═══════════════════════════════════════════════════════════════════════════════

(defn check-worker-daemon
  "Check if the worker daemon is reachable via emacsclient.
   Returns :alive, :timeout, or :dead."
  ([server-name]
   (check-worker-daemon server-name (or (resolve-emacsclient) "emacsclient")))
  ([server-name emacsclient-path]
   (letfn [(try-check [timeout]
             (try
               (let [result (p/shell {:out :string :err :string
                                      :continue true
                                      :timeout timeout}
                                     emacsclient-path
                                     "-a" "false"
                                     "-s" server-name
                                     "--eval" "t")]
                 (if (and (= 0 (:exit result)) (str/includes? (:out result) "t"))
                   :alive
                   :dead))
               (catch Exception e
                 ;; Check for timeout
                 (let [msg (.getMessage e)]
                   (if (or (str/includes? (str msg) "Timeout")
                           (str/includes? (str msg) "timeout"))
                     :timeout
                     :dead)))))]
     (let [first-check (try-check 1000)]
       (if (= :alive first-check)
         :alive
         (let [second-check (try-check 3000)]
           second-check))))))

(defn- worker-daemon-pids
  "Find PIDs for worker daemons matching server-name."
  [server-name]
  (try
    (let [result (proc/sh "pgrep" "-f" (str "emacs.*daemon.*" server-name))]
      (if (= 0 (:exit result))
        (filterv (comp not str/blank?) (str/split-lines (str/trim (:out result))))
        []))
    (catch Exception _ [])))

;; Forward declarations for mutual references
(declare default-status!)

(defn default-status!
  "Write default (idle) status to status-file."
  [status-file]
  (let [f (io/file status-file)]
    (.mkdirs (.getParentFile f))
    (spit f "(:running nil :kept 0 :total 0 :phase \"idle\" :results nil :store \"var/world-store\")\n")))

(defn clean-stale-socket
  "Clean up a stale socket for name from all candidate directories."
  [name]
  (let [uid-val (uid*)
        bases (filter some? (distinct [(System/getenv "TMPDIR") "/tmp" (System/getenv "XDG_RUNTIME_DIR")]))]
    (doseq [base bases]
      (when base
        (let [sock (io/file (str base "/emacs" uid-val "/" name))]
          (when (or (.exists sock))
            (io/delete-file sock true)
            (log/log "Cleared stale socket:" (str sock)))))
      ;; Also try XDG_RUNTIME_DIR/emacs/name pattern
      (when (and base (.exists (io/file (str base "/emacs/" name))))
        (io/delete-file (io/file (str base "/emacs/" name)) true)))))

(defn discard-stale-worker-daemon!
  "Force-kill stale daemon processes for server-name, clean up sockets,
   reset status to idle."
  [server-name & {:keys [status-file] :or {status-file nil}}]
  (let [pids (worker-daemon-pids server-name)]
    (doseq [pid pids]
      (try
        (proc/sh "kill" "-9" pid)
        (catch Exception _ nil)))
    ;; Wait up to 3s for processes to die
    (dotimes [_ 10]
      (when (some (fn [pid] (proc/process-alive? pid)) pids)
        (Thread/sleep 300)))
    ;; Force-kill survivors
    (doseq [pid pids]
      (when (proc/process-alive? pid)
        (try (proc/sh "kill" "-9" pid) (catch Exception _ nil))))
    ;; Clean sockets
    (clean-stale-socket server-name)
    ;; Rewrite status idle if status-file provided
    (when status-file
      (default-status! status-file))
    :discarded))

;; ═══════════════════════════════════════════════════════════════════════════════
;; ensure-worker-daemon (ported from lines 933-1047)
;; ═══════════════════════════════════════════════════════════════════════════════

(defn- hydrate-missing-worktree-submodules
  "Initialize missing submodules for worktrees. Ported from lines 172-209."
  [repo-path]
  (let [gitmodules (io/file repo-path ".gitmodules")]
    (when (.exists gitmodules)
      ;; submodule sync + update
      (try
        (proc/sh "git" "-C" repo-path "submodule" "sync")
        (proc/sh "git" "-C" repo-path "submodule" "update" "--init" "--recursive")
        (catch Exception _ nil))))
  :hydrated)

(defn- common-root-var
  "Find common git root for symlinking shared var (elpa, etc.)."
  [repo-path]
  (try
    (let [common (str/trim (sh-out "git" "-C" repo-path "rev-parse" "--git-common-dir"))]
      (if (.startsWith common "/")
        (.getParent (io/file common))
        (let [abs (io/file repo-path common)]
          (.getParent (.getCanonicalFile abs)))))
    (catch Exception _ repo-path)))

(defn- seed-worker-daemon-var
  "Symlink shared var directories from common root to worktree. Ported from lines 211-237."
  [repo-path]
  (let [common-root (common-root-var repo-path)]
    (when-not (= common-root repo-path)
      (let [shared-var (io/file common-root "var")
            target-var (io/file repo-path "var")]
        (when (.exists (io/file shared-var "elpa"))
          (.mkdirs (io/file target-var "elpa"))
          (doseq [entry (.listFiles (io/file shared-var "elpa"))]
            (let [target (io/file target-var "elpa" (.getName entry))]
              (when (and (not (.exists target)) (not (java.nio.file.Files/isSymbolicLink (.toPath target))))
                (try
                  (java.nio.file.Files/createSymbolicLink
                   (.toPath target)
                   (.toPath entry))
                  (catch Exception _ nil))))))
        ;; package-quickstart.el and tree-sitter
        (doseq [rel ["package-quickstart.el" "tree-sitter"]]
          (let [src (io/file shared-var rel)
                tgt (io/file target-var rel)]
            (when (and (.exists src) (not (.exists tgt)))
              (try
                (java.nio.file.Files/createSymbolicLink (.toPath tgt) (.toPath src))
                (catch Exception _ nil)))))))))

(defn ensure-worker-daemon!
  "Ensure a worker daemon for SERVER-NAME is running. If not, start one.
   This is the most complex function — ported from ensure_worker_daemon()
   bash function (lines 933-1047)."
  [{:keys [server-name action repo-path daemon-log]
    :or {repo-path (project-root)
         daemon-log (str (project-root) "/var/tmp/cron/" server-name ".log")}
    :as opts}]
  (let [emacs-path (or (:emacs-path opts) (resolve-emacs) "emacs")
        emacsclient-path (or (:emacsclient-path opts) (resolve-emacsclient) "emacsclient")]
    ;; 1. Check if already alive
    (let [state (check-worker-daemon server-name emacsclient-path)]
      (when (= :alive state)
        :already-running))
    ;; 2. Kill stale PIDs
    (let [stale-pids (worker-daemon-pids server-name)]
      (when (seq stale-pids)
        (log/logf "Killing stale daemon: %s (pids: %s)" server-name (str/join " " stale-pids))
        (discard-stale-worker-daemon! server-name)
        (Thread/sleep 1000)))
    ;; 3. Clean orphaned sockets
    (clean-stale-socket server-name)
    ;; Verify socket is gone (up to 60 retries)
    (loop [i 0]
      (let [sock (find-server-socket server-name)]
        (when (and sock (< i 60))
          (Thread/sleep 200)
          (recur (inc i)))))
    ;; Force-remove if still present
    (let [sock (find-server-socket server-name)]
      (when sock
        (log/logf "WARNING: Socket for %s still present after cleanup. Force-removing..." server-name)
        (let [uid-val (uid*)]
          (try (io/delete-file (io/file (str "/tmp/emacs" uid-val "/" server-name)) true)
               (catch Exception _ nil))
          (try (io/delete-file (io/file (str (System/getenv "TMPDIR") "/emacs" uid-val "/" server-name)) true)
               (catch Exception _ nil))
          (when-let [xdg (System/getenv "XDG_RUNTIME_DIR")]
            (try (io/delete-file (io/file (str xdg "/emacs/" server-name)) true)
                 (catch Exception _ nil))))))
    ;; 4. Clear stale eln cache
    (let [eln-dir (io/file repo-path "var/eln-cache")]
      (when (.exists eln-dir)
        (doseq [f (file-seq eln-dir)]
          (when (and (.isFile f) (str/ends-with? (.getName f) ".eln"))
            (try (io/delete-file f true) (catch Exception _ nil))))))
    ;; 5. Hydrate submodules
    (hydrate-missing-worktree-submodules repo-path)
    ;; 6. Seed shared var
    (seed-worker-daemon-var repo-path)
    ;; 7. Launch daemon
    (let [daemon-log-file (io/file daemon-log)]
      (.mkdirs (.getParentFile daemon-log-file))
      (let [inner-cmd (str
                       "ulimit -s 65532 2>/dev/null; "
                       "ulimit -v 4194304 2>/dev/null; "
                       "exec '" emacs-path "' --init-directory='" repo-path "' "
                       "--daemon='" server-name "' "
                       "--eval \"(setq native-comp-jit-compilation nil gc-cons-threshold (* 50 1024 1024))\" "
                       "</dev/null >>'" daemon-log "' 2>&1")
            env-opts (merge {"EMACSNATIVELOADPATH" ""
                             "AUTO_WORKFLOW_EMACS_SERVER" server-name
                             "MINIMAL_EMACS_WORKFLOW_ROLE" (or action "")
                             "MINIMAL_EMACS_ALLOW_SECOND_DAEMON" "1"
                             "MINIMAL_EMACS_WORKFLOW_DAEMON" "1"})
            launch-cmd [emacs-path
                        "--init-directory" repo-path
                        "--daemon" server-name
                        "--eval" "(setq native-comp-jit-compilation nil gc-cons-threshold (* 50 1024 1024))"]]
        ;; Try setsid for session isolation
        (if (sh-ok? "command" "-v" "setsid")
          (let [setsid-cmd ["setsid" "env"
                            "-u" "DISPLAY" "-u" "WAYLAND_DISPLAY"
                            "-u" "WAYLAND_SOCKET" "-u" "XAUTHORITY"
                            "bash" "-c" inner-cmd]]
            (try
              ;; Start as background process (not waited)
              (apply p/process {:out :inherit :err :inherit :env env-opts} setsid-cmd)
              (catch Exception e
                (log/logf "ERROR launching daemon via setsid: %s" (.getMessage e))
                ;; Fallback: launch directly
                (apply p/process {:out :inherit :err :inherit :env env-opts} launch-cmd))))
          (apply p/process {:out :inherit :err :inherit :env env-opts} launch-cmd)))
      ;; 8. Poll up to 150*0.2s for daemon to respond
      (loop [i 0]
        (let [state (check-worker-daemon server-name emacsclient-path)]
          (if (= :alive state)
            :started
            (if (< i 150)
              (do (Thread/sleep 200) (recur (inc i)))
              (do
                (log/logf "failed to start worker daemon: %s" server-name)
                (log/logf "Last 40 lines of daemon log:")
                (try
                  (let [log-content (slurp daemon-log-file)]
                    (doseq [line (take-last 40 (str/split-lines log-content))]
                      (log/log line)))
                  (catch Exception _ nil))
                :failed))))))))

;; ═══════════════════════════════════════════════════════════════════════════════
;; Elisp generation helpers (ported from lines 710-829)
;; ═══════════════════════════════════════════════════════════════════════════════

(defn- lisp-escape
  "Escape a string for embedding in elisp."
  [s]
  (-> s
      (str/replace "\\" "\\\\")
      (str/replace "\"" "\\\"")))

(defn- wrap-emacs-eval
  "Wrap an elisp body with environment setup for workflow actions."
  [body & {:keys [action status-file messages-file ssh-auth-sock git-ssh-command]}]
  (let [env-sets (str/join " "
                           (filter some?
                                   [(when status-file
                                      (format "(setenv \"AUTO_WORKFLOW_STATUS_FILE\" \"%s\")"
                                              (lisp-escape status-file)))
                                    (when messages-file
                                      (format "(setenv \"AUTO_WORKFLOW_MESSAGES_FILE\" \"%s\")"
                                              (lisp-escape messages-file)))
                                    (when ssh-auth-sock
                                      (format "(setenv \"SSH_AUTH_SOCK\" \"%s\")"
                                              (lisp-escape ssh-auth-sock)))
                                    (when git-ssh-command
                                      (format "(setenv \"GIT_SSH_COMMAND\" \"%s\")"
                                              (lisp-escape git-ssh-command)))]))]
    (format "(with-current-buffer (get-buffer-create \"*pmf-value-stream-eval*\") %s %s)"
            env-sets body)))

;; ═══════════════════════════════════════════════════════════════════════════════
;; Emacsclient eval (ported from lines 589-625)
;; ═══════════════════════════════════════════════════════════════════════════════

(defn run-emacsclient-eval
  "Evaluate elisp code on a named daemon socket.
   Returns {:exit N, :out str, :err str}.
   Handles 'Server not responding', 'Server did not reply', and timeouts."
  [server-name elisp-code & {:keys [timeout] :or {timeout 10}}]
  (let [emacsclient-path (or (resolve-emacsclient) "emacsclient")]
    (try
      (let [result (proc/sh emacsclient-path
                            "-a" "false"
                            "-s" server-name
                            "--eval" elisp-code
                            :timeout timeout)
            out (str/trim (:out result))
            err (str/trim (:err result))
            exit (:exit result)]
        (cond
          ;; Timeout (process throws, but check for 124)
          (= 124 exit)
          (do (when (not (str/blank? out)) (log/log out))
              {:exit 124 :out out :err err :timeout true})

          ;; Server not responding / server did not reply
          (and (not= 0 exit)
               (or (str/includes? (str out err) "Server not responding")
                   (str/includes? (str out err) "server did not reply")))
          (do (when (not (str/blank? (str out err))) (log/log (str out err)))
              {:exit 124 :out out :err err :timeout true})

          ;; Connection refused but socket exists
          (and (not= 0 exit)
               (str/includes? (str out err) "Connection refused")
               (find-server-socket server-name))
          (do (when (not (str/blank? (str out err))) (log/log (str out err)))
              {:exit 124 :out out :err err :timeout true})

          :else
          {:exit exit :out out :err err}))
      (catch Exception e
        (let [msg (.getMessage e)]
          (if (or (str/includes? (str msg) "Timeout")
                  (str/includes? (str msg) "timeout"))
            {:exit 124 :out "" :err (str msg) :timeout true}
            {:exit 1 :out "" :err (str msg)}))))))

;; ═══════════════════════════════════════════════════════════════════════════════
;; Workflow action elisp dispatch (ported from lines 797-847)
;; ═══════════════════════════════════════════════════════════════════════════════

(defn workflow-action-elisp
  "Generate elisp for workflow actions. Ported from lines 797-829."
  [action root-path]
  (let [root-lisp (lisp-escape root-path)]
    (case action
      ("auto-workflow" "research" "mementum" "instincts")
      (format (str "(condition-case _err "
                   "  (let ((root (file-name-as-directory \"%s\"))"
                   "        (load-prefer-newer t))"
                   "    (load-file (expand-file-name \"lisp/modules/gptel-auto-workflow-bootstrap.el\" root))"
                   "    (gptel-auto-workflow-bootstrap-run root \"%s\"))"
                   "  (error (format \"[workflow-action] load-error: %%s\" (error-message-string _err))))")
              root-lisp action)

      "evolution"
      (format (str "(condition-case _err"
                   "  (let ((root (file-name-as-directory \"%s\"))"
                   "        (load-prefer-newer t))"
                   "    (let ((inhibit-message t) (load-verbose nil))"
                   "      (ignore-errors (load-file (expand-file-name \"lisp/modules/gptel-tools-agent.el\" root)))"
                   "      (dolist (module (list \"gptel-tools-agent-prompt-build.el\" \"gptel-tools-agent-error.el\" \"gptel-benchmark-subagent.el\" \"gptel-tools-agent-main.el\" \"gptel-auto-workflow-evolution.el\" \"gptel-auto-experiment-ai-behaviors.el\" \"gptel-tools-agent-base.el\" \"gptel-auto-workflow-research-benchmark.el\" \"gptel-auto-workflow-ontology-router.el\" \"gptel-auto-workflow-context-database.el\" \"gptel-auto-workflow-knowledge-reasoning.el\" \"gptel-auto-workflow-external-sensors.el\" \"gptel-auto-workflow-production-metrics.el\" \"gptel-auto-workflow-production.el\" \"gptel-auto-workflow-monitoring-agent.el\" \"gptel-auto-workflow-approval-queue.el\" \"gptel-auto-workflow-disposable-tracker.el\" \"gptel-auto-workflow-code-regeneration.el\" \"gptel-auto-workflow-architectural-evolution.el\" \"gptel-auto-workflow-human-interface.el\" \"gptel-auto-workflow-skill-governance.el\"))"
                   "        (ignore-errors (load-file (expand-file-name (concat \"lisp/modules/\" module) root))))"
                   "      (ignore-errors (when (fboundp 'gptel-auto-workflow--activate-live-root)"
                   "                       (gptel-auto-workflow--activate-live-root root)))"
                   "      (ignore-errors (when (fboundp 'gptel-auto-workflow--reload-live-support)"
                   "                       (gptel-auto-workflow--reload-live-support root))))"
                   "    (condition-case action-err"
                   "      (when (fboundp 'gptel-auto-workflow-evolution-run-cycle)"
                   "        (gptel-auto-workflow-evolution-run-cycle))"
                   "      (error (format \"[workflow-action] action-error: %%s\" (error-message-string action-err)))))"
                   "  (error (format \"[workflow-action] load-error: %%s\" (error-message-string _err))))")
              root-lisp)

      ;; default
      (format "(format \"unknown action: %s\")" action))))

(defn stop-action-elisp
  "Elisp to force-stop a workflow daemon. Ported from lines 832-847."
  [root-path]
  (let [root-lisp (lisp-escape root-path)]
    (format (str "(let ((root (file-name-as-directory \"%s\")) (load-prefer-newer t))"
                 "  (let ((agent-file (expand-file-name \"lisp/modules/gptel-tools-agent.el\" root))"
                 "        (projects-file (expand-file-name \"lisp/modules/gptel-auto-workflow-projects.el\" root)))"
                 "    (when (file-readable-p agent-file) (load-file agent-file))"
                 "    (when (file-readable-p projects-file) (load-file projects-file)))"
                 "  (when (fboundp 'gptel-auto-workflow--activate-live-root)"
                 "    (gptel-auto-workflow--activate-live-root root))"
                 "  (when (fboundp 'gptel-auto-workflow-force-stop)"
                 "    (gptel-auto-workflow-force-stop))"
                 "  (if (fboundp 'gptel-auto-workflow--status-plist)"
                 "      (gptel-auto-workflow--status-plist)"
                 "    '(:running nil :kept 0 :total 0 :phase \"idle\" :run-id nil :results nil)))")
            root-lisp)))

;; ═══════════════════════════════════════════════════════════════════════════════
;; Status parsing
;; ═══════════════════════════════════════════════════════════════════════════════

(defn- parse-status-plist
  "Parse an Emacs plist string like (:running nil :kept 0 ...) into a Clojure map.
   Very rough parser — just extracts :running, :kept, :total, :phase values."
  [s]
  (when s
    (let [s (str/trim s)]
      (try
        ;; Try to parse as EDN first (may be valid Clojure/EDN)
        (if (str/starts-with? s "(")
          (let [cleaned (-> s
                            (str/replace #":running\s+nil" ":running false")
                            (str/replace #":running\s+true" ":running true")
                            (str/replace #"\"([^\"]*)\"" "\"$1\""))]
            (try
              (let [edn-data (clojure.edn/read-string cleaned)]
                (if (map? edn-data) edn-data
                    (into {} (partition 2 edn-data))))
              (catch Exception _
                {:raw s})))
          {:raw s})
        (catch Exception _
          {:raw s})))))

;; ═══════════════════════════════════════════════════════════════════════════════
;; Actions (ported from lines 1049-1247)
;; ═══════════════════════════════════════════════════════════════════════════════

(defn- status-file-for-server
  [server-name repo-path]
  (case server-name
    "pmf-value-stream" (str repo-path "/var/tmp/cron/auto-workflow-status.edn")
    "gtm-product-org" (str repo-path "/var/tmp/cron/researcher-status.edn")
    (str repo-path "/var/tmp/cron/" server-name "-status.edn")))

(defn- messages-file-for-server
  [server-name repo-path]
  (case server-name
    "pmf-value-stream" (str repo-path "/var/tmp/cron/auto-workflow-messages-tail.txt")
    "gtm-product-org" (str repo-path "/var/tmp/cron/researcher-messages-tail.txt")
    (str repo-path "/var/tmp/cron/" server-name "-messages-tail.txt")))

(defn status-action!
  "Query daemon for current status. Returns a map with :running, :phase, :kept, :total."
  [{:keys [server-name repo-path]
    :or {repo-path (project-root)}}]
  (let [status-file (status-file-for-server server-name repo-path)
        elisp (wrap-emacs-eval
               "(and (fboundp 'gptel-auto-workflow--status-plist) (gptel-auto-workflow--status-plist))"
               :status-file status-file
               :action "status")
        result (run-emacsclient-eval server-name elisp :timeout 5)]
    (if (and (= 0 (:exit result)) (str/includes? (:out result) ":phase "))
      (do
        ;; Cache status to file
        (try
          (spit (io/file status-file) (str (:out result) "\n"))
          (catch Exception _ nil))
        (parse-status-plist (:out result)))
      ;; Fall back to cached status
      (let [f (io/file status-file)]
        (if (.exists f)
          (parse-status-plist (slurp f))
          {:running false :kept 0 :total 0 :phase "idle" :results nil})))))

(defn stop-action!
  "Stop the worker daemon gracefully, then force-kill if needed."
  [{:keys [server-name repo-path]
    :or {repo-path (project-root)}
    :as opts}]
  (let [status-file (status-file-for-server server-name repo-path)
        elisp (wrap-emacs-eval
               (stop-action-elisp repo-path)
               :status-file status-file
               :messages-file (messages-file-for-server server-name repo-path)
               :action "stop")
        result (run-emacsclient-eval server-name elisp :timeout 20)]
    ;; Always discard stale daemon after stop, regardless of result
    (discard-stale-worker-daemon! server-name :status-file status-file)
    (parse-status-plist (:out result))))

(defn queue-workflow-action!
  "Queue a workflow action (auto-workflow, research, evolution, mementum, instincts)
   via emacsclient. Includes crash recovery with up to 3 restarts."
  [{:keys [action server-name repo-path timeout-ms max-restarts]
    :or {repo-path (project-root)
         timeout-ms 10
         max-restarts 3}
    :as opts}]
  (let [status-file (status-file-for-server server-name repo-path)
        messages-file (messages-file-for-server server-name repo-path)
        timeout-sec (max 1 (int (/ timeout-ms 1000)))
        elisp-code (workflow-action-elisp action repo-path)
        wrapped (wrap-emacs-eval elisp-code
                                 :status-file status-file
                                 :messages-file messages-file
                                 :action action)
        evo-timeout (if (= action "evolution")
                      (max 1 (int (/ (or timeout-ms 900000) 1000)))
                      timeout-sec)]
    ;; Check if already running
    (when (str/includes? (try (slurp (io/file status-file)) (catch Exception _ "")) ":running true")
      (println "already-running")
      :already-running)
    ;; Ensure daemon is running
    (let [daemon-state (ensure-worker-daemon! (assoc opts
                                                     :repo-path repo-path
                                                     :server-name server-name
                                                     :daemon-log (str repo-path "/var/tmp/cron/" server-name ".log")))]
      (when (= :failed daemon-state)
        (log/logf "Failed to start daemon for %s" action)
        :daemon-failed))
    ;; Re-check if already running (daemon might have picked up a queued job)
    (when (str/includes? (try (slurp (io/file status-file)) (catch Exception _ "")) ":running true")
      (println "already-running")
      :already-running)
    ;; Run workflow with crash recovery
    (loop [restart-count 0]
      (let [result (run-emacsclient-eval server-name wrapped :timeout (max 1 evo-timeout))]
        (if (= 0 (:exit result))
          :completed
          (let [rc (:exit result)]
            (cond
              ;; Timeout but status says running → already-running
              (and (= 124 rc)
                   (str/includes? (try (slurp (io/file status-file)) (catch Exception _ "")) ":running true"))
              (do (println "already-running") :already-running)

              ;; Daemon crashed
              (and (< restart-count max-restarts)
                   (not= :alive (check-worker-daemon server-name)))
              (do
                (log/logf "[auto-workflow] Daemon crashed during workflow (restart %d/%d)"
                         (inc restart-count) max-restarts)
                (discard-stale-worker-daemon! server-name :status-file status-file)
                (Thread/sleep 5000)
                (let [restart-state (ensure-worker-daemon! (assoc opts
                                                                  :repo-path repo-path
                                                                  :server-name server-name
                                                                  :daemon-log (str repo-path "/var/tmp/cron/" server-name ".log")))]
                  (when (= :failed restart-state)
                    (log/log "[auto-workflow] Failed to restart daemon after crash")
                    :failed)
                  (Thread/sleep 2000)
                  (recur (inc restart-count))))

              ;; Daemon still alive but workflow failed
              :else
              (do
                (log/logf "[auto-workflow] Workflow failed with rc=%d (daemon still alive)" rc)
                :failed))))))))

(defn run-action!
  "Dispatch to the appropriate action handler.
   Action is a keyword: :status, :stop, :research, :evolution, :auto-workflow."
  [action & {:as opts}]
  (let [server-name (or (:server-name opts)
                        (case action
                          (:auto-workflow :stop) "pmf-value-stream"
                          :research "gtm-product-org"
                          "pmf-value-stream"))]
    (case (keyword action)
      :status (status-action! (assoc opts :server-name server-name))
      :stop (stop-action! (assoc opts :server-name server-name))
      (:research :evolution :auto-workflow)
      (queue-workflow-action! (assoc opts :action (name action) :server-name server-name))
      ;; default
      (do (log/logf "Unknown action: %s" action) :unknown-action))))

;; ═══════════════════════════════════════════════════════════════════════════════
;; wait-for-idle (ported from run-pipeline.sh lines 184-274)
;; ═══════════════════════════════════════════════════════════════════════════════

(defn wait-for-idle!
  "Wait for a daemon action to complete (idle/complete/skipped state).
   Two behaviors depending on socket-name:
   - pmf-value-stream: poll status via daemon, check experiment count via World Store
   - gtm-product-org (researcher): wait for findings file freshness
   Returns :complete or :timeout"
  [{:keys [action max-wait-ms socket-name min-start-wait-ms
           project-root findings-file pipeline-start-time]
    :or {max-wait-ms 900000     ;; 15 min default
         socket-name "pmf-value-stream"
         min-start-wait-ms 60000 ;; 60s
         project-root (project-root)
         findings-file (str (project-root) "/var/tmp/research-findings.edn")
         pipeline-start-time (quot (System/currentTimeMillis) 1000)}
    :as opts}]
  (let [poll-interval-ms (* 1000 (try (Long/parseLong (System/getenv "POLL_INTERVAL"))
                                      (catch Exception _ 30)))
        deadline (+ (System/currentTimeMillis) max-wait-ms)
        emacsclient-path (or (resolve-emacsclient) "emacsclient")]
    (log/logf "Waiting for %s to complete (max %ds)..." action (quot max-wait-ms 1000))
    (loop [elapsed 0
           daemon-seen false]
      (if (>= elapsed max-wait-ms)
        (do (log/logf "WARNING: %s did not complete within %ds" action (quot max-wait-ms 1000))
            :timeout)
        (let [now (System/currentTimeMillis)]
          (if (= socket-name "pmf-value-stream")
            ;; Behavior 1: pmf-value-stream — poll status via daemon
            (let [status (try (status-action! opts) (catch Exception _ {:phase "unknown"}))
                  phase (:phase status)
                  running (:running status)]
              (if (and (or (#{"idle" "complete" "skipped" "quota-exhausted"} phase)
                           (false? running))
                       ;; Check experiments produced
                       (try
                         (let [ws-connect (requiring-resolve 'ov5.world-store/connect)
                               ws-exp-count (requiring-resolve 'ov5.world-store/experiment-count)
                               ws-path (str project-root "/var/world-store")]
                           (when ws-connect (ws-connect ws-path))
                           (if ws-exp-count
                             (> (ws-exp-count) 0)
                             (>= elapsed 300000)))
                         (catch Exception _
                           (>= elapsed 300000)))) ;; >5min with no experiments = done
                (do (log/logf "%s completed after %ds" action (quot elapsed 1000))
                    :complete)
                (do
                  (when (>= elapsed 300000)
                    ;; Still idle after 5min with no experiments = daemon done
                    (log/logf "%s completed after %ds (no experiments after 5min idle, daemon likely done)"
                             action (quot elapsed 1000))
                    :complete))
                ))
            ;; Behavior 2: gtm-product-org — researcher daemon
            (let [findings (io/file findings-file)]
              (if (and (.exists findings)
                       (> (.length findings) 100)
                       (>= (/ (.lastModified findings) 1000) pipeline-start-time))
                (do (log/logf "%s completed after %ds (findings file ready)" action (quot elapsed 1000))
                    :complete)
                ;; Check daemon phase
                (let [phase-eval (try
                                   (run-emacsclient-eval socket-name
                                                         (str "(if (and (boundp 'gptel-auto-workflow--stats)"
                                                              "gptel-auto-workflow--stats)"
                                                              "(plist-get gptel-auto-workflow--stats :phase)"
                                                              "\"unknown\")")
                                                         :timeout 3)
                                   (catch Exception _ {:exit 1 :out "unknown" :err ""}))]
                  (if (and (str/includes? (:out phase-eval) "complete")
                           daemon-seen)
                    (do (log/logf "%s daemon phase=complete after %ds" action (quot elapsed 1000))
                        :complete)
                    ;; Check if daemon is alive
                    (if (= :alive (check-worker-daemon socket-name emacsclient-path))
                      :continue-pm-loop   ;; daemon alive, keep polling
                      (if daemon-seen
                        (do (log/logf "WARNING: %s daemon stopped after %ds without findings" action (quot elapsed 1000))
                            :failed)
                        (if (>= elapsed min-start-wait-ms)
                          (do (log/logf "WARNING: %s daemon was not observed within %ds" action (quot elapsed 1000))
                              :failed)
                          :continue-pm-loop))))))
              ;; fallthrough to poll
              (Thread/sleep poll-interval-ms)
              (recur (+ elapsed poll-interval-ms) (or daemon-seen true)))))))))
