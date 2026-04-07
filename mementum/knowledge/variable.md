---
title: Variables in Shell and Emacs Lisp
status: active
category: knowledge
tags: [shell, emacs-lisp, cron, portability, debugging, path]
---

# Variables in Shell and Emacs Lisp

## Introduction

Variables are fundamental to both shell scripting and Emacs Lisp programming. They enable configuration, environment management, and dynamic behavior. However, variable scoping, expansion timing, and environment inheritance create subtle bugs that can be difficult to diagnose. This page synthesizes practical knowledge about variables across shell (bash) and Emacs Lisp contexts, with emphasis on portability and debugging techniques.

## Variable Expansion in Shell Environments

### The Cron Variable Expansion Problem

One of the most insidious variable bugs occurs in crontab files. Variables *appear* to be set correctly, but commands fail silently because the variable isn't visible to the shell that executes them.

**Root Cause:** Crontab format allows variable assignment at the top of the file:

```crontab
LOGDIR=$HOME/.emacs.d/var/tmp/cron
0 * * * * /path/to/script.sh >> $LOGDIR/auto-workflow.log 2>&1
```

However, cron sets these variables in its own environment table. When cron invokes the shell to run the command, it passes the command string directly. The receiving shell process has *no knowledge* of `LOGDIR`—it only inherits the environment variables that cron explicitly exports.

**Why This Happens:**

| Crontab Line | What It Does | What It Doesn't Do |
|--------------|--------------|-------------------|
| `VAR=value` | Sets in cron's env table | Exports to child shell |
| `0 * * * * cmd $VAR` | String interpolation happens | Shell gets literal `$VAR` text |

The command string `$LOGDIR/auto-workflow.log` is interpolated by cron (which knows `LOGDIR`), but the *shell* that receives the command sees the literal text `$LOGDIR` and expands it to empty string since `LOGDIR` doesn't exist in its environment.

**Fix Pattern:** Always use variables that are guaranteed to exist in the execution environment:

```crontab
# WRONG - LOGDIR not visible to shell
LOGDIR=$HOME/.emacs.d/var/tmp/cron
0 * * * * /path/to/script.sh >> $LOGDIR/log.txt

# CORRECT - $HOME is in the inherited environment
0 * * * * /path/to/script.sh >> $HOME/.emacs.d/var/tmp/cron/log.txt
```

### Environment Inheritance Chain

Understanding the environment inheritance chain helps predict variable visibility:

```
User Session (shell, SSH)
    ↓ exports
Systemd User Service
    ↓ inherits + adds
Cron Daemon
    ↓ for each job
New Shell Process (subcommand)
```

Each boundary is a potential point of variable loss. Variables must be:
1. Exported (`export VAR=value` or `VAR=value; export VAR`)
2. Passed explicitly (`VAR=value command`)
3. Or use universally available variables (`$HOME`, `$USER`, `$PATH`)

## Emacs Lisp Variable Patterns

### Forward Declarations with defvar

Emacs Lisp uses dynamic binding by default. When a variable is defined in one file and used in another, `defvar` serves as a forward declaration that tells the compiler "this variable exists" without creating a duplicate definition.

**The Problem with Docstrings in Forward Declarations:**

```elisp
;; WRONG - Compiler re-defines with docstring, losing original metadata
(defvar gptel-auto-workflow--worktree-state nil
  "Hash table for worktree state. Defined in gptel-tools-agent.el.")
```

This pattern has two issues:
1. The docstring duplicates information from the primary definition
2. If loaded before the real definition, it sets the variable's documentation string incorrectly

**Correct Forward Declaration Pattern:**

```elisp
;; CORRECT - Minimal forward declaration
(defvar gptel-auto-workflow--worktree-state)
```

The bare `defvar` without value or docstring:
- Tells the compiler the symbol exists as a variable
- Prevents "variable not defined" warnings
- Doesn't override any existing definition or documentation
- Is idempotent—loadi
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-klHRio.txt. Use Read tool if you need more]...