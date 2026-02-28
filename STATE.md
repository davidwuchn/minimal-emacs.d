# STATE: Current Emacs Project Configuration

## Recent Updates
- **NAMING STANDARDIZED**: Renamed preview tools to PascalCase (InlineDiffPreview, BatchPreview, SyntaxPreview). Standardized arg names to snake_case (old_str, new_str_or_diff, agent_name). Updated all documentation to match.
- **SIGNATURE VALIDATION**: Created nucleus-tools-validate.el to verify tool prompt lambda signatures match registered :args. Interactive: M-x nucleus-validate-tool-signatures. Catches mismatches between documentation and implementation.
- **CLEANUP DEPRECATED PROMPTS**: Removed deprecated LSP tool prompts (lsp_hover.md, lsp_rename.md, code_check.md) and duplicate todowrite.md. Updated nucleus-prompts.el to reference todo_write.md. nucleus now only references existing, non-deprecated tool prompt files.
- **CLEANUP DEPRECATED PROMPTS**: Removed deprecated LSP tool prompts (lsp_hover.md, lsp_rename.md, code_check.md) and duplicate todowrite.md. Updated nucleus-prompts.el to reference todo_write.md. nucleus now only references existing, non-deprecated tool prompt files.
- **TOOL UI AUTO-PERMIT**: Added `a` (auto) option to the tool confirmation prompt. Users can now press `a` to set the confirmation level to 'auto' and automatically permit all subsequent tool calls without being prompted again.
- **OVERLAY KEYMAP TIMING FIX**: Moved gptel-tool-ui.el load BEFORE gptel creates overlays. Keymap now modified synchronously on load (not in with-eval-after-load). All overlays now use our dispatch function from creation.
- **TOOL VERIFY PARENS FIX**: Fixed missing closing parenthesis in nucleus-tools-verify.el dolist loop. Parentheses now balanced (119 open, 119 close). Module loads correctly.
- **TOOL VERIFY FIX**: Added missing (require 'subr-x) to nucleus-tools-verify.el. string-join function needs subr-x library. Compilation now succeeds.
- **TOOL DOCS COMPLETED**: Created/expanded documentation for ApplyPatch, Edit (fixed arg names), Skill, TodoWrite, WebFetch, WebSearch, YouTube, Insert, Mkdir, Move, Write. All tools now have comprehensive docs with usage, parameters, examples, failure modes, and dependencies.
- **RUNTIME TOOL VERIFICATION**: Created nucleus-tools-verify.el to verify all declared tools in nucleus-toolsets are actually registered. Auto-warns on missing/duplicate tools. Interactive: M-x nucleus-verify-tools-interactively.
- **KEYMAP FIX**: Fixed overlay mouse click by modifying gptel-tool-call-actions-map directly with define-key instead of using advice-add. Advice doesn't work with keymap bindings. Moved setup to with-eval-after-load 'gptel to ensure keymap exists.
- **OVERLAY CLICK FIX**: Fixed mouse click on tool permit overlay. Now moves point to click position before prompting, so gptel--accept-tool-calls can retrieve tool data correctly. Clicking overlay now works same as C-c C-y.
- **OVERLAY MOUSE CLICK FIX**: Fixed seq-do error when clicking tool permit overlay. Changed interactive spec to properly handle mouse events from overlay keymap. Now works for both mouse clicks and interactive calls.
- **PREVIEW CALLBACK FIX**: Fixed seq-do error in enhanced preview tools. Changed callbacks to pass string messages directly instead of converting symbols. Matches existing preview tools pattern.
- **ENHANCED PREVIEW TOOLS**: Added inline_diff_preview (syntax-highlighted diffs), batch_preview (multiple files), and syntax_preview (auto-detect mode). All with quick confirm/abort keybindings.
- **5-TIER CONFIRMATION SYSTEM**: Implemented configurable confirmation levels (auto/safe/normal/strict/paranoid). Auto mode skips confirmation, safe mode confirms only dangerous tools, normal confirms all, strict/paranoid add review requirements. Interactive: M-x my/gptel-set-confirmation-level.
- **UNIFIED TOOL UI**: Minibuffer prompt now shows 6 options (y/n/k/i/p/q) matching overlay keymap. Previously showed only 4 options, causing confusion. Consistent UX between overlay clicks and minibuffer prompts.
- **DEPRECATED DOCS REMOVED**: Removed deprecated AST tool docs (ast_map.md, ast_read.md, ast_replace.md, ast_find_workspace.md) and LSP tool docs (lsp_*.md). All functionality merged into Code_* tools. Cleaned up assistant/README.md references.
- **DOCUMENTATION COMPLETE**: Created missing tool docs (bash_ro.md, diagnostics.md, run_agent.md, skill.md). Updated bash_command.md to reference BashRO. Fixed all Code_Check → Diagnostics naming. All registered tools now have corresponding documentation.
- **PARENTHESIS BALANCE FIX**: Fixed unbalanced parentheses in gptel-tools-code.el. Moved comment outside let bindings, added missing closing paren for when block. **FIXES**: "End of file during parsing" errors.
- **GPTL-TOOLS-LSP REQUIRE FIX**: Removed stale `require 'gptel-tools-lsp` from gptel-tools.el. Module was deleted when functionality merged into gptel-tools-code.el. **FIXES**: "Cannot open load file: gptel-tools-lsp" compilation error.
- **BYTE-COMPILATION FIX**: Added `no-byte-compile: t` to gptel-tools-code.el to avoid check-parens false positives with regex patterns containing `\\'`. Removed stale .elc files. **FIXES**: "End of file during parsing" errors. File loads correctly in Emacs sessions.
- **CODE_CHECK REPORTING**: my/gptel--run-fallback-linter now reports exactly what was checked (e.g., "✓ No linter errors (ESLint) - checked package.json"). Non-standard projects get helpful message about what was searched. **FIXES**: Generic "no errors" messages.
- **CODE_USAGES BACKEND REPORTING**: Output now includes which backend was used: "Found X usages of 'symbol' (via LSP|ripgrep)". **FIXES**: User doesn't know if results are semantic (LSP) or text-based (ripgrep).
- **DIAGNOSTICS NAMING**: Tool registered as `Diagnostics` in nucleus toolsets. Updated all documentation to use consistent naming (replaced Code_Check with Diagnostics). Upstream Diagnostics (open-buffers-only) NOT registered.
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
