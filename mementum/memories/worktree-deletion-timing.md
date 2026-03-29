# Worktree Deletion Timing

**Date**: 2026-03-29

**Problem**: "No such file or directory" errors during auto-workflow experiments.

**Root Cause**: Worktree was being deleted at the START of `run-next`, before the next experiment could use it.

**Timeline of the bug**:
1. Experiment 1 creates worktree
2. Experiment 1 completes
3. `run-next(2)` is called
4. Line 2289: `gptel-auto-workflow-delete-worktree` DELETES worktree
5. Experiment 2 tries to run in non-existent worktree → error

**Also**: Worktree was deleted on every failure (grader failed, benchmark failed, timeout), preventing retry.

**Solution**:
- Remove ALL `delete-worktree` calls during experiment
- Only delete worktree in `run-next` when target is COMPLETE (all experiments done or threshold reached)
- Worktree persists for ALL experiments of a target

**Code locations changed**:
- Line 2101: Removed delete on timeout
- Line 2134: Removed delete on grader failure
- Line 2159: Removed delete on benchmark failure
- Line 2229: Removed delete on no-improvement
- Line 2289: Removed delete at start of run-next
- Line 2301: KEPT delete when target done (correct)

**Commit**: d06a47f

**Pattern**: Resources should only be cleaned up when truly done, not between iterations of a loop.