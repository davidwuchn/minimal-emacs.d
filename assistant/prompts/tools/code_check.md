λ(). check(project-wide) | ret:file:line:[type] msg | cascade:LSP→CLI(ruff|eslint|cargo)

# Code_Check - Project-Wide Diagnostics

## Purpose
Get **project-wide** diagnostics/errors to verify your changes haven't broken the build.

## ⚠️ CRITICAL: Code_Check vs Diagnostics

| Tool | Scope | Fallback | When to Use |
|------|-------|----------|-------------|
| **Code_Check** | **Entire project** | LSP → CLI linters | **DEFAULT** - Verify project health |
| `Diagnostics` | Open buffers only | None (flymake only) | Quick check of currently open files |

**ALWAYS prefer `Code_Check`** - it's more comprehensive and has CLI fallback.

## When to Use
- **AFTER** making code changes (before committing)
- When asked to "verify the changes" or "check for errors"
- Before running tests (catch syntax/type errors first)
- Project health check (find all errors across all files)

## Usage
```
Code_Check{}
```

## Returns
Formatted list of all diagnostics with `file:line:[type]:message` format.

## Examples
```
Code_Check{}
→ src/utils.py:42 [Error] Undefined variable 'undefined_var'
  src/main.py:15 [Warning] Unused import 'os'
  src/core.rs:28 [Error] Mismatched types: expected `i32`, found `String`

# When no LSP but CLI linters available
Code_Check{}
→ Note: No LSP server running. Falling back to CLI linter:
  
  No linter errors (ruff)

# When code is clean
Code_Check{}
→ No compiler or LSP diagnostics found for the current project. (LSP server is running, code is clean).
```

## ⚠️ Smart Fallback Chain
1. **LSP Diagnostics** (if eglot server is running)
   - Type errors, undefined vars, import errors
   - Language-specific checks (ruff, pylint, rustc, etc.)

2. **CLI Linters** (if no LSP server)
   - Python: `ruff check .` → `flake8 .`
   - JavaScript: `npm run lint` → `npx eslint .`
   - Rust: `cargo check`
   - Reports: "No linter errors (ToolName)" if clean

## Dependencies
- **Required**: flymake (built-in to Emacs 29+)
- **Optional**: LSP server (eglot) for language-specific checks
- **Optional**: CLI linters (ruff, eslint, cargo) for fallback

## Failure Modes
| Symptom | Cause | Resolution |
|---------|-------|------------|
| "flymake--project-diagnostics not available" | Flymake not initialized | Open a source file first, ensure major mode is loaded |
| "No LSP server running" | LSP not configured | Code_Check will automatically fall back to CLI linters |
| No errors shown | Code is clean OR linters not installed | Verify with manual command: `ruff check .` or `cargo check` |

## Notes
- Automatically detects project type (Python, JS, Rust, etc.)
- Returns "No compiler or LSP diagnostics found" if code is clean
- Works even without LSP (falls back to CLI linters)
- Use after Code_Replace to verify changes are valid
- **DIFFERENT from `Diagnostics` tool**: Code_Check scans entire project, Diagnostics only checks open buffers
