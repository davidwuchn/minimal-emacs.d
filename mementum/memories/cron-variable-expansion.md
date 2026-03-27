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