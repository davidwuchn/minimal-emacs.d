# gptel-auto-workflow-bootstrap

## Purpose

Headless bootstrap module that initializes the auto-workflow daemon from a fresh Emacs worker process. Configures the package system to use repo-local ELPA archives, seeds the load-path with lisp modules and gptel packages, ensures required runtime packages (yaml, magit) are installed, and loads the full gptel core stack. The `gptel-auto-workflow-bootstrap-run` function is the single entry point called by the pipeline cron wrapper via `emacsclient --eval`.

## File Stats

- **Lines**: 209
- **Path**: `lisp/modules/gptel-auto-workflow-bootstrap.el`

## Key Functions

- `gptel-auto-workflow-bootstrap--elpa-dirs` (L40) — Returns package directories under `ROOT/var/elpa` suitable for `load-path`.
- `gptel-auto-workflow-bootstrap--configure-package-system` (L51) — Points `package.el` at the repo-local package cache and activates it, setting archive priorities and gnupg directory.
- `gptel-auto-workflow-bootstrap--load-package-archive-cache` (L63) — Loads cached package archive contents from disk without network refresh, avoiding unnecessary API calls.
- `gptel-auto-workflow-bootstrap--ensure-package-installed` (L88) — Ensures a package can be loaded, installing it from the local cache or refreshing archives if needed.
- `gptel-auto-workflow-bootstrap--seed-load-path` (L97) — Adds repo-local directories (lisp, lisp/modules, packages/gptel, etc.) and ELPA package dirs to `load-path`.
- `gptel-auto-workflow-bootstrap--known-gptel-load-error-p` (L108) — Detects the known fresh-daemon gptel `invalid-read-syntax` error for graceful retry.
- `gptel-auto-workflow-bootstrap--gptel-ready-p` (L112) — Checks if core gptel entrypoints (`gptel-send`, `gptel-request`) are available.
- `gptel-auto-workflow-bootstrap--load-gptel-core` (L118) — Loads the full gptel stack from root: gptel, gptel-request, gptel-agent, gptel-agent-tools, with fallback to compiled `.elc` files.
- `gptel-auto-workflow-bootstrap-run` (L141) — Main entry point: configures packages, seeds load-path, loads nucleus and gptel modules, then queues the requested action (instincts, mementum, projects, or research).

## Dependencies

- `subr-x` — for `proper-list-p`

## Integration Points

- **Pipeline cron wrapper** — `gptel-auto-workflow-bootstrap-run` is called by `emacsclient --eval` from the scheduled pipeline.
- **gptel-auto-workflow-projects** — `queue-all-instincts`, `queue-all-mementum`, `queue-all-projects`, `queue-all-research` are declared for action queuing.
- **nucleus-tools** — loaded early to provide tool configuration before gptel stack.
- **nucleus-prompts** — loaded for prompt definitions.
- **nucleus-presets** — loaded for preset configurations.
- **gptel-ext-backends** — loaded for provider backend configuration.

## See Also

- [gptel-auto-workflow-production](gptel-auto-workflow-production.md) — Production timer and evolution scheduling
- [gptel-tools-agent-main](gptel-tools-agent-main.md) — Main workflow execution
- [gptel-auto-workflow-strategic](gptel-auto-workflow-strategic.md) — Target selection

---
*Auto-generated from code header. Manually refined 2026-06-06.*