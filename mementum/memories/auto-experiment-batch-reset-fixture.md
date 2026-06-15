# Batch Auto-Experiment Tests Need a Shared Reset Fixture

**Date**: 2026-06-15
**Category**: pattern
**Related**: tests/test-gptel-tools-agent-regressions.el, lisp/modules/gptel-tools-agent-error.el, regression/auto-experiment, batch mode

## Insight

Batch-only auto-experiment failures came from leaked globals plus early-exit guards that never show up in isolated runs. A shared reset helper at the top of each regression test makes the file deterministic again. When helper code depends on load order, add a numeric fallback (`or ... 0`) so batch mode cannot trip `wrong-type-argument` on nil.

## Fix Pattern

- Reset the known leakers before each test.
- Neutralize guard thresholds that are only meaningful in live runs.
- Preserve truly environment-dependent tests as descriptive skips instead of letting them flake.

## Test Pattern

Run the focused regression selector in batch, then the full unit gate, and expect zero unexpected failures even if some follow-up cases remain skipped by design.
