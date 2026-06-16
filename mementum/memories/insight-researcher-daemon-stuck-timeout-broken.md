---
title: "Researcher daemon stuck 2+ hours, pipeline timeout broken"
date: 2026-06-16
tags: [pipeline, timeout, daemon, researcher, critical, operational]
symbol: ⊘
---

# Researcher daemon stuck 2+ hours, pipeline timeout broken

## Problem
Pipeline stuck at "Waiting for research to complete" for 2+ hours (since 19:08). Max wait is 900s (15 minutes) but timeout never triggered. Researcher daemon (gtm-product-org) running for 2h14m without producing findings. Pipeline process exited but daemon kept running.

## Root Causes
1. **Pipeline timeout mechanism broken** — `wait-for-idle!` in `clj/ov5/pipeline/daemon.clj` not enforcing 900s timeout
2. **Researcher subagent stuck** — LLM call hanging or infinite loop in research logic
3. **No daemon cleanup on pipeline exit** — Pipeline exits but daemon keeps running
4. **No watchdog for long-running sessions** — No mechanism to detect and kill stuck researchers

## Impact
- Pipeline has not produced experiments since 18:31 (zero-run)
- Multiple pipeline runs stuck at research phase
- Resources wasted on stuck daemons
- No research findings generated for 2+ hours

## Immediate Fix
Killed stuck daemon manually: `pkill -f "gtm-product-org"`

## Next Steps (Critical)
1. **Fix pipeline timeout** — Debug `wait-for-idle!` in `clj/ov5/pipeline/daemon.clj`, ensure 900s timeout is enforced
2. **Add daemon cleanup** — Kill researcher daemon when pipeline exits (success or failure)
3. **Add watchdog** — Monitor researcher session duration, kill if > 1800s (30 min)
4. **Investigate researcher hang** — Check if LLM call timing out, infinite loop in AutoTTS controller, or subagent dispatch issue
5. **Consider Fusion self-fusion** — Lowest-effort improvement from Fusion study (6.7pt boost proven)

## Lessons Learned
- Pipeline timeout mechanisms must be tested under failure conditions
- Daemon lifecycle must be tied to pipeline lifecycle
- Long-running subagents need watchdog timers
- Research quality improvements (Fusion, auto-research) are secondary to operational stability
