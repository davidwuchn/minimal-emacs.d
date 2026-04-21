λ(file_path, old_str?, new_str, diffp?). Edit | async

## Availability
- `Edit`: :core, :nucleus, :snippets

## Parameters
- `file_path` (string): Path to the file to edit
- `old_str` (string, optional): Text to replace
- `new_str` (string): Replacement text or unified diff
- `diffp` (boolean, optional): Set true when `new_str` is a diff
