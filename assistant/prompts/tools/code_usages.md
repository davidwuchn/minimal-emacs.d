λ(n). find_usages(n) | n:symbol | ret:locations(file:line:context) | cascade:LSP→rg

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
List of all locations where the symbol is referenced, with file:line:context.

## Examples
```
Code_Usages{node_name: "calculate_totals"}
→ Found 5 usages of 'calculate_totals':

  src/utils.py:10: def calculate_totals(data):
  src/main.py:25: result = calculate_totals(items)
  src/main.py:42: return calculate_totals(filtered)
  src/reports.py:15: from utils import calculate_totals
  src/reports.py:78: total = calculate_totals(data)
```

## ⚠️ Smart Fallback Chain
1. **LSP References** (if eglot server is running)
   - Semantic understanding of references
   - Distinguishes definition from usages
   - Handles imports, aliases, method calls

2. **Ripgrep Search** (if no LSP or LSP finds nothing)
   - Fast text-based search across project
   - Excludes .pyc, .elc, __pycache__, etc.
   - Returns raw matching lines

## Notes
- Works for all languages (Python, Elisp, Clojure, Rust, JS, etc.)
- LSP provides semantic accuracy, grep provides speed
- Use before renaming to ensure you update all call sites
- Output includes definition location + all usage locations
