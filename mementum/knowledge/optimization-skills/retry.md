---
title: Optimization Skill: retry
phi: 0.50
skill-type: optimization-target
target: lisp/modules/gptel-ext-retry.el
created: 2026-03-23
runs: 5
mutation-skills:
  - mementum/knowledge/mutations/caching.md
  - mementum/knowledge/mutations/lazy-init.md
  - mementum/knowledge/mutations/simplification.md
---

# Optimization Skill: retry

Target: `lisp/modules/gptel-ext-retry.el`

## Current Baseline

| Metric | Value |
|--------|-------|
| Eight Keys | 0.40 |
| Code Quality | 0.50 → 1.00 (improved) |
| Weakest Key | σ Specificity |

## Successful Mutations

| Mutation | Hypothesis | Delta | Date |
|----------|------------|-------|------|
| simplification | Extract error patterns into named constants | Quality +0.50 | 2026-03-25 |

## Failed Mutations

| Mutation | Issue | Date |
|----------|-------|------|
| docstring-enhancement | No hypothesis stated, grader 2/6 | 2026-03-25 |
| adaptive-behavior | No Eight Keys improvement | 2026-03-25 |

## Nightly History

| Date | Experiments | Kept | Score Before | Score After | Best Delta |
|------|-------------|------|--------------|-------------|------------|
| 2026-03-25 | 5 | 0 | 0.40 | 0.40 | 0.00 |

## Key Learnings

1. **Code quality ≠ Eight Keys**: Named constants improved docstring coverage but not signal patterns
2. **Hypothesis required**: Experiments without explicit hypothesis fail grader
3. **Need signal patterns**: To improve Eight Keys, code must contain signal phrases

## Next Hypothesis

Based on weakest key (σ Specificity = 0.40):

```
"Extract magic numbers into named constants with descriptive names"
"Add explicit ASSUMPTIONS section documenting retry criteria"
"Name the backoff algorithm explicitly (exponential-backoff)"
```

## Compounding

| Night | Focus | Result |
|-------|-------|--------|
| 1 | Baseline | σ = 0.40 |
| 2 | Constants | Quality +0.50, σ unchanged |
| 3 | (next) | Target: signal patterns |

## Statistics

| Metric | Value |
|--------|-------|
| Total experiments | 5 |
| Kept | 0 |
| Best quality delta | +0.50 |
| Best Eight Keys delta | 0.00 |