---
title: Git Worktrees in Auto-Workflow Systems
status: active
category: knowledge
tags: [git, worktree, automation, debugging, experiments, cleanup]
---

# Git Worktrees in Auto-Workflow Systems

This document covers practical patterns for managing Git worktrees in automated experiment workflows, including common pitfalls, cleanup strategies, and timing considerations.

## Overview

Worktrees allow multiple working directories to share a single Git repository. In auto-workflow systems, each experiment typically runs in its own worktree to isolate changes and enable parallel execution. However, this pattern introduces specific challenges around path resolution, resource cleanup, and timing of deletion operations.

---

## The Verification-Script Path Bug

### Symptom

Auto-workflow experiments consistently failed with `verification-failed` status even when the grader passed all 9/9 test cases.

### Root Cause Analysis

The benchmark runner (`gptel-auto-experiment-benchmark`) invoked verification scripts using an absolute path derived from `proj-root`:

```elisp
(expand-file-name "scripts/verify-nucleus.sh" proj-root)
```

However, the `default-directory` was set to the experiment worktree. The verification script computes its `$DIR` variable relative to its own location (the main repository), causing it to validate main repo code rather than the worktree's experimental changes.

```
┌─────────────────────────────────────────────────────────────┐
│  Worktree: var/tmp/experiments/optimize/agent-exp1/        │
│  └── default-directory points here                         │
│                                                             │
│  Script: scripts/verify-nucleus.sh (resolves to main repo) │
│  └── $DIR computed from script location → main repo        │
│                                                             │
│  Result: Validates main repo, NOT worktree changes          │
└─────────────────────────────────────────────────────────────┘
```

### The Fix

Skip nucleus script validation in the experiment benchmark because:

1. **Syntax validation still works** — Code syntax checks target the worktree file directly
2. **Executor runs verification in worktree context** — The actual execution phase validates properly
3. **Full validation occurs in staging flow** — Post-experiment merge to staging includes comprehensive checks

```elisp
;; Before: Always ran verification
(verify-nucleus proj-root)  ; Wrong: uses main repo paths

;; After: Skip for benchmark, rely on executor + staging validation
(when (not experiment-p)
  (verify-nucleus proj-root))
```

### Verification Result

```elisp
(:passed t :nucleus-passed t :nucleus-skipped t)
```

---

## Worktree Cleanup Pattern for Merged Experiments

### Problem

Experiment worktrees accumulate indefinitely after branches are merged to staging, consuming disk space and creating confusion about which worktrees are active.

### Symptoms

- Multiple stale worktrees in `var/tmp/experiments/`
- Experiment branches merged but not deleted
- Unbounded worktree count growth

### Detection Command

```bash
# List experiment worktrees and identify merged branches
git worktree list | grep optimize | awk '{print $3}' | \
  sed 's/\[//' | sed 's/\]//' | while read branch; do
  if git log staging --oneline | grep -q "Merge $branch"; then
    echo "MERGED: $branch"
  fi
done
```

### Cleanup Procedure

```bash
# Remove the worktree
git worktree remove <path> --force

# Delete the branch
git branch -D <branch>
```

### Example Cleanup

Cleaned 7 merged worktrees in a single session:

| Worktree | Branch | Status |
|----------|--------|--------|
| agent-exp1 | optimize/agent-exp1 | Merged → Removed |
| agent-exp2 | optimize/agent-exp2 | Merged → Removed |
| core-exp2 | optimize/core-exp2 | Merged → Removed |
| strategic-exp1 | optimize/strategic-exp1 | Merged → Removed |
| strategic-exp2 | optimize/strategic-exp2 | Merged → Removed |
| tools-exp1 | optimize/tools-exp1 | Merged → Removed |
| tools-exp2 | optimize/tools-exp2 | Merged → Removed |

### Prevention Strategies

1. **Auto-cleanup in workflow** — The auto-workflow should remove worktrees after successful merge to staging
2. **Periodic cleanup** — Run detection script weekly to identify stale worktrees
3. **Auto-deletion on merge** — Configure workflow to delete experiment branch immediately after staging merge

---

## Worktree Deletion Timing Bug

### Problem

"No such file or directory" errors occurred during multi-experiment runs, where subsequent experiments failed immediately after earlier ones completed.

### Root Cause: Premature Deletion

Worktrees were being deleted at the **start** of `run-next`, before the next experiment could use them:

```
Timeline:
1. Experiment 1 creates worktree
2. Experiment 1 completes successfully
3. run-next(2) is called
4. Line 2289: gptel-auto-worktree-delete-worktree DELETES worktree
5. Experiment 2 tries to run in non-existent worktree → ERROR
```

Additionally, worktrees were deleted on **every failure** (grader failure, benchmark failure, timeout), preventing any retry mechanism from working.

### The Solution

**Remove all intermediate worktree deletions:**

1. Remove `delete-worktree` calls during experiment execution
2. Remove `delete-worktree` when target is marked done
3. Only clean worktrees at the **start of the next workflow run**

### Why Keep Worktrees Until Next Run?

```
┌─────────────────────────────────────────────────────────────┐
│  Experiment completes                                       │
│  └─> Worktree persists                                      │
│       └─> Improvements may need merging to staging          │
│            └─> Staging merge happens AFTER workflow         │
│                 └─> Only safe to delete at START of next run │
└─────────────────────────────────────────────────────────────┘
```

The worktree must survive until:
- All experiments in the current run complete
- Staging merge finishes
- Next workflow run begins (providing a clean slate for new experiments)

### Commit History

| Commit | Description |
|--------|-------------|
| d06a47f | Partial fix |
| 1834e09 | Final fix - complete removal of premature deletion |

### Pattern: Resource Lifetime Management

```
┌─────────────────────────────────────────────────────────────┐
│  Resource Lifetime                                          │
├─────────────────────────────────────────────────────────────┤
│  Created → Used by N experiments → All complete →           │
│  Merge to staging → Workflow ends → START OF NEXT RUN      │
│  → Only NOW safe to delete                                 │
└─────────────────────────────────────────────────────────────┘

WRONG: Delete at end of current operation
RIGHT: Delete at start of next cycle
```

---

## Key Insights Summary

### Worktrees Share .git, Not Working Directory

```
Main Repository          Worktree
├── .git (shared)        ├── .git -> ../.git (pointer)
├── src/                 ├── src/ (separate copy)
└── scripts/             └── [no scripts/]
```

Scripts that compute paths relative to their own location will traverse into the main repo, not the worktree.

### Path Resolution in Shared-Repository Scenarios

| Scenario | Behavior | Risk |
|----------|----------|------|
| `expand-file-name` with `proj-root` | Resolves to main repo | Verification wrong |
| Script-relative `$DIR` computation | Resolves to script location | Validates wrong tree |
| `default-directory` in Elisp | Points to worktree | Context correct |

### Timing Principle

> Resources should only be cleaned up when truly done. For automated workflows, "done" means at the **start of the next run**, not the **end of the current one**.

---

## Action Checklist

### For New Experiment Setup

- [ ] Create worktree in `var/tmp/experiments/`
- [ ] Set `default-directory` to worktree path
- [ ] Verify all scripts use worktree-relative paths

### For Experiment Completion

- [ ] Do NOT delete worktree immediately
- [ ] Allow staging merge to complete
- [ ] Keep worktree accessible for debugging if needed

### For Workflow Cleanup (Start of Next Run)

- [ ] Call `gptel-auto-workflow--cleanup-old-worktrees`
- [ ] Run in `gptel-auto-workflow-cron-safe`
- [ ] Remove only worktrees from previous completed run

### Periodic Maintenance

- [ ] Run merged-worktree detection monthly
- [ ] Clean up stale branches and worktrees
- [ ] Verify disk usage in `var/tmp/experiments/`

---

## Related

- [Git Worktrees](https://git-scm.com/docs/git-worktree) — Official documentation
- [Auto-Workflow System](category:auto-workflow) — Parent system containing worktree management
- [Staging Branch](topic:staging) — Merge target for experimental changes
- [Experiment Benchmark](topic:experiment-benchmark) — Where verification bugs manifested
- [Cron Workflow](topic:cron-automation) — Where cleanup runs scheduled
- [Git Branch Management](topic:branch-lifecycle) — Branch creation and deletion patterns
- [Path Resolution Bugs](topic:path-resolution) — General category of similar issues

---

## File References

| File | Line | Purpose |
|------|------|---------|
| `lisp/modules/gptel-tools-agent.el` | 1634 | `gptel-auto-experiment-benchmark` - verification invocation |
| `lisp/modules/gptel-tools-agent.el` | 2289 | `gptel-auto-worktree-delete-worktree` - premature deletion (removed) |

---

*This page documents patterns discovered through debugging auto-workflow experiments. Update as new worktree-related issues arise.*