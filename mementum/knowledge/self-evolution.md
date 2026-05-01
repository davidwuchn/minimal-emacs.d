---
title: Self-Evolution Patterns
status: active
category: knowledge
tags: [self-evolution, auto-workflow, patterns, verified]
updated: 2026-05-02 02:27
---

# Self-Evolution Knowledge Base

*This is the SINGLE SOURCE OF TRUTH for auto-workflow self-evolution.*
*It synthesizes git history (facts) and benchmark data (verification).*

## Git History Facts

- Active experiment branches: 99
- Historical merges: 579
- Active branches merged: 7
- Active branches abandoned: 92
- Active merge rate: 7.1%

### Target Frequency

- `agent`: 31 experiments
- `loop`: 16 experiments
- `cache`: 14 experiments
- `utils`: 8 experiments
- `strategic`: 7 experiments
- `sandbox`: 7 experiments
- `projects`: 4 experiments
- `retry`: 3 experiments
- `tools`: 2 experiments
- `core`: 2 experiments
- `confirm`: 2 experiments
- `tests`: 1 experiments
- `sanitize`: 1 experiments
- `context`: 1 experiments

## Benchmark-Verified Patterns

- **bug-fix**: 24% verified (56/229 experiments)
- **performance**: 17% verified (4/24 experiments)
- **refactoring**: 28% verified (22/78 experiments)
- **safety**: 28% verified (18/64 experiments)

## Actionable Advice for Next Experiments

Based on verified benchmark patterns (sorted by success rate):

1. **refactoring** - 28% kept (78 experiments)
2. **safety** - 28% kept (64 experiments)
3. **bug-fix** - 24% kept (229 experiments)
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
- **bug-fix**: 43% (21 experiments)

### `gptel-auto-workflow-strategic.el`

- **safety**: 36% (11 experiments)
- **bug-fix**: 17% (18 experiments)
- **performance**: 0% (3 experiments)

### `staging-merge`

- **other**: 0% (23 experiments)

### `gptel-ext-retry.el`

- **bug-fix**: 6% (17 experiments)
- **refactoring**: 0% (5 experiments)

### `gptel-benchmark-core.el`

- **bug-fix**: 50% (20 experiments)

### `gptel-ext-context-cache.el`

- **bug-fix**: 45% (11 experiments)
- **performance**: 29% (7 experiments)

### `gptel-sandbox.el`

- **safety**: 40% (5 experiments)
- **bug-fix**: 33% (9 experiments)
- **refactoring**: 0% (3 experiments)

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
