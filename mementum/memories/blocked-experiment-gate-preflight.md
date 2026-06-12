💡 blocked-experiment-gate-preflight

## Problem
Evolution treated “no new experiments” as a trigger success even when the human-decision gate blocked `run-async`, so logs reported progress that never actually started.

## Root Cause
`gptel-auto-workflow-evolution-run-cycle` launched `gptel-auto-workflow-run-async` without preflighting `gptel-auto-workflow--pending-decisions-p`.
`gptel-auto-workflow-run-async` also used `(eq t ...)` instead of truthiness.

## Fix
Preflight the gate in evolution, persist blocked status/hints, return `blocked-pending-decisions`, and use truthiness in the gate check.

## Key Insight
A launch gate must be checked at the control point that decides to start work; otherwise a blocked launch looks like success to upstream self-evolution.

## Files
- lisp/modules/gptel-auto-workflow-evolution.el
- lisp/modules/gptel-tools-agent-main.el
- tests/test-evolution-timeout.el
