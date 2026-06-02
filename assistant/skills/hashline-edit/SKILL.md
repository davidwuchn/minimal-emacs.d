---
name: hashline-edit
description: >
  Content-addressed line editing using hashline tags.
  Use when editing files where exact text reproduction is unreliable.
  Hashlines provide stable anchors: "42:a3|content" → edit by referencing "42:a3".
version: 1.0.0
triggers: ["hashline", "content-addressed", "stable-edit"]
lambda: hashline.edit.content-addressed
metadata:
  evolution-stats:
    total-experiments: 0
---

# hashline-edit: Content-Addressed Line Editing

## When to Use

Use **hashline editing** when:
- Edit tool fails with "oldString not found" due to formatting differences
- File has complex whitespace/indentation that's hard to reproduce exactly
- You need to edit a file that might change between read and edit
- Working with files that have variable formatting (e.g., generated code)

**Prefer hashline over string mode** — it's more reliable.

## How It Works

### 1. Read with hashline=true

```
Read(file_path="src.el", hashline=true)
```

Returns:
```
1:a3|(defun hello ()
2:f1|  "world")
```

### 2. Edit by hash tag

```
Edit(file_path="src.el", old_str="2:f1", new_str="  \"universe\"")
```

**No need to reproduce exact text or whitespace!**

## Hashline Formats

### Single Line
```
Edit(file_path="file", old_str="42:a3", new_str="replacement")
```

### Range Replacement
```
Edit(file_path="file", old_str="2:f1 to 5:b2", new_str="new lines here")
```

### Insert After
```
Edit(file_path="file", old_str="+2:f1", new_str="inserted line")
```

## Decision Tree

```
IF file was read with hashline=true:
  → Use hashline mode (pass hash tag as old_str)
ELIF change is simple AND exact text is known:
  → Use string mode
ELIF multiple changes needed:
  → Use patch mode (diffp=true)
```

## Anti-Patterns

- ❌ Reproducing text when hashline tags are available
- ❌ Using string mode for files with complex formatting
- ❌ Not using hashline=true when planning to edit

## Examples

### Example 1: Simple Replacement

**Read:**
```
Read(file_path="config.json", hashline=true)
→ 10:a3|  "timeout": 30,
```

**Edit:**
```
Edit(file_path="config.json", old_str="10:a3", new_str='  "timeout": 60,')
```

### Example 2: Range Replacement

**Read:**
```
Read(file_path="main.py", hashline=true)
→ 42:a3|def old_function():
→ 43:f1|    pass
→ 44:0e|
```

**Edit:**
```
Edit(file_path="main.py", old_str="42:a3 to 44:0e",
     new_str="def new_function():\n    return True")
```

### Example 3: Insert After

**Read:**
```
Read(file_path="routes.py", hashline=true)
→ 15:a3|@app.route('/api/v1')
```

**Edit:**
```
Edit(file_path="routes.py", old_str="+15:a3",
     new_str="@app.route('/api/v2')")
```

## Safety

- **Optimistic locking**: Hash mismatch → edit rejected before corruption
- **Content addressing**: If file changed since read, hash won't match
- **No truncation**: Unlike string mode, no risk of partial matches

## Integration

```
Read(file_path="target.el", hashline=true)
→ Returns hashline-tagged content

Edit(file_path="target.el", old_str="42:a3", new_str="...")
→ Verifies hash before editing
→ Returns success or hash mismatch error
```
