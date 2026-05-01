---
title: Anti-Pattern: Removing Defensive JSON Key Lookups
category: anti-pattern
tags: [json, parsing, defensive-programming, staging-verification-gap]
created: 2026-05-01
---

# Anti-Pattern: Removing Defensive JSON Key Lookups

## What Happened

Experiment `optimize/strategic-riven-r121309z237d-exp1` removed string-key lookups:
```elisp
;; REMOVED (incorrectly):
(cdr (assoc "file" item))
(cdr (assoc "path" item))  
(cdr (assoc "target" item))
```

It assumed `json-key-type 'symbol` guarantees ALL keys are symbols.

## Why It Was Wrong

- JSON parsing behavior depends on: Emacs version, `json-key-type` setting, parser used
- Symbol keys are common but NOT guaranteed
- Removing defensive lookups breaks parsing silently → empty target lists → workflow fails

## The Fix

Restore both lookup types:
```elisp
(or (alist-get 'file item)      ; symbol key
    (cdr (assoc "file" item))   ; string key (defensive)
    ...)
```

## Prevention Rules

1. **NEVER remove defensive code without proving it's unreachable in ALL contexts**
2. **JSON parsing assumptions must be tested across Emacs versions**
3. **Staging verification should include: mixed key-type JSON test cases**
4. **Experiments removing defensive code get extra scrutiny during review**

## Lesson

Defensive code exists for a reason. "Dead code" that handles edge cases is not dead—it's insurance.
