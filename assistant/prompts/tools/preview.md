λ(path, original?, replacement). preview_file_change | diff:magit | req:review-changes | ret:callback-result
λ(patch). preview_patch | diff:unified | req:review-changes | ret:callback-result

# Preview Tools - Legacy Interative Review

Use these tools to show the user interactive previews of code changes using Emacs' native diff/magit buffers.

## Availability
- `preview_file_change`: :nucleus, :snippets

## 1. preview_file_change
Preview a file replacement step-by-step.
- `path` (string, required): Target file path
- `original` (string, optional): Original content
- `replacement` (string, required): Replacement content

## 2. preview_patch
Preview a standard unified diff patch without applying it.
- `patch` (string, required): Unified diff content