---
title: "Nil Guard Pattern"
status: active
category: pattern
tags: [nil, safety, elisp, defensive-programming]
related: [string-guard-pattern, workspace-boundary-pattern]
depends-on: []
---

# Nil Guard Pattern

> **Frequency**: High (>=3 sessions)
> **Severity**: Medium-High
> **Applies to**: All gptel-auto-workflow modules, especially evolution.el, strategic.el, ontology-router.el

## Problem

Elisp functions throw `wrong-type-argument` when passed nil. This crashes in:
- Process sentinels (curl timeout)
- FSM callbacks (missing FSM info)
- Arithmetic comparisons (`=`, `<`, `>`)
- Overlay creation (`make-overlay`, `copy-marker`)
- String operations (`string-suffix-p`, `string-match-p`)

## Root Cause

Functions derived from external commands (git, curl, API responses) can return nil in edge cases.

## Solution: Guard Pattern

```elisp
;; BEFORE: crashes on nil
(= status 400)                       ; wrong-type-argument number-or-marker-p nil
(string-suffix-p ".el" file)         ; wrong-type-argument stringp nil
(make-overlay start end)              ; wrong-type-argument markerp nil

;; AFTER: safe with guard
(when (numberp status)
  (= status 400))

(when (stringp file)
  (string-suffix-p ".el" file))

(when (markerp tm)
  (make-overlay tm end))
```

## Common Guard Combinations

### Number Guard
```elisp
(when (numberp status)
  (= status 400))
```

### String Guard
```elisp
(when (stringp file)
  (string-suffix-p ".el" file))
```

### Marker Guard
```elisp
(when (markerp tm)
  (marker-position tm))
```

### Combined Guard
```elisp
(when (and target (stringp target) (not (string-empty-p target)))
  (process-target target))
```

## Where to Apply

| Module | Function | Guard Type |
|--------|----------|------------|
| evolution.el | gptel-auto-workflow--run-experiments | numberp |
| strategic.el | gptel-auto-workflow--select-target | stringp |
| ontology-router.el | gptel-auto-workflow--route-ontology | stringp |
| tools-agent.el | gptel-auto-workflow--execute-task | stringp + numberp |

## Prevention

- Always guard values from external commands before use
- Use `condition-case` for defensive wrappers
- Add `(declare (type string file))` where possible

## References

- `mementum/memories/nil-guard-pattern.md`
- `mementum/memories/nil-safety-pattern.md`
- `mementum/memories/nil-guard-project-root.md`
- `mementum/memories/assoc-nil-guard-in-let-bindings.md`
- `mementum/memories/check-protected-configs-nil-guard.md`
