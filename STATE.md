# STATE: Current Emacs Project Configuration

## Recent Updates
- **ELISP INTROSPECTION ROUTING**: Updated `code_agent.md` and `plan_agent.md` to explicitly forbid the AI from attempting to use `Code_Inspect`/`Code_Replace` for Emacs Lisp files (due to Emacs 30 ABI mismatches with the Wilfred tree-sitter grammar). The AI is now instructed to use the highly-reliable native `get_symbol_source`, `describe_symbol`, and standard `Edit` tools for `.el` files.
- **UNIFIED KISS TOOLING**: Removed fragmented LSP and AST tools in favor of a unified `Code_*` interface (`Code_Map`, `Code_Inspect`, `Code_Replace`, `Code_Check`). This dramatically reduces the cognitive load on the LLM.
- **SMART DIAGNOSTICS**: `Code_Check` now automatically cascades from LSP diagnostics to CLI linters (`ruff`, `eslint`, `cargo`) if no server is available.
- **AST SYNTAX VALIDATION**: Added syntax validation to `treesit-agent-replace-node` using Emacs 30 compatible `treesit-node-check`.
- **AST DIFF PREVIEWS**: Integrated inline diff UI previews for `Code_Replace` using `diff-added`/`diff-removed` faces in `gptel-agent--confirm-overlay`.
