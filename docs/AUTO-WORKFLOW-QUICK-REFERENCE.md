# Auto-Workflow Quick Reference

## Status: ✅ FIXED (2026-04-02)

All 4 critical bugs fixed. Auto-workflow now successfully:
1. Runs experiments ✓
2. Pushes branches to origin ✓
3. Merges to staging ✓
4. Pushes staging for review ✓

## What Was Fixed

| Bug | Impact | Fix |
|-----|--------|-----|
| Silent push failures | Branches not on remote | Check push result, retry with --force-with-lease |
| Staging merges failed | No integration testing | Merge from local OR remote, validate branch exists |
| Fetch only got main | Remote branches invisible | Fetch all branches: `refs/heads/*` |
| No error handling | Silent failures | Add logging and validation |

## Verification Commands

```bash
# Check remote branches exist
git branch -r | grep optimize | wc -l  # Should show 40+

# Check staging has merges
git log origin/staging --oneline -10 | grep "optimize/"

# Run manual workflow
./scripts/run-auto-workflow-cron.sh auto-workflow

# Check logs
tail -f var/tmp/cron/auto-workflow.log
```

## Expected Results

### After Auto-Workflow Run

1. **TSV results** - `var/tmp/experiments/YYYY-MM-DD/results.tsv`
   - Look for `decision: kept` (improvements)

2. **Remote branches** - `git branch -r | grep optimize`
   - Should show new branches like `optimize/target-hostname-expN`

3. **Staging merges** - `git log staging`
   - Should show merge commits from optimize branches

4. **Human review** - Check `origin/staging` and merge to main

## Cron Schedule

| Machine | Schedule | Runs/Day |
|---------|----------|----------|
| macOS | 10AM, 2PM, 6PM | 3 |
| Pi5/Linux | 11PM, 3AM, 7AM, 11AM, 3PM, 7PM | 6 |

## Key Files

| File | Purpose |
|------|---------|
| `lisp/modules/gptel-tools-agent.el` | Main workflow + fixes |
| `docs/auto-workflow-e2e-fixed.md` | Complete fix documentation |
| `scripts/fix-optimize-branches.sh` | Batch push local branches |
| `var/tmp/experiments/YYYY-MM-DD/results.tsv` | Experiment results |

## New Functions

### `gptel-auto-workflow--push-with-retry`

Pushes branch with automatic retry:
- Try normal push
- If rejected (non-fast-forward), retry with `--force-with-lease`
- Returns `t` on success, `nil` on failure

### `gptel-auto-workflow--branch-exists-p`

Validates branch before merge:
- Returns `'local` if branch exists locally
- Returns `'remote` if branch exists on origin
- Returns `nil` if branch doesn't exist

### `gptel-auto-workflow--merge-to-staging`

Merges optimize branch to staging:
- Validates branch exists (local or remote)
- Merges with `--theirs` conflict resolution
- Runs in isolated worktree (never touches project root)

## Monitoring

### Check Workflow Status

```bash
./scripts/run-auto-workflow-cron.sh status
```

Returns:
```elisp
(:running nil :kept N :total M :phase "idle" :results "var/tmp/experiments/...")
```

### Check for Failures

```bash
# Recent failures
grep -E "staging-merge-failed|push.*failed" var/tmp/experiments/*/results.tsv

# Should return nothing after fix
```

## Human Workflow

### Morning Review

```bash
# 1. Fetch latest
git fetch origin

# 2. Check what's in staging
git log main..origin/staging --oneline

# 3. Review changes
git diff main..origin/staging

# 4. If good, merge to main
git checkout main
git merge origin/staging
git push origin main

# 5. If bad, reset staging
git checkout staging
git reset --hard origin/main
git push --force origin staging
```

## Troubleshooting

### Branch not on remote

```bash
# Push manually
git push origin optimize/branch-name --force-with-lease
```

### Staging merge failed

```bash
# Check if branch exists
git branch -r | grep optimize/branch-name

# If not, push it first
git push origin optimize/branch-name --force-with-lease

# Retry merge
git checkout staging
git merge -X theirs origin/optimize/branch-name --no-ff
```

### Verify fixes work

```bash
# Run workflow
./scripts/run-auto-workflow-cron.sh auto-workflow

# Wait 10 minutes, then check
git branch -r | grep optimize  # Should show new branches
git log staging --oneline -5   # Should show recent merges
```

---

**Status:** Production-ready
**Last Updated:** 2026-04-02