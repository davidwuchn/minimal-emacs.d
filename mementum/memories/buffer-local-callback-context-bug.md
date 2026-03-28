# Buffer-Local Callback Context Bug

## Issue
Workflow gets stuck because experiments run in parallel (dolist spawns all 5 targets at once) but state was stored in global/buffer-local variables.

## Root Cause
1. `dolist` in `gptel-auto-workflow--run-with-targets` spawns 5 experiments in parallel
2. Callbacks from `gptel-agent--task` fire asynchronously
3. Global/buffer-local variables get overwritten by race conditions

## Evidence
- `gptel-auto-experiment--grade-done=t` found in `*Minibuf-1*` (wrong buffer)
- 5 timeout messages, only 1 result recorded
- Hash table shows 5 tasks, 4 grades in progress after fix

## Fix
Changed to hash tables keyed by unique id:

```elisp
(defvar my/gptel--agent-task-state (make-hash-table :test 'eql))
(defvar gptel-auto-experiment--grade-state (make-hash-table :test 'eql))
```

Each callback looks up its own state by id:
- `task-id` from `my/gptel--agent-task-counter`
- `grade-id` from `gptel-auto-experiment--grade-counter`

Cleanup via `remhash` after callback completes.

## Status
✅ Fixed 2026-03-28, commit 4a23297
Verified: 5 parallel tasks running, hash tables tracking independent state