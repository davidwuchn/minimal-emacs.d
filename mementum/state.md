# Mementum State

> Last session: 2026-03-25 23:00

## Total Improvements: 12 Real Code Fixes

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

---

## Lessons Learned

### Curl Timeout (Exit Code 28)

```
ERROR: "Curl failed with exit code 28"
CAUSE: API connection timeout (>300s)
FIX: Increase curl timeout or retry
```

### Workflow State Can Get Stuck

```
λ fsm. Long-running executor can leave workflow in "running" state
λ reset. (setq gptel-auto-workflow--running nil) to unstick
λ monitor. Check status after each run completes
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
λ real. 12 code fixes, not documentation
λ async. Daemon never blocks
λ safety. Main NEVER touched by auto-workflow
λ retry. Curl timeout → automatic retry
```