# cl-return-from Pitfall

**Discovered:** 2026-03-22
**Symbol:** ❌

## Problem

`cl-return-from` throws a catch for a tag that must exist in the dynamic scope. In Emacs Lisp, `defun` does NOT automatically create a `cl-block` named after the function.

```elisp
(defun foo ()
  (cl-return-from foo nil))  ;; ERROR: No catch for tag: --cl-block-foo--, t
```

## Solution

Use nested `if` or `cond` instead of early returns:

```elisp
(defun foo ()
  (if (not condition)
      nil
    (let ((result ...))
      result)))
```

## Alternative (if you must use cl-return)

Explicitly wrap body in `cl-block`:

```elisp
(defun foo ()
  (cl-block foo
    (cl-return-from foo nil)))
```

But nested `if` is cleaner and more idiomatic.

## Files Affected

- `lisp/eca-security.el` — Fixed 3 functions using `cl-return-from`

## Reference

- Emacs CL manual: `cl-return-from` requires enclosing `cl-block`
- Common Lisp: `defun` implicitly creates a block; Emacs Lisp does not