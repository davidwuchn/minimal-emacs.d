# Mementum State

> Last session: 2026-03-24

## Complete ✓

**Autonomous Research Agent** — Fully functional with DashScope

### Key Fixes

| Issue | Root Cause | Solution |
|-------|------------|----------|
| HTTP parsing errors | DashScope SSE differs from OpenAI | Disable streaming |
| Slow API (100-200s) | 27 tools in payload | lite-executor (4 tools) |
| Callback chain failure | gptel-agent--task needs FSM | Use gptel-with-preset |
| Stale magit buffers | Worktree paths cached | Kill buffers on start/delete |

### Configuration

```elisp
;; DashScope: non-streaming for reliability
(setq gptel-auto-experiment-lite-mode t)  ; 4 tools vs 27
(setq gptel-auto-experiment-time-budget 120)  ; 2 min per experiment
```

### Test Results

| Test | Time | Status |
|------|------|--------|
| Simple query | 2.5s | ✓ |
| Auto-workflow (1 exp) | 73s | ✓ |
| Subagent completion | ✓ | No HTTP errors |

### Commits

| Commit | Description |
|--------|-------------|
| 630fbd4 | ⚡ fix DashScope: disable streaming |
| a7b0931 | ⚡ add lite-executor: 4 tools instead of 27 |
| 3073567 | ⚡ improve auto-experiment: better scoring |

### Entry Points

```elisp
M-x gptel-auto-workflow-run
(gptel-auto-workflow-run '("lisp/modules/gptel-ext-retry.el"))
```

### Cron

```bash
0 2 * * * emacsclient -e '(gptel-auto-workflow-run-autonomous)'
```