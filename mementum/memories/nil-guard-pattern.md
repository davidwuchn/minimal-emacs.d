# Nil Guard Pattern for Elisp

**Pattern:** Guard nil values before passing to functions expecting number-or-marker.

## Problem

Elisp functions like `=`, `make-overlay`, `copy-marker` throw `wrong-type-argument` when passed nil. This crashes in process sentinels and FSM callbacks where edge cases (curl timeout, missing FSM info) can produce nil values.

## Solution

```elisp
;; Guard before arithmetic comparison
(and (numberp status) (= status 400))

;; Guard before overlay creation
(and (markerp tm) (marker-position tm) tm)

;; Fallback chain
(or (and (markerp tm) (marker-position tm) tm)
    (with-current-buffer buf (point-marker)))
```

## Files Fixed

- `gptel-tools-agent.el:133-137` — marker fallback chain
- `gptel-agent-loop.el:506-512` — same pattern
- `gptel-ext-tool-confirm.el:337-340` — tool confirm guard
- `gptel-ext-retry.el:314-318` — `(numberp status)` guard

## Commits

- `57d96ab` — FSM markers nil
- `aa4e5e8` — HTTP status nil