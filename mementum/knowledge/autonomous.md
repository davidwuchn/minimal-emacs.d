---
title: Autonomous Research Agent
status: active
category: knowledge
tags: [autonomous, agent, workflow, gptel, research, automation, cron]
---

# Autonomous Research Agent

The Autonomous Research Agent is a self-directed code improvement system that runs experiments without human intervention. It creates worktrees, executes subagents to make improvements, grades the results, benchmarks against metrics, and logs outcomes—all automatically.

## Architecture Overview

The autonomous workflow consists of six sequential stages that form a complete feedback loop:

```
┌─────────────────────────────────────────────────────────────────┐
│                    AUTONOMOUS RESEARCH LOOP                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│   worktree ──→ executor ──→ grader ──→ benchmark ──→ decide ──→ log
│      │           │          │          │            │          │
│      ▼           ▼          ▼          ▼            ▼          │
│   magit      gptel-      LLM       Eight      keep/       TSV
│   worktree   agent       eval      Keys       discard     results
│                                                                  │
│   Duration:   50-80s     10s       10s         <1s         <1s   │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

| Stage | Component | Purpose | Duration |
|-------|-----------|---------|----------|
| 1 | `magit-worktree` | Isolated git branch for experiment | <1s |
| 2 | `gptel-agent--task` | Executor subagent makes code changes | 50-80s |
| 3 | LLM grader | Evaluate change quality via structured prompt | 10s |
| 4 | `gptel-benchmark-grade` | Eight Keys scoring | 10s |
| 5 | Comparator | Decide keep/discard based on score delta | <1s |
| 6 | TSV logger | Record experiment to `results.tsv` | <1s |

## Verified Working Components

### Worktree Creation ✓
```elisp
(require 'magit)
(magit-worktree-create "var/tmp/experiments" "retry-exp1" "HEAD")
```
- Status: **PASS**
- Duration: <1 second
- Creates isolated branch for each experiment
- Clean separation prevents interference between experiments

### Executor Subagent ✓
```elisp
(gptel-agent--task
 "Improve the retry logic in gptel-ext-retry.el"
 :system "You are a code improvement specialist...")
```
- Status: **PASS**
- Duration: 50-80 seconds
- Makes targeted changes (docstrings, refactors, optimizations)
- Output: ~520 characters (hypothesis + changes summary)

### Grader Subagent ✓
```elisp
(gptel-benchmark-grade
 output
 '("hypothesis clearly stated" "change is minimal")
 '("large refactor" "no hypothesis")
 callback)
```
- Status: **PASS**
- Duration: 10 seconds
- Checks 6/6 behavior criteria
- Returns structured JSON with pass/fail per criterion

### Benchmark & Scoring ✓
```elisp
(gptel-benchmark-grade ;; Uses Eight Keys framework
 experiment-output
 hypothesis-changes)
```
- Status: **PASS**
- Duration: 10 seconds
- Returns score between 0.0 and 1.0
- Score delta determines keep/discard decision

### TSV Logging ✓
```
target          hypothesis                     score_before  score_after  decision    duration  grader
gptel-ext-retry.el  Adding docstring for maintainability  1.00         1.00         discarded  100s     6/6 passed
```
- Status: **PASS**
- Location: `var/tmp/experiments/YYYY-MM-DD/results.tsv`

## Known Issues & Fixes

### Issue 1: Grader Subagent Timeout

**Problem:** The grader subagent calls an LLM with no explicit timeout. If the API is slow, the entire experiment hangs indefinitely.

**Root Cause:**
```elisp
;; BROKEN: No timeout handling
(defun gptel-auto-experiment-grade (output callback)
  (gptel-benchmark-grade  ; Can hang forever on slow API
   output
   criteria
   callback))
```

**Solution:** Wrap with `run-with-timer` timeout and fallback to local 
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-qL2ewR.txt. Use Read tool if you need more]...