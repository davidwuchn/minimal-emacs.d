# Auto-Workflow E2E Fix Summary

**Date:** 2026-04-02
**Fixes Applied:** 3 critical bugs fixed

## Bugs Fixed

### Bug 1: Silent Push Failures (CRITICAL)

**Location:** `gptel-tools-agent.el:2904-2908` (old)

**Problem:**
- `magit-git-success` returns `nil` on failure but doesn't signal error
- Code continues to staging flow even if push failed
- Staging tries to merge from `origin/optimize-branch` which doesn't exist
- Result: "staging-merge-failed"

**Fix:**
```elisp
;; Old (broken):
(magit-git-success "push" "origin" branch)
(when gptel-auto-workflow-use-staging
  (gptel-auto-workflow--staging-flow branch))

;; New (fixed):
(let ((push-success (gptel-auto-workflow--push-with-retry branch)))
  (if (and push-success gptel-auto-workflow-use-staging)
      (gptel-auto-workflow--staging-flow branch)
    (message "[auto-experiment] ✗ Push failed, skipping staging flow")))
```

### Bug 2: Non-Fast-Forward Push Rejection

**Problem:**
- Optimize branches may exist on remote with different history
- Push rejected: `! [rejected] optimize/xxx -> optimize/xxx (non-fast-forward)`
- No retry with `--force`

**Fix:** Added `gptel-auto-workflow--push-with-retry`:
1. Try normal push
2. If rejected as non-fast-forward, retry with `--force-with-lease`
3. Return success/failure status

**Rationale:** Optimize branches are experimental, force-with-lease is safe.

### Bug 3: Merge from Non-Existent Remote Branch

**Location:** `gptel-tools-agent.el:1713` (old)

**Problem:**
- Merge tried to use `origin/optimize-branch` even if branch only exists locally
- If push failed, remote branch doesn't exist
- Merge fails

**Fix:** Added `gptel-auto-workflow--branch-exists-p`:
```elisp
;; Check where branch exists:
;; - 'local: merge from optimize-branch
;; - 'remote: merge from origin/optimize-branch
;; - nil: error, don't attempt merge
```

## New Functions Added

### `gptel-auto-workflow--push-with-retry`

Pushes branch to origin with automatic retry on rejection.

**Features:**
- Returns `t` on success, `nil` on failure
- Retries with `--force-with-lease` if push rejected
- Logs all attempts and results

### `gptel-auto-workflow--branch-exists-p`

Checks if branch exists locally or on remote.

**Returns:**
- `'local` - branch exists in local repo
- `'remote` - branch exists on origin
- `nil` - branch doesn't exist

## Testing

### Quick Manual Test

```bash
# 1. Run workflow
./scripts/run-auto-workflow-cron.sh auto-workflow

# 2. Wait 5-10 minutes, then check results
cat var/tmp/experiments/$(date +%F)/results.tsv | grep "decision: kept"

# 3. Check remote branches (should show optimize/*)
git fetch origin
git branch -r | grep optimize | head -10

# 4. Check staging branch
git log staging --oneline -10
```

### Expected Results

1. **TSV shows "kept" decisions** - experiments improved combined score
2. **Remote has optimize branches** - `git branch -r | grep optimize` shows branches
3. **Staging has merge commits** - `git log staging` shows recent merges
4. **No "staging-merge-failed" errors** - merges succeed

### Verify Fix

```bash
# Check a specific optimize branch exists on remote
git branch -r | grep optimize/core-imacpro.taila8bdd.ts.net-exp3

# Should show:
# origin/optimize/core-imacpro.taila8bdd.ts.net-exp3

# Check staging has merge
git log staging --oneline | grep "optimize/core-imacpro"

# Should show merge commit
```

## Status

✅ **Code fixed** - 3 bugs resolved
🟡 **Testing needed** - Run manual E2E test
🟡 **Monitoring needed** - Check next cron run

## Files Changed

- `lisp/modules/gptel-tools-agent.el` - Fixed push/staging flow

## Next Steps

1. **Test manually** - Run workflow and verify branches push
2. **Monitor cron** - Check next scheduled run
3. **Review staging** - Human reviews and merges to main
4. **Update docs** - Document new workflow behavior

---

*Fix by: opencode*
*Date: 2026-04-02*