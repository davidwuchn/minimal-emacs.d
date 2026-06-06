# Production Module

## Purpose

Ties all self-evolution components together for production use. Runs automatically when the auto-workflow daemon is active.

## Key Functions

| Function | Purpose |
|---|---|
| `gptel-auto-workflow-run-async` | Start async workflow run |
| `gptel-auto-workflow-cron-safe` | Cron-safe wrapper |
| `gptel-auto-workflow--gc-trigger` | Force GC every 5 minutes to prevent memory growth |

## Configuration

```elisp
(defvar gptel-auto-workflow-evolution-interval 3600) ; Evolution cycle interval
(defvar gptel-auto-workflow--running nil)             ; Workflow active flag
(defvar gptel-auto-workflow--cron-job-running nil)    ; Cron job flag
```

## Integration Points

- **Cron**: Called by cron daemon
- **Evolution**: Triggers evolution cycles
- **Recovery**: Handles checkpointing and restart
