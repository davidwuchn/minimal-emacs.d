---
title: Mutation Skill: caching
phi: 0.50
skill-type: mutation
mutation-type: caching
applicable-to:
  - retry
  - context
  - code
created: 2026-03-23
---

# Mutation Skill: caching

## Description

Add caching to avoid redundant computation or lookups.

## Hypothesis Templates

```
"Add caching to {component} to reduce redundant {operation}"
"Cache {result} to avoid recomputing {input}"
"Memoize {function} for {scenario}"
```

## When to Apply

- Repeated lookups detected
- Same computation called multiple times
- Results don't change within session

## When to Avoid

- Data changes frequently
- Cache invalidation is complex
- Memory is constrained

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