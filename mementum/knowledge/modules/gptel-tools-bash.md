# gptel-tools-bash

## Purpose

Implements the async Bash tool for gptel-agent, enabling AI agents to execute shell commands. Features a persistent bash process to maintain environment state across calls, configurable timeout (default 60s), Plan mode sandbox for safe command validation, and automatic abort support. The tool is context-aware: it inherits the working directory and process environment from the associated gptel FSM buffer, and recreates the persistent shell when environment variables change.

## File Stats

- **Lines**: 312
- **Path**: `lisp/modules/gptel-tools-bash.el`

## Key Functions

- `my/gptel--bash-context-entry-p` (L44) — Checks if an environment entry requires bash process recreation (e.g., workflow status file changes).
- `my/gptel--bash-related-fsm-buffer` (L51) — Finds the related gptel FSM request buffer for context inheritance.
- `my/gptel--bash-context-buffer` (L63) — Returns the best buffer to use for bash process context (source buffer or related FSM buffer).
- `my/gptel--bash-context-environment` (L79) — Returns the process environment for bash execution, preferring subagent process environment.
- `my/gptel--bash-context-directory` (L89) — Returns the working directory for bash execution, inherited from the context buffer.
- `my/gptel--bash-context-signature` (L101) — Computes a signature of the current bash context for change detection.
- `my/gptel--reset-persistent-bash` (L107) — Kills the persistent bash process and clears its state.
- `my/gptel--safe-bash-command-p` (L118) — Validates that a command is safe to execute under Plan mode restrictions.
- `my/gptel--ensure-persistent-bash` (L155) — Ensures the persistent bash process is running, recreating it if needed.
- `my/gptel--bash-process-filter` (L189) — Process filter that accumulates output and detects completion via a marker string.
- `my/gptel--agent-bash-async` (L221) — Main async bash entry point: validates command, sets up persistent shell, executes with timeout.
- `gptel-tools-bash-register` (L297) — Registers the Bash tool with gptel-agent, defining the tool schema.

## Dependencies

- `cl-lib`, `subr-x`, `seq`
- `gptel-ext-abort` — abort generation support
- `gptel-tools-agent-base` — workspace boundary validation

## Integration Points

- **gptel-tools** — `gptel-tools-register-all` calls `gptel-tools-bash-register`.
- **gptel-tools-agent-base** — `expand-workspace-path` ensures shell commands operate within allowed directories.
- **gptel-ext-abort** — commands are interruptible via abort generation.
- **gptel-request** — `gptel-fsm-info` for retrieving related FSM context.
- **gptel-auto-workflow** — subagent process environment is inherited for workflow context.

## See Also

- [gptel-tools](gptel-tools.md) — Central tool registry
- [gptel-tools-agent-base](gptel-tools-agent-base.md) — Shell command timeout infrastructure
- [gptel-tools-edit](gptel-tools-edit.md) — Edit tool (often used alongside bash)
- [gptel-tools-grep](gptel-tools-grep.md) — Grep tool (search companion)

---
*Auto-generated from code header. Manually refined 2026-06-06.*