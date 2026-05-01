---
title: Self-Evolution Patterns
status: active
category: knowledge
tags: [self-evolution, auto-workflow, patterns, verified]
updated: 2026-05-02 01:08
---

# Self-Evolution Knowledge Base

*This is the SINGLE SOURCE OF TRUTH for auto-workflow self-evolution.*
*It synthesizes git history (facts) and benchmark data (verification).*

## Git History Facts

- Active experiment branches: 100
- Historical merges: 579
- Active branches merged: 4
- Active branches abandoned: 96
- Active merge rate: 4.0%

### Target Frequency

- `agent`: 31 experiments
- `loop`: 16 experiments
- `cache`: 15 experiments
- `utils`: 8 experiments
- `strategic`: 7 experiments
- `sandbox`: 5 experiments
- `projects`: 4 experiments
- `tools`: 2 experiments
- `retry`: 2 experiments
- `core`: 2 experiments
- `confirm`: 2 experiments
- `sanitize`: 1 experiments
- `context`: 1 experiments

## Benchmark-Verified Patterns

- **bug-fix**: 21% verified (173/833 experiments)
- **performance**: 35% verified (19/54 experiments)
- **refactoring**: 33% verified (58/174 experiments)
- **safety**: 40% verified (79/197 experiments)

## Actionable Advice for Next Experiments

Based on verified benchmark patterns (sorted by success rate):

1. **safety** - 40% kept (197 experiments)
2. **performance** - 35% kept (54 experiments)
3. **refactoring** - 33% kept (174 experiments)
4. **bug-fix** - 21% kept (833 experiments)

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

- **safety**: 45% (29 experiments)
- **refactoring**: 25% (16 experiments)
- **performance**: 22% (9 experiments)

### `gptel-ext-tool-sanitize.el`

- **safety**: 47% (34 experiments)
- **other**: 33% (6 experiments)
- **performance**: 33% (6 experiments)

### `gptel-ext-fsm-utils.el`

- **safety**: 58% (31 experiments)
- **performance**: 25% (8 experiments)
- **bug-fix**: 17% (72 experiments)

### `gptel-agent-loop.el`

- **safety**: 25% (12 experiments)
- **refactoring**: 22% (9 experiments)
- **bug-fix**: 8% (52 experiments)

### `gptel-ext-context-cache.el`

- **refactoring**: 60% (5 experiments)
- **safety**: 50% (4 experiments)
- **performance**: 25% (12 experiments)

### `gptel-benchmark-core.el`

- **bug-fix**: 25% (57 experiments)

### `staging-verification`

- **other**: 0% (56 experiments)

### `gptel-ext-retry.el`

- **refactoring**: 50% (6 experiments)
- **safety**: 33% (3 experiments)
- **bug-fix**: 18% (40 experiments)

### `gptel-auto-workflow-strategic.el`

- **bug-fix**: 0% (9 experiments)

### `gptel-benchmark-core.el`

- **bug-fix**: 0% (7 experiments)

### `gptel-ext-retry.el`

- **bug-fix**: 0% (3 experiments)

### `gptel-ext-context-cache.el`

- **performance**: 0% (3 experiments)

## Feedback Loop

```
Experiments → Git History → Facts
     ↓            ↓          ↓
Benchmark → Verification → MEMENTUM
     ↑                           ↓
Prompt Injection ← Knowledge ←─┘
```