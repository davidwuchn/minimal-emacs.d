lsp_workspace_symbol{query}

- `query`: Symbol name or partial name to search across the project.
- Finds definitions of a symbol via Emacs LSP (Eglot).
- Returns results in the format: `Name (Kind) - File:Line:Char`
- Use this *instead of* `Grep` or `Glob` to accurately find where a class, function, or variable is defined.
