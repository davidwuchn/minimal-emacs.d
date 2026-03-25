# Mementum State

> Last session: 2026-03-25 18:15

## Bug Fix: Executor Must Commit

**Root cause**: Eight Keys score_after was 0.00 because executor didn't commit changes.

Eight Keys scoring reads `git log -1` and `git diff HEAD~1` which fail without commits.

**Fix**: Added step 5 to experiment prompt:
```
5. COMMIT your changes: git add -A && git commit -m "message with signal phrases"
```

Also added signal phrase requirements to prompt.

---

## Staging Branch Protection Implemented

**Auto-workflow NEVER touches main.** All merges wait in staging for human review.

### Architecture

```
1. SYNC staging from main (start)
2. EXECUTOR creates optimize/*
3. MERGE optimize/* → staging
4. VERIFY staging (isolated worktree)
5. IF PASS: push staging (human reviews)
6. IF FAIL: log to TSV (human debugs)
```

### Safety Guarantees

| Guarantee | How |
|-----------|-----|
| Main never broken | Auto-workflow never touches main |
| Tests verified | Run on staging before push |
| Human in control | Must manually merge staging → main |

### Human Workflow

```bash
# Morning: check staging
git log staging..main

# If good: merge to main
git checkout main && git merge staging && git push

# If bad: reset staging
git checkout staging && git reset --hard main
```

### New Functions

- `gptel-auto-workflow--sync-staging-from-main`
- `gptel-auto-workflow--staging-flow`
- `gptel-auto-workflow--merge-to-staging`
- `gptel-auto-workflow--verify-staging`
- `gptel-auto-workflow--push-staging`

### Production Status

| Component | Status |
|-----------|--------|
| Staging protection | ✓ |
| Target selection | ✓ LLM |
| Executor | ✓ |
| Grader | ✓ 6/6 |
| Tests | ✓ 52/52 |
| Cron | ✓ 2 AM |

---

## λ Summary

```
λ safety. Main NEVER touched by auto-workflow
λ staging. All merges wait for human review
λ verify. Tests run on staging before push
λ control. Human merges staging to main
```