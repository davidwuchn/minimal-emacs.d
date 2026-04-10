---
title: variable
status: open
---

Synthesized from 3 memories.

# Cron Variable Expansion Bug

> Last session: 2026-03-27

## Problem

Cron jobs were running but logs were empty. The `$LOGDIR` variable in crontab was not being expanded.

## Root Cause

In crontab, the line:
```
LOGDIR=$HOME/.emacs.d/var/tmp/cron
```
sets the variable in cron's environment, but when the command runs:
```
... >> $LOGDIR/auto-workflow.log 2>&1
```
The shell receiving the command doesn't have `LOGDIR` set, so `$LOGDIR` expands to empty string.

## Fix

Use `$HOME` directly instead of custom variable:
```
... >> $HOME/.emacs.d/var/tmp/cron/auto-workflow.log 2>&1
```

## Detection

```bash
journalctl -u cron --since "today" | grep -E "davidwu|CMD"
```

Shows cron commands with unexpanded variables.

## Files

- `cron.d/auto-workflow-pi5` (Pi5)
- `cron.d/auto-workflow` (macOS)

# defvar for External Variables

**Discovery:** Use simple `(defvar var-name)` without docstring for variables defined in other files. Avoids duplicate definitions and compiler warnings.

**Before (wrong):**
```elisp
(defvar gptel-auto-workflow--worktree-state nil
  "Hash table for worktree state. Defined in gptel-tools-agent.el.")
```

**After (correct):**
```elisp
(defvar gptel-auto-workflow--worktree-state)
```

**Why:** 
- Docstring duplicates what's in the primary definition file
- Without docstring, compiler knows variable exists but doesn't override original
- Cleaner for forward declarations across modules

**Warning:** With `lexical-binding: t`, `let` bindings for special variables need `defvar` first. Otherwise the binding is lexical and has no effect on the global/dynamic value.

**Symbol:** 💡

# Use $HOME Instead of Hardcoded Paths

> Last session: 2026-03-26

## Context

Running on Debian Linux (Pi5 aarch64), not macOS.

## Pattern

```
λ paths. Use $HOME or $(git rev-parse --show-toplevel)
λ avoid. /Users/davidwu hardcoded paths
λ files. scripts/*.sh fallback paths updated
```

## Files Fixed

- `scripts/run-tests.sh` - unified test runner (unit/e2e/cron/evolve)
- `scripts/verify-integration.sh` - fallback to `$HOME/.emacs.d/scripts`
- `AGENTS.md` - nucleus reference uses `$HOME/workspace/nucleus/AGENTS.md`

## Systemd Service Management

On Debian, Emacs daemon runs via systemd user service:

```bash
systemctl --user status emacs   # Check status
systemctl --user restart emacs  # Restart daemon (NOT pkill)
journalctl --user -u emacs      # View logs
```

**Never use `pkill -f "emacs --daemon"`** - it leaves stale socket files.

## Detection

```bash
grep -rn "/Users/davidwu" . --include="*.sh" --include="*.el" --include="*.md"
```