---
title: Self-Evolution Patterns
status: active
category: knowledge
tags: [self-evolution, auto-workflow, patterns, verified]
updated: 2026-05-03 23:00
---

# Self-Evolution Knowledge Base

*This is the SINGLE SOURCE OF TRUTH for auto-workflow self-evolution.*
*It synthesizes git history (facts) and benchmark data (verification).*

## Git History Facts

- Active experiment branches: 123
- Historical merges: 647
- Active branches merged: 20
- Active branches abandoned: 103
- Active merge rate: 16.3%

### Target Frequency

- `agent`: 31 experiments
- `cache`: 21 experiments
- `loop`: 17 experiments
- `utils`: 8 experiments
- `strategic`: 8 experiments
- `sandbox`: 7 experiments
- `retry`: 7 experiments
- `tests`: 4 experiments
- `projects`: 4 experiments
- `core`: 3 experiments
- `tools`: 2 experiments
- `runtime`: 2 experiments
- `merge`: 2 experiments
- `git`: 2 experiments
- `confirm`: 2 experiments
- `sanitize`: 1 experiments
- `preview`: 1 experiments
- `context`: 1 experiments

## Benchmark-Verified Patterns

- **bug-fix**: 8% verified (7/90 experiments)
- **performance**: 12% verified (2/17 experiments)
- **refactoring**: 10% verified (2/21 experiments)
- **safety**: 19% verified (6/31 experiments)

## Actionable Advice for Next Experiments

Based on verified benchmark patterns (sorted by success rate):

1. **safety** - 19% kept (31 experiments)
2. **performance** - 12% kept (17 experiments)
3. **refactoring** - 10% kept (21 experiments)
4. **bug-fix** - 8% kept (90 experiments)

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

- **bug-fix**: 0% (16 experiments)
- **refactoring**: 0% (6 experiments)

### `gptel-ext-context-cache.el`

- **bug-fix**: 22% (9 experiments)
- **performance**: 0% (6 experiments)

### `gptel-auto-workflow-strategic.el`

- **refactoring**: 67% (3 experiments)
- **bug-fix**: 0% (10 experiments)

### `gptel-sandbox.el`

- **safety**: 33% (3 experiments)
- **bug-fix**: 14% (7 experiments)

### `gptel-ext-retry.el`

- **safety**: 67% (3 experiments)
- **bug-fix**: 0% (6 experiments)

### `gptel-benchmark-core.el`

- **bug-fix**: 0% (7 experiments)

### `gptel-auto-workflow-behavioral-tests.el`

- **bug-fix**: 0% (6 experiments)

## Feedback Loop

```
Experiments → Git History → Facts
     ↓            ↓          ↓
Benchmark → Verification → MEMENTUM
     ↑                           ↓
Prompt Injection ← Knowledge ←─┘
```
