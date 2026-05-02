---
title: Self-Evolution Patterns
status: active
category: knowledge
tags: [self-evolution, auto-workflow, patterns, verified]
updated: 2026-05-02 08:00
---

# Self-Evolution Knowledge Base

*This is the SINGLE SOURCE OF TRUTH for auto-workflow self-evolution.*
*It synthesizes git history (facts) and benchmark data (verification).*

## Git History Facts

- Active experiment branches: 171
- Historical merges: 585
- Active branches merged: 24
- Active branches abandoned: 147
- Active merge rate: 14.0%

### Target Frequency

- `agent`: 56 experiments
- `loop`: 34 experiments
- `cache`: 24 experiments
- `utils`: 8 experiments
- `projects`: 8 experiments
- `strategic`: 6 experiments
- `sandbox`: 6 experiments
- `core`: 6 experiments
- `retry`: 5 experiments
- `context`: 4 experiments
- `tools`: 2 experiments
- `tests`: 2 experiments
- `runtime`: 2 experiments
- `merge`: 2 experiments
- `git`: 2 experiments
- `confirm`: 2 experiments
- `sanitize`: 1 experiments
- `benchmark`: 1 experiments

## Benchmark-Verified Patterns

- **bug-fix**: 6% verified (17/268 experiments)
- **performance**: 19% verified (6/32 experiments)
- **refactoring**: 15% verified (8/54 experiments)
- **safety**: 11% verified (7/61 experiments)

## Actionable Advice for Next Experiments

Based on verified benchmark patterns (sorted by success rate):

1. **performance** - 19% kept (32 experiments)
2. **refactoring** - 15% kept (54 experiments)
3. **safety** - 11% kept (61 experiments)
4. **bug-fix** - 6% kept (268 experiments)

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

- **bug-fix**: 1% (77 experiments)
- **refactoring**: 0% (16 experiments)
- **safety**: 0% (9 experiments)

### `gptel-ext-context-cache.el`

- **performance**: 31% (13 experiments)
- **refactoring**: 29% (7 experiments)
- **safety**: 25% (8 experiments)

### `gptel-agent-loop.el`

- **safety**: 25% (8 experiments)
- **bug-fix**: 19% (32 experiments)
- **other**: 0% (3 experiments)

### `gptel-auto-workflow-strategic.el`

- **safety**: 0% (4 experiments)
- **bug-fix**: 0% (25 experiments)

### `gptel-ext-retry.el`

- **performance**: 33% (3 experiments)
- **refactoring**: 25% (4 experiments)
- **bug-fix**: 11% (18 experiments)

### `gptel-benchmark-core.el`

- **bug-fix**: 0% (21 experiments)

### `staging-verification`

- **other**: 0% (17 experiments)

### `gptel-sandbox.el`

- **bug-fix**: 0% (14 experiments)

### `gptel-workflow-benchmark.el`

- **refactoring**: 0% (3 experiments)
- **bug-fix**: 0% (5 experiments)

### `gptel-ext-context.el`

- **bug-fix**: 0% (7 experiments)

### `gptel-ext-tool-confirm.el`

- **bug-fix**: 0% (6 experiments)

### `staging-merge`

- **other**: 0% (5 experiments)

### `gptel-auto-workflow-projects.el`

- **bug-fix**: 20% (5 experiments)

### `gptel-auto-workflow-behavioral-tests.el`

- **bug-fix**: 0% (3 experiments)

## Feedback Loop

```
Experiments → Git History → Facts
     ↓            ↓          ↓
Benchmark → Verification → MEMENTUM
     ↑                           ↓
Prompt Injection ← Knowledge ←─┘
```
