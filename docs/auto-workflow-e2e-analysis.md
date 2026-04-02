# Auto-Workflow E2E Analysis & Fix Plan

**Date:** 2026-04-02
**Issue:** Staging merges failing, optimize branches not pushed to origin

## Current State

### ✓ What's Working

1. **Auto-workflow runs** - Cron jobs trigger, workflow executes
2. **Experiments execute** - Executor makes changes, grader validates
3. **TSV logging** - Results logged to `var/tmp/experiments/YYYY-MM-DD/results.tsv`
4. **Optimize branches created** - Local branches with hostname in name
5. **Worktrees created** - Each experiment gets isolated worktree

### ✗ What's Broken

1. **Staging merges failing** - "staging-merge-failed" in results.tsv
2. **Optimize branches NOT on remote** - `git branch -r | grep optimize` returns empty
3. **Push failures silently ignored** - `magit-git-success` returns nil on failure but code continues

## Root Cause Analysis

### Issue 1: Silent Push Failures

**Location:** `gptel-tools-agent.el:2854-2857`

```elisp
(when gptel-auto-experiment-auto-push
  (message "[auto-experiment] Pushing to %s" (gptel-auto-workflow--get-current-branch target))
  (magit-git-success "push" "origin" (gptel-auto-workflow--get-current-branch target))
  (when gptel-auto-workflow-use-staging
    (gptel-auto-workflow--staging-flow (gptel-auto-workflow--get-current-branch target))))
```

**Problem:**
- `magit-git-success` returns `nil` on failure but doesn't signal error
- Code continues to `staging-flow` even if push failed
- `staging-flow` tries to merge from `origin/optimize-branch` which doesn't exist
- Merge fails: "staging-merge-failed"

### Issue 2: Non-Fast-Forward Push Rejection

**Evidence:** Manual push test shows:
```
! [rejected] optimize/agent-imacpro.taila8bdd.ts.net-exp1 -> optimize/agent-imacpro.taila8bdd.ts.net-exp1 (non-fast-forward)
```

**Root cause:**
- Branch already exists on remote with different history
- Or local branch was rebased/modified
- Push rejected without `--force`

### Issue 3: Merge from Non-Existent Remote Branch

**Location:** `gptel-tools-agent.el:1713-1714`

```elisp
(optimize-ref (format "origin/%s" optimize-branch))
(optimize-q (shell-quote-argument optimize-ref))
```

**Problem:**
- Tries to merge from `origin/optimize-branch`
- If push failed, this branch doesn't exist on remote
- Merge fails silently

## Fix Plan

### Fix 1: Check Push Success Before Staging

**Change:** Add explicit check and retry logic

```elisp
(when gptel-auto-experiment-auto-push
  (let* ((branch (gptel-auto-workflow--get-current-branch target))
         (push-success (gptel-auto-workflow--push-with-retry branch)))
    (if push-success
        (when gptel-auto-workflow-use-staging
          (gptel-auto-workflow--staging-flow branch))
      (message "[auto-experiment] ✗ Push failed, skipping staging flow for %s" branch))))
```

### Fix 2: Add `--force-with-lease` for Optimize Branches

**Rationale:** Optimize branches are experimental, we want latest version

```elisp
(defun gptel-auto-workflow--push-with-retry (branch)
  "Push BRANCH to origin, retry with --force-with-lease if needed.
Returns t on success, nil on failure."
  (message "[auto-workflow] Pushing %s to origin" branch)
  (let ((push-result (magit-git-success "push" "origin" branch)))
    (if push-success
        t
      ;; Retry with force-with-lease for optimize branches
      (when (string-prefix-p "optimize/" branch)
        (message "[auto-workflow] Push rejected, retrying with --force-with-lease")
        (magit-git-success "push" "--force-with-lease" "origin" branch)))))
```

### Fix 3: Merge from Local Branch Instead of Remote

**Change:** Merge from local branch, not remote

```elisp
;; Current (broken):
(optimize-ref (format "origin/%s" optimize-branch))

;; Fixed:
(optimize-ref optimize-branch)
```

**Rationale:** The branch exists locally, we just committed to it. Merging from local is faster and doesn't require remote fetch.

### Fix 4: Add Pre-Merge Validation

**Add check before merge:**

```elisp
(defun gptel-auto-workflow--merge-to-staging (optimize-branch)
  "Merge OPTIMIZE-BRANCH to staging.
Requires branch to exist locally or on origin."
  (let ((local-exists (shell-command-to-string 
                        (format "git rev-parse --verify %s 2>/dev/null" 
                                (shell-quote-argument optimize-branch))))
        (remote-exists (shell-command-to-string
                        (format "git rev-parse --verify origin/%s 2>/dev/null"
                                (shell-quote-argument optimize-branch)))))
    (unless (or (not (string-empty-p local-exists))
                (not (string-empty-p remote-exists)))
      (message "[auto-workflow] ✗ Branch %s doesn't exist locally or on origin" optimize-branch)
      (cl-return-from gptel-auto-workflow--merge-to-staging nil))
    ;; ... rest of merge logic
    ))
```

## Testing Plan

### Test 1: Manual E2E Run

```bash
# Start clean
git checkout main
git branch -D optimize/test-manual 2>/dev/null || true

# Run auto-workflow manually
./scripts/run-auto-workflow-cron.sh auto-workflow

# Wait for completion, then check:
# 1. TSV results
cat var/tmp/experiments/$(date +%F)/results.tsv | grep "decision: kept"

# 2. Optimize branches on remote
git fetch origin
git branch -r | grep optimize

# 3. Staging branch
git log staging --oneline -10
```

### Test 2: Verify Push Success

```bash
# Check last experiment's branch
LAST_KEPT=$(tail -1 var/tmp/experiments/$(date +%F)/results.tsv | cut -f1)
BRANCH="optimize/${LAST_KEPT}-$(hostname)-exp1"

# Try to push manually
git push origin $BRANCH --force-with-lease

# Check if it's on remote now
git branch -r | grep $BRANCH
```

### Test 3: Staging Merge

```bash
# Manually test merge
git checkout staging
git merge -X theirs optimize/some-branch --no-ff

# Should succeed
echo $?  # 0 = success
```

## Expected Results After Fix

1. **Push succeeds** - All `decision: kept` experiments push to origin
2. **Remote has branches** - `git branch -r | grep optimize` shows many branches
3. **Staging merges succeed** - No more "staging-merge-failed"
4. **Staging has commits** - `git log staging` shows merge commits
5. **Human can review** - `git log staging..main` shows pending changes

## Implementation Priority

| Fix | Priority | Complexity | Impact |
|-----|----------|------------|--------|
| Check push success | HIGH | Low | Prevents wasted staging runs |
| Force-with-lease retry | HIGH | Low | Fixes push rejections |
| Merge from local | MEDIUM | Low | Faster, more reliable |
| Pre-merge validation | LOW | Medium | Better error messages |

## Next Steps

1. Implement Fix 1 (check push success)
2. Implement Fix 2 (force-with-lease retry)
3. Run manual E2E test
4. Monitor cron runs for 24 hours
5. Check staging branch for merged experiments

---

*Analysis by: opencode*
*Date: 2026-04-02*