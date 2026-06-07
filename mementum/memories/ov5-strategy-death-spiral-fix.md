---
title: OV5 Strategy Death Spiral — Root Cause and Fix
date: 2026-06-07
tags: [pipeline, strategy, ov5, death-spiral, business-value]
---

## The Problem

The OV5 pipeline ran 140+ experiments with only 1.4% keep-rate (2 kept). Every experiment was "add ONE safety guard" regardless of target or context. The pipeline was burning tokens without producing value.

## Root Causes

1. **Strategy 1-try-and-out**: `gptel-auto-workflow--select-best-strategy` compared new strategies to `template-default` after just 1 trial. Since all experiments scored ~0.4 (the default Eight Keys baseline), new strategies always "underperformed" and were discarded.

2. **Template fixation**: All 4 category prompt templates (`prompt-template-{agentic,programming,tool-calls,natural-language}.md`) had "ADD ONE SAFETY GUARD" as the primary instruction. This produced only nil guards, which are low-value changes that worsen code quality metrics.

3. **Business metrics blind**: The `business_value_score` column in TSV was always 0.00 because `gptel-auto-workflow-production-metrics.el` was never loaded or called. Without business signals, the pipeline couldn't distinguish high-value from low-value changes.

4. **Git divergence**: `git pull --ff-only` in `run-pipeline.sh` always failed because Pi5's local branch diverged from origin. Pi5 was running stale code.

## The Fix

- `strategy-harness.el`: Min 5 trials before comparing to template-default. 70% exploration for under-tried strategies.
- `experiment-core.el`: Rotate to random alternative strategy instead of always template-default.
- All 4 prompt templates v2: Prioritized change types (fix bugs > improve errors > add tests > nil guards).
- `production-metrics.el`: Local business value from error logs, byte-compile warnings, test coverage.
- `run-pipeline.sh`: `git pull --rebase` instead of `--ff-only`.

## Pattern: Death Spiral Detection

When a self-evolving system has a "champion" strategy and all alternatives are compared against it after insufficient trials, the champion's lead grows monotonically. The fix: minimum exploration budget before comparison (multi-armed bandit principle).

## Anti-Pattern: Single-Task Templates

Prompt templates that constrain the agent to ONE task type (e.g., "add nil guards") produce homogeneous, low-value output. Templates must offer a prioritized menu of change types ranked by business impact.
