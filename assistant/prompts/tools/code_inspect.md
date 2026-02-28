λ(p,n). extract(n∈p) | p:file_path(opt) | n:node_name | ret:AST_block(balanced) | req:structural_edit

# Code_Inspect - Extract Function/Class by Name

## Purpose
Extract the exact, perfectly balanced implementation block of a function or class by name.

## When to Use
- Need to read the full implementation of a specific function
- Before modifying a function (use Code_Inspect first, then Code_Replace)
- Finding definitions across the project (omit file_path to auto-search)

## Usage
```
Code_Inspect{node_name: "function_name", file_path?: "optional/path.py"}
```

## Parameters
- `node_name` (required): Exact name of function/class to extract
- `file_path` (optional): Path to file. If omitted, searches entire project!

## Returns
Complete, perfectly balanced code block with correct indentation/parentheses.

## Examples
```
# With file path
Code_Inspect{node_name: "calculate_totals", file_path: "src/utils.py"}
→ Code block 'calculate_totals' from src/utils.py:
  
  def calculate_totals(data):
      total = 0
      for item in data:
          total += item['value']
      return total

# Without file path (auto-searches project)
Code_Inspect{node_name: "helper_function"}
→ Found in src/helpers.py:
  
  def helper_function(x, y):
      return x + y
```

## Notes
- Uses tree-sitter AST for perfect extraction
- Guarantees balanced parentheses/brackets
- Auto-searches workspace if file_path omitted (uses AST_Find_Workspace)
- Works for: Python, Elisp, Clojure (.clj/.cljs/.cljc), Rust, JS
