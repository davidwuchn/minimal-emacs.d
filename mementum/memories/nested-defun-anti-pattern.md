# Nested Defun Anti-Pattern Detection

**Date:** 2026-03-28
**Source:** Code review of `gptel-workflow-benchmark.el`

## Finding

Found nested `defun` inside another function:

```elisp
(defun outer-function ()
  ...
  (defun inner-function ()  ; WRONG - creates new function every call!
    ...))
```

## Impact

- Creates a new function object on every call to outer function
- Function is inaccessible from outside (local binding)
- Memory leak - function objects accumulate
- Copy-paste error pattern - likely from refactoring

## Detection Pattern

Look for:
- `defun` inside `let`, `when`, `if` blocks
- Functions defined at indentation level > 0
- Functions that appear to be helpers but are inside main functions

## Fix Pattern

Move to top-level:

```elisp
(defun inner-function ()
  "Docstring."
  ...)

(defun outer-function ()
  ...
  (inner-function))
```

## Prevention

- `M-x checkdoc` will flag some issues
- Code review: scan for defun at wrong indentation
- Unit tests will fail if function is not defined at load time

## Related

- File: `lisp/modules/gptel-workflow-benchmark.el:709`
- Fix: commit `25c63eb` then `9056845`

**Symbol:** 🔁 pattern | ❌ mistake
