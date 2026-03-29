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
- Removed ALL `delete-worktree` calls during experiment
- Removed delete-worktree when target is done
- Worktrees only cleaned at START of NEXT workflow run
- Cleanup: `gptel-auto-workflow--cleanup-old-worktrees` in `gptel-auto-workflow-cron-safe`

**Why keep worktrees until next run?**
1. After experiments complete, improvements may need to be merged to staging
2. Staging merge happens AFTER workflow completes
3. Only safe to delete at START of next run (clean slate for new experiments)

**Commit**: d06a47f (partial), 1834e09 (final)

**Pattern**: Resources should only be cleaned up when truly done - for auto-workflow, that means at the START of the NEXT run, not the end of the current run.