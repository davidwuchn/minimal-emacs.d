# gptel-tools-agent-main

## Purpose

The main entry point and workflow control module for the gptel auto-workflow system. Orchestrates the complete experiment lifecycle: target discovery, experiment execution, status monitoring, self-healing, cleanup, and cron-based scheduling. Provides the `gptel-auto-workflow-cron-safe` entry point used by the pipeline daemon, the `gptel-auto-workflow-run-async` async execution engine, and the self-healing system that validates critical functions before each run and can auto-rollback broken changes.

## File Stats

- **Lines**: 1686
- **Path**: `lisp/modules/gptel-tools-agent-main.el`

## Key Functions

- `gptel-auto-workflow--call-process-with-watchdog` (L129) — Runs a blocking subprocess with timeout while pausing the workflow watchdog.
- `gptel-auto-workflow--stop-status-refresh-timer` (L159) — Cancels the active status refresh timer.
- `gptel-auto-workflow--refresh-status-if-running` (L165) — Refreshes workflow status display if a workflow is active.
- `gptel-auto-workflow--maybe-start-status-refresh-timer` (L185) — Starts the status refresh timer if a workflow is running.
- `gptel-auto-workflow-force-stop` (L203) — Force-stops the active workflow, terminating all processes and timers.
- `gptel-auto-workflow--headless-p` (L231) — Returns t when running in headless (daemon) mode.
- `gptel-auto-workflow--active-use-p` (L275) — Returns t when the user is actively using the workflow UI.
- `gptel-auto-workflow-status` (L302) — Returns a plist with current workflow status (running, targets, progress, stats).
- `gptel-auto-workflow-log` (L349) — Returns the workflow log buffer contents.
- `gptel-auto-workflow-run-async` (L386) — Main async execution engine: discovers targets, runs experiments, handles completion.
- `gptel-auto-workflow-run-async--guarded` (L641) — Guarded wrapper that validates critical functions before running.
- `gptel-auto-workflow-cron-safe` (L744) — Cron-safe entry point: self-heal check, cleanup, target selection, experiment execution.
- `gptel-auto-workflow--self-heal-check` (L873) — Validates all critical functions are fboundp; returns list of broken functions.
- `gptel-auto-workflow--self-heal-rollback` (L922) — Auto-rolls back the most recent change if critical functions are broken.
- `gptel-auto-workflow--cleanup-integrated-remote-optimize-branches` (L957) — Cleans up remote optimize branches that have been integrated.
- `gptel-auto-workflow--cleanup-old-worktrees` (L1024) — Removes stale worktrees from previous runs.
- `gptel-auto-workflow--cleanup-stale-state` (L1089) — Cleans up stale experiment state, tracking files, and orphaned commits.
- `gptel-auto-workflow-run` (L1407) — Synchronous wrapper: runs the workflow and blocks until complete.
- `gptel-auto-workflow-skill-load` (L1491) — Loads a skill file for prompt injection.
- `gptel-auto-workflow-recall-skills` (L1508) — Recalls skills relevant to a target for hypothesis generation.
- `gptel-auto-workflow-orient` (L1568) — Orient function: reads mementum/state.md and sets up session context.

## Dependencies

- `cl-lib`
- `gptel-tools-agent-base` — core utilities, boundary validation, run-id management
- `gptel-auto-workflow-knowledge-reasoning` — frontier target selection, dialectic check
- `gptel-auto-workflow-evolution` — gap-based target prioritization
- `gptel-tools-agent-experiment-loop` — experiment execution and status tracking
- `gptel-tools-agent-prompt-build` — rate limit clearing, prompt compilation
- `gptel-tools-agent-worktree` — worktree and remote branch management
- `gptel-auto-workflow-strategic` — research findings loading

## Integration Points

- **gptel-auto-workflow-cron-safe** is the primary entry point called by the pipeline daemon via `emacsclient --eval`.
- **gptel-auto-workflow-run-async** is called by the evolution engine to queue experiments.
- **gptel-auto-workflow-force-stop** is called by the user or watchdog timer to abort runs.
- Self-healing checks run before every experiment batch to prevent broken code from executing.
- The orient function is the session bootstrap, called first when starting work.

## See Also

- [gptel-tools-agent-base](gptel-tools-agent-base.md) — Base utilities and boundary validation
- [gptel-auto-workflow-evolution](gptel-auto-workflow-evolution.md) — Evolution engine called by cron
- [gptel-auto-workflow-strategic](gptel-auto-workflow-strategic.md) — Target selection
- [gptel-auto-workflow-bootstrap](gptel-auto-workflow-bootstrap.md) — Headless daemon bootstrap

---
*Auto-generated from code header. Manually refined 2026-06-06.*