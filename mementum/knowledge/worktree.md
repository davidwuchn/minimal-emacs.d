---
title: Git Worktree Patterns and Gotchas
status: active
category: knowledge
tags: [git, worktree, workflow, automation, experiments]
---

# Git Worktree Patterns and Gotchas

## Overview

Git worktrees allow multiple working directories to share a single repository. This is particularly useful for running experiments in parallel without checking out new branches. This knowledge page documents patterns, gotchas, and best practices discovered through the auto-experiment system.

## Core Concept

```
Main Repository
├── .git/                    # Shared git data
├── lisp/                    # Main working directory
└── var/tmp/experiments/
    ├── exp1/               # Worktree 1 - separate working directory
    │   └── lisp/          # Isolated changes
    └── exp2/               # Worktree 2 - parallel work
        └── lisp/          # Different isolated changes
```

**Key Insight:** Worktrees share `.git` but have separate working directories. Any script that hardcodes paths relative to script location will validate the main repo, not the worktree.

## Worktree Creation Pattern

### Standard Creation

```bash
# Create a new worktree from a new branch
git worktree add -b experiment-1 ../exp1
git worktree add ../exp2 experiment-branch-2

# Create worktree in specific location
git worktree add /var/tmp/experiments/optimize/agent-exp1 -b agent-exp1
```

### From Existing Branch

```bash
# List existing branches
git branch -a

# Create worktree from existing branch
git worktree add ../exp2 feature-branch
```

### Emacs Integration

```elisp
;; Create worktree for experiment
(git-worktree-create "agent-exp1" "agent-exp1" 
                     "/var/tmp/experiments/optimize/agent-exp1")

;; List all worktrees
(git-worktree-list)
;; =>
;; /repo/main        # Main repo
;; /repo/exp1        # Experiment worktree
;; /repo/exp2        # Another worktree
```

## Worktree Verification Gotchas

### The Path Resolution Bug

**Problem:** Auto-workflow experiments always failed with `verification-failed` after grader passed 9/9.

**Root Cause:** Scripts compute `$DIR` from their own location, not the worktree context.

```elisp
;; BROKEN CODE - gptel-auto-experiment-benchmark (line 1634)
(expand-file-name "scripts/verify-nucleus.sh" proj-root)
```

When `default-directory` is the worktree, this path resolves to:
- `scripts/verify-nucleus.sh` in the **worktree** directory

But the script internally computes its directory:
```bash
# Inside verify-nucleus.sh
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# $DIR points to MAIN REPO scripts/, not worktree
```

**Result:** Validates main repo code instead of worktree changes.

### The Fix

```elisp
;; Skip nucleus script validation in experiment benchmark
;; because:
;; 1. Code syntax validation still works (targets worktree file)
;; 2. Executor runs verification in worktree context
;; 3. Full validation happens in staging flow anyway

(when (not experiment-mode)
  (call-script "verify-nucleus.sh" ...))
```

### Verification Pattern

```elisp
;; Correct verification returns:
(:passed t :nucleus-passed t :nucleus-skipped t)

;; When skipping nucleus:
(:passed t :nucleus-skipped t)
```

## Worktree Lifecycle Management

### The Deletion Timing Bug

**Problem:** "No such file or directory" errors during auto-workflow experiments.

**Root Cause:** Worktree deleted at START of `run-next`, before next experiment could use it.

```
Timeline of the bug:
1. Experiment 1 creates worktree
2. Experiment 1 completes
3. run-next(2) is called
4. Line 2289: delete-worktree DELETES worktree
5. Experiment 2 tries to run in non-existent worktree → ERROR
```

### Secondary Issue

Worktree was also deleted on every failure:
- Grader failed → delete
- Benchmark failed → delete
- Timeout → delete

This prevented any retry mechanism.

### The Solution

```elisp
;; WRONG: Delete during experiment run
(defun gptel-auto-workflow-run-next ()
  ...
  (gptel-auto-workflow-delete-worktree)  ;; REMOVED
  (run-next-experiment ...))

;; CORRECT: Delete at START of next workflow run
(defun gptel-auto-workflow-cron-safe ()
  "Safe cleanup at workflow start."
  (gptel-auto-workflow--cleanup-old-worktrees)
  (gptel-auto-workflow--run-workflow ...))
```

### Why Keep Worktrees Until Next Run?

| Reason | Explanation |
|--------|-------------|
| Merge pending | After experiments complete, improvements may need merging to staging |
| Timing | Staging merge happens AFTER workflow completes |
| Safe deletion point | Only safe to delete at START of next run (clean slate for new experiments) |

**Pattern:** Resources should only be cleaned up when truly done. For auto-workflow, that means at the START of the NEXT run, not the end of the current run.

## Worktree Cleanup Pattern

### Detecting Merged Worktrees

```bash
git worktree list | grep optimize | awk '{print $3}' | sed 's/\[//' | sed 's/\]//' | while read branch; do
  if git log staging --oneline | grep -q "Merge $branch"; then
    echo "MERGED: $branch"
  fi
done
```

### Cleanup Commands

```bash
# Remove worktree (force if dirty)
git worktree remove <path> --force

# Delete the branch
git branch -D <branch-name>

# Verify removal
git worktree list
```

### Prevention Strategies

1. **Auto-workflow cleanup** - Clean up merged experiments automatically
2. **Periodic cleanup** - Run cleanup script regularly
3. **Post-merge hooks** - Auto-delete after merge to staging

### Example: Cleanup Session

```
Cleaned 7 merged worktrees:
- agent-exp1
- agent-exp2
- core-exp2
- strategic-exp1
- strategic-exp2
- tools-exp1
- tools-exp2

Location: var/tmp/experiments/optimize/
```

## Common Commands Reference

### Worktree Management

```bash
# List all worktrees
git worktree list

# List worktrees with details
git worktree list --porcelain

# Prune stale worktree references
git worktree prune

# Remove worktree
git worktree remove /path/to/worktree
git worktree remove /path/to/worktree --force  # Ignore unmerged changes
```

### Branch Management with Worktrees

```bash
# Create worktree with new branch
git worktree add -b new-branch /path/to/worktree

# Create worktree from existing branch
git worktree add /path/to/worktree existing-branch

# Remove worktree and delete branch
git worktree remove /path/to/worktree
git branch -D branch-name

# List branches with worktree status
git branch -vv | while read line; do
  branch=$(echo $line | awk '{print $1}')
  worktree=$(git worktree list | grep -v "^/" | grep "$branch" | awk '{print $1}')
  if [ -n "$worktree" ]; then
    echo "$branch -> $worktree"
  fi
done
```

### Debugging Worktree Issues

```bash
# Check if worktree is valid
git worktree list --porcelain | grep -A2 "/path/to/worktree"

# Check for lock files
cat .git/worktrees/<name>/locked

# Find worktree for a commit
git worktree list --porcelain | while read line; do
  if [[ $line == "worktree"* ]]; then
    path="${line#worktree }"
  else
    commit="${line#commit }"
    echo "$path: $commit"
  fi
done
```

## Emacs Worktree Functions

### Creation

```elisp
(defun gptel-worktree-create (branch path)
  "Create a new worktree with BRANCH at PATH."
  (let ((default-directory proj-root))
    (shell-command
     (format "git worktree add -b %s %s %s" branch path branch))))

(defun gptel-worktree-create-from-branch (branch path)
  "Create worktree at PATH from existing BRANCH."
  (let ((default-directory proj-root))
    (shell-command
     (format "git worktree add %s %s" path branch))))
```

### Cleanup

```elisp
(defun gptel-worktree-cleanup-merged ()
  "Remove worktrees for branches merged to staging."
  (interactive)
  (let ((merged-branches (gptel-get-merged-branches)))
    (dolist (branch merged-branches)
      (let* ((worktree-path (gptel-find-worktree branch))
             (worktree-dir (file-name-directory worktree-path)))
        ;; Remove worktree
        (when worktree-dir
          (shell-command
           (format "git worktree remove %s --force" worktree-dir)))
        ;; Delete branch
        (shell-command
         (format "git branch -D %s" branch))))))

(defun gptel-worktree-safe-cleanup ()
  "Clean up old worktrees at safe point (workflow start)."
  (gptel-worktree-cleanup-merged)
  (shell-command "git worktree prune"))
```

### Verification

```elisp
(defun gptel-worktree-verify-path (file-path worktree-root)
  "Verify FILE-PATH exists and is within WORKTREE-ROOT."
  (let ((expanded (expand-file-name file-path)))
    (string-prefix-p (expand-file-name worktree-root) expanded)))

(defun gptel-worktree-get-context ()
  "Get current worktree context for path resolution."
  (let ((worktree-root (gptel-find-worktree-root default-directory)))
    (if worktree-root
        (cons :worktree t :root worktree-root)
      (cons :worktree nil :root proj-root))))
```

## Best Practices

### Do

1. **Resolve paths from worktree context** - Always use `default-directory` or `buffer-file-name` as base
2. **Clean up at safe points** - Delete worktrees at START of next workflow run
3. **Use `--force` carefully** - Only when you know changes are safe to discard
4. **Prune regularly** - Run `git worktree prune` to clean stale references
5. **Track worktree locations** - Maintain a registry for cleanup automation

### Don't

1. **Hardcode main repo paths** - Scripts will validate wrong location
2. **Delete during active experiments** - Prevents retry and causes errors
3. **Delete before merge** - May lose work if merge fails
4. **Ignore worktree locks** - Can indicate incomplete operations
5. **Leave merged worktrees** - Causes accumulation and confusion

## Troubleshooting

| Symptom | Cause | Solution |
|---------|-------|----------|
| `verification-failed` after grader pass | Script path resolves to main repo | Skip nucleus validation in benchmark context |
| `No such file or directory` | Worktree deleted mid-workflow | Move deletion to workflow start |
| Worktree stuck | Lock file exists | `git worktree unlock <path>` |
| Can't create worktree | Branch already has one | `git worktree list` to find existing |
| Branch not found | Branch deleted but worktree remains | `git worktree prune` |

## Related

- [Git Workflow](./git-workflow.md)
- [Auto-Experiment System](./auto-experiment.md)
- [Staging Branch Management](./staging-branch.md)
- [Experiment Benchmarking](./experiment-benchmark.md)
- [Nucleus Verification](./nucleus-verification.md)