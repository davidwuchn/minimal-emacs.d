# Respect Headless Auto-Approve Defaults

**Date**: 2026-06-15
**Category**: anti-pattern
**Related**: lisp/modules/gptel-auto-workflow-production.el, gptel-tools-agent-research.el, gptel-mementum-headless-auto-approve

## Insight

The evolution runner must not force `gptel-mementum-headless-auto-approve` to `t`. That variable already encodes the intended headless policy: `nil` skips, `draft` saves drafts, and `t` allows direct writes. Overriding it in the scheduler bypasses the safety mode and breaks the regression contract.

## Fix

Let the current value flow through unchanged when calling mementum maintenance.

## Test pattern

Stub `gptel-mementum-build-index`, record the live value, and assert the runner never injects `t`.
