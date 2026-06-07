# tools agent experiment core

## Purpose

Single experiment execution engine for the auto-workflow. Creates an isolated
git worktree for each experiment, builds the prompt via the selected strategy
(analyzing previous results and baseline), launches the executor agent with
timeout protection, validates all modified files for syntax and diff quality,
handles the full lifecycle: pre-existing breakage detection, duplicate hypothesis
rejection, repeated-focus symbol guarding, executor timeout fast-fail,
provisional commit management, and the analyze→grade→decide pipeline.

## File Stats

- **Lines**: 1915
- **Path**: `lisp/modules/gptel-tools-agent-experiment-core.el`

## Key Functions

| Function | Line | Purpose |
|----------|------|---------|
| `gptel-auto-experiment--pre-existing-breakage-p` | 104 | Check if target was already broken before experiment |
| `gptel-auto-experiment--modified-files` | 135 | List files modified in worktree against HEAD |
| `gptel-auto-experiment--validate-all-modified-files` | 147 | Validate all modified .el files (syntax, boundary guard) |
| `gptel-auto-experiment--maybe-failover-main-backend` | 182 | Switch backend if current is rate-limited |
| `gptel-auto-experiment-run` | 209 | Run single experiment (main entry point, ~530 lines) |

## Experiment Lifecycle

1. **Setup**: Create worktree, check target state, capture backend/model
2. **Precondition check**: Hard block on action preconditions
3. **Analyze**: Analyze previous results for patterns
4. **Build prompt**: Select strategy, build prompt with analysis
5. **Execute**: Launch executor agent with timeout
6. **Post-execute**: Check for stale runs, duplicate hypotheses, repeated focus
7. **Validate**: Syntax check all modified files, diff content validation
8. **Grade**: LLM-based grading with retry
9. **Decide**: Comparator decides keep/discard
10. **Commit**: Create provisional commit, promote or drop

## Dependencies

- `cl-lib`
- `gptel-tools-agent-base` (worktree root, run ID, backend helpers)
- `gptel-tools-agent-prompt-build` (prompt building, KIBC-M axis, logging)
- `gptel-tools-agent-benchmark` (benchmark, analyze, code quality)
- `gptel-tools-agent-experiment-loop` (provisional commits, retry, summarize)
- `gptel-tools-agent-error` (error categorization, grading)
- `gptel-tools-agent-validation` (code validation, diff content)
- `gptel-tools-agent-prompt-analyze` (decide, correctness fix promotion)
- `gptel-tools-agent-worktree` (worktree creation)
- `gptel-tools-agent-staging-merge` (staging flow, push)
- `gptel-tools-agent-subagent` (agent tool execution with timeout)

## Integration Points

- **Experiment loop**: Called by `gptel-auto-experiment-run` which is the core loop entry
- **Strategy harness**: Strategy selection and tracing during prompt building
- **Mementum**: Experiment results recorded as memories via `gptel-auto-workflow--mementum-record-experiment`
- **Token economics**: Tracked via `gptel-token-economics--track-experiment`
- **AI behaviors**: Reasoning patterns parsed from agent output for behavior evolution
- **Think intelligence**: Agent output analyzed for verdict, acts, explores scores

## See Also

- [tools agent prompt build](gptel-tools-agent-prompt-build.md)
- [tools agent strategy harness](gptel-tools-agent-strategy-harness.md)
- [tools agent worktree](gptel-tools-agent-worktree.md)
- [tools agent experiment loop](gptel-tools-agent-experiment-loop.md)
- [tools agent benchmark](gptel-tools-agent-benchmark.md)