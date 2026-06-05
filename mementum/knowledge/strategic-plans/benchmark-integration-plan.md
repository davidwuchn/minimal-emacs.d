---
title: "Benchmark Integration Plan: Sensor Layer for Self-Improving Company"
status: active
category: strategic-implementation
tags: [benchmark, sensor-layer, ycv-vision, production-metrics, token-economics, monitoring-agent]
created: 2026-06-05
updated: 2026-06-05
related: [yc-vision-analysis, gap-analysis, implementation-roadmap]
---

# Benchmark Integration Plan: Sensor Layer for Self-Improving Company

## Executive Summary

The benchmark is the **nervous system** of OV5's self-improving company architecture. This plan integrates the benchmark (32-column TSV) with all 5 YC vision gaps, transforming OV5 from "code improvement tool" into "self-improving AI architecture."

**Core principle:** Every subsystem (AutoTTS, AutoGo, Router, VSM, Monitoring Agent, Token Economics) consumes benchmark data to make decisions. The benchmark is the single source of truth that enables recursive self-improvement.

## Integration Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    BENCHMARK (32-column TSV)                 │
│  keep-rate, cost, effort, duration, backend, model, ...    │
└─────────────────────────────────────────────────────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
        ▼                 ▼                 ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────────┐
│  Monitoring  │  │    Token     │  │   Production     │
│    Agent     │  │  Economics   │  │    Sensors       │
│  (Gap 2)     │  │   (Gap 5)    │  │    (Gap 1)       │
│              │  │              │  │                  │
│ Analyzes     │  │ Calculates   │  │ Tracks real-     │
│ failure      │  │ ROI, budgets │  │ world impact     │
│ patterns     │  │ tokens       │  │                  │
└──────────────┘  └──────────────┘  └──────────────────┘
        │                 │                 │
        └─────────────────┼─────────────────┘
                          │
                          ▼
              ┌──────────────────────┐
              │  Decision Engine     │
              │                      │
              │ - Risk scoring       │
              │ - Approval thresholds│
              │ - Regeneration       │
              │   decisions          │
              └──────────────────────┘
                          │
                ┌─────────┴─────────┐
                │                   │
                ▼                   ▼
        ┌──────────────┐    ┌──────────────┐
        │  AI Auto-    │    │   Human      │
        │  Approve     │    │   Review     │
        │  (low risk)  │    │   (high risk)│
        └──────────────┘    └──────────────┘
```

## Phase 1: Production Sensors (0-6 months, P0)

### Goal
Close the feedback loop between code quality and business value.

### TSV Schema Extension
Add columns 33-37 to `results.tsv`:

```
Column 33: prod_error_rate_before    (float, 0.0-1.0)
Column 34: prod_error_rate_after     (float, 0.0-1.0)
Column 35: prod_error_rate_delta     (float, -1.0-1.0)
Column 36: user_satisfaction_delta   (float, -1.0-1.0)
Column 37: support_tickets_reduced   (integer, 0-N)
```

### Implementation Tasks

#### Task 1.1: Production Monitoring Integration (Week 1-2)
**Files:** `lisp/modules/gptel-auto-workflow-production-metrics.el` (new)

```elisp
(defun gptel-auto-workflow--track-production-impact (target experiment-id)
  "Query production metrics before/after experiment.
Returns plist with :error-rate-before, :error-rate-after, :delta."
  (let* ((sentry-api-key (gptel-auto-workflow--get-sentry-key))
         (before (gptel-auto-workflow--query-sentry-errors 
                  target :days-before 7))
         (after (gptel-auto-workflow--query-sentry-errors 
                 target :days-after 7)))
    (list :error-rate-before before
          :error-rate-after after
          :delta (- after before)
          :improvement-pct (if (> before 0) 
                               (/ (- before after) before)
                             0))))
```

**Dependencies:**
- Sentry API access (or DataDog, custom logs)
- Target-to-service mapping (which file affects which service?)

**Acceptance criteria:**
- [ ] Query Sentry API for error rates
- [ ] Map target files to production services
- [ ] Log production metrics to TSV columns 33-35
- [ ] Test with 10 historical experiments

#### Task 1.2: User Feedback Collection (Week 3-4)
**Files:** `lisp/modules/gptel-auto-workflow-user-feedback.el` (new)

```elisp
(defun gptel-auto-workflow--collect-user-feedback (target)
  "Collect user complaints/praise about generated code.
Returns satisfaction delta: -1.0 (worse) to +1.0 (better)."
  (let* ((feedback-api (gptel-auto-workflow--get-feedback-endpoint))
         (complaints (gptel-auto-workflow--query-complaints 
                      target :days 30))
         (praise (gptel-auto-workflow--query-praise 
                  target :days 30)))
    (gptel-auto-workflow--calculate-satisfaction-delta 
     complaints praise)))
```

**Dependencies:**
- User feedback system (Slack channel, GitHub issues, custom form)
- Feedback categorization (positive/negative/neutral)

**Acceptance criteria:**
- [ ] Query feedback API for target-related complaints/praise
- [ ] Calculate satisfaction delta
- [ ] Log to TSV column 36
- [ ] Test with 5 targets that have known user feedback

#### Task 1.3: Business Value Scoring (Week 5-6)
**Files:** `lisp/modules/gptel-auto-workflow-business-value.el` (new)

```elisp
(defun gptel-auto-workflow--calculate-business-value (experiment)
  "Calculate business value from production impact.
Returns weighted score: 0.0-1.0.
Weights: error-reduction (40%), support-tickets (30%), satisfaction (30%)."
  (let* ((error-delta (plist-get experiment :prod-error-rate-delta))
         (tickets (plist-get experiment :support-tickets-reduced))
         (satisfaction (plist-get experiment :user-satisfaction-delta))
         (error-score (min 1.0 (/ (abs error-delta) 0.1)))  ; 10% reduction = 1.0
         (ticket-score (min 1.0 (/ tickets 10.0)))          ; 10 tickets = 1.0
         (satisfaction-score (/ (+ satisfaction 1.0) 2.0))) ; -1..1 → 0..1
    (+ (* 0.4 error-score)
       (* 0.3 ticket-score)
       (* 0.3 satisfaction-score))))
```

**Acceptance criteria:**
- [ ] Calculate weighted business value score
- [ ] Integrate into experiment scoring (weight: 60% business value, 40% code quality)
- [ ] Log to TSV column 37
- [ ] Validate: experiments with high business value score correlate with production improvements

### Milestone: Phase 1 Complete
- [ ] 10 targets tracked with production metrics
- [ ] Business value scoring integrated into experiment decisions
- [ ] Dashboard showing: code quality vs. production impact
- [ ] Report: "Which experiments delivered most business value?"

---

## Phase 2: Monitoring Agent (6-12 months, P1)

### Goal
Create meta-agent that analyzes failures and rewrites the pipeline.

### Implementation Tasks

#### Task 2.1: Failure Pattern Analysis (Month 7-8)
**Files:** `lisp/modules/gptel-monitoring-agent.el` (new)

```elisp
(defun gptel-monitoring-agent--analyze-failure-patterns (results-tsv)
  "Analyze last 50 runs for systemic failures.
Returns list of (pattern . proposal) pairs.

Patterns detected:
1. Grader fails 3+ times on similar code → propose grader rewrite
2. Backend X has 0% keep-rate on category Y → propose backend swap
3. Effort 'high' wastes tokens without improvement → propose effort downgrade
4. Same target fails 5+ times → propose target skip"
  (let* ((results (gptel-auto-workflow--parse-all-results 50))
         (patterns nil))
    ;; Pattern 1: Grader failures
    (let ((grader-fails (gptel-monitoring-agent--filter-by-decision 
                         results "grader-failed")))
      (when (>= (length grader-fails) 3)
        (push (list :pattern "grader-systematic-failure"
                    :target "grader"
                    :proposal "rewrite-grader-logic"
                    :evidence grader-fails)
              patterns)))
    ;; Pattern 2: Backend category failures
    (let ((backend-perf (gptel-monitoring-agent--group-by-backend-category 
                         results)))
      (dolist (entry backend-perf)
        (let ((backend (car entry))
              (category (cadr entry))
              (keep-rate (caddr entry)))
          (when (and (< keep-rate 0.05) (> (cadddr entry) 20))
            (push (list :pattern "backend-category-failure"
                        :backend backend
                        :category category
                        :proposal "swap-backend"
                        :evidence entry)
                  patterns)))))
    patterns))
```

**Acceptance criteria:**
- [ ] Parse last 50 runs from TSV
- [ ] Detect 4 failure patterns (grader, backend, effort, target)
- [ ] Generate improvement proposals with evidence
- [ ] Test with historical failure data

#### Task 2.2: Self-Improvement Proposals (Month 9-10)
**Files:** `lisp/modules/gptel-monitoring-agent-proposals.el` (new)

```elisp
(defun gptel-monitoring-agent--generate-proposal (pattern)
  "Generate concrete improvement proposal from failure pattern.
Returns proposal with :target, :changes, :test-plan, :expected-improvement."
  (pcase (plist-get pattern :pattern)
    ("grader-systematic-failure"
     (list :target "gptel-tools-agent-grader.el"
           :changes "Rewrite grader logic to handle edge cases"
           :test-plan "Test against 5 failed experiments"
           :expected-improvement "Grader pass rate: 60% → 85%"))
    ("backend-category-failure"
     (let ((backend (plist-get pattern :backend))
           (category (plist-get pattern :category)))
       (list :target "gptel-auto-workflow-ontology-router.el"
             :changes (format "Remove %s from %s category routing" backend category)
             :test-plan "Run 10 experiments with new routing"
             :expected-improvement "Category keep-rate: 5% → 15%")))))
```

**Acceptance criteria:**
- [ ] Generate concrete proposals (file changes, test plans)
- [ ] Estimate expected improvement
- [ ] Log proposals to `var/tmp/monitoring-agent/proposals/`
- [ ] Test: proposals address root cause of failures

#### Task 2.3: Automated Testing & Deployment (Month 11-12)
**Files:** `lisp/modules/gptel-monitoring-agent-deploy.el` (new)

```elisp
(defun gptel-monitoring-agent--test-proposal (proposal)
  "Test proposal against historical failures.
Returns :pass-rate (0.0-1.0), :improvement (delta keep-rate)."
  (let* ((changes (plist-get proposal :changes))
         (test-experiments (plist-get proposal :test-plan))
         (before-keep-rate (gptel-monitoring-agent--calculate-keep-rate 
                            test-experiments :baseline t))
         (after-keep-rate (gptel-monitoring-agent--apply-and-test 
                           changes test-experiments)))
    (list :pass-rate after-keep-rate
          :improvement (- after-keep-rate before-keep-rate)
          :decision (if (> after-keep-rate before-keep-rate)
                        "deploy"
                      "reject"))))

(defun gptel-monitoring-agent--deploy-proposal (proposal)
  "Deploy proposal if test pass rate > baseline.
Creates branch, applies changes, runs tests, merges if better."
  (let* ((test-result (gptel-monitoring-agent--test-proposal proposal)))
    (when (equal (plist-get test-result :decision) "deploy")
      (gptel-monitoring-agent--create-branch proposal)
      (gptel-monitoring-agent--apply-changes proposal)
      (gptel-monitoring-agent--run-tests)
      (gptel-monitoring-agent--merge-if-passing))))
```

**Acceptance criteria:**
- [ ] Test proposals against historical failures
- [ ] Calculate improvement delta
- [ ] Deploy if new version is better (keep-rate improves)
- [ ] Log deployment decisions to `var/tmp/monitoring-agent/deployments/`

### Milestone: Phase 2 Complete
- [ ] Monitoring agent analyzes failures daily
- [ ] Generates 5+ improvement proposals per month
- [ ] Tests and deploys 2+ proposals per month
- [ ] Measurable improvement: system keep-rate increases 5% from agent interventions

---

## Phase 3: Token Economics (12-18 months, P2)

### Goal
Optimize token allocation based on ROI per category.

### Implementation Tasks

#### Task 3.1: Cumulative Cost Tracking (Month 13-14)
**Files:** Extend `gptel-auto-experiment--calculate-cost-usd`

```elisp
(defun gptel-token-economics--track-cumulative-cost (experiment)
  "Track cumulative cost per category.
Returns updated cost tracker state."
  (let* ((category (plist-get experiment :category))
         (cost (plist-get experiment :cost-usd))
         (kept (equal (plist-get experiment :decision) "kept"))
         (tracker (gptel-token-economics--get-tracker category)))
    (plist-put tracker :total-cost (+ (plist-get tracker :total-cost) cost))
    (plist-put tracker :total-experiments (1+ (plist-get tracker :total-experiments)))
    (when kept
      (plist-put tracker :kept-experiments (1+ (plist-get tracker :kept-experiments))))
    (plist-put tracker :cost-per-kept 
               (if (> (plist-get tracker :kept-experiments) 0)
                   (/ (plist-get tracker :total-cost) 
                      (plist-get tracker :kept-experiments))
                 0))
    (gptel-token-economics--save-tracker category tracker)))
```

**Acceptance criteria:**
- [ ] Track cumulative cost per category
- [ ] Calculate cost-per-kept experiment
- [ ] Persist to `var/tmp/token-economics/category-costs.json`
- [ ] Dashboard: cost breakdown by category

#### Task 3.2: ROI Calculation (Month 15-16)
**Files:** `lisp/modules/gptel-token-economics.el` (new)

```elisp
(defun gptel-token-economics--calculate-roi (category)
  "Calculate ROI for category: business value per token spent.
ROI = (business-value-score × experiments-kept) / total-tokens-spent.
Higher ROI = more value per token."
  (let* ((tracker (gptel-token-economics--get-tracker category))
         (total-cost (plist-get tracker :total-cost))
         (kept-experiments (plist-get tracker :kept-experiments))
         (avg-business-value (gptel-token-economics--avg-business-value category))
         (total-value (* avg-business-value kept-experiments)))
    (if (> total-cost 0)
        (/ total-value total-cost)
      0)))

(defun gptel-token-economics--rank-categories-by-roi ()
  "Rank all categories by ROI (descending).
Returns list of (category . roi) pairs."
  (let ((categories (gptel-token-economics--all-categories))
        (roi-list nil))
    (dolist (category categories)
      (let ((roi (gptel-token-economics--calculate-roi category)))
        (push (cons category roi) roi-list)))
    (sort roi-list (lambda (a b) (> (cdr a) (cdr b))))))
```

**Acceptance criteria:**
- [ ] Calculate ROI per category
- [ ] Rank categories by ROI
- [ ] Identify high-ROI (spend more) and low-ROI (spend less) categories
- [ ] Report: "Top 5 categories by ROI"

#### Task 3.3: Token Budget Optimization (Month 17-18)
**Files:** Extend `gptel-auto-workflow-ontology-router.el`

```elisp
(defun gptel-token-economics--optimize-allocation (total-budget)
  "Optimize token allocation across categories based on ROI.
Allocates more tokens to high-ROI categories, less to low-ROI.
Returns list of (category . token-budget) pairs."
  (let* ((roi-ranking (gptel-token-economics--rank-categories-by-roi))
         (total-roi (apply #'+ (mapcar #'cdr roi-ranking)))
         (allocation nil))
    (dolist (entry roi-ranking)
      (let* ((category (car entry))
             (roi (cdr entry))
             (budget-share (/ roi total-roi))
             (token-budget (* total-budget budget-share)))
        (push (cons category token-budget) allocation)))
    allocation))

(defun gptel-token-economics--apply-budget (allocation)
  "Apply token budget to ontology router.
Modifies category weights to reflect budget allocation."
  (dolist (entry allocation)
    (let ((category (car entry))
          (budget (cdr entry)))
      (gptel-auto-workflow--set-category-weight 
       category (* 1.5 (/ budget (gptel-token-economics--avg-budget)))))))
```

**Acceptance criteria:**
- [ ] Calculate optimal token allocation based on ROI
- [ ] Apply budget to ontology router (adjust category weights)
- [ ] Test: allocation increases total kept experiments by 20%
- [ ] Dashboard: token allocation vs. ROI

### Milestone: Phase 3 Complete
- [ ] Cumulative cost tracking for all categories
- [ ] ROI calculation and ranking
- [ ] Token budget optimization integrated into router
- [ ] Measurable improvement: 20% more kept experiments with same total tokens

---

## Phase 4: Human Review Thresholds (12-18 months, P2)

### Goal
Implement risk-based approval (low-risk = AI approves, high-risk = human approves).

### Implementation Tasks

#### Task 4.1: Risk Scoring (Month 13-14)
**Files:** `lisp/modules/gptel-auto-workflow-risk-scoring.el` (new)

```elisp
(defun gptel-auto-workflow--calculate-risk-score (experiment)
  "Calculate risk score (0.0-1.0) for experiment.
Risk factors:
- Keep-rate < 15% → +0.3
- Code quality delta > 0.3 → +0.3
- Cost > $5.00 → +0.2
- Production impact > 20% → +0.2

Returns risk score: 0.0 (low risk) to 1.0 (high risk)."
  (let* ((keep-rate (gptel-auto-workflow--category-keep-rate 
                     (plist-get experiment :category)))
         (quality-delta (abs (- (plist-get experiment :score-after)
                                (plist-get experiment :score-before))))
         (cost (plist-get experiment :cost-usd))
         (prod-impact (abs (plist-get experiment :prod-error-rate-delta)))
         (risk 0.0))
    (when (< keep-rate 0.15)
      (setq risk (+ risk 0.3)))
    (when (> quality-delta 0.3)
      (setq risk (+ risk 0.3)))
    (when (> cost 5.0)
      (setq risk (+ risk 0.2)))
    (when (> prod-impact 0.2)
      (setq risk (+ risk 0.2)))
    (min 1.0 risk)))
```

**Acceptance criteria:**
- [ ] Calculate risk score based on 4 factors
- [ ] Log to TSV column 38
- [ ] Validate: high-risk experiments correlate with failures

#### Task 4.2: Approval Thresholds (Month 15-16)
**Files:** Extend `gptel-auto-experiment--decide`

```elisp
(defun gptel-auto-workflow--approval-threshold (experiment)
  "Determine approval threshold based on risk score.
Risk < 0.3 → AI auto-approves
Risk 0.3-0.7 → AI recommends, human confirms
Risk > 0.7 → Human must approve

Returns :approval-type (auto/recommend/required)."
  (let ((risk (plist-get experiment :risk-score)))
    (cond
     ((< risk 0.3) :auto)
     ((< risk 0.7) :recommend)
     (t :required))))

(defun gptel-auto-experiment--decide-with-risk (experiment)
  "Decide with risk-based approval.
If risk < 0.3 and score improves, auto-approve.
If risk 0.3-0.7, recommend but wait for human.
If risk > 0.7, require human approval."
  (let* ((decision (gptel-auto-experiment--decide experiment))
         (approval-type (gptel-auto-workflow--approval-threshold experiment)))
    (pcase approval-type
      (:auto 
       (when (equal decision "kept")
         (gptel-auto-workflow--auto-approve experiment)))
      (:recommend
       (gptel-auto-workflow--request-human-confirmation experiment))
      (:required
       (gptel-auto-workflow--require-human-approval experiment)))))
```

**Acceptance criteria:**
- [ ] Implement 3-tier approval (auto/recommend/required)
- [ ] Auto-approve low-risk experiments
- [ ] Request human confirmation for high-risk experiments
- [ ] Log approval decisions to TSV column 39

### Milestone: Phase 4 Complete
- [ ] Risk scoring integrated into all experiments
- [ ] 70% of experiments auto-approved (low risk)
- [ ] 20% require human confirmation (medium risk)
- [ ] 10% require human approval (high risk)
- [ ] Human review time reduced by 60%

---

## Phase 5: Software as Consumable (18-24 months, P2)

### Goal
Treat code as disposable, regenerate with better models.

### Implementation Tasks

#### Task 5.1: Regeneration Decision (Month 19-20)
**Files:** `lisp/modules/gptel-auto-workflow-regeneration.el` (new)

```elisp
(defun gptel-auto-workflow--should-regenerate (target)
  "Decide whether to regenerate target instead of maintaining.
Regenerate when:
- Keep-rate < 10% for 3+ runs (experiments failing)
- Cost-per-kept > $5.00 (expensive to improve)
- Code quality stagnant or declining
- Better model available (e.g., gpt-5.5 vs gpt-5.4)

Returns :regenerate or :maintain."
  (let* ((results (gptel-auto-workflow--target-results target 10))
         (keep-rate (gptel-auto-workflow--calculate-keep-rate results))
         (cost-per-kept (gptel-auto-workflow--calculate-cost-per-kept results))
         (quality-trend (gptel-auto-workflow--quality-trend results))
         (better-model (gptel-auto-workflow--better-model-available target)))
    (if (or (and (< keep-rate 0.10) (>= (length results) 3))
            (> cost-per-kept 5.0)
            (<= quality-trend 0.0)
            better-model)
        :regenerate
      :maintain)))
```

**Acceptance criteria:**
- [ ] Analyze target performance trends
- [ ] Detect when regeneration is better than maintenance
- [ ] Log regeneration decisions to `var/tmp/regeneration/decisions/`
- [ ] Test with 5 targets that have poor performance

#### Task 5.2: Business Context Preservation (Month 21-22)
**Files:** `lisp/modules/gptel-auto-workflow-business-context.el` (new)

```elisp
(defun gptel-auto-workflow--extract-business-context (target)
  "Extract business context from target: why it exists, what it does.
Returns plist with :purpose, :key-decisions, :constraints."
  (let* ((history (gptel-auto-workflow--target-git-history target))
         (commits (gptel-auto-workflow--filter-significant-commits history))
         (purpose (gptel-auto-workflow--infer-purpose commits))
         (decisions (gptel-auto-workflow--extract-decisions commits))
         (constraints (gptel-auto-workflow--infer-constraints target)))
    (list :purpose purpose
          :key-decisions decisions
          :constraints constraints
          :target target)))

(defun gptel-auto-workflow--preserve-business-context (target context)
  "Preserve business context before regeneration.
Writes to mementum/knowledge/business-context/{target}.md."
  (let ((context-file (format "mementum/knowledge/business-context/%s.md"
                              (file-name-base target))))
    (with-temp-file context-file
      (insert (format "# Business Context: %s\n\n" target))
      (insert (format "## Purpose\n%s\n\n" (plist-get context :purpose)))
      (insert "## Key Decisions\n")
      (dolist (decision (plist-get context :key-decisions))
        (insert (format "- %s\n" decision)))
      (insert (format "\n## Constraints\n%s\n" (plist-get context :constraints))))))
```

**Acceptance criteria:**
- [ ] Extract business context from git history
- [ ] Preserve context before regeneration
- [ ] Context includes: purpose, decisions, constraints
- [ ] Test with 10 targets

#### Task 5.3: Code Regeneration (Month 23-24)
**Files:** Extend `gptel-auto-workflow-regeneration.el`

```elisp
(defun gptel-auto-workflow--regenerate-target (target context)
  "Regenerate target with better model, preserving business context.
Process:
1. Generate new implementation with better model
2. Test against historical failed experiments
3. If new version passes 70%, replace old code
4. Log regeneration event"
  (let* ((better-model (gptel-auto-workflow--better-model-available target))
         (new-code (gptel-auto-workflow--generate-with-model 
                    target better-model context))
         (test-results (gptel-auto-workflow--test-against-history 
                        target new-code))
         (pass-rate (gptel-auto-workflow--calculate-pass-rate test-results)))
    (when (>= pass-rate 0.7)
      (gptel-auto-workflow--replace-code target new-code)
      (gptel-auto-workflow--log-regeneration-event 
       target better-model pass-rate))))
```

**Acceptance criteria:**
- [ ] Generate new code with better model
- [ ] Test against historical experiments
- [ ] Replace code if pass rate >= 70%
- [ ] Log regeneration events to `var/tmp/regeneration/events/`

### Milestone: Phase 5 Complete
- [ ] 5 targets regenerated with better models
- [ ] Business context preserved for all regenerations
- [ ] Regenerated code passes 70%+ of historical tests
- [ ] Report: "Regeneration vs. maintenance cost comparison"

---

## Resource Requirements

### Engineering Effort
- **Phase 1 (0-6 months):** 0.5 engineer-years
- **Phase 2 (6-12 months):** 1.0 engineer-years
- **Phase 3 (12-18 months):** 0.5 engineer-years
- **Phase 4 (12-18 months):** 0.5 engineer-years
- **Phase 5 (18-24 months):** 0.5 engineer-years
- **Total:** 3.0 engineer-years over 24 months

### Infrastructure
- Sentry/DataDog API access (Phase 1)
- User feedback system (Phase 1)
- Monitoring agent compute (Phase 2)
- Token economics database (Phase 3)

### Dependencies
- Production monitoring system (Phase 1)
- Historical experiment data (all phases)
- Better model availability (Phase 5)

---

## Success Metrics

### Phase 1 Success
- [ ] 10 targets tracked with production metrics
- [ ] Business value scoring correlates with production improvements
- [ ] Dashboard shows: code quality vs. production impact

### Phase 2 Success
- [ ] Monitoring agent generates 5+ proposals per month
- [ ] System keep-rate increases 5% from agent interventions
- [ ] "Holy shit moment": agent rewrites grader and improves pass rate

### Phase 3 Success
- [ ] Token allocation optimized based on ROI
- [ ] 20% more kept experiments with same total tokens
- [ ] Dashboard shows: token allocation vs. ROI

### Phase 4 Success
- [ ] 70% of experiments auto-approved
- [ ] Human review time reduced by 60%
- [ ] High-risk experiments catch 90% of failures

### Phase 5 Success
- [ ] 5 targets regenerated with better models
- [ ] Regenerated code passes 70%+ of historical tests
- [ ] Maintenance cost reduced by 30%

---

## Next Steps

**Immediate (this week):**
1. Create TSV schema extension (columns 33-39)
2. Stub production metrics tracking function
3. Design Sentry API integration

**Short-term (this month):**
1. Implement production monitoring for 10 targets
2. Create monitoring agent prototype
3. Calculate ROI for top 5 categories

**Medium-term (this quarter):**
1. Deploy production sensors
2. Test monitoring agent on historical data
3. Implement risk-based approval thresholds

---

## Conclusion

The benchmark is the **nervous system** of OV5's self-improving company. By integrating it with production sensors, monitoring agents, token economics, and risk-based approval, we transform OV5 from "code improvement tool" into "self-improving AI architecture."

**Without benchmark:** Blind system, no feedback, no learning  
**With benchmark:** Self-aware system, continuous improvement, autonomous operation  
**With extended benchmark:** Self-improving company that optimizes for business value, not just code quality

This 24-month roadmap delivers the YC vision: recursive self-improving AI loops that learn from every outcome and get smarter every cycle.
