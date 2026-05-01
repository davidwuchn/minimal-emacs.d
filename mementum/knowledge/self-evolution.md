---
title: Self-Evolution Patterns
status: active
category: knowledge
tags: [self-evolution, auto-workflow, patterns, verified]
updated: 2026-05-01 14:29
---

# Self-Evolution Knowledge Base

*This is the SINGLE SOURCE OF TRUTH for auto-workflow self-evolution.*
*It synthesizes git history (facts) and benchmark data (verification).*

## Git History Facts

- Active experiment branches: 224
- Historical merges: 566
- Active branches merged: 92
- Active branches abandoned: 132
- Active merge rate: 41.1%

### Target Frequency

- `agent`: 77 experiments
- `loop`: 49 experiments
- `cache`: 31 experiments
- `sandbox`: 11 experiments
- `retry`: 11 experiments
- `projects`: 10 experiments
- `utils`: 9 experiments
- `core`: 8 experiments
- `context`: 6 experiments
- `tools`: 2 experiments
- `strategic`: 2 experiments
- `sanitize`: 2 experiments
- `code`: 2 experiments
- `subagent`: 1 experiments
- `memory`: 1 experiments
- `evolution`: 1 experiments
- `benchmark`: 1 experiments

## Benchmark-Verified Patterns

- **bug-fix**: 22% verified (47/209 experiments)
- **performance**: 17% verified (4/24 experiments)
- **refactoring**: 28% verified (20/71 experiments)
- **safety**: 25% verified (13/51 experiments)

## Actionable Advice for Next Experiments

Based on verified benchmark patterns (sorted by success rate):

1. **refactoring** - 28% kept (71 experiments)
2. **safety** - 25% kept (51 experiments)
3. **bug-fix** - 22% kept (209 experiments)
4. **performance** - 17% kept (24 experiments)

## Critical Guidance for Maximum Success

To ensure your changes are KEPT (not discarded):

1. **Improve BOTH score AND quality** - Changes that improve only one metric often get discarded
2. **Target the weakest keys** - Focus on the specific Eight Keys with lowest scores
3. **Make minimal, focused changes** - Large changes often reduce quality despite good intentions
4. **Verify before submitting** - Run tests and confirm both score and quality improve
5. **Avoid 'safety theater'** - Adding ignore-errors or nil guards that don't fix real bugs reduces quality


## Per-Target Success Patterns

Which change types work best for each target file:

### `gptel-tools-agent.el`

- **refactoring**: 29% (7 experiments)
- **bug-fix**: 22% (37 experiments)
- **safety**: 0% (4 experiments)

### `gptel-agent-loop.el`

- **safety**: 57% (7 experiments)
- **refactoring**: 50% (6 experiments)
- **bug-fix**: 40% (20 experiments)

### `gptel-auto-workflow-strategic.el`

- **safety**: 44% (9 experiments)
- **bug-fix**: 12% (17 experiments)
- **performance**: 0% (3 experiments)

### `staging-merge`

- **other**: 0% (23 experiments)

### `gptel-benchmark-core.el`

- **bug-fix**: 50% (20 experiments)

### `gptel-ext-retry.el`

- **bug-fix**: 7% (14 experiments)
- **refactoring**: 0% (5 experiments)

### `gptel-ext-context-cache.el`

- **bug-fix**: 45% (11 experiments)
- **performance**: 29% (7 experiments)

### `gptel-sandbox.el`

- **safety**: 33% (3 experiments)
- **bug-fix**: 29% (7 experiments)
- **refactoring**: 0% (3 experiments)

### `staging-review`

- **bug-fix**: 0% (12 experiments)

### `staging-verification`

- **other**: 0% (12 experiments)

### `gptel-benchmark-subagent.el`

- **bug-fix**: 0% (10 experiments)

### `gptel-ext-context.el`

- **bug-fix**: 11% (9 experiments)

### `gptel-auto-workflow-projects.el`

- **bug-fix**: 12% (8 experiments)

### `gptel-ext-core.el`

- **safety**: 25% (4 experiments)

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
