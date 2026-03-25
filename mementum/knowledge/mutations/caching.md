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
"Lazy initialize {resource} to defer {cost} until needed"
```

## When to Apply

- Repeated lookups detected
- Same computation called multiple times
- Results don't change within session
- Startup time could be improved

## When to Avoid

- Data changes frequently
- Cache invalidation is complex
- Memory is constrained
- Results are already fast (<1ms)

## Eight Keys Impact

| Key | Impact | Why |
|-----|--------|-----|
| λ Efficiency | +high | Reduces redundant work |
| φ Vitality | +medium | Adapts by memoizing common cases |
| ρ Robustness | +low | Same result = consistent |

## Success History

| Target | Date | Hypothesis | Delta |
|--------|------|------------|-------|
| (pending) | - | - | - |

## Retry.el Candidates

Functions that could benefit from caching:

| Function | Current | Cache Opportunity |
|----------|---------|-------------------|
| `my/gptel--transient-error-p` | Compiles regex each call | Cache compiled patterns |
| `my/gptel--should-retry-p` | Checks conditions | Cache decision for same input |
| `my/gptel--backoff-delay` | Calculates each time | Cache for same retry count |

## Statistics

| Metric | Value |
|--------|-------|
| Total uses | 0 |
| Success rate | N/A |
| Avg delta | N/A |

## Implementation Pattern

```elisp
;; Before
(defun my/function (arg)
  (expensive-operation arg))

;; After
(defvar my/function--cache (make-hash-table :test 'equal))

(defun my/function (arg)
  (or (gethash arg my/function--cache)
      (puthash arg (expensive-operation arg) my/function--cache)))
```