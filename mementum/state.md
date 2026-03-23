# Mementum State

> Last session: 2026-03-24

## Active

- **Autonomous Research Agent** — Fixed! Subagent now works with DashScope

## Fixed

| Issue | Cause | Solution |
|-------|-------|----------|
| Subagent stuck | `gptel-agent--task` requires `gptel--fsm-last` | Use `gptel-with-preset` + `gptel-request` |
| No callback | FSM state nil in server buffer | Direct preset application |
| Slow API | Not API, was callback not firing | Fixed by above |

## Test Results

| Test | Time | Result |
|------|------|--------|
| Simple query "2+2" | 2.9s | "4" ✓ |
| Optimization task | 64.4s | 1247 chars ✓ |

## Recommended Settings

```elisp
;; For auto-workflow: set timeout longer than expected subagent time
(setq gptel-auto-experiment-time-budget 300)  ; 5 min
```

## Commits

- f2b0614: ⚒ fix auto-experiment: mock mode callback chain, worktree directory handling
- 81e722d: ⚒ fix subagent: use gptel-with-preset + gptel-request instead of gptel-agent--task

## Entry Points

```elisp
M-x gptel-auto-workflow-run-autonomous
```

## Cron

```bash
0 2 * * * emacsclient -e '(gptel-auto-workflow-run-autonomous)'   # Daily 2 AM
0 3 * * 0 emacsclient -e '(gptel-benchmark-instincts-weekly-job)' # Sunday 3 AM
```