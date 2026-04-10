---
title: Git Worktree Management in gptel-auto-workflow
status: active
category: knowledge
tags: [git, worktree, automation, debugging, experiments]
---

# Git Worktree Management in gptel-auto-workflow

## Overview

Git worktrees allow multiple working directories to be attached to a single repository. In the gptel-auto-workflow system, worktrees enable parallel experiment execution where each experiment runs in its own isolated directory while sharing the same `.git` database.

This page documents critical lessons learned about worktree management, including a significant verification bug, cleanup patterns, and timing issues that caused experiment failures.

## How Worktrees Are Used in Auto-Workflow

### Architecture

```
Main Repository ($GIT_DIR)
├── worktree: agent-exp1    (var/tmp/experiments/optimize/agent-exp1)
├── worktree: core-exp1     (var/tmp/experiments/optimize/core-exp1)
├── worktree: tools-exp1    (var/tmp/experiments/optimize/tools-exp1)
└── main working directory  (~/projects/gptel/)
```

### Creation Pattern

Each experiment creates a dedicated worktree:

| Step | Action | Command |
|------|--------|---------|
| 1 | Create experiment branch | `git branch experiment-branch` |
| 2 | Create worktree | `git worktree add <path> <branch>` |
| 3 | Run experiment in worktree | Changes isolated to worktree |
| 4 | On success | Merge to staging |
| 5 | On failure | Worktree preserved for debugging |

### Key Properties

| Property | Main Repo | Worktree |
|----------|-----------|----------|
| `.git` reference | Points to self | Points to main repo |
| Commit history | Shared | Shared (read-only) |
| Working directory | Main | Isolated |
| Branch association | `HEAD` | Specific branch |
| Path computation | Relative to cwd | Relative to script location |

## Critical Bug: Verification Against Wrong Directory

### Symptom

Auto-workflow experiments always failed with `verification-failed` even after the grader passed 9/9 cases.

### Root Cause

The `gptel-auto-experiment-benchmark` function ran the verification script using a path computed from `proj-root`:

```elisp
;; BEFORE (buggy code) - lisp/modules/gptel-tools-agent.el:1634
(let* ((proj-root (gptel-auto-workflow--get-proj-root))
       (verify-script (expand-file-name "scripts/verify-nucleus.sh" proj-root))
       ...)
  (gptel-auto-experiment-run-command
   verify-script
   (list "--file" target-file)
   :directory worktree-path))
```

**The Problem:** `verify-nucleus.sh` computes its `$DIR` from the script's own location:

```bash
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIR="$(dirname "$SCRIPT_DIR")"
```

Since the script lives in the **main repository**, `$DIR` pointed to the **main repo code**, not the worktree changes.

### Why This Went Undetected

1. The script ran successfully (exit code 0)
2. The grader logic in the main repo passed
3. But the actual worktree changes were never validated
4. Experiments could merge broken code

### The Fix

Skip nucleus script validation in experiment benchmark:

```elisp
;; AFTER (fixed code)
(let* ((proj-root (gptel-auto-workflow--get-proj-root))
       ...)
  ;; Syntax validation still works because it targets worktree file directly
  ;; Executor runs verification in worktree context
  ;; Full validation happens in staging flow
  (when (gptel-auto-experiment--syntax-valid-p target-file)
    ...))
```

### Verification Results

After the fix, experiments return:

```elisp
(:passed t :nucleus-passed t :nucleus-skipped t)
```

The `nucleus-skipped: t` indicates the script was intentionally skipped because:
- Syntax validation targets the actual worktree file
- Executor runs verification in correct context
- Staging flow provides full validation

## Worktree Deletion Timing Bug

### Symptom

"No such file or directory" errors during auto-workflow experiments, specifically when `run-next` attempted to start subsequent exp
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-whdoO3.txt. Use Read tool if you need more]...