---
title: Staging Branch Cleanup - Incomplete Refactoring
category: git
status: active
tags: [refactoring, breaking-changes, staging, auto-workflow]
date: 2026-03-31
related: [staging-workflow, git-worktrees, auto-workflow]
---

## Problem

Staging branch contained 20+ optimization commits with **breaking changes**:

1. **Function reference errors** - Functions removed but callers not updated
2. **Signature mismatches** - Function signatures changed but not all callers updated
3. **Inlined abstractions** - Helper functions removed, logic inlined back

## Specific Issues Found

### gptel-benchmark-core.el
- Function `gptel-benchmark--calculate-average` renamed to `gptel-benchmark--safe-average`
- BUT callers still referenced old name
- Signature changed from `(score-totals score-type total)` to `(total sum)`

### gptel-agent-loop.el
Functions removed but still called:
- `gptel-agent-loop--transient-error-p` (error retry broken)
- `gptel-agent-loop--build-final-result` (result building fails)
- `gptel-agent-loop--maybe-cache-get/put` (caching disabled)

### gptel-tools-agent.el
- Removed `--no-pager` from git commands (risk of blocking)
- Inlined helper functions causing code duplication

## Solution

**Reset staging to main** - discard all problematic commits:

```bash
git checkout staging
git reset --hard main
git push --force origin staging
```

## Lessons Learned

1. **Incomplete refactoring is worse than no refactoring** - Partial changes break runtime
2. **Always check callers when renaming/removing functions** - Static analysis helps
3. **Review staging before merge** - Use `git diff main..staging` to catch issues
4. **Abstractions should stay** - Inlining helpers reduces clarity and increases duplication
5. **Test in worktree before committing** - Verify experiments actually work

## Prevention

- Run byte-compile on all changed files
- Test function calls exist: `grep -r "removed-function-name" lisp/`
- Review diff stats before merge
- Keep helper functions unless truly unnecessary

## When to Reset vs Fix

**Reset when:**
- Multiple breaking changes across files
- Incomplete refactoring (functions removed, callers not updated)
- Runtime errors detected in review
- More work to fix than re-do

**Fix when:**
- Single isolated issue
- Clear path to resolution
- Most changes are valid
