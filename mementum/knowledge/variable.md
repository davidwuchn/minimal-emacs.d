---
title: Variable
status: active
category: knowledge
tags: [shell, cron, elisp, environment, path, portability]
---

# Variable

Variables are symbolic names that store values. This knowledge page covers critical patterns for working with variables across different contexts: shell environment, Emacs Lisp, and path resolution.

## Environment Variables in Cron

### The Problem

Cron has its own limited environment. Variables set within a crontab entry are **not** inherited by the shell executing the command.

**Failing Pattern:**
```crontab
# This sets LOGDIR in cron's environment, NOT in the shell
LOGDIR=$HOME/.emacs.d/var/tmp/cron
0 * * * * some-command >> $LOGDIR/auto-workflow.log 2>&1
```

When cron executes the command, `$LOGDIR` expands to empty string because the shell doesn't have `LOGDIR` in its environment.

### The Fix

Use direct variable expansion from the shell's inherited environment:

```crontab
0 * * * * some-command >> $HOME/.emacs.d/var/tmp/cron/auto-workflow.log 2>&1
```

### Detection Command

```bash
journalctl -u cron --since "today" | grep -E "davidwu|CMD"
```

This reveals cron commands with unexpanded variables appearing as empty strings in log output.

### Files Affected

| File | System |
|------|--------|
| `cron.d/auto-workflow-pi5` | Debian/Pi5 |
| `cron.d/auto-workflow` | macOS |

---

## Emacs Lisp: defvar for External Variables

### Forward Declaration Pattern

When a variable is defined in one file but used in another, use `defvar` without a docstring as a forward declaration.

**Incorrect:**
```elisp
(defvar gptel-auto-workflow--worktree-state nil
  "Hash table for worktree state. Defined in gptel-tools-agent.el.")
```

**Correct:**
```elisp
(defvar gptel-auto-workflow--worktree-state)
```

### Why This Works

| Aspect | With Docstring | Without Docstring |
|--------|---------------|-------------------|
| Definition | Creates/redefines variable | Forward declaration only |
| Compiler warning | None (redefinition) | None |
| Source of truth | This file overrides | Original definition file |

The docstring duplicates information and may override the original definition. Without it, the compiler knows the variable exists but leaves the original definition intact.

### Warning: lexical-binding

With `lexical-binding: t`, `let` bindings for special variables require `defvar` first:

```elisp
(defvar some-special-variable)  ; Required before let with lexical-binding

(let (some-special-variable)
  (setq some-special-variable '(value))
  ;; Without defvar above, this would create a lexical binding
  ;; that doesn't affect the global/dynamic value
  (some-function))
```

---

## Path Variables: Portability

### The Problem

Hardcoded paths like `/Users/davidwu` break portability across systems and users.

**Avoid:**
```bash
# Never hardcode usernames
/Users/davidwu/workspace/...
```

**Prefer:**
```bash
# Use HOME for user directories
$HOME/workspace/...

# Use git rev-parse for project roots
$(git rev-parse --show-toplevel)/relative/path
```

### Portable Path Pattern

```bash
# In shell scripts
SCRIPT_DIR="${HOME}/.emacs.d/scripts"
PROJECT_ROOT="$(git rev-parse --show-toplevel)"

# In crontab (inherits HOME)
0 * * * * ${HOME}/.emacs.d/scripts/auto-workflow.sh >> /tmp/workflow.log
```

### Detection Command

```bash
grep -rn "/Users/davidwu" . --include="*.sh" --include="*.el" --include="*.md"
```

### Files Fixed

| File | Purpose |
|------|---------|
| `scripts/run-tests.sh` | Unified test runner |
| `scripts/verify-integration.sh` | Integration verification |
| `AGENTS.md` | Agent documentation |

---

## Systemd Environment

### Service Management

On Debian/Linux with systemd user services:

```bash
# Check status
systemctl --user status emacs

# Restart daemon (NOT pkill)
systemctl --user restart emacs

# View logs
journalctl --user -u emacs
```

### Critical Warning

**Never use `pkill -f "emacs --daemon"`** on systemd systems. This leaves stale socket files and prevents the service from starting cleanly.

Instead, rely on systemd to manage the daemon lifecycle.

### Environment Variables in Systemd

Systemd services have a sanitized environment. Pass variables explicitly:

```ini
[Service]
Environment="HOME=/home/username"
Environment="PATH=/usr/local/bin:/usr/bin:/bin"
```

---

## Actionable Patterns Checklist

- [ ] **Cron**: Use `$HOME` directly, never custom variables from crontab
- [ ] **Elisp**: Use `(defvar var-name)` without docstring for forward declarations
- [ ] **Paths**: Use `$HOME` or `$(git rev-parse --show-toplevel)` instead of hardcoded paths
- [ ] **Systemd**: Use `systemctl --user` commands, never `pkill` for Emacs daemon
- [ ] **Detection**: Run grep commands to find hardcoded paths or unexpanded variables

---

## Related

- [Cron](./cron.md)
- [Emacs Lisp](./elisp.md)
- [Shell](./shell.md)
- [Systemd](./systemd.md)
- [Path Resolution](./path-resolution.md)
- [Emacs Daemon](./emacs-daemon.md)