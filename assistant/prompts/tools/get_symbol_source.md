λ(name). get_symbol_source | id:name | ret:source-code

# get_symbol_source - Get Elisp Source Code

Get the actual Elisp source code definition of a function or variable.

## Availability
- Toolsets: `:readonly`, `:researcher`, `:nucleus`, `:snippets`

## Parameters
- `name` (string, required): The exact name of the symbol to look up.

## Usage Guidelines
- This uses Emacs' internal `find-function` logic to locate the exact file and line where a symbol is defined, and extracts the raw lisp form.
- Use this when documentation alone is not enough and you need to see the actual implementation.

## Examples

### 1. Reading the source code of a command
```json
{
  "name": "gptel-send"
}
```