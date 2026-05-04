---
title: Self-Evolution Patterns
status: active
category: knowledge
tags: [self-evolution, auto-workflow, patterns, verified]
updated: 2026-05-04 16:52
---

# Self-Evolution Knowledge Base

*This is the SINGLE SOURCE OF TRUTH for auto-workflow self-evolution.*
*It synthesizes git history (facts) and benchmark data (verification).*

## Git History Facts

- Active experiment branches: 136
- Historical merges: 672
- Active branches merged: 24
- Active branches abandoned: 112
- Active merge rate: 17.6%

### Target Frequency

- `agent`: 31 experiments
- `cache`: 22 experiments
- `loop`: 18 experiments
- `strategic`: 9 experiments
- `utils`: 8 experiments
- `sandbox`: 8 experiments
- `retry`: 7 experiments
- `tests`: 6 experiments
- `projects`: 5 experiments
- `worktree`: 4 experiments
- `git`: 3 experiments
- `core`: 3 experiments
- `tools`: 2 experiments
- `runtime`: 2 experiments
- `merge`: 2 experiments
- `confirm`: 2 experiments
- `sanitize`: 1 experiments
- `preview`: 1 experiments
- `context`: 1 experiments
- `benchmark`: 1 experiments

## Benchmark-Verified Patterns

- **bug-fix**: 19% verified (28/149 experiments)
- **performance**: 18% verified (6/33 experiments)
- **refactoring**: 19% verified (7/37 experiments)
- **safety**: 28% verified (15/54 experiments)

## Actionable Advice for Next Experiments

Based on verified benchmark patterns (sorted by success rate):

1. **safety** - 28% kept (54 experiments)
2. **refactoring** - 19% kept (37 experiments)
3. **bug-fix** - 19% kept (149 experiments)
4. **performance** - 18% kept (33 experiments)

## Critical Guidance for Maximum Success

To ensure your changes are KEPT (not discarded):

1. **Improve BOTH score AND quality** - Changes that improve only one metric often get discarded
2. **Target the weakest keys** - Focus on the specific Eight Keys with lowest scores
3. **Make minimal, focused changes** - Large changes often reduce quality despite good intentions
4. **Verify before submitting** - Run tests and confirm both score and quality improve
5. **Avoid 'safety theater'** - Adding ignore-errors or nil guards that don't fix real bugs reduces quality


## Per-Target Success Patterns

Which change types work best for each target file:

### `gptel-ext-context-cache.el`

- **safety**: 75% (4 experiments)
- **bug-fix**: 22% (18 experiments)
- **performance**: 0% (6 experiments)

### `gptel-auto-workflow-behavioral-tests.el`

- **safety**: 44% (9 experiments)
- **refactoring**: 25% (4 experiments)
- **bug-fix**: 8% (13 experiments)

### `gptel-tools-agent.el`

- **bug-fix**: 0% (16 experiments)
- **refactoring**: 0% (6 experiments)

### `gptel-sandbox.el`

- **bug-fix**: 29% (14 experiments)
- **safety**: 25% (4 experiments)

### `gptel-auto-workflow-strategic.el`

- **refactoring**: 60% (5 experiments)
- **bug-fix**: 0% (10 experiments)

### `gptel-tools-agent-git.el`

- **bug-fix**: 50% (4 experiments)
- **safety**: 40% (5 experiments)
- **refactoring**: 0% (3 experiments)

### `gptel-tools-agent-worktree.el`

- **refactoring**: 25% (4 experiments)
- **bug-fix**: 14% (7 experiments)

### `gptel-workflow-benchmark.el`

- **bug-fix**: 33% (6 experiments)
- **safety**: 33% (3 experiments)

### `gptel-ext-retry.el`

- **safety**: 67% (3 experiments)
- **bug-fix**: 0% (6 experiments)

### `gptel-benchmark-core.el`

- **bug-fix**: 0% (7 experiments)

## Auto-Approved Knowledge Pages

*1 knowledge page(s) auto-approved (trust-but-verify):*

### `gptel-workflow-benchmark-el`

- **Confidence:** 24%
- **Sources:** 4 memories
- **Status:** ⚠ Flagged
- **Warnings:** No code examples or concrete references, Content does not mention topic 'gptel-workflow-benchmark-el'


## Feedback Loop

```
Experiments → Git History → Facts
     ↓            ↓          ↓
Benchmark → Verification → MEMENTUM
     ↑                           ↓
Prompt Injection ← Knowledge ←─┘
```
