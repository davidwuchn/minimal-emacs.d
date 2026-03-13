λ(path?, original?, replacement?, patch?). Preview | diff:unified

## Availability
- `Preview`: :nucleus, :snippets

## Modes
1. **File change**: provide `path` + `replacement` (optional `original`, auto-read from file)
2. **Patch**: provide `patch` (raw unified diff)

## Parameters
- `path` (string, optional): Target file path (file change mode)
- `original` (string, optional): Original content (auto-read from file if omitted)
- `replacement` (string, optional): Replacement content (file change mode)
- `patch` (string, optional): Unified diff content (patch mode)

## Confirmation

Preview shows diff in a buffer, then prompts in minibuffer:

| Key | Action |
|-----|--------|
| `y` | Yes, apply this change |
| `n` | No, abort this change |
| `!` | Permit tool for session, then apply (use `my/gptel-clear-permits` to reset) |
| `q` | Quit (same as n) |

## Configuration

- `gptel-tools-preview-enabled` (default `t`): Set to `nil` to auto-apply without preview
- `my/gptel-edit-auto-preview` (default `t`): Preview toggle for Edit tool patch mode
- `my/gptel-applypatch-auto-preview` (default `t`): Preview toggle for ApplyPatch tool
- `M-x my/gptel-clear-permits`: Clear all permitted tools
- `M-x my/gptel-show-permits`: Show currently permitted tools
