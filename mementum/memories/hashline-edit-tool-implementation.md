---
title: Hashline Edit Tool Implementation
φ: 0.90
e: hashline-edit-tool-implementation
λ: when.agent.fails.to.edit
Δ: 0.25
evidence: 2
sources:
  - https://blog.can.ac/2026/02/12/the-harness-problem/
  - gptel-tools-edit-hashline.el
---

💡 Implemented hashline content-addressed editing for OV5 Edit tool.

## What Was Built

**New file:** `lisp/modules/gptel-tools-edit-hashline.el`

| Function | Purpose |
|----------|---------|
| `gptel-tools-edit-hashline--hash` | Compute 2-char MD5 hash of line content |
| `gptel-tools-edit-hashline-format-file` | Format file with hashline tags: `42:a3|content` |
| `gptel-tools-edit-hashline-replace` | Replace line by hash tag |
| `gptel-tools-edit-hashline-replace-range` | Replace range by start/end tags |
| `gptel-tools-edit-hashline-insert-after` | Insert after line by hash tag |
| `gptel-tools-edit-hashline--verify` | Check hash still matches before editing |

**Modified:** `lisp/modules/gptel-tools-edit.el`
- Added hashline detection in `old_str` parameter
- Three modes: hashline (detected), patch (`diffp`), string (fallback)
- Updated tool description to mention hashline support

## How It Works

1. **Agent reads file** → `gptel-tools-edit-hashline-format-file` returns:
   ```
   1:a3|function hello() {
   2:f1|  return "world";
   3:0e|}
   ```

2. **Agent edits** → References hash tag instead of reproducing text:
   ```
   Edit(file_path="test.el", old_str="2:f1", new_str="  return "universe";")
   ```

3. **Verify before apply** → Hash check detects if file changed since read:
   ```
   Hash mismatch for tag '2:f1'. File may have changed.
   ```

## Test Results

9/9 tests pass:
- Hash computation (deterministic, collision-resistant)
- File formatting with hashlines
- Tag parsing
- Hash verification (match/mismatch)
- Single line replacement
- Range replacement
- Insert after
- Optimistic locking (hash mismatch rejection)

## Integration with Existing Tools

| Scenario | Tool | Mode |
|----------|------|------|
| Code files with tree-sitter | Code_Replace | Node-based (existing, stays) |
| Text files / no parser | Edit | Hashline (new) |
| Patch available | Edit | Patch (existing) |
| Fallback | Edit | String exact match (existing) |

## Next Steps

1. **File read integration** — When agent reads a file, optionally return hashline format
2. **Agent prompt** — Instruct agent to use hashline tags when available
3. **Benchmark** — Compare hashline vs string replacement failure rates
4. **Edge cases** — Binary files, very long lines, unicode
