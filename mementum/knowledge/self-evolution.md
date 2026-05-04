---
title: Self-Evolution Patterns
status: active
category: knowledge
tags: [self-evolution, auto-workflow, patterns, verified]
updated: 2026-05-04 12:00
---

# Self-Evolution Knowledge Base

*This is the SINGLE SOURCE OF TRUTH for auto-workflow self-evolution.*
*It synthesizes git history (facts) and benchmark data (verification).*

## Git History Facts

- Active experiment branches: 136
- Historical merges: 672
- Active branches merged: 27
- Active branches abandoned: 109
- Active merge rate: 19.9%

### Target Frequency

- `agent`: 31 experiments
- `cache`: 22 experiments
- `loop`: 18 experiments
- `utils`: 8 experiments
- `strategic`: 8 experiments
- `sandbox`: 8 experiments
- `retry`: 7 experiments
- `tests`: 6 experiments
- `projects`: 5 experiments
- `worktree`: 4 experiments
- `git`: 3 experiments
- `core`: 3 experiments
- `tools`: 2 experiments
- `runtime`: 2 experiments
- `merge`: 2 experiments
- `confirm`: 2 experiments
- `benchmark`: 2 experiments
- `sanitize`: 1 experiments
- `preview`: 1 experiments
- `context`: 1 experiments

## Benchmark-Verified Patterns

- **bug-fix**: 17% verified (23/136 experiments)
- **performance**: 17% verified (5/29 experiments)
- **refactoring**: 14% verified (4/28 experiments)
- **safety**: 24% verified (12/49 experiments)

## Actionable Advice for Next Experiments

Based on verified benchmark patterns (sorted by success rate):

1. **safety** - 24% kept (49 experiments)
2. **performance** - 17% kept (29 experiments)
3. **bug-fix** - 17% kept (136 experiments)
4. **refactoring** - 14% kept (28 experiments)

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

- **safety**: 67% (3 experiments)
- **bug-fix**: 25% (16 experiments)
- **performance**: 0% (6 experiments)

### `gptel-auto-workflow-behavioral-tests.el`

- **safety**: 50% (8 experiments)
- **refactoring**: 25% (4 experiments)
- **bug-fix**: 0% (11 experiments)

### `gptel-tools-agent.el`

- **bug-fix**: 0% (16 experiments)
- **refactoring**: 0% (6 experiments)

### `gptel-sandbox.el`

- **bug-fix**: 29% (14 experiments)
- **safety**: 25% (4 experiments)

### `gptel-auto-workflow-strategic.el`

- **refactoring**: 67% (3 experiments)
- **bug-fix**: 0% (10 experiments)

### `gptel-tools-agent-git.el`

- **bug-fix**: 50% (4 experiments)
- **safety**: 40% (5 experiments)
- **refactoring**: 0% (3 experiments)

### `gptel-ext-retry.el`

- **safety**: 67% (3 experiments)
- **bug-fix**: 0% (6 experiments)

### `gptel-benchmark-core.el`

- **bug-fix**: 0% (7 experiments)

### `gptel-tools-agent-worktree.el`

- **bug-fix**: 0% (5 experiments)

### `gptel-workflow-benchmark.el`

- **bug-fix**: 50% (4 experiments)

## Feedback Loop

```
Experiments → Git History → Facts
     ↓            ↓          ↓
Benchmark → Verification → MEMENTUM
     ↑                           ↓
Prompt Injection ← Knowledge ←─┘
```
