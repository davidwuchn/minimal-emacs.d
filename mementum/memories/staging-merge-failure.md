# Staging-Merge Failure Pattern (FIXED)

## Problem (Historical)
Auto-workflow kept experiments were not being merged to staging branch due to branch divergence.

## Root Cause
Optimize branches are created from `main` at experiment start. By the time the experiment is "kept":
1. Staging may have advanced (new commits merged)
2. Optimize branch is behind staging
3. `git merge -X theirs` fails due to branch history conflicts

## Solution (Implemented)
Changed `gptel-auto-workflow--merge-to-staging` to use cherry-pick instead of merge:

```elisp
;; Before: git merge -X theirs optimize/branch --no-ff
;; After:  git cherry-pick --no-commit <commit-hash>
;;         git commit -m "Merge optimize/branch for verification"
```

**Benefits:**
- Cherry-pick applies only the tip commit changes
- Works even when staging has moved forward
- No branch history conflicts
- Falls back to merge if cherry-pick fails
- No manual intervention needed

## Code Location
`gptel-auto-workflow--merge-to-staging` (gptel-tools-agent.el:2931)

## Test
`regression/auto-workflow/merge-to-staging-resets-worktree-before-merge`

## Commit
`e293aa29` - ⚒ fix: use cherry-pick instead of merge for staging integration

## Status
✅ FIXED - No manual intervention needed after this commit.