# Broken .elc can corrupt cl-defgeneric dispatch

**Target:** var/elpa/vertico-2.8/vertico.elc

After Emacs daemon restart (launchctl), `vertico--format-candidate` (a `cl-defgeneric`) failed with `cl-no-applicable-method` on every call, causing Vertico to show "detected an error: ()" during M-x.

**Root cause:** The `.elc` file was compiled with a different Emacs/byte-compiler version, producing a broken generic function dispatch table. The source `.el` worked correctly when loaded directly.

**Fix:** Delete the stale `.elc` file. Emacs will use the source `.el` and JIT-compile correctly on next daemon start.

**Detection:** If `cl-defgeneric` functions raise `cl-no-applicable-method` for types they should handle, try `(load "package.el" nil t t)` to force source reload. If it works from source, delete the `.elc`.

**Prevention:** After Emacs version upgrades, run `(byte-recompile-directory package-user-dir 0 t)` or delete all `.elc` in `var/elpa/`.
