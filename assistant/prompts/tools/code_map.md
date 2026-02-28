λ(p). map(AST) | p:file_path | ret:symbols(ordered) | use:understand_structure_first

# Code_Map - File Structure/Outline Tool

## Purpose
Get a high-level overview of all functions, classes, and definitions in a file before editing.

## When to Use
- **FIRST** tool when opening an unfamiliar file
- Before making any edits to understand file organization
- To find the exact name of a function/class before using Code_Inspect or Code_Replace

## Usage
```
Code_Map{file_path: "path/to/file.py"}
```

## Returns
Ordered list of all defined symbols (functions, classes, methods) in the file.

## Examples
```
Code_Map{file_path: "src/utils.py"}
→ File map for src/utils.py:
  calculate_totals
  MyClass
  method_one
  process_data
```

## Dependencies
- **Required**: tree-sitter parser for the file's language
- **Optional**: None (file-local operation, no LSP needed)

## Failure Modes
| Symptom | Cause | Resolution |
|---------|-------|------------|
| "Could not generate file map" | tree-sitter parser not installed | Run `M-x treesit-install-language-grammar RET <lang> RET` |
| "Is tree-sitter enabled?" | File not using tree-sitter mode | Ensure `global-treesit-auto-mode` is enabled |
| Empty list | File has no definitions | File may only contain imports/exports |

## Setup Requirements
Parsers are **auto-installed** when you open a file. Manual installation:
```elisp
M-x treesit-install-language-grammar RET python RET
M-x treesit-install-language-grammar RET elisp RET
M-x treesit-install-language-grammar RET rust RET
M-x treesit-install-language-grammar RET clojure RET
```

## Notes
- Works for: Python, Elisp, Clojure, Rust, JS (any tree-sitter supported language)
- Fast, file-local operation (no project-wide search)
- Use output to get exact symbol names for Code_Inspect/Code_Replace
