---
title: Variable Handling Patterns
status: active
category: knowledge
tags: [shell, crontab, elisp, portability, paths, systemd]
---

# Variable Handling Patterns

This knowledge page covers essential patterns for working with variables across different contexts: shell scripting, cron jobs, Emacs Lisp, and cross-platform path handling. Understanding these patterns prevents common bugs related to variable scope, expansion, and portability.

## 1. Variable Expansion in Cron Jobs

### The Problem

Cron jobs have a unique environment behavior that often surprises developers. Variables defined in the crontab itself are **not automatically passed** to the shell executing the command. This is because cron spawns a shell that doesn't inherit variables set in the crontab's environment.

### Root Cause Example

```crontab
# WRONG: This sets LOGDIR in cron's environment, not the shell's
LOGDIR=$HOME/.emacs.d/var/tmp/cron
0 * * * * ... >> $LOGDIR/auto-workflow.log 2>&1
```

When this runs, `$LOGDIR` expands to an empty string because the shell executing the command doesn't have access to `LOGDIR`.

### The Fix

Use environment variables directly in the command, or use shell variable assignment within the command itself:

```crontab
# Option 1: Direct variable expansion
0 * * * * ... >> $HOME/.emacs.d/var/tmp/cron/auto-workflow.log 2>&1

# Option 2: Shell variable in the command
0 * * * * LOGDIR=$HOME/.emacs.d/var/tmp/cron; ... >> $LOGDIR/auto-workflow.log 2>&1

# Option 3: Use a wrapper script that sets variables
0 * * * * /path/to/wrapper-script.sh
```

### Detection Commands

```bash
# View cron logs to identify unexpanded variables
journalctl -u cron --since "today" | grep -E "davidwu|CMD"

# Check crontab for problematic patterns
crontab -l | grep -E '^\w+='

# Inspect cron job environment
crontab -l | while read line; do echo "Running: $line"; done
```

### Files Affected

| File | System | Issue |
|------|--------|-------|
| `cron.d/auto-workflow-pi5` | Pi5 (Debian) | `$LOGDIR` not expanded |
| `cron.d/auto-workflow` | macOS | Same issue |

---

## 2. Emacs Lisp: Declaring External Variables

### The Pattern

When a variable is defined in one Emacs Lisp file but referenced in another, use `defvar` without a docstring to declare it. This acts as a forward declaration and prevents compiler warnings about undefined variables.

### Correct Usage

```elisp
;; In file-a.el (primary definition)
(defvar gptel-auto-workflow--worktree-state nil
  "Hash table for worktree state.")

;; In file-b.el (references file-a.el)
(defvar gptel-auto-workflow--worktree-state)
;; No docstring - acts as forward declaration
```

### Why No Docstring?

- **Avoids duplication** - The docstring already exists in the primary definition file
- **Without docstring** - The compiler knows the variable exists but doesn't override the original definition
- **With docstring** - Creates a duplicate definition which can cause confusion

### Common Mistake (Wrong)

```elisp
;; WRONG: Duplicate definition with docstring
(defvar gptel-auto-workflow--worktree-state nil
  "Hash table for worktree state. Defined in gptel-tools-agent.el.")
```

### Lexical Binding Consideration

When using `lexical-binding: t`, special variables (intended for dynamic binding) require explicit `defvar` before `let` bindings:

```elisp
;; With lexical-binding: t
(defvar some-special-variable)  ; Required for dynamic binding

(defun my-function ()
  (let (some-special-variable)  ; Without defvar, this is lexical!
    (setq some-special-variable "value")
    (some-other-function)))     ; some-other-function won't see the value!
```

Without the `defvar`, the `let` binding creates a lexical variable that shadows the special (global) variable.

---

## 3. Portable Path Patterns

### The Golden Rule

```
λ USE:     $HOME, $(git rev-parse --show-toplevel), relative paths
λ AVOID:   /Users/davidwu, /home/username, hardcoded absolute paths
```

### Portable Path Examples

| Context | Wrong | Correct |
|---------|-------|---------|
| Script paths | `/Users/davidwu/scripts/run.sh` | `$HOME/scripts/run.sh` |
| Workspace | `/home/pi/workspace/nucleus` | `$(git rev-parse --show-toplevel)` |
| Config | `~/Library/Application Support/Emacs` | `$HOME/.emacs.d` |

### Detection Command

```bash
# Find hardcoded paths in codebase
grep -rn "/Users/davidwu" . --include="*.sh" --include="*.el" --include="*.md"

# Find other hardcoded patterns
grep -rn "/home/" . --include="*.sh"
grep -rn "~/" . --include="*.sh"  # Note: ~ works in shell but not always in scripts
```

### Files Fixed

| File | Change |
|------|--------|
| `scripts/run-tests.sh` | Unified test runner with `$HOME` fallback |
| `scripts/verify-integration.sh` | Fallback to `$HOME/.emacs.d/scripts` |
| `AGENTS.md` | References use `$HOME/workspace/nucleus/AGENTS.md` |

---

## 4. Systemd Service Management (Linux)

On Debian-based systems (including Raspberry Pi), the Emacs daemon runs as a systemd user service. Understanding this is crucial for managing variables and environment.

### Service Management Commands

```bash
# Check service status
systemctl --user status emacs

# Restart daemon (NOT pkill)
systemctl --user restart emacs

# View logs
journalctl --user -u emacs

# View recent logs
journalctl --user -u emacs --since "1 hour ago"

# Follow logs in real-time
journalctl --user -u emacs -f
```

### Why Not pkill?

**Never use `pkill -f "emacs --daemon"`** - it leaves stale socket files causing:

- New daemon can't start (socket in use)
- Connection refused errors
- Need to manually remove socket files

The proper way is always `systemctl --user restart emacs`.

### Environment Variables in Systemd

Systemd services don't inherit user environment variables by default. To pass variables:

```ini
# ~/.config/systemd/user/emacs.service.d/override.conf
[Service]
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
Environment="HOME=/home/pi"
```

---

## 5. Summary Patterns Table

| Pattern | Context | Key Command/Code |
|---------|---------|------------------|
| Cron variable expansion | Crontab | Use `$VAR` directly in command |
| Forward declaration | Emacs Lisp | `(defvar name)` without docstring |
| Lexical binding | Emacs Lisp | Add `defvar` before `let` for specials |
| Portable paths | Shell scripts | `$HOME` or `$(git rev-parse --show-toplevel)` |
| Service restart | Systemd | `systemctl --user restart emacs` |
| View logs | Systemd | `journalctl --user -u emacs` |

---

## Related

- [[shell-scripting]] - Shell variable scope and expansion
- [[cron-configuration]] - Cron job best practices
- [[emacs-lisp-basics]] - Emacs Lisp variable concepts
- [[systemd-services]] - Systemd user services
- [[path-portability]] - Cross-platform path handling
- [[defvar-special-variables]] - Deep dive on defvar and lexical binding
- [[emacs-daemon-management]] - Emacs daemon best practices

---

## References

- Cron environment: Variables set in crontab are not passed to shell commands
- Emacs Lisp: `defvar` without init-value acts as forward declaration
- Shell: `$HOME` is always expanded by shell; `~` may not be in scripts
- Systemd: User services require `--user` flag for user-level management