---
title: Self-Evolution Patterns
status: active
category: knowledge
tags: [self-evolution, auto-workflow, patterns, verified]
updated: 2026-05-01 11:01
---

# Self-Evolution Knowledge Base

*This is the SINGLE SOURCE OF TRUTH for auto-workflow self-evolution.*
*It synthesizes git history (facts) and benchmark data (verification).*

## Git History Facts

- Active experiment branches: 155
- Historical merges: 566
- Active branches merged: 23
- Active branches abandoned: 132
- Active merge rate: 14.8%

### Target Frequency

- `agent`: 56 experiments
- `loop`: 33 experiments
- `cache`: 20 experiments
- `utils`: 8 experiments
- `projects`: 8 experiments
- `sandbox`: 6 experiments
- `core`: 6 experiments
- `strategic`: 5 experiments
- `context`: 4 experiments
- `retry`: 3 experiments
- `tools`: 2 experiments
- `confirm`: 2 experiments
- `sanitize`: 1 experiments
- `benchmark`: 1 experiments

## Benchmark-Verified Patterns

- **bug-fix**: 17% verified (234/1413 experiments)
- **performance**: 38% verified (48/127 experiments)
- **refactoring**: 37% verified (120/327 experiments)
- **safety**: 27% verified (90/333 experiments)

## Actionable Advice for Next Experiments

Based on verified benchmark patterns (sorted by success rate):

1. **performance** - 38% kept (127 experiments)
2. **refactoring** - 37% kept (327 experiments)
3. **safety** - 27% kept (333 experiments)
4. **bug-fix** - 17% kept (1413 experiments)

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

- **safety**: 12% (66 experiments)
- **bug-fix**: 7% (426 experiments)
- **other**: 7% (15 experiments)

### `gptel-agent-loop.el`

- **safety**: 38% (24 experiments)
- **performance**: 33% (6 experiments)
- **bug-fix**: 29% (145 experiments)

### `gptel-benchmark-core.el`

- **refactoring**: 70% (10 experiments)
- **safety**: 55% (11 experiments)
- **performance**: 33% (3 experiments)

### `gptel-ext-retry.el`

- **safety**: 33% (9 experiments)
- **refactoring**: 33% (21 experiments)
- **bug-fix**: 23% (106 experiments)

### `gptel-ext-context-cache.el`

- **refactoring**: 57% (7 experiments)
- **performance**: 47% (17 experiments)
- **bug-fix**: 26% (102 experiments)

### `gptel-auto-workflow-strategic.el`

- **refactoring**: 44% (9 experiments)
- **safety**: 30% (10 experiments)
- **bug-fix**: 5% (108 experiments)

### `gptel-tools-code.el`

- **bug-fix**: 6% (52 experiments)
- **refactoring**: 0% (5 experiments)
- **safety**: 0% (9 experiments)

### `gptel-sandbox.el`

- **safety**: 83% (6 experiments)
- **refactoring**: 67% (6 experiments)
- **bug-fix**: 28% (46 experiments)

### `staging-merge`

- **other**: 0% (36 experiments)

### `gptel-workflow-benchmark.el`

- **safety**: 33% (3 experiments)
- **bug-fix**: 18% (22 experiments)
- **refactoring**: 17% (6 experiments)

### `staging-verification`

- **other**: 0% (29 experiments)

### `staging-push`

- **other**: 0% (27 experiments)

### `gptel-benchmark-subagent.el`

- **performance**: 33% (3 experiments)
- **safety**: 0% (3 experiments)
- **bug-fix**: 0% (15 experiments)

### `gptel-auto-workflow-projects.el`

- **refactoring**: 60% (5 experiments)
- **bug-fix**: 12% (16 experiments)

### `staging-review`

- **bug-fix**: 0% (15 experiments)
- **other**: 0% (6 experiments)

### `gptel-ext-context.el`

- **safety**: 20% (5 experiments)
- **bug-fix**: 14% (14 experiments)

### `gptel-ext-tool-sanitize.el`

- **bug-fix**: 50% (10 experiments)
- **refactoring**: 0% (3 experiments)
- **safety**: 0% (4 experiments)

### `nucleus-tools.el`

- **safety**: 23% (13 experiments)
- **bug-fix**: 0% (3 experiments)

### `gptel-ext-fsm-utils.el`

- **safety**: 80% (5 experiments)
- **bug-fix**: 56% (9 experiments)

### `gptel-benchmark-evolution.el`

- **bug-fix**: 0% (9 experiments)

### `gptel-ext-tool-confirm.el`

- **bug-fix**: 0% (6 experiments)

### `gptel-skill-benchmark.el`

- **bug-fix**: 0% (3 experiments)
- **refactoring**: 0% (3 experiments)

### `gptel-tools.el`

- **bug-fix**: 0% (3 experiments)

### `gptel-benchmark-instincts.el`

- **refactoring**: 0% (3 experiments)

### `gptel-ext-context-images.el`

- **refactoring**: 33% (3 experiments)

## Feedback Loop

```
Experiments → Git History → Facts
     ↓            ↓          ↓
Benchmark → Verification → MEMENTUM
     ↑                           ↓
Prompt Injection ← Knowledge ←─┘
```
