# gptel-auto-workflow-production

## Purpose

Production integration layer that ties all self-evolution components together for continuous operation. Manages the evolution timer (periodic cycles), garbage collection timer, experiment completion hooks, and the innovation queue. Also provides GTM (Go-To-Market) strategy management, PMF (Product-Market Fit) dashboards, and a human decision pipeline for pending changes.

## File Stats

- **Lines**: 973
- **Path**: `lisp/modules/gptel-auto-workflow-production.el`

## Key Functions

- `gptel-auto-workflow--gc-trigger` (L39) — Forces garbage collection to prevent memory growth in long-running daemons.
- `gptel-auto-workflow-start-gc-timer` (L50) — Starts periodic GC timer (300s intervals).
- `gptel-auto-workflow-stop-gc-timer` (L57) — Stops GC timer.
- `gptel-auto-workflow--maybe-run-evolution` (L65) — Runs evolution cycle if enabled, with pre-cycle context DB load, token budget optimization, and monitoring agent analysis.
- `gptel-auto-workflow-start-evolution-timer` (L133) — Starts periodic evolution timer (default 1 hour).
- `gptel-auto-workflow-stop-evolution-timer` (L144) — Stops evolution timer.
- `gptel-auto-workflow--experiment-complete-hook` (L162) — Hook called on experiment completion; triggers evolution cycle, innovation queue, and dashboard updates.
- `gptel-auto-workflow-evolution-status` (L279) — Returns current evolution status including timer state, cycle count, and champion data.
- `gptel-auto-workflow-evolution-auto-start` (L408) — Enables automatic evolution with configurable interval.
- `gptel-auto-workflow--verify-pipeline-integration` (L438) — Verifies the full pipeline is wired correctly.
- `gptel-auto-workflow--decision-create` (L509) — Creates a human decision entry with GTM and PMF recommendations.
- `gptel-auto-workflow--update-pmf-dashboard` (L569) — Updates the PMF dashboard with current metrics.
- `gptel-auto-workflow--innovation-queue-add` (L661) — Adds an innovation to the queue with source, technique, and expected impact.
- `gptel-auto-workflow--read-gtm-strategy` (L799) — Reads GTM strategy from mementum/gtm/strategy-roadmap.md.
- `gptel-auto-workflow--maybe-run-gtm-strategy-evolution` (L877) — Periodically evolves the GTM strategy based on experiment results.

## Dependencies

- `cl-lib`
- `gptel-auto-workflow-external-sensors` (soft)
- `gptel-auto-workflow-production-metrics` (soft)
- `gptel-monitoring-agent` (soft)
- `gptel-auto-workflow-human-interface` (soft)
- `gptel-token-economics` (soft)
- `gptel-auto-workflow-context-database` (soft)
- `gptel-auto-workflow-decision-classification` (soft)

## Integration Points

- **gptel-auto-workflow-evolution** — `evolution-run-cycle` is the core evolution entry point
- **gptel-tools-agent-base** — `worktree-base-root` for file path resolution
- **gptel-auto-workflow-beads** — experiment-to-bead updates for mementum
- **gptel-auto-workflow-mementum** — memory status for GC logging
- **gptel-token-economics** — token budget optimization before evolution
- **gptel-monitoring-agent** — failure pattern analysis before evolution
- **gptel-auto-workflow-context-database** — context loading and persistence

## See Also

- [gptel-auto-workflow-evolution](gptel-auto-workflow-evolution.md) — Core evolution engine
- [gptel-tools-agent-main](gptel-tools-agent-main.md) — Main workflow entry point
- [gptel-auto-workflow-bootstrap](gptel-auto-workflow-bootstrap.md) — Headless daemon bootstrap

---
*Auto-generated from code header. Manually refined 2026-06-06.*