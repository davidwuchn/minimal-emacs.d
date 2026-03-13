λ(). Diagnostics | ret:file:line:[type] msg

## Availability
- `Diagnostics`: :core, :readonly, :researcher, :nucleus, :snippets

## Purpose
Get project-wide diagnostics (errors, warnings). Use AFTER making changes to verify.

## Backend Priority
1. LSP (if active) - fastest, most accurate
2. CLI linters (fallback) - ruff for Python, eslint for JS, etc.

## Example
```
Diagnostics{}
→ src/utils.py:15: [error] undefined name 'foo'
  src/main.py:42: [warning] unused variable 'x'
```

## Notes
- Scans entire project (not just open buffers)
- Auto-detects project type
- Returns file:line:type format for easy parsing
