λ(). Diagnostics(project-wide) | ret:file:line:[type] msg + backend(LSP|CLI) | cascade:LSP→CLI(ruff|eslint|cargo)

# Diagnostics (Code_Check) - Project-Wide Diagnostics

## Tool Name
**Registered as**: `Diagnostics` (overrides upstream gptel-agent-tools.el)

**Purpose**: Get **project-wide** diagnostics/errors to verify your changes haven't broken the build.

## ⚠️ CRITICAL: This Tool vs Upstream Diagnostics

| Feature | This Tool (Ours) | Upstream Diagnostics |
|---------|-----------------|---------------------|
| **Scope** | **Entire project** ✅ | Open buffers only |
| **LSP awareness** | **Checks LSP status** ✅ | None |
| **Fallback** | **CLI linters** (ruff/eslint/cargo) ✅ | None (flymake only) |
| **Reports backend** | **Yes (LSP or CLI)** ✅ | N/A |
| **Registered** | ✅ Yes (overrides upstream) | ❌ No (not in nucleus toolsets) |

**This Diagnostics tool is STRICTLY SUPERIOR** - it replaces the upstream version.

## When to Use
- **AFTER** making code changes (before committing)
- When asked to "verify the changes" or "check for errors"
- Before running tests (catch syntax/type errors first)
- Project health check (find all errors across all files)

## Usage
```
Diagnostics{}
```

## Returns
Formatted list of all diagnostics with `file:line:[type]:message` format.

**IMPORTANT**: Output indicates which backend was used:
- LSP diagnostics when server is running
- CLI linter output with checkmark (✓) when successful
- Clear message about what was checked

## Examples
```
# LSP backend (semantic diagnostics)
Diagnostics{}
→ src/utils.py:42 [Error] Undefined variable 'undefined_var'
  src/main.py:15 [Warning] Unused import 'os'

# CLI backend (Python project)
Diagnostics{}
→ ✓ No linter errors (ruff/flake8) - checked Python project (pyproject.toml/setup.py)

# CLI backend (JavaScript project)
Diagnostics{}
→ ✓ No linter errors (ESLint) - checked package.json (JavaScript/Node.js)

# CLI backend (Rust project)
Diagnostics{}
→ ✓ No compiler errors (cargo check) - checked Cargo.toml (Rust)

# No standard project files found
Diagnostics{}
→ Note: No standard project files found (package.json, pyproject.toml, Cargo.toml).
  Searched for: JavaScript (package.json), Python (pyproject.toml/setup.py/.py), Rust (Cargo.toml).
  If this is a different language, configure a linter or use LSP for diagnostics.

# When code is clean with LSP
Diagnostics{}
→ No compiler or LSP diagnostics found for the current project. (LSP server is running, code is clean).
```

## ⚠️ Smart Fallback Chain
1. **LSP Diagnostics** (if eglot server is running)
   - Type errors, undefined vars, import errors
   - Language-specific checks (ruff, pylint, rustc, etc.)
   - **Reports**: "LSP server is running"

2. **CLI Linters** (if no LSP server)
   - Python: `ruff check .` → `flake8 .`
   - JavaScript: `npm run lint` → `npx eslint .`
   - Rust: `cargo check`
   - **Reports**: "✓ No linter errors (tool) - checked [project type]"

3. **No Standard Project** (if no recognized files)
   - Reports what was searched for
   - Suggests configuring linter or using LSP
   - **Reports**: "Note: No standard project files found..."

## Dependencies
- **Required**: flymake (built-in to Emacs 29+)
- **Optional**: LSP server (eglot) for language-specific checks
- **Optional**: CLI linters (ruff, eslint, cargo) for fallback

## Failure Modes
| Symptom | Cause | Resolution |
|---------|-------|------------|
| "flymake--project-diagnostics not available" | Flymake not initialized | Open a source file first, ensure major mode is loaded |
| "No LSP server running" | LSP not configured | Tool automatically falls back to CLI linters |
| "No standard project files found" | Non-standard project structure | Configure custom linter or set up LSP |
| No errors shown | Code is clean OR linters not installed | Verify with manual command: `ruff check .` or `cargo check` |

## Notes
- **OVERRIDES upstream `Diagnostics` tool** from gptel-agent-tools.el
- **ALWAYS reports what was checked** (LSP, CLI linter, or search attempt)
- Automatically detects project type (Python, JS, Rust, etc.)
- Works even without LSP (falls back to CLI linters)
- Use after Code_Replace to verify changes are valid
- **DIFFERENT from upstream `Diagnostics`**: Scans entire project, not just open buffers
- **Reports backend**: User knows if results are from LSP or CLI linter
