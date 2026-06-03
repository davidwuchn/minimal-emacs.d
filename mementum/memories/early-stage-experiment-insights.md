## Early-Exploration State (2026-06-02T21:55)

### Pipeline Status (run-id `2026-06-02T214934Z-36c2`)
- Status: stopped (not running)
- Targets: 5 targets, only 1 experiment attempted
- Experiment 1: `gptel-tools-agent-error.el` → **tool-error** (executor could not finish)
- Score before: 0.42, Score after: 0.00, delta: -0.42
- Backend: `kimi-k2.6` (moonshot), strategy: `template-default`
- Experiment 2 (`error-neopi5-r214934z36c2-exp2`) was created as retry but pipeline stopped

### Persistent Failure Pattern
- Same target (`gptel-tools-agent-error.el`) fails identically across runs
- Root cause: executor receives "early-exploration" context without structured guidance
- Worktree gets created, FSM initialized, but executor aborts mid-flight
- Three attempts made (worktree re-created each time after stale removal)

### Insight
The self-heal retry pattern (core pattern #3) is triggering but not resolving the core issue: the executor subagent needs more explicit directional guidance about what to improve. The ontology gate (core pattern #2) should perhaps block targets that repeatedly fail with tool-error to avoid wasting budget.