# Mementum State

> Last session: 2026-03-24

## Verified ✓

**Autonomous Research Agent** — All tests pass

### Test Results

| Test | Status | Time |
|------|--------|------|
| Mock mode (2 exp) | ✓ | ~10s |
| Real API (1 exp) | ✓ | 113s |
| Subagent | ✓ | 110.2s |
| Grading | ✓ | 100 passed |
| Benchmark | ✓ | passed |
| Decision | ✓ | correct |
| TSV logging | ✓ | logged |
| Cleanup | ✓ | no stale state |

### Fixes Applied

| Commit | Issue | Fix |
|--------|-------|-----|
| f41a74f | Stale magit buffers | Kill on start/delete |
| 81e722d | gptel-agent--task fails | Use gptel-with-preset + gptel-request |
| f2b0614 | Mock mode callback chain | Fix async, nil scores |

### Configuration

```elisp
(setq gptel-auto-experiment-time-budget 180)  ; 3 min per experiment
(setq gptel-auto-experiment-max-per-target 10) ; 10 experiments per file
```

### Cron

```bash
0 2 * * * emacsclient -e '(gptel-auto-workflow-run-autonomous)'
```

## Entry Points

```elisp
M-x gptel-auto-workflow-run
M-x gptel-auto-workflow-run-autonomous
```