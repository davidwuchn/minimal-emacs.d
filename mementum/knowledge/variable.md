---

title: Variable Management Patterns
status: active
category: knowledge
tags: [elisp, shell, cron, path-resolution, best-practices]

# Variable Management Patterns

## Overview

This page covers essential patterns for managing variables across different contexts: Emacs Lisp (`defvar`, special variables), shell scripting (environment variables, cron), and path resolution. The common thread is avoiding scope leakage, ensuring variables expand in the correct environment, and maintaining portable code across systems.

---

## 1. Emacs Lisp: `defvar` for External Variables

### The Problem

When a variable is defined in one file but referenced in another, a naive `defvar` with docstring creates a duplicate definition that may override the original or trigger compiler warnings.

### Pattern: Forward Declaration Without Docstring

```elisp
;; BAD: Duplicate docstring, potential override
(defvar gptel-auto-workflow--worktree-state nil
  "Hash table for worktree state. Defined in gptel-tools-agent.el.")

;; GOOD: Clean forward declaration
(defvar gptel-auto-workflow--worktree-state)
```

### Why This Works

| Approach | Behavior |
|----------|----------|
| `defvar` with docstring | Sets variable if unbound; preserves value if already bound; docstring is redundant if primary definition exists |
| `defvar` without docstring | Same value-preserving behavior, but signals intent that this is a forward/reference declaration |
| No declaration | Byte-compiler warning; runtime `void-variable` error if accessed before load |

### Critical: `lexical-binding` Interaction

When `lexical-binding: t` is enabled, `let` bindings create lexical closures by default. For dynamic/special variable behavior:

```elisp
;; -*- lexical-binding: t; -*-

;; Without defvar: this binds LEXICALLY (local to closure)
(let ((gptel-auto-workflow--worktree-state (make-hash-table)))
  (message "This is a local binding, not the global variable"))

;; With defvar: this binds DYNAMICALLY (affects global value)
(defvar gptel-auto-workflow--worktree-state)

(let ((gptel-auto-workflow--worktree-state (make-hash-table)))
  (message "This IS the global/dynamic variable"))
```

### Quick Reference: `defvar` Forms

| Form | Use Case |
|------|----------|
| `(defvar SYMBOL)` | Forward declaration; no docstring; suppresses compiler warning |
| `(defvar SYMBOL INITVALUE DOC)` | Full definition with initial value (only set if unbound) |
| `(defvar SYMBOL INITVALUE)` | Definition without docstring but with init value |
| `(defcustom SYMBOL VALUE DOC)` | User-customizable variable (via `M-x customize`) |

---

## 2. Shell: Path Resolution Patterns

### The Golden Rule

```
⚠ ALWAYS use $HOME or $(git rev-parse --show-toplevel)
⚠ NEVER hardcode /Users/username paths
```

### Pattern Matrix

| Context | Preferred | Avoid |
|---------|-----------|-------|
| User home | `$HOME` | `/Users/davidwu`, `/home/username` |
| Project root | `$(git rev-parse --show-toplevel)` | `/home/user/workspace/project` |
| Relative to script | `$(dirname "$0")` | Hardcoded parent dirs |
| Config files | `$XDG_CONFIG_HOME` or `$HOME/.config` | `~/Library/Preferences` |

### Examples

```bash
# ✅ GOOD: Portable path resolution
LOGDIR="$HOME/.emacs.d/var/tmp/cron"
LOGFILE="$LOGDIR/auto-workflow.log"

# ✅ GOOD: Git-aware project root
PROJECT_ROOT="$(git rev-parse --show-toplevel)"
source "$PROJECT_ROOT/scripts/common.sh"

# ✅ GOOD: Script-relative paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/../config/app.conf"

# ❌ BAD: Hardcoded username
LOGFILE="/Users/davidwu/.emacs.d/var/tmp/cron/auto-workflow.log"

# ❌ BAD: Assumes specific home location
CONFIG="/home/davidwu/.config/emacs/app.conf"
```

### Detection Command

Find all hardcoded paths that break portability:

```bash
grep -rn "/Users/davidwu\|/home/[^/]\+" . \
  --include="*.sh" \
  --include="*.
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-0Zr4vO.txt. Use Read tool if you need more]...