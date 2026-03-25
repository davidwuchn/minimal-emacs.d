# Mementum State

> Last session: 2026-03-25 21:30

## Real Code Fixes Generated ✓

**2 real bug fixes by auto-workflow:**

| Target | Fix | Type |
|--------|-----|------|
| gptel-auto-workflow-strategic.el | Added `(require 'json)` | Missing dependency |
| gptel-ext-fsm-utils.el | Fixed `%d` → `%s` for float-time | Type bug |

**3rd experiment**: Timed out (agent branch - no changes)

---

## Async Pattern: No Blocking

**KEY INSIGHT**: With emacs daemon + emacsclient, we don't need blocking sync functions.

### Pattern

```bash
# Start workflow (returns immediately)
emacsclient -e '(gptel-auto-workflow-run)'

# Check status anytime (daemon always responds)
emacsclient -e '(gptel-auto-workflow-status)'
# => (:running t :phase "running" :kept 2 :total 3)

# Check Messages buffer for details
emacsclient -e '(with-current-buffer "*Messages*" ...)'
```

### How It Works

1. `gptel-auto-workflow-run` starts async, returns immediately
2. Workflow runs in background via timers/processes
3. Daemon event loop stays responsive
4. `gptel-auto-workflow-status` checks state anytime

### Anti-Pattern: Blocking Sync

```elisp
;; BAD: Blocks daemon, can't respond to emacsclient
(while running
  (accept-process-output nil 1.0))

;; GOOD: Async with status checking
(defun run-workflow ()
  (setq running t)
  (run-async ...))

(defun status ()
  (list :running running ...))
```

---

## Real Code Changes Required

**PROBLEM**: Executor generated only documentation because prompt focused on Eight Keys score.

**FIX**: Updated prompt to:
- FORBID: comments, docstrings, documentation-only
- REQUIRE: actual code changes
- LIST: 5 improvement types (bug fix, performance, refactoring, safety, tests)

---

## Key Learnings

### Async Pattern

**Never block the daemon.** Use async + status checking.

```bash
# Start
emacsclient -e '(gptel-auto-workflow-run)'

# Check progress
emacsclient -e '(gptel-auto-workflow-status)'

# Debug via Messages
emacsclient -e '(with-current-buffer "*Messages*" ...)'
```

### Use Emacs Daemon + Emacsclient

**Do NOT use batch mode.** Batch mode lacks user config (API keys, gptel setup).

```bash
# Correct: daemon + emacsclient
emacs --daemon
emacsclient -e '(gptel-auto-workflow-run)'

# Wrong: batch mode
emacs --batch -Q --eval "..."  # No API keys!
```

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