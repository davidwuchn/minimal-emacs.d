# gptel-auto-workflow-strategic

## Purpose

LLM-first strategic target selection for the auto-workflow system. Instead of using static target lists, this module lets an AI analyzer decide which files to optimize each run. It gathers git history, file sizes, and known issues, runs optional research to discover patterns, then asks the analyzer to select the highest-impact targets. Includes fallback to static targets when the LLM is unavailable, a headless target denylist for critical files, and research trace persistence for mementum tracking.

## File Stats

- **Lines**: 2889
- **Path**: `lisp/modules/gptel-auto-workflow-strategic.el`

## Key Functions

- `gptel-auto-workflow--research-trace-for-hash` (L114) — Retrieves a persisted research trace by its SHA1 hash.
- `gptel-auto-workflow--research-context-from-findings` (L136) — Builds a research context plist from findings, including strategy, hash, source, and timestamp.
- `gptel-auto-workflow--ensure-research-context` (L158) — Ensures research context exists for findings, creating it if needed.
- `gptel-auto-workflow--clear-analyzer-error-state` (L217) — Clears cached analyzer error state for retry.
- `gptel-auto-workflow--analyzer-failover-candidate` (L222) — Returns a failover candidate when the primary analyzer fails.
- `gptel-auto-workflow--effective-project-root` (L247) — Returns the effective project root, preferring override over current project.
- `gptel-auto-workflow--skip-headless-target-p` (L254) — Checks if a target is in the headless denylist (critical files, tool definitions).
- `gptel-auto-workflow--discover-targets` (L262) — Discovers all eligible target files in the project, filtering by denylist and size.
- `gptel-auto-workflow--gather-context` (L307) — Gathers context for target selection: git history, file sizes, recent changes, known issues.
- `gptel-auto-workflow--local-research-patterns` (L371) — Runs local research to discover patterns, anti-patterns, and code smells.
- `gptel-auto-workflow--build-research-prompt` (L989) — Builds the research prompt with context, recent outcomes, and strategy guidance.
- `gptel-auto-workflow--research-patterns` (L1305) — Executes research via the analyzer subagent, with retry logic.
- `gptel-auto-workflow--ask-analyzer-for-targets` (L1372) — Asks the LLM analyzer to select optimization targets.
- `gptel-auto-workflow--parse-targets` (L1745) — Parses analyzer response into target file paths, with JSON and regex fallback.
- `gptel-auto-workflow--handle-analyzer-error-state` (L1785) — Handles analyzer errors with failover to static targets.
- `gptel-auto-workflow-select-targets` (L2211) — Main entry: orchestrates research, analyzer selection, and target validation.
- `gptel-auto-workflow--load-active-strategy` (L2313) — Loads the active research strategy from configuration.
- `gptel-auto-workflow--save-research-trace` (L2456) — Persists research trace to disk for mementum tracking.
- `gptel-auto-workflow-run-research` (L2662) — Runs research independently of target selection (for periodic research).
- `gptel-auto-workflow-load-research-findings` (L2719) — Loads cached research findings for the current project.
- `gptel-auto-workflow-start-periodic-research` (L2764) — Starts periodic research daemon.

## Dependencies

- `cl-lib`, `json`
- `gptel-tools-agent` — subagent delegation for LLM calls
- `gptel-benchmark-subagent` (soft) — benchmark subagent integration
- `gptel-auto-workflow-research-cache` (soft) — research result caching
- `gptel-auto-workflow-research-benchmark` (soft) — research trace benchmarking

## Integration Points

- **gptel-tools-agent-main** — `run-async` and `cron-safe` call `select-targets` to get the target list for each experiment batch.
- **gptel-auto-workflow-evolution** — evolution knowledge is loaded for context enrichment.
- **gptel-tools-agent-prompt-build** — frontier-saturated targets are filtered before selection.
- **gptel-tools-agent-benchmark** — project root is used for path resolution.
- **gptel-benchmark-subagent** — research findings are benchmarked for quality.
- **gptel-auto-workflow-research-benchmark** — traces are loaded for outcome analysis.

## See Also

- [gptel-auto-workflow-evolution](gptel-auto-workflow-evolution.md) — Evolution engine consuming selected targets
- [gptel-tools-agent-main](gptel-tools-agent-main.md) — Main workflow calling target selection
- [gptel-auto-workflow-bootstrap](gptel-auto-workflow-bootstrap.md) — Headless daemon bootstrap
- [gptel-auto-workflow-knowledge-reasoning](gptel-auto-workflow-knowledge-reasoning.md) — Knowledge reasoning for research

---
*Auto-generated from code header. Manually refined 2026-06-06.*