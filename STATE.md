# STATE: Current Emacs Project Configuration

## Recent Updates
- **UNIFIED KISS TOOLING**: Removed fragmented LSP and AST tools in favor of a unified `Code_*` interface (`Code_Map`, `Code_Inspect`, `Code_Replace`, `Code_Check`). This dramatically reduces the cognitive load on the LLM.
- **SMART DIAGNOSTICS**: `Code_Check` now automatically cascades from LSP diagnostics to CLI linters (`ruff`, `eslint`, `cargo`) if no server is available.
- **AST SYNTAX VALIDATION**: Added syntax validation to `treesit-agent-replace-node` (rejects replacement if it breaks tree grammar).
- **AST DIFF PREVIEWS**: Integrated inline diff UI previews for `Code_Replace` using `diff-added`/`diff-removed` faces in `gptel-agent--confirm-overlay`.
- **AST GRACEFUL ERROR HANDLING**: Added `condition-case` and `with-timeout` wrappers.
