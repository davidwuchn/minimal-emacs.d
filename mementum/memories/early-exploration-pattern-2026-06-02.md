## Early-Exploration Stage: June 2 2026

**Pipeline status**: RUNNING (2026-06-02T192002Z-fcea) on DashScope (kimi-k2.6)

### Current Run Results (so far)
- **prompt-build.el** exp1: **kept** (+0.03, 9/9) — validation guards for `validate-candidate-safely`
- **prompt-build.el** exp2: discarded (-0.03) — hash-table caching regressed score
- **prompt-build.el** exp3: discarded (+0.00, tie) — allium-check nil guards (tie → comparator chose A)
- **prompt-build.el** exp4: discarded (-0.03) — select-skill-variant validation regressed
- **fsm-utils.el** exp1: **staging-pending** (+0.03) — fail-fast in fsm-traverse

### Signal: MiniMax systematic failure
`Wrong type argument: listp, "qwen3.6-plus"` — backend name passed where list expected. Affects 4+ targets across many runs. Root cause: serialization issue with `qwen3.6-plus` model name, likely from `gptel-backend-name` returning a string where a list was expected. Needs blacklisting or backend config fix.

### Early exploration patterns observed
1. **Nil-guard saturation**: Most kept/discarded experiments add nil/type validation guards — basic safety net being established
2. **Low keep rate** (~5%): Expected for early-exploration; system building confidence baselines
3. **Staging pipeline fragility**: worktree creation failures, scope-creep blocks, review failures — likely stale worktree state

### Recommended next actions
- Blacklist MiniMax backend until `listp` serialization bug is fixed
- Clean up stale worktrees with `git worktree prune`
- After baseline safety guards are established, shift to higher-value refactoring/performance experiments
