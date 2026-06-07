# sandbox

## Purpose

Restricted evaluator for the Programmatic tool that orchestrates other tools
without exposing general Emacs Lisp evaluation. Supports a tiny subset of
expression forms (if, setq, when, unless, progn, let, let*, not, mapcar,
filter, dolist, and, or, quote) and data operations (comparison, arithmetic,
string, list) for serial tool orchestration. Enforces tool call limits (25 max),
timeout (15s), and result truncation (4000 chars). Supports readonly and agent
capability profiles, aggregate confirmation for multi-step mutating plans, and
profile loading from the `sandbox-profiles` skill.

## File Stats

- **Lines**: 1072
- **Path**: `lisp/modules/gptel-sandbox.el`

## Key Functions

| Function | Line | Purpose |
|----------|------|---------|
| `gptel-sandbox--parse-forms` | 170 | Parse code string into list of Lisp forms |
| `gptel-sandbox--eval-expr` | 441 | Evaluate pure sandbox expression (whitelist only) |
| `gptel-sandbox--eval-statement` | 935 | Evaluate statement (setq, tool-call, result, progn) |
| `gptel-sandbox--execute-tool` | 864 | Execute tool call within sandbox with confirmation |
| `gptel-sandbox--run-forms` | 1011 | Run sandbox forms sequentially with async support |
| `gptel-sandbox-execute-async` | 1037 | Public API: execute restricted code with timeout |
| `gptel-sandbox--current-profile` | 609 | Return active capability profile (agent or readonly) |
| `gptel-sandbox--allowed-tool-p` | 592 | Check if tool is allowed in current profile |
| `gptel-sandbox--collect-confirming-plan` | 669 | Collect static summaries for confirming tool calls |

## Supported Expressions

- **Control flow**: `if`, `when`, `unless`, `progn`, `and`, `or`
- **Binding**: `setq`, `let`, `let*`
- **Iteration**: `dolist`, `mapcar`, `filter`
- **Logic**: `not`, `quote`, comparison operators
- **Data**: `concat`, `format`, `list`, `append`, `length`, `car`, `cdr`, `nth`, `cons`, `assoc`, `alist-get`, `plist-get`, `split-string`, `string-join`, `string-trim`, `string-match-p`, `substring`, `memq`
- **Tool orchestration**: `tool-call`, `result`

## Dependencies

- `cl-lib`, `pp`, `seq`, `subr-x`
- `gptel` (optional), `nucleus-tools`

## Integration Points

- **Programmatic tool**: `gptel-sandbox-execute-async` is the entry point for the Programmatic tool
- **nucleus-tools**: Uses `nucleus-tool-markers` for tool classification and profile derivation
- **Sandbox profiles**: Loads tool allowlists from `sandbox-profiles` skill
- **Confirmation flow**: Aggregate preview for multi-step mutating plans before execution
- **Tool safety**: `gptel-sandbox--excluded-tools` excludes delegates, sandbox-external, and Programmatic itself

## See Also

- [nucleus tools](nucleus-tools.md)
- [ext security](gptel-ext-security.md)