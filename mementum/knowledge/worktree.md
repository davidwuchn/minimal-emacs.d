---
title: Git Worktrees in Auto-Workflow
status: active
category: knowledge
tags: [worktree, auto-workflow, git, debugging, optimization]
---

# Git Worktrees in Auto-Workflow

Git worktrees are a critical component of the auto-workflow system, enabling parallel experiment execution without interfering with the main repository. This document covers common pitfalls, operational patterns, and debugging techniques.

## Overview

Worktrees in the auto-workflow system are created in `var/tmp/experiments/` directories, each associated with an experiment branch. They allow experiments to run in isolated environments while sharing the `.git` metadata with the main repository.

```
/project/
├── .git/                    # Shared git metadata
├── var/tmp/experiments/
│   ├── optimize/agent-exp1/ # Worktree 1
│   ├── optimize/agent-exp2/ # Worktree 2
│   └── optimize/core-exp1/  # Worktree 3
└── staging/                 # Main branch checkout
```

## Common Pitfall: Script Path Resolution

### The Problem

When running verification scripts inside a worktree, scripts that compute paths relative to their own location will resolve to the **main repository**, not the worktree. This causes verification to pass/fail against the wrong codebase.

### Symptom

```
Verification failed (9/9 passed by grader)
```

The grader passes all tests, but verification fails because the script is validating main repo code instead of worktree changes.

### Root Cause

The benchmark function constructs paths using `proj-root`:
```elisp
;; lisp/modules/gptel-tools-agent.el:1634
(expand-file-name "scripts/verify-nucleus.sh" proj-root)
```

The script itself computes `$DIR` from its location (main repo):
```bash
# Inside verify-nucleus.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIR="$(dirname "$SCRIPT_DIR")"  # Points to main repo, not worktree
```

Since `default-directory` is the worktree but the script resolves paths from the main repo, validation runs against the wrong code.

### Solution

Skip nucleus script validation in experiment benchmarks:
- Syntax validation still works (targets worktree file directly)
- Executor runs verification in worktree context
- Full validation happens in staging flow after merge

```elisp
;; Result shows nucleus was skipped
(:passed t :nucleus-passed t :nucleus-skipped t)
```

### Pattern

When working with worktrees, ensure scripts that compute paths do so relative to:
- The worktree's root (passed as argument)
- Or use absolute paths passed from the caller

Never rely on `BASH_SOURCE[0]` for path resolution in worktree contexts.

## Worktree Deletion Timing

### The Problem

Experiments fail with "No such file or directory" errors when the worktree is deleted before the next experiment can use it.

### Timeline of the Bug

1. Experiment 1 creates worktree
2. Experiment 1 completes successfully
3. `run-next(2)` is invoked
4. Line 2289: `gptel-auto-worktree-delete-worktree` executes → **deletes worktree**
5. Experiment 2 tries to run in non-existent worktree → **error**

### Additional Issue

Worktrees were also deleted on every failure (grader failure, benchmark failure, timeout), preventing any retry capability.

### Solution

- **Remove all `delete-worktree` calls during experiment execution**
- Only clean worktrees at the START of the next workflow run
- Use `gptel-auto-workflow--cleanup-old-worktrees` in `gptel-auto-workflow-cron-safe`

### Rationale

Worktrees must persist after experiments complete because:
1. Post-experiment improvements may need merging to staging
2. Staging merge happens AFTER workflow completes
3. Deleting too early removes the ability to inspect or retry

The safe deletion point is the **beginning of the next workflow run**, ensuring a clean slate for new experiments.

### Commits

- `d06a47f` - Partial fix
- `1834e09` - Complete fix

## Worktree Cleanup Pattern

### Problem

Accumulated stale worktrees from merged experiments clutter the filesystem and waste resources.

### Detection Script

```bash
# Find merged experiment worktrees
git worktree list | grep optimize | awk '{print $3}' | sed 's/\[//' | sed 's/\]//' | while read branch; do
  if git log staging --oneline | grep -q "Merge $branch"; then
    echo "MERGED: $branch"
  fi
done
```

### Cleanup Commands

```bash
# Remove the worktree
git worktree remove <path> --force

# Delete the branch
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

1. Auto-workflow should clean up merged experiments automatically
2. Run periodic cleanup of merged worktrees
3. Consider auto-deletion after successful merge to staging

## Worktree Management Commands

| Task | Command |
|------|---------|
| List worktrees | `git worktree list` |
| Create worktree | `git worktree add <path> <branch>` |
| Remove worktree | `git worktree remove <path> --force` |
| Delete branch | `git branch -D <branch>` |
| Prune stale | `git worktree prune` |

## Key Insights

1. **Shared .git, separate working directories**: Worktrees share `.git` metadata but have independent working trees. Scripts that hardcode paths relative to their location won't see worktree changes.

2. **Deletion timing matters**: Resources should only be cleaned up when truly done—for auto-workflow, that's at the START of the next run, not the end of the current run.

3. **Verify path resolution**: Always verify that scripts resolve paths relative to the intended working directory, not their own location.

4. **Persist for merging**: Keep worktrees alive until after staging merges complete, as they may be needed for post-experiment inspection or manual merging.

## Related

- [Auto-Workflow Configuration](auto-workflow-config)
- [Experiment Benchmarking](experiment-benchmark)
- [Staging Merge Flow](staging-merge)
- [Git Worktrees (external)](https://git-scm.com/docs/git-worktree)
- [Debugging Verification Failures](debugging-verification)
- [Workflow Cleanup Automation](workflow-cleanup)
- [Retry Logic in Experiments](experiment-retry)