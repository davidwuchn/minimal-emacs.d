λ(cmd). bash | cmd:str | ret:stdout/stderr | use:git/tests/system | avoid:file-ops

# Bash - Execute Shell Commands

## Purpose
Execute Bash commands for git operations, running tests, package management, and system inspection.

## When to Use
- Git operations (commit, push, pull, rebase)
- Running tests and builds
- Package management (npm, pip, cargo)
- System inspection
- File operations NOT covered by native tools

## Usage
```
Bash{command: "git status"}
```

## ⚠️ CRITICAL: Prefer Native Tools
| Task | Use This Instead |
|------|-----------------|
| Read file | `Read` tool |
| Search text | `Grep` tool |
| Find files | `Glob` tool |
| Edit file | `Edit` tool |
| Create file | `Write` tool |

## Bash vs BashRO
| Tool | Purpose | Confirmation |
|------|---------|--------------|
| **Bash** | General commands (may mutate) | Required |
| **BashRO** | Read-only commands (sandboxed) | Required |

**See `bash_ro.md` for detailed BashRO documentation and whitelist.**

## Examples
```
# Git operations
Bash{command: "git commit -m 'Fix bug'"}
Bash{command: "git push origin main"}

# Run tests
Bash{command: "pytest tests/ -v"}
Bash{command: "npm test"}
Bash{command: "cargo test"}

# Package management
Bash{command: "pip install requests"}
Bash{command: "npm install lodash"}

# System inspection
Bash{command: "which python"}
Bash{command: "pwd"}
```

## Error Handling
| Symptom | Cause | Resolution |
|---------|-------|------------|
| "Command failed" | Command error | Check command syntax and dependencies |
| "Permission denied" | Insufficient permissions | Check file permissions or use sudo |
| "Command not found" | Missing dependency | Install required package/tool |

## Notes
- Use BashRO for read-only operations when possible
- Prefer native tools (Read, Grep, Glob, Edit, Write) for file operations
- Commands run in project root directory
- Output captured and returned to conversation
