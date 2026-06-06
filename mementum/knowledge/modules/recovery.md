# Recovery Module

## Purpose

Daemon restart recovery and circuit-breaker integration. Coordinates checkpoint loading, worktree cleanup, circuit-breaker health, and experiment recovery into a unified startup sequence.

## Recovery Sequence

1. Load circuit-breaker state (survives daemon restart)
2. Clean stale recovery locks and old checkpoints
3. Check for recoverable workflow checkpoint
4. If found and not manual stop:
   - Acquire recovery lock
   - Load recovery context (targets, progress, results)
   - Validate worktree state
   - Resume workflow from last position
5. If no checkpoint or not recoverable: start fresh

## Circuit-Breaker Integration

- Each component (researcher, analyzer, executor, grader) has independent circuit
- Circuit state persists across daemon restart
- Open circuits prevent requests to degraded components
- Automatic recovery via half-open probe

## Edge Cases

| Case | Behavior |
|---|---|
| Manual stop | state=aborted → start fresh |
| Complete | state=completed → archive, start fresh |
| Failed | state=failed → start fresh |
| No checkpoint | start fresh |
