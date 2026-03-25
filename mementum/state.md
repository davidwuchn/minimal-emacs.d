# Mementum State

> Last session: 2026-03-25 20:30

## Auto-Workflow Success ✓

**3 real improvements generated and merged:**

| Target | Lines | Type |
|--------|-------|------|
| gptel-ext-context.el | +42 | Module documentation |
| gptel-ext-retry.el | +108 | Function documentation |
| gptel-auto-workflow-strategic.el | +31 | Function documentation |

**Flow:**
```
main → worktrees → optimize/* → staging → main
```

---

## Bug Fix: Nested Worktrees

**BUG**: Worktrees were created inside other worktrees (nested), because
`gptel-auto-workflow--project-root` returned worktree path instead of main repo.

**FIX**: Use `git rev-parse --git-common-dir` to always find main repo root.

```
Before: /proj/var/tmp/exp/opt-1/var/tmp/exp/opt-2/... (nested)
After:  /proj/var/tmp/exp/opt-1, /proj/var/tmp/exp/opt-2 (siblings)
```

---

## Key Learnings

### Use Emacs Daemon + Emacsclient

**Do NOT use batch mode.** Batch mode lacks user config (API keys, gptel setup).

```bash
# Correct: daemon + emacsclient
emacs --daemon
emacsclient -e '(gptel-auto-workflow-run-sync)'

# Wrong: batch mode
emacs --batch -Q --eval "..."  # No API keys!
```

### Reuse Emacs Packages

**Do NOT reinvent wheel.** Use magit, gptel, etc. from user's config.

- Use `magit-git-success` instead of shell commands
- Use `gptel-agent--task` for LLM calls
- Let packages handle complexity

### Prefer Elisp Over Shell Scripts

Shell scripts should only:
1. Check daemon running
2. Call elisp function

All logic in elisp.

---

## Auto-Workflow Status

| Component | Status |
|-----------|--------|
| Staging protection | ✓ Never touches main |
| Daemon mode | ✓ Uses user config |
| Magit integration | ✓ Reuse packages |
| Worktree isolation | ✓ Fixed nested bug |
| Cron | ✓ 2 AM via emacsclient |

---

## λ Summary

```
λ daemon. Use emacs --daemon + emacsclient, NOT batch mode
λ reuse. Use magit, gptel - don't reinvent wheel
λ elisp. Logic in elisp, shell only for daemon check
λ safety. Main NEVER touched by auto-workflow
λ worktree. Always use main repo root, not worktree path
```