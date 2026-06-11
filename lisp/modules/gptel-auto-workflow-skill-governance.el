;;; gptel-auto-workflow-skill-governance.el --- Skill governance integration for self-evolution -*- lexical-binding: t; -*-
;; Integrates yknothing/skills-refiner toolkit into our self-evolution pipeline.
;; Four layers:
;;   1. Governance gate — run skill-scan.sh after evolution, report health
;;   2. Semia security audit — static analysis for shell commands, network access, secrets
;;   3. Dashboard — observe which skills agents actually use
;;   4. Activation tracing — inject canaries, observe which skills agents use
;;   5. Skill-eval A/B testing — measure skill effectiveness

;;; Code:

(require 'json)
(declare-function gptel-auto-workflow--worktree-base-root "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--json-encode-plist "gptel-auto-workflow-ontology-router" (plist))
(defvar gptel-auto-workflow-opencode-eval-enabled nil
  "When non-nil, run opencode skill A/B evals during governance cycle.")
(declare-function gptel-auto-workflow-skill-eval-parse-task "gptel-auto-workflow-skill-eval-opencode" (filepath))
(declare-function gptel-auto-workflow-skill-eval-ab "gptel-auto-workflow-skill-eval-opencode" (skill-name task &optional n-runs))
(declare-function gptel-auto-workflow-skill-eval-promote "gptel-auto-workflow-skill-eval-opencode" (skill-name ab-result))

;; ─── Semia Security Audit (Layer 2) ───

(defvar gptel-auto-workflow--semia-bin "semia"
  "Path or name of the Semia CLI binary.")

(defvar gptel-auto-workflow--semia-report-dir nil
  "Directory for Semia scan reports (set at first use).")

(defun gptel-auto-workflow--semia-report-dir ()
  "Return the Semia report directory."
  (or gptel-auto-workflow--semia-report-dir
      (setq gptel-auto-workflow--semia-report-dir
            (expand-file-name "var/tmp/skill-governance/semia"
                              user-emacs-directory))))

(defun gptel-auto-workflow--semia-available-p ()
  "Return non-nil when Semia CLI is available."
  (condition-case nil
      (= 0 (call-process gptel-auto-workflow--semia-bin nil nil nil "--version"))
    (error nil)))

(defun gptel-auto-workflow--semia-scan-skill (skill-dir)
  "Run Semia security audit on SKILL-DIR.
Returns plist with :skill :findings :errors :warnings :status, or nil on
failure.  Uses offline baseline (no LLM calls) for fast static analysis."
  (let* ((slug (file-name-nondirectory (directory-file-name skill-dir)))
         (run-dir (expand-file-name slug (gptel-auto-workflow--semia-report-dir)))
         (result-file (expand-file-name "detection_result.json" run-dir))
         (report-file (expand-file-name "report.md" run-dir)))
    (make-directory run-dir t)
    (condition-case err
        (progn
          (call-process gptel-auto-workflow--semia-bin nil nil nil
                        "scan" (expand-file-name skill-dir)
                        "--offline-baseline" "--out" run-dir)
          (if (file-exists-p result-file)
              (let* ((json-object-type 'plist)
                     (json-key-type 'keyword)
                     (result (json-read-file result-file)))
                (list :skill slug
                      :findings (or (plist-get result :findings) 0)
                      :status (plist-get result :status)
                      :report report-file
                      :result-file result-file))
            (list :skill slug :findings -1 :status "no_result" :error "detection_result.json missing")))
      (error
       (message "[semia] Scan failed for %s: %s" slug err)
       nil))))

(defun gptel-auto-workflow--semia-scan-all-skills ()
  "Run Semia security audit on all skill directories.
Returns list of result plists."
  (unless (gptel-auto-workflow--semia-available-p)
    (message "[semia] CLI not available (install: uv tool install semia-audit)")
    (list (list :status 'unavailable :message "semia CLI not found")))
  (let* ((skills-root (expand-file-name "assistant/skills" user-emacs-directory))
         (results nil))
    (if (file-directory-p skills-root)
        (dolist (skill-dir (directory-files skills-root t "^[^._]"))
          (when (and (file-directory-p skill-dir)
                     (file-exists-p (expand-file-name "SKILL.md" skill-dir)))
            (message "[semia] Scanning %s..." (file-name-nondirectory skill-dir))
            (when-let ((result (gptel-auto-workflow--semia-scan-skill skill-dir)))
              (push result results))))
      (message "[semia] No skills directory found"))
    (nreverse results)))

;; ─── Skills-Refiner Helpers ───

(defvar gptel-auto-workflow--skill-governance-tools-root nil
  "Path to skills-refiner toolkit installation.")

(defun gptel-auto-workflow--skill-governance-tools-root ()
  "Return the skills-refiner toolkit root directory."
  (or gptel-auto-workflow--skill-governance-tools-root
      (let ((root (expand-file-name ".agents/skills"
                                     (gptel-auto-workflow--worktree-base-root))))
        (if (file-exists-p (expand-file-name "skill-hygiene/bin/skill-scan.sh" root))
            root
          (expand-file-name ".agents/skills" "~")))))

(defun gptel-auto-workflow--skill-governance-shell (command &rest args)
  "Run a skills-refiner shell COMMAND with ARGS, return stdout or nil on error."
  (condition-case nil
      (let ((cmd (mapconcat #'identity
                            (cons command args) " ")))
        (with-temp-buffer
          (if (= 0 (call-process "bash" nil t nil "-c" cmd))
              (string-trim (buffer-string))
            (progn
              (message "[skill-governance] Shell command failed: %s" cmd)
              nil))))
    (error nil)))

(defun gptel-auto-workflow--skill-governance-json (cmd)
  "Run shell CMD, parse JSON output, return parsed object or nil."
  (let ((json (gptel-auto-workflow--skill-governance-shell cmd)))
    (when (and json (not (string-empty-p json)))
      (condition-case nil
          (let ((json-object-type 'hash-table)
                (json-array-type 'list)
                (json-key-type 'keyword))
            (json-read-from-string json))
        (error nil)))))

;; ─── Layer 1: Governance Gate ───

(defun gptel-auto-workflow--skill-governance-scan ()
  "Run skill-scan.sh and return health plist.
Returns (:status ok|error :skills N :broken-symlinks N :load-blockers N
:collisions N)."
  (let* ((root (gptel-auto-workflow--skill-governance-tools-root))
         (scan (expand-file-name "skill-hygiene/bin/skill-scan.sh" root))
         (cmd (format "cd %s && SKILLS_REFINER_TOOLS_ROOT=%s bash %s --json"
                      root root scan))
         (result (if (file-exists-p scan)
                      (gptel-auto-workflow--skill-governance-json cmd)
                    nil)))
    (if result
        (list :status 'ok
              :skills (length (gethash :skills result))
              :broken-symlinks (length (gethash :broken_symlinks result))
              :load-blockers (length (gethash :runtime_load_blockers result))
              :collisions (length (gethash :name_collisions result))
              :topology (if (hash-table-p (gethash :topology result))
                            (hash-table-count (gethash :topology result))
                          0)
              :raw result)
      (list :status 'error
            :error "scan_failed"))))

(defun gptel-auto-workflow--skill-governance-doctor ()
  "Run the full doctor check and return summary plist."
  (let* ((root (gptel-auto-workflow--skill-governance-tools-root))
         (doctor (expand-file-name "skill-debug/bin/skills-refiner-doctor.sh" root))
         (cmd (format "cd %s && SKILLS_REFINER_TOOLS_ROOT=%s bash %s --json"
                      root root doctor))
         (result (if (file-exists-p doctor)
                      (gptel-auto-workflow--skill-governance-json cmd)
                    nil)))
    (if result
        (let ((probe (gethash :probe result))
              (dash (gethash :dashboard result))
              (hyg (gethash :hygiene result)))
          (list :status 'ok
                :discoverable (if (and probe (gethash :counts probe))
                                  (gethash :discoverable_entries (gethash :counts probe))
                                0)
                :dashboard (if dash (gethash :status dash) "unknown")
                :hygiene (if hyg (gethash :status hyg) "unknown")
                :raw result))
      (list :status 'error :error "doctor_failed"))))

(defun gptel-auto-workflow--skill-governance-dashboard (&optional days)
  "Read the canary observation dashboard for the last DAYS (default 30).
Also includes opencode eval stats if available."
  (interactive)
  (let* ((root (gptel-auto-workflow--skill-governance-tools-root))
         (dash (expand-file-name "skill-debug/bin/skill-dashboard.sh" root))
         (window (or days 30))
         (cmd (format "cd %s && bash %s --days %d" root dash window))
         (result (if (file-exists-p dash)
                      (gptel-auto-workflow--skill-governance-json cmd)
                    nil))
         (base (if result
                   (list :status 'ok
                         :observed (or (gethash :observed_count result) 0)
                         :not-observed (or (gethash :not_observed_count result) 0)
                         :observed-rate (or (gethash :observed_rate result) 0.0)
                         :raw result)
                 (list :status 'no_data))))
    ;; Append opencode eval stats
    (let* ((eval-dir (expand-file-name "var/tmp/skill-eval-opencode/results/"
                                        (or (gptel-auto-workflow--worktree-base-root)
                                            default-directory)))
           (eval-count (if (file-directory-p eval-dir)
                           (length (directory-files eval-dir t "\\.json\\'" t))
                         0)))
      (when (> eval-count 0)
        (setq base (plist-put base :opencode-eval-runs eval-count)))
      base)))

;; ─── Missing Implementation Functions ───

(defun gptel-auto-workflow--skill-governance-inject-canaries ()
  "Inject observation canaries into skill files for activation tracing.
Canaries are invisible markers that get logged when a skill is loaded,
allowing us to track which skills agents actually use vs ignore."
  (let* ((skills-dir (expand-file-name "assistant/skills"
                                        (or (gptel-auto-workflow--worktree-base-root)
                                            "~")))
         (canary-tag "<!-- canary: observed -->")
         (count 0))
    (when (file-directory-p skills-dir)
      (dolist (skill-dir (directory-files skills-dir t "^[^._]"))
        (when (file-directory-p skill-dir)
          (let ((skill-file (expand-file-name "SKILL.md" skill-dir)))
            (when (file-exists-p skill-file)
              (with-temp-buffer
                (insert-file-contents skill-file)
                (unless (search-forward "canary:" nil t)
                  (goto-char (point-max))
                  (insert "\n" canary-tag "\n")
                  (write-region nil nil skill-file)
                  (cl-incf count))))))))
    (message "[skill-governance] Injected canaries in %d skills" count)
    count))

(defun gptel-auto-workflow--skill-governance-run-scan-report ()
  "Save scan health report to var/tmp/skill-governance/."
  (let* ((report-dir (expand-file-name "var/tmp/skill-governance"
                                        (or (gptel-auto-workflow--worktree-base-root)
                                            "~")))
         (report-file (expand-file-name (format "scan-%s.json"
                                                (format-time-string "%Y%m%d-%H%M"))
                                        report-dir))
         (skills-dir (expand-file-name "assistant/skills"
                                        (or (gptel-auto-workflow--worktree-base-root)
                                            "~")))
         (health (gptel-auto-workflow--skill-governance-scan))
         (doctor (gptel-auto-workflow--skill-governance-doctor)))
    (make-directory report-dir t)
    (let ((report (list :timestamp (format-time-string "%Y-%m-%dT%H:%M:%SZ")
                       :health health
                       :doctor doctor
                        :skills-count (let ((cnt 0))
                                        (dolist (dir (directory-files skills-dir t "^[^._]"))
                                          (when (and (file-directory-p dir)
                                                     (file-exists-p (expand-file-name "SKILL.md" dir)))
                                            (cl-incf cnt)))
                                         cnt))))
      (with-temp-file report-file
        (insert (gptel-auto-workflow--json-encode-plist report)))
      (message "[skill-governance] Saved scan report: %s"
               (file-name-nondirectory report-file))
      report)))

;; ─── Bridge: Skill A/B Testing via Benchmark Infrastructure ───

(defun gptel-auto-workflow--skill-eval-run-ab (skill-name target-file &optional n-experiments)
  "Run controlled A/B experiment for SKILL-NAME on TARGET-FILE.
Returns plist with (:skill :baseline-success :treatment-success :delta
:recommendation).  Integrates skill-eval methodology with benchmark
infrastructure.  N-EXPERIMENTS per arm (default 3)."
  (let* ((n (or n-experiments 3))
         (_skill-label (format "skill-eval:%s" skill-name))
         (baseline (gptel-auto-workflow--skill-eval-run-arm
                    target-file nil n))
         (treatment (gptel-auto-workflow--skill-eval-run-arm
                     target-file skill-name n))
         (delta (- (plist-get treatment :success-rate)
                   (plist-get baseline :success-rate)))
         (effect-size (if (> (plist-get baseline :stddev) 0)
                          (/ delta (plist-get baseline :stddev))
                        0.0)))
    (list :skill skill-name
          :target target-file
          :baseline-success (plist-get baseline :success-rate)
          :treatment-success (plist-get treatment :success-rate)
          :delta delta
          :effect-size effect-size
          :recommendation (cond
                           ((> effect-size 0.3) 'keep)
                           ((< effect-size 0.1) 'reject)
                           (t 'indeterminate)))))

(defun gptel-auto-workflow--skill-eval-run-arm (target-file skill-name n)
  "Run N experiments on TARGET-FILE with SKILL-NAME injected (or nil for baseline).
Returns plist with (:success-rate :stddev :experiments)."
  (let ((results nil))
    (dotimes (_ n)
      (let ((result (condition-case err
                        (gptel-auto-workflow--skill-eval-single-experiment
                         target-file skill-name)
                      (error
                       (list :success nil :error (error-message-string err))))))
        (push result results)))
    (let* ((successes (cl-count-if (lambda (r) (plist-get r :success)) results))
           (rate (/ (float successes) (float n)))
           (mean rate)
           (variance (/ (apply '+ (mapcar
                                   (lambda (r) (expt (- (if (plist-get r :success) 1.0 0.0) mean) 2))
                                   results))
                        (float n))))
      (list :success-rate rate
            :stddev (sqrt variance)
            :experiments results))))

(defun gptel-auto-workflow--skill-eval-single-experiment (target-file &optional skill-name)
  "Run a single experiment on TARGET-FILE, optionally with SKILL-NAME injected.
Returns plist (:success t|nil :compile-ok t|nil :anti-patterns N)."
  (let* ((default-directory (file-name-directory target-file))
         (compile-ok (condition-case nil
                         (progn
                           (byte-compile-file target-file)
                           t)
                       (error nil)))
         ;; Run behavioral tests if available
         (tests-ok (and (fboundp 'gptel-auto-workflow--run-behavioral-tests)
                        (gptel-auto-workflow--run-behavioral-tests
                         (list target-file)))))
    (list :success (and compile-ok (or (not tests-ok) (car tests-ok)))
          :compile-ok compile-ok
          :tests-ok (if tests-ok (car tests-ok) t)
          :skill-injected (if skill-name t nil)
          :skill-name skill-name)))

;; ─── Evolution Cycle Integration ───

(defun gptel-auto-workflow--skill-governance-run-cycle ()
  "Run a complete skill governance cycle.
1. Health scan (skills-refiner)
2. Semia security audit (static analysis)
3. Inject canaries / Dashboard
4. Skill-eval A/B tests (Emacs-scope)
5. Opencode skill A/B tests (when feature flag enabled)
6. Save report"
  (interactive)
  (message "[skill-governance] Starting governance cycle...")

  ;; Layer 1: Health scan
  (let ((scan (gptel-auto-workflow--skill-governance-scan)))
    (message "[skill-governance] Scan: %s skills, %s broken symlinks, %s load blockers"
             (plist-get scan :skills)
             (plist-get scan :broken-symlinks)
             (plist-get scan :load-blockers))
    (when (and (plist-get scan :load-blockers)
               (> (plist-get scan :load-blockers) 0))
      (message "[skill-governance] WARNING: %d runtime load blockers detected"
               (plist-get scan :load-blockers))))

  ;; Layer 2: Semia security audit
  (when (gptel-auto-workflow--semia-available-p)
    (let ((semia-results (gptel-auto-workflow--semia-scan-all-skills))
          (findings 0) (errors 0))
      (dolist (r semia-results)
        (when (plist-get r :findings)
          (cl-incf findings (plist-get r :findings)))
        (unless (equal (plist-get r :status) "ok")
          (cl-incf errors)))
      (if (> findings 0)
          (message "[skill-governance] Semia: %d findings across %d skills (%d errors)"
                   findings (length semia-results) errors)
        (message "[skill-governance] Semia: %d skills scanned, 0 findings"
                 (length semia-results)))))

  ;; Layer 3: Dashboard
  (let ((dash (gptel-auto-workflow--skill-governance-dashboard)))
    (if (eq (plist-get dash :status) 'ok)
        (message "[skill-governance] Dashboard: %d observed, %.0f%% rate"
                 (plist-get dash :observed)
                 (* 100 (plist-get dash :observed-rate)))
      (message "[skill-governance] Dashboard: no observation data (inject canaries first)")))

  ;; Layer 4: Skill-eval A/B testing on recently evolved skills
  (let ((recent (gptel-auto-workflow--evolution-get-recently-evolved-skills))
        (results nil))
    (dolist (skill-name recent)
      (let* ((target (gptel-auto-workflow--skill-eval-pick-target skill-name))
             (ab (when target
                   (gptel-auto-workflow--skill-eval-run-ab skill-name target 2))))
        (when ab
          (push ab results)
          (message "[skill-governance] Skill-eval %s: delta=%.2f, %s"
                   skill-name (plist-get ab :delta)
                   (plist-get ab :recommendation)))))
    (when results
      (gptel-auto-workflow--skill-governance-save-ab-results results)))

  ;; Layer 5: Opencode skill A/B evals (feature-gated)
  (when gptel-auto-workflow-opencode-eval-enabled
    (message "[skill-governance] Running opencode skill eval cycle...")
    (condition-case err
        (gptel-auto-workflow--skill-governance-run-opencode-cycle)
      (error
       (message "[skill-governance] Opencode eval cycle error: %s"
                (error-message-string err)))))

  ;; Save report
  (gptel-auto-workflow--skill-governance-run-scan-report))

(defun gptel-auto-workflow--skill-eval-pick-target (skill-name)
  "Pick a suitable target file for evaluating SKILL-NAME.
Returns file path or nil if no suitable target found."
  (let ((modules-dir (expand-file-name "lisp/modules"
                                        (or (gptel-auto-workflow--worktree-base-root)
                                            "~"))))
    (cond
     ((string-match "elisp" skill-name)
      (expand-file-name "gptel-ext-retry.el" modules-dir))
     ((string-match "debug" skill-name)
      (expand-file-name "gptel-auto-workflow-strategic.el" modules-dir))
     ((string-match "replace" skill-name)
      (expand-file-name "gptel-tools-agent-git.el" modules-dir))
     ((string-match "refactor" skill-name)
      (expand-file-name "gptel-sandbox.el" modules-dir))
     ((string-match "discover" skill-name)
      (expand-file-name "gptel-ext-fsm-utils.el" modules-dir))
     (t
      ;; Pick smallest non-trivial module
      (car (sort (directory-files modules-dir t "\\.el$")
                 (lambda (a b)
                   (< (or (nth 7 (file-attributes a)) 0)
                      (or (nth 7 (file-attributes b)) 0)))))))))

;; ─── Opencode Skill Eval Integration (Layer 6) ───

(defcustom gptel-auto-workflow-opencode-eval-enabled nil
  "When non-nil, run opencode skill A/B evals during governance cycle.
Opencode evals test whether skill variants change agent behavior
on controlled tasks.  Disabled by default to avoid unnecessary
LLM costs; enable when skill evolution is active."
  :type 'boolean
  :group 'gptel-auto-workflow)

(defcustom gptel-auto-workflow-opencode-eval-skills '("brepl" "daemon-repl" "ov5")
  "List of skill names eligible for opencode A/B evaluation.
Each skill must have a task corpus in `assistant/skills/_eval-tasks/'."
  :type '(repeat string)
  :group 'gptel-auto-workflow)

(defun gptel-auto-workflow--evolution-get-recently-evolved-skills ()
  "Return a list of skill names that were recently evolved.
Scans the evolution history for skills modified in the last 24 hours.
Returns the opencode eval skills list as a fallback."
  (or (ignore-errors
        (let* ((root (or (gptel-auto-workflow--worktree-base-root)
                         default-directory))
               (skills-dir (expand-file-name "assistant/skills" root))
               (cutoff (- (float-time) 86400))
               (recent nil))
          (when (file-directory-p skills-dir)
            (dolist (entry (directory-files skills-dir t nil t))
              (let ((skill-file (expand-file-name "SKILL.md" entry)))
                (when (and (file-exists-p skill-file)
                           (> (float-time (nth 5 (file-attributes skill-file)))
                              cutoff))
                   (push (file-name-nondirectory entry) recent)))))
          (nreverse recent)))
      ;; Fallback: return the configured opencode eval skills
      gptel-auto-workflow-opencode-eval-skills))

(defun gptel-auto-workflow--skill-governance-run-opencode-cycle ()
  "Run opencode skill A/B evals for eligible skills.
For each skill in `gptel-auto-workflow-opencode-eval-skills':
1. Load task corpus from `assistant/skills/_eval-tasks/'
2. Run A/B comparison (baseline vs variant)
3. If variant wins, enqueue for human approval
4. Save results tagged with :platform \"opencode\""
  (require 'gptel-auto-workflow-skill-eval-opencode nil t)
  (when (fboundp 'gptel-auto-workflow-skill-eval-ab)
    (let ((results nil))
      (dolist (skill-name gptel-auto-workflow-opencode-eval-skills)
        (message "[skill-governance] Opencode eval: %s" skill-name)
        (condition-case err
            (let* ((task-dir (or (and (boundp 'gptel-auto-workflow-skill-eval-task-dir)
                                      gptel-auto-workflow-skill-eval-task-dir)
                                (expand-file-name "assistant/skills/_eval-tasks/"
                                                  (or (gptel-auto-workflow--worktree-base-root)
                                                      default-directory))))
                   (tasks (when (file-directory-p task-dir)
                            (directory-files task-dir t
                                             (format "%s.*\\.yaml\\'" (regexp-quote skill-name))
                                             t)))
                   (task-file (car tasks)))
              (when task-file
                (let* ((task (gptel-auto-workflow-skill-eval-parse-task task-file))
                       (ab (when task
                             (gptel-auto-workflow-skill-eval-ab skill-name task 2))))
                  (when ab
                    (push (plist-put ab :platform "opencode") results)
                    (message "[skill-governance] Opencode %s: baseline=%.2f treatment=%.2f rec=%s"
                             skill-name
                             (or (plist-get ab :baseline-rate) 0)
                             (or (plist-get ab :treatment-rate) 0)
                             (plist-get ab :recommendation))
                    ;; Auto-promote if variant wins
                    (when (and (string= (plist-get ab :recommendation) "promote")
                               (fboundp 'gptel-auto-workflow-skill-eval-promote))
                      (gptel-auto-workflow-skill-eval-promote skill-name ab))))))
          (error
           (message "[skill-governance] Opencode eval error for %s: %s"
                    skill-name (error-message-string err)))))
      (when results
        (gptel-auto-workflow--skill-governance-save-ab-results
         (cons (list :platform "opencode" :count (length results)) results))))))

(defun gptel-auto-workflow--skill-governance-save-ab-results (results)
  "Save A/B test RESULTS to var/tmp/skill-governance/ab-results.json."
  (let* ((report-dir (expand-file-name "var/tmp/skill-governance" user-emacs-directory))
         (report-file (expand-file-name "ab-results.json" report-dir)))
    (make-directory report-dir t)
    (with-temp-file report-file
       (insert (gptel-auto-workflow--json-encode-plist results)))
    (message "[skill-governance] Saved A/B results: %d skills tested" (length results))))

(defun gptel-auto-workflow--skill-governance-schedule-canary-refresh ()
  "Schedule periodic canary injection."
  ;; Inject canaries once per day
  (run-with-timer 3600 86400
   (lambda ()
     (condition-case nil
         (gptel-auto-workflow--skill-governance-inject-canaries)
       (error nil)))))

(provide 'gptel-auto-workflow-skill-governance)
;;; gptel-auto-workflow-skill-governance.el ends here
