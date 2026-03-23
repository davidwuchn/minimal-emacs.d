---
title: Mutation Skill: simplification
phi: 0.50
skill-type: mutation
mutation-type: simplification
applicable-to:
  - retry
  - context
  - code
created: 2026-03-23
---

# Mutation Skill: simplification

## Description

Remove unnecessary complexity, merge redundant code paths.

## Hypothesis Templates

```
"Simplify {logic} by removing {redundancy}"
"Merge {path-a} and {path-b} into unified {path}"
"Remove {unused} to reduce complexity"
```

## When to Apply

- Dead code detected
- Redundant branches exist
- Complexity score is high

## When to Avoid

- Logic serves different purposes
- Simplification breaks edge cases
- Code is already minimal

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