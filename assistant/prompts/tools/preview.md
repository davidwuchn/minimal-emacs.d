λ(path, original?, replacement). preview_file_change | diff:magit
λ(patch). preview_patch | diff:unified
λ(path, original, replacement). preview_inline | diff:inline
λ(files). preview_batch | diff:batch
λ(path, content). preview_syntax | read:syntax

## Availability
- `preview_file_change`: :nucleus, :snippets
- `preview_patch`: :nucleus, :snippets
- `preview_inline`: :nucleus, :snippets
- `preview_batch`: :nucleus, :snippets
- `preview_syntax`: :nucleus, :snippets

## Parameters
- `path` (string): File path
- `original` (string, optional): Original content
- `replacement` (string): New content
- `patch` (string): Unified diff content
- `files` (array): File change objects [{path, original, replacement}]
- `content` (string): Code snippet content
