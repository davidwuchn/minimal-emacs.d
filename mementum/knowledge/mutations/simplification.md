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

Remove unnecessary complexity, merge redundant code paths, extract patterns.

## Hypothesis Templates

```
"Simplify {logic} by removing {redundancy}"
"Merge {path-a} and {path-b} into unified {path}"
"Remove {unused} to reduce complexity"
"Extract {pattern} into helper function"
"Replace {repetition} with loop or macro"
```

## When to Apply

- Dead code detected
- Redundant branches exist
- Complexity score is high
- Same pattern repeated 3+ times
- Function > 50 lines

## When to Avoid

- Logic serves different purposes
- Simplification breaks edge cases
- Code is already minimal
- Readability would suffer

## Eight Keys Impact

| Key | Impact | Why |
|-----|--------|-----|
| Clarity | +high | Simpler = clearer |
| λ Efficiency | +medium | Fewer paths = faster |
| μ Directness | +medium | Less indirection |

## Success History

| Target | Date | Hypothesis | Delta |
|--------|------|------------|-------|
| retry | 2026-03-25 | Extract constants | Quality +0.50 |

## Simplification Patterns

### 1. Extract Constants

```elisp
;; Before
(string-match-p "429\\|503\\|502" status)

;; After
(defvar my/gptel--transient-http-statuses "429\\|503\\|502")
(string-match-p my/gptel--transient-http-statuses status)
```

### 2. Merge Conditions

```elisp
;; Before
(when condition-a
  (when condition-b
    (do-thing)))

;; After
(when (and condition-a condition-b)
  (do-thing))
```

### 3. Extract Helper

```elisp
;; Before (repeated pattern)
(let ((result (expensive-call)))
  (if result
      (process result)
    (fallback)))

;; After
(defun my/with-fallback (expensive-fn process-fn fallback-fn)
  (let ((result (funcall expensive-fn)))
    (if result (funcall process-fn result) (funcall fallback-fn))))
```

## Statistics

| Metric | Value |
|--------|-------|
| Total uses | 1 |
| Success rate | 100% |
| Avg quality delta | +0.50 |
| Avg Eight Keys delta | 0.00 |

## Signal Phrases for Commit

- "Simplifies X by..."
- "Removes redundant Y"
- "Extracts pattern into Z"