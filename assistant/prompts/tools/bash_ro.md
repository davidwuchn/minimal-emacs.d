λ(command). bash_ro | cmd:readonly | ret:stdout/stderr | sandbox:whitelist

# BashRO - Read-Only Bash Commands

## Purpose
Execute read-only Bash commands in a sandboxed environment. Safer alternative to `Bash` for inspection tasks.

## When to Use
- Inspecting file system (ls, find, tree)
- Checking git status/diff/log
- Reading file contents (cat, head, tail)
- Searching text (grep, rg)
- Running tests (pytest, npm test, cargo test)
- System inspection (which, type, pwd)

## Usage
```
BashRO{command: "ls -la"}
```

## Parameters
- `command` (required): Read-only Bash command string

## Whitelisted Commands
- **File ops**: ls, pwd, tree, file, find, fd
- **Git**: git status, git diff, git log, git show, git branch, git grep, git rev-parse
- **Search**: grep, rg, cat, head, tail, wc
- **Text processing**: jq, awk, sort, uniq, cut, tr, xargs
- **Testing**: pytest, npm test, npm run test, cargo test, go test, make test, make check
- **Utilities**: which, type, echo, basename, dirname, realpath, readlink, test, [, true, false

## ⚠️ Forbidden Operations
- File redirection (`>`, `<`, `>>`)
- In-place editing (`sed -i`)
- Backgrounding (`&`)
- Any mutating commands

## Returns
Command stdout/stderr output.

## Examples
```
# Check git status
BashRO{command: "git status"}
→ On branch main
  Your branch is up to date with 'origin/main'.

# List files
BashRO{command: "ls -la"}
→ total 48
  drwxr-xr-x  7 user  staff   224  Feb 28 23:40 .

# Search for pattern
BashRO{command: "rg 'def main' src/"}
→ src/main.py:5:def main():

# Run tests
BashRO{command: "pytest tests/ -v"}
→ ================= test session starts =================
  tests/test_utils.py::test_helper PASSED
```

## Error Handling
| Symptom | Cause | Resolution |
|---------|-------|------------|
| "Command rejected by Sandbox" | Command not in whitelist | Use whitelisted command or ask user to say "go" for Execution mode |
| "ripgrep not found" | rg not installed | Install: `brew install ripgrep` or `apt install ripgrep` |

## Notes
- Sandboxed to read-only operations only
- For file mutations, use `Bash` tool or ask user to switch to Execution mode
- Prefer native tools (Read, Grep, Glob) over Bash for file operations when possible
