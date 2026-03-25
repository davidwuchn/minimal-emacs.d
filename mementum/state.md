# Mementum State

> Last session: 2026-03-26 00:30

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

## Lessons Learned

### Curl Timeout (Exit Code 28)

```
ERROR: "Curl failed with exit code 28"
CAUSE: API connection timeout (>300s)
FIX: Increase curl timeout to 600s
```

### Workflow State Can Get Stuck

```
λ fsm. Long-running executor can leave workflow in "running" state
λ reset. (setq gptel-auto-workflow--running nil) to unstick
λ monitor. Check status after each run completes
```

### cl-return-from Anti-Pattern

```
λ rule. defun + cl-return-from = BUG
λ detect. grep -rn "cl-return" | grep -v "cl-defun"
λ fix. Add cl-block wrapper or use if-else
```

---

## Final Configuration

### Agent Distribution (DashScope has more quota)

| DashScope (8 agents) | Moonshot (2 agents) |
|----------------------|---------------------|
| analyzer | researcher |
| comparator | reviewer |
| executor | |
| explorer | |
| grader | |
| introspector | |
| nucleus-gptel-agent | |
| nucleus-gptel-plan | |

### Parallel Setup

| Machine | Schedule | Runs/Day |
|---------|----------|----------|
| macOS | 10AM, 2PM, 6PM | 3 |
| Pi5 | 11PM, 3AM, 7AM, 11AM, 3PM, 7PM | 6 |
| **Total** | | **9** |

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
```