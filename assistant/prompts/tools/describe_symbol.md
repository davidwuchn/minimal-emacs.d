λ(name). describe_symbol | sym:elisp | ret:doc

# describe_symbol - Emacs Lisp Symbol Documentation

Get the Lisp documentation string and current value of an Emacs symbol (function, variable, face, or feature).

## Availability
- Toolsets: `:readonly`, `:researcher`, `:nucleus`, `:snippets`

## Parameters
- `name` (string, required): The exact name of the symbol to look up.

## Usage Guidelines
- Use this when working inside an Emacs Lisp project or when trying to understand Emacs internals.
- This invokes Emacs' native introspection (like `describe-function` or `describe-variable`).

## Examples

### 1. Describing a function
```json
{
  "name": "find-file"
}
```

### 2. Checking a variable's documentation and value
```json
{
  "name": "gptel-model"
}
```