---
title: Variable Handling in Shell and Emacs
status: active
category: knowledge
tags: [shell, emacs-lisp, environment, cron, portability]
---

# Variable Handling in Shell and Emacs

## Overview

Variables in shell scripts and Emacs Lisp behave differently from traditional programming languages. Environment variables, shell variables, and Lisp variables each have distinct scoping rules and expansion behaviors. This page synthesizes patterns for handling variables correctly across these contexts.

## Shell Environment Variables

### Variable Expansion in Cron Jobs

**Problem:** Cron jobs often fail silently when variables appear undefined.

| Context | Variable Set | Variable Visible | Result |
|---------|--------------|------------------|--------|
| Crontab assignment | Yes | No | Empty expansion |
| Inline `$HOME` | N/A | Yes | Works correctly |
| Subshell export | Yes | Yes | Works correctly |

**Broken Pattern (Crontab):**
```bash
# WRONG - LOGDIR is set in cron's environment, not the shell's
LOGDIR=$HOME/.emacs.d/var/tmp/cron
0 * * * * /path/to/command >> $LOGDIR/auto-workflow.log 2>&1
```

**Correct Pattern (Crontab):**
```bash
# RIGHT - Expand variable inline
0 * * * * /path/to/command >> $HOME/.emacs.d/var/tmp/cron/auto-workflow.log 2>&1
```

**Why This Happens:**

1. Crontab lines are parsed by cron daemon
2. Variable assignments like `LOGDIR=value` set cron's environment
3. The actual command runs in a separate shell process
4. That shell doesn't inherit the variable from cron's environment
5. `$LOGDIR` expands to empty string

**Detection Commands:**
```bash
# View cron job execution with expanded variables
journalctl -u cron --since "today" | grep -E "COMMAND|CMD"

# On macOS
log show --predicate 'process == "cron"' --last 1h

# Test variable visibility in your cron environment
crontab -l | while read line; do echo "Line: $line"; done
```

---

### Path Portability: Use `$HOME` or Dynamic Resolution

**Anti-pattern:** Hardcoded user paths
```bash
# WRONG - Breaks on different systems/users
/Users/davidwu/workspace/project
/home/username/project
```

**Correct Patterns:**
```bash
# Use HOME for home directory
$HOME/.emacs.d/var/tmp

# Use git toplevel for project root
$(git rev-parse --show-toplevel)

# Use script directory for relative paths
$(dirname "$0")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Use realpath for canonical paths
$(realpath "$0")
```

**System Detection Pattern:**
```bash
# Detect OS and set paths accordingly
detect_os() {
    case "$(uname -s)" in
        Darwin*)  echo "macOS" ;;
        Linux*)   echo "Linux" ;;
        CYGWIN*)  echo "Windows" ;;
        *)        echo "Unknown" ;;
    esac
}

# Linux systemd paths
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"

# macOS launchd paths
LAUNCHD_USER_DIR="$HOME/Library/LaunchAgents"
```

**Portability Scan:**
```bash
# Find all hardcoded paths that should be portable
grep -rn "/Users/" . --include="*.sh" --include="*.el" --include="*.md"
grep -rn "/home/" . --include="*.sh" --include="*.el"
grep -rn "/tmp" . --include="*.sh" | grep -v "\$TMPDIR\|\/tmp\/"
```

---

## Emacs Lisp Variables

### Forward Declaration with `defvar`

**Purpose:** Declare a variable exists without defining it, useful when a variable is defined in another file or loaded library.

**Correct Pattern (No Docstring):**
```elisp
;; Forward declaration - variable defined elsewhere
(defvar gptel-auto-workflow--worktree-state)

;; Multiple forward declarations
(defvar gptel-auto-workflow--cache-dir)
(defvar gptel-auto-workflow--config-alist)
```

**Anti-pattern (Duplicate Definition):**
```elisp
;; WRONG - Duplicates docstring and may cause compiler warnings
(defvar gptel-auto-workflow--worktree-state nil
  "Hash table for worktree state. Defined in gptel-tools-agent.el.")
```

**Why Without Docstring:**
| Aspect | With Docstring | Without Docstring |
|--------|----------------|-------------------|
| Co
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-2UwLRN.txt. Use Read tool if you need more]...