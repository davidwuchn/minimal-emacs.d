# gptel-tools-edit

## Purpose

Implements the async Edit tool for gptel-agent with three editing modes: hashline-based (content-addressed line identifiers for reliable editing), patch-based (applying unified diff patches), and traditional string replacement. The hashline mode, inspired by the harness problem, enables AI agents to target specific lines even after the file has been modified by other edits. Includes patch target validation to prevent path traversal attacks.

## File Stats

- **Lines**: 292
- **Path**: `lisp/modules/gptel-tools-edit.el`

## Key Functions

- `my/gptel--agent--strip-diff-fences` (L42) — Strips leading/trailing markdown code fences from diff/patch text, handling multi-line whitespace.
- `my/gptel--validate-patch-target` (L54) — Validates that a patch targets the expected file, not an arbitrary path (prevents path traversal via crafted diff headers).
- `my/gptel--agent-edit-async` (L85) — Main async edit function: dispatches to hashline, patch, or string replacement based on arguments. Patch mode is truly async/interruptible.
- `my/gptel--agent-edit-hashline` (L171) — Hashline-based edit: uses content-addressed lines to find the correct location for old_str replacement, even after concurrent edits.
- `my/gptel--agent-edit-apply-patch` (L201) — Patch mode: applies a unified diff to the target file with timeout and abort support.
- `gptel-tools-edit-register` (L254) — Registers the Edit tool with gptel-agent, defining the tool schema and wiring the async handler.

## Dependencies

- `cl-lib`, `subr-x`, `seq`
- `gptel-ext-abort` — abort generation support
- `gptel-tools-preview` — preview tool for showing changes
- `gptel-tools-edit-hashline` — content-addressed line identifiers
- `gptel-tools-agent-base` — workspace boundary validation

## Integration Points

- **gptel-tools** — `gptel-tools-register-all` calls `gptel-tools-edit-register`.
- **gptel-tools-agent-base** — `expand-workspace-path` ensures file operations stay within allowed directories.
- **gptel-tools-preview** — edit results are passed to preview for user confirmation.
- **gptel-tools-edit-hashline** — hashline mode delegates to the hashline module for line identification.
- **gptel-ext-abort** — patch mode is interruptible via abort generation.

## See Also

- [gptel-tools](gptel-tools.md) — Central tool registry
- [gptel-tools-agent-base](gptel-tools-agent-base.md) — Workspace boundary validation
- [gptel-tools-bash](gptel-tools-bash.md) — Bash tool for shell-based edits

---
*Auto-generated from code header. Manually refined 2026-06-06.*