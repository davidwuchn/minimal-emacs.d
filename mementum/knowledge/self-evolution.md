---
title: Self-Evolution Patterns
status: active
category: knowledge
tags: [self-evolution, auto-workflow, patterns, verified]
updated: 2026-05-02 01:00
---

# Self-Evolution Knowledge Base

*This is the SINGLE SOURCE OF TRUTH for auto-workflow self-evolution.*
*It synthesizes git history (facts) and benchmark data (verification).*

## Git History Facts

- Active experiment branches: 96
- Historical merges: 578
- Active branches merged: 7
- Active branches abandoned: 89
- Active merge rate: 7.3%

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

- **bug-fix**: 0% verified (0/46 experiments)
- **performance**: 0% verified (0/6 experiments)
- **refactoring**: 0% verified (0/8 experiments)
- **safety**: 0% verified (0/9 experiments)

## Actionable Advice for Next Experiments

Based on verified benchmark patterns (sorted by success rate):

1. **bug-fix** - 0% kept (46 experiments)
2. **performance** - 0% kept (6 experiments)
3. **refactoring** - 0% kept (8 experiments)
4. **safety** - 0% kept (9 experiments)

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
