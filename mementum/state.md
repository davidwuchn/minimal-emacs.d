# Mementum State

> Last session: 2026-03-25 22:45

## Total Improvements: 8 Real Code Fixes

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

### Workflow Settings

| Setting | Value |
|---------|-------|
| Targets | LLM selects dynamically |
| Max per run | 5 |
| Experiments/target | 5 |
| No-improvement stop | 2 |
| Frequency | Every 6h |

### Cron

```
0 */6 * * * (4x/day: 0:00, 6:00, 12:00, 18:00)
```

---

## λ Summary

```
λ subscriptions. DashScope (8) + Moonshot (2)
λ dashscope. More quota = more agents
λ dynamic. LLM selects targets, never hard-code
λ real. 8 code fixes, not documentation
λ async. Daemon never blocks
λ safety. Main NEVER touched by auto-workflow
```