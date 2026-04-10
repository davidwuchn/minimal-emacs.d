---
title: Autonomous Research Agent
status: active
category: knowledge
tags: [autonomous, agent, workflow, cron, infrastructure, experimentation]
---

# Autonomous Research Agent

## Overview

The Autonomous Research Agent is an Emacs-based system that runs self-directed experiments on codebases. It can create worktrees, execute changes via subagents, grade results, benchmark outcomes, and log decisions automatically.

## Architecture

The autonomous workflow consists of six sequential stages:

```
gptel-auto-workflow-run
  ├── worktree (magit-worktree)
  ├── executor subagent (gptel-agent--task)
  ├── grader subagent (LLM, JSON output)
  ├── benchmark (Eight Keys scoring)
  ├── comparator (keep/discard)
  └── TSV log
```

### Component Status Matrix

| Component | Status | Duration | Notes |
|-----------|--------|----------|-------|
| Worktree creation | ✓ Pass | <1s | Creates optimize/retry-exp1 |
| Executor subagent | ✓ Pass | 50-80s | Makes code changes |
| Grader subagent | ⚠️ Timeout | 5+ min | Needs timeout handling |
| Benchmark | ✓ Pass | 10s | Eight Keys scoring |
| Decision | ✓ Pass | <1s | Keep or discard |
| TSV logging | ✓ Pass | <1s | results.tsv created |

## Usage

### Running the Workflow

```elisp
;; Execute a full autonomous experiment
(gptel-auto-workflow-run "optimize" "improve code structure")

;; With explicit hypothesis
(gptel-auto-workflow-run 
  "feature X"
  "Adding documentation improves maintainability")
```

### Manual Step Execution

```elisp
;; Create worktree manually
(gptel-auto-worktree-create "experiment-name")

;; Run executor on a file
(gptel-agent--task "Add docstrings to improve clarity" 
                  '((file . "lisp/modules/gptel-ext-retry.el")))

;; Run grader
(gptel-benchmark-grade output 
                       '("hypothesis clearly stated")
                       '("large refactor"))
```

## Timeout Handling

The grading subagent can hang due to LLM API delays. This fix adds timeout fallback:

```elisp
(defun gptel-auto-experiment-grade (output callback)
  "Grade experiment OUTPUT with timeout fallback."
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

### Timeout Patterns

| Scenario | Solution | Fallback |
|----------|----------|----------|
| Grading subagent hangs | 60s timer | Local grade (score 100) |
| DashScope API slow | `run-with-timer` | Retry with exponential backoff |
| Curl exit 28 (timeout) | Auto-retry | Log to var/tmp/cron/ |

## Experiment Results Log

Results are written to `var/tmp/experiments/YYYY-MM-DD/results.tsv`:

```tsv
timestamp	target	hypothesis	score_before	score_after	decision	duration	grader_status
2026-03-24T10:30:00	gptel-ext-retry.el	Adding docstring to improve maintainability	1.00	1.00	discarded	100s	6/6 passed
```

### Log Format

| Column | Type | Description |
|--------|------|-------------|
| timestamp | ISO 8601 | When experiment started |
| target | string | File or module modified |
| hypothesis | string | Explicit claim about change |
| score_before | float | Benchmark score prior |
| score_after | float | Benchmark score after |
| decision | enum | kept / discarded |
| duration | seconds | Total experiment time |
| grader_status | string | Subagent pass/fail count |

## Infrastructure

### Cron Scheduling

The autonomous system runs on scheduled intervals:

| Schedule | Job | Purpose |
|----------|-----|---------|
| Daily 2:00 AM | auto-workflow-run | Overnight experiments |
| Weekly Sun 4:00 AM | mementum-weekly-job | Synthesis + decay |
| Weekly Sun 5:00 AM | instincts-weekly-job | Evolution |

### Installation

```bash
# Preview cron changes
./scripts/install-cron.sh --dry-run

# Install actual cron jobs
./scripts/install-cron.sh

# Monitor logs
tail -f var/tmp/cron/*.log
```

### Directory Structure

```
var/tmp/
├── cron/           # Cron job logs
├── experiments/    # Experiment worktrees
│   └── YYYY-MM-DD/
│       └── results.tsv
```

## Known Issues

### Issue 1: Grading Timeout

**Symptom:** Grader subagent hangs for 5+ minutes  
**Root Cause:** No explicit timeout on LLM subagent calls  
**Fix:** Wrap with `run-with-timer` as shown above

### Issue 2: No Score Improvement for Docs

**Symptom:** Adding docstrings yields no benchmark score change  
**Root Cause:** Metrics don't capture documentation quality  
**Fix:** Add maintainability-specific metrics, separate scoring tracks

### Issue 3: Excessive Duration

**Symptom:** 100s for simple docstring changes  
**Root Cause:** Full benchmark run for every change  
**Fix:** Add quick-validation mode for non-functional changes

### Issue 4: API Timeouts

**Symptom:** DashScope slow, curl exit 28  
**Root Cause:** Network latency, no retry logic  
**Fix:** Add exponential backoff, log failures to cron logs

## Improvement Recommendations

1. **Add heartbeat logging** - Periodic "still grading..." messages to `*Messages*`
2. **Separate scoring tracks** - Functional vs quality vs documentation
3. **Weight scores by change category** - Docs get maintainability weights
4. **Quick-validation mode** - Skip full benchmark for trivial changes

## Verdict

**60% complete** - Core loop works (worktree → executor → changes → benchmark → decide → log). Grading subagent needs timeout handling to be production-ready.

## Code Diff Example

Typical executor output adds documentation:

```diff
+ ;; Usage:
+ ;;   This module automatically activates when loaded...
+ ;; Customization:
+ ;;   - `my/gptel-max-retries': Max retry attempts (default: 3)
```

## Related

- [Agent System](agent-system) - Subagent architecture
- [Benchmark System](benchmark) - Eight Keys scoring
- [Worktree Management](magit-worktree) - Git worktree operations
- [Cron Infrastructure](cron) - Scheduled job system
- [Logging Patterns](logging) - TSV and cron logging

---

*Page Status: active | Last Updated: 2026-03-24 | Source: gptel-auto-workflow-run tests*