λ(file_path, start_line?, end_line?, hashline?). Read | p:path | s:?L(1-idx) | e:?L(1-idx) | req:grep-b4-large | ret:lines

## Parameters
- `file_path` (string): Path to the file
- `start_line` (int, optional): Start line (1-indexed)
- `end_line` (int, optional): End line (1-indexed)
- `hashline` (boolean, optional): When true, returns file with hashline tags for stable editing

## Hashline Mode

When `hashline=true`, each line is prefixed with a stable content hash:
```
1:a3|function hello() {
2:f1|  return "world";
3:0e|}
```

**Use this when you plan to edit the file.**

**Why:** The hash tag lets you edit without reproducing exact text:
```
Edit(file_path="test.el", old_str="2:f1", new_str="  return 'universe';")
```

**Advantages over plain text:**
- No need to reproduce whitespace or formatting
- Content-addressed: detects if file changed since read
- More reliable than exact string matching

## Default Behavior

When `hashline` is omitted, returns plain text (backward compatible).