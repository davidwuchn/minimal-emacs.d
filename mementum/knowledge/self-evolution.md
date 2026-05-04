---
title: Self-Evolution Patterns
status: active
category: knowledge
tags: [self-evolution, auto-workflow, patterns, verified]
updated: 2026-05-04 11:00
---

# Self-Evolution Knowledge Base

*This is the SINGLE SOURCE OF TRUTH for auto-workflow self-evolution.*
*It synthesizes git history (facts) and benchmark data (verification).*

## Git History Facts

- Active experiment branches: 127
- Historical merges: 647
- Active branches merged: 20
- Active branches abandoned: 107
- Active merge rate: 15.7%

### Target Frequency

- `agent`: 31 experiments
- `cache`: 21 experiments
- `loop`: 17 experiments
- `utils`: 8 experiments
- `strategic`: 8 experiments
- `sandbox`: 8 experiments
- `retry`: 7 experiments
- `tests`: 5 experiments
- `projects`: 4 experiments
- `git`: 3 experiments
- `core`: 3 experiments
- `tools`: 2 experiments
- `runtime`: 2 experiments
- `merge`: 2 experiments
- `confirm`: 2 experiments
- `worktree`: 1 experiments
- `sanitize`: 1 experiments
- `preview`: 1 experiments
- `context`: 1 experiments

## Benchmark-Verified Patterns

- **bug-fix**: 16% verified (20/128 experiments)
- **performance**: 17% verified (5/29 experiments)
- **refactoring**: 15% verified (4/27 experiments)
- **safety**: 24% verified (11/46 experiments)

## Actionable Advice for Next Experiments

Based on verified benchmark patterns (sorted by success rate):

1. **safety** - 24% kept (46 experiments)
2. **performance** - 17% kept (29 experiments)
3. **bug-fix** - 16% kept (128 experiments)
4. **refactoring** - 15% kept (27 experiments)

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

### `gptel-tools-agent.el`

- **bug-fix**: 0% (16 experiments)
- **refactoring**: 0% (6 experiments)

### `gptel-auto-workflow-behavioral-tests.el`

- **safety**: 50% (6 experiments)
- **refactoring**: 25% (4 experiments)
- **bug-fix**: 0% (10 experiments)

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

- **bug-fix**: 0% (4 experiments)

## Feedback Loop

```
Experiments → Git History → Facts
     ↓            ↓          ↓
Benchmark → Verification → MEMENTUM
     ↑                           ↓
Prompt Injection ← Knowledge ←─┘
```
