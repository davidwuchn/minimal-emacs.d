λ(p,l,c,n). rename | p:path | l:0-idx | c:0-idx | n:new-name | ret:Δfiles

# lsp_rename - Cross-File Symbol Renaming

## Purpose
Rename a symbol across all files in the project using LSP's rename provider.

## ⚠️ When to Use
- Renaming a function/variable/class across the ENTIRE project
- Need to update all references, imports, and usages
- Safer than manual search/replace for cross-file changes

## Usage
```
lsp_rename{path: "file.py", l: 10, c: 5, n: "new_name"}
```

## Parameters
- `path`: File containing the symbol
- `l`: Line number (0-indexed)
- `c`: Column number (0-indexed)
- `n`: New name for the symbol

## Returns
List of files that were changed with the rename operation.

## Example
```
lsp_rename{path: "src/utils.py", l: 5, c: 4, n: "calculate_sum"}
→ Renamed 'calculate_totals' to 'calculate_sum' in 5 files:
  - src/utils.py
  - src/main.py
  - src/reports.py
  - tests/test_utils.py
  - tests/test_reports.py
```

## ⚠️ CRITICAL: When NOT to Use
- **NOT for modifying function implementation** → Use Code_Replace
- **NOT for single-file changes** → Use Edit or Code_Replace
- **ONLY for cross-file symbol renaming**

## Notes
- Requires LSP server with renameProvider capability
- Updates imports, references, and all usages
- Safer than regex-based rename
- Preview changes before applying (if preview enabled)
