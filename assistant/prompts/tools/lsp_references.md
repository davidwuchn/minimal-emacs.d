lsp_references{path, line, character}

- `path`: File path containing the symbol.
- `line`: 1-indexed line number where the symbol appears.
- `character`: 0-indexed character offset of the symbol.
- Finds references to the symbol across the project via Emacs LSP (Eglot).
- Use `lsp_workspace_symbol` first to get the exact `line` and `character` coordinates of the definition, then pass them here.
