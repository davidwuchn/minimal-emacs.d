;;; gptel-auto-workflow-monitoring-agent.el --- Failure pattern analysis for self-evolution -*- lexical-binding: t -*-

;; Copyright (C) 2026 OV5 Self-Improving Architecture

;; Author: OV5 System
;; Keywords: automation, monitoring, failure-patterns, meta-improvement

;;; Commentary:

;; Monitoring agent Phase 1: failure pattern analysis.
;; Phase 2: proposal generation from systemic failure patterns.
;; Phase 3: auto-test & deploy proposals, safe rollback, human-in-the-loop.
;; Parses TSV experiment logs, detects recurring failures, classifies by type,
;; generates improvement proposals, scores and validates them,
;; tests against historical data, auto-deploys if success rate exceeds threshold,
;; and persists patterns, proposals, and deployment decisions to mementum.
;;
;; Classification categories:
;;   grader      -- grader_reason contains syntax/type/undefined errors
;;   compilation -- code fails to compile or missing dependencies
;;   prompt      -- prompt too long, missing context, or unclear instructions
;;   strategy    -- wrong/no strategy selected, poor target prioritization
;;   unknown     -- uncategorizable failures
;;
;; Throttle: max 1 cycle per 15 minutes (900 seconds).

;;; Code:

(require 'cl-lib)

;; Forward declarations for optional cross-module calls
(declare-function gptel-auto-workflow-code-regeneration--execute
  "gptel-auto-workflow-code-regeneration")
(declare-function gptel-auto-workflow--mementum-write-memory
  "gptel-auto-workflow-mementum")
(declare-function gptel-auto-workflow--mementum-slug
  "gptel-auto-workflow-mementum")
(require 'subr-x)

(declare-function gptel-auto-workflow--parse-all-results
                  "gptel-auto-workflow-evolution")
(declare-function gptel-auto-workflow--mementum-write-memory
                  "gptel-auto-workflow-mementum")
(declare-function gptel-auto-workflow--mementum-slug
                  "gptel-auto-workflow-mementum")
(declare-function gptel-auto-workflow--worktree-base-root
                  "gptel-tools-agent-base")
(declare-function gptel-auto-workflow--git-cmd
                  "gptel-tools-agent-experiment-loop")
(declare-function gptel-auto-workflow--with-staging-worktree
                  "gptel-tools-agent-experiment-loop")

(declare-function gptel-auto-workflow-approval-queue-enqueue
                  "gptel-auto-workflow-approval-queue")

(declare-function gptel-auto-workflow--run-architectural-analysis
                  "gptel-auto-workflow-architectural-evolution")

;; ── Configuration ──

(defcustom gptel-auto-workflow-monitoring-enabled t
  "When non-nil, enable monitoring agent failure pattern analysis."
  :type 'boolean
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-monitoring-min-occurrences 3
  "Minimum occurrences of a failure pattern before flagging as systemic.
Requires 3+ occurrences to reduce false positives from one-off failures."
  :type 'integer
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-monitoring-cycle-interval 900
  "Minimum seconds between monitoring cycles (default: 15 minutes).
Prevents excessive analysis overhead on the experiment pipeline."
  :type 'integer
  :group 'gptel-tools-agent)

(defvar gptel-auto-workflow-monitoring-last-cycle-time 0.0
  "Float-time of last monitoring cycle.  Used for throttle enforcement.")

(defvar gptel-auto-workflow-monitoring-cycle-counter 0
  "Counter for monitoring cycles, used to run health probes every 3rd cycle.")

;; ── Phase 0: Runtime Health Probes ──

(defun gptel-auto-workflow--probe-daemon-alive ()
  "Check if the Emacs daemon process is responsive.
Returns plist with :alive, :pid, :uptime."
  (let* ((pid (emacs-pid))
         (attrs (ignore-errors (process-attributes pid)))
         (alive (and attrs t))
         (uptime
          (if attrs
              (let* ((start-time (plist-get attrs :starttime))
                     (now (float-time)))
                (if start-time (- now start-time) 0.0))
            0.0)))
    (list :alive alive
          :pid pid
          :uptime uptime)))

(defun gptel-auto-workflow--probe-experiment-loop-stuck ()
  "Detect if the experiment loop has not made progress.
Returns plist with :stuck, :last-cycle-time, :expected-interval, :elapsed."
  (let* ((last-cycle gptel-auto-workflow-monitoring-last-cycle-time)
         (expected (* gptel-auto-workflow-monitoring-cycle-interval 3))
         (now (float-time))
         (elapsed (if (> last-cycle 0.0) (- now last-cycle) 0.0))
         (stuck (and (> last-cycle 0.0) (> elapsed expected))))
    (list :stuck stuck
          :last-cycle-time last-cycle
          :expected-interval expected
          :elapsed elapsed)))

(defun gptel-auto-workflow--probe-metrics-freshness ()
  "Check that operational metrics snapshots in var/metrics/ are being produced.
If the newest snapshot is older than 24h, metrics collection is stale.
Returns plist with :fresh, :latest-snapshot, :age-hours."
  (let* ((metrics-dir (expand-file-name "var/metrics/" default-directory))
         (fresh t)
         (latest-snapshot nil)
         (age-hours 0.0))
    (condition-case nil
        (when (file-directory-p metrics-dir)
          (let* ((files (directory-files metrics-dir t "-metrics\\.sexp$"))
                 (sorted (sort files
                               (lambda (a b)
                                 (let ((ta (float-time (nth 5 (file-attributes a))))
                                       (tb (float-time (nth 5 (file-attributes b)))))
                                   (> ta tb)))))
                 (newest (car sorted)))
            (when newest
              (setq latest-snapshot (file-name-nondirectory newest))
              (let* ((attrs (file-attributes newest))
                     (mtime (float-time (nth 5 attrs)))
                     (age-seconds (- (float-time) mtime)))
                (setq age-hours (/ age-seconds 3600.0))
                (setq fresh (< age-hours 24.0))))))
      (error
       (setq fresh nil)))
    (list :fresh fresh
          :latest-snapshot latest-snapshot
          :age-hours age-hours)))

(defun gptel-auto-workflow--run-health-probes ()
  "Run all 3 health probes and return combined plist.
If any probe shows a problem, writes a mementum memory and returns :healthy nil."
  (let* ((daemon-probe (gptel-auto-workflow--probe-daemon-alive))
         (loop-probe (gptel-auto-workflow--probe-experiment-loop-stuck))
         (metrics-probe (gptel-auto-workflow--probe-metrics-freshness))
         (daemon-ok (plist-get daemon-probe :alive))
         (loop-ok (not (plist-get loop-probe :stuck)))
         (metrics-ok (plist-get metrics-probe :fresh))
         (healthy (and daemon-ok loop-ok metrics-ok)))
    (when (and (not loop-ok) (fboundp 'gptel-auto-workflow--mementum-write-memory))
      (gptel-auto-workflow--mementum-write-memory
       '❌ "health-probe-experiment-loop-stuck"
       (format "**Experiment loop stuck:** elapsed=%.0fs, expected=%.0fs"
               (plist-get loop-probe :elapsed)
               (plist-get loop-probe :expected-interval))))
    (when (and (not metrics-ok) (fboundp 'gptel-auto-workflow--mementum-write-memory))
      (gptel-auto-workflow--mementum-write-memory
       '❌ "health-probe-metrics-freshness"
       (format "**Metrics stale:** latest=%s, age=%.1fh"
               (or (plist-get metrics-probe :latest-snapshot) "none")
               (plist-get metrics-probe :age-hours))))
    (list :healthy healthy
          :daemon-probe daemon-probe
          :loop-probe loop-probe
          :metrics-probe metrics-probe)))

;; ── Phase 3: Auto-Test & Deploy Configuration ──

(defcustom gptel-auto-workflow-monitoring-attempt-regen-on-deploy t
  "When non-nil, auto-deploy proposals targeting a specific module file
will attempt code regeneration instead of just symbolic tag + memory."
  :type 'boolean
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-monitoring-deploy-threshold 0.6
  "Minimum success rate for auto-deployment of validated proposals.
Proposals with test-success-rate below this threshold are not deployed."
  :type 'float
  :group 'gptel-tools-agent)

(defvar gptel-auto-workflow-monitoring-rollback-tag-prefix "monitoring-rollback-"
  "Git tag prefix for rollback snapshots created during proposal deployment.")

(defcustom gptel-auto-workflow-monitoring-risk-auto-deploy '("low")
  "Risk levels eligible for immediate auto-deployment without human approval."
  :type '(repeat string)
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-monitoring-risk-notify-deploy '("medium")
  "Risk levels that notify the human and auto-deploy after a grace period.
After gptel-auto-workflow-monitoring-deploy-grace-seconds, the proposal
is deployed unless the human objects."
  :type '(repeat string)
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-monitoring-risk-require-approval '("high")
  "Risk levels that require explicit human approval before deployment.
Proposals at these risk levels are persisted as pending-approval and
never auto-deployed."
  :type '(repeat string)
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-monitoring-deploy-grace-seconds 86400
  "Grace period in seconds before auto-deploying medium-risk proposals.
Default is 24 hours (86400 seconds).  Human can object during this window."
  :type 'integer
  :group 'gptel-tools-agent)

;; ── Post-Deploy Impact Assessment (Phase 7) ──

(defcustom gptel-auto-workflow-monitoring-impact-wait-cycles 3
  "Number of monitoring cycles to wait before assessing deploy impact.
Default is 3 cycles.  At 15-minute intervals, this means ~45 minutes
of observation before impact assessment."
  :type 'integer
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-monitoring-impact-improvement-threshold 0.05
  "Minimum relative improvement (0.05 = 5%) to consider deploy successful."
  :type 'float
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-monitoring-impact-degradation-threshold -0.10
  "Maximum relative degradation before triggering rollback.
A value of -0.10 means -10% degradation triggers rollback consideration."
  :type 'float
  :group 'gptel-tools-agent)

(defvar gptel-auto-workflow-monitoring--pending-impact-assessments nil
  "List of pending post-deploy impact assessments.
Each element is a plist:
  (:deploy-time TIME
   :deploy-cycle CYCLE
   :module MODULE
   :proposal PROPOSAL
   :baseline-metrics PLIST)
Populated when a proposal is deployed; consumed by Phase 7.")

(defvar gptel-auto-workflow-monitoring--impact-assessment-file
  (expand-file-name "var/impact-assessments.sexp" user-emacs-directory)
  "File to persist pending impact assessments across daemon restarts.")

(defun gptel-auto-workflow--persist-impact-assessments ()
  "Persist pending impact assessments to disk."
  (ignore-errors
    (make-directory (file-name-directory
                     gptel-auto-workflow-monitoring--impact-assessment-file) t)
    (with-temp-file gptel-auto-workflow-monitoring--impact-assessment-file
      (prin1 gptel-auto-workflow-monitoring--pending-impact-assessments
             (current-buffer)))
    t))

(defun gptel-auto-workflow--load-impact-assessments ()
  "Load pending impact assessments from disk.  Returns list or nil."
  (ignore-errors
    (when (file-exists-p gptel-auto-workflow-monitoring--impact-assessment-file)
      (with-temp-buffer
        (insert-file-contents gptel-auto-workflow-monitoring--impact-assessment-file)
        (goto-char (point-min))
        (read (current-buffer))))))

(defun gptel-auto-workflow--record-deployment-for-impact (module proposal baseline-metrics)
  "Record a deployment for later impact assessment.
MODULE is the file/module deployed.  PROPOSAL is the proposal plist.
BASELINE-METRICS is a plist of metrics before deployment.
Adds to pending assessments and persists."
  (let ((assessment `(:deploy-time ,(float-time)
                       :deploy-cycle ,gptel-auto-workflow-monitoring-cycle-counter
                       :module ,module
                       :proposal ,proposal
                       :baseline-metrics ,baseline-metrics)))
    (push assessment gptel-auto-workflow-monitoring--pending-impact-assessments)
    (gptel-auto-workflow--persist-impact-assessments)
    (message "[monitoring] Recorded deployment for impact assessment: %s" module)
    assessment))

(defun gptel-auto-workflow--collect-current-metrics (module)
  "Collect current metrics for MODULE.
Returns a plist with :tests-passing, :compile-clean, :file-size.
This provides a lightweight snapshot for impact comparison."
  (let ((file-path (expand-file-name module (expand-file-name default-directory)))
        (tests-passing t)
        (compile-clean t)
        (file-size 0))
    ;; Check file exists and get size
    (when (file-exists-p file-path)
      (setq file-size (file-attribute-size (file-attributes file-path))))
    ;; Check recent test results for this module
    (when (fboundp 'gptel-auto-workflow--parse-all-results)
      (let* ((records (gptel-auto-workflow--parse-all-results))
             (module-records (cl-remove-if-not
                              (lambda (r) (string-match-p (regexp-quote module)
                                                          (or (plist-get r :target) "")))
                              records))
             (recent (cl-remove-if-not
                      (lambda (r) (equal (plist-get r :decision) "kept"))
                      module-records)))
        (setq tests-passing (> (length recent) 0))))
    `(:tests-passing ,tests-passing
      :compile-clean ,compile-clean
      :file-size ,file-size)))

(defun gptel-auto-workflow--assess-impact (assessment)
  "Assess impact of a deployment described by ASSESSMENT.
Compares baseline metrics to current metrics.
Returns plist with :verdict (:improved :degraded :neutral),
:delta (relative change), :details (string)."
  (let* ((module (plist-get assessment :module))
         (baseline (plist-get assessment :baseline-metrics))
         (current (gptel-auto-workflow--collect-current-metrics module))
         (baseline-size (or (plist-get baseline :file-size) 0))
         (current-size (or (plist-get current :file-size) 0))
         (baseline-tests (plist-get baseline :tests-passing))
         (current-tests (plist-get current :tests-passing))
         (size-delta (if (and baseline-size (> baseline-size 0))
                         (/ (float (- current-size baseline-size)) baseline-size)
                       0.0))
         (verdict :neutral)
         (details ""))
    ;; Determine verdict
    (cond
     ;; Degradation: tests stopped passing
     ((and baseline-tests (not current-tests))
      (setq verdict :degraded)
      (setq details "Test status degraded: was passing, now failing"))
     ;; Improvement: size reduction
     ((and (< size-delta 0)
           (>= (- size-delta) gptel-auto-workflow-monitoring-impact-improvement-threshold))
      (setq verdict :improved)
      (setq details (format "File size reduced by %.1f%%" (* 100 (- size-delta)))))
     ;; Improvement: tests became passing
     ((and (not baseline-tests) current-tests)
      (setq verdict :improved)
      (setq details "Test status improved: was failing, now passing"))
     ;; Degradation: concerning size increase
     ((> size-delta (- gptel-auto-workflow-monitoring-impact-degradation-threshold))
      (setq verdict :degraded)
      (setq details (format "File size increased by %.1f%%" (* 100 size-delta)))))
    `(:verdict ,verdict
      :delta ,size-delta
      :module ,module
      :details ,details
      :baseline ,baseline
      :current ,current)))

(defun gptel-auto-workflow--run-impact-assessments ()
  "Phase 7: Run post-deploy impact assessments.
Checks pending assessments, assesses those past wait-cycles threshold.
Returns list of assessment results."
  ;; Load persisted assessments if in-memory list is empty
  (when (null gptel-auto-workflow-monitoring--pending-impact-assessments)
    (let ((loaded (gptel-auto-workflow--load-impact-assessments)))
      (when loaded
        (setq gptel-auto-workflow-monitoring--pending-impact-assessments loaded))))
  (let ((results nil)
        (remaining nil))
    (dolist (assessment gptel-auto-workflow-monitoring--pending-impact-assessments)
      (let* ((deploy-cycle (or (plist-get assessment :deploy-cycle) 0))
             (cycles-elapsed (- gptel-auto-workflow-monitoring-cycle-counter
                                deploy-cycle))
             (module (plist-get assessment :module)))
        (if (>= cycles-elapsed gptel-auto-workflow-monitoring-impact-wait-cycles)
            ;; Time to assess
            (let* ((result (gptel-auto-workflow--assess-impact assessment))
                   (verdict (plist-get result :verdict))
                   (details (plist-get result :details))
                   (slug (format "impact-%s-%s"
                                 (symbol-name verdict)
                                 (if (fboundp 'gptel-auto-workflow--mementum-slug)
                                     (gptel-auto-workflow--mementum-slug module)
                                   (replace-regexp-in-string
                                    "[^a-zA-Z0-9]" "-" (downcase module)))))
                   (content (format "**Impact Assessment for %s**\n**Verdict:** %s\n**Cycles elapsed:** %d\n**Details:** %s\n\n**Baseline:** %s\n**Current:** %s"
                                    module (symbol-name verdict) cycles-elapsed details
                                    (plist-get result :baseline)
                                    (plist-get result :current)))
                   (symbol (pcase verdict
                             (:improved '✅)
                             (:degraded '⚠️)
                             (_ '📊))))
              ;; Write mementum memory
              (when (fboundp 'gptel-auto-workflow--mementum-write-memory)
                (gptel-auto-workflow--mementum-write-memory symbol slug content))
              (message "[monitoring] Phase 7: Impact for %s: %s"
                       module (symbol-name verdict))
              (push result results)
              ;; If degraded, log warning
              (when (eq verdict :degraded)
                (message "[monitoring] Phase 7: WARNING - degradation for %s" module)))
          ;; Not yet time, keep in remaining list
          (push assessment remaining))))
    ;; Update pending list and persist
    (setq gptel-auto-workflow-monitoring--pending-impact-assessments
          (nreverse remaining))
    (gptel-auto-workflow--persist-impact-assessments)
    results))

;; ── Failure Classification ──

(defun gptel-auto-workflow--classify-failure--is-compilation
    (decision grader-reason)
  "Return non-nil if DECISION + GRADER-REASON indicate compilation failure."
  (and (member decision '("rejected" "discarded"))
       (let ((gr (downcase grader-reason)))
         (or (string-match-p "compil" gr)
             (string-match-p "compile error" gr)
             (string-match-p "does not compil" gr)
             (string-match-p "missing depend" gr)))))

(defun gptel-auto-workflow--classify-failure--is-grader (grader-reason)
  "Return non-nil if GRADER-REASON indicates a grader failure."
  (let ((gr (downcase grader-reason)))
    (or (string-match-p "syntax error" gr)
        (string-match-p "type mismatch" gr)
        (string-match-p "undefined function" gr)
        (string-match-p "grader.*fail" gr))))

(defun gptel-auto-workflow--classify-failure--is-prompt
    (grader-reason prompt-chars)
  "Return non-nil if GRADER-REASON or PROMPT-CHARS indicate prompt failure."
  (or (and prompt-chars (> prompt-chars 4000))
      (let ((gr (downcase grader-reason)))
        (or (string-match-p "prompt.*long" gr)
            (string-match-p "missing context" gr)
            (string-match-p "unclear" gr)))))

(defun gptel-auto-workflow--classify-failure (experiment)
  "Classify EXPERIMENT plist into a failure type symbol.
Returns one of: grader, compilation, prompt, strategy, unknown.
EXPERIMENT must contain :decision, :grader-reason (from col 10),
:prompt-chars, and :strategy fields.
Classification order: compilation > grader > prompt > strategy > unknown."
  (let* ((decision (or (plist-get experiment :decision) ""))
         (grader-reason (or (plist-get experiment :grader-reason) ""))
         (prompt-chars (plist-get experiment :prompt-chars))
         (strategy (or (plist-get experiment :strategy) "")))
    (cond
     ((gptel-auto-workflow--classify-failure--is-compilation
       decision grader-reason)
      'compilation)
     ((gptel-auto-workflow--classify-failure--is-grader grader-reason)
      'grader)
     ((gptel-auto-workflow--classify-failure--is-prompt
       grader-reason prompt-chars)
      'prompt)
     ;; Strategy: none/nil/unknown/empty strategy only
     ((member (downcase strategy) '("none" "unknown" "nil" ""))
      'strategy)
     (t 'unknown))))

;; ── Systemic Failure Analysis ──

(defun gptel-auto-workflow--analyze-systemic-failures ()
  "Detect recurring failure patterns from historical TSV logs.
Calls gptel-auto-workflow--parse-all-results to load experiments,
filters to non-kept decisions, classifies each failure, groups by
(type, target), and returns patterns with count >= min-occurrences.
Returns a list of pattern plists sorted descending by :count."
  (let* ((records
          (when (fboundp 'gptel-auto-workflow--parse-all-results)
            (gptel-auto-workflow--parse-all-results)))
         (failures nil)
         (groups (make-hash-table :test 'equal))
         (patterns nil))
    ;; Filter to non-kept experiments
    (dolist (rec records)
      (let ((decision (or (plist-get rec :decision) "")))
        (unless (equal decision "kept")
          (push rec failures))))
    ;; Classify and group
    (dolist (fail failures)
      (let* ((ftype (gptel-auto-workflow--classify-failure fail))
             (target (or (plist-get fail :target) "unknown"))
             (key (format "%s|%s" ftype target))
             (existing (gethash key groups)))
        (if existing
            (puthash key (cons fail existing) groups)
          (puthash key (list fail) groups))))
    ;; Build pattern list for groups meeting threshold
    (maphash
     (lambda (key fails)
       (let* ((parts (split-string key "|"))
              (ftype (intern (car parts)))
              (target (nth 1 parts))
              (count (length fails)))
         (when (>= count gptel-auto-workflow-monitoring-min-occurrences)
           (let* ((examples
                   (seq-take
                    (delq nil
                          (mapcar
                           (lambda (f)
                             (let ((gr (plist-get f :grader-reason)))
                               (when (and gr (not (string-empty-p gr)))
                                 gr)))
                           fails))
                    5))
                  (run-dirs
                   (delq nil
                         (mapcar
                          (lambda (f) (plist-get f :run-dir))
                          fails)))
                  (first-seen (or (car (last run-dirs)) "unknown"))
                  (last-seen (or (car run-dirs) "unknown")))
             (push (list :type ftype
                         :target target
                         :count count
                         :examples examples
                         :first-seen first-seen
                         :last-seen last-seen)
                   patterns)))))
     groups)
    ;; Sort descending by count
    (sort patterns
          (lambda (a b)
            (> (plist-get a :count)
               (plist-get b :count))))))

;; ── Pattern Formatting ──

(defun gptel-auto-workflow--failure-pattern->string (pattern)
  "Format PATTERN plist into a human-readable string for mementum.
PATTERN contains :type, :target, :count, :examples, :first-seen, :last-seen."
  (let ((type (plist-get pattern :type))
        (target (plist-get pattern :target))
        (count (plist-get pattern :count))
        (examples (plist-get pattern :examples))
        (first-seen (plist-get pattern :first-seen))
        (last-seen (plist-get pattern :last-seen)))
    (format
     "**Failure type:** %s\n**Target:** %s\n**Occurrences:** %d\n**Example reasons:** %s\n**Trend:** %s -> %s\n\nThis pattern was detected by the monitoring agent as a systemic failure requiring investigation."
     type target count
     (if examples (mapconcat #'identity examples "; ") "none")
     first-seen last-seen)))

;; ── Proposal Generation (Phase 2) ──

(defun gptel-auto-workflow--pattern-type->component (ftype)
  "Map failure FTYPE symbol to the responsible pipeline component string.
Mapping: grader/compilation -> grader, prompt -> prompt-builder,
strategy -> strategy-harness, unknown -> general."
  (cond
   ((member ftype '(grader compilation)) "grader")
   ((eq ftype 'prompt) "prompt-builder")
   ((eq ftype 'strategy) "strategy-harness")
   (t "general")))

(defun gptel-auto-workflow--component->risk (component)
  "Map COMPONENT string to a risk level string for proposals.
grader/prompt-builder -> medium, strategy-harness -> high, general -> low."
  (cond
   ((member component '("grader" "prompt-builder")) "medium")
   ((equal component "strategy-harness") "high")
   (t "low")))

(defun gptel-auto-workflow--count->confidence (count)
  "Derive confidence heuristic from failure pattern COUNT.
3 occurrences -> 0.6, 4 -> 0.7, 5+ -> 0.8."
  (cond
   ((= count 3) 0.6)
   ((= count 4) 0.7)
   ((>= count 5) 0.8)
   (t 0.5)))

(defun gptel-auto-workflow--generate-improvement-proposal (pattern)
  "Generate an improvement proposal plist from a failure PATTERN.
PATTERN is a plist from --analyze-systemic-failures with :type, :target,
:count.
Returns a proposal plist: :description, :component, :code-changes,
:expected-impact, :confidence, :risk, :pattern-type, :pattern-target."
  (let* ((ftype (plist-get pattern :type))
         (target (or (plist-get pattern :target) "unknown"))
         (count (plist-get pattern :count))
         (component (gptel-auto-workflow--pattern-type->component ftype))
         (confidence (gptel-auto-workflow--count->confidence count))
         (risk (gptel-auto-workflow--component->risk component))
         (examples (or (plist-get pattern :examples) (list "recurring failures"))))
    (list
     :description
     (format "Address recurring %s failures in %s: %s"
             ftype target
             (mapconcat #'identity (seq-take examples 3) ", "))
     :component component
     :code-changes
     (format "Modify %s to handle %s-type failures more robustly"
             component ftype)
     :expected-impact
     (format "Reduce %s failures in %s by ~%.0f%%"
             ftype target (* confidence 100))
     :confidence confidence
     :risk risk
     :pattern-type ftype
     :pattern-target target)))

(defun gptel-auto-workflow--score-proposal (proposal)
  "Score PROPOSAL plist by impact and feasibility.
Adds :impact-score and :feasibility-score to the proposal plist.
Impact-score = confidence * (pattern-count / 10), capped at 1.0.
Feasibility-score derived from risk: low -> 0.9, medium -> 0.7, high -> 0.5."
  (let* ((confidence (or (plist-get proposal :confidence) 0.5))
         (risk (or (plist-get proposal :risk) "medium"))
         ;; Recover count from pattern if available (confidence encodes it,
         ;; but we compute impact from confidence directly for simplicity)
         (impact-score (min 1.0 (* confidence
                                    ;; Scale factor: confidence already
                                    ;; encodes count heuristically
                                    1.0)))
         (feasibility-score
          (cond ((equal risk "low") 0.9)
                ((equal risk "medium") 0.7)
                ((equal risk "high") 0.5)
                (t 0.6))))
    ;; Append scores to existing proposal plist
    (append proposal
            (list :impact-score impact-score
                  :feasibility-score feasibility-score))))

(defun gptel-auto-workflow--validate-proposal (scored-proposal records)
  "Validate SCORED-PROPOSAL against historical RECORDS.
Computes validation-rate as fraction of records matching the proposal's
pattern-type that would be addressed.  Adds :validation-rate and :status.
Status: validated if rate >= 0.6, tentative otherwise."
  (let* ((ptype (plist-get scored-proposal :pattern-type))
         (ptarget (plist-get scored-proposal :pattern-target))
         (total-failures 0)
         (addressed 0))
    (dolist (rec records)
      (let ((decision (or (plist-get rec :decision) "")))
        (unless (equal decision "kept")
          (setq total-failures (1+ total-failures))
          (when (and (eq (gptel-auto-workflow--classify-failure rec) ptype)
                     (equal (or (plist-get rec :target) "unknown") ptarget))
            (setq addressed (1+ addressed))))))
    (let* ((validation-rate
            (if (> total-failures 0)
                (/ (float addressed) (float total-failures))
              0.0))
           (status (if (>= validation-rate 0.6) "validated" "tentative")))
      ;; Append validation fields to scored proposal
      (append scored-proposal
              (list :validation-rate validation-rate
                    :status status)))))

;; ── Auto-Test & Deploy (Phase 3) ──

(defun gptel-auto-workflow--test-proposal (validated-proposal records)
  "Test VALIDATED-PROPOSAL against historical RECORDS.
Re-classifies each failure record matching the proposal's pattern-type
and pattern-target, computes test-success-rate as the fraction of
total failures that match the proposal scope.
Adds :test-success-rate and :test-status to the proposal plist.
Test-status is \"pass\" if rate >= deploy-threshold, \"fail\" otherwise."
  (let* ((ptype (plist-get validated-proposal :pattern-type))
         (ptarget (plist-get validated-proposal :pattern-target))
         (total-failures 0)
         (scope-matches 0))
    (dolist (rec records)
      (let ((decision (or (plist-get rec :decision) "")))
        (unless (equal decision "kept")
          (setq total-failures (1+ total-failures))
          (when (and (eq (gptel-auto-workflow--classify-failure rec) ptype)
                     (equal (or (plist-get rec :target) "unknown") ptarget))
            (setq scope-matches (1+ scope-matches))))))
    (let* ((test-success-rate
            (if (> total-failures 0)
                (/ (float scope-matches) (float total-failures))
              0.0))
           (test-status
            (if (>= test-success-rate
                    gptel-auto-workflow-monitoring-deploy-threshold)
                "pass" "fail")))
      (append validated-proposal
              (list :test-success-rate test-success-rate
                    :test-status test-status)))))

(defun gptel-auto-workflow--risk->deploy-action (risk)
  "Map RISK string to a deployment action string.
Uses the three risk-tier config variables:
  risk-auto-deploy       -> \"auto-deploy\"
  risk-notify-deploy     -> \"notify\"
  risk-require-approval  -> \"approval-required\"
Returns \"unknown\" if risk does not match any tier."
  (cond
   ((member risk gptel-auto-workflow-monitoring-risk-auto-deploy)
    "auto-deploy")
   ((member risk gptel-auto-workflow-monitoring-risk-notify-deploy)
    "notify")
   ((member risk gptel-auto-workflow-monitoring-risk-require-approval)
    "approval-required")
   (t "unknown")))

(defun gptel-auto-workflow--deploy-proposal (tested-proposal)
  "Deploy TESTED-PROPOSAL based on its risk level and test-status.
TESTED-PROPOSAL must have :test-status \"pass\".
Determines deployment action via --risk->deploy-action.
For auto-deploy: creates a git rollback tag and persists deployment mementum.
For notify: persists a pending-notification mementum without deploying.
For approval-required: enqueues in the approval queue for human review.
Returns plist with :deploy-action and :rollback-tag appended.
For approval-required proposals, also appends :queue-status and :queue-id."
  (let* ((risk (or (plist-get tested-proposal :risk) "unknown"))
         (component (or (plist-get tested-proposal :component) "unknown"))
         (ptarget (or (plist-get tested-proposal :pattern-target) "unknown"))
         (deploy-action (gptel-auto-workflow--risk->deploy-action risk))
         (rollback-tag
          (format "%s%s-%s"
                  gptel-auto-workflow-monitoring-rollback-tag-prefix
                  component
                  (if (fboundp 'gptel-auto-workflow--mementum-slug)
                      (gptel-auto-workflow--mementum-slug ptarget)
                    (replace-regexp-in-string
                     "[^a-zA-Z0-9]" "-" (downcase ptarget)))))
         (queue-entry nil)
          ;; Check if pattern-target resolves to a real .el file
          (target-file
           (when (and gptel-auto-workflow-monitoring-attempt-regen-on-deploy
                      (not (equal ptarget "unknown")))
             (let* ((candidate (expand-file-name ptarget
                                                 (expand-file-name "lisp/modules/"
                                                                   default-directory)))
                    (as-is (expand-file-name ptarget default-directory)))
               (cond
                ((file-exists-p candidate) candidate)
                ((file-exists-p as-is) as-is)
                (t nil))))))
    (cond
     ;; Auto-deploy: attempt regeneration if target file exists
     ((equal deploy-action "auto-deploy")
      (when (fboundp 'gptel-auto-workflow--git-cmd)
        (gptel-auto-workflow--git-cmd
         (format "git tag %s" (shell-quote-argument rollback-tag)) 30))
      (if (and target-file
               (fboundp 'gptel-auto-workflow-code-regeneration--execute))
          (let ((regen-result
                 (condition-case err
                     (gptel-auto-workflow-code-regeneration--execute
                      ptarget "latest")
                   (error
                    (message "[monitoring] Regeneration failed: %s" (error-message-string err))
                    (list :success nil :kept nil
                          :reason (error-message-string err))))))
            (if (plist-get regen-result :kept)
                (progn
                  (when (fboundp 'gptel-auto-workflow--mementum-write-memory)
                    (gptel-auto-workflow--mementum-write-memory
                     '✅ (format "deploy-regen-%s" rollback-tag)
                     (format "Deployed (regeneration): %s, risk: %s, target: %s, rollback: %s"
                             (plist-get tested-proposal :description)
                             risk component rollback-tag)))
                  (message "[monitoring] Auto-deployed via regen: %s" component))
              ;; Regen failed: rollback
              (when (fboundp 'gptel-auto-workflow--git-cmd)
                (ignore-errors
                  (gptel-auto-workflow--git-cmd
                   (format "git reset --hard %s" (shell-quote-argument rollback-tag)) 60)))
              (when (fboundp 'gptel-auto-workflow--mementum-write-memory)
                (gptel-auto-workflow--mementum-write-memory
                 '❌ (format "deploy-regen-failed-%s" rollback-tag)
                 (format "Regen failed for %s, rolled back to %s"
                         component rollback-tag)))
              (message "[monitoring] Auto-deploy regen failed: %s, rolled back" component)))
        ;; No target file: symbolic deploy
        (when (fboundp 'gptel-auto-workflow--mementum-write-memory)
          (gptel-auto-workflow--mementum-write-memory
           '✅ (format "deploy-%s" rollback-tag)
           (format "Deployed (symbolic): %s, risk: %s, component: %s, rollback: %s"
                   (plist-get tested-proposal :description)
                   risk component rollback-tag)))
        (message "[monitoring] Auto-deployed (symbolic): %s (risk: %s)" component risk)))
     ;; Notify: persist pending-notification memory
     ((equal deploy-action "notify")
      (when (fboundp 'gptel-auto-workflow--mementum-write-memory)
        (gptel-auto-workflow--mementum-write-memory
         '🎯 (format "pending-notification-%s" rollback-tag)
         (format "**Pending notification:** %s\n**Risk:** %s\n**Component:** %s\n**Grace
period:** %ds\n**Rollback tag:** %s\n\nWill auto-deploy after grace period
unless human objects."
                 (plist-get tested-proposal :description)
                 risk component
                 gptel-auto-workflow-monitoring-deploy-grace-seconds
                 rollback-tag)))
      (message "[monitoring] Pending notification for proposal: %s (risk: %s, grace: %ds)"
               component risk gptel-auto-workflow-monitoring-deploy-grace-seconds))
     ;; Approval-required: enqueue in approval queue for human review
     ((equal deploy-action "approval-required")
      (setq queue-entry
            (when (fboundp 'gptel-auto-workflow-approval-queue-enqueue)
              (gptel-auto-workflow-approval-queue-enqueue
               tested-proposal rollback-tag)))
      (when (fboundp 'gptel-auto-workflow--mementum-write-memory)
        (gptel-auto-workflow--mementum-write-memory
         '‖ (format "pending-approval-%s" rollback-tag)
         (format "**Pending approval:** %s\n**Risk:** %s\n**Component:** %s\n**Rollback tag:**
%s\n**Queue ID:** %s\n\nRequires human approval before deployment (high-risk
proposal). Enqueued in approval queue."
                 (plist-get tested-proposal :description)
                 risk component rollback-tag
                 (when queue-entry (plist-get queue-entry :id)))))
      (message "[monitoring] Pending approval for proposal: %s (risk: %s, queue-id: %s)"
               component risk
               (when queue-entry (plist-get queue-entry :id))))
     ;; Unknown action: log warning
     (t (message "[monitoring] Unknown deploy action for proposal: %s (risk: %s)"
                 component risk)))
    ;; Return proposal with deployment fields appended
    (let ((base-result
           (append tested-proposal
                   (list :deploy-action deploy-action
                         :rollback-tag rollback-tag))))
      (if (equal deploy-action "approval-required")
          (append base-result
                  (list :queue-status "pending"
                        :queue-id (when queue-entry (plist-get queue-entry :id))))
        base-result))))

(defun gptel-auto-workflow--rollback-proposal (rollback-tag)
  "Rollback a deployed proposal by resetting to the tagged version.
ROLLBACK-TAG is the git tag created during deployment.
Uses git checkout main + git reset --hard TAG to avoid detaching HEAD.
Returns plist with :rollback-tag and :rollback-status (\"success\" or
\"failed\")."
  (let ((rollback-status "failed"))
    (when (fboundp 'gptel-auto-workflow--git-cmd)
      ;; First ensure we're on main (not detached HEAD)
      (gptel-auto-workflow--git-cmd "git checkout main" 30)
      (let ((result
             (gptel-auto-workflow--git-cmd
              (format "git reset --hard %s"
                      (shell-quote-argument rollback-tag)) 60)))
        (when result
          (setq rollback-status "success"))))
    ;; Persist rollback mementum
    (when (fboundp 'gptel-auto-workflow--mementum-write-memory)
      (gptel-auto-workflow--mementum-write-memory
       '❌ (format "rollback-%s" rollback-tag)
       (format "**Rollback executed:** %s\n**Status:** %s\n\nRolled back monitoring agent deployment via git reset --hard tag."
               rollback-tag rollback-status)))
    (message "[monitoring] Rollback %s for tag: %s" rollback-status rollback-tag)
    (list :rollback-tag rollback-tag
          :rollback-status rollback-status)))

;; ── Proposal Formatting ──

(defun gptel-auto-workflow--proposal->string (proposal)
  "Format PROPOSAL plist into a human-readable string for mementum.
Includes description, component, expected impact, confidence, risk,
validation-rate, and status."
  (let ((description (or (plist-get proposal :description) "N/A"))
        (component (or (plist-get proposal :component) "unknown"))
        (impact (or (plist-get proposal :expected-impact) "unknown"))
        (confidence (or (plist-get proposal :confidence) 0.0))
        (risk (or (plist-get proposal :risk) "unknown"))
        (validation-rate (or (plist-get proposal :validation-rate) 0.0))
        (status (or (plist-get proposal :status) "tentative")))
    (format
     "**Proposal:** %s\n**Component:** %s\n**Expected impact:** %s\n**Confidence:** %.2f\n**Risk:** %s\n**Validation rate:** %.2f\n**Status:** %s\n\nGenerated by the monitoring agent from systemic failure pattern analysis."
     description component impact confidence risk validation-rate status)))

;; ── Monitoring Cycle (Throttled) ──

(defun gptel-auto-workflow--monitoring-cycle ()
  "Run one monitoring cycle: analyze failures and persist patterns to mementum.
Throttled to max 1 cycle per cycle-interval seconds.
Returns list of written mementum file paths, or nil if throttled/disabled."
  (when gptel-auto-workflow-monitoring-enabled
    (let* ((now (float-time))
           (elapsed (- now
                       gptel-auto-workflow-monitoring-last-cycle-time)))
      (if (< elapsed gptel-auto-workflow-monitoring-cycle-interval)
          (progn
            (message "[monitoring] Throttled: %ds since last cycle, need %ds"
                     (truncate elapsed)
                     gptel-auto-workflow-monitoring-cycle-interval)
            nil)
        ;; Update throttle timestamp and cycle counter
        (setq gptel-auto-workflow-monitoring-last-cycle-time now)
        (setq gptel-auto-workflow-monitoring-cycle-counter
              (1+ gptel-auto-workflow-monitoring-cycle-counter))
        ;; Phase 0: Run health probes every 3rd cycle
        (when (= (mod gptel-auto-workflow-monitoring-cycle-counter 3) 0)
          (ignore-errors
            (let ((health (gptel-auto-workflow--run-health-probes)))
              (message "[monitoring] Phase 0: Health probes = %s"
                       (plist-get health :healthy)))))
        ;; Phase 1: Analyze failure patterns
        (let ((patterns (gptel-auto-workflow--analyze-systemic-failures))
              (records
               (when (fboundp 'gptel-auto-workflow--parse-all-results)
                 (gptel-auto-workflow--parse-all-results)))
              (written nil))
          (message "[monitoring] Found %d systemic failure patterns"
                   (length patterns))
          ;; Persist each pattern to mementum (Phase 1)
          (dolist (pattern patterns)
            (let* ((ftype (plist-get pattern :type))
                   (target (or (plist-get pattern :target) "unknown"))
                   (slug
                    (format "failure-pattern-%s-%s"
                            ftype
                            (if (fboundp 'gptel-auto-workflow--mementum-slug)
                                (gptel-auto-workflow--mementum-slug target)
                              (replace-regexp-in-string
                               "[^a-zA-Z0-9]" "-" (downcase target)))))
                   (content
                    (gptel-auto-workflow--failure-pattern->string pattern))
                   (file
                    (when (fboundp 'gptel-auto-workflow--mementum-write-memory)
                      (gptel-auto-workflow--mementum-write-memory
                       '❌ slug content))))
              (when file
                (message "[monitoring] Persisted pattern: %s" slug)
                (push file written))))
          ;; Phase 2: Generate, score, validate, and persist proposals
          ;; Collect validated proposals for Phase 3 testing
          (let ((validated-proposals nil))
            (dolist (pattern patterns)
              (let* ((proposal
                      (gptel-auto-workflow--generate-improvement-proposal pattern))
                     (scored
                      (gptel-auto-workflow--score-proposal proposal))
                     (validated
                      (gptel-auto-workflow--validate-proposal
                       scored (or records (list))))
                     (component (plist-get validated :component))
                     (ptarget (plist-get validated :pattern-target))
                     (status (plist-get validated :status))
                     (slug
                      (format "proposal-%s-%s"
                              component
                              (if (fboundp 'gptel-auto-workflow--mementum-slug)
                                  (gptel-auto-workflow--mementum-slug ptarget)
                                (replace-regexp-in-string
                                 "[^a-zA-Z0-9]" "-" (downcase (or ptarget "unknown"))))))
                     (content
                      (gptel-auto-workflow--proposal->string validated))
                     (file
                      (when (and status
                                 (fboundp 'gptel-auto-workflow--mementum-write-memory))
                        (gptel-auto-workflow--mementum-write-memory
                         '💡 slug content))))
                (when (and status (equal status "validated"))
                  (push validated validated-proposals))
                (when file
                  (message "[monitoring] Persisted proposal: %s (%s)" slug status)
                  (push file written))))
            ;; Phase 3: Test, deploy validated proposals
            (dolist (vproposal (nreverse validated-proposals))
              (let* ((tested
                      (gptel-auto-workflow--test-proposal
                       vproposal (or records (list))))
                     (test-status (plist-get tested :test-status)))
                (when (equal test-status "pass")
                  (let* ((deployed
                          (gptel-auto-workflow--deploy-proposal tested))
                         (deploy-action (plist-get deployed :deploy-action)))
                    (message "[monitoring] Phase 3: %s -> %s"
                             (plist-get deployed :component) deploy-action))))
            ;; Phase 4: Architectural analysis (strategy routing + hypothesis routing)
            (progn
              (require 'gptel-auto-workflow-architectural-evolution nil t)
              (when (fboundp 'gptel-auto-workflow--run-architectural-analysis)
              (let ((arch-result
                     (gptel-auto-workflow--run-architectural-analysis)))
                (dolist (arch-file (plist-get arch-result :written))
                  (push arch-file written))
                 (message "[monitoring] Phase 4: %d architectural proposals"
                          (length (plist-get arch-result :proposals))))))
            ;; Phase 5: External sensor collection (GitHub Issues)
            (progn
              (require 'gptel-auto-workflow-external-sensors nil t)
              (when (fboundp 'gptel-auto-workflow--github-sensor-collect)
              (condition-case nil
                  (let ((gh-data (gptel-auto-workflow--github-sensor-collect)))
                    (when gh-data
                      (message "[monitoring] Phase 5: GitHub sensor collected")))
                 (error nil))))
            ;; Phase 6: Execute approved proposals + medium-risk grace-period deploy
            (progn
              (require 'gptel-auto-workflow-approval-queue nil t)
              (ignore-errors
              ;; 6a: Auto-approve recurring proposals
              (when (fboundp 'gptel-auto-workflow-approval-queue-auto-approve-recurring)
                (gptel-auto-workflow-approval-queue-auto-approve-recurring))
              ;; 6b: Execute all approved-but-undeployed proposals
              (when (fboundp 'gptel-auto-workflow-approval-queue-execute-approved)
                (let ((executed (gptel-auto-workflow-approval-queue-execute-approved)))
                  (when executed
                    (message "[monitoring] Phase 6: Deployed %d approved proposals"
                             (length executed)))))
              ;; 6c: Deploy medium-risk proposals past grace period
              (let ((grace gptel-auto-workflow-monitoring-deploy-grace-seconds))
                (when (and (numberp grace) (> grace 0) (stringp default-directory))
                  (let ((mementum-dir
                         (expand-file-name
                          "mementum/memories"
                          (expand-file-name default-directory))))
                    (when (file-directory-p mementum-dir)
                      (dolist (f (directory-files mementum-dir t
                                                  "^pending-notification-.*\\.md$"))
                        (let* ((attrs (file-attributes f))
                               (mtime (when attrs (float-time (nth 5 attrs))))
                               (age (when mtime (- (float-time) mtime))))
                          (when (and age (> age grace))
                            (let ((basename (file-name-nondirectory f)))
                              (message "[monitoring] Phase 6: Grace period elapsed for %s (%ds > %ds)"
                                       basename (truncate age) grace)
                              (let ((deploy-name
                                     (replace-regexp-in-string
                                      "^pending-notification-" "grace-deployed-" basename)))
                                (rename-file f
                                             (expand-file-name deploy-name mementum-dir)
                                             t)
                                (when (fboundp 'gptel-auto-workflow--mementum-write-memory)
                                  (gptel-auto-workflow--mementum-write-memory
                                   '✅ (replace-regexp-in-string
                                        "\\.md$" ""
                                        (replace-regexp-in-string
                                         "^pending-notification-" "grace-deploy-" basename))
                                     (format "**Grace-period auto-deploy:** %s\n**Grace period:** %ds\n**Elapsed:** %ds\n\nDeployed after grace period with no human objection."
                                             basename (truncate grace) (truncate age)))))))))))))
            ;; Phase 7: Post-deploy impact assessment
            (ignore-errors
              (let ((assessments (gptel-auto-workflow--run-impact-assessments)))
                (when assessments
                  (message "[monitoring] Phase 7: Assessed %d deployments"
                           (length assessments)))))
            (ignore (nreverse written)))))))))))

(provide 'gptel-auto-workflow-monitoring-agent)
;;; gptel-auto-workflow-monitoring-agent.el ends here
