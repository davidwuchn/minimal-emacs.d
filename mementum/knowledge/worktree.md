---
title: Git Worktrees in Auto-Experiment Workflows
status: active
category: knowledge
tags: [git, worktree, auto-experiment, debugging, resource-management]
---

# Git Worktrees in Auto-Experiment Workflows

## Overview

Git worktrees enable running experiments in isolated working directories while sharing the same `.git` repository. This is essential for the auto-experiment system, which needs to test code changes without disrupting the main development branch. This knowledge page covers common pitfalls, cleanup patterns, and timing considerations for worktree management.

## The Worktree Path Resolution Problem

### The Bug

Auto-workflow experiments consistently failed with `verification-failed` even after the grader passed all 9 tests.

### Root Cause

The `gptel-auto-experiment-benchmark` function invokes `verify-nucleus.sh` using a path computed from `proj-root`:

```elisp
(expand-file-name "scripts/verify-nucleus.sh" proj-root)
```

However, `default-directory` is set to the worktree. The verification script computes its `$DIR` variable based on its own location in the **main repository**, causing it to validate main repo code instead of the worktree changes.

### Key Insight

Worktrees share `.git` but have separate working directories. Scripts that hardcode paths relative to their location will **not** see worktree-specific changes.

### The Fix

Skip nucleus script validation in experiment benchmark mode:

| Validation Layer | Target | Works in Worktree? |
|-----------------|--------|-------------------|
| Code syntax validation | Worktree file | ✅ Yes |
| Executor verification | Worktree context | ✅ Yes |
| Nucleus script | Main repo location | ❌ No |
| Full validation | Staging flow | ✅ Yes |

### Verification Result

```
(:passed t :nucleus-passed t :nucleus-skipped t)
```

### Affected File

```
lisp/modules/gptel-tools-agent.el:1634 - gptel-auto-experiment-benchmark
```

---

## Worktree Cleanup Patterns

### When to Clean Up

Merged experiment worktrees should be cleaned up to prevent accumulation. Without cleanup, the `var/tmp/experiments/` directory grows unbounded with stale branches.

### Symptoms of Accumulation

- Many stale worktrees in `var/tmp/experiments/`
- Experiment branches merged to staging but not deleted
- Worktree count grows without bound
- Disk space wasted on obsolete experiment code

### Detection Script

Use this script to identify merged experiment worktrees:

```bash
git worktree list | grep optimize | awk '{print $3}' | sed 's/\[//' | sed 's/\]//' | while read branch; do
  if git log staging --oneline | grep -q "Merge $branch"; then
    echo "MERGED: $branch"
  fi
done
```

### Cleanup Commands

```bash
# Remove the worktree directory
git worktree remove <path> --force

# Delete the branch
git branch -D <branch>
```

### Prevention Strategies

1. **Auto-workflow cleanup**: Add cleanup logic to the workflow that runs after successful merges
2. **Periodic cleanup**: Schedule a periodic job to remove merged worktrees
3. **Auto-deletion**: Automatically delete after successful merge to staging
4. **Manual review**: Include cleanup step in post-merge checklist

### Example Cleanup Session

Cleaned 7 merged worktrees in one session:

| Branch | Status |
|--------|--------|
| agent-exp1 | Merged, deleted |
| agent-exp2 | Merged, deleted |
| core-exp2 | Merged, deleted |
| strategic-exp1 | Merged, deleted |
| strategic-exp2 | Merged, deleted |
| tools-exp1 | Merged, deleted |
| tools-exp2 | Merged, deleted |

**Location**: `var/tmp/experiments/optimize/`

---

## Worktree Deletion Timing

### The Bug

"No such file or directory" errors during auto-workflow experiments, causing cascade failures.

### Root Cause

Worktree deletion happened at the **START** of `run-next`, before the next experiment could use it.

### Buggy Timeline

```
1. Experiment 1 creates worktree
2. Experiment 1 completes successfully
3. run-next(2) is called
4.
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-axXroD.txt. Use Read tool if you need more]...