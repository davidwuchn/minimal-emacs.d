# Mementum State

> Last session: 2026-03-25

## Session Summary: Auto-Workflow Ready for Production

**52/52 tests pass.** Component tests verified. Ready for cron installation.

### Latest Commits

| Hash | Description |
|------|-------------|
| `dcf23aa` | ◈ Update state.md: 52/52 tests pass |
| `70d4e37` | ✓ gptel-tools-agent: add local fallback for comparator |

### Component Tests (Verified)

| Test | Result |
|------|--------|
| Local comparator | ✓ KEEP when quality improves |
| Hypothesis extraction | ✓ Multiple patterns work |
| Branch format | ✓ `optimize/{hostname}-{date}` |
| Push logic | ✓ Only pushes to `optimize/*` branches |

### Production Status

| Component | Status |
|-----------|--------|
| Sync wrapper | ✓ `gptel-auto-workflow-run-sync` |
| Executor | ✓ Finds files, makes changes |
| Grader | ✓ 6/6 pass rate |
| Comparator | ✓ LLM decides with proper prompt |
| Eight Keys scoring | ✓ Fixed plist-get + code diff input |
| Hypothesis extraction | ✓ Multiple patterns |
| Branching | ✓ optimize/* only |
| All tests | ✓ 52/52 pass |

### Auto-Workflow Branching Rule (CRITICAL)

```
λ auto-workflow-branching(x).
    change(x) → branch(optimize/{target}-{hostname}-exp{N})
    | push(optimize/...) → origin/optimize/...
    | ¬push(main)
    | human_review → merge(main)
```

**Branch Format**: `optimize/{target-name}-{hostname}-exp{N}`

**Flow**:
1. Auto-workflow creates worktree with optimize branch
2. Executor makes changes in worktree (isolated from main)
3. If improvement → commit to optimize branch
4. Push to `origin optimize/...` (NOT main!)
5. Human reviews and merges to main via PR

### Install Cron

```bash
crontab cron.d/auto-workflow
```

Schedule:
- 2 AM daily - auto-workflow
- 4 AM Sunday - mementum synthesis
- 5 AM Sunday - instincts evolution

### View Results

```bash
cat var/tmp/experiments/$(date +%Y-%m-%d)/results.tsv
tail -f var/tmp/cron/auto-workflow.log
```

### Merge Successful Experiments

```bash
git fetch origin
git branch -r 'origin/optimize/*'
git merge --squash origin/optimize/<branch>
```

---

## Previous Sessions

### Eight Keys Scoring (FIXED 2026-03-25)

**Problem**: Eight Keys score rarely improved even when code quality improved.

**Root Causes**:
1. `plist-get` called on wrong structure (key-def instead of cdr key-def)
2. Inner quotes in signals/anti-patterns lists broke plist structure
3. Git diff --stat doesn't contain signal patterns

**Fixes**:
1. Fixed `plist-get` to use `(cdr key-def)` for proper plist access
2. Removed inner quotes from signal/anti-pattern definitions
3. Changed scoring input from `git diff --stat` to commit message + code diff

### Executor Model Issue (RESOLVED)

**Problem**: `qwen3.5-plus` didn't always output "HYPOTHESIS:" prefix.

**Solutions Applied**:
1. Enhanced hypothesis extraction with multiple patterns
2. Relaxed grader criteria: 'change clearly described'

### Async/Sync Incompatibility (FIXED)

**Problem**: `gptel-auto-workflow-run` returns immediately when called via cron

**Solution**: Added `gptel-auto-workflow-run-sync` using `accept-process-output`

### Comparator Prompt Fix (FINAL)

**Problem**: Comparator subagent returned `nil` because prompt expected directories but we sent plists.

**Solution**: Rewrote prompt to match actual data (scores as text).

---

## λ Summary

```
λ complete. 52/52 tests pass
λ verify. component tests: comparator, hypothesis, branching
λ ready. cron installation pending
```