## Nil Guard for `with-current-buffer`

In `gptel-auto-workflow-run-research-for-project`, `project-buf` from `gptel-auto-workflow--get-project-buffer` could return nil if buffer creation fails. `with-current-buffer` signals an error on nil buffer.

**Pattern**: Always guard `with-current-buffer` calls when the buffer comes from a lookup function that may return nil.

```elisp
(when project-buf
  (with-current-buffer project-buf
    ...))
```

Applied in experiment 1/18 to `gptel-auto-workflow-projects.el` line ~842.