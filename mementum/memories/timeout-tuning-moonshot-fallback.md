---
title: Timeout Tuning for moonshot Fallback
status: active
category: memory
tags: [timeout, moonshot, provider, fallback]
related: []
---

# Timeout Tuning for moonshot Fallback

## Problem

Experiments timed out at 180s when using moonshot/kimi-k2.6 as fallback provider. The executor needs more time for complex code analysis.

## Data

- **180s timeout:** Experiment 3 timed out at 180.0s (gptel-tools-agent.el)
- **240s total:** Experiment 4 timed out at 240s total runtime
- **350s needed:** Experiment completed in 346.5s (gptel-sandbox.el)
- **Result:** 9/9 score when given enough time

## Solution

Increased idle timeout from 180s → 350s:
- `gptel-auto-experiment-time-budget`: 350s
- `gptel-auto-experiment-active-grace`: 60s
- **Max runtime:** 410s total

## Lesson

**Different providers need different timeouts.** MiniMax is fast (completes in ~20s), moonshot is thorough but slow (~350s). When primary provider is exhausted and fallback is slower, increase timeout accordingly.

## Commits

- `a350e0f8` — 180s→300s
- `ace28d1b` — 300s→350s
