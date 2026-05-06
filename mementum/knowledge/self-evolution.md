---
title: Self-Evolution Patterns
status: active
category: knowledge
tags: [self-evolution, auto-workflow, patterns, verified]
updated: 2026-05-06 12:27
---

# Self-Evolution Knowledge Base

*This is the SINGLE SOURCE OF TRUTH for auto-workflow self-evolution.*
*It synthesizes git history (facts) and benchmark data (verification).*

## Git History Facts

- Active experiment branches: 196
- Historical merges: 721
- Active branches merged: 53
- Active branches abandoned: 143
- Active merge rate: 27.0%

### Target Frequency

- `cache`: 40 experiments
- `agent`: 31 experiments
- `loop`: 21 experiments
- `sandbox`: 19 experiments
- `strategic`: 13 experiments
- `retry`: 9 experiments
- `utils`: 8 experiments
- `worktree`: 7 experiments
- `tests`: 6 experiments
- `projects`: 6 experiments
- `git`: 6 experiments
- `sanitize`: 4 experiments
- `merge`: 4 experiments
- `core`: 4 experiments
- `error`: 3 experiments
- `confirm`: 3 experiments
- `benchmark`: 3 experiments
- `baseline`: 3 experiments
- `tools`: 2 experiments
- `runtime`: 2 experiments
- `evolution`: 1 experiments
- `context`: 1 experiments

## Benchmark-Verified Patterns

- **bug-fix**: 25% verified (112/440 experiments)
- **performance**: 24% verified (16/68 experiments)
- **refactoring**: 24% verified (30/123 experiments)
- **safety**: 32% verified (43/134 experiments)

## Actionable Advice for Next Experiments

Based on verified benchmark patterns (sorted by success rate):

1. **safety** - 32% kept (134 experiments)
2. **bug-fix** - 25% kept (440 experiments)
3. **refactoring** - 24% kept (123 experiments)
4. **performance** - 24% kept (68 experiments)

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

- **bug-fix**: 32% (56 experiments)
- **performance**: 30% (10 experiments)
- **safety**: 14% (7 experiments)

### `gptel-agent-loop.el`

- **safety**: 43% (14 experiments)
- **bug-fix**: 36% (36 experiments)
- **refactoring**: 33% (12 experiments)

### `gptel-sandbox.el`

- **safety**: 46% (13 experiments)
- **bug-fix**: 26% (38 experiments)
- **refactoring**: 12% (8 experiments)

### `gptel-tools-agent.el`

- **refactoring**: 29% (7 experiments)
- **bug-fix**: 22% (37 experiments)
- **safety**: 0% (4 experiments)

### `gptel-ext-retry.el`

- **safety**: 38% (8 experiments)
- **bug-fix**: 12% (24 experiments)
- **refactoring**: 0% (5 experiments)

### `gptel-auto-workflow-strategic.el`

- **safety**: 36% (11 experiments)
- **bug-fix**: 17% (23 experiments)
- **performance**: 0% (3 experiments)

### `gptel-benchmark-core.el`

- **bug-fix**: 40% (35 experiments)

### `staging-merge`

- **other**: 0% (26 experiments)

### `gptel-ext-context.el`

- **safety**: 25% (4 experiments)
- **bug-fix**: 15% (13 experiments)

### `gptel-auto-workflow-projects.el`

- **refactoring**: 25% (4 experiments)
- **bug-fix**: 8% (13 experiments)

### `staging-verification`

- **other**: 0% (15 experiments)

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

### `gptel-tools-agent-error.el`

- **bug-fix**: 29% (7 experiments)

### `gptel-ext-core.el`

- **safety**: 25% (4 experiments)
- **bug-fix**: 0% (3 experiments)

### `gptel-workflow-benchmark.el`

- **bug-fix**: 20% (5 experiments)

### `gptel-tools-agent-git.el`

- **bug-fix**: 0% (4 experiments)

### `gptel-tools-agent-staging-baseline.el`

- **bug-fix**: 0% (4 experiments)

### `staging-push`

- **other**: 0% (4 experiments)

### `gptel-tools-agent-strategy-evolver.el`

- **safety**: 33% (3 experiments)

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
