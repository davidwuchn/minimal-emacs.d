---
title: Mutation Skill: lazy-init
phi: 0.50
skill-type: mutation
mutation-type: lazy-initialization
applicable-to:
  - retry
  - context
  - code
created: 2026-03-23
---

# Mutation Skill: lazy-init

## Description

Defer initialization until first use to reduce startup cost.

## Hypothesis Templates

```
"Lazy initialize {resource} to defer {cost} until needed"
"Defer {initialization} to first {usage}"
"Wrap {variable} in lazy-{pattern} for on-demand init"
```

## When to Apply

- Resource not always needed
- Initialization is expensive
- Startup time matters

## When to Avoid

- Resource always needed
- First-use latency is critical
- Initialization has side effects

## Success History

| Target | Date | Hypothesis | Delta |
|--------|------|------------|-------|
| (none yet) | - | - | - |

## Statistics

| Metric | Value |
|--------|-------|
| Total uses | 0 |
| Success rate | N/A |
| Avg delta | N/A |