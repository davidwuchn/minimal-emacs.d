---
title: Variable Handling Patterns
status: active
category: knowledge
tags: [variables, cron, elisp, shell, paths, portability]
---

# Variable Handling Patterns

This knowledge page covers critical patterns for working with variables across different contexts: shell environments, cron jobs, and Emacs Lisp. Understanding how variables are expanded, scoped, and declared prevents common bugs.

## 1. Variable Expansion in Cron Jobs

### The Problem

Cron jobs have a unique environment model that often surprises developers. Variables defined in the crontab itself are **not** passed to the executed command's shell.

### Root Cause

When you define a variable in crontab:

```crontab
LOGDIR=$HOME/.emacs.d/var/tmp/cron
* * * * * some-command >> $LOGDIR/auto-workflow.log 2>&1
```

The crontab sets `LOGDIR` in cron's environment, but the shell executing your command doesn't inherit it. The result: `$LOGDIR` expands to an empty string.

### Verification Command

```bash
journalctl -u cron --since "today" | grep -E "davidwu|CMD"
```

This reveals cron commands with unexpanded variables in the logs.

### The Fix

Use direct variable references or inline the path:

```crontab
* * * * * some-command >> $HOME/.emacs.d/var/tmp/cron/auto-workflow.log 2>&1
```

### Comparison Table

| Approach | Works in Cron? | Portable? | Readable? |
|----------|---------------|-----------|-----------|
| Custom variable (`$LOGDIR`) | ❌ No | ✅ Yes | ✅ Yes |
| Direct variable (`$HOME`) | ✅ Yes | ✅ Yes | ✅ Yes |
| Hardcoded path (`/Users/davidwu/...`) | ✅ Yes | ❌ No | ✅ Yes |

---

## 2. Emacs Lisp: Declaring External Variables

### The Pattern

When a variable is defined in one file but referenced in another, use `defvar` without a docstring to declare it. This acts as a forward declaration.

### Correct Usage

```elisp
;; In gptel-tools-agent.el (primary definition)
(defvar gptel-auto-workflow--worktree-state nil
  "Hash table for worktree state.")
```

```elisp
;; In other-file.el (reference only)
(defvar gptel-auto-workflow--worktree-state)
```

### Incorrect Usage (Duplicate Definition)

```elisp
;; DON'T DO THIS - creates duplicate definition with compiler warning
(defvar gptel-auto-workflow--worktree-state nil
  "Hash table for worktree state. Defined in gptel-tools-agent.el.")
```

### Why It Matters

| Aspect | With Docstring | Without Docstring |
|--------|---------------|-------------------|
| Compiler warning | ⚠️ Duplicate definition | ✅ Silent |
| Docstring source | ❌ Duplicated | ✅ Single source |
| Variable exists | ✅ Yes | ✅ Yes |
| Value override | ❌ May override original | ✅ Respects original |

### Critical: lexical-binding Warning

With `lexical-binding: t`, `let` bindings for "special" (dynamic) variables require `defvar` first:

```elisp
;; Without defvar - this creates a lexical binding, NOT a dynamic one
(let ((some-var "local-value"))
  (func-that-uses-var))  ; Won't see "local-value"!

;; With defvar - this correctly binds the special variable
(defvar some-var)
(let ((some-var "local-value"))
  (func-that-uses-var))  ; Will see "local-value"
```

---

## 3. Cross-Platform Path Variables

### The Principle

Always use environment variables for paths instead of hardcoded values. This ensures portability across different systems and users.

### Recommended Variables

| Variable | Use Case | Example |
|----------|----------|---------|
| `$HOME` | User home directory | `$HOME/.emacs.d/init.el` |
| `$PWD` | Current working directory | Logs: `$PWD/logs/app.log` |
| `$(git rev-parse --show-toplevel)` | Project root | `$PROJECT_ROOT/AGENTS.md` |
| `$USER` | Current username | `/home/$USER/` |

### Anti-Pattern: Hardcoded Paths

```bash
# BAD - won't work on different machines
/Users/davidwu/.emacs.d/scripts/run-tests.sh

# GOOD - works everywhere
$HOME/.emacs.d/scripts/run-tests.sh
```

### Systemd-Specific Patterns

On Linux systems with systemd (Debian, Pi5):

```bash
# Check user service status
systemctl --user status emacs

# Restart the daemon (NOT pkill)
systemctl --user restart emacs

# View user service logs
journalctl --user -u emacs
```

**Critical:** Never use `pkill -f "emacs --daemon"` on systemd systems—it leaves stale socket files.

### Detection Commands

Find hardcoded paths in your codebase:

```bash
grep -rn "/Users/davidwu" . --include="*.sh" --include="*.el" --include="*.md"
```

Find all path variables needing updates:

```bash
grep -rn '\$HOME\|\$PWD\|HOME\|PWD' . --include="*.sh" | head -20
```

---

## 4. Variable Scope Summary

### Environment Comparison

| Context | Variable Source | Inheritance | Expansion Time |
|---------|----------------|-------------|----------------|
| Bash shell | Environment or script | Child inherits | Runtime |
| Cron job | Crontab only | ❌ Not inherited | Parse time |
| Emacs Lisp | `defvar` / `defcustom` | Dynamic binding | Load time |
| Systemd unit | `[Service]` section | Inherited | Service start |

### Actionable Patterns

1. **Cron jobs:** Never use custom variables; use `$HOME`, `$PATH` directly
2. **Emacs external refs:** Use bare `(defvar name)` without docstring
3. **Paths:** Always prefer `$HOME` over hardcoded `/Users/username`
4. **Systemd:** Use `systemctl --user` commands, never `pkill` for daemons

---

## Related

- [Cron Configuration](../system/cron-configuration.md)
- [Emacs Package Development](../development/emacs-package-dev.md)
- [Shell Scripting Best Practices](../scripts/shell-patterns.md)
- [Systemd User Services](../system/systemd-user-services.md)
- [Path Handling in Scripts](../scripts/path-handling.md)

---