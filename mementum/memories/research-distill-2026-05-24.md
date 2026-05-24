# Research Distillation: 2026-05-24

## Priority Gaps (Local Analysis)

| Component | Gap | Severity |
|-----------|-----|----------|
| `gptel-agent-loop.el` | No circuit breaker, no mid-session guidance injection | HIGH |
| `gptel-auto-workflow-mementum.el` | No SQLite FTS5; relies on grep | MEDIUM |
| `gptel-sandbox.el` | Large output interception incomplete | MEDIUM |

## Quick Wins from External Patterns

1. **Circuit breaker** — Track per-tool failures, exponential backoff. Add to `gptel-agent-loop.el`.
2. **Verification hook** — `byte-compile` + `checkdoc` every ELisp change before accepting.
3. **FTS5 session memory** — Replace mementum grep with SQLite FTS5 for cross-session recall.
4. **Mid-session guidance injection** — Rewrite pending prompt mid-turn without aborting.

## Higher-Effort Patterns (Defer)

- FormalPlanner / probabilistic branching — requires FSM overhaul
- Git worktree isolation — complex infra
- Meta-prompt bandit selector — needs offline training data
- DreamCycle idle consolidation — low urgency
