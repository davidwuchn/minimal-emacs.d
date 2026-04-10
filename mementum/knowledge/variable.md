---
title: Variable Handling in Shell Scripts, Cron, and Emacs Lisp
status: active
category: knowledge
tags: [variables, shell, emacs-lisp, cron, portability, paths, best-practices]
---

# Variable Handling in Shell Scripts, Cron, and Emacs Lisp

This knowledge page covers essential patterns and pitfalls when working with variables in shell scripts, cron jobs, and Emacs Lisp. Understanding variable scope, expansion rules, and portable path handling is critical for reliable automation.

---

## 1. Variable Expansion in Cron Jobs

### The Problem

Cron jobs may run but produce empty log files when custom variables are used incorrectly. The shell receiving the command doesn't inherit variables set within the crontab itself.

### Root Cause

In crontab, setting a variable only affects cron's environment, not the shell executing the command:

```
# WRONG - Variable set in crontab but not passed to shell
LOGDIR=$HOME/.emacs.d/var/tmp/cron
0 * * * * some-command >> $LOGDIR/auto-workflow.log 2>&1
```

When cron executes the command, `$LOGDIR` expands to an empty string because the shell spawned by cron doesn't have `LOGDIR` in its environment.

### The Fix

Use environment variables directly or expand the full path inline:

```
# CORRECT - Use $HOME directly in the command
0 * * * * some-command >> $HOME/.emacs.d/var/tmp/cron/auto-workflow.log 2>&1
```

Alternatively, export variables in a shell wrapper:

```
SHELL=/bin/bash
0 * * * * export LOGDIR=$HOME/.emacs.d/var/tmp/cron; some-command >> $LOGDIR/auto-workflow.log 2>&1
```

### Detection Commands

View cron job execution with expanded variables:

```bash
# Check today's cron logs
journalctl -u cron --since "today" | grep -E "your-username|CMD"

# On macOS
log show --predicate 'process == "cron"' --last 24h
```

### Comparison Table

| Approach | Works? | Portability | Notes |
|----------|--------|-------------|-------|
| `VAR=value` in crontab | ❌ | Poor | Variable not passed to shell |
| `$VAR` inline | ✅ | Good | Use built-in variables like `$HOME` |
| `export VAR=value` in crontab | ❌ | Poor | Still not inherited by shell |
| `VAR=value` in script | ✅ | Good | Script handles its own variables |
| `env VAR=value command` in crontab | ✅ | Good | Explicit environment passing |

---

## 2. Emacs Lisp Variable Declarations with defvar

### The Pattern for External Variables

When a variable is defined in one file but referenced in another, use `defvar` without a docstring to avoid duplicate definitions and compiler warnings.

### Correct Usage

```elisp
;; In gptel-tools-agent.el (primary definition)
(defvar gptel-auto-workflow--worktree-state nil
  "Hash table for worktree state.")

;; In gptel-auto-workflow.el (consumer file)
;; Forward declaration - no docstring, no initial value
(defvar gptel-auto-workflow--worktree-state)
```

### Incorrect Usage (Don't Do This)

```elisp
;; WRONG - Duplicates docstring and resets the variable
(defvar gptel-auto-workflow--worktree-state nil
  "Hash table for worktree state. Defined in gptel-tools-agent.el.")
```

This resets the variable to `nil` every time the file loads, losing any state set by the primary definition.

### Why This Works

- **Without docstring**: The compiler knows the variable exists but doesn't emit a "definition shadows existing variable" warning
- **Without value**: No initial value is set, preserving whatever the primary definition established
- **Forward declaration**: Enables cross-file references without loading order issues

### Lexical Binding Consideration

When using `lexical-binding: t`, special (dynamic) variables require explicit `defvar` for `let` bindings to affect the global value:

```elisp
;; With lexical-binding: t
(defvar my-special-var nil)

(defun example-function ()
  (let (my-special-var)  ; Without defvar, this creates a lexical binding!
    (setq my-special-var "local")
    (call-other-function)))
```

Without the `defvar` declaration, the `let` binding creates a new lexical variable that doesn't affect the global/dynamic one.

---

## 3. Portable Path Patterns

### The Golden Rule

Always use environment variables or dynamic commands for paths instead of hardcoded user directories.

### Recommended Patterns

```bash
# ✅ GOOD - Uses environment variable
LOGDIR=$HOME/.emacs.d/var/tmp/cron

# ✅ GOOD - Uses git to find project root
PROJECT_ROOT=$(git rev-parse --show-toplevel)

# ✅ GOOD - Usespwd as fallback
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ❌ BAD - Hardcoded username
LOGDIR=/Users/davidwu/.emacs.d/var/tmp/cron

# ❌ BAD - Hardcoded path on wrong OS
CONFIG=/Users/davidwu/.config/emacs
```

### Common Environment Variables

| Variable | Typical Value (Linux) | Typical Value (macOS) | Use Case |
|----------|----------------------|----------------------|----------|
| `$HOME` | `/home/username` | `/Users/username` | User home directory |
| `$USER` | `username` | `username` | Current user |
| `$PWD` | current directory | current directory | Working directory |
| `$PATH` | system PATH | system PATH | Executable search path |
| `$XDG_CONFIG_HOME` | `$HOME/.config` | not set by default | XDG config directory |

### Systemd Service Management (Linux)

On Debian Linux with systemd user services:

```bash
# Check service status
systemctl --user status emacs

# Restart daemon (NOT pkill)
systemctl --user restart emacs

# View logs
journalctl --user -u emacs

# NEVER do this - leaves stale socket files
pkill -f "emacs --daemon"
```

### Detection Commands

Find hardcoded paths in your codebase:

```bash
# Search for hardcoded user paths
grep -rn "/Users/davidwu" . --include="*.sh" --include="*.el" --include="*.md"

# Search for hardcoded home-like paths
grep -rn "~/" . --include="*.sh"

# Find all potential path issues
find . -type f \( -name "*.sh" -o -name "*.el" \) -exec grep -l "/home/" {} \;
```

---

## 4. Cross-Platform Considerations

### Path Separator

| Platform | Separator | Example |
|----------|------------|---------|
| Linux/macOS | `/` | `/home/user/file` |
| Windows | `\` | `C:\Users\user\file` |

In Emacs Lisp, use `expand-file-name` which handles separators:

```elisp
(expand-file-name "subdir" "~/")  ; Works on all platforms
```

### Environment Variable Availability

```bash
# Check if variable exists
echo ${HOME:?Variable not set}

# Set default if not set
export LOGDIR=${LOGDIR:-$HOME/.emacs.d/logs}
```

### Shell Compatibility

```bash
# POSIX-compliant (works in sh, bash, dash)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Bash-specific (not POSIX)
SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
```

---

## 5. Common Pitfalls and Quick Reference

### Pitfall Summary Table

| Pitfall | Symptom | Solution |
|---------|---------|----------|
| Cron variable not expanded | Empty log files, no errors | Use `$HOME` inline, not custom vars |
| Hardcoded `/Users/username` | Works on one machine only | Use `$HOME` or `$(git rev-parse --show-toplevel)` |
| `defvar` with value in consumer | Variable always resets to nil | Use `defvar` without value for forward decl |
| `pkill` on emacs daemon | Stale socket files | Use `systemctl --user restart emacs` |
| Missing export in script | Variable not available to subshells | Use `export VAR=value` in wrapper scripts |

### Quick Reference Commands

```bash
# Test variable expansion
echo "$HOME"
echo "${HOME:?This variable is required}"

# List all environment variables
env | sort

# Run command with specific environment
env HOME=/tmp LOGDIR=/tmp/logs your-command

# Debug crontab expansion
crontab -l | while read line; do echo "$line"; done
```

### Emacs Lisp Quick Reference

```elisp
;; Declare external variable (forward reference)
(defvar external-var)

;; Declare with default (defines if not exists)
(defvar my-var "default" "Doc string.")

;; Check if variable is bound
(boundp 'external-var)

;; Get value safely
(or (bound-and-true-p external-var) default-value)
```

---

## Related

- [[Cron Configuration]] - System job scheduling
- [[Emacs Lisp Best Practices]] - Language conventions
- [[Path Handling in Emacs]] - Portable file operations
- [[Systemd User Services]] - Linux service management
- [[Shell Scripting Fundamentals]] - POSIX shell patterns
- [[Environment Variables]] - System configuration

---

*This page is maintained as part of the knowledge base. Last updated: 2026-03-27*