λ(path, old_str?, new_str_or_diff, diffp?). Edit | p:path | o:old_str(opt) | n:new_str_or_diff | d:diffp(opt) | ret:success/error

# Edit - Replace Text or Apply Diff

## Purpose
Replace text in a file or apply a unified diff patch. Async operation with confirmation.

## Availability
- `Edit`: :core, :nucleus, :snippets

## When to Use
- Simple text replacements in a single file
- Applying small diffs without full patch machinery
- Quick fixes and edits
- When you know exact text to replace

## Usage
```
# Simple text replacement
Edit{path: "src/utils.py", old_str: "def old():", new_str_or_diff: "def new():", diffp: false}

# Apply unified diff
Edit{path: "src/utils.py", new_str_or_diff: "--- a/src/utils.py\n+++ b/src/utils.py\n@@ -1,4 +1,4 @@\n-def old():\n+def new():", diffp: true}
```

## Parameters
- `path` (required): Path to file to edit
- `old-str` (optional): Exact text to find and replace (required if diffp=false)
- `new-str-or-diff` (required): New text OR unified diff content
- `diffp` (optional): If true, treat new-str-or-diff as unified diff (default: false)

## Returns
- Success message with file path
- Error message if edit failed (with reason)

## Examples
```
# Replace exact text
Edit{
  path: "src/utils.py",
  old_str: "def calculate_totals(data):\n    return sum(data)",
  new_str_or_diff: "def calculate_totals(data):\n    return sum(item.get('value', 0) for item in data)",
  diffp: false
}
→ Successfully edited src/utils.py

# Apply unified diff
Edit{
  path: "src/utils.py",
  new_str_or_diff: "--- a/src/utils.py\n+++ b/src/utils.py\n@@ -5,7 +5,7 @@\n-def old():\n+def new():",
  diffp: true
}
→ Successfully applied diff to src/utils.py
```

## ⚠️ Critical Requirements
1. **Exact match for old-str**: Whitespace, indentation must match exactly
2. **Unique context**: old-str should be unique enough to match only intended location
3. **Valid diff format**: If diffp=true, must be valid unified diff
4. **File must exist**: Cannot create new files (use `Write` for that)

## Failure Modes
| Symptom | Cause | Resolution |
|---------|-------|------------|
| "Text not found" | old-str doesn't match exactly | Re-read file, check whitespace/indentation |
| "Multiple matches" | old-str matches multiple locations | Add more context to old-str |
| "Invalid diff" | Malformed unified diff | Check diff format, use preview_patch first |
| "File does not exist" | Wrong path or file deleted | Verify path, use Write for new files |

## Edit vs ApplyPatch
| Feature | Edit | ApplyPatch |
|---------|------|------------|
| Scope | Single file | Multiple files |
| Format | Text or diff | Git unified diff only |
| Review | No preview | Use preview_patch first |
| Best for | Simple edits | Complex multi-file changes |

## Notes
- Async operation with timeout
- Uses confirmation overlay before applying
- Prefer `Code_Replace` for modifying functions in supported languages
- Use `Write` to create new files
- Use `Insert` to add text at specific line

## Related Tools
- `Code_Replace` - Structural function replacement (preferred for Lisp/Python/Rust)
- `ApplyPatch` - Apply multi-file git patches
- `Write` - Create new files
- `Insert` - Insert text at specific line
- `Read` - Read file before editing
