λ(p,n,c). replace(n∈p) | p:file_path | n:node_name | c:new_code(balanced) | req:Lisp(.el|.clj|.cljs|.cljc)|Python|JS|Rust

# Code_Replace - Structural Function Replacement

## Purpose
Surgically replace an exact function or class by name with new code. GUARANTEES perfectly balanced parentheses/brackets.

## ⚠️ CRITICAL: When to Use
- **MUST use** for Lisp languages (.el, .clj, .cljs, .cljc, .edn)
- **MUST use** for Python, JavaScript, Rust when modifying existing functions
- **NEVER use** standard Edit for function modifications in these languages
- Use Code_Inspect first to see current implementation

## Usage
```
Code_Replace{file_path: "path/to/file.py", node_name: "function_name", new_code: "def function_name():\n    return 'new'"}
```

## Parameters
- `file_path` (required): Path to the file containing the function
- `node_name` (required): Exact name of function/class to replace
- `new_code` (required): Complete new implementation (must be syntactically valid!)

## Returns
Success message or error if node not found / syntax invalid.

## Examples
```
Code_Replace{
  file_path: "src/utils.py",
  node_name: "calculate_totals",
  new_code: "def calculate_totals(data):\n    return sum(item.get('value', 0) for item in data)"
}
→ Successfully replaced 'calculate_totals' in src/utils.py
```

## ⚠️ Safety Features
- **Syntax validation**: Rejects code with unbalanced parentheses/brackets
- **Preview**: Shows diff before applying (if preview enabled)
- **Atomic**: Either fully replaces or fully reverts (no partial edits)

## Notes
- Uses tree-sitter AST for structural replacement
- Preserves surrounding code exactly
- Works for: Python, Elisp, Clojure (.clj/.cljs/.cljc), Rust, JavaScript
- For Elisp: Prefer this over standard Edit to avoid paren mismatches
