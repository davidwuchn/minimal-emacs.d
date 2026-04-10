---
title: Git Worktree Management in Auto-Workflow
status: active
category: knowledge
tags: [git, worktree, auto-workflow, debugging, experiments, cleanup]
---

# Git Worktree Management in Auto-Workflow

This page documents the patterns, bugs, and best practices for managing Git worktrees in the auto-workflow system. Worktrees are used to run experiments in isolated directories while sharing the `.git` repository with the main checkout.

## Overview

The auto-workflow system uses Git worktrees to:

1. **Isolate experiments** - Each experiment runs in its own worktree to prevent cross-contamination
2. **Enable parallel development** - Worktrees allow checking multiple branches simultaneously
3. **Share repository resources** - Only one `.git` directory exists, saving disk space

```bash
# Typical worktree structure
/home/user/project/           # main checkout
/home/user/var/tmp/experiments/optimize/exp1/  # experiment worktree
/home/user/var/tmp/experiments/optimize/exp2/  # another worktree
```

## Worktree Creation Pattern

Worktrees are created automatically during experiment setup:

```elisp
;; From gptel-tools-agent.el
(setq worktree-dir (expand-file-name (format "experiments/optimize/%s" exp-id) var-tmp-dir))
(when (file-directory-p worktree-dir)
  (delete-directory worktree-dir t))
(make-directory worktree-dir t)
(apply #'process-file "git" nil nil nil
       (list "worktree" "add" "-b" branch-name worktree-dir base-commit))
```

### Key Properties

| Property | Value |
|----------|-------|
| Location | `var/tmp/experiments/optimize/` |
| Branch naming | `exp-{experiment-id}` |
| Base commit | Typically staging head |
| Cleanup trigger | START of next workflow run |

## The Verification Bug (Critical)

### Problem Description

Auto-workflow experiments always failed with `verification-failed` even after the grader passed 9/9.

### Root Cause Analysis

The bug occurred in `gptel-auto-experiment-benchmark` which ran `verify-nucleus.sh`:

```elisp
;; lisp/modules/gptel-tools-agent.el:1634
(expand-file-name "scripts/verify-nucleus.sh" proj-root)
```

**The critical issue**: `default-directory` was set to the worktree, but the script computes `$DIR` from its own location (the main repo). This meant the script validated main repo code, not the worktree changes.

### How the Script Worked

```bash
# Inside verify-nucleus.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIR="$(dirname "$SCRIPT_DIR")"  # This resolves to main repo, not worktree
```

### The Fix

Skip nucleus script validation in experiment benchmark because:

1. **Code syntax validation still works** - Targets the worktree file directly
2. **Executor runs verification in worktree context** - The actual verification happens there
3. **Full validation happens in staging flow** - Before merge to staging

```elisp
;; Verification result after fix
(:passed t :nucleus-passed t :nucleus-skipped t)
```

### Key Insight

> Worktrees share `.git` but have separate working directories. Scripts that hardcode paths relative to script location won't see worktree changes.

## Worktree Deletion Timing

### The Bug (2026-03-29)

**Problem**: "No such file or directory" errors during auto-workflow experiments.

**Root Cause**: Worktree was being deleted at the START of `run-next`, before the next experiment could use it.

### Timeline of the Bug

| Step | Action | Result |
|------|--------|--------|
| 1 | Experiment 1 creates worktree | `/var/tmp/experiments/optimize/exp1/` |
| 2 | Experiment 1 completes | Success |
| 3 | `run-next(2)` is called | Next experiment queued |
| 4 | Line 2289: `gptel-auto-worktree-delete-worktree` executes | DELETES worktree |
| 5 | Experiment 2 tries to run | **Error: worktree doesn't exist** |

### Additional Problem

Worktrees were also deleted on every failure (grader failed, benchmark failed, timeout), preventing retry attempts.

### The Solution

```elisp
;; Changes committed in d06a47f and 1834e09
;; 1. Removed ALL delete-worktree calls during experiment execution
;; 2. Removed delete-worktree when target is done
;; 3. Worktrees only cleaned at START of next workflow run
```

### Cleanup Function

```elisp
;; Only called from gptel-auto-workflow-cron-safe
(gptel-auto-workflow--cleanup-old-worktrees)
```

### Why Keep Worktrees Until Next Run?

1. **Post-experiment merging** - Improvements may need to be merged to staging AFTER workflow completes
2. **Staging merge timing** - Staging merge happens after workflow finishes
3. **Safe deletion window** - Only safe to delete at START of next run (clean slate for new experiments)

### Pattern Summary

> Resources should only be cleaned up when truly done. For auto-workflow, that means at the START of the NEXT run, not the end of the current run.

## Worktree Cleanup Pattern

### Symptoms of Accumulation

- Many stale worktrees in `var/tmp/experiments/`
- Experiment branches that were merged to staging but not deleted
- Worktree count grows without bound

### Detection Command

```bash
git worktree list | grep optimize | awk '{print $3}' | sed 's/\[//' | sed 's/\]//' | while read branch; do
  if git log staging --oneline | grep -q "Merge $branch"; then
    echo "MERGED: $branch"
  fi
done
```

### Manual Cleanup

```bash
# Remove worktree
git worktree remove <path> --force

# Delete branch
git branch -D <branch>
```

### Example

Cleaned 7 merged worktrees:
- agent-exp1
- agent-exp2
- core-exp2
- strategic-exp1
- strategic-exp2
- tools-exp1
- tools-exp2

Location: `var/tmp/experiments/optimize/`

### Prevention Strategies

1. **Auto-cleanup in workflow** - Auto-workflow should clean up merged experiments
2. **Periodic cleanup** - Run cleanup of merged worktrees regularly
3. **Auto-deletion after merge** - Consider auto-deletion after merge to staging

## Worktree File Paths

### Common Locations

| Path | Purpose |
|------|---------|
| `var/tmp/experiments/optimize/` | Main experiment directory |
| `var/tmp/experiments/optimize/{exp-id}/` | Individual experiment worktree |
| `.git` | Shared git directory (not in worktree) |

### Path Resolution in Elisp

```elisp
;; Safe path expansion
(expand-file-name "scripts/verify-nucleus.sh" proj-root)

;; Unsafe - resolves to main repo when called from worktree
;; (uses script's location, not current working directory)
```

## Debugging Worktree Issues

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `verification-failed` | Script paths resolve to main repo | Skip nucleus validation in benchmark |
| `No such file or directory` | Worktree deleted too early | Delete only at start of next run |
| `path already exists` | Stale worktree not cleaned | Run cleanup before creating new |

### Verification Commands

```bash
# List all worktrees
git worktree list

# Check worktree status
git status

# Verify branch exists
git branch -a | grep exp-

# Check staging merges
git log staging --oneline --grep="Merge"
```

## Related Topics

- **Auto-Workflow**: The system that manages experiment execution
- **Staging Branch**: Where successful experiments are merged
- **Git Branching**: Experiment branch creation and management
- **Experiment Flow**: The full lifecycle from creation to merge
- **Cron Safe**: The wrapper that ensures cleanup runs properly
- **Verification Scripts**: Scripts that validate experiment outputs

---

## Quick Reference

### Do's

- ✅ Create worktrees in `var/tmp/experiments/optimize/`
- ✅ Clean up at START of next workflow run
- ✅ Use worktree context for validation
- ✅ Delete branches after staging merge

### Don'ts

- ❌ Delete worktrees during experiment execution
- ❌ Run verification scripts from main repo context
- ❌ Hardcode paths relative to script location
- ❌ Leave merged experiment branches behind

---

*Last updated: 2026-03-29 based on bug fixes in d06a47f and 1834e09*