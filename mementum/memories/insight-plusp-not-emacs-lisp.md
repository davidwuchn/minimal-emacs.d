# plusp is Common Lisp, not Emacs Lisp

**Target:** lisp/modules/gptel-ext-retry.el

`plusp` does not exist in standard Emacs Lisp. The staging merge introduced `(plusp (length messages))` which caused `"Symbol's function definition is void: plusp"` process filter errors.

**Fix:** Replace with `(> (length messages) 0)`.

**Note:** `cl-plusp` exists in `cl-lib` but requires explicit `(require 'cl-lib)` which is heavier than the standard `>` form.

**Detection:** Grep for `(plusp ` in non-test source files.
