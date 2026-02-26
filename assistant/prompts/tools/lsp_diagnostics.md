lsp_diagnostics{}

- Requires no arguments.
- Returns current project-wide syntax/type errors and warnings via Flymake/Eglot.
- **CRITICAL**: Always run this after making code edits (`Edit`, `ApplyPatch`) to verify you haven't introduced compilation or type errors. If it reports errors, fix them.
