λ(p,n,c). replace(n∈p) | p:file_path | n:node_name | c:new_code(balanced) | req:Lisp(.el|.clj|.cljs|.cljc)|Python|JS|Rust

# Code_Replace - Structural Function Replacement

## Purpose
Surgically replace an exact function or class by name with new code. GUARANTEES perfectly balanced parentheses/brackets.

## Availability
- `Code_Replace`: :core, :nucleus, :snippets

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

## Dependencies
- **Required**: tree-sitter parser for the file's language
- **Required**: File must exist and be readable
- **Optional**: Preview system (for diff display before applying)

## Failure Modes
| Symptom | Cause | Resolution |
|---------|-------|------------|
| "Could not find node named 'X'" | Symbol doesn't exist in file | Use Code_Map to see available symbols, check spelling |
| "AST Replacement rejected: syntax error" | new_code has unbalanced parens/brackets | Fix syntax in new_code, ensure all brackets close |
| "Error executing Code_Replace" | tree-sitter parser not installed | Run `M-x treesit-install-language-grammar RET <lang> RET` |
| Timeout after 5s | Very large file or slow disk | Ensure file is accessible, check disk performance |

## Setup Requirements
1. **Tree-sitter parsers** (auto-installed, or manual):
   ```elisp
   M-x treesit-install-language-grammar RET python RET
   M-x treesit-install-language-grammar RET elisp RET
   M-x treesit-install-language-grammar RET rust RET
   M-x treesit-install-language-grammar RET clojure RET
   ```

2. **Verify parser installation**:
   ```elisp
   M-x eval-expression RET (treesit-language-available-p 'python) RET
   ;; Should return: t
   ```

## Notes
- Uses tree-sitter AST for structural replacement
- Preserves surrounding code exactly
- Works for: Python, Elisp, Clojure (.clj/.cljs/.cljc), Rust, JavaScript
- For Elisp: Prefer this over standard Edit to avoid paren mismatches
- Syntax validation uses `treesit-node-check` for Emacs 30 compatibility
