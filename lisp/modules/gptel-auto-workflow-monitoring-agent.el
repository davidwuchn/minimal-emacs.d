;;; gptel-auto-workflow-monitoring-agent.el --- Failure pattern analysis for self-evolution -*- lexical-binding: t -*-

;; Copyright (C) 2026 OV5 Self-Improving Architecture

;; Author: OV5 System
;; Keywords: automation, monitoring, failure-patterns, meta-improvement

;;; Commentary:

;; Monitoring agent Phase 1: failure pattern analysis.
;; Parses TSV experiment logs, detects recurring failures, classifies by type,
;; and persists patterns to mementum for downstream proposal generation.
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
        ;; Analyze
        (let ((patterns (gptel-auto-workflow--analyze-systemic-failures))
              (written nil))
          (message "[monitoring] Found %d systemic failure patterns"
                   (length patterns))
          ;; Persist each pattern to mementum
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
          (nreverse written))))))

(provide 'gptel-auto-workflow-monitoring-agent)
;;; gptel-auto-workflow-monitoring-agent.el ends here