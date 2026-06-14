(ns ov5.pipeline
  "OV5 Self-Evolution Pipeline — main entry point.
   Replaces scripts/run-pipeline.sh. Orchestrates the full pipeline:
   bootstrap → cleanup → self-audit → auto-fix → research →
   self-evolution → auto-workflow → reporting → daily digest → publish.

   Invoked via: bb -m ov5.pipeline [--help] [--smoke] [--skip-pre-evolution]"
  (:gen-class)
  (:require [ov5.pipeline.log :as log]
            [ov5.pipeline.process :as proc :refer [sh-out sh-ok? sh-lines]]
            [ov5.pipeline.git :as git]
            [ov5.pipeline.daemon :as daemon]
            [clojure.edn :as edn]
            [clojure.java.io :as io]
            [clojure.string :as str]
            [babashka.process :as p]))

;; ═══════════════════════════════════════════════════════════════════════════════
;; State atoms (trampoline for env vars)
;; ═══════════════════════════════════════════════════════════════════════════════

(defonce ^:private env (atom {}))
(defonce ^:private pipeline-start-time* (atom nil))

;; ═══════════════════════════════════════════════════════════════════════════════
;; Arg parsing
;; ═══════════════════════════════════════════════════════════════════════════════

(defn- usage
  "Print usage and exit 0."
  []
  (println "Usage: bb -m ov5.pipeline [OPTIONS]")
  (println "")
  (println "  --help                Show this help")
  (println "  --smoke               Smoke-only mode (exit before auto-workflow)")
  (println "  --dry-run             Parse args, print environment, and exit (no side effects)")
  (println "  --skip-pre-evolution  Skip pre-workflow self-evolution")
  (println "")
  (println "Environment variables:")
  (println "  PIPELINE_SMOKE_ONLY          Smoke-only mode (yes/no)")
  (println "  SKIP_IF_QUOTA_EXHAUSTED      Skip when quota exhausted (yes/no)")
  (println "  PIPELINE_SKIP_PRE_EVOLUTION  Skip pre-evolution (yes/no)")
  (println "  MAX_WAIT_RESEARCH            Max wait for research (seconds, default 900)")
  (println "  MAX_WAIT_EVOLUTION           Max wait for evolution (seconds, default 900)")
  (println "  MAX_WAIT_WORKFLOW            Max wait for workflow (seconds, default 14400)")
  (println "  POLL_INTERVAL                Poll interval (seconds, default 30)")
  (println "  PIPELINE_PROJECT_ROOT        Override project root")
  (System/exit 0))

(defn- parse-args
  "Parse *command-line-args* into a map of flags.
   Returns {:help true|false :smoke true|false :dry-run true|false :skip-pre-evolution true|false}"
  [args]
  (reduce (fn [acc arg]
            (case arg
              "--help" (assoc acc :help true)
              "--smoke" (assoc acc :smoke true)
              "--dry-run" (assoc acc :dry-run true)
              "--skip-pre-evolution" (assoc acc :skip-pre-evolution true)
              acc))
          {:help false :smoke false :dry-run false :skip-pre-evolution false}
          args))

;; ═══════════════════════════════════════════════════════════════════════════════
;; Environment setup
;; ═══════════════════════════════════════════════════════════════════════════════

(defn- env-get
  "Get an env var with a default string value."
  [key default]
  (or (System/getenv key) default))

(defn- env-int
  "Get an env var as integer with a default."
  [key default]
  (try (Long/parseLong (System/getenv key)) (catch Exception _ default)))

(defn- setup-env!
  "Initialize environment variables, resolve paths, create directories."
  [flags]
  ;; Pin TMPDIR
  (System/setProperty "TMPDIR" "/tmp")
  ;; Project root
  (let [root (or (System/getenv "PIPELINE_PROJECT_ROOT")
                 (System/getProperty "user.dir"))]
    (log/set-project-root! root))
  ;; Env vars
  (swap! env assoc
         :project-root (log/project-root)
         :log-dir (log/log-dir)
         :pipeline-log (log/pipeline-log-path)
         :lock-file (str (log/log-dir) "/pipeline.lock")
         :findings-file (str (log/project-root) "/var/tmp/research-findings.edn")
         :internal-file (str (log/project-root) "/var/tmp/internal-research.md")
         :active-runs-file (str (log/project-root) "/var/tmp/active-runs")
         :self-audit-result-file (str (log/project-root) "/var/tmp/self-audit-result.edn")
         :plan-dir (str (log/project-root) "/mementum/knowledge/plans/pipeline-runs")
         :max-wait-research (env-int "MAX_WAIT_RESEARCH" 900)
         :max-wait-evolution (env-int "MAX_WAIT_EVOLUTION" 900)
         :max-wait-workflow (env-int "MAX_WAIT_WORKFLOW" 14400)
         :poll-interval (env-int "POLL_INTERVAL" 30)
         :smoke-only (or (:smoke flags)
                        (= "yes" (env-get "PIPELINE_SMOKE_ONLY" "no")))
         :skip-quota (env-get "SKIP_IF_QUOTA_EXHAUSTED" "no")
         :skip-pre-evolution (or (:skip-pre-evolution flags)
                                (= "yes" (env-get "PIPELINE_SKIP_PRE_EVOLUTION" "no"))))
  ;; Create needed directories
  (doseq [d [(log/log-dir)
             (str (log/project-root) "/var/tmp/experiments")
             (:plan-dir @env)]]
    (.mkdirs (io/file d)))
  @env)

;; ═══════════════════════════════════════════════════════════════════════════════
;; Pipeline helper: create plan, update state
;; ═══════════════════════════════════════════════════════════════════════════════

(defn- timestamp-str
  "YYYYMMDD-HHMMSS"
  []
  (.format (java.time.LocalDateTime/now)
           (java.time.format.DateTimeFormatter/ofPattern "yyyyMMdd-HHmmss")))

(defn- ts
  "Human-readable timestamp."
  []
  (.format (java.time.LocalDateTime/now)
           (java.time.format.DateTimeFormatter/ofPattern "yyyy-MM-dd HH:mm")))

(defn- create-pipeline-plan
  []
  (let [ts-str (timestamp-str)
        plan-dir (str (:plan-dir @env) "/run-" ts-str)]
    (.mkdirs (io/file plan-dir))
    (spit (io/file plan-dir "plan.md")
          (str "# Pipeline Run " ts-str "\n\n"
               "## Objective\n"
               "Run OV5 self-evolution pipeline with research -> digestion -> workflow.\n\n"
               "## Requirements\n"
               "- Research findings digested before workflow\n"
               "- Quota-aware scheduling\n"
               "- Results tracked in mementum\n\n"
               "## DoD\n"
               "- [ ] Pipeline completes without error\n"
               "- [ ] Results stored in mementum/memories/\n"
               "- [ ] State updated in mementum/state.md\n\n"
               "## Changelog\n"
               "- **" (ts) "**: Plan created\n"))
    (log/log "Plan created:" (str plan-dir "/"))
    (swap! env assoc :plan-dir-run plan-dir)))

(defn- update-pipeline-plan
  [status]
  (when-let [d (:plan-dir-run @env)]
    (spit (io/file d "plan.md")
          (str "\n## Results\n\n- **Status**: " status "\n- **Timestamp**: " (timestamp-str) "\n")
          :append true)
    (log/log "Plan updated with status:" status)))

(defn- update-mementum-state
  [status]
  (let [state-file (str (log/project-root) "/mementum/state.md")]
    (when (.exists (io/file state-file))
      (let [existing (try (slurp state-file) (catch Exception _ ""))
            new-content (str "# Mementum State\n\n"
                             "> **Last pipeline**: " (ts) " (" status ")\n"
                             "> **Next pipeline**: scheduled\n"
                             "> **Plan**: " (:plan-dir-run @env "N/A") "/\n\n")]
        (spit (io/file state-file) new-content)
        (log/log "State updated")))))

(defn- log-pipeline-patterns
  [status]
  (try
    (spit (io/file (str (log/project-root) "/mementum/.pipeline-log"))
          (str (ts) " | Pipeline " status
               " | Plan: " (:plan-dir-run @env "N/A") "/\n")
          :append true)
    (catch Exception _ nil))
  (log/log "Patterns logged to mementum/.pipeline-log"))

;; ═══════════════════════════════════════════════════════════════════════════════
;; Phase 0: Bootstrap + Lock + Cross-machine + Cleanup
;; ═══════════════════════════════════════════════════════════════════════════════

(defn- bootstrap-and-pull!
  "Git fetch, rebase origin/main. If HEAD changed, re-exec with same args
   so we run the latest code."
  []
  (log/log "Bootstrapping: ensuring latest code...")
  (let [root (log/project-root)
        head-before (try (sh-out "git" "-C" root "rev-parse" "HEAD")
                         (catch Exception _ ""))
        _ (git/fetch-and-rebase! root)
        head-after (try (sh-out "git" "-C" root "rev-parse" "HEAD")
                        (catch Exception _ ""))]
    (when (and (not (str/blank? head-before))
               (not= head-before head-after))
      (log/log "Bootstrap: HEAD updated, re-execing with latest code")
      (let [args (into-array String
                             (concat ["bb" "-m" "ov5.pipeline"]
                                     *command-line-args*))]
        (try
          (p/exec {:inherit true} (into-array String args))
          (catch Exception _ nil))
        (System/exit 0)))))

(defn- acquire-lock!
  []
  (let [lock-file (:lock-file @env)]
    (log/acquire-lock! lock-file)))

(defn- cross-machine-check!
  "Prune stale entries >12h and check if another host ran within 4h.
   If so, skip this pipeline run."
  []
  (let [active-runs-file (:active-runs-file @env)
        hostname (try (sh-out "hostname" "-s") (catch Exception _ (try (sh-out "hostname") (catch Exception _ "unknown"))))
        now-epoch (quot (System/currentTimeMillis) 1000)
        recent-threshold (* 4 3600)
        prune-cutoff (- now-epoch 43200)]
    ;; Prune stale entries
    (when (.exists (io/file active-runs-file))
      (try
        (let [lines (str/split-lines (slurp active-runs-file))
              fresh (filter (fn [line]
                              (let [parts (str/split line #"\|" 3)]
                                (and (>= (count parts) 2)
                                     (try
                                       (> (Long/parseLong (nth parts 1)) prune-cutoff)
                                       (catch Exception _ false)))))
                            lines)]
          (spit (io/file active-runs-file) (str (str/join "\n" fresh) "\n")))
        (catch Exception _ nil)))
    ;; Check for recent runs on other hosts
    (when (.exists (io/file active-runs-file))
      (let [lines (str/split-lines (slurp active-runs-file))
            other-recent (keep (fn [line]
                                 (let [parts (str/split line #"\|" 3)]
                                   (when (and (>= (count parts) 2)
                                              (not= (first parts) hostname))
                                     (let [age (- now-epoch (try (Long/parseLong (nth parts 1)) (catch Exception _ 0)))]
                                       (when (< age recent-threshold)
                                         (str (first parts) ":" (quot age 60) "min"))))))
                               lines)]
        (when (seq other-recent)
          (log/log "Cross-machine coordination: recent runs on other host(s):"
                   (str/join ", " other-recent))
          (log/logf "  Skipping pipeline to avoid duplicate work; threshold %ds" recent-threshold)
          (System/exit 0)))))
  ;; Record this run (deferred until end)
  (swap! env assoc :hostname (try (sh-out "hostname" "-s") (catch Exception _ "unknown"))))

(defn- cleanup-stale!
  "Rotate logs, clean stale files, kill old daemons, clear sockets, pull latest code."
  []
  ;; Rotate logs
  (doseq [log-path [(:pipeline-log @env)
                    (str (log/log-dir) "/gtm-product-org.log")
                    (str (log/log-dir) "/pmf-value-stream.log")
                    (str (log/log-dir) "/evolution-backtrace.log")]]
    (log/log-rotate log-path (if (str/includes? log-path "evolution-backtrace") 51200 102400)))
  ;; Clean stale pid/lock files older than 12h
  (try
    (let [pids (filter (fn [f]
                         (let [nm (.getName f)]
                           (or (str/ends-with? nm ".pid") (str/ends-with? nm ".lock"))))
                       (.listFiles (io/file (str (log/project-root) "/var/tmp"))))]
      (doseq [f pids]
        (when (< (.lastModified f) (- (System/currentTimeMillis) (* 43200 1000)))
          (io/delete-file f true))))
    (catch Exception _ nil))
  ;; Clean old experiment dirs >7d
  (let [exp-dir (io/file (str (log/project-root) "/var/tmp/experiments"))]
    (when (.exists exp-dir)
      (doseq [d (.listFiles exp-dir)]
        (when (and (.isDirectory d)
                   (not (str/includes? (.getName d) "staging"))
                   (< (.lastModified d) (- (System/currentTimeMillis) (* 7 86400 1000))))
          (try
            (doseq [f (file-seq d)]
              (io/delete-file f true))
            (io/delete-file d true)
            (catch Exception _ nil))))))
  ;; Git worktree prune
  (try (sh-out "git" "-C" (log/project-root) "worktree" "prune") (catch Exception _ nil))
  (log/log "Cleaned old experiment directories + stale worktree metadata")
  ;; Clean old Emacs daemon logs (keep 50)
  (let [log-dir (io/file (str (log/project-root) "/var/log"))]
    (when (.exists log-dir)
      (let [emacs-logs (sort-by #(.lastModified %)
                                (filter #(and (.isFile %) (str/starts-with? (.getName %) "emacs-") (str/ends-with? (.getName %) ".log"))
                                        (.listFiles log-dir)))]
        (when (> (count emacs-logs) 50)
          (let [to-remove (drop-last 50 emacs-logs)]
            (doseq [f to-remove]
              (io/delete-file f true))
            (log/logf "Cleaned %d old Emacs daemon logs (kept 50 most recent)" (count to-remove)))))))
  ;; Clear stale .elc files
  (try
    (let [elc-dir (io/file (str (log/project-root) "/lisp/modules"))]
      (doseq [f (file-seq elc-dir)]
        (when (and (.isFile f) (str/ends-with? (.getName f) ".elc"))
          (io/delete-file f true))))
    (catch Exception _ nil))
  ;; Clear stale .eln cache
  (let [eln-dir (io/file (str (log/project-root) "/var/eln-cache"))]
    (when (.exists eln-dir)
      (doseq [f (file-seq eln-dir)]
        (when (and (.isFile f) (str/ends-with? (.getName f) ".eln"))
          (io/delete-file f true)))))
  (log/log "Cleared stale .elc + .eln files from lisp/modules/")
  ;; Force-kill stale Emacs daemons
  (let [stale-pattern "(pmf-value-stream|gtm-product-org|ov5-auto-workflow|ov5-researcher)"
        killed-info (proc/kill-by-pattern! stale-pattern)]
    (when (> (:killed killed-info) 0)
      (log/logf "Killing %d stale daemon process(es)..." (:killed killed-info)))
    (Thread/sleep 3000))
  (log/log "Cleanup: killed stale daemons")
  ;; Kill stale bg-daemon processes (Emacs daemons only, not bb pipeline)
  (proc/kill-by-pattern! "Emacs.*--bg-daemon")
  (Thread/sleep 2000)
  (log/log "Cleanup: killed stale bg-daemons")
  ;; Clean stale sockets
  (doseq [sock-name ["server" "pmf-value-stream" "gtm-product-org"]]
    (daemon/clean-stale-socket sock-name))
  (log/log "Cleanup: cleaned stale sockets")
  ;; Pull latest code
  (log/log "Pulling latest code from origin...")
  (git/git-sync-latest! "pre-workflow" "auto-workflow-pre-pull")
  (log/log "Cleanup: pulled latest code")
  ;; Stop existing daemons
  (log/log "Stopping any existing daemons to load latest code...")
  (try (daemon/stop-action! {:server-name "pmf-value-stream"}) (catch Exception _ nil))
  (try (daemon/stop-action! {:server-name "gtm-product-org"}) (catch Exception _ nil))
  ;; Clear stale status
  (try (io/delete-file (io/file (str (log/project-root) "/var/tmp/cron/auto-workflow-status.edn")) true) (catch Exception _ nil))
  ;; Clean worktrees
  (try
    (let [staging (io/file (str (log/project-root) "/var/tmp/experiments/staging-verify"))]
      (when (.exists staging)
        (doseq [f (file-seq staging)] (io/delete-file f true))))
    (catch Exception _ nil))
  ;; Clear stale findings
  (try (io/delete-file (io/file (:findings-file @env)) true) (catch Exception _ nil))
  (try (io/delete-file (io/file (:internal-file @env)) true) (catch Exception _ nil))
  (log/log "Cleared stale findings files")
  ;; Capture start time
  (reset! pipeline-start-time* (quot (System/currentTimeMillis) 1000)))

;; ═══════════════════════════════════════════════════════════════════════════════
;; Step 0.4: Self-audit
;; ═══════════════════════════════════════════════════════════════════════════════

(defn- self-audit!
  "Run self-audit via emacs --batch. Parse result EDN file.
   Returns audit map with :issues-count, :cold-backends, etc."
  []
  (log/log "=== Step 0.4: Self-audit (DETECT) ===")
  (let [root (log/project-root)
        result-file (:self-audit-result-file @env)]
    ;; Remove stale result
    (try (io/delete-file (io/file result-file) true) (catch Exception _ nil))
    (try (io/delete-file (io/file (str root "/var/tmp/self-audit-result.el")) true) (catch Exception _ nil))
    ;; Run self-audit
    (let [audit-failed (try
                         (proc/sh "emacs" "--batch"
                                  "-L" (str root "/lisp/modules")
                                  "-L" (str root "/packages/gptel")
                                  "-L" (str root "/packages/compat")
                                  "-l" "gptel"
                                  "--eval"
                                  (str "(progn"
                                       "  (require 'gptel-auto-workflow-self-audit)"
                                       "  (setq gptel-auto-workflow-self-audit-enabled t)"
                                       "  (setq gptel-auto-workflow--workspace-path \"" root "\")"
                                       "  (let ((report (gptel-auto-workflow-self-audit-execute)))"
                                       "    (when report (princ report))))"))
                         (catch Exception e
                           (log/logf "WARNING: self-audit emacs batch failed: %s" (.getMessage e))
                           {:exit 1 :out "" :err (.getMessage e)}))
          audit-ok? (and (not (str/blank? (:out audit-failed)))
                         (not= 0 (:exit audit-failed)))]
      (if audit-ok?
        (do
          (log/log (str/trim (:out audit-failed)))
          (if (.exists (io/file result-file))
            (if-let [data (try (edn/read-string (slurp result-file)) (catch Exception _ nil))]
              (let [issues (get data :issues-count 0)
                    cold (get data :cold-backends [])
                    unev (get data :unevaluated-strategies 0)
                    bottleneck (get data :staging-merge-bottleneck false)
                    broken (count (get data :broken-modules []))
                    p-stale (get data :pricing-stale 0)
                    p-days (get data :pricing-days-stale 0)]
                (log/logf "  Structured audit: %d issues, %d broken modules, bottleneck=%s"
                         issues broken bottleneck)
                (when (> p-stale 0)
                  (log/logf "  WARNING: Pricing STALE: %d discrepancies (%d days since last knowledge page update)"
                           p-stale p-days))
                (swap! env assoc
                       :audit-issues issues
                       :cold-backends cold
                       :unevaluated-strategies unev
                       :bottleneck bottleneck
                       :broken-modules broken
                       :pricing-stale p-stale
                       :days-stale p-days))
              {:issues-count 0 :cold-backends [] :unevaluated-strategies 0
               :staging-merge-bottleneck false :broken-modules 0 :pricing-stale 0 :pricing-days-stale 0})
            {:issues-count 0 :cold-backends [] :unevaluated-strategies 0
             :staging-merge-bottleneck false :broken-modules 0 :pricing-stale 0 :pricing-days-stale 0}))
        {:issues-count 0 :cold-backends [] :unevaluated-strategies 0
         :staging-merge-bottleneck false :broken-modules 0 :pricing-stale 0 :pricing-days-stale 0}))))

;; ═══════════════════════════════════════════════════════════════════════════════
;; Step 0.5: Auto-fix
;; ═══════════════════════════════════════════════════════════════════════════════

(defn- auto-fix!
  "Apply remediations based on self-audit findings."
  []
  (log/log "=== Step 0.5: Auto-fix (ACT on self-audit findings) ===")
  (let [root (log/project-root)
        cold-backends (:cold-backends @env)
        unevaluated-strategies (:unevaluated-strategies @env)
        bottleneck (:bottleneck @env)
        broken-modules (:broken-modules @env)
        pricing-stale (:pricing-stale @env)
        days-stale (:days-stale @env)
        remedial (atom 0)]
    ;; Auto-fix 1: Force cold backends
    (when (and cold-backends (not= cold-backends []) (not= cold-backends "nil"))
      (log/log "  Auto-fix: forcing cold backends into rotation")
      (try (io/delete-file (io/file (str root "/var/tmp/rate-limited-backends.txt")) true)
           (catch Exception _ nil))
      (spit (io/file (str root "/var/tmp/force-try-backends.txt"))
            (str/join "," (if (string? cold-backends) [cold-backends] cold-backends)))
      (swap! remedial inc))
    ;; Auto-fix 2: Increase exploration rate
    (when (> unevaluated-strategies 2)
      (log/logf "  Auto-fix: increasing exploration rate (%d strategies unevaluated)" unevaluated-strategies)
      (spit (io/file (str root "/var/tmp/exploration-rateOverride.txt")) "70")
      (swap! remedial inc))
    ;; Auto-fix 3: Staging bottleneck
    (when bottleneck
      (log/log "  Auto-fix: staging-merge bottleneck flagged (.md auto-resolved, .el needs review)")
      (swap! remedial inc))
    ;; Auto-fix 4: Broken modules
    (when (> broken-modules 0)
      (log/log "  WARNING: BROKEN MODULES DETECTED — cannot auto-fix source code, flagged for human review")
      (swap! remedial inc))
    ;; Auto-fix 5: Pipeline-health pending + grader escalation
    (let [health-file (io/file (str root "/mementum/knowledge/pipeline-health.md"))]
      (when (.exists health-file)
        (let [content (slurp health-file)
              pending (count (re-seq #"(?m)\| PENDING" content))
              consecutive (try
                            (->> (re-seq #"(?m)^Consecutive failures:\s*(\d+)" content)
                                 first second Long/parseLong)
                            (catch Exception _ 0))]
          (when (or (>= pending 5) (>= consecutive 3))
            (log/log "  Auto-fix: clearing stale rate-limited-backend cache (threshold reached)")
            (try (io/delete-file (io/file (str root "/var/tmp/rate-limited-backends.txt")) true)
                 (catch Exception _ nil))
            (swap! remedial inc))
          ;; Grader escalation
          (let [grader-count (count (re-seq #"(?m)grader-destroying-experiments.*\| PENDING" content))]
            (when (>= grader-count 3)
              (let [current-timeout (try
                                      (->> (re-find #"grader-timeout=(\d+)" content)
                                           second Long/parseLong)
                                      (catch Exception _ 900))
                    new-timeout (if (< current-timeout 900) 900 (long (* current-timeout 1.5)))]
                (log/log "  Auto-fix: grader-destroying-experiments detected (escalating timeout)")
                (log/logf "  Escalating grader timeout: %d → %d" current-timeout new-timeout)
                (spit (io/file (str root "/var/tmp/grader-timeoutOverride.txt")) (str new-timeout))
                (spit (io/file (str root "/var/tmp/force-grader-backends.txt")) "deepseek-v4-flash,deepseek-v4-pro")
                (swap! remedial inc)))))))
    ;; Auto-fix: pricing stale
    (when (> pricing-stale 0)
      (log/logf "  Auto-fix: pricing may be stale (%d discrepancies, %d days old)" pricing-stale days-stale)
      (spit (io/file (str root "/var/tmp/pricing-stale.txt"))
            (str "pricing-stale:" pricing-stale ":days:" days-stale))
      (log/log "  -> Flagged in var/tmp/pricing-stale.txt")
      (swap! remedial inc))
    (if (> @remedial 0)
      (log/logf "  Auto-fix: %d remedial actions applied — KEEPING GOING" @remedial)
      (log/log "  Auto-fix: no remedial actions needed this cycle"))
    @remedial))

;; ═══════════════════════════════════════════════════════════════════════════════
;; Step 0.6: Approval priorities + Step 0.7: Mementum prune
;; ═══════════════════════════════════════════════════════════════════════════════

(defn- approval-priorities!
  []
  (log/log "=== Step 0.6: Refresh approval priorities ===")
  (let [root (log/project-root)
        decisions-dir (io/file (str root "/var/approval-queue/decisions"))]
    (if (.exists decisions-dir)
      (let [count (count (filter #(and (.isFile %)
                                       (try (str/includes? (slurp %) ":status \"approved\"") (catch Exception _ false)))
                                 (.listFiles decisions-dir)))]
        (if (> count 0)
          (do
            (log/logf "  Found %d approved proposals; refreshing priorities" count)
            (try (io/delete-file (io/file (str root "/var/tmp/approval-priorities.el")) true) (catch Exception _ nil)))
          (log/log "  No approved proposals pending; priorities unchanged")))
      (log/log "  No approved proposals pending; priorities unchanged"))))

(defn- mementum-prune!
  []
  (log/log "=== Step 0.7: Prune mementum memories ===")
  (let [eval-result (try
                      (daemon/run-emacsclient-eval
                       "pmf-value-stream"
                       (str "(condition-case err"
                            "  (let ((result (and (fboundp 'gptel-auto-workflow--mementum-prune-run)"
                            "                     (gptel-auto-workflow--mementum-prune-run))))"
                            "    (if result (format \"kept=%d pruned=%d topics=%d\""
                            "                       (or (plist-get result :kept-count) 0)"
                            "                       (or (plist-get result :pruned-count) 0)"
                            "                       (or (plist-get result :topics-affected) 0))"
                            "      \"skipped\"))"
                            "  (error (format \"prune-error: %s\" (error-message-string err))))")
                       :timeout 10)
                      (catch Exception _ {:out "skipped" :err ""}))]
    (log/log "Mementum prune:" (str/trim (:out eval-result)))))

;; ═══════════════════════════════════════════════════════════════════════════════
;; Step 1: Research
;; ═══════════════════════════════════════════════════════════════════════════════

(defn- research-quality
  "Determine research quality from findings file."
  [findings-file internal-file]
  (if (.exists (io/file findings-file))
    (let [size (.length (io/file findings-file))
          content (try (slurp findings-file) (catch Exception _ ""))
          has-external (or (str/includes? content "https://")
                           (str/includes? content "http://")
                           (str/includes? content "## "))]
      (log/logf "Research findings: %d bytes" size)
      (if has-external
        (do (log/log "  ✓ External research content detected") "external")
        (if (str/includes? content "Source type: local-fallback")
          (do (log/log "  ⚠ Local fallback research generated") "internal")
          (if (> size 200)
            (do (log/log "  ⚠ Findings file present but may lack external content") "unknown")
            (do (log/log "  ✗ Findings file too small, research may have failed") "failed")))))
    (do
      (log/log "WARNING: No findings file found")
      "none")))

(defn- write-research-fallback
  [reason]
  (let [root (log/project-root)]
    (.mkdirs (.getParentFile (io/file (:findings-file @env))))
    (spit (io/file (:findings-file @env))
          (str "{:project \"" root "\""
               " :updated \"" (ts) "\""
               " :findings \"Local research fallback: " reason ". "
               "The dedicated researcher daemon did not produce fresh external findings. "
               "Treat missing research files as a pipeline defect, not a successful empty research run.\"}\n"))
    (spit (io/file (:internal-file @env))
          (str "# Internal Code Analysis\n\n"
               "> Updated: " (ts) "\n"
               "> Source type: local-fallback\n\n"
               "The pipeline generated fallback research because the researcher daemon "
               "did not produce fresh findings. This is still useful input for self-evolution.\n"))))

(defn- step-1-research!
  []
  (log/log "=== Step 1: Research ===")
  (try
    (daemon/run-action! :research {:repo-path (log/project-root)})
    (catch Exception e
      (log/logf "WARNING: research action failed: %s" (.getMessage e))))
  (let [wait-result (daemon/wait-for-idle!
                     {:action "research"
                      :max-wait-ms (* 1000 (:max-wait-research @env))
                      :socket-name "gtm-product-org"
                      :min-start-wait-ms 180000})]
    (when (= :timeout wait-result)
      (log/log "Research still in progress after timeout — continuing with partial findings")))
  (let [quality (research-quality (:findings-file @env) (:internal-file @env))]
    (when (#{"none" "failed"} quality)
      (write-research-fallback "research findings file missing after wait")
      (swap! env assoc :research-quality "internal"))
    (when-not (#{"none" "failed"} quality)
      (swap! env assoc :research-quality quality))
    ;; Check internal research
    (when (.exists (io/file (:internal-file @env)))
      (let [size (.length (io/file (:internal-file @env)))]
        (when (> size 100)
          (log/log "  ✓ Internal code analysis available"))))))

;; ═══════════════════════════════════════════════════════════════════════════════
;; Step 2: Verify integration
;; ═══════════════════════════════════════════════════════════════════════════════

(defn- step-2-verify-integration!
  []
  (log/log "=== Step 2: Verify Pipeline Integration ===")
  (let [root (log/project-root)
        findings-file (:findings-file @env)
        internal-file (:internal-file @env)
        directive-file (str root "/assistant/skills/auto-workflow/DIRECTIVE.md")]
    (when (.exists (io/file findings-file))
      (let [size (.length (io/file findings-file))]
        (if (> size 100)
          (log/logf "  ✓ Findings file: %d bytes" size)
          (log/logf "  ⚠ Findings file too small: %d bytes" size))))
    (when (.exists (io/file internal-file))
      (let [size (.length (io/file internal-file))]
        (when (> size 100)
          (log/logf "  ✓ Internal research file: %d bytes" size))))
    (if (.exists (io/file directive-file))
      (log/log "  ✓ Directive skill exists")
      (log/log "  ⚠ Directive skill file not found"))
    ;; Report research quality
    (let [quality (:research-quality @env "none")]
      (case quality
        "external" (log/log "Pipeline integration: External research available ✓")
        "internal" (log/log "Pipeline integration: Internal research only (no external) ⚠")
        "unknown" (log/log "Pipeline integration: Research file present but content unclear ⚠")
        (log/log "Pipeline integration: No research available ⚠")))))

;; ═══════════════════════════════════════════════════════════════════════════════
;; Step 3: Self-Evolution (pre-workflow)
;; ═══════════════════════════════════════════════════════════════════════════════

(defn- run-self-evolution
  "Run self-evolution and log the result. Ported from bash run_self_evolution()."
  [label]
  (log/logf "=== %s ===" label)
  (let [root (log/project-root)
        max-wait (:max-wait-evolution @env)]
    (try
      (System/setProperty "PIPELINE_RESEARCH_QUALITY" (:research-quality @env "none"))
      (System/setProperty "PIPELINE_FINDINGS_FILE" (:findings-file @env))
      (System/setProperty "PIPELINE_INTERNAL_FILE" (:internal-file @env))
      (let [result (daemon/run-action! :evolution
                                       {:repo-path root
                                        :timeout-ms (* 1000 max-wait)})]
        (log/log "Self-evolution result:" result))
      (catch Exception e
        (log/logf "WARNING: self-evolution command had issues: %s" (.getMessage e))))))

(defn- step-3-self-evolution-pre!
  []
  (if (:skip-pre-evolution @env)
    (log/log "=== Step 3: Skipped (PIPELINE_SKIP_PRE_EVOLUTION=yes) ===")
    (do
      (run-self-evolution "Step 3: Self-Evolution (pre-workflow)")
      ;; Restart daemon to pick up evolved code
      (log/log "Restarting daemon to load evolved code...")
      (proc/kill-by-pattern! "(pmf-value-stream|gtm-product-org|ov5-auto-workflow)")
      (try (daemon/stop-action! {:server-name "pmf-value-stream"}) (catch Exception _ nil))
      ;; Clean sockets
      (doseq [sock-name ["pmf-value-stream" "gtm-product-org"]]
        (daemon/clean-stale-socket sock-name))
      ;; Clear workflow status
      (try (io/delete-file (io/file (str (log/project-root) "/var/tmp/cron/auto-workflow-status.edn")) true)
           (catch Exception _ nil))
      ;; Git sync
      (git/git-sync-latest! "post-evolution" "auto-workflow-post-pull")
      (Thread/sleep 2000))))

;; ═══════════════════════════════════════════════════════════════════════════════
;; Step 4: Auto-Workflow
;; ═══════════════════════════════════════════════════════════════════════════════

(defn- step-4-auto-workflow!
  []
  (log/log "=== Step 4: Auto-Workflow ===")
  (when (:smoke-only @env)
    (log/log "PIPELINE_SMOKE_ONLY=yes; skipping auto-workflow batch queue")
    (System/exit 0))
  ;; Stop researcher
  (proc/kill-by-pattern! "(pmf-value-stream|gtm-product-org|ov5-auto-workflow)")
  (try (daemon/stop-action! {:server-name "gtm-product-org"}) (catch Exception _ nil))
  (Thread/sleep 2000)
  ;; Queue workflow with retry
  (loop [retry 0]
    (let [result (daemon/run-action! :auto-workflow
                                     {:repo-path (log/project-root)
                                      :timeout-ms (* 1000 (:max-wait-workflow @env))
                                      :server-name "pmf-value-stream"})]
      (if (and (= :already-running result) (< retry 4))
        (do
          (log/logf "Auto-workflow already running, retry %d/5 in 30s..." (inc retry))
          (Thread/sleep 30000)
          (recur (inc retry)))
        (log/logf "Auto-workflow queued: %s" result))))
  ;; Wait for idle
  (daemon/wait-for-idle!
   {:action "auto-workflow"
    :max-wait-ms (* 1000 (:max-wait-workflow @env))
    :socket-name "pmf-value-stream"})
  ;; Verify completion
  (let [status (try (daemon/status-action! {:server-name "pmf-value-stream"}) (catch Exception _ {:phase "unknown"}))]
    (if (contains? #{"idle" "complete" "skipped" "quota-exhausted"} (:phase status))
      (log/log "Auto-workflow completed successfully")
      (when (= "running" (:phase status))
        (log/log "WARNING: Auto-workflow still running after timeout; may need more time")))
    (swap! env assoc :workflow-status status)))

;; ═══════════════════════════════════════════════════════════════════════════════
;; Step 5: Self-Evolution (post-workflow)
;; ═══════════════════════════════════════════════════════════════════════════════

(defn- step-5-self-evolution-post!
  []
  (let [status (:workflow-status @env)]
    (if (contains? #{"idle" "complete" "skipped" "quota-exhausted"} (:phase status))
      (run-self-evolution "Step 5: Self-Evolution (post-workflow)")
      (log/log "Skipping post-workflow self-evolution because auto-workflow did not complete"))))

;; ═══════════════════════════════════════════════════════════════════════════════
;; Step 6: Report
;; ═══════════════════════════════════════════════════════════════════════════════

(defn- step-6-report!
  []
  (log/log "=== Pipeline Complete ===")
  (let [root (log/project-root)]
    ;; Experiment count
    (try
      (let [ws-connect (requiring-resolve 'ov5.world-store/connect)
            ws-exp-count (requiring-resolve 'ov5.world-store/experiment-count)
            ws-path (str root "/var/world-store")]
        (when ws-connect (ws-connect ws-path))
        (let [total (if ws-exp-count (ws-exp-count) 0)]
          (if (> total 0)
            (do
              (log/logf "Results: World Store has %d total experiments" total)
              (swap! env assoc :zero-run 0))
            (do
              (log/log "No experiments in World Store")
              (swap! env assoc :zero-run 1)
              (log/log "  ⚠ NO RESULTS: auto-workflow produced no experiments")))))
      (catch Exception e
        (log/logf "World Store query failed: %s" (.getMessage e))
        (swap! env assoc :zero-run 1)))
    ;; Operational metrics
    (log/log "=== Step 6.1: Operational Metrics ===")
    (try
      (daemon/run-emacsclient-eval
       "pmf-value-stream"
       (str "(progn (ignore-errors (require 'gptel-auto-workflow-production))"
            "  (when (fboundp 'gptel-auto-workflow-operational-metrics-report)"
            "    (gptel-auto-workflow-operational-metrics-report)))")
       :timeout 10)
      (log/log "  Metrics logged to daemon output")
      (catch Exception _
        (log/log "  Daemon not available for metrics (non-fatal)")))
    ;; Daily digest
    (log/log "=== Step 6.4: Daily digest ===")
    (try
      (let [digest-dir (str root "/mementum/knowledge/digests")
            today (java.time.LocalDate/now)
            digest-file (str digest-dir "/" (.format today (java.time.format.DateTimeFormatter/ofPattern "yyyy-MM-dd")) ".md")]
        (.mkdirs (io/file digest-dir))
        ;; Query World Store
        (let [kept-today (try
                           (let [ws-kept-count (requiring-resolve 'ov5.world-store/kept-experiment-count)]
                             (if ws-kept-count (ws-kept-count) 0))
                           (catch Exception _ 0))
              mem-count (try
                          (count (.listFiles (io/file (str root "/mementum/memories"))))
                          (catch Exception _ 0))
              status (or (:pipeline-final-status @env "ok") "ok")]
          (spit (io/file digest-file)
                (str "# Daily Pipeline Digest — " today "\n\n"
                     "> Auto-generated by run-pipeline.sh.\n\n"
                     "## System Health\n\n"
                     "- **Kept experiments this run**: " kept-today "\n"
                     "- **Memory bank**: " mem-count " memories\n"
                     "- **Final status**: " status "\n"
                     "- **Pipeline log**: " (:pipeline-log @env) "\n\n"
                     "## Kept Experiments\n\n"
                     "- Total kept experiments: " kept-today "\n"))
          (log/log "Daily digest written:" digest-file)))
      (catch Exception e
        (log/logf "WARNING: daily digest generation failed: %s" (.getMessage e))))))

;; ═══════════════════════════════════════════════════════════════════════════════
;; Step 7: Publish
;; ═══════════════════════════════════════════════════════════════════════════════

(defn- step-7-publish!
  []
  (log/log "=== Step 7: Publish outcomes to main ===")
  (let [root (log/project-root)]
    ;; Determine final status
    (let [final-status (if (= 1 (:zero-run @env 0)) "zero-run" "ok")]
      (swap! env assoc :pipeline-final-status final-status))
    ;; Update plan, state, patterns
    (update-pipeline-plan (:pipeline-final-status @env "ok"))
    (update-mementum-state (:pipeline-final-status @env "ok"))
    (log-pipeline-patterns (:pipeline-final-status @env "ok"))
    ;; Cross-machine coordination entry
    (when (or (.exists (io/file (:active-runs-file @env)))
              (not= "ok" (:pipeline-final-status @env "ok")))
      (spit (io/file (:active-runs-file @env))
            (str (:hostname @env) "|"
                 (quot (System/currentTimeMillis) 1000) "|"
                 (:pipeline-final-status @env "ok") "\n")
            :append true)
      (log/logf "Recorded this run for cross-machine coordination: %s %s"
               (:hostname @env) (:pipeline-final-status @env "ok")))))

;; ═══════════════════════════════════════════════════════════════════════════════
;; -main entry point
;; ═══════════════════════════════════════════════════════════════════════════════

(defn -main
  "Main pipeline entry point."
  [& args]
  (let [flags (parse-args args)]
    (when (:help flags)
      (usage))
    ;; Setup
    (setup-env! flags)
    (log/log "=== OV5 Self-Evolution Pipeline ===")
    (when (:dry-run flags)
      (log/log "--dry-run: parsed environment, no side effects; exiting")
      (println (str "Project root: " (log/project-root)))
      (println (str "Smoke only: " (:smoke-only @env)))
      (println (str "Log file: " (:pipeline-log @env)))
      (System/exit 0))
    (try
      ;; Phase 0: Bootstrap + Lock + Cross-machine + Cleanup
      (bootstrap-and-pull!)
      (acquire-lock!)
      (cross-machine-check!)
      (cleanup-stale!)
      ;; Phase 0.4-0.7: Audit + Fix + Approvals + Prune
      (create-pipeline-plan)
      (self-audit!)
      (auto-fix!)
      (approval-priorities!)
      (mementum-prune!)
      ;; Step 1: Research
      (step-1-research!)
      ;; Step 2: Verify integration
      (step-2-verify-integration!)
      ;; Step 3: Self-Evolution (pre-workflow)
      (step-3-self-evolution-pre!)
      ;; Step 4: Auto-Workflow
      (step-4-auto-workflow!)
      ;; Step 5: Self-Evolution (post-workflow)
      (step-5-self-evolution-post!)
      ;; Step 6: Report
      (step-6-report!)
      ;; Step 7: Publish
      (step-7-publish!)
      (log/log "=== Pipeline completed successfully ===")
      (System/exit 0)
      (catch Exception e
        (log/logf "=== Pipeline ERROR: %s ===" (.getMessage e))
        (log/log (str/join "\n" (take 10 (str/split-lines (str (.getStackTrace e))))))
        ;; Update state with error status
        (swap! env assoc :pipeline-final-status "err")
        (try (update-pipeline-plan "err") (catch Exception _ nil))
        (try (update-mementum-state "err") (catch Exception _ nil))
        (System/exit 1)))))
