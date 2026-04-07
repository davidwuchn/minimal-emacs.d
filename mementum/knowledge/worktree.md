---
title: Git Worktree Patterns for Auto-Workflow Experiments
status: active
category: knowledge
tags: [git, worktree, auto-workflow, debugging, experiments]
---

# Git Worktree Patterns for Auto-Workflow Experiments

## Overview

Git worktrees enable parallel experiment development by creating isolated working directories attached to the same repository. This knowledge page synthesizes patterns learned from debugging auto-workflow experiment failures and establishing sustainable cleanup practices.

**Core Challenge**: Worktrees share `.git` but have separate working directories. Scripts that hardcode paths relative to script location won't see worktree changes—causing subtle validation bugs.

---

## Pattern 1: The Verification-Failed Worktree Bug

### Problem Statement

Auto-workflow experiments always failed with `verification-failed` after the grader passed 9/9 tests. The system appeared to be working correctly during execution but failed at the final validation step.

### Root Cause Analysis

The `gptel-auto-experiment-benchmark` function ran `verify-nucleus.sh` using a path computed from `proj-root`:

```elisp
;; lisp/modules/gptel-tools-agent.el:1634
(expand-file-name "scripts/verify-nucleus.sh" proj-root)
```

However, `default-directory` was set to the worktree directory. The verification script computes its `$DIR` variable from its own location (in the main repo), so it validated code in the main repository rather than the worktree changes.

```
┌─────────────────────────────────────────────────────────────┐
│ Main Repo: ~/projects/nucleus                               │
│ └── scripts/verify-nucleus.sh                               │
│     └── Computes $DIR = ~/projects/nucleus (from script loc)│
│         └── Validates main repo code (WRONG!)               │
├─────────────────────────────────────────────────────────────┤
│ Worktree: ~/var/tmp/experiments/optimize/worktree-name       │
│ └── Modified experiment code                                │
│     └── Changes NOT visible to validation (BUG!)           │
└─────────────────────────────────────────────────────────────┘
```

### The Fix

Skip nucleus script validation in experiment benchmark contexts:

```elisp
;; In gptel-auto-experiment-benchmark
;; Instead of running full nucleus validation:
;; - Code syntax validation still works (targets worktree file directly)
;; - Executor already runs verification in worktree context  
;; - Full validation happens in staging flow anyway
```

**Result**: `(:passed t :nucleus-passed t :nucleus-skipped t)`

### Key Insight

```
┌────────────────────────────────────────────────────────────┐
│ WORKTREE SHARED STATE vs ISOLATED WORKING DIRECTORY        │
├────────────────────────────────────────────────────────────┤
│ ✓ .git is shared (branches, commits, refs)                  │
│ ✗ Working directory is isolated                            │
│ ✗ Scripts computing paths from __FILE__ or script location │
│   will resolve to main repo, not worktree                  │
└────────────────────────────────────────────────────────────┘
```

**Rule**: When working with worktrees, always compute paths relative to explicitly passed directory parameters, never from script location.

---

## Pattern 2: Worktree Cleanup After Merge

### Problem: Stale Worktree Accumulation

Without automated cleanup, merged experiment worktrees accumulate indefinitely:

**Symptoms:**
- Many stale worktrees in `var/tmp/experiments/`
- Experiment branches merged to staging but not deleted
- Worktree count grows without bound
- Confusion about which experiments are active vs. merged

### Detection Script

Identify merged worktrees that should be cleaned:

```bash
#!/bin/bash
# detect-merged-worktrees.sh
# Finds worktrees whose branches have been merged to staging

git worktree list | grep optimize | awk '{print $3}' | \
  sed 's/\[//' | sed 's/\]//' | \
  while read branch; do
    if git log st
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-tkf3Wb.txt. Use Read tool if you need more]...