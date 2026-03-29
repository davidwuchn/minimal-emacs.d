# dir-locals.el Loading in Non-File Buffers

**Discovery:** Setting `default-directory` alone does NOT auto-load `.dir-locals.el`. Must call `hack-dir-local-variables-non-file-buffer` explicitly.

**Context:** Multi-project auto-workflow assumed `.dir-locals.el` would load when changing directory. This was wrong - Emacs only auto-loads it when visiting files.

**Fix:** Add `(hack-dir-local-variables-non-file-buffer)` after:
1. Setting buffer-local `default-directory`
2. Creating project-specific gptel-agent buffers
3. Before running workflow in `with-current-buffer`

**Pattern:**
```elisp
(with-current-buffer project-buf
  (setq-local default-directory project-root)
  (hack-dir-local-variables-non-file-buffer)  ;; <- critical
  (gptel-auto-workflow-run))
```

**Related:** gptel-auto-workflow-projects.el, multi-project support

**Symbol:** 💡