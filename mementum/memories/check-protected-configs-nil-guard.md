# Nil guard for `gptel-auto-workflow--check-protected-configs`

Added `proj-root` nil guard to `gptel-auto-workflow--check-protected-configs` in `gptel-tools-agent-benchmark.el`.

**Problem**: `gptel-auto-workflow--project-root` can return nil (e.g., when not in a git repo). The function then sets `(default-directory proj-root)` to nil and calls `(cdr staging-content)` / `(cdr experiment-content)` which would error on nil.

**Fix**: Added `proj-root` as a precondition in the `when` clause. If project root is nil, the protected config check is silently skipped — the function returns `(cons t nil)` (safe/success) since there's no project to regress in.

```elisp
(when (and (stringp expected)
           proj-root
           (= 0 (cdr staging-content))
           (= 0 (cdr experiment-content)))
```

This is a boundary validation pattern: when a mandatory precondition (project root) can't be determined, skip the check rather than crash.