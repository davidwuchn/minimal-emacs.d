---
title: Variable Usage Patterns and Pitfalls
status: active
category: knowledge
tags: [shell, elisp, environment, debugging, portability]
---

# Variable Usage Patterns and Pitfalls

## Overview

Variables are fundamental to portable, maintainable configuration. This page synthesizes patterns for working with variables across different contexts—shell scripts, crontab entries, and Emacs Lisp—with emphasis on common pitfalls and their solutions.

## 1. Environment Variables in Shell Contexts

### The Cron Variable Expansion Problem

**Problem:** Cron has a non-obvious behavior: variables set *within* a crontab file exist in cron's parsing environment but are **not passed** to the shell executing the command.

**Broken Pattern:**
```crontab
# WRONG: LOGDIR is set in cron's env, not the shell's env
LOGDIR=$HOME/.emacs.d/var/tmp/cron
0 * * * * /path/to/script.sh >> $LOGDIR/auto-workflow.log 2>&1
```

When cron executes this, the shell receives `$LOGDIR` as a literal string, which expands to empty since the shell has no `LOGDIR` variable defined.

**Correct Pattern:**
```crontab
# RIGHT: Use HOME directly or export in the command
0 * * * * /path/to/script.sh >> $HOME/.emacs.d/var/tmp/cron/auto-workflow.log 2>&1
```

**Alternative with Export:**
```crontab
# If you need a variable, export it in the same line
0 * * * * export LOGDIR=$HOME/.emacs.d/var/tmp/cron && /path/to/script.sh >> $LOGDIR/auto-workflow.log 2>&1
```

### Why This Happens

| Context | Variable Visibility | Expansion Point |
|---------|---------------------|-----------------|
| Crontab `VAR=value` | Cron daemon process only | Not propagated to child shell |
| Shell script `VAR=value` | Current shell session | Immediately available |
| `export VAR=value` | Current shell + child processes | Available everywhere |

### Rule of Thumb

> **In crontab:** Never assume variables set at the top of the file are available in commands. Either inline the full path or use `export` on the same command line.

---

## 2. Path Portability with $HOME

### Hardcoded Paths Break Portability

**The Problem:** Absolute paths like `/Users/davidwu/...` work on macOS but fail on Linux, BSD, or other users' machines.

**Common Offenders:**
```
/Users/davidwu/.emacs.d/scripts
/Users/davidwu/workspace/nucleus
/Users/davidwu/.local/bin
```

### Portable Alternatives

| Hardcoded (Bad) | Portable (Good) | Use Case |
|-----------------|-----------------|----------|
| `/Users/davidwu` | `$HOME` | Shell scripts, crontab |
| `/Users/davidwu/workspace/project` | `$(git rev-parse --show-toplevel)` | Git-aware scripts |
| `~/project` | `$HOME/project` or `$(cd ~/project && pwd)` | Makefiles |

### Implementation Example

**Before (broken on Linux):**
```bash
#!/bin/bash
SCRIPT_DIR="/Users/davidwu/.emacs.d/scripts"
source "$SCRIPT_DIR/common.sh"
```

**After (portable):**
```bash
#!/bin/bash
# Method 1: Use $HOME
SCRIPT_DIR="$HOME/.emacs.d/scripts"

# Method 2: Relative to script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts"

# Method 3: Git-aware (if in a repo)
SCRIPT_DIR="$(git rev-parse --show-toplevel)/scripts"
```

### Detection Command

Find all hardcoded paths that need fixing:
```bash
grep -rn "/Users/davidwu" . --include="*.sh" --include="*.el" --include="*.md"
```

### Files Commonly Affected

| File Type | Pattern to Find | Fix Required |
|-----------|------------------|--------------|
| Shell scripts | `"/Users/.*"` | Replace with `$HOME` |
| Emacs config | `"/Users/.*"` | Replace with `~` or `$HOME` |
| Documentation | `"$HOME"` | Verify paths are relative |
| Cron files | Any absolute path | Audit for system-specific paths |

---

## 3. Emacs Lisp: defvar Patterns

### Forward Declaration with defvar

When a variable is defined in one file but used in another, use `defvar` without a docstring for the forward declaration.

**Anti-Pattern (Duplicate Definition):**
```elisp
;; In gptel-tool
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-LuUR51.txt. Use Read tool if you need more]...