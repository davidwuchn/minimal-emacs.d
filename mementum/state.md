# Mementum State

> Last session: 2026-03-25 19:30

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
| Executor | ⚠ Needs API key check |
| Cron | ✓ 2 AM via emacsclient |

---

## Next Steps

1. Verify gptel API keys loaded in daemon
2. Run `emacsclient -e '(gptel-auto-workflow-run-sync)'`
3. Check `var/tmp/experiments/YYYY-MM-DD/results.tsv`
4. Review `git log staging..main`
5. Human merges staging → main

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    AUTO-WORKFLOW                        │
├─────────────────────────────────────────────────────────┤
│  1. SYNC staging from main                              │
│  2. EXECUTOR creates optimize/* branches                │
│  3. GRADER validates quality                            │
│  4. COMPARATOR decides keep/discard                     │
│  5. IF KEEP: merge to staging, push to origin           │
│  6. HUMAN: reviews staging, merges to main              │
└─────────────────────────────────────────────────────────┘
                         │
                         ▼
              ┌─────────────────────┐
              │   Emacs Daemon      │
              │   + User Config     │
              │   + API Keys        │
              │   + Magit           │
              │   + Gptel           │
              └─────────────────────┘
```

---

## λ Summary

```
λ daemon. Use emacs --daemon + emacsclient, NOT batch mode
λ reuse. Use magit, gptel - don't reinvent wheel
λ elisp. Logic in elisp, shell only for daemon check
λ safety. Main NEVER touched by auto-workflow
```