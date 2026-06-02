λ(file_path, old_str?, new_str, diffp?). Edit | async

## Availability
- `Edit`: :core, :nucleus, :snippets

## Parameters
- `file_path` (string): Path to the file to edit
- `old_str` (string, optional): Text to replace or hashline tag
- `new_str` (string): Replacement text or unified diff
- `diffp` (boolean, optional): Set true when `new_str` is a diff

## Modes (preferred → fallback)

### 1. HASHLINE MODE (preferred — most reliable)
When file was read with hashline tags (`42:a3|content`), use the hash tag as `old_str`:
```
Edit(file_path="test.el", old_str="42:a3", new_str="replacement text")
```

**Advantages:**
- No need to reproduce exact text or whitespace
- Content-addressed: hash verifies the line hasn't changed
- Works across formatting differences

**Hashline formats:**
- Single line: `old_str="line-num:hash"` (e.g., `"42:a3"`)
- Range: `old_str="start-line:start-hash to end-line:end-hash"`
- Insert after: `old_str="+line-num:hash"`

### 2. STRING MODE (fallback)
When no hashline tags available, use exact text match:
```
Edit(file_path="test.el", old_str="exact old text", new_str="replacement")
```

**Warning:** Must reproduce every character exactly, including whitespace.

### 3. PATCH MODE (for bulk changes)
For multiple changes or complex diffs:
```
Edit(file_path="test.el", new_str="unified diff text", diffp=true)
```

## Decision Tree

```
IF file read with hashline tags:
  → Use hashline mode (pass hash tag as old_str)
ELIF change is simple single-line replacement:
  → Use string mode (pass exact old text)
ELSE:
  → Use patch mode (pass unified diff, diffp=true)
```

## Anti-Patterns

- ❌ Reproducing text when hashline tags are available
- ❌ Using patch mode for single-line changes
- ❌ Using string mode when formatting differs (whitespace, indentation)
