# STATE: Current Emacs Project Configuration

## Recent Updates
- **AST NATIVE TOOLS**: Successfully built and registered `AST_Map`, `AST_Read`, and `AST_Replace` tools in `lisp/modules/gptel-tools-ast.el` utilizing `treesit-agent-tools`. Integrated them into the `gptel-tools` registry and updated agent system prompts to strictly require their use when modifying parenthesized languages like `.el` and `.clj`.
- **AST TOOLS CORE**: Created `lisp/treesit-agent-tools.el` with `treesit-agent-get-file-map`, `treesit-agent-extract-node`, and `treesit-agent-replace-node`.
- **XREF GRACEFUL FALLBACK**: Integrated `treesit-local-xref.el` in `init-dev.el` as a mid-tier fallback (priority 50) between LSP and `dumb-jump`.
