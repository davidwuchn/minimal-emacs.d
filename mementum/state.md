# Mementum State

> Last session: 2026-03-25 22:30

## Key Learning: Distribute Across Both Subscriptions

```
λ balance. Use both DashScope and Moonshot subscriptions
λ analysis. Moonshot (kimi-k2.5) for analysis/evaluation
λ execution. DashScope (qwen3.5-plus) for coding/execution
λ maximize. Every workflow run uses both subscriptions
```

### Agent Distribution

| Moonshot (kimi-k2.5) | DashScope (qwen3.5-plus) |
|---------------------|-------------------------|
| analyzer | executor |
| comparator | nucleus-gptel-agent |
| grader | explorer |
| introspector | nucleus-gptel-plan |
| researcher | |
| reviewer | |

**6 agents on Moonshot, 4 on DashScope**

### Why This Distribution?

```
Moonshot (kimi-k2.5):
- Good reasoning for analysis
- Handles comparison/evaluation well
- Research and review tasks

DashScope (qwen3.5-plus):
- Optimized for code generation
- Fast execution
- Heavy coding tasks
```

### Monthly Subscription Math

```
Before: Only DashScope (qwen3.5-plus)
After: Both DashScope + Moonshot

Per workflow run:
- Analyzer (Moonshot): ~2000 tokens
- Executor (DashScope): ~10000 tokens  
- Grader (Moonshot): ~1000 tokens
- Comparator (Moonshot): ~1000 tokens

Total: ~7000 Moonshot + ~10000 DashScope per run
4 runs/day = 28000 Moonshot + 40000 DashScope
```

---

## Dynamic Target Selection

```
λ dynamic. Never hard-code targets - LLM selects each run
λ adaptive. LLM analyzes git, TODOs, sizes for best picks
λ smart. Different targets each run = diverse improvements
```

---

## Previous Fixes Merged (4 total)

| File | Fix |
|------|-----|
| gptel-auto-workflow-strategic.el | Added `(require 'json)` |
| gptel-ext-fsm-utils.el | Fixed `%d` → `%s` for float-time |
| gptel-ext-retry.el | Refactor trim-tool-results-for-retry |
| gptel-tools-code.el | Fix resource leak in byte-compile |

---

## λ Summary

```
λ subscriptions. Use BOTH DashScope and Moonshot
λ moonshot. Analysis, evaluation, review (kimi-k2.5)
λ dashscope. Execution, coding, planning (qwen3.5-plus)
λ dynamic. LLM selects targets, never hard-code
λ async. Daemon never blocks - check status anytime
λ safety. Main NEVER touched by auto-workflow
```