# gptel-tools-grep

## Purpose

Implements the async Grep tool for gptel-agent, enabling AI agents to search file contents using ripgrep (preferred) or grep. Features configurable timeout (default 20s), abort support, glob pattern filtering, context lines, and progressive output shortening to respect max answer character limits. Results are sorted by modification time when using ripgrep, providing the most relevant matches first.

## File Stats

- **Lines**: 191
- **Path**: `lisp/modules/gptel-tools-grep.el`

## Key Functions

- `gptel-tools-grep--normalize-context-lines` (L34) — Normalizes context line values: accepts integer-like strings, clamps negatives to 0, caps at 30, returns invalid values unchanged for contract validation.
- `my/gptel--agent-grep-async` (L47) — Main async grep function: validates regex and path (with workspace boundary check), selects ripgrep or grep, executes with configurable args, and returns progressively shortened output.
- `gptel-tools-grep-register` (L159) — Registers the Grep tool with gptel-agent, defining the tool schema with args for regex, path, glob, context-lines, and max-answer-chars.

## Dependencies

- `cl-lib`, `subr-x`, `seq`
- `gptel-ext-abort` — abort generation support
- `nucleus-tools` — `nucleus-tool-max-answer-chars` for default output limit
- `gptel-tools-agent-base` — workspace boundary validation

## Integration Points

- **gptel-tools** — `gptel-tools-register-all` calls `gptel-tools-grep-register`.
- **gptel-tools-agent-base** — `expand-workspace-path` ensures searched paths are within allowed directories.
- **gptel-ext-abort** — search is interruptible via abort generation.
- **nucleus-tools** — default max answer chars from `nucleus-tool-max-answer-chars`.

## See Also

- [gptel-tools](gptel-tools.md) — Central tool registry
- [gptel-tools-agent-base](gptel-tools-agent-base.md) — Workspace boundary validation
- [gptel-tools-bash](gptel-tools-bash.md) — Bash tool (often used alongside grep)
- [nucleus-tools](nucleus-tools.md) — Nucleus tool configuration

---
*Auto-generated from code header. Manually refined 2026-06-06.*