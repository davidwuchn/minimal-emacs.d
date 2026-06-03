## Pipeline State: 2026-06-02T192002Z-fcea

**Status**: RUNNING (but stalled) — 0 kept, 5 total
**Backend**: kimi-k2.6 (DashScope) + minimax-m2.7-highspeed

### Failed Experiments
1. **exp1** (`gptel-tools-agent-error.el`): tool-error — "aborted by user"
2. **exp2** (`gptel-tools-agent-error.el`): grader-failed — Minimax model gave incomplete output

### Active subagent experiments
- `subagent-neopi5-r192002zfcea-exp1` in optimize/ directory
- Two `error-neopi5-*` experiments that errored out

### Known Issues
- **MiniMax systematic failure**: `Wrong type argument: listp, "qwen3.6-plus"` — backend name string where list expected. Affects serialization of model names.
- **Low keep rate** (~5%): expected for early-exploration stage
- Staging worktree exists but may be stale

### Recommended Actions
1. Blacklist MiniMax backend until listp serialization bug fixed
2. git worktree prune
3. After baseline guards established, shift to refactoring/performance experiments
