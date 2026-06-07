# gptel-tools-agent-base

## Purpose

Foundation module providing base utilities, validation, and shell command infrastructure for the gptel agent system. Implements the critical workspace boundary validator that ensures file operations stay within allowed directories, shell command execution with timeout protection, run-id management for experiment tracking, commit tracking and orphan recovery, and ELPA package management for headless workflows.

## File Stats

- **Lines**: 1026
- **Path**: `lisp/modules/gptel-tools-agent-base.el`

## Key Functions

- `gptel-auto-workflow--default-dir` (L38) — Returns the default directory for git operations, falling back to `~/.emacs.d/`.
- `gptel-auto-workflow--worktree-base-root` (L46) — Returns the stable root for workflow-owned worktree artifacts.
- `gptel-auto-workflow--validate-non-empty-string` (L89) — Validates that a value is a non-nil, non-empty string; signals error on failure.
- `gptel-auto-workflow--non-empty-string-p` (L99) — Predicate: returns t for non-nil, non-empty strings.
- `gptel-auto-workflow--path-within-workspace-p` (L106) — Boundary validator: checks if a path is within allowed workspace roots, handling symlinks, relative paths, and `..` escapes.
- `gptel-auto-workflow--expand-workspace-path` (L124) — Expands and validates a path against workspace boundaries; signals error on violation.
- `with-workspace-boundary` (L138) — Macro that binds a path-var to a boundary-checked path expansion.
- `gptel-auto-workflow--plist-get` (L149) — Safe plist getter with default value, handling nil members.
- `gptel-auto-workflow--make-idempotent-callback` (L172) — Wraps a callback to ensure it fires at most once.
- `gptel-auto-workflow--safe-call` (L205) — Calls a function with error logging, preventing crashes from propagating.
- `gptel-auto-workflow--require-magit-dependencies` (L229) — Ensures magit git functions are available.
- `gptel-auto-workflow--prefer-elpa-transient` (L286) — Prefers transient ELPA packages over built-in versions.
- `gptel-auto-workflow--seed-live-root-load-path` (L311) — Seeds the load-path from a project root's ELPA and lisp directories.
- `gptel-auto-workflow--activate-live-root` (L371) — Activates a project root for live workflow operations.
- `gptel-auto-workflow--read-file-contents` (L463) — Reads file contents with boundary validation.
- `gptel-auto-workflow--terminate-active-shell-processes` (L533) — Kills all registered shell processes.
- `gptel-auto-workflow--shell-command-with-timeout` (L547) — Executes a shell command with configurable timeout (default 30s).
- `gptel-auto-workflow--make-run-id` (L633) — Generates a unique run-id for experiment tracking.
- `gptel-auto-workflow--commit-integrated-p` (L872) — Checks if a commit has been integrated into the main branch.
- `gptel-auto-workflow--track-commit` (L920) — Tracks a commit in the experiment ledger.
- `gptel-auto-workflow--recover-orphans` (L985) — Recovers orphaned commits from previous runs.

## Dependencies

- `cl-lib`, `subr-x`
- `gptel` (soft), `gptel-agent` (soft)
- `magit-git` (soft)
- `gptel-auto-workflow-production` (soft)

## Integration Points

- **gptel-tools-agent-base** is the foundational module used by nearly every other agent module.
- **gptel-tools-agent-main** — workflow orchestration calls `worktree-base-root`, `run-id`, `safe-call`, etc.
- **gptel-tools-** — all tool modules (bash, grep, edit, etc.) use `expand-workspace-path` for boundary enforcement.
- **gptel-auto-workflow-production** — timer and hook infrastructure depends on base utilities.
- **gptel-tools-agent-experiment-loop** — experiment tracking relies on commit tracking and run-id management.
- **gptel-tools-agent-worktree** — worktree operations use `worktree-base-root` and boundary validation.

## See Also

- [gptel-tools-agent-main](gptel-tools-agent-main.md) — Main workflow entry point
- [gptel-tools-bash](gptel-tools-bash.md) — Bash tool using shell command infrastructure
- [gptel-tools-grep](gptel-tools-grep.md) — Grep tool using boundary validation
- [gptel-tools-edit](gptel-tools-edit.md) — Edit tool using boundary validation

---
*Auto-generated from code header. Manually refined 2026-06-06.*