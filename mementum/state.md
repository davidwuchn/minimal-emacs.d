# Mementum State

> Last session: 2026-03-24

## Fully Tested ✓

**Autonomous Research Agent** — End-to-end working

### Test Results

| Test | Experiments | Time | Status |
|------|-------------|------|--------|
| Mock mode (3 exp) | 3 | ~15s | ✓ |
| Real API (1 exp) | 1 | 73s | ✓ |
| Real API (2 exp) | 2 | ~3min | ✓ |

### Fixes Applied

| Issue | Fix |
|-------|-----|
| HTTP parsing errors | Disable streaming on DashScope |
| Agent runs too long | Limit to 10 steps |
| Stale magit buffers | Kill on start/delete |
| Subagent FSM error | Use gptel-with-preset |

### Configuration

```elisp
;; Recommended settings
(setq gptel-auto-experiment-lite-mode t)  ; 4 tools
(setq gptel-auto-experiment-time-budget 180)  ; 3 min
(setq gptel-auto-experiment-max-per-target 3)
```

### Commits

| Commit | Description |
|--------|-------------|
| 12eea4e | ⚡ limit lite-executor to 10 steps |
| 5f5b90d | ⚡ fix lite-executor: disable streaming |
| 630fbd4 | ⚡ fix DashScope: disable streaming |
| a7b0931 | ⚡ add lite-executor: 4 tools |

### How It Works

1. Create git worktree
2. Run lite-executor (max 10 API calls)
3. Grade output
4. Run benchmark
5. Decide keep/discard
6. Log to TSV
7. Cleanup worktree

### Entry Points

```elisp
M-x gptel-auto-workflow-run
(gptel-auto-workflow-run '("lisp/modules/file.el"))
```

### Cron

```bash
0 2 * * * emacsclient -e '(gptel-auto-workflow-run-autonomous)'
```