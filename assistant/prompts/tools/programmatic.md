λ(code). Programmatic | async | ret:text | req:restricted-elisp

## Availability
- `Programmatic`: :readonly, :researcher, :nucleus, :snippets

## Parameters
- `code` (string): Restricted Emacs Lisp program. Tool-call syntax is `(tool-call "ToolName" :arg value ...)`. Must end with `(result <expr>)`.

## Sandbox
- Profiles:
  - `gptel-plan` / `:readonly`: readonly nested tools only
  - `gptel-agent` / `:nucleus`: readonly + preview-backed mutating tools
- Supported forms:
  - `setq`, `result`, top-level `tool-call`
  - `if`, `when`, `unless`, `not`, `and`, `or`, `progn`
  - `let`, `let*`, `mapcar`, `filter`
  - comparisons: `equal`, `string=`, `=`, `<`, `>`, `<=`, `>=`
  - data/string helpers: `concat`, `format`, `list`, `vector`, `append`, `length`, `car`, `cdr`, `nth`, `cons`, `assoc`, `alist-get`, `plist-get`, `split-string`, `string-join`, `string-trim`, `string-empty-p`, `string-match-p`, `substring`
- Unsupported:
  - arbitrary function calls / `eval`
  - open-ended loops like `while`
  - nested `tool-call` in arbitrary expressions

## Mutating runs
- Agent mode allows preview-backed mutating tools: `Edit`, `ApplyPatch`, `Code_Replace`
- Multi-step mutating runs get one aggregate preview/approval summary before per-tool confirmations

## Limits
- Timeout: 15 seconds (`my/gptel-programmatic-timeout`)
- Max tool calls: 25 (`my/gptel-programmatic-max-tool-calls`)
- Result limit: 4000 chars (`my/gptel-programmatic-result-limit`)

## Error recovery
Use `condition-case` to handle tool failures gracefully:
```elisp
(condition-case err
    (tool-call "Edit" :file_path "file.el" :new_str "content")
  (error (result (format "Edit failed: %s" err))))
```
