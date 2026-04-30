---
title: Self-Evolution Patterns
status: active
category: knowledge
tags: [self-evolution, auto-workflow, patterns, verified]
updated: 2026-04-30 15:14
---

# Self-Evolution Knowledge Base

*This is the SINGLE SOURCE OF TRUTH for auto-workflow self-evolution.*
*It synthesizes git history (facts) and benchmark data (verification).*

## Git History Facts

- Active experiment branches: 100
- Historical merges: 563
- Active branches merged: 4
- Active branches abandoned: 96
- Active merge rate: 4.0%

### Target Frequency

- `agent`: 38 experiments
- `loop`: 17 experiments
- `cache`: 16 experiments
- `projects`: 8 experiments
- `utils`: 6 experiments
- `core`: 4 experiments
- `context`: 4 experiments
- `sandbox`: 3 experiments
- `retry`: 2 experiments
- `sanitize`: 1 experiments
- `benchmark`: 1 experiments

## Benchmark-Verified Patterns

- **bug-fix**: 21% verified (165/784 experiments)
- **performance**: 37% verified (19/51 experiments)
- **refactoring**: 36% verified (56/156 experiments)
- **safety**: 42% verified (74/175 experiments)

## Actionable Advice for Next Experiments

Based on verified benchmark patterns (sorted by success rate):

1. **safety** - 42% kept (175 experiments)
2. **performance** - 37% kept (51 experiments)
3. **refactoring** - 36% kept (156 experiments)
4. **bug-fix** - 21% kept (784 experiments)

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

- **safety**: 63% (27 experiments)
- **performance**: 25% (8 experiments)
- **bug-fix**: 17% (71 experiments)

### `gptel-agent-loop.el`

- **safety**: 33% (6 experiments)
- **refactoring**: 25% (8 experiments)
- **bug-fix**: 8% (52 experiments)

### `gptel-ext-context-cache.el`

- **refactoring**: 50% (4 experiments)
- **safety**: 50% (4 experiments)
- **performance**: 27% (11 experiments)

### `gptel-benchmark-core.el`

- **bug-fix**: 25% (57 experiments)

### `gptel-ext-retry.el`

- **refactoring**: 60% (5 experiments)
- **bug-fix**: 22% (32 experiments)

### `staging-verification`

- **other**: 0% (37 experiments)

### `gptel-tools-code.el`

- **bug-fix**: 0% (30 experiments)
- **safety**: 0% (5 experiments)

### `staging-merge`

- **other**: 0% (31 experiments)

### `gptel-auto-workflow-strategic.el`

- **refactoring**: 50% (6 experiments)
- **bug-fix**: 4% (25 experiments)

### `staging-review`

- **bug-fix**: 0% (13 experiments)
- **other**: 0% (16 experiments)

### `gptel-auto-workflow-projects.el`

- **bug-fix**: 17% (18 experiments)

### `gptel-ext-core.el`

- **safety**: 57% (14 experiments)

### `gptel-ext-context.el`

- **refactoring**: 50% (6 experiments)
- **bug-fix**: 43% (7 experiments)

### `nucleus-tools.el`

- **safety**: 25% (4 experiments)
- **bug-fix**: 0% (9 experiments)

### `gptel-sandbox.el`

- **refactoring**: 33% (3 experiments)
- **bug-fix**: 22% (9 experiments)

### `gptel-benchmark-integrate.el`

- **bug-fix**: 45% (11 experiments)

### `gptel-workflow-benchmark.el`

- **refactoring**: 67% (3 experiments)
- **bug-fix**: 0% (4 experiments)

### `gptel-benchmark-subagent.el`

- **bug-fix**: 0% (5 experiments)

### `gptel-benchmark-evolution.el`

- **bug-fix**: 0% (4 experiments)

### `gptel-tools.el`

- **refactoring**: 100% (3 experiments)

### `staging-push`

- **other**: 0% (3 experiments)

## Feedback Loop

```
Experiments → Git History → Facts
     ↓            ↓          ↓
Benchmark → Verification → MEMENTUM
     ↑                           ↓
Prompt Injection ← Knowledge ←─┘
```
