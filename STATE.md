# STATE: Current Emacs Project Configuration

## Recent Updates
- **ELISP AST SUPPORT ENABLED**: Fixed `treesit-agent-tools.el` to support Elisp tree-sitter AST operations. Added `treesit-agent--get-defun-regexp` and `treesit-agent--get-defun-name` fallback functions for Elisp. Updated agent prompts to allow `Code_Inspect` and `Code_Replace` for `.el` files. **VERIFIED**: File map extraction, node extraction, and structural replacement all work perfectly for Elisp.
- **TREESIT-AUTO GRAMMARS INSTALLED**: All tree-sitter grammars (Elisp, Python, Rust, Clojure) have been successfully installed to `~/.emacs.d/var/tree-sitter/` with ABI14-compatible revisions. **VERIFIED**: All four grammars load without errors and parse test buffers cleanly (has-error: nil). Corrected tag names: Elisp "1.2" (not "v1.2.0"), Rust "v0.21.0".
- **UNIFIED TREE-SITTER DIRECTORY**: The `~/.emacs.d/tree-sitter` directory has been merged into `var/tree-sitter` and replaced with a symlink. Emacs is now explicitly configured in `init-dev.el` with `treesit-extra-load-path` pointing to `var/tree-sitter`. This eliminates the "two directory" confusion where Emacs 29+ native engine downloaded to one place while older tree-sitter.el configurations looked in another.
- **UNIFIED KISS TOOLING**: Removed fragmented LSP and AST tools in favor of a unified `Code_*` interface (`Code_Map`, `Code_Inspect`, `Code_Replace`, `Code_Check`). This dramatically reduces the cognitive load on the LLM.
- **SMART DIAGNOSTICS**: `Code_Check` now automatically cascades from LSP diagnostics to CLI linters (`ruff`, `eslint`, `cargo`) if no server is available.
- **AST SYNTAX VALIDATION**: Added syntax validation to `treesit-agent-replace-node` using Emacs 30 compatible `treesit-node-check`.
