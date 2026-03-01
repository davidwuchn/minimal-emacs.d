λ(command). Bash | cmd:str | ret:stdout/stderr | sandbox:plan-mode

# Bash - Execute Shell Commands

Use this tool to execute Bash commands for git operations, running tests, package management, and system inspection.

## Availability
- `Bash`: :core, :readonly, :researcher, :nucleus, :snippets

## Usage Mode & Sandbox
The behavior of this tool automatically adapts based on your current agent mode:
- **Execution Mode (Default)**: Full unrestricted shell access.
- **Plan Mode (Read-Only)**: Automatically sandboxed. The tool will strictly block any mutating commands or file redirections. Only read-only introspection and testing commands are permitted. 

## ⚠️ CRITICAL: Prefer Native Tools First
| Task | Use This Instead |
|------|-----------------|
| Read file | `Read` tool |
| Search text | `Grep` tool |
| Find files | `Glob` tool |
| Edit file | `Edit` tool |
| Create file | `Write` tool |

## Sandboxed Allowed Commands (Plan Mode)
When in Plan Mode, only the following operations are permitted:
- **File ops**: ls, pwd, tree, file, find, fd, which, type
- **Git**: git status, git diff, git log, git show, git branch, git grep, git rev-parse, git describe, git remote, git tag
- **Search**: grep, rg, cat, head, tail, wc
- **Text processing**: jq, awk, sort, uniq, cut, tr, xargs
- **Testing & Exec**: pytest, npm test, npm run test, cargo test, go test, make test, make check, make, cargo, npm, pip, python, node
- **Utilities**: echo, basename, dirname, realpath, readlink, test, [, true, false

If you attempt a forbidden operation (like `rm`, `sed -i`, command substitution `$(...)`, or file redirection `>`) while in Plan Mode, the Sandbox will reject the command and return an error.

## Examples
```
# Git operations
Bash{command: "git status"}
Bash{command: "git commit -m 'Fix bug'"}

# Run tests
Bash{command: "pytest tests/ -v"}
Bash{command: "cargo check"}

# Package management
Bash{command: "npm install lodash"}

# System inspection
Bash{command: "which python"}
```