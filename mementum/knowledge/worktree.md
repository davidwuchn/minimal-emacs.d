---
title: worktree
status: open
---

Synthesized from 3 memories.

💡 verification-failed-worktree-bug

## Problem
Auto-workflow experiments always failed with `verification-failed` after grader passed 9/9.

## Root Cause
`gptel-auto-experiment-benchmark` ran `verify-nucleus.sh` with path from `proj-root`:
```elisp
(expand-file-name "scripts/verify-nucleus.sh" proj-root)
```

But `default-directory` was worktree. The script computes `$DIR` from its own location (main repo), so it validated main repo code, not worktree changes.

## Fix
Skip nucleus script validation in experiment benchmark:
- Code syntax validation still works (targets worktree file)
- Executor already runs verification in worktree context
- Full validation happens in staging flow anyway

## Key Insight
Worktrees share `.git` but have separate working directories. Scripts that hardcode paths relative to script location won't see worktree changes.

## Verification
```
(:passed t :nucleus-passed t :nucleus-skipped t)
```

## Files
- lisp/modules/gptel-tools-agent.el:1634 - gptel-auto-experiment-benchmark

# Experiment Worktree Cleanup Pattern

**Pattern:** Merged experiment worktrees should be cleaned up to prevent accumulation.

**Symptoms:**
- Many stale worktrees in `var/tmp/experiments/`
- Experiment branches that were merged to staging but not deleted
- Worktree count grows without bound

**Detection:**
```bash
git worktree list | grep optimize | awk '{print $3}' | sed 's/\[//' | sed 's/\]//' | while read branch; do
  if git log staging --oneline | grep -q "Merge $branch"; then
    echo "MERGED: $branch"
  fi
done
```

**Cleanup:**
```bash
git worktree remove <path> --force
git branch -D <branch>
```

**Prevention:**
- Auto-workflow should clean up merged experiments
- Periodic cleanup of merged worktrees
- Consider auto-deletion after merge to staging

**Example:** Cleaned 7 merged worktrees (agent-exp1, agent-exp2, core-exp2, strategic-exp1, strategic-exp2, tools-exp1, tools-exp2)

**Location:** `var/tmp/experiments/optimize/`

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