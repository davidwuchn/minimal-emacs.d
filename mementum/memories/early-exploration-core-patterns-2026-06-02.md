## Early-Exploration Core Pattern Focus (2026-06-02)

### Current State
- Pipeline: stalled (0 kept / 5 total experiments)
- Run: 2026-06-02T192002Z-fcea
- Backend issues: MiniMax serialization bug (`listp` error on model name string)
- Strategy: `experiment-velocity-context` at 20% keep rate

### Core Patterns Requiring Attention

1. **Executor Context Injection**: Subagents receive identical "early-exploration" context → can't produce actionable improvements. Need differentiated guidance per task type.

2. **Backend Failover**: MiniMax systematic failure blocks experiments. Need blacklist mechanism + automatic failover to working backends.

3. **Strategy Evolution Trigger**: Every 5 experiments but current strategy underperforming. Need faster evolution cadence in early stage.

4. **Hypothesis Quality Gate**: Placeholder hypotheses slipping through. Need stricter validation before experiment execution.

5. **Validation Retry Loop**: Self-heal retry exists but may not be triggering correctly for early-stage failures.

### Priority Actions
- Seed at least 1 successful experiment per task type (5 types)
- Fix MiniMax backend serialization or blacklist
- Improve executor prompt structure with concrete improvement targets
- Monitor keep rate; evolve strategy if <15% after 10 experiments