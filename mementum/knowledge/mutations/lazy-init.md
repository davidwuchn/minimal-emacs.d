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

Defer initialization until first use to reduce startup cost and memory footprint.

## Hypothesis Templates

```
"Lazy initialize {resource} to defer {cost} until needed"
"Defer {initialization} to first {usage}"
"Wrap {variable} in accessor for on-demand init"
```

## When to Apply

- Resource not always needed
- Initialization is expensive (I/O, computation)
- Startup time matters
- Memory footprint could be reduced

## When to Avoid

- Resource always needed at startup
- First-use latency is critical
- Initialization has side effects that must happen early
- Thread safety concerns

## Eight Keys Impact

| Key | Impact | Why |
|-----|--------|-----|
| λ Efficiency | +high | Defers cost to when needed |
| φ Vitality | +medium | Adapts to actual usage |
| τ Wisdom | +low | Proactive about performance |

## Success History

| Target | Date | Hypothesis | Delta |
|--------|------|------------|-------|
| (pending) | - | - | - |

## Lazy Init Patterns

### 1. Nil-Check Pattern

```elisp
;; Before
(defvar my/resource (expensive-init))

;; After
(defvar my/resource nil)

(defun my/get-resource ()
  (or my/resource
      (setq my/resource (expensive-init))))
```

### 2. Hash Table Lazy Init

```elisp
;; Before
(defvar my/cache (make-hash-table :test 'equal))

;; After
(defvar my/cache nil)

(defun my/get-cache ()
  (or my/cache
      (setq my/cache (make-hash-table :test 'equal))))
```

### 3. Buffer-Local Lazy Init

```elisp
;; Before
(defvar-local my/buffer-cache (make-hash-table))

;; After
(defvar-local my/buffer-cache nil)

(defun my/get-buffer-cache ()
  (or my/buffer-cache
      (setq-local my/buffer-cache (make-hash-table))))
```

## Candidates in Target Files

| File | Variable | Current | Lazy Opportunity |
|------|----------|---------|------------------|
| context.el | `my/gptel--context-window-cache` | ? | Defer until first compact |
| code.el | `my/gptel--usages-cache-initialized` | nil-check | Already lazy |
| retry.el | (check file) | - | - |

## Statistics

| Metric | Value |
|--------|-------|
| Total uses | 0 |
| Success rate | N/A |
| Avg delta | N/A |

## Signal Phrases for Commit

- "Defers initialization of X until..."
- "Lazy initializes Y to reduce..."
- "On-demand init for Z"