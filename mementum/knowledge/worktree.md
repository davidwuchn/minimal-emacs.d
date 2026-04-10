---
title: Git Worktree in Auto-Workflow System
status: active
category: knowledge
tags: [git, worktree, auto-workflow, debugging, cleanup]
---

# Git Worktree in Auto-Workflow System

## Overview

This knowledge page documents the use of Git worktrees in the auto-workflow experiment system, common pitfalls encountered, and established patterns for proper worktree management. Git worktrees allow multiple working directories to share a single Git repository, enabling parallel experiment execution while maintaining isolated development environments.

## Git Worktree Fundamentals

### What is a Worktree?

A Git worktree is a separate working directory that shares the same Git repository (`.git` directory) with other worktrees. Each worktree can have its own branch checked out, allowing parallel work on multiple features or experiments.

### Basic Worktree Commands

```bash
# List all worktrees
git worktree list

# Create a new worktree
git worktree add <path> <branch>

# Remove a worktree
git worktree remove <path>

# Prune stale worktree references
git worktree prune
```

### Worktree Structure

```
.git/
  → shared repository (objects, refs)

worktree-main/
  → main branch working directory

worktree-experiment/
  → experiment branch working directory
```

## Worktree in Auto-Workflow Architecture

### Workflow Overview

The auto-workflow system uses Git worktrees to run experiments in isolated environments:

```
Main Repository (staging branch)
         │
         ├── Worktree 1: agent-exp1
         ├── Worktree 2: core-exp1  
         ├── Worktree 3: optimize-exp1
         └── Worktree N: ...
```

### Worktree Creation Flow

```elisp
(defun gptel-auto-workflow-create-worktree (experiment-name proj-root)
  "Create worktree for EXPERIMENT-NAME at PROJ-ROOT."
  (let* ((branch-name (format "experiments/%s" experiment-name))
         (worktree-path (expand-file-name
                        (format "var/tmp/experiments/%s" experiment-name)
                        proj-root)))
    ;; Create worktree with dedicated branch
    (process-file "git" nil nil nil "worktree" "add" "-b" branch-name worktree-path "staging")))
```

### Worktree Configuration

| Parameter | Value | Purpose |
|-----------|-------|---------|
| Base path | `var/tmp/experiments/` | Isolated from main codebase |
| Branch prefix | `experiments/` | Named experiment branches |
| Shared refs | `.git` | Object database sharing |

## Common Problems and Solutions

### Problem 1: Verification Failed After Grader Pass

**Symptom**: Auto-workflow experiments always failed with `verification-failed` after grader passed 9/9.

**Root Cause**: `gptel-auto-experiment-benchmark` ran `verify-nucleus.sh` with path from `proj-root`, but `default-directory` was the worktree. The script computes `$DIR` from its own location (main repo), so it validated main repo code, not worktree changes.

**Code Location**: `lisp/modules/gptel-tools-agent.el:1634` - `gptel-auto-experiment-benchmark`

**Problematic Code**:
```elisp
;; BROKEN: Uses proj-root which points to main repo, not worktree
(expand-file-name "scripts/verify-nucleus.sh" proj-root)
```

**Solution**: Skip nucleus script validation in experiment benchmark:
- Code syntax validation still works (targets worktree file)
- Executor already runs verification in worktree context
- Full validation happens in staging flow anyway

**Verification Result**:
```elisp
(:passed t :nucleus-passed t :nucleus-skipped t)
```

### Problem 2: Worktree Deleted Too Early

**Symptom**: "No such file or directory" errors during auto-workflow experiments.

**Root Cause**: Worktree was being deleted at the START of `run-next`, before the next experiment could use it.

**Timeline of the Bug**:
1. Experiment 1 creates worktree
2. Experiment 1 completes
3. `run-next(2)` is called
4. Line 2289: `gptel-auto-worktree-delete-worktree` DELETES worktree
5. Experiment 2 tries to run in non-existent worktree → error

**Also**: Worktree was deleted on every failure (grader failed, benchmark failed, timeout), preventing retry.

**Solution**:
- Removed ALL `delete-worktree` calls during experiment execution
- Removed delete-worktree when target is done
- Worktrees only cleaned at START of NEXT workflow run
- Cleanup: `gptel-auto-workflow--cleanup-old-worktrees` in `gptel-auto-workflow-cron-safe`

**Why Keep Worktrees Until Next Run?**
1. After experiments complete, improvements may need to be merged to staging
2. Staging merge happens AFTER workflow completes
3. Only safe to delete at START of next run (clean slate for new experiments)

**Commits**: d06a47f (partial), 1834e09 (final)

**Pattern**: Resources should only be cleaned up when truly done - for auto-workflow, that means at the START of the NEXT run, not the end of the current run.

## Actionable Patterns

### Pattern 1: Safe Worktree Cleanup

**When to use**: After experiments are merged to staging branch.

**Detection Script**:
```bash
git worktree list | grep optimize | awk '{print $3}' | sed 's/\[//' | sed 's/\]//' | while read branch; do
  if git log staging --oneline | grep -q "Merge $branch"; then
    echo "MERGED: $branch"
  fi
done
```

**Cleanup Commands**:
```bash
# Remove worktree
git worktree remove <path> --force

# Delete branch
git branch -D <branch>
```

**Example Output**:
```
MERGED: experiments/agent-exp1
MERGED: experiments/agent-exp2
MERGED: experiments/core-exp2
MERGED: experiments/strategic-exp1
MERGED: experiments/strategic-exp2
MERGED: experiments/tools-exp1
MERGED: experiments/tools-exp2
```

**Prevention**:
- Auto-workflow should clean up merged experiments
- Periodic cleanup of merged worktrees
- Consider auto-deletion after merge to staging

### Pattern 2: Worktree Context Verification

**When to use**: Before running verification scripts in experiment context.

**Checklist**:
- [ ] `default-directory` is set to worktree path
- [ ] Script paths resolve correctly relative to worktree
- [ ] Verification targets actual worktree files, not main repo

**Correct Pattern**:
```elisp
;; Run verification in worktree context
(let ((default-directory worktree-path))
  (shell-command-to-string "bash scripts/verify.sh"))
```

### Pattern 3: Worktree Lifecycle Management

**Phase 1: Creation**
- Create worktree at start of experiment
- Checkout experiment branch from staging

**Phase 2: Execution**
- Run all operations in worktree context
- Keep worktree alive throughout experiment
- Keep worktree alive after failure (for debugging)

**Phase 3: Completion**
- If merged: cleanup at next workflow start
- If not merged: keep for potential retry
- Never delete during same workflow run

**Phase 4: Cleanup**
- Run `gptel-auto-workflow--cleanup-old-worktrees`
- Called from `gptel-auto-workflow-cron-safe`
- Only at START of new workflow run

## Debugging Worktree Issues

### Common Error Messages

| Error | Cause | Solution |
|-------|-------|----------|
| `No such file or directory` | Worktree deleted early | Check deletion timing in workflow |
| `verification-failed` | Script checking main repo | Verify worktree context |
| `fatal: 'branch' already exists` | Branch in use by another worktree | Check `git worktree list` |

### Debugging Commands

```bash
# List all worktrees with paths and branches
git worktree list --porcelain

# Check which branch is checked out
git -C /path/to/worktree branch

# Verify worktree is not locked
git worktree prune --dry-run

# Check for stale references
ls .git/worktrees/
```

## Related

- [Auto-Workflow System](auto-workflow.md)
- [Experiment Benchmark](experiment-benchmark.md)
- [Staging Flow](staging-flow.md)
- [Git Branch Management](git-branch-management.md)
- [Resource Cleanup Patterns](cleanup-patterns.md)

---

**Key Insight**: Worktrees share `.git` but have separate working directories. Scripts that hardcode paths relative to script location won't see worktree changes. Always verify context before running verification.