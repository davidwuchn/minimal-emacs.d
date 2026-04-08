# Staging-Merge Failure Pattern

## Problem
Auto-workflow kept experiments were not being merged to staging branch.

## Symptom
- Results TSV shows: `staging-merge discarded staging-merge-failed`
- Comparator reason: `Failed to merge optimize/{branch} to staging`
- Agent output: empty (no detailed error logged)

## Root Cause
Optimize branches are created during experiments and based on the state at experiment start time. By the time the experiment is "kept" and ready to merge to staging:
1. Staging may have advanced (new commits merged)
2. Optimize branch is behind staging
3. `git merge -X theirs` fails (conflict resolution not sufficient)

## Manual Fix
```bash
git checkout staging
git merge optimize/{branch} -m "Merge optimize/{branch} for verification"
./scripts/run-tests.sh unit  # Verify tests pass
git push origin staging
```

## Affected Runs
- 2026-04-08T180000Z-7ca9: 2 staging-merge failures (cache, core experiments)

## Code Location
`gptel-auto-workflow--merge-to-staging` (gptel-tools-agent.el:2923)
- Uses `git merge -X theirs --no-ff`
- Resets staging to origin/staging before merge
- Problem: doesn't rebase optimize branch onto staging first

## Potential Fix
Before merging, rebase optimize branch onto staging:
```elisp
(gptel-auto-workflow--git-result
 (format "git rebase %s %s" staging-q optimize-branch-q)
 180)
```

## Lesson
Always manually check staging branch after auto-workflow runs to ensure kept experiments are merged.