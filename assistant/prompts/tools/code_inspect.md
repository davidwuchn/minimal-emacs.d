λ(node_name, file_path?). extract(n∈p) | p:file_path(opt) | n:node_name | ret:AST_block(balanced) | req:structural_edit

## Availability
- `Code_Inspect`: :core, :readonly, :researcher, :nucleus, :snippets

## Purpose
Extract the exact, perfectly balanced implementation block of a function or class by name.

## Parameters
- `node_name` (required): Exact name of function/class to extract
- `file_path` (optional): Path to file. If omitted, searches entire project.

## Example
```
Code_Inspect{node_name: "calculate_totals", file_path: "src/utils.py"}
→ Code block 'calculate_totals' from src/utils.py:
  
  def calculate_totals(data):
      total = 0
      for item in data:
          total += item['value']
      return total
```

## Notes
- Uses tree-sitter AST for perfect extraction
- Guarantees balanced parentheses/brackets
- Auto-searches workspace if file_path omitted
