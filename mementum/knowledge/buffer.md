---
title: buffer
status: open
---

Synthesized from 4 memories.

# Buffer-Local Callback Context Bug

## Issue
Experiments run in parallel (dolist spawns all 5 targets) but used global state variables, causing race conditions.

## Root Cause
1. `dolist` in `gptel-auto-workflow--run-with-targets` spawns 5 experiments in parallel
2. Callbacks from `gptel-agent--task` fire asynchronously
3. Global/buffer-local variables get overwritten by race conditions

## Evidence
- `gptel-auto-experiment--grade-done=t` found in `*Minibuf-1*` (wrong buffer)
- 5 timeout messages, only 1 result recorded
- Hash table shows 5 tasks, 5 worktrees after fix

## Fix
Three hash tables keyed by target/id:

1. **my/gptel--agent-task-state** - task execution state
   - Key: task-id (integer)
   - Value: (:done :timeout-timer :progress-timer)

2. **gptel-auto-experiment--grade-state** - grading state
   - Key: grade-id (integer)
   - Value: (:done :timer)

3. **gptel-auto-workflow--worktree-state** - worktree state
   - Key: target (string)
   - Value: (:worktree-dir :current-branch)

4. **Experiment loop local variables** - closure-captured state
   - `results`, `best-score`, `no-improvement-count`
   - Each loop has its own copy via `let*`

## Key Functions Updated
- `gptel-auto-experiment-loop`: local state in closure
- `gptel-auto-workflow-create-worktree/delete-worktree`: hash table
- `gptel-auto-experiment-benchmark`: uses current-target for lookup
- Benchmark score functions: use current-target for lookup

## Status
✅ Fixed 2026-03-28
Commits: 4a23297, 3d8b77e, e74d58d, 221ef37
Verified: 5 parallel tasks, 5 worktrees in hash tables

# Buffer-Local Variable Pattern

**Date**: 2026-04-02
**Category**: pattern
**Related**: auto-workflow, fsm, buffers

## Pattern

Buffer-local variables must be set in the correct buffer context.

## Problem

```elisp
;; WRONG - sets in current buffer, not target
(setq gptel--fsm-last fsm)

;; WRONG - not buffer-local
(setq-local gptel--fsm-last fsm)  ; in wrong buffer
```

## Solution

```elisp
;; RIGHT - switch to target buffer first
(with-current-buffer target-buf
  (setq-local gptel--fsm-last fsm))

;; Or create in current buffer if that's correct context
(setq-local gptel--fsm-last fsm)  ; in correct buffer
```

## Common Buffer-Local Variables

- `gptel--fsm-last` - FSM state
- `gptel-backend` - LLM backend
- `gptel-model` - Model name
- `gptel--stream-buffer` - Response buffer

## Signal

- Variable is nil unexpectedly → check buffer context
- Variable works in some buffers but not others → buffer-local issue
- Use `with-current-buffer` to ensure correct context

## Test

```elisp
(with-current-buffer target
  (should gptel--fsm-last))  ; Verify set in correct buffer
```

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