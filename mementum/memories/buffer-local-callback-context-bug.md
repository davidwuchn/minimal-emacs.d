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