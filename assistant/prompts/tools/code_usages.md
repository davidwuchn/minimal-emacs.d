λ(n). find_usages(n) | ret:file:line:context + backend(LSP|ripgrep) | cascade:LSP→rg

# Code_Usages - Find Symbol References

## Purpose
Find all usages/references of a symbol (function, class, variable) across the entire project.

## When to Use
- Before renaming a function (find all call sites)
- Understanding how a function is used across the codebase
- Impact analysis before making breaking changes

## Usage
```
Code_Usages{node_name: "function_name"}
```

## Parameters
- `node_name` (required): Symbol/function/class name to find usages for

## Returns
List of all locations where the symbol is referenced, with `file:line:context`.

**IMPORTANT**: Output includes which backend was used:
- `Found X usages of 'symbol' (via LSP):` - Semantic, understands imports/aliases
- `Found X usages of 'symbol' (via ripgrep):` - Text-based search, may have false positives

## Examples
```
# LSP backend (semantic understanding)
Code_Usages{node_name: "calculate_totals"}
→ Found 5 usages of 'calculate_totals' (via LSP):

  src/utils.py:10: def calculate_totals(data):
  src/main.py:25: result = calculate_totals(items)
  src/main.py:42: return calculate_totals(filtered)
  src/reports.py:15: from utils import calculate_totals
  src/reports.py:78: total = calculate_totals(data)

# Ripgrep backend (text search fallback)
Code_Usages{node_name: "helper_function"}
→ Found 3 usages of 'helper_function' (via ripgrep):

  src/helpers.py:5:def helper_function(x, y):
  src/main.py:10:from helpers import helper_function
  src/main.py:25:result = helper_function(1, 2)
```

## ⚠️ Smart Fallback Chain
1. **LSP References** (if eglot server is running)
   - Semantic understanding of references
   - Distinguishes definition from usages
   - Handles imports, aliases, method calls
   - **Output**: `(via LSP)`

2. **Ripgrep Search** (if no LSP or LSP finds nothing)
   - Fast text-based search across project
   - Excludes .pyc, .elc, __pycache__, etc.
   - Returns raw matching lines
   - **Output**: `(via ripgrep)`

## Dependencies
- **Required**: None (works without LSP)
- **Optional**: LSP server for semantic accuracy
- **Optional**: Ripgrep for text-based fallback

## Failure Modes
| Symptom | Cause | Resolution |
|---------|-------|------------|
| "No usages found" | Symbol doesn't exist | Check spelling, use Code_Map to explore files |
| "(via ripgrep)" with many results | LSP unavailable, text search | Install LSP server for better accuracy |
| "ripgrep not found" | rg not in PATH | `brew install ripgrep` or `apt install ripgrep` |
| Timeout after 10s | Large project, slow LSP | Provide file_path to Code_Inspect instead |

## Notes
- Output **always indicates** which backend was used (LSP or ripgrep)
- LSP provides semantic accuracy (understands imports/aliases)
- Ripgrep provides speed and works without LSP
- Works for all languages (Python, Elisp, Clojure, Rust, JS, etc.)
- Use before renaming to ensure you update all call sites
