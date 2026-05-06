---
title: Self-Evolution Patterns
status: active
category: knowledge
tags: [self-evolution, auto-workflow, patterns, verified]
updated: 2026-05-05 11:27
---

# Self-Evolution Knowledge Base

*This is the SINGLE SOURCE OF TRUTH for auto-workflow self-evolution.*
*It synthesizes git history (facts) and benchmark data (verification).*

## Git History Facts

- Active experiment branches: 188
- Historical merges: 694
- Active branches merged: 49
- Active branches abandoned: 139
- Active merge rate: 26.1%

### Target Frequency

- `cache`: 38 experiments
- `agent`: 31 experiments
- `loop`: 20 experiments
- `sandbox`: 19 experiments
- `strategic`: 13 experiments
- `retry`: 9 experiments
- `utils`: 8 experiments
- `worktree`: 7 experiments
- `git`: 6 experiments
- `tests`: 5 experiments
- `projects`: 5 experiments
- `core`: 5 experiments
- `merge`: 4 experiments
- `confirm`: 3 experiments
- `benchmark`: 3 experiments
- `baseline`: 3 experiments
- `tools`: 2 experiments
- `sanitize`: 2 experiments
- `runtime`: 2 experiments
- `evolver`: 1 experiments
- `evolution`: 1 experiments
- `context`: 1 experiments

## Benchmark-Verified Patterns

- **bug-fix**: 27% verified (101/372 experiments)
- **performance**: 24% verified (13/54 experiments)
- **refactoring**: 25% verified (29/114 experiments)
- **safety**: 34% verified (39/115 experiments)

## Actionable Advice for Next Experiments

Based on verified benchmark patterns (sorted by success rate):

1. **safety** - 34% kept (115 experiments)
2. **bug-fix** - 27% kept (372 experiments)
3. **refactoring** - 25% kept (114 experiments)
4. **performance** - 24% kept (54 experiments)

## Critical Guidance for Maximum Success

To ensure your changes are KEPT (not discarded):

1. **Improve BOTH score AND quality** - Changes that improve only one metric often get discarded
2. **Target the weakest keys** - Focus on the specific Eight Keys with lowest scores
3. **Make minimal, focused changes** - Large changes often reduce quality despite good intentions
4. **Verify before submitting** - Run tests and confirm both score and quality improve
5. **Avoid 'safety theater'** - Adding ignore-errors or nil guards that don't fix real bugs reduces quality


## Per-Target Success Patterns

Which change types work best for each target file:

### `gptel-ext-context-cache.el`

- **bug-fix**: 38% (39 experiments)
- **performance**: 30% (10 experiments)
- **safety**: 17% (6 experiments)

### `gptel-agent-loop.el`

- **safety**: 45% (11 experiments)
- **refactoring**: 40% (10 experiments)
- **bug-fix**: 37% (30 experiments)

### `gptel-tools-agent.el`

- **refactoring**: 29% (7 experiments)
- **bug-fix**: 22% (37 experiments)
- **safety**: 0% (4 experiments)

### `gptel-sandbox.el`

- **safety**: 45% (11 experiments)
- **bug-fix**: 33% (27 experiments)
- **refactoring**: 12% (8 experiments)

### `gptel-ext-retry.el`

- **safety**: 38% (8 experiments)
- **bug-fix**: 12% (24 experiments)
- **refactoring**: 0% (5 experiments)

### `gptel-auto-workflow-strategic.el`

- **safety**: 36% (11 experiments)
- **bug-fix**: 17% (18 experiments)
- **performance**: 0% (3 experiments)

### `gptel-benchmark-core.el`

- **bug-fix**: 42% (31 experiments)

### `staging-merge`

- **other**: 0% (25 experiments)

### `gptel-ext-context.el`

- **safety**: 25% (4 experiments)
- **bug-fix**: 15% (13 experiments)

### `gptel-auto-workflow-projects.el`

- **refactoring**: 25% (4 experiments)
- **bug-fix**: 9% (11 experiments)

### `staging-verification`

- **other**: 0% (14 experiments)

### `gptel-auto-workflow-behavioral-tests.el`

- **safety**: 44% (9 experiments)
- **bug-fix**: 0% (4 experiments)

### `staging-review`

- **bug-fix**: 0% (12 experiments)

### `gptel-benchmark-subagent.el`

- **bug-fix**: 0% (10 experiments)

### `gptel-tools-agent-worktree.el`

- **safety**: 50% (4 experiments)
- **bug-fix**: 20% (5 experiments)

### `gptel-workflow-benchmark.el`

- **bug-fix**: 20% (5 experiments)

### `gptel-tools-agent-git.el`

- **bug-fix**: 0% (4 experiments)

### `gptel-tools-agent-staging-baseline.el`

- **bug-fix**: 0% (4 experiments)

### `gptel-ext-core.el`

- **safety**: 25% (4 experiments)

### `staging-push`

- **other**: 0% (4 experiments)

### `gptel-tools-agent-error.el`

- **bug-fix**: 33% (3 experiments)

### `gptel-tools-agent-benchmark.el`

- **bug-fix**: 33% (3 experiments)

### `gptel-ext-fsm.el`

- **bug-fix**: 0% (3 experiments)

### `gptel-tools-grep.el`

- **bug-fix**: 0% (3 experiments)

### `gptel-tools-code.el`

- **bug-fix**: 0% (3 experiments)

## Feedback Loop

```
Experiments → Git History → Facts
     ↓            ↓          ↓
Benchmark → Verification → MEMENTUM
     ↑                           ↓
Prompt Injection ← Knowledge ←─┘
```
