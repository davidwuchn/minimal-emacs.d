# ✅ Consecutive Timeout Gate for Experiment Loop

tags: experiment-loop, timeout, stuck-target, retry

## Symptom
Same experiment target (gptel-tools-agent.el, gptel-workflow-benchmark.el) timed out at 800s and was retried 33+ times with no skip logic. Wasted hours of runtime.

## Root Cause
`hard-timeout` experiments in `gptel-tools-agent-experiment-loop.el` logged a message and continued without incrementing the no-improvement counter. No separate timeout counter existed.

## Fix
Added `consecutive-timeouts` counter (threshold=3) in experiment-loop:
- Increments on each hard-timeout result
- Resets on any non-timeout completion
- Stops the loop when threshold reached (same stop condition as no-improvement-count)

## Files Changed
- lisp/modules/gptel-tools-agent-experiment-loop.el: consecutive-timeouts counter + stop gate
