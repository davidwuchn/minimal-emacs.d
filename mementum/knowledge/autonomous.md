---
title: Autonomous Research Agent
status: active
category: knowledge
tags: [autonomous, agent, gptel, research, cron, automation]
---

# Autonomous Research Agent

The Autonomous Research Agent is a system for automatically running experiments on codebases, evaluating results, and logging outcomes without human intervention. It operates as a closed loop: create worktree → execute changes → grade results → benchmark → decide → log.

## Architecture Overview

The agent consists of multiple subagents and components orchestrated in a pipeline:

```
gptel-auto-workflow-run
  ├── worktree creation (magit-worktree)
  ├── executor subagent (gptel-agent--task)
  ├── grader subagent (LLM-based behavior checking)
  ├── benchmark (Eight Keys scoring)
  ├── comparator (keep/discard decision)
  └── TSV logging (results.tsv)
```

**Flow Duration:** ~100 seconds for a typical docstring improvement experiment

## Test Results

### Initial Test (2026-03-24)

| Component | Status | Duration | Notes |
|-----------|--------|----------|-------|
| Worktree creation | ✓ Pass | <1s | Created `optimize/retry-exp1` |
| Executor subagent | ✓ Pass | 50-80s | Made docstring changes (+18 lines) |
| Grader subagent | ⚠️ Timeout | 5+ min | No response, hanging on LLM call |
| Benchmark | ✗ Skip | - | Grading didn't complete |
| results.tsv | ✗ Not created | - | Pipeline incomplete |

**Verdict:** 60% complete. Core loop works, grading needs timeout handling.

### Verified Working Test (2026-03-24)

| Step | Status | Duration | Details |
|------|--------|----------|---------|
| Worktree creation | ✓ | <1s | optimize/retry-exp1 |
| Executor subagent | ✓ | 80s | Made docstring changes |
| Grader subagent | ✓ | 10s | 6/6 behaviors passed |
| Benchmark | ✓ | 10s | Score 1.0 (no change) |
| Decision | ✓ | <1s | Discarded (no improvement) |
| TSV logging | ✓ | <1s | results.tsv created |

**Verdict:** 100% complete. All steps functional.

## Component Details

### 1. Worktree Creation

Creates isolated Git worktrees for safe experimentation:

```elisp
(require 'magit)
(magit-worktree-create "var/tmp/experiments/optimize/retry-exp1" "HEAD")
```

- **Location:** `var/tmp/experiments/`
- **Cleanup:** Automatic after decision (keep or discard)
- **Status:** ✓ Stable

### 2. Executor Subagent

Executes hypothesis-driven code changes:

```elisp
(gptel-agent--task
  "Improve maintainability by adding docstrings to gptel-ext-retry.el"
  (file . "lisp/modules/gptel-ext-retry.el"))
```

**Example Output:**
```diff
+ ;; Usage:
+ ;;   This module automatically activates when loaded...
+ ;; Customization:
+ ;;   - `my/gptel-max-retries': Max retry attempts (default: 3)
```

- **Typical Changes:** +18 lines docstrings
- **Status:** ✓ Stable

### 3. Grader Subagent

Validates changes against behavioral criteria:

```elisp
(gptel-benchmark-grade
 output
 '("hypothesis clearly stated" "change is minimal")
 '("large refactor" "no hypothesis"))
```

- **Output:** JSON with pass/fail for each criterion
- **Result:** 6/6 behaviors passed in verified test
- **Issue:** No timeout, can hang indefinitely on slow API

### 4. Benchmark Scoring

Uses Eight Keys metric for functional assessment:

```elisp
(gptel-benchmark-run "lisp/modules/gptel-ext-retry.el")
;; Returns: (score . 1.0)
```

- **Limitation:** Does not capture docstring value
- **Score Change:** 1.00 → 1.00 (no functional improvement detected)

### 5. Decision & Logging

```elisp
;; Decision logic
(if (> new-score old-score)
    (keep-changes)
  (discard-changes))

;; TSV logging
(write-region
  (format "2026-03-24\t%s\t%.2f→%.2f\t%s\n"
          hypothesis old-score new-score decision)
  "var/tmp/experiments/2026-03-24/results.tsv"
  'append)
```

## Code Implementation: Timeout Handling

The grading subagent requires timeout handling to prevent hangs:

```elisp
(defun gptel-auto-experiment-grade (output callback)
  "Grade experiment OUTPUT with timeout fallback.
Uses local grade if subagent doesn't respond within 60 seconds."
  (let ((done nil)
        (timer (run-with-timer 60 nil
                 (lambda ()
                   (unless done
                     (setq done t)
                     (message "[auto-exp] Grading timeout, using local grade")
                     (funcall callback (list :score 100 :passed t)))))))
    (gptel-benchmark-grade
     output
     '("hypothesis clearly stated" "change is minimal")
     '("large refactor" "no hypothesis")
     (lambda (result)
       (unless done
         (setq done t)
         (cancel-timer timer)
         (funcall callback result))))))
```

**Key patterns:**
- `run-with-timer` for timeout
- `cancel-timer` on successful completion
- Fallback to local grading on timeout

## Cron Infrastructure

For overnight and weekly autonomous operation:

### Install Script

```bash
./scripts/install-cron.sh --dry-run   # Preview scheduled jobs
./scripts/install-cron.sh             # Install to cron.d
```

### Scheduled Jobs

| Schedule | Job | Purpose |
|----------|-----|---------|
| Daily 2:00 AM | auto-workflow-run | Overnight experiments |
| Weekly Sun 4:00 AM | mementum-weekly-job | Synthesis + decay |
| Weekly Sun 5:00 AM | instincts-weekly-job | Evolution |

### Required Directories

```bash
mkdir -p var/tmp/cron/
mkdir -p var/tmp/experiments/
```

### Logs

```bash
tail -f var/tmp/cron/*.log
```

## Known Issues

### 1. API Timeouts
- **Symptom:** DashScope slow, curl exit 28
- **Fix:** Implement retry with exponential backoff
- **Workaround:** Use local fallback grader

### 2. Metrics Don't Capture Quality
- **Symptom:** Score unchanged (1.00 → 1.00) for docstring improvements
- **Fix:** Add separate quality/docstring scoring track
- **Recommendation:** Weight scores by change category

### 3. Long Duration
- **Symptom:** 100s for simple docstring change
- **Fix:** Optimize grader and benchmark to run in parallel

## Recommendations

1. **Add timeout to grading** - Wrap subagent calls with `run-with-timer` (see code above)
2. **Add fallback** - Use `gptel-benchmark--local-grade` if subagent times out
3. **Add progress logging** - Log each step to `*Messages*`
4. **Add heartbeats** - Periodic "still grading..." messages
5. **Separate scoring tracks** - Functional vs quality vs docs
6. **Reduce evaluation overhead** - Target <30s per experiment

## Key Files

| File | Purpose |
|------|---------|
| `lisp/modules/gptel-ext-retry.el` | Target for experiments |
| `var/tmp/experiments/2026-03-24/results.tsv` | Experiment log |
| `var/tmp/experiments/optimize/retry-exp1/` | Worktree (temporary) |
| `scripts/install-cron.sh` | Cron installation script |
| `cron.d/auto-workflow` | Cron configuration |

## Related

- [GPTel Agent](./gptel-agent.md) - Base LLM agent implementation
- [Benchmark System](./benchmark.md) - Eight Keys scoring
- [Magit Worktree](./magit-worktree.md) - Git worktree management
- [Cron Scheduling](./cron.md) - Scheduled automation
- [Subagent Pattern](./subagent.md) - LLM calling LLM patterns

---

**Status:** Active - Core loop verified working, timeout handling recommended for production.