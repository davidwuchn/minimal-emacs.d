---
title: Variable Scope and Expansion
status: active
category: knowledge
tags: [shell, emacs-lisp, cron, environment, portability]
---

# Variable Scope and Expansion

## Overview

Variables behave differently across contexts—shell scripts, crontab entries, and Emacs Lisp each have distinct scoping rules. Understanding these differences prevents silent failures where variables appear to be set but expand to empty strings or unexpected values.

## Shell Variables in Cron

### The Problem

Cron runs commands in a restricted environment. Variables set in the crontab file are **not** passed to the executing shell.

**Broken pattern:**
```crontab
LOGDIR=$HOME/.emacs.d/var/tmp/cron
*/15 * * * * /path/to/script.sh >> $LOGDIR/auto-workflow.log 2>&1
```

Here, `$LOGDIR` is set in cron's context, but when `/bin/sh -c` executes the command, `LOGDIR` is undefined. The redirect becomes `>> /auto-workflow.log 2>&1`—writing to root filesystem, not your log directory.

### The Fix

Use variable syntax that expands in cron's own context, or reference environment variables directly:

```crontab
*/15 * * * * /path/to/script.sh >> $HOME/.emacs.d/var/tmp/cron/auto-workflow.log 2>&1
```

**Rule:** Only use `$ENV_VAR` syntax in crontab for variables that exist in the system environment. Define custom paths inline or use absolute paths.

### Debugging Cron Variables

```bash
# View cron job execution logs
journalctl -u cron --since "today" | grep -E "CMD|specific-job-name"

# Verify crontab syntax
crontab -l

# Check cron daemon status (Debian/Ubuntu)
systemctl status cron

# On macOS
sudo launchctl list | grep cron
```

| Command | System | Purpose |
|---------|--------|---------|
| `journalctl -u cron` | Debian/Ubuntu | View cron logs |
| `systemctl --user status emacs` | Linux (user) | Emacs daemon status |
| `launchctl list` | macOS | List launchd jobs |

---

## Emacs Lisp Variable Declarations

### Forward Declaration with defvar

Use `(defvar symbol)` without a docstring when declaring a variable defined elsewhere. This prevents duplicate definition warnings and compiler errors.

**Correct:**
```elisp
;; In gptel-auto-workflow.el - primary definition with docstring
(defvar gptel-auto-workflow--worktree-state nil
  "Hash table caching worktree state per buffer.")

;; In gptel-tools-agent.el - forward declaration only
(defvar gptel-auto-workflow--worktree-state)
```

**Incorrect (duplicate definition):**
```elisp
(defvar gptel-auto-workflow--worktree-state nil
  "Hash table for worktree state. Defined in gptel-tools-agent.el.")
```

### Why No Docstring?

- The docstring lives with the **primary definition**—one source of truth
- Without a docstring, `defvar` acts as a compiler hint only
- Re-declaring with a docstring can cause the compiler to overwrite the original value
- Cleaner separation between "defines here" and "uses here" modules

### Lexical Binding Gotcha

When `lexical-binding: t` is enabled, `let` creates lexical bindings by default. For special (dynamic) variables, you must use `defvar` first:

```elisp
;; Without defvar - lexical binding, has no effect on global value
(let ((gptel-auto-workflow--worktree-state (make-hash-table)))
  (message "Inside let: %s" gptel-auto-workflow--worktree-state))  ; local only

;; With defvar - dynamic binding, affects global value
(defvar gptel-auto-workflow--worktree-state)
(let ((gptel-auto-workflow--worktree-state (make-hash-table)))
  (message "Inside let: %s" gptel-auto-workflow--worktree-state))  ; global affected
```

---

## Path Portability Patterns

### Use Environment Variables, Not Hardcoded Paths

**Never hardcode user-specific paths:**
```bash
# ✗ Breaks on Linux, servers, other users
/path/to /Users/davidwu/workspace/...

# ✓ Portable
$HOME/workspace/...
$(git rev-parse --show-toplevel)/...
```

### Detection Commands

```bash
# Find all hardcoded paths in codebase
grep -rn "/Users/davidwu" . --include="*.sh" --include="*
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-QsIIHl.txt. Use Read tool if you need more]...