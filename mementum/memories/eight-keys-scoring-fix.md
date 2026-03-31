# Eight Keys Scoring: Commit Before Score

**Symbol:** ❌ mistake  
**Date:** 2026-03-31

## Problem

All auto-workflow experiments showed "Winner: tie" with identical scores (0.40 → 0.40). Every improvement was discarded because the comparator saw no improvement.

## Root Cause

The Eight Keys scoring function uses `git log -1` (last commit message) and `git diff HEAD~1` (code diff) to calculate scores.

The flow was:
1. Calculate baseline (before experiment)
2. Create worktree
3. Run executor (makes changes)
4. Calculate after score

The executor changes were **not committed** before the after score was calculated. So `git diff HEAD~1` showed the same thing for both baseline and after - the last committed changes, not the executor's improvements.

## Fix

Commit the executor's changes BEFORE running the benchmark:

```elisp
;; Grader passed - commit changes, then run benchmark
(let ((commit-dir (or (gptel-auto-workflow--get-worktree-dir target)
                      (gptel-auto-workflow--project-root))))
  (when commit-dir
    (let ((default-directory commit-dir))
      (magit-git-success "add" "-A")
      (magit-git-success "commit" "-m" (format "WIP: experiment %s" target)))))
```

## Lesson

When scoring code changes with git commands:
- Ensure changes are committed before scoring
- `git diff HEAD~1` only shows committed changes
- Uncommitted working directory changes need `git diff HEAD` or commit first

## Location

`lisp/modules/gptel-tools-agent.el:2377-2382`