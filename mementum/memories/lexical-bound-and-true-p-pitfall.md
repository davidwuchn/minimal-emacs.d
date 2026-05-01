# lexical bound-and-true-p pitfall

**Date**: 2026-05-01
**Category**: emacs-lisp
**Related**: lexical-binding, validation-retry, auto-workflow

## Insight

`bound-and-true-p` checks dynamic/special variable bindings, not an ordinary lexical `let` binding in a `lexical-binding: t` file. A retry guard like:

```elisp
(let ((gptel-auto-experiment--in-retry t))
  (funcall callback output))
```

does not make `(bound-and-true-p gptel-auto-experiment--in-retry)` true inside the callback unless the variable is declared special. For callback-local state, prefer an explicit lexical flag captured by the callback closure, e.g. `validation-retry-active`, and mutate that flag before dispatching retry work.

Regression pattern: force validation to fail twice and assert only two executor dispatches occur.
