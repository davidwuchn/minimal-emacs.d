# gptel-tools

## Purpose

The central tool registry for gptel-agent. Loads and registers all individual tool modules (Bash, Grep, Glob, Edit, Apply, Preview, Programmatic, Introspection, Code, Agent, Memory) and provides the `gptel-tools-register-all` function that wires them into the gptel-agent tool system. Also defines the `invalid` tool for catching malformed model tool calls and the `gptel-tools-after-register-hook` for post-registration actions.

## File Stats

- **Lines**: 414
- **Path**: `lisp/modules/gptel-tools.el`

## Key Functions

- `gptel-tools--eval-expression` (L45) — Evaluates Emacs Lisp expressions safely, returning results and captured stdout.
- `gptel-tools-register-all` (L71) — Registers all gptel tools: calls each module's register function, then registers the `invalid` tool and global tools (Read, Write, Web Search, Web Fetch).
- `my/gptel--read-file-safe` (L256) — Reads a file safely with boundary validation, optional line range, and hashline support.
- `my/gptel--extract-pdf-text` (L281) — Extracts text from PDF files for AI consumption.
- `gptel-tools--wrap-result-callback` (L329) — Wraps a tool callback to handle errors and produce consistent result messages.
- `my/gptel-web-search-safe` (L347) — Performs web search via eww with safe error handling.
- `my/gptel-web-fetch-safe` (L363) — Fetches web content with safe error handling.
- `my/gptel--around-web-search-eww-callback` (L381) — Advice around eww callbacks for web search tool integration.
- `gptel-tools-setup` (L395) — Setup function that ensures all tool modules are loaded and registered.

## Dependencies

- `cl-lib`, `subr-x`, `seq`
- `gptel-tools-agent-base` — boundary validation
- `gptel-tools-bash` — Bash tool
- `gptel-tools-grep` — Grep tool
- `gptel-tools-glob` — Glob tool
- `gptel-tools-edit` — Edit tool
- `gptel-tools-apply` — Apply patch tool
- `gptel-tools-preview` — Preview tool
- `gptel-tools-programmatic` — Programmatic tool
- `gptel-tools-introspection` — Introspection tool
- `gptel-tools-code` — Code tool (replaces deprecated lsp and ast)
- `gptel-tools-agent` — Agent delegation tool
- `gptel-tools-memory` — Memory tool

## Integration Points

- **gptel-agent** — `gptel-tools-register-all` is called after gptel-agent-tools loads to register all tools.
- **gptel-tools-agent** — agent delegation tool is registered conditionally when `gptel-tools-agent-register` is fboundp.
- **gptel-request** — `gptel--file-binary-p` is declared for binary file detection.
- **gptel-tools-after-register-hook** — hook run after registration for presets and buffer updates.

## See Also

- [gptel-tools-bash](gptel-tools-bash.md) — Bash tool implementation
- [gptel-tools-grep](gptel-tools-grep.md) — Grep tool implementation
- [gptel-tools-edit](gptel-tools-edit.md) — Edit tool implementation
- [gptel-tools-agent-base](gptel-tools-agent-base.md) — Base utilities and boundary validation

---
*Auto-generated from code header. Manually refined 2026-06-06.*