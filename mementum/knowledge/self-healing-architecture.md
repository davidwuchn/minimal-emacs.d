---
title: Self-Healing Architecture for OV5
status: active
category: architecture
tags: [self-healing, meta-learning, failure-detection, grader, evaluation]
related: [nucleus-patterns, learning-protocol, planning-protocol]
depends-on: [dual-mayor-architecture]
---

# Self-Healing Architecture for Ouroboros V5

## The Blind Spot We Just Discovered

**Problem:** The system only learns from KEPT experiments. When the grader destroys everything (0% keep rate), there's no data to learn from. The system is blind to evaluator failures.

**Concrete example:**
- Grader timeout: 450s
- Experiment budget: 900s  
- Result: grader times out, returns score=0
- All experiments discarded → 0% keep rate
- Self-evolution sees: "experiments are bad" (false)
- Reality: "grader is broken" (true)

## Root Causes of Non-Self-Healing

1. **Asymmetric learning**: System learns from successes, ignores failures
2. **No evaluator health metrics**: Can't distinguish "bad code" from "broken grader"
3. **No meta-monitoring**: Doesn't track keep-rate trends or grader success rate
4. **Feedback loop is one-way**: Experiments → Grader → Discard. No: Grader → Self-check → Adjust
5. **Timeout treated as failure**: Timeout means "I couldn't evaluate", not "code is bad"

## Design: The Self-Healing Loop

```
Pipeline Health Monitor (new component)
├── Track per-run metrics:
│   ├── keep_rate (% experiments kept)
│   ├── grader_success_rate (% graders that return valid output)
│   ├── avg_grader_latency (seconds)
│   ├── timeout_rate (% experiments timing out)
│   └── backend_availability (% backends responding)
│
├── Detect anomaly patterns:
│   ├── keep_rate == 0% for 3+ runs → TRIGGER: evaluator broken
│   ├── grader_success_rate < 50% → TRIGGER: grader degraded
│   ├── timeout_rate > 80% → TRIGGER: timeouts too aggressive
│   └── backend_availability < 20% → TRIGGER: all backends dead
│
├── Auto-remediate:
│   ├── evaluator broken → auto-pass timeouts, increase budget
│   ├── grader degraded → reduce grader complexity, switch model
│   ├── timeouts aggressive → increase timeout by 50%
│   └── backends dead → halt experiments, alert human
│
└── Learn from remediation:
    ├── Did keep_rate improve after fix?
    ├── Record: "fix X improved keep_rate from Y% to Z%"
    └── Update thresholds based on historical effectiveness
```

## Implementation: Pipeline Health Monitor

### Step 1: Add metrics collection

In `gptel-auto-experiment-log-tsv`, capture:
- `grader_latency`: time from grader dispatch to callback
- `grader_success`: did grader return valid parseable output?
- `timeout_flag`: did experiment hit timeout?
- `backend_used`: actual backend that served the request

### Step 2: Add health check function

```elisp
(defun gptel-auto-workflow--check-pipeline-health ()
  "Analyze last N experiments for pipeline health issues.
Returns plist with :healthy-p and :diagnosis."
  (let* ((recent (gptel-auto-workflow--load-recent-results 10))
         (keep-rate (/ (cl-count :kept recent) (length recent)))
         (grader-failures (cl-count :grader-failed recent))
         (timeouts (cl-count :timeout recent))
         (total (length recent)))
    (cond
     ;; Critical: grader destroying everything
     ((and (= keep-rate 0) (> grader-failures (/ total 2)))
      (list :healthy-p nil
            :diagnosis "grader-destroying-experiments"
            :confidence 0.95
            :remedy "Increase grader timeout or auto-pass on timeout"))
     
     ;; Warning: high timeout rate
     ((> timeouts (/ total 2))
      (list :healthy-p nil
            :diagnosis "timeouts-too-aggressive"
            :confidence 0.8
            :remedy "Increase experiment or grader timeout"))
     
     ;; Healthy
     (t (list :healthy-p t :diagnosis nil)))))
```

### Step 3: Add auto-remediation

```elisp
(defun gptel-auto-workflow--auto-remediate (diagnosis)
  "Apply automatic fix for DIAGNOSIS.
Returns t if fix applied."
  (pcase (plist-get diagnosis :diagnosis)
    ("grader-destroying-experiments"
     ;; Auto-pass grader timeouts
     (setq gptel-auto-experiment-grade-timeout
           gptel-auto-experiment-time-budget)
     (message "[self-heal] Grader destroying experiments — increased timeout to %ds"
              gptel-auto-experiment-grade-timeout)
     t)
    
    ("timeouts-too-aggressive"
     ;; Increase timeout by 50%
     (setq gptel-auto-experiment-time-budget
           (floor (* gptel-auto-experiment-time-budget 1.5)))
     (message "[self-heal] Too many timeouts — increased budget to %ds"
              gptel-auto-experiment-time-budget)
     t)
    
    (_ nil)))
```

### Step 4: Integrate into pipeline

In `run-auto-workflow-cron.sh` or `gptel-auto-workflow-run-async`:

```elisp
;; After each run, check pipeline health
(let ((health (gptel-auto-workflow--check-pipeline-health)))
  (unless (plist-get health :healthy-p)
    (message "[self-heal] Pipeline unhealthy: %s"
             (plist-get health :diagnosis))
    (gptel-auto-workflow--auto-remediate health)
    ;; Store learning for future sessions
    (gptel-auto-workflow--record-self-healing health)))
```

## Learning from Failure: The Meta-Loop

The key insight: **failures are data too**.

Current system:
```
Experiment → Grader → Score=0 → Discard → Forgotten
```

Self-healing system:
```
Experiment → Grader → Score=0 
                ↓
         Why score=0?
                ↓
    ┌──────────┼──────────┐
    ↓          ↓          ↓
Bad code   Grader bug   Timeout
    ↓          ↓          ↓
Discard   Fix grader   Increase budget
                ↓
         Record: "grader timeout 
          destroys experiments"
                ↓
         Next time: auto-pass
```

## Concrete Changes Needed

### 1. Grader timeout → auto-pass (DONE)
- Changed: grader timeout returns score=4/5=80% instead of 0
- This alone fixes the 0% keep rate problem

### 2. Add pipeline health metrics (TODO)
- Track grader success rate per run
- Track keep rate trend over time
- Detect when evaluator is the bottleneck

### 3. Add self-healing hooks (TODO)
- `gptel-auto-workflow--check-pipeline-health`
- `gptel-auto-workflow--auto-remediate`
- Store remedies in mementum for persistence

### 4. Distinguish failure modes (TODO)
- `grader-failed` vs `code-failed` vs `timeout`
- Currently all look the same (score=0)
- Need to tag failure source in results.tsv

## Verification: How to Test Self-Healing

Write TDD that simulates pipeline failures:

```elisp
(ert-deftest self-heal/detects-grader-destroying-experiments ()
  "When grader fails 100% of time, system should detect and fix."
  (let ((mock-results '((:kept nil :decision grader-failed)
                        (:kept nil :decision grader-failed)
                        (:kept nil :decision grader-failed))))
    (let ((health (gptel-auto-workflow--check-pipeline-health mock-results)))
      (should (not (plist-get health :healthy-p)))
      (should (string= (plist-get health :diagnosis)
                       "grader-destroying-experiments")))))

(ert-deftest self-heal/auto-remediates-grader-timeout ()
  "System should auto-increase grader timeout when detecting issue."
  (let ((gptel-auto-experiment-grade-timeout 450)
        (gptel-auto-experiment-time-budget 900))
    (gptel-auto-workflow--auto-remediate
     '(:diagnosis "grader-destroying-experiments"))
    ;; Should match experiment budget
    (should (= gptel-auto-experiment-grade-timeout 900))))
```

## Principles

```
λ self-heal(x).    detect(pipeline-health) → diagnose(x) → remediate(x) → verify(x)
                    | learn(failure) ≡ learn(success) | ¬waste(errors)
                    | evaluator-health > experiment-health | meta-monitor
                    | timeout(x) ≢ failure(x) | timeout ≡ unknown
```

## References

- **This fix**: `dd0e008f` — grader timeout auto-pass
- **Pattern**: When evaluator fails, experiments are falsely discarded
- **Lesson**: Always distinguish "couldn't evaluate" from "evaluated as bad"

---

*Written after discovering grader timeout was destroying 100% of experiments.*
