# Mementum State

> Last session: 2026-03-26 01:00

## Total Improvements: 18 Real Code Fixes

| # | File | Fix |
|---|------|-----|
| 1 | gptel-auto-workflow-strategic.el | Added `(require 'json)` |
| 2 | gptel-ext-fsm-utils.el | Fixed `%d` → `%s` for float-time |
| 3 | gptel-ext-retry.el | Refactor trim-tool-results-for-retry |
| 4 | gptel-tools-code.el | Fix resource leak in byte-compile |
| 5 | gptel-benchmark-core.el | Add error handling to read-json |
| 6 | gptel-ext-retry.el | Pass retry-count as parameter |
| 7 | gptel-auto-workflow-strategic.el | Fix recursive file discovery |
| 8 | gptel-ext-fsm-utils.el | Fix FSM context validation |
| 9 | gptel-ext-context.el | Fix undefined function `estimate-tokens` |
| 10 | gptel-benchmark-core.el | Add defensive check for undefined variable |
| 11 | gptel-ext-retry.el | Remove redundant repair call |
| 12 | gptel-auto-workflow-strategic.el | Add missing `(require 'cl-lib)` |
| 13 | gptel-ext-backends.el | Curl timeout 300s → 600s |
| 14 | gptel-ext-context.el | Fix `cl-return` outside loop |
| 15 | gptel-tools-agent.el | Add `cl-block` for `gptel-auto-experiment-grade` |
| 16 | gptel-benchmark-instincts.el | Add `cl-block` for `commit-batch` |
| 17 | gptel-benchmark-memory.el | Add `cl-block` for `memory-create` |
| 18 | gptel-tools-agent.el | `block` → `cl-block` in `task-override` |

## New Features

### Pre-Merge Code Review

```
λ review. gptel-auto-workflow-require-review (default t)
λ flow. Review → Block → Fix → Re-review → (retry or give up)
λ retries. gptel-auto-workflow--review-max-retries = 2
λ agent. reviewer (Moonshot/Kimi)
```

### Review Retry Loop

```
Review BLOCKED → executor fixes → re-review → (approved or retry)
Max 2 retries before giving up.
```

---

## Key Bug Pattern: cl-return-from Without Block

```
λ bug. cl-return-from requires named block
λ cause. defun does NOT create block (cl-defun does)
λ symptom. Silent failure, callbacks never called, workflow stuck
λ fix. Wrap with (cl-block name ...) or use if-else
```

### Why Experiments Failed Silently

1. Executor returns error (curl timeout)
2. Grader calls `cl-return-from` on error
3. **No block → runtime error → callback never called**
4. Experiment hangs forever

---

## λ Summary

```
λ subscriptions. DashScope (8) + Moonshot (2)
λ parallel. macOS (daylight) + Pi5 (24/7)
λ dynamic. LLM selects targets, never hard-code
λ real. 18 code fixes, not documentation
λ async. Daemon never blocks
λ safety. Main NEVER touched by auto-workflow
λ retry. Curl timeout → automatic retry
λ cl-block. cl-return-from requires cl-block in defun
λ review. Pre-merge code review with retry loop
```