---
title: Headless Timeout - Evolution vs Cron Path Divergence
created: 2026-06-03
tags: [auto-workflow, timeout, daemon, evolution]
---

## Problem

All experiments timed out at 480s (300s budget + 180s grace) with 0 kept results.
The timeout configuration was correct in `gptel-auto-workflow-cron-safe` (900s),
but evolution-timer-triggered experiments bypassed cron-safe and used the
default 300s.

## Root Cause

There are two entry points for running experiments:

1. **Cron path**: `bootstrap-run` -> `queue-all-projects` -> `run-all-projects` -> `cron-safe`
   - Sets `gptel-auto-experiment-time-budget 900` ✓
   
2. **Evolution timer path**: `evolution-run-cycle` -> `run-async` (directly)
   - Uses default 300s ✗
   - 300 + 180 grace = 480s hard timeout
   - Executor frequently exceeds 480s on complex targets

## Fix

Added timeout setting to `gptel-auto-workflow-run-async` when
`gptel-auto-workflow-persistent-headless` is true:

```elisp
(when (and (boundp 'gptel-auto-workflow-persistent-headless)
           gptel-auto-workflow-persistent-headless)
  (setq gptel-auto-experiment-time-budget 900))
```

This ensures ALL headless paths (cron + evolution timer + manual async)
use the generous 900s timeout.

## TDD Test

`grader/experiment-timeout-headless` verifies that `run-async` sets
budget to 900 in headless mode.

## Impact

- Executor hard timeout: 480s -> 1080s (900 + 180)
- Experiments now have time to complete multi-step edits
- Keep rate should improve from 0%
