# STATE: Current Emacs Project Configuration

## Recent Updates
- **ERROR HANDLING IMPROVED**: All Code_* tools now have enhanced error detection and user-friendly messages. Code_Map detects missing parsers and suggests installation. Code_Inspect/Code_Usages detect missing ripgrep and provide brew/apt install commands. Code_Usages has LSP retry logic (3 retries, 0.5s delay) for startup race conditions. Code_Check provides clearer messaging about LSP status.
- **TREE-SITTER AUTO-INSTALL**: Changed `treesit-auto-install` from `'prompt` to `'auto` in `init-treesit.el`. Parsers now install automatically on first use without prompting.
- **COMPREHENSIVE DOCS**: Created `docs/CODE_TOOLS.md` with full documentation for all Code_* tools. Updated `assistant/README.md` with Code_* tool table, workflow diagram, and when-to-use guide. All tool prompts now include Dependencies, Failure Modes, and Setup Requirements tables.
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
| Code_Map | ✅ Operational | tree-sitter parser | None (file-local) |
| Code_Inspect | ✅ Operational | tree-sitter, ripgrep | File-local if rg missing |
| Code_Replace | ✅ Operational | tree-sitter parser | Edit (manual) |
| Code_Usages | ✅ Operational | ripgrep (optional) | LSP references |
| Code_Check | ✅ Operational | flymake, LSP (optional) | CLI linters |

## Setup Checklist for Users

1. **Tree-sitter parsers**: Auto-installed on first use (or manual via `M-x treesit-install-language-grammar`)
2. **Ripgrep**: Install for workspace search (`brew install ripgrep` or `apt install ripgrep`)
3. **LSP servers**: Optional, Code_* tools work without LSP (fall back to CLI/ripgrep)
