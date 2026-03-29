# hash-table-p Defensive Checks

**Discovery:** Always check `(hash-table-p var)` before calling `gethash`/`puthash` on variables that may not be initialized.

**Problem:** If a hash-table variable is nil (not yet initialized), calling `gethash` on it throws:
```
(wrong-type-argument hash-table-p nil)
```

**Pattern:**
```elisp
;; Before (unsafe)
(defun my-get (key)
  (gethash key my-hash-table))

;; After (safe)
(defun my-get (key)
  (when (hash-table-p my-hash-table)
    (gethash key my-hash-table)))
```

**Context:** `gptel-auto-workflow--worktree-state` and `my/gptel--subagent-cache` were accessed before initialization, causing errors in auto-workflow.

**Related:** gptel-tools-agent.el, defensive programming

**Symbol:** 💡