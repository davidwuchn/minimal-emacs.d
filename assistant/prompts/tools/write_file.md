λ(path, filename, content). Write | p:parent | f:filename | c:content | req:new-file | ret:success/error

# Write - Create New File

## Purpose
Create a new file with specified content. Will NOT overwrite existing files (safety feature).

## When to Use
- Creating new source files
- Writing configuration files
- Generating output files
- Creating documentation

## Usage
```
Write{parent: "/path/to/dir", filename: "new_file.py", content: "def main():\n    pass\n"}
```

## Parameters
- `parent` (required): Parent directory path
- `filename` (required): Name of file to create
- `content` (required): File content (use \n for newlines)

## Returns
- Success message with file path
- Error message if write failed

## Examples
```
# Create Python file
Write{
  parent: "src",
  filename: "utils.py",
  content: "def helper():\n    return True\n"
}
→ Successfully created src/utils.py

# Create config file
Write{
  parent: ".",
  filename: "config.json",
  content: "{\n  \"debug\": true\n}\n"
}
→ Successfully created config.json
```

## ⚠️ Critical Requirements
1. **File must NOT exist**: Write refuses to overwrite (safety!)
2. **Parent must exist**: Parent directory must exist
3. **Filename not empty**: Must provide valid filename

## Failure Modes
| Symptom | Cause | Resolution |
|---------|-------|------------|
| "File exists" | File already exists | Use Edit to modify, or remove first |
| "Parent not found" | Parent directory missing | Create parent with Mkdir first |
| "Permission denied" | No write permission | Check permissions or use different location |

## Write vs Edit
| Feature | Write | Edit |
|---------|-------|------|
| Existing files | ❌ Refuses | ✅ Modifies |
| New files | ✅ Creates | ❌ Cannot |
| Use case | New files only | Modify existing |

## Notes
- Safety feature: won't accidentally overwrite work
- Creates file with specified content exactly
- Use \n for line breaks in content
- Use Edit tool to modify existing files

## Related Tools
- `Edit` - Modify existing files
- `Mkdir` - Create parent directory first
- `Read` - Verify file doesn't exist before writing
- `Insert` - Add content to existing files
