---
title: Git Worktree Management in Auto-Workflow
status: active
category: knowledge
tags: [git, worktree, automation, debugging, patterns]
---

# Git Worktree Management in Auto-Workflow

## Overview

Git worktrees are a critical component of the auto-workflow system, enabling parallel experiment execution and isolated testing environments. This knowledge page documents key patterns, bugs, and best practices for managing worktrees in automated experiment workflows.

## Core Concepts

### What is a Worktree?

A Git worktree allows multiple working directories to share a single repository. This is essential for running experiments in isolation while maintaining a shared git history.

```
Main Repository: ~/.emacs.d/
Worktree:       var/tmp/experiments/optimize/agent-exp1/
```

### Worktree Structure

| Component | Path | Purpose |
|-----------|------|---------|
| `.git` | Shared (symlink) | Git database |
| Working directory | Unique per worktree | Actual code files |
| Branch | Unique per worktree | Experiment branch |

---

## Key Patterns

### Pattern 1: Worktree Creation for Experiments

Worktrees are created for each experiment to ensure isolation:

```bash
git worktree add <path> -b <branch-name>
```

Example from auto-workflow:
```bash
git worktree add var/tmp/experiments/optimize/agent-exp1 -b optimize/agent-exp1
```

### Pattern 2: Worktree Cleanup After Merge

When experiments are merged to staging, their worktrees should be cleaned up:

```bash
# Detection: Find merged experiment branches
git worktree list | grep optimize | awk '{print $3}' | sed 's/\[//' | sed 's/\]//' | while read branch; do
  if git log staging --oneline | grep -q "Merge $branch"; then
    echo "MERGED: $branch"
  fi
done

# Cleanup
git worktree remove <path> --force
git branch -D <branch>
```

**Example:** Cleaned 7 merged worktrees (agent-exp1, agent-exp2, core-exp2, strategic-exp1, strategic-exp2, tools-exp1, tools-exp2)

---

## Critical Bug: Verification Failed in Worktree

### Problem

Auto-workflow experiments always failed with `verification-failed` after grader passed 9/9.

### Root Cause

The `gptel-auto-experiment-benchmark` function ran `verify-nucleus.sh` with path from `proj-root`:

```elisp
(expand-file-name "scripts/verify-nucleus.sh" proj-root)
```

However, `default-directory` was the worktree. The script computes `$DIR` from its own location (main repo), so it validated main repo code, not worktree changes.

### The Bug in Detail

```
Main Repo:     ~/.emacs.d/
Worktree:      var/tmp/experiments/optimize/agent-exp1/
Script Path:   ~/.emacs.d/scripts/verify-nucleus.sh (hardcoded to main repo)
Script $DIR:   ~/.emacs.d/ (computed from script location)
Validation:    Validates ~/.emacs.d/ instead of worktree!
```

### Solution

Skip nucleus script validation in experiment benchmark:
- Code syntax validation still works (targets worktree file)
- Executor already runs verification in worktree context
- Full validation happens in staging flow anyway

```elisp
;; In gptel-auto-experiment-benchmark (lisp/modules/gptel-tools-agent.el:1634)
;; Removed verification that used script path from main repo
```

### Verification

After fix:
```elisp
(:passed t :nucleus-passed t :nucleus-skipped t)
```

---

## Critical Bug: Worktree Deletion Timing

### Problem

"No such file or directory" errors during auto-workflow experiments.

### Timeline of the Bug

1. Experiment 1 creates worktree
2. Experiment 1 completes
3. `run-next(2)` is called
4. Line 2289: `gptel-auto-worktree-delete-worktree` DELETES worktree
5. Experiment 2 tries to run in non-existent worktree → error

### Additional Issue

Worktree was deleted on every failure (grader failed, benchmark failed, timeout), preventing retry.

### Solution

- Removed ALL `delete-worktree` calls during experiment execution
- Removed delete-worktree when target is done
- Worktrees only cleaned at START of next workflow run
- Cleanup: `gptel-auto-worktree--cleanup-old-worktrees` in `gptel-auto-workflow-cron-safe`

### Commits

- `d06a47f` - Partial fix
- `1834e09` - Final fix

### Why Keep Worktrees Until Next Run?

1. After experiments complete, improvements may need to be merged to staging
2. Staging merge happens AFTER workflow completes
3. Only safe to delete at START of next run (clean slate for new experiments)

### Pattern: Resource Lifecycle Management

> Resources should only be cleaned up when truly done - for auto-workflow, that means at the START of the NEXT run, not the end of the current run.

---

## Worktree Commands Reference

### Common Operations

```bash
# List all worktrees
git worktree list

# Create worktree
git worktree add <path> -b <branch>

# Remove worktree
git worktree remove <path>

# Force remove (if files exist)
git worktree remove <path> --force

# Prune stale worktree references
git worktree prune
```

### Debugging Worktree Issues

```bash
# Check which branch a worktree is on
git worktree list

# Verify worktree is valid
git -C <worktree-path> status

# Check for file conflicts
git -C <worktree-path> diff --name-only
```

---

## Best Practices

### 1. Always Use Absolute Paths in Scripts

When scripts need to reference files, use absolute paths or pass paths as arguments:

```bash
# BAD: Script computes path from its location
$DIR/scripts/verify.sh

# GOOD: Script accepts path as argument
./verify.sh /absolute/path/to/worktree
```

### 2. Clean Up at Workflow Boundaries

- Clean old worktrees at the START of a new workflow run
- Never clean during experiment execution
- Allow cleanup between workflow runs for merge operations

### 3. Track Worktree State

```elisp
;; Store worktree path for later cleanup
(setq current-worktree-path (expand-file-name "var/tmp/experiments/..." project-root))
```

### 4. Handle Failures Gracefully

Never delete worktree on experiment failure - this prevents debugging and retry:

```bash
# BAD: Delete on every failure
(when (or grader-failed benchmark-failed timeout)
  (delete-worktree worktree-path))

# GOOD: Keep until next workflow run
;; Only cleanup in gptel-auto-workflow-cron-safe
```

---

## Related Topics

- [[auto-workflow]] - The automated experiment workflow system
- [[staging]] - Where experiment results are merged
- [[verification]] - Code verification process
- [[git-branching]] - Branch management strategies
- [[benchmark]] - Experiment benchmarking

---

## Summary

Worktree management is critical for reliable auto-workflow execution:

1. **Path Resolution**: Scripts must not hardcode paths relative to their location - they won't see worktree changes
2. **Cleanup Timing**: Delete worktrees at workflow boundaries, not during execution
3. **Merge Cleanup**: Remove worktrees for experiments merged to staging
4. **Failure Handling**: Keep worktrees on failure to enable debugging and retry

Key insight: Worktrees share `.git` but have separate working directories. Scripts that compute paths from their own location will always target the main repo, not the worktree.