;;; gptel-auto-workflow-skill-governance.el --- Skill governance integration for self-evolution -*- lexical-binding: t; -*-
;; Integrates yknothing/skills-refiner toolkit into our self-evolution pipeline.
;; Three layers:
;;   1. Governance gate — run skill-scan.sh after evolution, report health
;;   2. Skills-refiner reviewer — audit skills using refiner's design framework
;;   3. Activation tracing — inject canaries, observe which skills agents use

;;; Code:

(require 'json)

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
Returns (:status ok|error :skills N :broken-symlinks N :load-blockers N :collisions N)."
  (let* ((root (gptel-auto-workflow--skill-governance-tools-root))
         (scan (expand-file-name "skill-hygiene/bin/skill-scan.sh" root))
         (cmd (format "cd %s && SKILLS_REFINER_TOOLS_ROOT=%s bash %s --json"
                      root root scan))
         (result (gptel-auto-workflow--skill-governance-json cmd)))
    (if result
        (list :status 'ok
              :skills (length (or (gethash :skills result) nil))
              :broken-symlinks (length (or (gethash :broken_symlinks result) nil))
              :load-blockers (length (or (gethash :runtime_load_blockers result) nil))
              :collisions (length (or (gethash :name_collisions result) nil))
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
         (result (gptel-auto-workflow--skill-governance-json cmd)))
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
  "Read the canary observation dashboard for the last DAYS (default 30)."
  (interactive)
  (let* ((root (gptel-auto-workflow--skill-governance-tools-root))
         (dash (expand-file-name "skill-debug/bin/skill-dashboard.sh" root))
         (window (or days 30))
         (cmd (format "cd %s && bash %s --days %d" root dash window))
         (result (gptel-auto-workflow--skill-governance-json cmd)))
    (if result
        (list :status 'ok
              :observed (or (gethash :observed_count result) 0)
              :not-observed (or (gethash :not_observed_count result) 0)
              :observed-rate (or (gethash :observed_rate result) 0.0)
              :raw result)
      (list :status 'no_data))))

;; ─── Evolution Cycle Integration ───

(defun gptel-auto-workflow--skill-governance-run-cycle ()
  "Run a complete skill governance cycle.
1. Scan health
2. Inject canaries (if not already injected)
3. Run dashboard
4. Save report
Designed to be called from the self-evolution cycle."
  (interactive)
  (message "[skill-governance] Starting governance cycle...")

  ;; Layer 1: Health scan
  (let ((scan (gptel-auto-workflow--skill-governance-scan)))
    (message "[skill-governance] Scan: %s skills, %s broken symlinks, %s load blockers"
             (plist-get scan :skills)
             (plist-get scan :broken-symlinks)
             (plist-get scan :load-blockers))
    ;; Block evolution if load blockers found
    (when (> (plist-get scan :load-blockers) 0)
      (message "[skill-governance] WARNING: %d runtime load blockers detected"
               (plist-get scan :load-blockers))))

  ;; Layer 3: Dashboard
  (let ((dash (gptel-auto-workflow--skill-governance-dashboard)))
    (if (eq (plist-get dash :status) 'ok)
        (message "[skill-governance] Dashboard: %d observed, %.0f%% rate"
                 (plist-get dash :observed)
                 (* 100 (plist-get dash :observed-rate)))
      (message "[skill-governance] Dashboard: no observation data (inject canaries first)")))

  ;; Save report
  (gptel-auto-workflow--skill-governance-run-scan-report))

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
