# STATE: Current Emacs Project Configuration

## Recent Updates
- **AST GRACEFUL ERROR HANDLING**: Added `condition-case` and `with-timeout` wrappers to `AST_Map`, `AST_Read`, and `AST_Replace` to ensure the agent doesn't hang or crash if tree-sitter fails to parse a file or takes too long.
- **AST CLOJURE FAMILY SUPPORT**: Expanded agent instructions and tool descriptions in `assistant/prompts/code_agent.md`, `gptel-tools-ast.el`, and `ast_read.md`/`ast_replace.md` to mandate structural editing across the entire Clojure ecosystem (`.clj`, `.cljs`, `.cljc`, `.edn`). Released as `0.2.6`.
- **AST NATIVE TOOLS**: Successfully built and registered `AST_Map`, `AST_Read`, and `AST_Replace` tools in `lisp/modules/gptel-tools-ast.el` utilizing `treesit-agent-tools`. Integrated them into the `gptel-tools` registry and updated agent system prompts to strictly require their use when modifying parenthesized languages like `.el` and `.clj`.
- **AST TOOLS CORE**: Created `lisp/treesit-agent-tools.el` with `treesit-agent-get-file-map`, `treesit-agent-extract-node`, and `treesit-agent-replace-node`.
- **XREF GRACEFUL FALLBACK**: Integrated `treesit-local-xref.el` in `init-dev.el` as a mid-tier fallback (priority 50) between LSP and `dumb-jump`.
