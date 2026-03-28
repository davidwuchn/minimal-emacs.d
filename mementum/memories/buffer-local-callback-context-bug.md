# Buffer-Local Callback Context Bug

## Issue
Workflow gets stuck because buffer-local variables (`my/gptel--agent-task-done`, `gptel-auto-experiment--grade-done`) are accessed in wrong buffer context when callbacks fire.

## Root Cause
1. Variables defined with `defvar-local` or `make-variable-buffer-local`
2. Callbacks from `gptel-agent--task` fire in arbitrary buffer context
3. `setq` and `unless` checks happen in wrong buffer

## Evidence
- `gptel-auto-experiment--grade-done=t` found in `*Minibuf-1*` (emacsclient buffer)
- `gptel-auto-experiment--grade-done=nil` in worktree buffer
- 5 timeout messages, only 1 result recorded

## Fix
Changed to regular `defvar` (global) since experiments run sequentially:
- `my/gptel--agent-task-done` (line 617)
- `my/gptel--agent-task-timeout-timer` (line 620)
- `my/gptel--agent-task-progress-timer` (line 623)
- `gptel-auto-experiment--grade-done` (line 1559)
- `gptel-auto-experiment--grade-timer` (line 1563)

Removed `make-variable-buffer-local` calls.

## Status
✅ Fixed 2026-03-28, commit 54382a9