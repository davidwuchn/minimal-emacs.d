λ(). check(LSP→lint) | ret:diagnostics | use:verify_changes | cascade:LSP→CLI(ruff|eslint|cargo)

# Code_Check - Project-wide Diagnostics

## Purpose
Get project-wide diagnostics/errors to verify your changes haven't broken the build.

## When to Use
- **AFTER** making code changes (before committing)
- When asked to "verify the changes" or "check for errors"
- Before running tests (catch syntax/type errors first)

## Usage
```
Code_Check{}
```

## Returns
Formated list of all diagnostics with file:line:type:message format.

## Examples
```
Code_Check{}
→ src/utils.py:42 [Error] Undefined variable 'undefined_var'
  src/main.py:15 [Warning] Unused import 'os'
  src/core.rs:28 [Error] Mismatched types: expected `i32`, found `String`
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

## Notes
- Automatically detects project type (Python, JS, Rust, etc.)
- Returns "No compiler or LSP diagnostics found" if code is clean
- Works even without LSP (falls back to CLI linters)
- Use after Code_Replace to verify changes are valid
