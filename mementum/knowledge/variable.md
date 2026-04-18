---
title: Variable Handling Patterns
status: active
category: knowledge
tags: [shell, emacs-lisp, cron, systemd, path-handling, debugging]
---

# Variable Handling Patterns

## Overview

Variables are fundamental to portable, maintainable configuration across shell scripts, Emacs Lisp, and system services. This page covers common pitfalls and best practices for variable declaration, expansion, and cross-platform handling.

---

## 1. Shell Environment Variables

### Variable Expansion Scope

**Critical Rule:** Variables set in one context may not be available in another.

| Context | Variable Visibility | Example |
|---------|---------------------|---------|
| Shell script | Local to script and children | `VAR=value ./script.sh` |
| Cron job | Separate environment | Set in crontab, not inherited |
| Systemd service | Service environment | `Environment=` in unit file |
| Subshell | Inherited from parent | `$(command)` inherits parent env |

### Cron Variable Expansion Bug

**Problem:** Variables defined in crontab don't expand in command redirection.

**Incorrect pattern:**
```cron
LOGDIR=$HOME/.emacs.d/var/tmp/cron
0 * * * * /usr/bin/emacsclient --eval "(message \"Running\")" >> $LOGDIR/auto-workflow.log 2>&1
```

**Root Cause:** The cron daemon spawns a shell that receives the command string. While `LOGDIR` is set in cron's environment, the shell interpreting the command doesn't have access to it for I/O redirection.

**Correct pattern - inline the path:**
```cron
0 * * * * /usr/bin/emacsclient --eval "(message \"Running\")" >> $HOME/.emacs.d/var/tmp/cron/auto-workflow.log 2>&1
```

**Alternative - use environment variable with command wrapper:**
```cron
0 * * * * /bin/bash -c 'LOGDIR=$HOME/.emacs.d/var/tmp/cron; /usr/bin/emacsclient --eval "(message \"Running\")" >> $LOGDIR/auto-workflow.log 2>&1'
```

### Portable Path Handling

**Rule:** Never hardcode user home directories. Always use `$HOME` or equivalent.

**Anti-pattern (fails on non-macOS systems):**
```bash
CONFIG=/Users/davidwu/.emacs.d/config.el
DATA_DIR=/Users/davidwu/Projects
```

**Correct pattern:**
```bash
CONFIG=$HOME/.emacs.d/config.el
DATA_DIR=$HOME/Projects
```

**Dynamic alternative using git:**
```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
CONFIG=$REPO_ROOT/config.el
```

### Detection Commands

Find hardcoded paths in your codebase:

```bash
# Find macOS-specific paths
grep -rn "/Users/davidwu" . --include="*.sh" --include="*.el" --include="*.md"

# Find potential hardcoded home paths
grep -rn "\$HOME" . | grep -v "\$HOME/"  # Missing trailing slash

# Check crontab variable expansion issues
journalctl -u cron --since "today" | grep -E "CMD|error"
```

---

## 2. Emacs Lisp Variable Declarations

### Forward Declaration with defvar

**Pattern:** Use bare `(defvar symbol)` for variables defined elsewhere.

**When to use:**
- Variable defined in another file/package
- Avoiding duplicate definition warnings
- Forward declaration before use

**Incorrect - redundant docstring:**
```elisp
(defvar gptel-auto-workflow--worktree-state nil
  "Hash table for worktree state. Defined in gptel-tools-agent.el.")
```

**Correct - forward declaration:**
```elisp
(defvar gptel-auto-workflow--worktree-state)
```

**Why this works:**
- Without a docstring, `defvar` doesn't override the original definition
- Compiler recognizes the variable exists (avoids byte-compiler warnings)
- Cleaner separation between definition and declaration

### Lexical Binding and Special Variables

**Warning:** With `lexical-binding: t`, `let` bindings require `defvar` for dynamic/special variable behavior.

```elisp
;; With lexical-binding: t

;; This creates a lexical binding - doesn't affect global value
(let (some-var)
  (setq some-var "local")
  (message some-var))  ; Prints "local", but global some-var unchanged

;; Correct pattern for dynamic binding
(defvar some-var)  ; Declare as special
(let (some-var)
  (setq some-var "dynamic")
  (message some-var))  ; some-var is dynamically scoped
```

**Best practice:**
```elisp
;; Always defvar special variables before let binding
(defvar my-special-var)

(defun my-function ()
  (let ((my-special-var "value"))
    (my-inner-function)))  ; Inner function sees the dynamic value
```

### Variable Definition Checklist

| Situation | Pattern | Example |
|-----------|---------|---------|
| Define own variable | `(defvar name initial-value "doc")` | `(defvar my-var 42 "My variable.")` |
| External variable | `(defvar name)` | `(defvar external-pkg--state)` |
| Buffer-local variable | `(defvar-local name default "doc")` | `(defvar-local buf-data nil "Buffer data.")` |
| Custom variable | `defcustom` | `(defcustom my-option t "My option." :type 'boolean)` |

---

## 3. System Service Environment

### Systemd User Services

**On Debian/Linux (including Pi5 aarch64):**

```bash
# Check service status
systemctl --user status emacs

# Restart daemon (preferred over pkill)
systemctl --user restart emacs

# View logs
journalctl --user -u emacs -f

# List all user services
systemctl --user list-units --type=service
```

**Critical warning:**
```
NEVER use: pkill -f "emacs --daemon"
```
Using `pkill` on the Emacs daemon leaves stale socket files, causing subsequent start attempts to fail silently.

**Correct restart pattern:**
```bash
systemctl --user restart emacs
# Or for configuration changes requiring full stop/start:
systemctl --user stop emacs
systemctl --user start emacs
```

### Cron Job Locations

| System | Location | Notes |
|--------|----------|-------|
| macOS | `/usr/local/var/cron/tabs/` | Homebrew cron |
| Linux/Debian | `/etc/cron.d/` | System-wide |
| User crontab | `crontab -e` | Per-user |

**Crontab file examples:**
```
# Linux - /etc/cron.d/auto-workflow-pi5
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin
HOME=/home/pi

0 * * * * pi /usr/bin/emacsclient --eval "(auto-workflow-run)" >> $HOME/.emacs.d/var/tmp/cron/auto-workflow.log 2>&1
```

---

## 4. Actionable Patterns Summary

### Pattern 1: Cron Variable Safety

```bash
# NEVER do this
CRON_VAR=$HOME/data
* * * * * command >> $CRON_VAR/log.txt

# ALWAYS do this
* * * * * command >> $HOME/data/log.txt

# OR wrap in bash
* * * * * /bin/bash -c 'CRON_VAR=$HOME/data; command >> $CRON_VAR/log.txt'
```

### Pattern 2: Portable Path Resolution

```bash
# Detect hardcoded paths
detect_hardcoded_paths() {
    grep -rn "/Users/" . --include="*.sh" --include="*.el" 2>/dev/null
    grep -rn "~/.[^/]*" . --include="*.sh" 2>/dev/null | grep -v '\$HOME'
}

# Use in scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/myapp}"
DATA_DIR="${DATA_DIR:-$HOME/data}"
```

### Pattern 3: Emacs Variable Declaration

```elisp
;; In main definition file (e.g., mypkg-core.el)
(defvar mypkg--state (make-hash-table)
  "Hash table storing persistent state.")

;; In dependent file (e.g., mypkg-helper.el)
(eval-when-compile (defvar mypkg--state))
;; or simply:
(defvar mypkg--state)

(defun mypkg-helper-access-state ()
  "Access state from main module."
  (when (hash-table-p mypkg--state)
    (gethash 'key mypkg--state)))
```

### Pattern 4: Environment Variable Defaults

```bash
# Set defaults only if unset
: "${CONFIG_DIR:=$HOME/.config/myapp}"
: "${DATA_DIR:=$HOME/data}"
: "${LOG_LEVEL:=info}"

# Use throughout script
echo "Config: $CONFIG_DIR"
echo "Log: $LOG_LEVEL"
```

---

## 5. Debugging Variable Issues

### Shell Debugging

```bash
# Trace variable expansion
bash -x script.sh

# Show all variables in crontab
crontab -l | grep -E "^[A-Z]"

# Check cron environment
crontab -l | while read line; do echo "Line: $line"; done

# View cron logs with variable expansion issues
journalctl -u cron --since "1 hour ago" | grep -A2 -B2 "error\|failed"
```

### Emacs Debugging

```elisp
;; Check variable value and definition
C-h v variable-name

;; Check if variable is bound
(boundp 'variable-name)

;; Check variable's file location
(find-definition-noselect 'variable-name 'defvar)

;; Trace variable changes
(add-hook 'post-command-hook
          (lambda ()
            (when (eq (symbol-value 'my-var) 'unexpected)
              (message "my-var changed!"))))
```

---

## 6. Quick Reference Commands

| Task | Command |
|------|---------|
| List all env vars | `printenv` or `env` |
| Search for hardcoded paths | `grep -rn "/Users/" .` |
| Check crontab | `crontab -l` |
| Cron logs (systemd) | `journalctl -u cron -f` |
| Emacs variable docs | `C-h v` |
| Systemd user status | `systemctl --user status` |
| Restart Emacs daemon | `systemctl --user restart emacs` |

---

## Related

- [Path Handling Best Practices](path-handling)
- [Emacs Lisp Package Development](emacs-lisp-patterns)
- [Cron Configuration](cron-setup)
- [Systemd User Services](systemd-user)
- [Shell Script Portability](shell-portability)
- [Environment Variable Management](environment-variables)

---

## Changelog

- **2026-03-27:** Documented cron variable expansion scope issue
- **2026-03-26:** Added portable path patterns and systemd service management
- **2026-03-25:** Initial defvar patterns documentation