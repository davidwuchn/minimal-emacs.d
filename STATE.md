# STATE: Current Emacs Project Configuration

## Recent Updates
- **GPTL-TOOLS-LSP REQUIRE FIX**: Removed stale `require 'gptel-tools-lsp` from gptel-tools.el. Module was deleted when functionality merged into gptel-tools-code.el. **FIXES**: "Cannot open load file: gptel-tools-lsp" compilation error.
- **BYTE-COMPILATION FIX**: Added `no-byte-compile: t` to gptel-tools-code.el to avoid check-parens false positives with regex patterns containing `\\'`. Removed stale .elc files. **FIXES**: "End of file during parsing" errors. File loads correctly in Emacs sessions.
- **CODE_CHECK REPORTING**: my/gptel--run-fallback-linter now reports exactly what was checked (e.g., "✓ No linter errors (ESLint) - checked package.json"). Non-standard projects get helpful message about what was searched. **FIXES**: Generic "no errors" messages.
- **CODE_USAGES BACKEND REPORTING**: Output now includes which backend was used: "Found X usages of 'symbol' (via LSP|ripgrep)". **FIXES**: User doesn't know if results are semantic (LSP) or text-based (ripgrep).
- **DIAGNOSTICS VS CODE_CHECK**: Upstream `Diagnostics` tool (open buffers only) overlaps with our `Code_Check` (project-wide + CLI fallback). **Resolution**: Code_Check is superior and registered in nucleus toolsets. Diagnostics remains available from upstream but not promoted. Updated Code_Check prompt to clarify distinction.
- **LSP TOOLS CLEANUP**: Removed 4 redundant LSP tool prompts (lsp_diagnostics, lsp_references, lsp_workspace_symbol, lsp_definition) - all replaced by Code_* tools. Kept lsp_hover (type info at cursor) and lsp_rename (cross-file renaming). **Reduces LLM cognitive load**.
- **PRE-FLIGHT PARSER CHECKS**: All Code_* tools (Map, Inspect, Replace) now verify tree-sitter parser availability BEFORE attempting operations. Auto-detect language from file extension (.py, .el, .clj, .rs). Provide step-by-step recovery: install → reopen → verify → fallback. **FIXES**: Confusing errors when files aren't in tree-sitter mode.
- **ENHANCED LSP RETRY LOGIC**: Code_Usages now uses 5 retries with exponential backoff (0.5s, 1s, 2s, 4s, 8s = ~15s total) for LSP startup race conditions. Detects empty results vs. errors. **FIXES**: Premature fallback to ripgrep when LSP is still indexing.
- **ACTIONABLE ERROR MESSAGES**: All Code_* tools now provide numbered ACTION steps with exact commands (M-x commands, brew/apt install, verification commands). Distinguish between parser missing, ripgrep missing, timeout, and syntax errors.
- **BUFFER MODE ENFORCEMENT**: Code_Map, Code_Inspect, Code_Replace check (treesit-parser-list) and provide language-specific recovery instructions with fallback to standard tools (Read, Edit, Grep).
- **TREE-SITTER AUTO-INSTALL**: Changed `treesit-auto-install` from `'prompt` to `'auto` in `init-treesit.el`. Parsers now install automatically on first use without prompting.
- **COMPREHENSIVE DOCS**: Created `docs/CODE_TOOLS.md` with full documentation. Updated `assistant/README.md` with Code_* tool table, workflow diagram, and when-to-use guide. All tool prompts include Dependencies, Failure Modes, and Setup Requirements tables.
- **CODE_USAGES ADDED**: New tool finds all references of a symbol across the project. Cascades: LSP references (semantic) → ripgrep (text search). Added to all nucleus toolsets.
- **POST-EARLY-INIT CREATED**: `post-early-init.el` sets `treesit-extra-load-path` early in the boot sequence, ensuring tree-sitter grammars are found before any modes load.
- **CODE_CHECK FIXED**: Replaced missing `my/gptel-lsp--get-server` with `my/gptel--lsp-active-p` (uses `eglot-current-server`). LSP diagnostics now work correctly.
- **BASH WHITELIST EXPANDED**: Added common commands (git rev-parse, cargo, npm, pip, python, node, basename, dirname, realpath, etc.). Improved sandbox error messages. **FIXES**: Doom-loop issues where LLM retries same Bash command.
- **DUMB-JUMP VERIFIED**: Full verification for Elisp, Clojure (.clj/.cljs/.cljc), Python (.py), and Rust (.rs). Xref fallback chain: LSP (0) → Tree-sitter (50) → Dumb-jump (90).
- **ELISP LSP CLARIFIED**: Emacs Lisp does NOT use LSP - native introspection (elisp--xref-backend, find-function, describe-function) is superior. Optimal stack: elisp--xref-backend → dumb-jump → Tree-sitter.
- **ALL LANGUAGES SUPPORTED**: Code_* tools verified for Elisp, Clojure family, Python, Rust with AST structural editing, syntax validation, and LSP integration.

## Tool Status

| Tool | Status | Dependencies | Fallback |
|------|--------|--------------|----------|
| Code_Map | ✅ Operational | tree-sitter parser | Read, Grep |
| Code_Inspect | ✅ Operational | tree-sitter, ripgrep | File-local if rg missing |
| Code_Replace | ✅ Operational | tree-sitter parser | Edit (manual) |
| Code_Usages | ✅ Operational | ripgrep (optional) | LSP references |
| Code_Check | ✅ Operational | flymake, LSP (optional) | CLI linters |

## Error Handling Matrix

| Error Type | Detection | Action Provided |
|------------|-----------|-----------------|
| Parser not installed | `(treesit-parser-list)` nil | M-x treesit-install-language-grammar + reopen file |
| Ripgrep missing | `(executable-find "rg")` nil | brew/apt install commands |
| LSP not ready | Empty xref results | 5 retries with exponential backoff |
| Syntax error | `treesit-node-check` has-error | Check bracket balancing |
| Timeout | with-timeout exceeded | Provide file_path to skip workspace search |

## Setup Checklist for Users

1. **Tree-sitter parsers**: Auto-installed on first use (or manual via `M-x treesit-install-language-grammar`)
2. **Ripgrep**: Install for workspace search (`brew install ripgrep` or `apt install ripgrep`)
3. **LSP servers**: Optional, Code_* tools work without LSP (fall back to CLI/ripgrep)
