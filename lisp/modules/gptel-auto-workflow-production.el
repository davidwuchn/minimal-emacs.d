;;; gptel-auto-workflow-production.el --- Production integration for self-evolution -*- lexical-binding: t -*-

;; This module ties all self-evolution components together for production use.
;; It runs automatically when the auto-workflow daemon is active.

(require 'cl-lib)
(require 'gptel-auto-workflow-external-sensors nil t)
(require 'gptel-auto-workflow-production-metrics nil t)
(require 'gptel-auto-workflow-monitoring-agent nil t)
(require 'gptel-auto-workflow-human-interface nil t)
(require 'gptel-token-economics nil t)
(require 'gptel-auto-workflow-context-database nil t)
(require 'gptel-auto-workflow-decision-classification nil t)
(require 'gptel-auto-workflow-disposable-tracker nil t)
(declare-function gptel-auto-workflow-evolution-run-cycle "gptel-auto-workflow-evolution")
(declare-function gptel-auto-workflow--worktree-base-root "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--bead-update-from-experiment "gptel-auto-workflow-beads")
(declare-function gptel-auto-workflow--bead-file-from-research "gptel-auto-workflow-beads")
(declare-function gptel-auto-workflow--bead-list "gptel-auto-workflow-beads")
(declare-function gptel-auto-workflow--memory-status "gptel-auto-workflow-mementum")

;; ─── Configuration ───

(defcustom gptel-auto-workflow-evolution-interval 3600
  "Seconds between automatic evolution cycles (default: 1 hour)."
  :type 'integer
  :group 'gptel-tools-agent)

(defvar gptel-auto-workflow--evolution-timer nil
  "Timer for periodic evolution cycles.")

(defvar gptel-auto-workflow--running nil
  "Non-nil when a workflow is actively running experiments.")
(defvar gptel-auto-workflow--cron-job-running nil
  "Non-nil when a cron job is queued or running.")

(defvar gptel-auto-workflow--gc-timer nil
  "Timer for periodic garbage collection.")

(defun gptel-auto-workflow--gc-trigger ()
  "Force garbage collection to prevent memory growth.
Emacs GC doesn't release memory to the OS, but periodic GC
prevents further allocation growth by reusing freed pages.
Runs every 300s (5min) to keep RSS from runaway growth."
  (garbage-collect)
  (message "[mem] GC triggered: %s"
           (let ((stats (gptel-auto-workflow--memory-status)))
             (mapconcat (lambda (m) (format "%s" (plist-get m :state)))
                        stats "; "))))

(defun gptel-auto-workflow-start-gc-timer ()
  "Start periodic GC timer."
  (gptel-auto-workflow-stop-gc-timer)
  (setq gptel-auto-workflow--gc-timer
        (run-with-timer 300 300 #'gptel-auto-workflow--gc-trigger))
  (message "[auto-workflow] GC timer started (300 second intervals)"))

(defun gptel-auto-workflow-stop-gc-timer ()
  "Stop GC timer."
  (when gptel-auto-workflow--gc-timer
    (cancel-timer gptel-auto-workflow--gc-timer)
    (setq gptel-auto-workflow--gc-timer nil)))

;; ─── Automatic Evolution ───

(defun gptel-auto-workflow--maybe-run-evolution ()
  "Run evolution cycle if enabled and not already running.
Also runs periodic mementum maintenance (index rebuild + synthesis)
every cycle when there are candidate memories to process.
Skips when a workflow or cron job is active to avoid preempting experiments."
  (when (and (bound-and-true-p gptel-auto-workflow-evolution-enabled)
             (fboundp 'gptel-auto-workflow-evolution-run-cycle)
             (not (bound-and-true-p gptel-auto-workflow--running))
             (not (bound-and-true-p gptel-auto-workflow--cron-job-running)))
    ;; Ensure base functions are available (breaks circular require)
    (unless (fboundp 'gptel-auto-workflow--worktree-base-root)
      (condition-case nil
          (load "gptel-tools-agent-base" nil t)
        (error nil)))
    ;; Load context database at start of cycle (Phase 3: Context Database)
    (when (fboundp 'gptel-auto-workflow--context-db-load)
      (condition-case nil
          (gptel-auto-workflow--context-db-load)
        (error nil)))
    ;; Optimize token budget allocation based on category ROI (Phase 4: Token Economics)
    (when (fboundp 'gptel-token-economics--optimize-allocation)
      (condition-case nil
          (gptel-token-economics--optimize-allocation 100.0)
        (error nil)))
    ;; Monitoring/approval/disposable/regeneration are now in
    ;; gptel-auto-workflow-evolution-run-cycle itself — no need to call them here.
    (condition-case err
        (progn
          (message "[auto-workflow] Running scheduled evolution cycle...")
          (gptel-auto-workflow-evolution-run-cycle)
          ;; Inform context database after evolution (Phase 3: Context Database)
          (when (fboundp 'gptel-auto-workflow--context-db-persist)
            (condition-case nil
                (gptel-auto-workflow--context-db-persist)
              (error nil)))
          (message "[auto-workflow] Evolution cycle complete."))
      (error
       (message "[auto-workflow] Evolution cycle error: %s" err)
       (condition-case nil
           (let* ((frames (backtrace-frames))
                  (bt (mapconcat (lambda (f) (format "  %S" f))
                                 (seq-take frames 50) "\n"))
                  (log-file (expand-file-name "var/tmp/cron/evolution-backtrace.log"
                                              (or (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                                                       (gptel-auto-workflow--worktree-base-root))
                                                  user-emacs-directory))))
             (when (> (length bt) 0)
               (message "[auto-workflow] Evolution cycle backtrace:\n%s" bt)
               (make-directory (file-name-directory log-file) t)
               (with-temp-file log-file
                 (insert (format-time-string "%Y-%m-%d %H:%M:%S\n"))
                 (insert (format "Error: %s\n" err))
                 (insert (format "Error type: %S\n" (car err)))
                 (insert (format "Error data: %S\n" (cdr err)))
                 (insert "Backtrace (50 frames):\n" bt "\n"))))
         (error
          (message "[auto-workflow] Backtrace logging also failed")))))
    ;; Mementum maintenance: rebuild index + synthesize candidates.
    ;; Runs every cycle (hourly) but is cheap when no new memories exist.
    ;; Enable auto-approve in headless so synthesis actually writes files.
    (condition-case nil
        (when (fboundp 'gptel-mementum-build-index)
          (with-no-warnings
            (let ((gptel-mementum-headless-auto-approve t))
              (gptel-mementum-build-index)
              (when (fboundp 'gptel-mementum-synthesize-all-candidates)
                (gptel-mementum-synthesize-all-candidates nil t)))))
      (error
       (message "[mementum] Maintenance error in evolution cycle")))))

(defun gptel-auto-workflow-start-evolution-timer ()
  "Start periodic evolution timer."
  (interactive)
  (gptel-auto-workflow-stop-evolution-timer)
  (setq gptel-auto-workflow--evolution-timer
        (run-with-timer gptel-auto-workflow-evolution-interval
                        gptel-auto-workflow-evolution-interval
                        #'gptel-auto-workflow--maybe-run-evolution))
  (message "[auto-workflow] Evolution timer started (%d second intervals)"
           gptel-auto-workflow-evolution-interval))

(defun gptel-auto-workflow-stop-evolution-timer ()
  "Stop evolution timer."
  (interactive)
  (when gptel-auto-workflow--evolution-timer
    (cancel-timer gptel-auto-workflow--evolution-timer)
    (setq gptel-auto-workflow--evolution-timer nil)
    (message "[auto-workflow] Evolution timer stopped")))

;; ─── Experiment Hook ───

(defvar gptel-auto-workflow--research-batch-results nil
  "Accumulator for research batch tracking.
List of experiment results sharing the same research context.
Reset when research context changes.")

(defvar gptel-auto-workflow--stats nil)
(defvar gptel-auto-workflow-human-decision-gate nil)
(defun gptel-auto-workflow--experiment-complete-hook (experiment)
  "Hook called when EXPERIMENT completes.
Records to mementum and triggers evolution if needed."
  ;; Record to mementum
  (when (fboundp 'gptel-auto-workflow--mementum-record-experiment)
    (condition-case err
        (gptel-auto-workflow--mementum-record-experiment experiment)
      (error
       (message "[auto-workflow] Mementum recording error: %s" err))))

  ;; Capture business context (Phase 3: Context Database)
  (when (fboundp 'gptel-auto-workflow--capture-experiment-context)
    (condition-case err
        (gptel-auto-workflow--capture-experiment-context experiment)
      (error
       (message "[auto-workflow] Context capture error: %s" err))))

  ;; Persist context database after each experiment
  (when (fboundp 'gptel-auto-workflow--context-db-persist)
    (condition-case err
        (gptel-auto-workflow--context-db-persist)
      (error
       (message "[auto-workflow] Context persist error: %s" err))))

  ;; Track research batch for meta-learning
  (let ((research-hash (plist-get experiment :research-hash)))
    (when (and research-hash (not (equal research-hash "none")))
      ;; Check if this is a new research context
      (when (and gptel-auto-workflow--research-batch-results
                 (not (equal research-hash
                            (plist-get (car gptel-auto-workflow--research-batch-results) :research-hash))))
        ;; Research context changed - record previous batch
        (gptel-auto-workflow--record-research-batch))
      ;; Add to current batch
      (push experiment gptel-auto-workflow--research-batch-results)))

  ;; Record to holographic memory (verbum Phase 7)
  (when (fboundp 'gptel-auto-workflow--record-holographic-experiment)
    (condition-case err
        (gptel-auto-workflow--record-holographic-experiment experiment)
      (error (message "[auto-workflow] Holographic recording error: %s" err))))

  ;; File bead to PMF→GTM channel
  (when (fboundp 'gptel-auto-workflow--bead-update-from-experiment)
    (condition-case err
        (gptel-auto-workflow--bead-update-from-experiment experiment)
      (error (message "[bead] Experiment bead error: %s" err))))

  ;; Update PMF dashboard metrics (Phase 7)
  (when (fboundp 'gptel-auto-workflow--update-pmf-dashboard-metrics)
    (condition-case err
        (gptel-auto-workflow--update-pmf-dashboard-metrics)
      (error (message "[metrics] PMF dashboard update error: %s" err))))

  ;; Run monitoring cycle after each experiment (throttled internally to 15 min)
  ;; Layer 1 Sensor: analyzes failures, generates proposals, triggers architectural evolution
  (when (fboundp 'gptel-auto-workflow--monitoring-cycle)
    (condition-case err
        (gptel-auto-workflow--monitoring-cycle)
      (error (message "[monitoring] Monitoring cycle error: %s" err))))

  ;; Run evolution every N experiments
  (let ((exp-id (or (plist-get experiment :id) 0)))
    (when (and (> exp-id 0)
               (zerop (% exp-id 5))
               (fboundp 'gptel-auto-workflow-evolution-run-cycle))
      (run-with-idle-timer 30 nil #'gptel-auto-workflow--maybe-run-evolution))))

(defun gptel-auto-workflow--record-research-batch ()
  "Record accumulated research batch to mementum.
Called when research context changes or run completes."
  (when (and gptel-auto-workflow--research-batch-results
             (fboundp 'gptel-auto-workflow--mementum-record-research))
    (let* ((first-result (car gptel-auto-workflow--research-batch-results))
           (strategy (plist-get first-result :research-strategy))
           (hash (plist-get first-result :research-hash))
           (targets (delete-dups
                     (mapcar (lambda (r) (plist-get r :target))
                             gptel-auto-workflow--research-batch-results)))
            (kept-count (cl-count-if
                         (lambda (r) (eq (plist-get r :kept) t))
                         gptel-auto-workflow--research-batch-results))
           (total-count (length gptel-auto-workflow--research-batch-results)))
       (condition-case err
           (gptel-auto-workflow--mementum-record-research
            (list :strategy strategy
                  :hash hash
                  :targets targets
                  :kept-count kept-count
                  :total-count total-count
                  :findings (or (and (boundp 'gptel-auto-workflow--current-research-context)
                                     (plist-get gptel-auto-workflow--current-research-context :findings))
                                "")
                  :digested (or (and (boundp 'gptel-auto-workflow--current-research-context)
                                     (plist-get gptel-auto-workflow--current-research-context :digested))
                                "")))
         (error
          (message "[auto-workflow] Research recording error: %s" err))))

   ;; File beads from research findings (GTM → PMF)
   (when (fboundp 'gptel-auto-workflow--bead-file-from-research)
     (condition-case err
          (let* ((_first-result (car gptel-auto-workflow--research-batch-results))
                (findings (or (and (boundp 'gptel-auto-workflow--current-research-context)
                                   (plist-get gptel-auto-workflow--current-research-context :findings))
                              "")))
           (when (and findings (not (string-empty-p findings)))
             (let ((bead-ids (gptel-auto-workflow--bead-file-from-research findings)))
               (when bead-ids
                 (message "[bead] Filed %d beads from research findings"
                          (length bead-ids))))))
       (error (message "[bead] Research bead error: %s" err))))

   ;; Update GTM dashboard metrics (Phase 7)
   (when (fboundp 'gptel-auto-workflow--update-gtm-dashboard-metrics)
     (condition-case err
         (gptel-auto-workflow--update-gtm-dashboard-metrics)
       (error (message "[metrics] GTM dashboard update error: %s" err))))

   ;; Reset batch
   (setq gptel-auto-workflow--research-batch-results nil))

;; ─── Status Dashboard ───

(defun gptel-auto-workflow-evolution-status ()
  "Show evolution system status."
  (interactive)
  (let ((buf (get-buffer-create "*Auto-Workflow Evolution*")))
    (with-current-buffer buf
      (erase-buffer)
      (insert "=== Auto-Workflow Evolution Status ===\n\n")

      ;; Evolution config
      (insert "Configuration:\n")
      (insert (format "  Evolution enabled: %s\n" (bound-and-true-p gptel-auto-workflow-evolution-enabled)))
      (insert (format "  Evolution interval: %d seconds\n" gptel-auto-workflow-evolution-interval))
      (insert (format "  Timer active: %s\n\n" 
                      (if gptel-auto-workflow--evolution-timer "YES" "NO")))

      ;; Knowledge file
      (let ((knowledge-file (expand-file-name
                             "var/tmp/self-evolution.md"
                             (if (fboundp 'gptel-auto-workflow--worktree-base-root)
                                 (gptel-auto-workflow--worktree-base-root)
                               "/Users/davidwu/.emacs.d"))))
        (if (file-exists-p knowledge-file)
            (let ((size (nth 7 (file-attributes knowledge-file)))
                  (mtime (nth 5 (file-attributes knowledge-file))))
              (insert "Knowledge Base:\n")
              (insert (format "  File: %s\n" knowledge-file))
              (insert (format "  Size: %d bytes\n" size))
              (insert (format "  Last updated: %s\n\n" 
                              (format-time-string "%Y-%m-%d %H:%M" mtime))))
          (insert "Knowledge Base: NOT FOUND\n\n")))

      ;; Git stats
      (when (fboundp 'gptel-auto-workflow--git-raw-facts)
        (condition-case nil
            (let ((facts (gptel-auto-workflow--git-raw-facts)))
              (insert "Git History:\n")
              (insert (format "  Active branches: %d\n" 
                              (plist-get facts :total-active)))
              (insert (format "  Historical merges: %d\n" 
                              (plist-get facts :historical-merges)))
              (insert (format "  Merge rate: %.1f%%\n\n" 
                              (* 100 (or (plist-get facts :active-merge-rate) 0.0)))))
          (error nil)))

      ;; Benchmark stats
      (when (fboundp 'gptel-auto-experiment--parse-all-results)
        (condition-case nil
            (let* ((records (gptel-auto-experiment--parse-all-results))
                   (total (length records))
                   (kept (cl-count-if (lambda (r) 
                                        (string= (plist-get r :decision) "kept"))
                                      records)))
              (insert "Benchmark Data:\n")
              (insert (format "  Total experiments: %d\n" total))
              (insert (format "  Kept: %d (%.1f%%)\n\n" 
                              kept (* 100.0 (/ (float kept) (max total 1))))))
          (error nil)))

      ;; Conflicted target review queue
      (when (and (boundp 'gptel-auto-workflow--conflicted-targets)
                 gptel-auto-workflow--conflicted-targets)
        (insert "Conflicted Target Review:\n")
        (let* ((conflicted (length gptel-auto-workflow--conflicted-targets))
               (review-file (when (fboundp 'gptel-auto-workflow--review-file-path)
                              (gptel-auto-workflow--review-file-path)))
               (decisions (when (and review-file (file-exists-p review-file)
                                     (fboundp 'gptel-auto-workflow--read-review-decisions))
                            (gptel-auto-workflow--read-review-decisions)))
               (approved 0) (dropped 0) (pending conflicted))
          (when decisions
            (maphash (lambda (_target dec)
                       (pcase (plist-get dec :decision)
                         ('approved (cl-incf approved) (cl-decf pending))
                         ('dropped (cl-incf dropped) (cl-decf pending))))
                     decisions))
          (insert (format "  Total conflicted: %d\n" conflicted))
          (when (> approved 0)
            (insert (format "  Approved (override): %d\n" approved)))
          (when (> dropped 0)
            (insert (format "  Dropped (human): %d\n" dropped)))
          (insert (format "  Pending review: %d\n" pending))
          (when review-file
            (insert (format "  Review file: %s\n" review-file))))
        (insert "\n"))
      ;; Verbum integration status
      (insert "Verbum Integration:\n")
      (when (boundp 'gptel-auto-workflow--holographic-memory)
        (insert (format "  Holographic memory: %d target-axis pairs\n" 
                        (length gptel-auto-workflow--holographic-memory))))
      ;; Lambda verification report
      (when (fboundp 'gptel-auto-workflow--lambda-verification-report)
        (condition-case nil
            (let ((report (gptel-auto-workflow--lambda-verification-report)))
              (insert "\nLambda Verification Report:\n")
              (insert (format "  Healthy: %d, Degraded: %d, Unknown: %d\n"
                              (plist-get report :healthy)
                              (plist-get report :degraded)
                              (plist-get report :unknown)))
              (dolist (entry (plist-get report :backends))
                (insert (format "  %s: %s\n" (car entry) (cdr entry)))))
          (error nil)))
      ;; Bead protocol status
      (when (fboundp 'gptel-auto-workflow--bead-list)
        (condition-case nil
            (let ((gtm-to-pmf (gptel-auto-workflow--bead-list 'gtm-to-pmf))
                  (pmf-to-gtm (gptel-auto-workflow--bead-list 'pmf-to-gtm)))
              (insert "\nBead Protocol:\n")
              (insert (format "  GTM → PMF: %d beads\n" (length gtm-to-pmf)))
              (insert (format "  PMF → GTM: %d beads\n" (length pmf-to-gtm))))
          (error nil)))

      ;; Human decision gate
      (when (and gptel-auto-workflow-human-decision-gate
                 (fboundp 'gptel-auto-workflow--pending-decisions-p))
        (condition-case nil
            (let ((pending (gptel-auto-workflow--pending-decisions-p)))
              (insert "\nDecision Gate:\n")
              (insert (format "  Status: %s\n" (if pending "BLOCKED (pending decisions)" "clear"))))
          (error nil)))

      (insert "\n")

      (insert "\nPress q to quit\n")
      (goto-char (point-min))
      (local-set-key (kbd "q") #'kill-buffer-and-window))
     (pop-to-buffer buf))))

;; ─── Auto-start ───

(defun gptel-auto-workflow-evolution-auto-start ()
  "Auto-start evolution and GC timers if enabled.
Researcher daemons get periodic research instead of evolution.
Lazy-loads heavy modules (strategic, evolution) as needed."
  (require 'gptel-auto-workflow-strategic nil t)
  (require 'gptel-auto-workflow-evolution nil t)
  (cond
   ;; Researcher daemon: start periodic research + strategy evolution
   ((and (fboundp 'gptel-auto-workflow--researcher-daemon-p)
         (gptel-auto-workflow--researcher-daemon-p))
    (gptel-auto-workflow-start-gc-timer)
    (when (fboundp 'gptel-auto-workflow-start-periodic-research)
      (gptel-auto-workflow-start-periodic-research))
    ;; Phase 6: GTM owns strategy evolution
    (when (fboundp 'gptel-auto-workflow--maybe-run-gtm-strategy-evolution)
      (run-with-idle-timer 120 nil #'gptel-auto-workflow--maybe-run-gtm-strategy-evolution))
    (message "[research] GTM Mayor auto-start: GC + research + strategy evolution timers"))
   ;; PMF Mayor (auto-workflow): start evolution + GC timers
   ((bound-and-true-p gptel-auto-workflow-evolution-enabled)
    (gptel-auto-workflow-start-evolution-timer)
    (gptel-auto-workflow-start-gc-timer)
    ;; Run initial cycle
    (run-with-idle-timer 60 nil #'gptel-auto-workflow--maybe-run-evolution))
   ;; Evolution disabled: just GC
   (t
    (gptel-auto-workflow-start-gc-timer))))

;; τ Wisdom: deferred auto-start so heavy modules load after socket is ready.
(when (daemonp)
  (run-with-idle-timer 10 nil #'gptel-auto-workflow-evolution-auto-start))

;; ─── Pipeline Verification ───

(defun gptel-auto-workflow--verify-pipeline-integration ()
  "Verify that research findings feed into auto-workflow.
Checks:
1. Research findings file exists and has content
2. Research context is set for next auto-workflow run
Returns t if all checks pass, nil with warnings otherwise."
  (let* ((findings-file (expand-file-name "var/tmp/research-findings.md"))
         (findings-ok nil)
         (context-ok nil)
         (issues nil))

    ;; Check 1: Findings file
    (if (and (file-exists-p findings-file)
             (> (nth 7 (file-attributes findings-file)) 100))
        (setq findings-ok t)
      (push "Research findings file missing or too small" issues))

    ;; Check 2: Findings are recent (within last 24 hours)
    (let ((findings-mtime (when (file-exists-p findings-file)
                            (nth 5 (file-attributes findings-file)))))
      (if (and findings-mtime
               (time-less-p (time-subtract (current-time) findings-mtime)
                           (seconds-to-time 86400)))
          (setq context-ok t)
        (push "Research findings are stale (>24h old)" issues)))

    ;; Report
    (if (and findings-ok context-ok)
        (progn
          (message "[pipeline-verification] ✓ All checks passed")
          t)
      (let ((issue-str (string-join (reverse issues) "; ")))
        (message "[pipeline-verification] ✗ Issues found: %s" issue-str)
        (princ (format "ISSUES: %s\n" issue-str))
        nil))))

;;; ─── Human Decision Gate ───

(defcustom gptel-auto-workflow-human-decision-gate nil
  "When non-nil, block PMF experiment dispatch until human approves.
Requires a decision file in mementum/decisions/ with status: approved."
  :type 'boolean
  :group 'gptel-tools-agent)

(defun gptel-auto-workflow--decisions-dir ()
  "Return path to decisions directory."
  (expand-file-name "mementum/decisions/"
                    (or (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                             (gptel-auto-workflow--worktree-base-root))
                        default-directory)))

(defun gptel-auto-workflow--pending-decisions-p ()
  "Return non-nil if there are pending human decisions blocking PMF.
Checks mementum/decisions/ for files with status: proposed."
  (when gptel-auto-workflow-human-decision-gate
    (let ((dir (gptel-auto-workflow--decisions-dir))
          (pending nil))
      (when (file-directory-p dir)
        (dolist (file (directory-files dir t "\\.md$"))
          (unless (string-match-p "TEMPLATE" (file-name-nondirectory file))
            (let* ((content (condition-case nil
                              (with-temp-buffer
                                (insert-file-contents file)
                                (buffer-string))
                            (error nil)))
                   (status (when (and content (string-match "^status:\\s-*\\(.+\\)$" content))
                             (match-string 1 content))))
              (when (and status (string= (string-trim status) "proposed"))
                (setq pending t))))))
      pending)))

(defun gptel-auto-workflow--decision-create (title options gtm-rec pmf-fea)
  "Create a human decision file.
TITLE: decision title
OPTIONS: list of (description pros cons risk)
GTM-REC: GTM mayor recommendation string
PMF-FEA: PMF mayor feasibility string."
  (let* ((dir (gptel-auto-workflow--decisions-dir))
         (id (format-time-string "%Y%m%d-%H%M%S"))
         (file (expand-file-name (format "DECISION-%s.md" id) dir)))
    (make-directory dir t)
    (with-temp-file file
      (insert "---\n")
      (insert (format "id: DECISION-%s\n" id))
      (insert "type: cross-mayor\n")
      (insert "status: proposed\n")
      (insert "proposed-by: gtm-mayor\n")
      (insert "decided-by: human\n")
      (insert "---\n\n")
      (insert (format "# Decision: %s\n\n" title))
      (insert "## Context\n")
      (insert "GTM Mayor detected market signal requiring human judgment.\n\n")
      (insert "## Options\n")
      (cl-loop for (desc pros cons risk) in options
               for opt from ?A
               do (insert (format "### Option %c: %s\n- **Pros:** %s\n- **Cons:** %s\n- **Risk:** %s\n\n"
                                  opt desc pros cons risk)))
      (insert "## GTM Mayor Recommendation\n")
      (insert (format "%s\n\n" gtm-rec))
      (insert "## PMF Mayor Feasibility\n")
      (insert (format "%s\n\n" pmf-fea))
      (insert "## Decision\n\n")
      (insert "- **Chosen:** Option _\n")
      (insert "- **Rationale:** ...\n")
      (insert "- **Trigger condition:** ...\n\n")
      (insert "## Execution Log\n")
      (insert "- [ ] PMF Mayor dispatched\n")
      (insert "- [ ] Experiment complete\n")
      (insert "- [ ] Bead filed to pmf-to-gtm/\n"))
    (message "[decision] Created %s" file)
    file))

;;; ─── Dashboards ───

(defun gptel-auto-workflow--update-dashboard (file &rest replacements)
  "Update dashboard FILE by replacing placeholders with values.
REPLACEMENTS is a plist of :placeholder value pairs.
Example: (:UPDATED \"2026-06-03\" :PLG_STEP \"3\" ...)"
  (when (file-writable-p file)
    (let ((content (with-temp-buffer
                     (insert-file-contents file)
                     (buffer-string))))
      (cl-loop for (placeholder value) on replacements by #'cddr
               do (setq content
                        (replace-regexp-in-string
                         (format "<!-- %s -->" (substring (symbol-name placeholder) 1))
                         (or value "—")
                         content)))
      (with-temp-file file
        (insert content)))))

(defun gptel-auto-workflow--update-pmf-dashboard (&optional stats)
  "Update PMF dashboard with current experiment STATS.
Called after each experiment batch completes."
  (let* ((root (or (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                        (gptel-auto-workflow--worktree-base-root))
                   default-directory))
         (dash-file (expand-file-name "var/tmp/pmf-dashboard.md" root))
         (_results-file (expand-file-name
                        (or (plist-get gptel-auto-workflow--stats :results)
                            (format "var/tmp/experiments/%s/results.tsv"
                                    (format-time-string "%Y-%m-%d")))
                        root))
         (today (format-time-string "%Y-%m-%d %H:%M")))
    (when (file-exists-p dash-file)
      (gptel-auto-workflow--update-dashboard
       dash-file
       :UPDATED today
       :PLG_STEP "3"
       :EXP_TODAY (or (plist-get stats :total) "0")
       :EXP_WEEK "—"
       :KEEP_RATE (or (plist-get stats :kept) "0")
       :EXP_STATUS (if (bound-and-true-p gptel-auto-workflow--running)
                       "running" "idle")
       :VAL_STATUS "—"
       :DEP_STATUS "—"
       :REORIENT (format "PMF Value Stream: %s experiments, %s kept @ %s"
                         (or (plist-get stats :total) 0)
                         (or (plist-get stats :kept) 0)
                         today)))))

(defun gptel-auto-workflow--update-jtbd-dashboard (&optional findings)
  "Update JTBD dashboard with current research FINDINGS.
Called after research cycle completes."
  (let* ((root (or (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                        (gptel-auto-workflow--worktree-base-root))
                   default-directory))
         (dash-file (expand-file-name "var/tmp/jtbd-dashboard.md" root))
         (findings-file (expand-file-name "var/tmp/research-findings.md" root))
         (today (format-time-string "%Y-%m-%d %H:%M"))
         (findings-size (if (file-exists-p findings-file)
                            (nth 7 (file-attributes findings-file))
                          0)))
    (when (file-exists-p dash-file)
      (gptel-auto-workflow--update-dashboard
       dash-file
       :UPDATED today
       :RESEARCH_FRESH (if (> findings-size 100) "fresh" "stale")
       :FINDINGS_VOL (number-to-string findings-size)
       :EXT_SOURCES (if (and findings (stringp findings)
                             (string-match-p "https?://" findings))
                        "yes" "no")
       :CONFIDENCE "—"))))

(defun gptel-auto-workflow--update-gtm-dashboard (&optional findings)
  "Update GTM dashboard, referencing JTBD dashboard.
Called after research cycle completes."
  (let* ((root (or (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                        (gptel-auto-workflow--worktree-base-root))
                   default-directory))
         (dash-file (expand-file-name "var/tmp/gtm-dashboard.md" root))
         (findings-file (expand-file-name "var/tmp/research-findings.md" root))
         (today (format-time-string "%Y-%m-%d %H:%M"))
         (findings-size (if (file-exists-p findings-file)
                            (nth 7 (file-attributes findings-file))
                          0)))
    (when (file-exists-p dash-file)
      ;; First update JTBD dashboard (dependency)
      (gptel-auto-workflow--update-jtbd-dashboard findings)
      ;; Then update GTM dashboard
      (gptel-auto-workflow--update-dashboard
       dash-file
       :UPDATED today
       :JTBD_STEP "3"
       :RES_TODAY "1"
       :FIND_QUAL (if (> findings-size 1000) "high"
                     (if (> findings-size 100) "medium" "low"))
       :CF_STATUS (if (> findings-size 100) "active" "waiting")
       :TOP_SEG "—"
       :TOP_OUTCOME "—"
       :TOP_THREAT "—"
       :REORIENT (format "GTM Product Org: %d bytes findings @ %s"
                         findings-size today)))))

;;; ─── Innovation Queue ───

(defun gptel-auto-workflow--innovation-queue-file ()
  "Return the innovation queue file path."
  (expand-file-name "mementum/innovation-queue.md"
                    (or (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                             (gptel-auto-workflow--worktree-base-root))
                        default-directory)))

(defun gptel-auto-workflow--innovation-queue-add (source technique expected-impact)
  "Add an innovation idea to the queue.
SOURCE: where the idea came from \(e.g., `GitHub trends',
`arXiv paper'\)
TECHNIQUE: what to try \(e.g., `Hashline editing'\)
EXPECTED-IMPACT: predicted outcome \(e.g., `+15% keep-rate'\)
Returns the new item ID."
  (let* ((queue-file (gptel-auto-workflow--innovation-queue-file))
         (id (format "innov-%s-%d"
                     (format-time-string "%Y%m%d")
                     (random 10000)))
         (timestamp (format-time-string "%Y-%m-%d %H:%M"))
         (entry (format "| %s | %s | %s | %s | pending | - | - |\n"
                        id source technique expected-impact)))
    (when (file-exists-p queue-file)
      (let ((content (with-temp-buffer
                       (insert-file-contents queue-file)
                       (buffer-string))))
        ;; Insert after the header row
        (setq content
              (replace-regexp-in-string
               "| ID | Source | Technique | Expected Impact | Status | Experiment ID | Actual
Impact


|\n|----|--------|-----------|-----------------|--------|---------------|---------------|\n"
               (concat "| ID | Source | Technique | Expected Impact | Status | Experiment ID | Actual Impact |\n"
                       "|----|--------|-----------|-----------------|--------|---------------|---------------|\n"
                       entry)
               content))
        ;; Update timestamp
        (setq content (replace-regexp-in-string
                       "<!-- UPDATED -->"
                       timestamp
                       content))
        (with-temp-file queue-file
          (insert content))))
    (message "[innovation] Queued: %s (%s → %s)" id technique expected-impact)
    id))

(defun gptel-auto-workflow--innovation-queue-update (id status &optional experiment-id actual-impact)
  "Update an innovation queue item's STATUS.
ID: the innovation item ID
STATUS: new status (pending|running|validated|discarded|deployed)
EXPERIMENT-ID: optional experiment that tested this idea
ACTUAL-IMPACT: measured outcome after experiments"
  (let* ((queue-file (gptel-auto-workflow--innovation-queue-file))
         (timestamp (format-time-string "%Y-%m-%d %H:%M")))
    (when (file-exists-p queue-file)
      (let ((content (with-temp-buffer
                       (insert-file-contents queue-file)
                       (buffer-string))))
        ;; Update the matching row
        (setq content
              (replace-regexp-in-string
               (format "| %s | \\([^|]+\\) | \\([^|]+\\) | \\([^|]+\\) | \\([^|]+\\) | \\([^|]+\\) |
\\([^|]+\\) |"
                       (regexp-quote id))
               (lambda (match)
                 (let* ((parts (split-string match " | "))
                        (cols (mapcar (lambda (s) (string-trim s)) parts)))
                   (format "| %s | %s | %s | %s | %s | %s | %s |"
                           id
                           (nth 1 cols)
                           (nth 2 cols)
                           (nth 3 cols)
                           status
                           (or experiment-id (nth 5 cols))
                           (or actual-impact (nth 6 cols)))))
               content))
        ;; Update timestamp
        (setq content (replace-regexp-in-string
                       "<!-- UPDATED -->"
                       timestamp
                       content))
        (with-temp-file queue-file
          (insert content))))
    (message "[innovation] Updated %s → %s" id status)))

(defun gptel-auto-workflow--innovation-queue-list (&optional status-filter)
  "Return list of innovation queue items.
Optional STATUS-FILTER limits to items with that status."
  (let* ((queue-file (gptel-auto-workflow--innovation-queue-file))
         items)
    (when (file-exists-p queue-file)
      (with-temp-buffer
        (insert-file-contents queue-file)
        (goto-char (point-min))
        ;; Skip to queue table
        (while (and (not (eobp))
                    (not (looking-at "| ID |")))
          (forward-line 1))
        ;; Skip header and separator
        (forward-line 2)
        ;; Parse rows
        (while (and (not (eobp))
                    (looking-at "|"))
          (let* ((line (buffer-substring (line-beginning-position) (line-end-position)))
                 (parts (split-string line " | "))
                 (cols (mapcar #'string-trim parts)))
            (when (>= (length cols) 7)
              (let ((item (list :id (nth 0 cols)
                               :source (nth 1 cols)
                               :technique (nth 2 cols)
                               :expected-impact (nth 3 cols)
                               :status (nth 4 cols)
                               :experiment-id (nth 5 cols)
                               :actual-impact (nth 6 cols))))
                (when (or (null status-filter)
                          (string= (plist-get item :status) status-filter))
                  (push item items)))))
          (forward-line 1))))
    (nreverse items)))

(defun gptel-auto-workflow--innovation-queue-parse-findings (findings)
  "Parse research FINDINGS for innovation ideas and queue them.
Returns list of queued idea IDs."
  (let ((ids nil))
    ;; Look for innovation signals in findings
    ;; Pattern: "Try [technique] to [expected-impact]"
    (when (stringp findings)
      (with-temp-buffer
        (insert findings)
        (goto-char (point-min))
        (while (re-search-forward
                "Try \\([^\n]+\\) to \\([^\n]+\\)"
                nil t)
          (let ((technique (match-string 1))
                (impact (match-string 2)))
            (push (gptel-auto-workflow--innovation-queue-add
                   "research findings" technique impact)
                  ids)))))
    ids))

;;; ─── Strategy Roadmap (Phase 6: GTM owns strategy) ───

(defun gptel-auto-workflow--gtm-strategy-file ()
  "Return path to GTM strategy roadmap file."
  (expand-file-name "mementum/gtm/strategy-roadmap.md"
                    (or (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                             (gptel-auto-workflow--worktree-base-root))
                        default-directory)))

(defun gptel-auto-workflow--read-gtm-strategy (&optional section)
  "Read GTM strategy roadmap.  If SECTION is provided,
return that section's content.
Sections: current-focus, research-strategy, backend-prefs,
target-rules, experiment-strategy, market-insights,
pmf-checklist, next-review."
  (let ((file (gptel-auto-workflow--gtm-strategy-file)))
    (when (file-exists-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (if (null section)
            (buffer-string)
          (let* ((start-marker (format "<!-- %s -->" (upcase (symbol-name section))))
                 (end-marker (format "<!-- END_%s -->" (upcase (symbol-name section))))
                 (start (save-excursion
                          (goto-char (point-min))
                          (when (search-forward start-marker nil t)
                            (line-beginning-position 2))))
                 (end (save-excursion
                        (goto-char (point-min))
                        (when (search-forward end-marker nil t)
                          (line-beginning-position)))))
            (when (and start end (> end start))
              (string-trim (buffer-substring start end)))))))))

(defun gptel-auto-workflow--write-gtm-strategy (section content)
  "Write CONTENT to SECTION in GTM strategy roadmap.
Creates file if it doesn't exist."
  (let ((file (gptel-auto-workflow--gtm-strategy-file)))
    (make-directory (file-name-directory file) t)
    (if (not (file-exists-p file))
        ;; Create template if missing
        (gptel-auto-workflow--ensure-gtm-strategy-template file))
    (let* ((marker-start (format "<!-- %s -->" (upcase (symbol-name section))))
           (marker-end (format "<!-- END_%s -->" (upcase (symbol-name section))))
           (existing (with-temp-buffer
                       (insert-file-contents file)
                       (buffer-string))))
      (setq existing
            (replace-regexp-in-string
             (format "%s\\(.*\\)?%s"
                     (regexp-quote marker-start)
                     (regexp-quote marker-end))
             (format "%s\n%s\n%s"
                     marker-start
                     content
                     marker-end)
             existing t t))
      (with-temp-file file
        (insert existing))
      (message "[gtm] Updated strategy section: %s" section))))

(defun gptel-auto-workflow--ensure-gtm-strategy-template (file)
  "Create strategy roadmap template at FILE."
  (make-directory (file-name-directory file) t)
  (with-temp-file file
    (insert "---\n")
    (insert "version: 1.0\n")
    (insert "generated-by: gtm-mayor\n")
    (insert (format "updated: %s\n" (format-time-string "%Y-%m-%d")))
    (insert "status: active\n")
    (insert "---\n\n")
    (insert "# Strategy Roadmap\n\n")
    (dolist (section '((current-focus . "JTBD Step 1: Market Definition")
                       (research-strategy . "- Pattern: research-research-none\n- Sources: GitHub, Reddit, HackerNews\n-
Depth: 3 turns max")
                       (backend-prefs . "- Executor: moonshot → MiniMax → DeepSeek\n- Researcher: DeepSeek → moonshot →
DashScope\n- Validator: DashScope → DeepSeek")
                       (target-rules . "1. Prioritize files with TODOs/FIXMEs\n2. Skip files modified in last 24h\n3.
Focus on modules with < 60% keep-rate")
                       (experiment-strategy . "- Max experiments per run: 5\n- Timeout: 900s per experiment\n- Staging:
enabled\n- Auto-merge: disabled")
                       (market-insights . "- None yet")
                       (pmf-checklist . "- [ ] Can measure outcomes in code\n- [ ] Can close gaps with experiments\n- [
] Can serve identified segments\n- [ ] Strategy has measurable milestones")
                       (next-review . "See GTM dashboard")))
      (let ((name (car section))
            (content (cdr section)))
        (insert (format "## %s\n" (capitalize (symbol-name name))))
        (insert (format "<!-- %s -->\n" (upcase (symbol-name name))))
        (insert (if (stringp content) content (eval content)))
        (insert (format "\n<!-- END_%s -->\n\n" (upcase (symbol-name name))))))))

(defun gptel-auto-workflow--maybe-run-gtm-strategy-evolution ()
  "Run strategy evolution if this is the GTM Mayor (researcher daemon).
Writes updated strategy to mementum/gtm/strategy-roadmap.md."
  (when (and (fboundp 'gptel-auto-workflow--researcher-daemon-p)
             (gptel-auto-workflow--researcher-daemon-p)
             (fboundp 'gptel-auto-workflow--run-strategy-evolution))
    (message "[gtm] Running strategy evolution...")
    (condition-case err
        (progn
          (gptel-auto-workflow--run-strategy-evolution)
          ;; Update strategy roadmap with latest
          (gptel-auto-workflow--write-gtm-strategy
           'updated
           (format-time-string "%Y-%m-%d %H:%M"))
          (message "[gtm] Strategy evolution complete"))
       (error
        (message "[gtm] Strategy evolution error: %s" err)))))

;;; ─── Phase 7: Innovation Metrics ───

(defun gptel-auto-workflow--pmf-metrics ()
  "Calculate PMF Mayor metrics from experiment history.
Returns plist with :experiments-today :keep-rate :hours-per-experiment."
  (let* ((results-file (expand-file-name
                        (format "var/tmp/experiments/%s/results.tsv"
                                (format-time-string "%Y-%m-%d"))
                        (or (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                                 (gptel-auto-workflow--worktree-base-root))
                            default-directory)))
         (records (when (file-exists-p results-file)
                    (with-temp-buffer
                      (insert-file-contents results-file)
                      (split-string (buffer-string) "\n" t))))
         (total (length records))
         (kept (cl-count-if (lambda (r) (string-match-p "kept" r)) records))
         (keep-rate (if (> total 0) (/ (float kept) total) 0.0))
         ;; Estimate hours per experiment from timestamps if available
         (hours-per-exp (if (> total 0)
                            (/ 24.0 (max total 1))  ; assume 24h window
                          0.0)))
    (list :experiments-today total
          :keep-rate (format "%.1f%%" (* 100 keep-rate))
          :hours-per-experiment (format "%.1f" hours-per-exp))))

(defun gptel-auto-workflow--gtm-metrics ()
  "Calculate GTM Mayor metrics from research history.
Returns plist with :findings-today :strategy-accuracy :pmf-signal."
  (let* ((findings-file (expand-file-name "var/tmp/research-findings.md"
                                          (or (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                                                   (gptel-auto-workflow--worktree-base-root))
                                              default-directory)))
         (_findings-size (if (file-exists-p findings-file)
                            (nth 7 (file-attributes findings-file))
                          0))
         ;; Count beads filed today as proxy for findings velocity
         (beads (when (fboundp 'gptel-auto-workflow--bead-list)
                  (gptel-auto-workflow--bead-list 'gtm-to-pmf)))
         (findings-today (length beads))
         ;; Strategy accuracy: % of beads that led to kept experiments
         (validated (cl-count-if (lambda (b)
                                   (string= (plist-get b :status) "validated"))
                                 beads))
         (strategy-accuracy (if (> findings-today 0)
                                (/ (float validated) findings-today)
                              0.0))
         ;; PMF signal: correlation between research findings and experiment keep-rate
         (pmf-metrics (gptel-auto-workflow--pmf-metrics))
         (pmf-keep-rate (string-to-number
                         (replace-regexp-in-string "%" ""
                                                   (or (plist-get pmf-metrics :keep-rate) "0"))))
         (pmf-signal (if (> findings-today 0)
                         (* pmf-keep-rate (/ 100.0 (max findings-today 1)))
                       0.0)))
    (list :findings-today findings-today
          :strategy-accuracy (format "%.1f%%" (* 100 strategy-accuracy))
          :pmf-signal (format "%.2f" pmf-signal))))

(defun gptel-auto-workflow--update-pmf-dashboard-metrics ()
  "Update PMF dashboard with Phase 7 metrics."
  (let* ((root (or (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                        (gptel-auto-workflow--worktree-base-root))
                   default-directory))
         (dash-file (expand-file-name "var/tmp/pmf-dashboard.md" root))
         (metrics (gptel-auto-workflow--pmf-metrics))
         (today (format-time-string "%Y-%m-%d %H:%M")))
     (when (file-exists-p dash-file)
       (gptel-auto-workflow--update-dashboard
        dash-file
        :UPDATED today
        :EXP_VELOCITY (format "%s" (or (plist-get metrics :experiments-today) "0"))
        :KEEP_PCT (format "%s" (or (plist-get metrics :keep-rate) "0%"))
        :VALIDATE_HOURS (format "%s" (or (plist-get metrics :hours-per-experiment) "0"))
        :REORIENT (format "PMF Metrics: %s exp, %s kept, %s hrs/val"
                          (or (plist-get metrics :experiments-today) 0)
                          (or (plist-get metrics :keep-rate) "0%")
                          (or (plist-get metrics :hours-per-experiment) "0"))))))

(defun gptel-auto-workflow--update-gtm-dashboard-metrics ()
  "Update GTM dashboard with Phase 7 metrics."
  (let* ((root (or (and (fboundp 'gptel-auto-workflow--worktree-base-root)
                        (gptel-auto-workflow--worktree-base-root))
                   default-directory))
         (dash-file (expand-file-name "var/tmp/gtm-dashboard.md" root))
         (metrics (gptel-auto-workflow--gtm-metrics))
         (today (format-time-string "%Y-%m-%d %H:%M")))
     (when (file-exists-p dash-file)
       (gptel-auto-workflow--update-dashboard
        dash-file
        :UPDATED today
        :FIND_VELOCITY (format "%s" (or (plist-get metrics :findings-today) "0"))
        :STRAT_ACC (format "%s" (or (plist-get metrics :strategy-accuracy) "0%"))
        :PMF_SIGNAL (format "%s" (or (plist-get metrics :pmf-signal) "0"))
        :REORIENT (format "GTM Metrics: %s findings, %s accuracy, signal %s"
                          (or (plist-get metrics :findings-today) 0)
                          (or (plist-get metrics :strategy-accuracy) "0%")
                          (or (plist-get metrics :pmf-signal) "0"))))))

;; ─── Operational Metrics (YC Vision Evidence) ───

(defun gptel-auto-workflow-operational-metrics ()
  "Aggregate cross-cycle operational metrics from all OV5 subsystems.
Returns a plist suitable for logging or dashboard display."
  (let* ((root (or (when (fboundp 'gptel-auto-workflow--worktree-base-root)
                     (gptel-auto-workflow--worktree-base-root))
                   default-directory))
         (root (file-name-as-directory root))
         ;; ── Experiments ──
         (results-files
          (when (file-directory-p (concat root "var/tmp/experiments"))
            (directory-files (concat root "var/tmp/experiments") t
                             "results\\.tsv$" t)))
         (exp-total 0) (exp-kept 0) (exp-failed 0)
         (exp-decisions (make-hash-table :test 'equal))
         (exp-backends (make-hash-table :test 'equal)))
    (dolist (rf results-files)
      (condition-case nil
          (with-temp-buffer
            (insert-file-contents rf)
            (goto-char (point-min))
            (forward-line) ;; skip header
            (while (not (eobp))
              (let ((line (buffer-substring (line-beginning-position)
                                            (line-end-position))))
                (when (string-match "\\`[0-9]" line)
                  (let ((fields (split-string line "\t" t)))
                    (when (>= (length fields) 8)
                      (setq exp-total (1+ exp-total))
                      (let ((decision (nth 7 fields))
                            (backend (when (>= (length fields) 16)
                                       (nth 15 fields))))
                        (puthash decision (1+ (gethash decision exp-decisions 0))
                                 exp-decisions)
                        (when (member decision '("kept" "staged" "merged"))
                          (setq exp-kept (1+ exp-kept)))
                        (when (string-match "failed\\|error\\|timeout" decision)
                          (setq exp-failed (1+ exp-failed)))
                        (when backend
                          (puthash backend
                                   (1+ (gethash backend exp-backends 0))
                                   exp-backends)))))))
              (forward-line)))
        (error nil)))
    ;; ── Approval Queue ──
    (let ((aq-pending 0) (aq-approved 0) (aq-rejected 0)
          (aq-deployed 0) (aq-expired 0))
      (dolist (subdir '("pending" "decisions"))
        (let ((dir (concat root "var/approval-queue/" subdir "/")))
          (when (file-directory-p dir)
            (dolist (f (directory-files dir t "\\.sexp$"))
              (let ((entry (condition-case nil
                               (with-temp-buffer
                                 (insert-file-contents f)
                                 (goto-char (point-min))
                                 (read (current-buffer)))
                             (error nil))))
                (when entry
                  (pcase (plist-get entry :status)
                    ("pending" (setq aq-pending (1+ aq-pending)))
                    ("approved" (setq aq-approved (1+ aq-approved)))
                    ("rejected" (setq aq-rejected (1+ aq-rejected)))
                    ("deployed" (setq aq-deployed (1+ aq-deployed)))
                    ("expired" (setq aq-expired (1+ aq-expired))))))))))
      ;; ── Sensors ──
      (let ((sentry-configured (and (getenv "OV5_SENTRY_API_KEY") t))
            (feedback-configured (and (getenv "OV5_FEEDBACK_ENDPOINT") t))
            (github-data
             (condition-case nil
                 (when (fboundp 'gptel-auto-workflow--github-sensor-collect)
                   (gptel-auto-workflow--github-sensor-collect))
               (error nil))))
        ;; ── Context DB ──
        (let ((ctx-count
               (length (when (file-directory-p (concat root "var/context"))
                         (directory-files (concat root "var/context") t "\\.sexp$")))))
          ;; ── Disposable ──
          (let ((disp-count
                 (length (when (file-directory-p (concat root "var/disposable"))
                           (directory-files (concat root "var/disposable") t "\\.sexp$")))))
            ;; ── Mementum ──
            (let ((mem-count
                   (length (when (file-directory-p (concat root "mementum/memories"))
                             (directory-files (concat root "mementum/memories") t "\\.md$"))))
                  (know-count
                   (length (when (file-directory-p (concat root "mementum/knowledge"))
                             (directory-files (concat root "mementum/knowledge") t "\\.md$")))))
              ;; ── Build result ──
              (list
               :timestamp (format-time-string "%Y-%m-%dT%H:%M:%S")
               :experiments (list :total exp-total
                                  :kept exp-kept
                                  :failed exp-failed
                                  :keep-rate (if (> exp-total 0)
                                                 (/ (float exp-kept) exp-total)
                                               0.0)
                                  :results-files (length results-files)
                                  :decisions
                                  (let ((r nil))
                                    (maphash (lambda (k v) (push (cons k v) r))
                                             exp-decisions)
                                    (sort r (lambda (a b) (> (cdr a) (cdr b)))))
                                  :backends
                                  (let ((r nil))
                                    (maphash (lambda (k v) (push (cons k v) r))
                                             exp-backends)
                                    (sort r (lambda (a b) (> (cdr a) (cdr b))))))
               :approval-queue (list :pending aq-pending
                                     :approved aq-approved
                                     :rejected aq-rejected
                                     :deployed aq-deployed
                                     :expired aq-expired)
                :sensors (list :sentry (if sentry-configured "configured" "not-configured")
                               :feedback (if feedback-configured "configured" "not-configured")
                               :github-open (or (plist-get github-data :open-issues) 0)
                               :github-closed (or (plist-get github-data :closed-issues) 0)
                               :github-bugs (or (plist-get github-data :bug-count) 0))
               :context-db (list :entries ctx-count)
               :disposable (list :candidates disp-count)
               :mementum (list :memories mem-count
                               :knowledge know-count)))))))))

(defun gptel-auto-workflow-operational-metrics-report ()
  "Log a human-readable operational metrics summary.
Suitable for pipeline output and YC evidence.
Also persists the full report to var/metrics/ for historical tracking."
  (let ((m (gptel-auto-workflow-operational-metrics)))
    (let ((exp (plist-get m :experiments))
          (aq (plist-get m :approval-queue))
          (sensors (plist-get m :sensors))
          (ctx (plist-get m :context-db))
          (disp (plist-get m :disposable))
          (mem (plist-get m :mementum)))
      (message "")
      (message "=== OV5 Operational Metrics [%s] ===" (plist-get m :timestamp))
      (message "  Experiments: %d total, %d kept (%.1f%%), %d failed, %d result files"
               (plist-get exp :total)
               (plist-get exp :kept)
               (* 100 (plist-get exp :keep-rate))
               (plist-get exp :failed)
               (plist-get exp :results-files))
      (let ((top-decisions (seq-take (plist-get exp :decisions) 5)))
        (when top-decisions
          (message "  Top decisions: %s"
                   (mapconcat (lambda (d) (format "%s=%d" (car d) (cdr d)))
                              top-decisions ", "))))
      (let ((top-backends (seq-take (plist-get exp :backends) 5)))
        (when top-backends
          (message "  Top backends: %s"
                   (mapconcat (lambda (b) (format "%s=%d" (car b) (cdr b)))
                              top-backends ", "))))
      (message "  Approval Queue: %d pending, %d approved, %d deployed, %d rejected, %d expired"
               (plist-get aq :pending)
               (plist-get aq :approved)
               (plist-get aq :deployed)
               (plist-get aq :rejected)
               (plist-get aq :expired))
       (message "  Sensors: Sentry=%s, Feedback=%s"
                (plist-get sensors :sentry)
                (plist-get sensors :feedback))
       (when (fboundp 'gptel-auto-workflow--github-sensor-summary)
         (condition-case nil
             (message "  %s" (gptel-auto-workflow--github-sensor-summary))
           (error nil)))
       (message "  Context DB: %d entries | Disposable: %d candidates"
               (plist-get ctx :entries)
               (plist-get disp :candidates))
      (message "  Mementum: %d memories, %d knowledge pages"
               (plist-get mem :memories)
               (plist-get mem :knowledge))
      (message "============================================")
      ;; Persist to var/metrics/ for historical tracking
      (condition-case nil
          (let* ((root (or (and (fboundp 'gptel-auto-workflow--expand-workspace-path)
                                (gptel-auto-workflow--expand-workspace-path ""))
                           default-directory))
                 (metrics-dir (expand-file-name "var/metrics/" root))
                 (ts (format-time-string "%Y%m%dT%H%M%S")))
            (make-directory metrics-dir t)
            (with-temp-file (expand-file-name (concat ts "-metrics.sexp") metrics-dir)
              (prin1 m (current-buffer)))
            ;; Keep only last 30 metric snapshots
            (let ((files (sort (directory-files metrics-dir t "-metrics\\.sexp$")
                               (lambda (a b) (string< a b)))))
              (dolist (f (seq-take files (- (length files) 30)))
                (ignore-errors (delete-file f)))))
        (error nil))
      m)))

(provide 'gptel-auto-workflow-production)
;;; gptel-auto-workflow-production.el ends here
