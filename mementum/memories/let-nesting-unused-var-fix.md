# Fixing Unused Lexical Variable in Nested Let

## Problem
When a `let` binds two variables (e.g., `effective-effort` and `effort-param`) but only one is used in the body, byte-compile warns about the unused variable.

## Fix: Restructure as nested lets
Instead of `(let ((a val-a) (b val-b)) ...)` where `a` is only used to compute `b`:
```elisp
(let ((a val-a))
  (let ((b (compute-using a)))
    ...))
```
This makes `a` "used" (in the inner let's binding computation) and eliminates the warning. Bonus: can also use `a` for other purposes (cost tracking, logging) in the outer let's body.

## Application
Fixed in `gptel-benchmark-call-subagent` where `effective-effort` was bound alongside `effort-param` but unused in the body. Restructured to:
```elisp
(let ((effective-effort ...))
  (when ... (gptel-ai-behaviors--record-cost ... effective-effort ...))
  (let ((effort-param (gptel-ai-behaviors--effort-for-api ... effective-effort)))
    ...))
```
