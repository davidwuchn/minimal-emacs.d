---
symbol: 🔁
date: 2026-06-04
---

# Self-Healing Byte-Compiler: Dog-Food Principle

When building a self-healing function, the function MUST be its own
first customer. Manual whack-a-mole fixes of 80+ warnings took 3+
hours of iterative edit→compile→fail cycles. The self-heal function
(`gptel-auto-workflow--self-heal-byte-compiler`) can do the same in
minutes.

Key design decisions:
1. **Iterative**: One pass doesn't catch cascading warnings (fixing
   one reveals the next). Loop up to N iterations.
2. **5 fixers cover 90%+ of warnings**: docstring-width, unescaped-quotes,
   unused-variables, free-variables, unknown-functions.
3. **Source lookup for declare-function**: Uses `find-lisp-object-file-name`
   to auto-discover which .el file defines a missing function.
4. **Forward declarations at top**: `defvar`/`declare-function` inserted
   before first `defun`/`defvar`/`require` in the file.
5. **Circular dependency awareness**: Don't add `eval-when-compile
   require` between mutually-referencing modules — use `declare-function`
   + `defvar` instead.

Anti-pattern learned: manually fixing 80+ byte-compiler warnings one by
one is a trap. Each fix reveals new warnings (cascading). The right
approach is to write the auto-fixer FIRST, then let it fix everything.

Remaining limitation: `(setf struct-accessor)` warnings require
`(with-no-warnings)` wrapping — the byte-compiler can't see
`gv-define-setter` expansions from other files.
