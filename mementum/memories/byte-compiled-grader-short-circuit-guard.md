# Byte-Compiled Grader Short-Circuits Need Explicit Flags

**Date**: 2026-06-16
**Category**: pattern
**Related**: lisp/modules/gptel-tools-agent-benchmark.el, gptel-auto-experiment-grade, cl-block, cl-return-from

## Insight

`cl-block`/`cl-return-from` short-circuits can behave unexpectedly under native byte compilation in Emacs Lisp. For graded callbacks that must stop dispatch immediately, an explicit `short-circuited` flag plus a surrounding `unless` is more robust than relying on `cl-return-from` alone.

## Fix Pattern

- Set a local flag when a short-circuit condition is met.
- Deliver the callback result immediately.
- Guard the downstream dispatch with `unless short-circuited`.

## Test Pattern

Use a regression that proves the grader callback never dispatches after aborted output, even in batch/native-compiled mode.
