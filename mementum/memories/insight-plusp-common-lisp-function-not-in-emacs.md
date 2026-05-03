# 💡 plusp is Common Lisp, not Emacs Lisp

`plusp` does not exist in standard Emacs Lisp. Use `(> n 0)` instead.

The staging merge introduced `(plusp (length messages))` in `gptel-ext-retry.el` which caused `"Symbol's function definition is void: plusp"` errors in the auto-workflow process filter.

**Fix:** Replace `(plusp (length x))` with `(> (length x) 0)`.

**Related:** `cl-plusp` exists in `cl-lib` but requires `(require 'cl-lib)`. Prefer the standard `>` form.
