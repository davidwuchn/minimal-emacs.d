---
title: Git Worktree Management in Auto-Workflow
status: active
category: knowledge
tags: [git, worktree, auto-workflow, debugging, experiments]
---

# Git Worktree Management in Auto-Workflow

## Overview

This document covers critical patterns and bugs related to Git worktree management in the auto-workflow system. Worktrees are used to run experiments in isolated directories while sharing the `.git` metadata with the main repository.

## Key Concepts

| Concept | Description |
|---------|-------------|
| Worktree | Isolated working directory sharing `.git` with main repo |
| `default-directory` | Emacs variable determining where commands run |
| `proj-root` | Project root path (usually main repo) |
| Staging branch | Target branch for experiment merges |

## Common Pitfalls

### Pitfall 1: Script Path Resolution in Worktrees

**Problem**: Scripts that compute paths relative to their own location won't see worktree changes.

**Root Cause**: When running in a worktree, `default-directory` points to the worktree, but scripts may compute `$DIR` from the script's location (main repo).

**Example of the bug**:
```elisp
;; In gptel-auto-experiment-benchmark (line 1634)
(expand-file-name "scripts/verify-nucleus.sh" proj-root)
;; Runs with default-directory = worktree
;; But script computes DIR from its main-repo location
```

**Result**: Validation runs against main repo code, not worktree changes.

**Fix Applied**: Skip nucleus script validation in experiment benchmark:
- Syntax validation still targets worktree files correctly
- Executor runs verification in worktree context
- Full validation happens in staging flow anyway

**Verification result**:
```elisp
(:passed t :nucleus-passed t :nucleus-skipped t)
```

---

### Pitfall 2: Premature Worktree Deletion

**Problem**: "No such file or directory" errors during multi-experiment workflows.

**Timeline of the bug**:
1. Experiment 1 creates worktree
2. Experiment 1 completes
3. `run-next(2)` is called
4. Line 2289: `gptel-auto-worktree-delete-worktree` DELETES worktree
5. Experiment 2 tries to run in non-existent worktree → error

**Also**: Worktree was deleted on every failure (grader failed, benchmark failed, timeout), preventing retry.

**Solution**:
- Remove ALL `delete-worktree` calls during experiment execution
- Remove delete-worktree when target is done
- Worktrees only cleaned at START of next workflow run
- Cleanup function: `gptel-auto-workflow--cleanup-old-worktrees` in `gptel-auto-workflow-cron-safe`

**Why keep worktrees until next run?**
1. After experiments complete, improvements may need merging to staging
2. Staging merge happens AFTER workflow completes
3. Only safe to delete at START of next run (clean slate for new experiments)

**Key Pattern**: Resources should only be cleaned up when truly done—for auto-workflow, that's at the START of the NEXT run, not the end of the current run.

**Commits**: d06a47f (partial), 1834e09 (final)

---

## Worktree Cleanup Pattern

### Symptom

- Many stale worktrees accumulate in `var/tmp/experiments/`
- Experiment branches merged to staging but not deleted
- Worktree count grows without bound

### Detection Script

```bash
git worktree list | grep optimize | awk '{print $3}' | sed 's/\[//' | sed 's/\]//' | while read branch; do
  if git log staging --oneline | grep -q "Merge $branch"; then
    echo "MERGED: $branch"
  fi
done
```

### Manual Cleanup Commands

```bash
# Remove worktree
git worktree remove <path> --force

# Delete branch
git branch -D <branch>
```

**Example**: Cleaned 7 merged worktrees:
- agent-exp1
- agent-exp2
- core-exp2
- strategic-exp1
- strategic-exp2
- tools-exp1
- tools-exp2

### Prevention Strategies

1. Auto-workflow should clean up merged experiments automatically
2. Run periodic cleanup of merged worktrees
3. Consider auto-deletion after merge to staging
4. Implement cleanup in `gptel-auto-workflow-cron-safe`

---

## Worktree Reference Commands

| Command | Description |
|---------|-------------|
| `git worktree list` | List all worktrees |
| `git worktree add <path> <branch>` | Create new worktree |
| `git worktree remove <path>` | Remove worktree |
| `git branch -D <branch>` | Delete branch after worktree removed |

---

## File Locations

- `lisp/modules/gptel-tools-agent.el:1634` - `gptel-auto-experiment-benchmark`
- Worktree storage: `var/tmp/experiments/`

---

## Related

- [[auto-workflow]] - Main auto-workflow system
- [[staging-merge]] - Staging branch merge process
- [[experiment-tracking]] - Tracking experiment state
- [[git-branching-strategy]] - Branch management patterns
- [[debugging-patterns]] - General debugging approaches

---

## Summary

1. **Worktree isolation is partial**: Scripts with hardcoded path resolution won't see worktree changes
2. **Deletion timing matters**: Clean worktrees at START of next workflow run, not end of current run
3. **Prefer cleanup over deletion during execution**: Keep worktrees available for retry on failure
4. **Prevalence of accumulation**: Implement automatic cleanup for merged experiments