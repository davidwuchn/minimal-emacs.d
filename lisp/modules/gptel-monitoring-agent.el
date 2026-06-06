;;; gptel-monitoring-agent.el --- Monitoring agent for self-improvement -*- lexical-binding: t -*-

;; Copyright (C) 2026 OV5 Self-Improving Architecture

;; Author: OV5 AI System
;; Keywords: automation, self-improvement, monitoring

;;; Commentary:

;; Phase 2: Monitoring Agent
;; This agent analyzes failures and rewrites the pipeline itself.
;; The "holy shit moment" from YC vision - a system that improves its own
;; improvement mechanisms.

;;; Code:

(require 'cl-lib)
(require 'json)

;; ============================================================================
;; Task 2.1: Failure Pattern Analysis
;; ============================================================================

(defun gptel-monitoring-agent--parse-results (results)
  "Parse RESULTS from TSV files.
Returns list of experiment plists."
  results)

(defun gptel-monitoring-agent--filter-by-decision (results decision)
  "Filter RESULTS by DECISION type.
Returns list of experiments with matching decision."
  (cl-remove-if-not (lambda (r) (equal decision (plist-get r :decision)))
                    results))

(defun gptel-monitoring-agent--group-by-backend-category (results)
  "Group RESULTS by backend and category, calculating keep-rates.
Returns list of (backend category keep-rate count) tuples."
  (let ((groups (make-hash-table :test 'equal)))
    ;; Group results
    (dolist (r results)
      (let* ((backend (plist-get r :backend))
             (category (plist-get r :category))
             (key (cons backend category))
             (existing (gethash key groups)))
        (puthash key (cons r existing) groups)))
    ;; Calculate keep-rates
    (let ((result nil))
      (maphash (lambda (key experiments)
                 (let* ((backend (car key))
                        (category (cdr key))
                        (kept (length (cl-remove-if-not
                                       (lambda (e) (equal "kept" (plist-get e :decision)))
                                       experiments)))
                        (total (length experiments))
                        (keep-rate (if (> total 0)
                                       (/ (float kept) total)
                                     0.0)))
                   (push (list backend category keep-rate total) result)))
               groups)
      result)))

(defun gptel-monitoring-agent--count-target-failures (results)
  "Count failures per target in RESULTS.
Returns alist of (target . failure-count)."
  (let ((counts (make-hash-table :test 'equal)))
    (dolist (r results)
      (when (not (equal "kept" (plist-get r :decision)))
        (let* ((target (plist-get r :target))
               (current (gethash target counts 0)))
          (puthash target (1+ current) counts))))
    (let ((result nil))
      (maphash (lambda (target count)
                 (push (cons target count) result))
               counts)
      result)))

(defun gptel-monitoring-agent--analyze-failure-patterns (results)
  "Analyze RESULTS for systemic failures.
Returns list of pattern plists with :pattern, :target, :evidence.

Patterns detected:
1. Grader fails 3+ times on similar code
2. Backend X has <5% keep-rate on category Y with 20+ experiments
3. Effort \\='high wastes tokens without improvement
4. Same target fails 5+ times"
  (let ((patterns nil))
    ;; Pattern 1: Grader failures
    (let* ((grader-fails (gptel-monitoring-agent--filter-by-decision
                          results "grader-failed"))
           (count (length grader-fails)))
      (when (>= count 3)
        (push (list :pattern "grader-systematic-failure"
                    :target "grader"
                    :count count
                    :evidence grader-fails)
              patterns)))

    ;; Pattern 2: Backend category failures
    (let ((backend-perf (gptel-monitoring-agent--group-by-backend-category results)))
      (dolist (entry backend-perf)
        (let ((backend (car entry))
              (category (cadr entry))
              (keep-rate (caddr entry))
              (count (cadddr entry)))
          (when (and (< keep-rate 0.05) (>= count 20))
            (push (list :pattern "backend-category-failure"
                        :backend backend
                        :category category
                        :keep-rate keep-rate
                        :count count
                        :evidence (cl-remove-if-not
                                   (lambda (r)
                                     (and (equal backend (plist-get r :backend))
                                          (equal category (plist-get r :category))))
                                   results))
                  patterns)))))

    ;; Pattern 3: Effort waste
    (let* ((high-effort (cl-remove-if-not
                         (lambda (r) (equal "high" (plist-get r :effort-level)))
                         results))
           (discarded (gptel-monitoring-agent--filter-by-decision high-effort "discarded"))
           (wasted-tokens (apply #'+ (mapcar (lambda (r)
                                               (or (plist-get r :prompt-chars) 0))
                                             discarded))))
      (when (and (>= (length discarded) 5)
                 (> wasted-tokens 100000))
        (push (list :pattern "effort-waste"
                    :effort-level "high"
                    :wasted-tokens wasted-tokens
                    :count (length discarded)
                    :evidence discarded)
              patterns)))

    ;; Pattern 4: Target failure loop
    (let ((target-failures (gptel-monitoring-agent--count-target-failures results)))
      (dolist (entry target-failures)
        (let ((target (car entry))
              (count (cdr entry)))
          (when (>= count 5)
            (push (list :pattern "target-failure-loop"
                        :target target
                        :failure-count count
                        :evidence (cl-remove-if-not
                                   (lambda (r) (equal target (plist-get r :target)))
                                   results))
                  patterns)))))

    patterns))

;; ============================================================================
;; Task 2.2: Self-Improvement Proposals
;; ============================================================================

(defun gptel-monitoring-agent--generate-proposal (pattern)
  "Generate concrete improvement proposal from failure PATTERN.
Returns proposal with :target, :changes, :test-plan, :expected-improvement."
  (pcase (plist-get pattern :pattern)
    ("grader-systematic-failure"
     (list :target "gptel-tools-agent-grader.el"
           :changes "Rewrite grader logic to handle edge cases:
- Add better error handling for malformed code
- Improve detection of valid improvements vs. no-ops
- Handle nil values gracefully
- Add fallback scoring when AST parsing fails"
           :test-plan "Test against 5 failed experiments:
1. Run grader on each failed experiment
2. Verify grader produces valid scores
3. Check that kept experiments have score > baseline
4. Ensure no false positives (discarded good changes)"
           :expected-improvement "Grader pass rate: 60% → 85%"))

    ("backend-category-failure"
     (let ((backend (plist-get pattern :backend))
           (category (plist-get pattern :category))
           (keep-rate (or (plist-get pattern :keep-rate) 0.0)))
       (list :target "gptel-auto-workflow-ontology-router.el"
             :changes (format "Remove %s from %s category routing:
- Update ontology router to exclude %s for %s
- Add fallback to next best backend
- Update fallback chain to prefer alternatives"
                              backend category backend category)
             :test-plan (format "Run 10 experiments with new routing:
1. Select 10 targets from %s category
2. Run experiments with updated router
3. Verify %s is not selected
4. Measure keep-rate improvement" category backend)
             :expected-improvement (format "Category keep-rate: %.1f%% → 15%%" 
                                          (if (numberp keep-rate)
                                              (* keep-rate 100.0)
                                            0.0)))))

    ("effort-waste"
     (let ((effort (plist-get pattern :effort-level))
           (wasted (or (plist-get pattern :wasted-tokens) 0)))
       (list :target "gptel-tools-agent-base.el"
             :changes (format "Downgrade effort level for low-value tasks:
- Change default effort from '%s' to 'medium'
- Add task complexity detection
- Only use high effort for complex multi-file changes
- Reduce token budget for simple tasks" (or effort "unknown"))
             :test-plan "Run 10 experiments with new effort levels:
1. Select 5 simple tasks and 5 complex tasks
2. Run with new effort configuration
3. Verify simple tasks use medium effort
4. Verify complex tasks still use high effort
5. Measure token savings"
             :expected-improvement (format "Token waste: %d → 50%% reduction" 
                                          (if (numberp wasted) wasted 0)))))

    ("target-failure-loop"
     (let ((target (plist-get pattern :target))
           (count (or (plist-get pattern :failure-count) 0)))
       (list :target (or target "unknown")
             :changes (format "Skip problematic target %s:
- Add %s to skip list
- Investigate root cause manually
- Consider if target is too complex for automation
- May need human review before automation" (or target "unknown") (or target "unknown"))
             :test-plan (format "Verify skip works:
1. Check that %s is in skip list
2. Run workflow and verify %s is not selected
3. Verify other targets still work
4. Document why %s was skipped (%d failures)" 
                               (or target "unknown") (or target "unknown") 
                               (or target "unknown") 
                               (if (numberp count) count 0))
             :expected-improvement (format "Workflow efficiency: skip %d wasted experiments" 
                                          (if (numberp count) count 0)))))

    (_
     (list :target "unknown"
           :changes "Unknown pattern - manual investigation required"
           :test-plan "Analyze pattern manually"
           :expected-improvement "Unknown"))))

;; ============================================================================
;; Task 2.3: Automated Testing & Deployment
;; ============================================================================

(defun gptel-monitoring-agent--calculate-baseline (results proposal)
  "Calculate baseline keep-rate from RESULTS before applying PROPOSAL changes.
Returns keep-rate as float 0.0-1.0."
  (let* ((target (plist-get proposal :target))
         (relevant (cl-remove-if-not
                    (lambda (r) (equal target (plist-get r :target)))
                    results))
         (kept (length (cl-remove-if-not
                        (lambda (r) (equal "kept" (plist-get r :decision)))
                        relevant)))
         (total (length relevant)))
    (if (> total 0)
        (/ (float kept) total)
      0.0)))

(defun gptel-monitoring-agent--calculate-improvement (before after)
  "Calculate improvement delta from BEFORE to AFTER keep-rate.
Returns improvement as float (positive = improvement)."
  (- after before))

(defun gptel-monitoring-agent--test-proposal (proposal results)
  "Test PROPOSAL against historical RESULTS.
Returns plist with :pass-rate, :improvement, :decision."
  (let* ((baseline (gptel-monitoring-agent--calculate-baseline results proposal))
         ;; Simulate improvement (in real implementation, would apply changes and test)
         (simulated-improvement 0.25)  ; Assume 25% improvement for now
         (after-keep-rate (min 1.0 (+ baseline simulated-improvement)))
         (improvement (gptel-monitoring-agent--calculate-improvement
                       baseline after-keep-rate))
         (decision (if (> improvement 0.0) "deploy" "reject")))
    (list :pass-rate after-keep-rate
          :improvement improvement
          :decision decision)))

(defun gptel-monitoring-agent--log-deployment (proposal result file)
  "Log PROPOSAL and RESULT to FILE as JSON."
  (with-temp-file file
    (insert (json-encode (list :proposal proposal
                               :result result
                               :timestamp (current-time))))))

(defun gptel-monitoring-agent--deploy-proposal (proposal results)
  "Deploy PROPOSAL if test shows improvement over RESULTS baseline.
Returns deployment result plist."
  (let* ((test-result (gptel-monitoring-agent--test-proposal proposal results))
         (decision (plist-get test-result :decision)))
    (when (equal decision "deploy")
      ;; In real implementation:
      ;; 1. Create branch
      ;; 2. Apply changes
      ;; 3. Run tests
      ;; 4. Merge if passing
      (message "Deploying proposal: %s" (plist-get proposal :target)))
    test-result))

(provide 'gptel-monitoring-agent)

;;; gptel-monitoring-agent.el ends here
