# Kill Buffer Query Suppression: Inverted Logic

**Symbol:** ❌ mistake  
**Date:** 2026-03-31

## Problem

"Buffer X modified; kill anyway?" prompt appeared during auto-workflow execution, blocking headless operation.

## Root Cause

The function `gptel-auto-workflow--suppress-kill-buffer-query` had inverted logic:

```elisp
;; WRONG
(defun gptel-auto-workflow--suppress-kill-buffer-query ()
  (not gptel-auto-workflow--headless))
```

When `gptel-auto-workflow--headless` is `t`:
- `(not t)` = `nil`
- `kill-buffer-query-functions` interprets `nil` as "block the kill"

## Correct Logic

For `kill-buffer-query-functions`:
- Return `t` = allow killing
- Return `nil` = block killing

Fix:
```elisp
(defun gptel-auto-workflow--suppress-kill-buffer-query ()
  (or gptel-auto-workflow--headless t))
```

## Lesson

When adding hooks to `*-query-functions`, understand the return value semantics:
- `nil` often means "block/prevent"
- `t` often means "allow/proceed"

Always test the actual behavior, not just the docstring intent.

## Location

`gptel-tools-agent.el:2695-2698`