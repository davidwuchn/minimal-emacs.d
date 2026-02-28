λ(p,l,c). hover | p:path | l:0-idx | c:0-idx | ret:type-info+docstring

# lsp_hover - Get Type Information at Point

## Purpose
Get type information, documentation, and signature at a specific cursor position.

## When to Use
- Need type info for a variable/expression at cursor
- Want to see function signature without extracting full implementation
- Quick documentation lookup during editing

## Usage
```
lsp_hover{path: "file.py", l: 10, c: 5}
```

## Returns
Type information and docstring for symbol at position.

## Example
```
lsp_hover{path: "src/utils.py", l: 10, c: 5}
→ def calculate_totals(data: List[Dict]) -> int
  """Calculate sum of values."""
```

## Notes
- Different from Code_Inspect (extracts full function body)
- Uses LSP hover provider
- Works at any cursor position (not just function names)
