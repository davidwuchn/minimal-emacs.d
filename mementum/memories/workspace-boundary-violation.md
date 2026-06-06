---
title: "Workspace Boundary Violation Pattern"
status: active
category: pattern
tags: [security, self-heal, boundary]
related: [ov5-self-heal, workspace-boundary-validator]
depends-on: []
---

# Workspace Boundary Violation Pattern

## Problem

OV5's self-heal byte-compiler accessed `/Users/davidwu/lisp/modules` instead of `~/.emacs.d/lisp/modules` because it used a relative path `"lisp/modules"` without expanding against the project root.

## Root Cause

```elisp
;; BUG: relative path without root expansion
(directory-files "lisp/modules" t "\\.el\\'")
;; → Resolves to /Users/davidwu/lisp/modules (outside ~/.emacs.d!)
```

## Fix

Use `gptel-auto-workflow--expand-workspace-path` (from `gptel-tools-agent-base.el`):

```elisp
(let* ((proj-root (gptel-auto-workflow--worktree-base-root))
       (modules-dir (gptel-auto-workflow--expand-workspace-path "lisp/modules")))
  (directory-files modules-dir t "\\.el\\'"))
```

## Pattern Detection

Any `directory-files`, `with-temp-file`, `find-file`, or `insert-file-contents` with a bare string path that doesn't start with `/` or `~` is suspicious.

## Prevention

- Phase 1: Core boundary validator (`--path-within-workspace-p`, `--expand-workspace-path`, `with-workspace-boundary`)
- Phase 2: Replace all bare relative paths in auto-workflow modules
- Phase 3: Add to self-heal diagnostic — scan for bare paths and auto-remediate

## References

- `lisp/modules/gptel-tools-agent-base.el` — boundary validator functions
- `plans/workspace-boundary-validator/` — implementation plan
