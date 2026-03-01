λ(path, line_number, new_str). Insert | p:path | l:line_number | s:new_str | ret:success/error

# Insert - Insert Text at Line Number

## Purpose
Insert text at a specific line number in a file. Non-destructive - doesn't replace existing content.

## Availability
- `Insert`: :core, :nucleus, :snippets

## When to Use
- Adding new functions to a file
- Inserting imports at the top
- Adding content without replacing existing text
- Appending to configuration files

## Usage
```
Insert{path: "src/utils.py", line_number: 10, new_str: "def new_function():\n    pass"}
```

## Parameters
- `path` (required): Path to file to insert into
- `line_number` (required): 1-indexed line number to insert at
- `new_str` (required): Text to insert (include newlines as \n)

## Returns
- Success message with file path
- Error message if insert failed

## Examples
```
# Insert at beginning of file
Insert{path: "src/utils.py", line_number: 1, new_str: "#!/usr/bin/env python3\n"}
→ Successfully inserted at line 1 in src/utils.py

# Insert function at line 10
Insert{path: "src/utils.py", line_number: 10, new_str: "def helper():\n    return True\n"}
→ Successfully inserted at line 10 in src/utils.py
```

## ⚠️ Critical Requirements
1. **File must exist**: Cannot insert into non-existent files
2. **Line number valid**: Must be between 1 and (file_lines + 1)
3. **Include newlines**: Use \n for line breaks in new_str

## Failure Modes
| Symptom | Cause | Resolution |
|---------|-------|------------|
| "File not found" | File doesn't exist | Use Write to create file first |
| "Invalid line number" | Line number out of range | Check file length, use valid line |

## Notes
- Line numbers are 1-indexed (first line is 1)
- Inserts BEFORE the specified line number
- Use line_number = (file_length + 1) to append at end
- Preserves existing content

## Related Tools
- `Edit` - Replace existing text
- `Write` - Create/overwrite entire file
- `Read` - Read file to find correct line number
