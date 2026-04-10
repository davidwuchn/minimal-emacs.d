---
title: Variable Usage Patterns
status: active
category: knowledge
tags: [shell, crontab, emacs-lisp, portability, environment]
---

# Variable Usage Patterns

This knowledge page covers variable usage patterns across shell scripts, cron jobs, and Emacs Lisp, focusing on common pitfalls and best practices for portable, maintainable code.

## Shell Variables in Cron Jobs

### The Problem

Cron jobs have a unique environment behavior that often surprises developers. Variables set within a crontab entry are **not** automatically propagated to the shell executing the command.

### Example: Failed Variable Expansion

**Crontab entry:**
```crontab
LOGDIR=$HOME/.emacs.d/var/tmp/cron
*/5 * * * * some-command >> $LOGDIR/auto-workflow.log 2>&1
```

**What happens:**
- `LOGDIR=$HOME/...` sets the variable in cron's limited environment
- When the command executes, the shell receiving it has **no** `LOGDIR` defined
- `$LOGDIR` expands to an empty string
- Result: `>> /auto-workflow.log` (writes to root filesystem!) or silent failure

### Detection Command

```bash
journalctl -u cron --since "today" | grep -E "davidwu|CMD"
```

This reveals cron commands with unexpanded variables appearing in logs.

### Fix: Use Direct Variable References

```crontab
*/5 * * * * some-command >> $HOME/.emacs.d/var/tmp/cron/auto-workflow.log 2>&1
```

Or use a shell wrapper:
```crontab
*/5 * * * * /bin/bash -c 'LOGDIR=$HOME/.emacs.d/var/tmp/cron; some-command >> $LOGDIR/auto-workflow.log 2>&1'
```

### Comparison Table

| Approach | Example | Works? |
|----------|---------|--------|
| Crontab variable | `LOGDIR=...` then `>> $LOGDIR/...` | ❌ No |
| Direct `$HOME` | `>> $HOME/path/...` | ✅ Yes |
| Shell wrapper | `/bin/bash -c 'var=...; cmd >> $var/...'` | ✅ Yes |
| Inline export | `* * * * * export VAR=val; cmd` | ✅ Yes |

---

## Emacs Lisp: defvar for External Variables

### Forward Declaration Pattern

When a variable is defined in one Emacs Lisp file but referenced in another, use `defvar` without a docstring to declare it exists.

### Correct Usage

```elisp
;; In gptel-tools-agent.el (primary definition)
(defvar gptel-auto-workflow--worktree-state nil
  "Hash table for worktree state.")

;; In gptel-auto-workflow.el (reference file)
(defvar gptel-auto-workflow--worktree-state)
```

### Incorrect Usage (Duplicate Definition)

```elisp
;; WRONG - duplicates docstring, may cause compiler warnings
(defvar gptel-auto-workflow--worktree-state nil
  "Hash table for worktree state. Defined in gptel-tools-agent.el.")
```

### Why This Works

- Without docstring, `defvar` acts as a forward declaration
- Compiler knows the variable exists but doesn't override the original definition
- Avoids "variable defined multiple times" warnings
- Keeps documentation single-sourced

### Lexical Binding Consideration

With `lexical-binding: t`, special (global) variables require `defvar` before `let` bindings:

```elisp
;; With lexical-binding: t
(defvar my-global nil)  ; Required before let binding

(let ((my-global 'local-value))
  (setq my-global 'new-value)  ; Without defvar, this is a new local binding
  my-global)  ; Returns 'new-value (local), not affecting global
```

---

## Portable Path Patterns

### The Problem

Hardcoded paths like `/Users/davidwu` break portability across machines and operating systems.

### Pattern Summary

```
λ USE.     $HOME or $(git rev-parse --show-toplevel)
λ AVOID.   /Users/davidwu or C:\Users\...
```

### Shell Script Examples

```bash
# Good - portable
LOGDIR="$HOME/.emacs.d/var/tmp/cron"
WORKSPACE="$(git rev-parse --show-toplevel)"

# Bad - hardcoded
LOGDIR="/Users/davidwu/.emacs.d/var/tmp/cron"
```

### Emacs Lisp Examples

```elisp
;; Good - uses expand-file-name with ~
(defvar var-directory
  (expand-file-name "var/tmp/" user-emacs-directory))

;; Good - uses built-in paths
(let ((cache-dir (locate-user-emacs-file "cache")))
  (message "Cache at: %s" cache-dir))
```

### Detection Command

```bash
grep -rn "/Users/davidwu" . --include="*.sh" --include="*.el" --include="*.md"
```

### Files to Check

| File Type | Pattern to Search |
|-----------|-------------------|
| Shell scripts | `.sh` |
| Emacs Lisp | `.el` |
| Documentation | `.md` |
| Config files | `.yaml`, `.json` |

---

## Systemd Service Management

### Context

On Debian Linux (including Raspberry Pi), Emacs daemon runs as a systemd user service.

### Commands

```bash
# Check status
systemctl --user status emacs

# Restart daemon (NOT pkill)
systemctl --user restart emacs

# View logs
journalctl --user -u emacs
```

### Critical Warning

**Never use `pkill -f "emacs --daemon"`** — it leaves stale socket files causing subsequent startup failures.

### Example: Service File Location

```
~/.config/systemd/user/emacs.service
```

---

## Actionable Patterns Checklist

- [ ] In crontab: use `$HOME` directly or shell wrapper with exported variables
- [ ] In Emacs: use `defvar` without docstring for forward declarations
- [ ] In scripts: always use `$HOME` instead of hardcoded `/Users/...`
- [ ] In cross-platform code: use `$(git rev-parse --show-toplevel)` for project roots
- [ ] For Emacs paths: use `user-emacs-directory`, `locate-user-emacs-file`
- [ ] On systemd: use `systemctl --user` commands, never `pkill` for daemon
- [ ] Detection: run grep commands regularly to catch hardcoded paths

---

## Related

- [[Cron Configuration]]
- [[Emacs Lisp Conventions]]
- [[Shell Script Best Practices]]
- [[Systemd User Services]]
- [[Path Handling in Emacs]]
- [[Environment Variables in Cron]]

---