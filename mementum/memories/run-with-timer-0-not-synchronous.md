---
title: run-with-timer 0 Is NOT Synchronous
date: 2026-05-16
symbol: ❌
---

# run-with-timer 0 Is NOT Synchronous

`(run-with-timer 0 nil callback)` does NOT call the callback immediately. It
schedules it for the next timer event loop iteration. This means:

- Tests that expect synchronous results after calling a function that uses
  `run-with-timer 0 nil` internally will see stale/empty state
- Timer-based retries are stack-safe but introduce asynchrony

**Rule**: Only use `run-with-timer 0` when:
1. The caller is already async (inside a callback that doesn't need results
   before returning)
2. OR the delay is intentionally >0 (inter-experiment delay, rate limiting)

When delay must be 0 AND synchronous behavior is required, use direct `funcall`
if the stack is already safe from other async boundaries (subagent callbacks,
timer-based retries deeper in the chain).
