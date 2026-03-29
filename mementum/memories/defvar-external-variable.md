# defvar for External Variables

**Discovery:** Use simple `(defvar var-name)` without docstring for variables defined in other files. Avoids duplicate definitions and compiler warnings.

**Before (wrong):**
```elisp
(defvar gptel-auto-workflow--worktree-state nil
  "Hash table for worktree state. Defined in gptel-tools-agent.el.")
```

**After (correct):**
```elisp
(defvar gptel-auto-workflow--worktree-state)
```

**Why:** 
- Docstring duplicates what's in the primary definition file
- Without docstring, compiler knows variable exists but doesn't override original
- Cleaner for forward declarations across modules

**Warning:** With `lexical-binding: t`, `let` bindings for special variables need `defvar` first. Otherwise the binding is lexical and has no effect on the global/dynamic value.

**Symbol:** 💡