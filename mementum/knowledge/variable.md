---
title: Variable Handling in Practice
status: active
category: knowledge
tags: [cron, emacs-lisp, shell, paths, portability, best-practices]
---

# Variable Handling in Practice

This knowledge page covers critical patterns and pitfalls in variable handling across multiple contexts: shell scripting, cron scheduling, and Emacs Lisp. These topics share a common theme: variables not behaving as expected due to scope, expansion timing, or binding issues.

---

## Shell Variables in Cron: The Expansion Problem

### The Problem

Cron jobs often fail to expand custom variables defined in the crontab file itself. This leads to silent failures where logs appear empty or files are created in unexpected locations.

### Root Cause

Cron has a two-stage execution model that causes confusion:

1. **Crontab parsing**: When cron reads the crontab, variables like `LOGDIR=$HOME/.logs` are set in cron's environment
2. **Command execution**: The command runs in a subshell that does **not** inherit these custom variables—only the standard environment variables like `$HOME`, `$PATH`, and `$USER`

### Demonstration

```crontab
# WRONG: LOGDIR is not visible to the command
LOGDIR=$HOME/.emacs.d/var/tmp/cron
*/5 * * * * some-command >> $LOGDIR/auto-workflow.log 2>&1

# CORRECT: Use $HOME directly in the command
*/5 * * * * some-command >> $HOME/.emacs.d/var/tmp/cron/auto-workflow.log 2>&1
```

### Detection Commands

```bash
# View cron entries that may have expansion issues
crontab -l | grep -E '\$[A-Z_]+'

# Check systemd-cron logs (Debian/Pi5)
journalctl -u cron --since "today" | grep -E "CMD|auto-workflow"

# Search for unexpanded variables in logs
grep -r '\$LOGDIR\|\$CUSTOM' /var/log/cron* 2>/dev/null
```

### Files Affected

| File | System | Issue |
|------|--------|-------|
| `/etc/cron.d/auto-workflow-pi5` | Pi5 (Debian) | LOGDIR not expanded |
| `/etc/cron.d/auto-workflow` | macOS | LOGDIR not expanded |

---

## Emacs Lisp: Forward Declaration of Variables

### The Pattern

When a variable is defined in one Emacs Lisp file but referenced in another, use `defvar` without a docstring to create a forward declaration. This avoids compiler warnings about undefined variables and prevents duplicate definitions.

### Before (Problematic)

```elisp
;; ❌ DON'T do this in the consuming file
(defvar gptel-auto-workflow--worktree-state nil
  "Hash table for worktree state. Defined in gptel-tools-agent.el.")
```

**Problems:**
- Duplicates the docstring from the primary definition
- May confuse readers about the "true" source of the variable
- Compiler sees this as a new definition, not a reference

### After (Correct)

```elisp
;; ✅ DO this in the consuming file
(defvar gptel-auto-workflow--worktree-state)
```

**Benefits:**
- Satisfies the compiler (no "void variable" warning)
- Does not override the original definition
- Acts as a forward declaration

### The Lexical Binding Caveat

When `lexical-binding: t` is enabled, `defvar` becomes essential for dynamic binding:

```elisp
;;; -*- lexical-binding: t; -*-

;; Without defvar, this let binding is lexical (local only)
(let ((gptel-auto-workflow--worktree-state (make-hash-table)))
  (message "This creates a local binding, not affecting global state"))

;; With defvar first, the let binding affects the special (dynamic) variable
(defvar gptel-auto-workflow--worktree-state)
(let ((gptel-auto-workflow--worktree-state (make-hash-table)))
  (message "This modifies the global special variable"))
```

### Quick Reference: defvar Forms

| Form | Use Case |
|------|----------|
| `(defvar symbol)` | Forward declaration, no default |
| `(defvar symbol init-value)` | Define with default value |
| `(defvar symbol init-value "doc")` | Full definition with documentation |
| `(defvar symbol init-value "doc" :variable t)` | Customizable via `customize` |

---

## Cross-Platform Path Handling

### The Principle

Never hardcode user-specific paths like `/Users/davidwu`. Always use environment variables or runtime detection for portable scripts.

### Environment Variables for Paths

```bash
# Preferred: HOME is universal across Unix-like systems
$HOME/.emacs.d/scripts

# For Git projects: detect project root
PROJECT_ROOT=$(git rev-parse --show-toplevel)

# Fallback chain
SCRIPT_DIR="${HOME}/.emacs.d/scripts"
[ -d "$SCRIPT_DIR" ] || SCRIPT_DIR="./scripts"
```

### Pattern Matrix

| Pattern | Use | Avoid |
|---------|-----|-------|
| `$HOME` | User home directory | Hardcoded `/Users/username` |
| `$(git rev-parse --show-toplevel)` | Project root in Git repos | Relative paths from unknown location |
| `$PWD` | Current working directory | Assuming specific directory |
| `${0%/*}` | Script's own directory | Hardcoded script paths |

### Files Updated with Portable Paths

```bash
# Scripts converted from hardcoded to portable
scripts/run-tests.sh           # Now uses $HOME fallback
scripts/verify-integration.sh  # Now uses $HOME fallback

# Documentation updated
AGENTS.md                      # References $HOME/workspace/nucleus/
```

### Systemd Service Management (Debian)

On Debian-based systems (including Raspberry Pi OS), manage the Emacs daemon via systemd, not process signals:

```bash
# Check daemon status
systemctl --user status emacs

# Restart (NOT pkill)
systemctl --user restart emacs

# View logs
journalctl --user -u emacs -f

# NEVER use pkill - it leaves stale socket files
# pkill -f "emacs --daemon"  ❌
```

### Detection Commands

```bash
# Find hardcoded paths that break portability
grep -rn "/Users/davidwu" . \
  --include="*.sh" \
  --include="*.el" \
  --include="*.md"

# Find potential path issues in cron configs
grep -rn "\$HOME\|\$LOGDIR\|/home/" /etc/cron.d/
```

---

## Unified Pattern: Variable Scope Cheat Sheet

| Context | Scope Type | Solution |
|---------|-----------|----------|
| Cron crontab | Command doesn't inherit crontab vars | Use `$HOME` directly in command |
| Shell script | Inherited from parent | Export variables or use inline |
| Emacs Lisp (lexical) | Local by default | Use `defvar` for special variables |
| Emacs Lisp (dynamic) | Global by default | Use `let` to shadow |
| Cross-platform scripts | OS-dependent paths | Use `$HOME`, detect at runtime |

---

## Actionable Checklist

- [ ] When writing cron commands, use `$HOME` directly—never custom crontab variables
- [ ] In Emacs Lisp files that reference variables from other files, add `(defvar variable-name)` without docstring
- [ ] Enable `lexical-binding: t`? Add `defvar` for any variables you intend to bind dynamically with `let`
- [ ] Replace all `/Users/davidwu` with `$HOME` in scripts and documentation
- [ ] Use `$(git rev-parse --show-toplevel)` for project-relative paths in Git repositories
- [ ] On Debian, manage Emacs daemon with `systemctl --user`, never `pkill`
- [ ] Run detection commands before deploying scripts to new environments

---

## Related

- [Cron Configuration](/cron-configuration)
- [Emacs Lisp Development](/emacs-lisp-development)
- [Shell Script Best Practices](/shell-script-best-practices)
- [Systemd User Services](/systemd-user-services)
- [Path Handling in Emacs](/path-handling-emacs)
- [Project Detection with Git](/git-project-detection)
- [Environment Variables Reference](/environment-variables)