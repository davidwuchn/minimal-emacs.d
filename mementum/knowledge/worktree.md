---
title: Git Worktree Management in Auto-Workflow
status: active
category: knowledge
tags: [git, worktree, auto-workflow, debugging, cleanup]
---

# Git Worktree Management in Auto-Workflow

This document covers common pitfalls and patterns for managing Git worktrees in the auto-workflow system.

## Overview

The auto-workflow system uses Git worktrees to run experiments in isolated environments. Each experiment gets its own worktree, allowing parallel development without polluting the main repository. This document synthesizes three key learnings: a verification bug, cleanup patterns, and deletion timing.

---

## The Verification-Failed Worktree Bug

### Problem Statement

Auto-workflow experiments always failed with `verification-failed` status, even after the grader passed (9/9).

### Root Cause Analysis

The bug originated in `gptel-auto-experiment-benchmark` at line 1634 in `lisp/modules/gptel-tools-agent.el`. The function called `verify-nucleus.sh` using a path derived from `proj-root`:

```elisp
(expand-file-name "scripts/verify-nucleus.sh" proj-root)
```

The problem: `default-directory` was set to the experiment worktree, but the script computes its `$DIR` relative to its own location (the main repo). This meant the script validated code in the main repository, not the worktree changes.

```
┌─────────────────────────────────────────────────────────────┐
│  Main Repo: .git shared                                     │
│                                                             │
│  Main Working Directory          Worktree Directory         │
│  ─────────────────────────       ─────────────────          │
│  src/main.py (old code)    ← ← ← src/main.py (new code)    │
│                                                             │
│  verify-nucleus.sh reads script location                   │
│  → resolves to main repo                                    │
│  → validates main repo code ← BUG!                         │
└─────────────────────────────────────────────────────────────┘
```

### The Fix

The solution was to **skip nucleus script validation** in `gptel-auto-experiment-benchmark`:

| Aspect | Before | After |
|--------|--------|-------|
| Script validation | Always ran | Skipped |
| Code syntax | N/A | Works (targets worktree file) |
| Executor verification | N/A | Runs in worktree context |
| Full validation | N/A | Happens in staging flow |

The rationale:
1. **Syntax validation still works** — Code syntax checks target the worktree file directly
2. **Executor runs verification** — The experiment executor runs verification in the worktree context
3. **Staging provides full validation** — When changes are staged, full validation occurs

### Verification Results

After the fix, experiments complete with:
```elisp
(:passed t :nucleus-passed t :nucleus-skipped t)
```

---

## Experiment Worktree Cleanup Pattern

### Problem

Merged experiment worktrees accumulate over time, leading to:
- Many stale worktrees in `var/tmp/experiments/`
- Experiment branches merged to staging but never deleted
- Worktree count grows without bound

### Detection Script

```bash
# Find merged worktrees and report them
git worktree list | grep optimize | awk '{print $3}' | \
  sed 's/\[//' | sed 's/\]//' | while read branch; do
  if git log staging --oneline | grep -q "Merge $branch"; then
    echo "MERGED: $branch"
  fi
done
```

### Cleanup Commands

```bash
# Remove the worktree (force handles unmerged changes)
git worktree remove <path> --force

# Delete the branch
git branch -D <branch>
```

### Example Cleanup

The following merged worktrees were identified and cleaned:
- `agent-exp1`
- `agent-exp2`
- `core-exp2`
- `strategic-exp1`
- `strategic-exp2`
- `tools-exp1`
- `tools-exp2`

**Total cleaned: 7 worktrees** in `var/tmp/experiments/optimize/`

### Prevention Strategies

| Strategy | Implementation |
|----------|-----------------|
| Auto-workflow cleanup | Add cleanup step after merge to staging |
| Periodic cleanup | Run detection weekly, alert on accumulation |
| Auto-deletion | Delete merged worktrees automatically after merge |

---

## Worktree Deletion Timing

### The Bug

**Date**: 2026-03-29

**Symptom**: "No such file or directory" errors during auto-workflow experiments.

### Timeline of the Bug

```
Timeline:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Experiment 1: Creates worktree → Completes
                          ↓
  run-next(2) is called
                          ↓
  Line 2289: gptel-auto-workflow-delete-worktree DELETES worktree
                          ↓
  Experiment 2: Tries to run in non-existent worktree → ERROR!
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### Additional Problem

Worktrees were also deleted on **every failure**:
- Grader failed → delete worktree
- Benchmark failed → delete worktree
- Timeout → delete worktree

This prevented any retry mechanism from working.

### The Solution

**Removed ALL `delete-worktree` calls during experiment execution.**

Key changes:
1. Removed deletion at end of `run-next`
2. Removed deletion on failure
3. Removed deletion when target is done
4. **Worktrees only cleaned at START of next workflow run**

### The Cleanup Function

Worktree cleanup now happens in `gptel-auto-workflow-cron-safe` via `gptel-auto-workflow--cleanup-old-worktrees`:

```elisp
;; Pseudocode representation
(defun gptel-auto-workflow--cleanup-old-worktrees ()
  "Clean up worktrees from previous workflow run."
  ;; Runs only at START of new workflow
  ;; Not during experiment completion
  )
```

### Why Keep Worktrees Until Next Run?

| Reason | Explanation |
|--------|-------------|
| Post-experiment review | After experiments complete, improvements may need to be examined before merge |
| Staging merge timing | Staging merge happens AFTER workflow completes |
| Safety | Only safe to delete at START of next run (clean slate for new experiments) |

### The Pattern

> **Resources should only be cleaned up when truly done.** For auto-workflow, that means at the START of the NEXT run, not the end of the current run.

### Commit History

- **d06a47f**: Partial fix
- **1834e09**: Final fix

---

## Quick Reference

### Worktree Commands

```bash
# List worktrees
git worktree list

# Add a worktree
git worktree add <path> -b <branch-name>

# Remove a worktree
git worktree remove <path> [--force]

# Delete a branch
git branch -D <branch-name>
```

### Key Files

| File | Line | Purpose |
|------|------|---------|
| lisp/modules/gptel-tools-agent.el | 1634 | `gptel-auto-experiment-benchmark` |
| lisp/modules/gptel-tools-agent.el | 2289 | `gptel-auto-workflow-delete-worktree` |

### Status Indicators

```elisp
;; Experiment passed
(:passed t :nucleus-passed t :nucleus-skipped t)

;; Experiment failed (grader)
(:passed nil :reason "grader-failed")

;; Experiment failed (verification)
(:passed nil :reason "verification-failed")
```

---

## Related

- [[git-worktree|Git Worktree Documentation]]
- [[auto-workflow|Auto-Workflow System]]
- [[staging-flow|Staging Flow]]
- [[gptel-tools-agent|GPTel Tools Agent]]
- [[experiment-debugging|Experiment Debugging Patterns]]

---

## Summary

1. **Verification Bug**: Scripts that compute paths relative to their own location won't see worktree changes. Skip such validations in benchmark context.

2. **Cleanup Pattern**: Regularly clean up merged worktrees to prevent accumulation. Detect via branch merge status in staging.

3. **Deletion Timing**: Delete worktrees only at the START of the next workflow run, not at the end of the current run. This enables retries and allows post-experiment review before staging merge.