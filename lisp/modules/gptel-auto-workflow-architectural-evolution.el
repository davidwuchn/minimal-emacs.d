;;; gptel-auto-workflow-architectural-evolution.el --- Architectural-level pattern analysis and proposal generation -*- lexical-binding: t -*-

;; Copyright (C) 2026 OV5 Self-Improving Architecture

;; Author: OV5 System
;; Keywords: architecture, evolution, strategy-routing, module-analysis

;;; Commentary:

;; Architectural evolution extends the monitoring agent with higher-level
;; pattern analysis: strategy routing effectiveness, module-level change
;; patterns, and structural proposals (module add/remove/split).
;;
;; Risk classification for architectural proposals:
;;   investigation    -> auto-deploy (low risk, informational)
;;   routing-change   -> notify (medium risk, affects strategy selection)
;;   module-remove/add/split -> required (high risk, structural changes)
;;
;; Uses :research-strategy field from --parse-all-results records.
;; Uses --categorize-hypothesis for strategy routing analysis.
;; Does NOT require gptel-auto-workflow-evolution at load time;
;; uses declare-function and fboundp guards for all cross-module calls.
;; Adds legacy keys (:confidence :risk :component) so existing
;; --score-proposal from monitoring-agent can process architectural proposals.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

;; ── Cross-module declarations (NOT require at load time) ──

(declare-function gptel-auto-workflow--parse-all-results
                  "gptel-auto-workflow-evolution")
(declare-function gptel-auto-workflow--categorize-hypothesis
                  "gptel-auto-workflow-evolution")
(declare-function gptel-auto-workflow--score-proposal
                  "gptel-auto-workflow-monitoring-agent")
(declare-function gptel-auto-workflow--mementum-write-memory
                  "gptel-auto-workflow-mementum")
(declare-function gptel-auto-workflow--mementum-slug
                  "gptel-auto-workflow-mementum")

;; ── Configuration ──

(defcustom gptel-auto-workflow-architectural-min-occurrences 3
  "Minimum occurrences of a strategy-routing pattern before proposing changes.
Requires 3+ occurrences to reduce noise from one-off anomalies."
  :type 'integer
  :group 'gptel-tools-agent)

(defcustom gptel-auto-workflow-architectural-routing-success-threshold 0.4
  "Success rate threshold below which a strategy is considered ineffective.
Strategies with kept-rate below this threshold trigger routing-change proposals."
  :type 'float
  :group 'gptel-tools-agent)

;; ── Architectural Risk Classification ──

(defun gptel-auto-workflow--architectural-risk-classify (change-type)
  "Classify CHANGE-TYPE symbol into a risk level string.
Mapping: investigation -> low, routing-change -> medium,
module-remove/add/split -> high.
Returns risk level string compatible with monitoring-agent deploy tiers."
  (cond
   ((eq change-type 'investigation) "low")
   ((eq change-type 'routing-change) "medium")
   ((memq change-type '(module-remove module-add module-split)) "high")
   (t "medium")))

(defun gptel-auto-workflow--architectural-risk->deploy-action (risk)
  "Map RISK string to deployment action for architectural proposals.
investigation (low) -> auto-deploy, routing-change (medium) -> notify,
structural (high) -> approval-required.
Reuses monitoring-agent risk tier logic."
  (cond
   ((equal risk "low") "auto-deploy")
   ((equal risk "medium") "notify")
   ((equal risk "high") "approval-required")
   (t "unknown")))

;; ── Strategy Routing Analysis ──

(defun gptel-auto-workflow--analyze-strategy-routing (records)
  "Analyze strategy routing effectiveness from RECORDS.
Groups experiments by :research-strategy, computes kept-rate per strategy.
Returns list of strategy-group plists sorted by kept-rate (worst first).
Each plist has: :strategy, :total, :kept, :kept-rate, :targets."
  (let ((groups (make-hash-table :test 'equal)))
    (dolist (rec records)
      (let* ((strategy (or (plist-get rec :research-strategy) "none"))
             (decision (or (plist-get rec :decision) ""))
             (target (or (plist-get rec :target) "unknown"))
             (existing (gethash strategy groups)))
        (if existing
            (puthash strategy
                     (list :total (1+ (plist-get existing :total))
                           :kept (+ (plist-get existing :kept)
                                    (if (equal decision "kept") 1 0))
                           :targets (cons target (plist-get existing :targets)))
                     groups)
          (puthash strategy
                   (list :total 1
                         :kept (if (equal decision "kept") 1 0)
                         :targets (list target))
                   groups))))
    ;; Build sorted list: worst kept-rate first (candidates for improvement)
    (let ((result nil))
      (maphash
       (lambda (strategy data)
         (let ((total (plist-get data :total))
               (kept (plist-get data :kept))
               (targets (plist-get data :targets)))
           (when (>= total gptel-auto-workflow-architectural-min-occurrences)
             (push (list :strategy strategy
                         :total total
                         :kept kept
                         :kept-rate (if (> total 0) (/ (float kept) total) 0.0)
                         :targets targets)
                   result))))
       groups)
      (sort result
            (lambda (a b)
              (< (plist-get a :kept-rate)
                 (plist-get b :kept-rate)))))))

;; ── Hypothesis Category Routing Analysis ──

(defun gptel-auto-workflow--analyze-hypothesis-routing (records)
  "Analyze hypothesis category routing from RECORDS.
Uses --categorize-hypothesis to classify each hypothesis, then groups by
category and research-strategy, computing kept-rate per combination.
Returns list of routing-group plists sorted by kept-rate worst first.
Each plist: :category, :strategy, :total, :kept, :kept-rate, :change-type."
  (let ((groups (make-hash-table :test 'equal)))
    (dolist (rec records)
      (let* ((hypothesis (or (plist-get rec :hypothesis) ""))
             (strategy (or (plist-get rec :research-strategy) "none"))
             (decision (or (plist-get rec :decision) ""))
             (category
              (if (fboundp 'gptel-auto-workflow--categorize-hypothesis)
                  (gptel-auto-workflow--categorize-hypothesis hypothesis)
                'other))
             (key (format "%s|%s" category strategy))
             (existing (gethash key groups)))
        (if existing
            (puthash key
                     (list :total (1+ (plist-get existing :total))
                           :kept (+ (plist-get existing :kept)
                                    (if (equal decision "kept") 1 0))
                           :category category
                           :strategy strategy)
                     groups)
          (puthash key
                   (list :total 1
                         :kept (if (equal decision "kept") 1 0)
                         :category category
                         :strategy strategy)
                   groups))))
    (let ((result nil))
      (maphash
       (lambda (_key data)
         (let ((total (plist-get data :total))
               (kept (plist-get data :kept))
               (category (plist-get data :category))
               (strategy (plist-get data :strategy)))
           (when (>= total gptel-auto-workflow-architectural-min-occurrences)
             (let ((kept-rate
                    (if (> total 0) (/ (float kept) total) 0.0)))
               (push (list :category category
                           :strategy strategy
                           :total total
                           :kept kept
                           :kept-rate kept-rate
                           :change-type
                           (cond
                            ((and (< kept-rate
                                     gptel-auto-workflow-architectural-routing-success-threshold)
                                  (not (member strategy '("none" "unknown" ""))))
                             'routing-change)
                            ((< kept-rate 0.5) 'investigation)
                            (t nil)))
                     result)))))
       groups)
      (let ((filtered
             (delq nil
                   (mapcar
                    (lambda (r)
                      (if (plist-get r :change-type) r nil))
                    result))))
        (sort filtered
              (lambda (a b)
                (< (plist-get a :kept-rate)
                   (plist-get b :kept-rate))))))))

;; ── Architectural Proposal Generation ──

(defun gptel-auto-workflow--generate-architectural-proposal (routing-group)
  "Generate an architectural proposal plist from ROUTING-GROUP.
ROUTING-GROUP has :category, :strategy, :total, :kept, :kept-rate, :change-type.
Adds legacy keys (:confidence :risk :component) so --score-proposal can process it.
Returns proposal plist compatible with monitoring-agent pipeline."
  (let* ((category (plist-get routing-group :category))
         (strategy (plist-get routing-group :strategy))
         (total (plist-get routing-group :total))
         (kept (plist-get routing-group :kept))
         (kept-rate (plist-get routing-group :kept-rate))
         (change-type (plist-get routing-group :change-type))
         (risk (gptel-auto-workflow--architectural-risk-classify change-type))
         (confidence (cond ((<= total 5) 0.5)
                           ((<= total 10) 0.6)
                           (t 0.7)))
         (component "architectural-analysis"))
    (list :description
          (format "Architectural: %s category with %s strategy has %.0f%% success (%d/%d kept)"
                  category strategy (* 100 kept-rate) kept total)
          :component component
          :code-changes
          (format "Adjust strategy routing for %s category away from %s strategy"
                  category strategy)
          :expected-impact
          (format "Improve %s category success rate from %.0f%% to >50%%"
                  category (* 100 kept-rate))
          :confidence confidence
          :risk risk
          :component component
          :change-type change-type
          :category category
          :affected-strategy strategy
          :kept-rate kept-rate)))

;; ── Slug Helper ──

(defun gptel-auto-workflow--architectural-slug (change-type identifier)
  "Generate a mementum slug for an architectural proposal.
CHANGE-TYPE is a symbol (routing-change, investigation, etc).
IDENTIFIER is a string describing the target (strategy name, category+strategy).
Uses mementum-slug when available, falls back to manual sanitization."
  (format "architectural-%s-%s"
          change-type
          (if (fboundp 'gptel-auto-workflow--mementum-slug)
              (gptel-auto-workflow--mementum-slug identifier)
            (let* ((clean (replace-regexp-in-string
                           "[^a-zA-Z0-9]" "-" (or identifier "")))
                   (collapsed (replace-regexp-in-string "-+" "-" clean)))
              (downcase (string-trim collapsed "-"))))))

;; ── Proposal Formatting ──

(defun gptel-auto-workflow--architectural-proposal->string (proposal)
  "Format PROPOSAL plist into a human-readable string for mementum.
Includes change-type, affected strategy, category, confidence, risk, and impact."
  (let ((description (or (plist-get proposal :description) "N/A"))
        (component (or (plist-get proposal :component) "unknown"))
        (change-type (or (plist-get proposal :change-type) "unknown"))
        (affected-strategy (or (plist-get proposal :affected-strategy) "unknown"))
        (category (or (plist-get proposal :category) "unknown"))
        (confidence (or (plist-get proposal :confidence) 0.0))
        (risk (or (plist-get proposal :risk) "unknown"))
        (impact (or (plist-get proposal :expected-impact) "unknown"))
        (kept-rate (or (plist-get proposal :kept-rate) 0.0))
        (impact-score (or (plist-get proposal :impact-score) 0.0))
        (feasibility-score (or (plist-get proposal :feasibility-score) 0.0)))
    (format
     "**Architectural proposal:** %s\n**Change type:** %s\n**Component:** %s\n**Affected strategy:** %s\n**Category:** %s\n**Current kept-rate:** %.0f%%\n**Confidence:** %.2f\n**Risk:** %s\n**Expected impact:** %s\n**Impact score:** %.2f\n**Feasibility score:** %.2f\n\nGenerated by architectural evolution from strategy routing analysis."
     description change-type component affected-strategy category
     (* 100 kept-rate) confidence risk impact impact-score feasibility-score)))

;; ── Architectural Analysis Entry Point ──

(defun gptel-auto-workflow--run-architectural-analysis ()
  "Run architectural pattern analysis and generate proposals.
Loads experiment records via --parse-all-results, analyzes strategy routing
and hypothesis routing, generates proposals with legacy keys for
--score-proposal compatibility.
Returns plist with :proposals (list of scored proposal plists) and
:written (list of mementum file paths from persisted proposals)."
  (let* ((records
          (when (fboundp 'gptel-auto-workflow--parse-all-results)
            (gptel-auto-workflow--parse-all-results)))
         (raw-proposals nil)
         (scored-proposals nil)
         (written nil))
    (when (and records (> (length records) 0))
      ;; Phase A: Strategy routing analysis
      (let ((routing-patterns
             (gptel-auto-workflow--analyze-strategy-routing records)))
        (dolist (pattern routing-patterns)
          (when (< (plist-get pattern :kept-rate)
                   gptel-auto-workflow-architectural-routing-success-threshold)
            (let* ((strategy (plist-get pattern :strategy))
                   (total (plist-get pattern :total))
                   (kept (plist-get pattern :kept))
                   (kept-rate (plist-get pattern :kept-rate))
                   (proposal
                    (list :description
                          (format "Strategy routing: %s strategy has %.0f%% success (%d/%d)"
                                  strategy (* 100 kept-rate) kept total)
                          :component "strategy-router"
                          :code-changes
                          (format "Reduce %s strategy allocation or improve its prompt"
                                  strategy)
                          :expected-impact
                          (format "Improve %s strategy success from %.0f%% to >50%%"
                                  strategy (* 100 kept-rate))
                          :confidence (cond ((<= total 5) 0.5)
                                            ((<= total 10) 0.6)
                                            (t 0.7))
                          :risk "medium"
                          :component "strategy-router"
                          :change-type 'routing-change
                          :affected-strategy strategy
                          :kept-rate kept-rate)))
              (push proposal raw-proposals)))))
      ;; Phase B: Hypothesis category routing
      (let ((hypo-routing
             (gptel-auto-workflow--analyze-hypothesis-routing records)))
        (dolist (group hypo-routing)
          (let* ((proposal
                  (gptel-auto-workflow--generate-architectural-proposal group))
                 (change-type (plist-get proposal :change-type)))
            (when change-type
              (push proposal raw-proposals)))))
      ;; Phase C: Score all proposals and persist to mementum
      (dolist (proposal (nreverse raw-proposals))
        (let* ((scored
                (if (fboundp 'gptel-auto-workflow--score-proposal)
                    (gptel-auto-workflow--score-proposal proposal)
                  proposal))
               (change-type (plist-get scored :change-type))
               (identifier
                (if (plist-get scored :affected-strategy)
                    (format "%s-%s"
                            (or (plist-get scored :category) "unknown")
                            (plist-get scored :affected-strategy))
                  "unknown"))
               (slug
                (gptel-auto-workflow--architectural-slug change-type identifier))
               (content
                (gptel-auto-workflow--architectural-proposal->string scored))
               (file
                (when (fboundp 'gptel-auto-workflow--mementum-write-memory)
                  (gptel-auto-workflow--mementum-write-memory
                   '💡 slug content))))
          (push scored scored-proposals)
          (when file
            (push file written)))))
    (list :proposals (nreverse scored-proposals)
          :written (nreverse written))))

(provide 'gptel-auto-workflow-architectural-evolution)
;;; gptel-auto-workflow-architectural-evolution.el ends here