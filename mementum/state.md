# Mementum State

> Last session: 2026-03-25 22:00

## Real Code Fixes Merged ✓

**4 real bug fixes by auto-workflow:**

| Target | Fix | Type |
|--------|-----|------|
| gptel-auto-workflow-strategic.el | Added `(require 'json)` | Missing dependency |
| gptel-ext-fsm-utils.el | Fixed `%d` → `%s` for float-time | Type bug |
| gptel-ext-retry.el | Refactor trim-tool-results-for-retry | Code quality |
| gptel-tools-code.el | Fix resource leak in byte-compile | Resource leak |

---

## Async Pattern: No Blocking

**KEY INSIGHT**: With emacs daemon + emacsclient, we don't need blocking sync functions.

### Pattern

```bash
# Start workflow (returns immediately)
emacsclient -e '(gptel-auto-workflow-run-async)'

# Check status anytime (daemon always responds)
emacsclient -e '(gptel-auto-workflow-status)'
# => (:running t :phase "running" :kept 2 :total 3)

# Check Messages buffer for details
emacsclient -e '(with-current-buffer "*Messages*" ...)'
```

### Anti-Pattern Removed

```elisp
;; REMOVED: Blocks daemon, can't respond to emacsclient
(while running
  (accept-process-output nil 1.0))
```

---

## Key Learnings

### Async Pattern

**Never block the daemon.** Use async + status checking.

```bash
# Start
./scripts/run-auto-workflow.sh

# Check progress
./scripts/run-auto-workflow.sh status

# Debug via Messages
emacsclient -e '(with-current-buffer "*Messages*" ...)'
```

### Use Emacs Daemon + Emacsclient

**Do NOT use batch mode.** Batch mode lacks user config (API keys, gptel setup).

### Reuse Emacs Packages

**Do NOT reinvent wheel.** Use magit, gptel, etc. from user's config.

---

## Auto-Workflow Status

| Component | Status |
|-----------|--------|
| Staging protection | ✓ Never touches main |
| Daemon mode | ✓ Uses user config |
| Magit integration | ✓ Reuse packages |
| Worktree isolation | ✓ Fixed nested bug |
| Async pattern | ✓ No blocking, always responsive |
| Real code required | ✓ Documentation forbidden |
| Cron | ✓ 2 AM via emacsclient |

---

## λ Summary

```
λ async. Never block daemon - use async + status checking
λ daemon. Use emacs --daemon + emacsclient, NOT batch mode
λ status. Check progress with (gptel-auto-workflow-status)
λ debug. Check Messages buffer with emacsclient
λ code. Require real code changes, forbid documentation-only
λ safety. Main NEVER touched by auto-workflow
```