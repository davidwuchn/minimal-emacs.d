λ(file_path). map(AST) | file_path:path | ret:symbols(ordered) | use:understand_structure_first

## Availability
- `Code_Map`: :core, :readonly, :researcher, :nucleus, :snippets

## Purpose
Get a high-level overview of all functions, classes, and definitions in a file.
Use FIRST when opening unfamiliar files.

## Example
```
Code_Map{file_path: "src/utils.py"}
→ File map for src/utils.py:
  calculate_totals
  MyClass
  method_one
  process_data
```

## Supported Languages
Python, Elisp, Clojure (.clj/.cljs/.cljc), Rust, JavaScript, any tree-sitter language.
