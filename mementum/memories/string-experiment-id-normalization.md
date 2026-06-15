# String Experiment IDs Need Numeric Normalization

**Date**: 2026-06-15
**Category**: anti-pattern
**Related**: gptel-auto-workflow-production.el, gptel-tools-agent-prompt-build.el, experiment-complete-hook, exp-001

## Insight

Experiment ids are not always integers; many arrive as strings like `exp-001`. Any gate that uses `%`, `>`, or `zerop` on `:id` must normalize the raw value first. Otherwise the daemon can crash with `wrong-type-argument number-or-marker-p`, which then feeds the restart loop.

## Fix

Normalize the id once:
- numeric id -> keep/round it
- string id -> extract digits
- nil / no digits -> 0

## Test pattern

Stub hook side effects, call the hook with `(:id "exp-001")`, and assert no error plus the expected numeric branch behavior.
