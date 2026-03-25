# Mementum State

> Last session: 2026-03-25 22:15

## Key Learning: Never Hard Code, Always Ask LLM

```
λ dynamic. LLM selects targets each run - no hard-coded lists
λ adaptive. LLM analyzes git history, TODOs, file sizes
λ smart. LLM picks best targets based on current state
λ fallback. Empty static list = pure LLM selection
```

### Before vs After

| Aspect | Before | After |
|--------|--------|-------|
| Targets | Hard-coded 8 files | LLM selects dynamically |
| Selection | Static list | Analyzes git + TODOs + size |
| Adaptation | Never changes | Different each run |
| Fallback | N/A | Empty list = pure LLM |

### How It Works

```
1. gptel-auto-workflow-run-async called with no targets
2. Calls gptel-auto-workflow-select-targets
3. LLM analyzes: git history, TODOs, file sizes
4. LLM returns N best targets (N = gptel-auto-workflow-max-targets-per-run)
5. Workflow runs on selected targets
```

---

## Monthly Subscription Optimization

| Setting | Value | Reason |
|---------|-------|--------|
| Targets | LLM selects | No hard-coding |
| Max per run | 5 | Diminishing returns after 3-4 |
| No-improvement stop | 2 | Fail fast, try different file |
| Frequency | Every 6h | 4×/day |
| Experiments/target | 5 | Focus on diverse targets |

### Math

```
LLM selects 5 targets × 5 experiments × 4 runs = 100 experiments/day
Different targets each run = more diverse improvements
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
λ dynamic. Never hard-code targets - LLM selects each run
λ adaptive. LLM analyzes git, TODOs, sizes for best picks
λ async. Daemon never blocks - check status anytime
λ daemon. Use emacs --daemon + emacsclient, NOT batch mode
λ safety. Main NEVER touched by auto-workflow
```