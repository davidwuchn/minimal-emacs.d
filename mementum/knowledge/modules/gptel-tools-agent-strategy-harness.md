# tools agent strategy harness

## Purpose

Evolves the prompt-building strategy itself (Meta-Harness style), not just
filling templates. Strategies are stored as files in
`assistant/strategies/prompt-builders/`, registered with metadata, evaluated
against experiment outcomes, and selected based on historical performance
per-target and per-KIBC-M axis. Supports held-out test sets for anti-overfitting,
Pareto frontier tracking of non-dominated strategies, and strategy execution
tracing for debugging.

## File Stats

- **Lines**: 719
- **Path**: `lisp/modules/gptel-tools-agent-strategy-harness.el`

## Key Functions

| Function | Line | Purpose |
|----------|------|---------|
| `gptel-auto-workflow--fresh-start-strategies` | 111 | Clear generated strategies and reset logs for fresh run |
| `gptel-auto-workflow--discover-strategies` | 189 | Discover all available strategies from filesystem |
| `gptel-auto-workflow--load-strategy` | 210 | Load strategy from filesystem with conflict marker guard |
| `gptel-auto-workflow--register-strategy` | 246 | Register strategy with metadata and persist to filesystem |
| `gptel-auto-workflow--persist-strategy-metadata` | 254 | Persist metadata to JSON and auto-commit to git |
| `gptel-auto-workflow--record-strategy-evaluation` | 336 | Record evaluation result to JSONL file |
| `gptel-auto-workflow--get-strategy-performance` | 357 | Get performance statistics (total, kept, success-rate, avg-score) |
| `gptel-auto-workflow--select-best-strategy` | 430 | Select best strategy for target based on historical performance |
| `gptel-auto-workflow--best-strategy-for-axis` | 389 | Find best strategy for a specific KIBC-M axis |
| `gptel-auto-workflow--compute-strategy-frontier` | 592 | Compute Pareto frontier of non-dominated strategies |
| `gptel-auto-workflow--split-targets-search-test` | 665 | Split targets into search/test sets for anti-overfitting |
| `gptel-auto-experiment-build-prompt-with-strategy` | 700 | Build prompt using a specific strategy with fallback |

## Dependencies

- `cl-lib`, `json`, `subr-x`
- `gptel-auto-workflow-ontology-router` (JSON encoding)
- `gptel-auto-workflow-evolution` (parse all results)
- `gptel-tools-agent-base` (project root, results file path)

## Integration Points

- **Experiment core**: `gptel-auto-experiment-run` calls `--select-best-strategy` to pick the strategy
- **Prompt build**: `--build-prompt-with-strategy` is the strategy-aware prompt builder
- **Evaluation recording**: `--record-strategy-evaluation` called after each experiment completes
- **Evolution cycle**: `--fresh-start-strategies` clears evolved strategies for fresh runs
- **Strategy rotation**: Enforces rotation when keep-rate hits 0% with same strategy

## See Also

- [tools agent prompt build](gptel-tools-agent-prompt-build.md)
- [tools agent experiment core](gptel-tools-agent-experiment-core.md)
- [auto workflow evolution](gptel-auto-workflow-evolution.md)