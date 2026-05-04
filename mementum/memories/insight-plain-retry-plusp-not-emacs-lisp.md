# plusp is Common Lisp, not Emacs Lisp

**Target:** retry

**Decision:** Replace `plusp` with standard `>` comparison.

`plusp` does not exist in standard Emacs Lisp. The staging merge introduced `(plusp (length messages))` in retry trimming code, causing `Symbol's function definition is void: plusp` process filter errors that silently broke tool-result trimming.

**Fix:** `(plusp (length messages))` → `(> (length messages) 0)`

`cl-plusp` exists in `cl-lib` but requires explicit require. Prefer standard `>`.
