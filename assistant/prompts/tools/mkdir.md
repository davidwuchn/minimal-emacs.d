λ(parent, name). Mkdir | p:parent | n:name | ret:success/error

# Mkdir - Create Directory

## Purpose
Create a new directory under a parent directory. Creates parent directories if needed.

## Availability
- `Mkdir`: :core, :nucleus, :snippets

## When to Use
- Creating project structure
- Making new package directories
- Setting up folder hierarchy
- Creating test directories

## Usage
```
Mkdir{parent: "/path/to/parent", name: "new_directory"}
```

## Parameters
- `parent` (required): Parent directory path
- `name` (required): Name of new directory to create

## Returns
- Success message with created path
- Error message if creation failed

## Examples
```
# Create simple directory
Mkdir{parent: "/home/user/projects", name: "my_project"}
→ Successfully created /home/user/projects/my_project

# Create nested directory
Mkdir{parent: "/home/user", name: "projects/src/utils"}
→ Successfully created /home/user/projects/src/utils (with parents)
```

## ⚠️ Critical Requirements
1. **Parent must exist**: Parent directory must be accessible
2. **Name not empty**: Directory name cannot be empty
3. **Permissions**: Must have write permission in parent

## Failure Modes
| Symptom | Cause | Resolution |
|---------|-------|------------|
| "Parent not found" | Parent directory doesn't exist | Create parent first or use full path |
| "Permission denied" | No write permission | Check permissions or use different location |
| "Already exists" | Directory already exists | Use different name or remove existing |

## Notes
- Creates parent directories automatically (like mkdir -p)
- Uses forward slashes (/) for path separators
- Works on all platforms (Unix, macOS, Windows)

## Related Tools
- `Write` - Create files in new directory
- `Move` - Move files to new directory
