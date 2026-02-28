λ(s,d). Move | s:source | d:dest | ret:success/error

# Move - Move or Rename Files/Directories

## Purpose
Move files or directories from source to destination. Can also rename within same directory.

## When to Use
- Renaming files
- Moving files between directories
- Reorganizing project structure
- Moving files to archive

## Usage
```
Move{source: "/path/to/old_name.py", dest: "/path/to/new_name.py"}
```

## Parameters
- `source` (required): Source file or directory path
- `dest` (required): Destination path (new location or new name)

## Returns
- Success message with moved path
- Error message if move failed

## Examples
```
# Rename file
Move{source: "src/old_name.py", dest: "src/new_name.py"}
→ Successfully moved src/old_name.py to src/new_name.py

# Move to different directory
Move{source: "src/file.py", dest: "lib/file.py"}
→ Successfully moved src/file.py to lib/file.py

# Move and rename
Move{source: "src/old.py", dest: "lib/new.py"}
→ Successfully moved src/old.py to lib/new.py
```

## ⚠️ Critical Requirements
1. **Source must exist**: Cannot move non-existent files
2. **Dest parent must exist**: Parent directory of dest must exist
3. **Permissions**: Must have read/write permissions

## Failure Modes
| Symptom | Cause | Resolution |
|---------|-------|------------|
| "Source not found" | Source file doesn't exist | Check path, file may be deleted |
| "Destination exists" | Dest already exists | Remove dest first or use different name |
| "Permission denied" | No permissions | Check file permissions |

## Notes
- Overwrites destination if it exists (use with caution)
- Works for both files and directories
- Atomic operation (either succeeds or fails completely)

## Related Tools
- `Write` - Create new files
- `Read` - Verify file before moving
- `Mkdir` - Create destination directory first
