---
title: Self-Evolution Patterns
status: active
category: knowledge
tags: [self-evolution, auto-workflow, patterns, verified]
updated: 2026-04-30 10:37
---

# Self-Evolution Knowledge Base

*This is the SINGLE SOURCE OF TRUTH for auto-workflow self-evolution.*
*It synthesizes git history (facts) and benchmark data (verification).*

## Git History Facts

- Active experiment branches: 211
- Historical merges: 546
- Active branches merged: 90
- Active branches abandoned: 121
- Active merge rate: 42.7%

### Target Frequency

- `agent`: 76 experiments
- `loop`: 45 experiments
- `cache`: 31 experiments
- `retry`: 11 experiments
- `sandbox`: 10 experiments
- `projects`: 10 experiments
- `utils`: 9 experiments
- `context`: 6 experiments
- `core`: 5 experiments
- `sanitize`: 2 experiments
- `code`: 2 experiments
- `subagent`: 1 experiments
- `memory`: 1 experiments
- `evolution`: 1 experiments
- `benchmark`: 1 experiments

## Benchmark-Verified Patterns

- **bug-fix**: 24% verified (45/191 experiments)
- **performance**: 18% verified (4/22 experiments)
- **refactoring**: 31% verified (20/65 experiments)
- **safety**: 27% verified (12/45 experiments)

## Actionable Advice for Next Experiments

Based on verified benchmark patterns (sorted by success rate):

1. **refactoring** - 31% kept (65 experiments)
2. **safety** - 27% kept (45 experiments)
3. **bug-fix** - 24% kept (191 experiments)
4. **performance** - 18% kept (22 experiments)

## Per-Target Success Patterns

Which change types work best for each target file:

### `gptel-tools-agent.el`

- **refactoring**: 40% (5 experiments)
- **bug-fix**: 23% (35 experiments)

### `gptel-agent-loop.el`

- **safety**: 67% (6 experiments)
- **refactoring**: 50% (6 experiments)
- **bug-fix**: 47% (17 experiments)

### `gptel-auto-workflow-strategic.el`

- **safety**: 38% (8 experiments)
- **bug-fix**: 12% (16 experiments)
- **performance**: 0% (3 experiments)

### `staging-merge`

- **other**: 0% (23 experiments)

### `gptel-ext-retry.el`

- **bug-fix**: 7% (14 experiments)
- **refactoring**: 0% (5 experiments)

### `gptel-benchmark-core.el`

- **bug-fix**: 53% (17 experiments)

### `gptel-ext-context-cache.el`

- **bug-fix**: 56% (9 experiments)
- **performance**: 29% (7 experiments)

### `gptel-sandbox.el`

- **safety**: 33% (3 experiments)
- **bug-fix**: 29% (7 experiments)
- **refactoring**: 0% (3 experiments)

### `staging-review`

- **bug-fix**: 0% (12 experiments)

### `gptel-benchmark-subagent.el`

- **bug-fix**: 0% (10 experiments)

### `gptel-ext-context.el`

- **bug-fix**: 11% (9 experiments)

### `gptel-auto-workflow-projects.el`

- **bug-fix**: 14% (7 experiments)

### `gptel-ext-core.el`

- **safety**: 25% (4 experiments)

### `gptel-ext-fsm.el`

- **bug-fix**: 0% (3 experiments)

### `gptel-tools-grep.el`

- **bug-fix**: 0% (3 experiments)

### `gptel-tools-code.el`

- **bug-fix**: 0% (3 experiments)

### `staging-verification`

- **other**: 0% (3 experiments)

## Feedback Loop

```
Experiments → Git History → Facts
     ↓            ↓          ↓
Benchmark → Verification → MEMENTUM
     ↑                           ↓
Prompt Injection ← Knowledge ←─┘
```
