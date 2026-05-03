---
title: Self-Evolution Patterns
status: active
category: knowledge
tags: [self-evolution, auto-workflow, patterns, verified]
updated: 2026-05-03 15:00
---

# Self-Evolution Knowledge Base

*This is the SINGLE SOURCE OF TRUTH for auto-workflow self-evolution.*
*It synthesizes git history (facts) and benchmark data (verification).*

## Git History Facts

- Active experiment branches: 118
- Historical merges: 624
- Active branches merged: 14
- Active branches abandoned: 104
- Active merge rate: 11.9%

### Target Frequency

- `agent`: 31 experiments
- `cache`: 20 experiments
- `loop`: 17 experiments
- `utils`: 8 experiments
- `sandbox`: 8 experiments
- `strategic`: 6 experiments
- `retry`: 5 experiments
- `tests`: 4 experiments
- `projects`: 4 experiments
- `tools`: 2 experiments
- `runtime`: 2 experiments
- `merge`: 2 experiments
- `git`: 2 experiments
- `core`: 2 experiments
- `confirm`: 2 experiments
- `sanitize`: 1 experiments
- `preview`: 1 experiments
- `context`: 1 experiments

## Benchmark-Verified Patterns

- **bug-fix**: 6% verified (5/77 experiments)
- **performance**: 12% verified (2/16 experiments)
- **refactoring**: 0% verified (0/18 experiments)
- **safety**: 14% verified (3/22 experiments)

## Actionable Advice for Next Experiments

Based on verified benchmark patterns (sorted by success rate):

1. **safety** - 14% kept (22 experiments)
2. **performance** - 12% kept (16 experiments)
3. **bug-fix** - 6% kept (77 experiments)
4. **refactoring** - 0% kept (18 experiments)

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

- **bug-fix**: 29% (7 experiments)
- **performance**: 0% (6 experiments)

### `gptel-auto-workflow-strategic.el`

- **bug-fix**: 0% (9 experiments)

### `gptel-benchmark-core.el`

- **bug-fix**: 0% (7 experiments)

### `gptel-auto-workflow-behavioral-tests.el`

- **bug-fix**: 0% (6 experiments)

### `gptel-sandbox.el`

- **bug-fix**: 17% (6 experiments)

### `gptel-ext-retry.el`

- **bug-fix**: 0% (4 experiments)

## Feedback Loop

```
Experiments → Git History → Facts
     ↓            ↓          ↓
Benchmark → Verification → MEMENTUM
     ↑                           ↓
Prompt Injection ← Knowledge ←─┘
```
