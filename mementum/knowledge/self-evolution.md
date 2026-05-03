---
title: Self-Evolution Patterns
status: active
category: knowledge
tags: [self-evolution, auto-workflow, patterns, verified]
updated: 2026-05-03 16:27
---

# Self-Evolution Knowledge Base

*This is the SINGLE SOURCE OF TRUTH for auto-workflow self-evolution.*
*It synthesizes git history (facts) and benchmark data (verification).*

## Git History Facts

- Active experiment branches: 133
- Historical merges: 624
- Active branches merged: 21
- Active branches abandoned: 112
- Active merge rate: 15.8%

### Target Frequency

- `agent`: 31 experiments
- `cache`: 25 experiments
- `loop`: 16 experiments
- `sandbox`: 13 experiments
- `utils`: 8 experiments
- `strategic`: 8 experiments
- `retry`: 7 experiments
- `projects`: 5 experiments
- `tests`: 3 experiments
- `git`: 3 experiments
- `core`: 3 experiments
- `tools`: 2 experiments
- `runtime`: 2 experiments
- `merge`: 2 experiments
- `confirm`: 2 experiments
- `sanitize`: 1 experiments
- `context`: 1 experiments
- `benchmark`: 1 experiments

## Benchmark-Verified Patterns

- **bug-fix**: 25% verified (71/280 experiments)
- **performance**: 15% verified (4/27 experiments)
- **refactoring**: 26% verified (23/90 experiments)
- **safety**: 28% verified (23/82 experiments)

## Actionable Advice for Next Experiments

Based on verified benchmark patterns (sorted by success rate):

1. **safety** - 28% kept (82 experiments)
2. **refactoring** - 26% kept (90 experiments)
3. **bug-fix** - 25% kept (280 experiments)
4. **performance** - 15% kept (27 experiments)

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

- **safety**: 44% (9 experiments)
- **refactoring**: 44% (9 experiments)
- **bug-fix**: 43% (23 experiments)

### `gptel-ext-retry.el`

- **safety**: 50% (6 experiments)
- **bug-fix**: 9% (23 experiments)
- **refactoring**: 0% (5 experiments)

### `gptel-auto-workflow-strategic.el`

- **safety**: 36% (11 experiments)
- **bug-fix**: 17% (18 experiments)
- **performance**: 0% (3 experiments)

### `gptel-ext-context-cache.el`

- **bug-fix**: 43% (23 experiments)
- **performance**: 29% (7 experiments)

### `gptel-sandbox.el`

- **bug-fix**: 36% (14 experiments)
- **safety**: 29% (7 experiments)
- **refactoring**: 0% (4 experiments)

### `gptel-benchmark-core.el`

- **bug-fix**: 46% (24 experiments)

### `staging-merge`

- **other**: 0% (23 experiments)

### `gptel-ext-context.el`

- **safety**: 25% (4 experiments)
- **bug-fix**: 15% (13 experiments)

### `staging-review`

- **bug-fix**: 0% (12 experiments)

### `staging-verification`

- **other**: 0% (12 experiments)

### `gptel-benchmark-subagent.el`

- **bug-fix**: 0% (10 experiments)

### `gptel-auto-workflow-projects.el`

- **bug-fix**: 11% (9 experiments)

### `gptel-auto-workflow-behavioral-tests.el`

- **safety**: 50% (4 experiments)

### `gptel-ext-core.el`

- **safety**: 25% (4 experiments)

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
