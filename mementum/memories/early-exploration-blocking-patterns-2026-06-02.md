## Early-Exploration Blocking Patterns (2026-06-02)

### Critical Path: Executor Context Starvation
Root cause: `strategy-experiment-velocity-context.el` `compress-aggressive` strips all sections except `Task`, `Code under analysis`, `Failure patterns`, `Guidance`. This starves the executor of experiment history, previous outcomes, and strategy context needed to produce actionable improvements.

**Evidence**: 5 consecutive experiments with 0 kept. Same target (`gptel-tools-agent-error.el`) fails identically. Executor receives `;; [Compressed: early-stage focus on core patterns]` annotation but no structured directional guidance about *what* to improve.

### Mitigation Needed
1. **Executor prompt needs**: (a) specific improvement directives per run, (b) previous failure context, (c) concrete code-level guidance
2. **Backend blacklist**: MiniMax `listp` error on model name string serialization - needs automatic detection + blacklist
3. **Strategy evolution cadence**: Every 5 experiments is too slow for early-stage where 0/5 kept. Need faster evolution (every 3 or after 3 consecutive failures)
4. **Tool-error gate**: Targets that repeatedly fail with tool-error should be blocked to avoid budget waste

### Observation
The self-heal retry pattern triggers correctly but can't fix the root issue: the executor doesn't know what to improve. The velocity context strategy's aggressive compression is counterproductive in early exploration because it removes the very context the executor needs to make meaningful changes.