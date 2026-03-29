# dir-locals.el Loading in Non-File Buffers

**Discovery:** Setting `default-directory` alone does NOT auto-load `.dir-locals.el`. Must call `hack-dir-local-variables-non-file-buffer` explicitly.

**Critical:** `default-directory` MUST have a **trailing slash** for `hack-dir-local-variables-non-file-buffer` to work!

Without trailing slash:
- `(file-name-directory "~/.emacs.d")` → `"~/"`
- `locate-dominating-file` fails to find `.dir-locals.el`

With trailing slash:
- `(file-name-directory "~/.emacs.d/")` → `"~/.emacs.d/"`
- `locate-dominating-file` finds `.dir-locals.el`

**Fix:** Use `(file-name-as-directory (expand-file-name dir))` to ensure trailing slash.

**Also:** Use `:safe #'always` in `defcustom` to mark variables as safe for dir-locals without prompting (which hangs in daemon mode - no UI to show the prompt).

**Context:** Multi-project auto-workflow assumed `.dir-locals.el` would load when changing directory. This was wrong - Emacs only auto-loads it when visiting files.

**Pattern:**
```elisp
(let ((root (file-name-as-directory (expand-file-name project-root))))
  (with-current-buffer buf
    (setq-local default-directory root)  ;; MUST have trailing slash!
    (hack-dir-local-variables-non-file-buffer)
    ...))
```

**Related:** gptel-auto-workflow-projects.el, multi-project support

**Symbol:** 💡