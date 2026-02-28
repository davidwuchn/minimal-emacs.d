# STATE: Current Emacs Project Configuration

## Recent Updates
- **CODE_* PROMPT DOCS EXPANDED**: Created comprehensive documentation for all Code_* tools in `assistant/prompts/tools/`. Each tool doc includes: purpose, when to use, usage examples, parameters, returns, and notes. Updated code_agent.md and plan_agent.md with numbered workflow steps (1.Code_Map → 2.Code_Inspect → 3.Code_Replace → 4.Code_Usages → 5.Code_Check).
- **CODE_USAGES ADDED**: New tool finds all references of a symbol across the project. Cascades: LSP references (semantic) → ripgrep (text search). Added to all nucleus toolsets.
- **POST-EARLY-INIT CREATED**: `post-early-init.el` sets `treesit-extra-load-path` early in the boot sequence, ensuring tree-sitter grammars are found before any modes load.
- **CODE_CHECK FIXED**: Replaced missing `my/gptel-lsp--get-server` with `my/gptel--lsp-active-p` (uses `eglot-current-server`). LSP diagnostics now work correctly.
- **BASH WHITELIST EXPANDED**: Added common commands (git rev-parse, cargo, npm, pip, python, node, basename, dirname, realpath, etc.). Improved sandbox error messages. **FIXES**: Doom-loop issues where LLM retries same Bash command.
- **DUMB-JUMP VERIFIED**: Full verification for Elisp, Clojure (.clj/.cljs/.cljc), Python (.py), and Rust (.rs). Xref fallback chain: LSP (0) → Tree-sitter (50) → Dumb-jump (90).
- **ELISP LSP CLARIFIED**: Emacs Lisp does NOT use LSP - native introspection (elisp--xref-backend, find-function, describe-function) is superior. Optimal stack: elisp--xref-backend → dumb-jump → Tree-sitter.
- **ALL LANGUAGES SUPPORTED**: Code_* tools verified for Elisp, Clojure family, Python, Rust with AST structural editing, syntax validation, and LSP integration.
