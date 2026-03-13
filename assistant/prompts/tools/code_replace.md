λ(file_path, node_name, new_code). replace(node_name∈file_path) | file_path:path | node_name:symbol | new_code:balanced | req:Lisp(.el|.clj|.cljs|.cljc)|Python|JS|Rust

## Availability
- `Code_Replace`: :core, :nucleus, :snippets

## Purpose
Structural replacement of a function or class. AST-guaranteed balanced code.

## Parameters
- `file_path` (required): Path to file containing the function
- `node_name` (required): Exact name of function/class to replace
- `new_code` (required): Complete replacement code (must be balanced)

## Example
```
Code_Replace{
  file_path: "src/utils.py",
  node_name: "calculate_totals",
  new_code: "def calculate_totals(data):\n    return sum(item['value'] for item in data)"
}
```

## Workflow
1. Run Code_Map to see available symbols
2. Run Code_Inspect to get exact current code
3. Run Code_Replace with complete new code

## Notes
- New code must be complete (not truncated)
- Checks for balanced parentheses/brackets
- Preview-backed confirmation in agent mode
