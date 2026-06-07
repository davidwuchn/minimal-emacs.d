# ext security

## Purpose

Tool security and routing via ACL-based access control. Enforces a hybrid
sandbox that checks every tool call against workspace boundaries and plan-mode
restrictions. In plan mode, restricts Bash to a whitelist of read-only commands
and forbids destructive Lisp functions in Eval. For all tools carrying
`:file-inspector` or `:can-edit` markers, forces user confirmation when the
target path is outside the project workspace. Uses advice at depth 10 on
`gptel-make-tool` to wrap all tool execution with ACL checks.

## File Stats

- **Lines**: 106
- **Path**: `lisp/modules/gptel-ext-security.el`

## Key Functions

| Function | Line | Purpose |
|----------|------|---------|
| `my/is-inside-workspace` | 12 | Check if path is strictly inside project root |
| `my/gptel-tool-get-target-path` | 18 | Extract target file path from tool call args |
| `my/gptel-tool-acl-check` | 38 | Return error if tool call violates ACL rules |
| `my/gptel-tool-acl-needs-confirm` | 61 | Return t if tool call should force confirmation |
| `my/gptel-tool-router-advice` | 71 | Intercept `gptel-make-tool` to wrap with ACL router |

## ACL Rules

1. **Plan Mode Bash Whitelist**: Only allows `ls`, `pwd`, `tree`, `file`, `git status/diff/log/show/branch`, and test runners. Shell chaining (`;`, `|`, `&`, `>`, `<`) is forbidden.
2. **Plan Mode Eval Sandbox**: Blocks destructive functions (`shell-command`, `call-process`, `delete-file`, `delete-directory`, `write-region`, `kill-emacs`, network operations).
3. **Workspace Boundary**: Tools with `:file-inspector` or `:can-edit` markers force confirmation for paths outside the project root.

## Dependencies

- `subr-x`, `project`, `gptel`, `nucleus-tools`

## Integration Points

- **Tool creation**: Advice on `gptel-make-tool` at depth 10 (outermost, checked first)
- **nucleus-tools**: Uses `nucleus-tool-has-marker-p` for marker checks
- **Workspace enforcement**: `my/is-inside-workspace` used by sandbox and other modules

## See Also

- [nucleus tools](nucleus-tools.md)
- [sandbox](gptel-sandbox.md)