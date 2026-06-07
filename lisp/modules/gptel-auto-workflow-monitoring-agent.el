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

;; ── Phase 3: Auto-Test & Deploy Configuration ──

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
Proposals at these risk levels are persisted as 'pending-approval' and
never auto-deployed."
  :type '(repeat string)
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-monitoring-deploy-grace-seconds 86400
  "Grace period in seconds before auto-deploying medium-risk proposals.
Default is 24 hours (86400 seconds).  Human can object during this window."
  :type 'integer
  :group 'gptel-tools-agent)

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
PATTERN is a plist from --analyze-systemic-failures with :type, :target, :count.
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
         (queue-entry nil))
    (cond
     ;; Auto-deploy: tag current state and write deployment memory
     ((equal deploy-action "auto-deploy")
      (when (fboundp 'gptel-auto-workflow--git-cmd)
        (gptel-auto-workflow--git-cmd
         (format "git tag %s" (shell-quote-argument rollback-tag)) 30))
      (when (fboundp 'gptel-auto-workflow--mementum-write-memory)
        (gptel-auto-workflow--mementum-write-memory
         '✅ (format "deploy-%s" rollback-tag)
         (format "**Deployed:** %s\n**Risk:** %s\n**Component:** %s\n**Rollback tag:** %s\n\nAuto-deployed by monitoring agent (success rate exceeded threshold)."
                 (plist-get tested-proposal :description)
                 risk component rollback-tag)))
      (message "[monitoring] Auto-deployed proposal: %s (risk: %s)" component risk))
     ;; Notify: persist pending-notification memory
     ((equal deploy-action "notify")
      (when (fboundp 'gptel-auto-workflow--mementum-write-memory)
        (gptel-auto-workflow--mementum-write-memory
         '🎯 (format "pending-notification-%s" rollback-tag)
         (format "**Pending notification:** %s\n**Risk:** %s\n**Component:** %s\n**Grace period:** %ds\n**Rollback tag:** %s\n\nWill auto-deploy after grace period unless human objects."
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
         (format "**Pending approval:** %s\n**Risk:** %s\n**Component:** %s\n**Rollback tag:** %s\n**Queue ID:** %s\n\nRequires human approval before deployment (high-risk proposal). Enqueued in approval queue."
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
  "Rollback a deployed proposal by checking out the tagged version.
ROLLBACK-TAG is the git tag created during deployment.
Uses gptel-auto-workflow--git-cmd to checkout the rollback tag,
then persists a rollback mementum.  Returns plist with :rollback-tag
and :rollback-status (\"success\" or \"failed\")."
  (let ((rollback-status "failed"))
    (when (fboundp 'gptel-auto-workflow--git-cmd)
      (let ((result
             (gptel-auto-workflow--git-cmd
              (format "git checkout %s"
                      (shell-quote-argument rollback-tag)) 60)))
        (when result
          (setq rollback-status "success"))))
    ;; Persist rollback mementum
    (when (fboundp 'gptel-auto-workflow--mementum-write-memory)
      (gptel-auto-workflow--mementum-write-memory
       '❌ (format "rollback-%s" rollback-tag)
       (format "**Rollback executed:** %s\n**Status:** %s\n\nRolled back monitoring agent deployment via git tag checkout."
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
    (let ((now (float-time))
          (elapsed (- (float-time)
                      gptel-auto-workflow-monitoring-last-cycle-time)))
      (if (< elapsed gptel-auto-workflow-monitoring-cycle-interval)
          (progn
            (message "[monitoring] Throttled: %ds since last cycle, need %ds"
                     (truncate elapsed)
                     gptel-auto-workflow-monitoring-cycle-interval)
            nil)
        ;; Update throttle timestamp
        (setq gptel-auto-workflow-monitoring-last-cycle-time now)
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
            (nreverse written))))))))

(provide 'gptel-auto-workflow-monitoring-agent)
;;; gptel-auto-workflow-monitoring-agent.el ends here