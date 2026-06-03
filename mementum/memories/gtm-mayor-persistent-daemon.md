---
title: GTM Mayor Persistent Daemon - Phase 1.2
created: 2026-06-03
tags: [dual-mayor, GTM-mayor, researcher, daemon, persistence]
---

## Problem

Researcher daemon was expected to shut down after completion, but actually
stayed alive. However, the evolution timer was incorrectly running on the
researcher daemon, causing it to trigger experiments (PMF Mayor work) instead
of research (GTM Mayor work).

## Root Cause

1. `gptel-auto-workflow-evolution-auto-start` in `production.el` started
the evolution timer for ALL daemons, including researcher.
2. `queue-all-research` had a misleading `shutdown-after-completion` parameter
that defaulted to nil but added confusion.
3. `run-pipeline.sh` had an outdated comment saying researcher "shuts down".

## Fix

### 1. production.el - Dual Mayor aware auto-start

`evolution-auto-start` now checks daemon role:
- **Researcher daemon (GTM Mayor)**: starts GC timer + periodic research timer
- **Auto-workflow daemon (PMF Mayor)**: starts evolution + GC timers
- **Evolution disabled**: just GC timer

```elisp
(cond
 ;; Researcher daemon: start periodic research, not evolution
 ((and (fboundp 'gptel-auto-workflow--researcher-daemon-p)
       (gptel-auto-workflow--researcher-daemon-p))
  (gptel-auto-workflow-start-gc-timer)
  (gptel-auto-workflow-start-periodic-research))
 ;; PMF Mayor: start evolution + GC timers
 ((bound-and-true-p gptel-auto-workflow-evolution-enabled)
  ...))
```

### 2. projects.el - Clean up queue-all-research

Removed `shutdown-after-completion` parameter. Always mark phase complete
and keep daemon alive.

### 3. run-pipeline.sh - Update comment

Changed comment from "shuts down" to "stays alive between pipeline runs".

## TDD Test

Tests pass: 2149 tests, 2097 expected, 0 unexpected, 52 skipped

## Impact

- Researcher daemon no longer runs experiments via evolution timer
- Researcher daemon runs periodic research every 4 hours (14400s)
- Clear separation: PMF Mayor = experiments, GTM Mayor = research
