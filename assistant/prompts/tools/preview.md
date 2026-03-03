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
