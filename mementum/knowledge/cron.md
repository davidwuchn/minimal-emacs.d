---
title: Cron Scheduling in Emacs
status: active
category: knowledge
tags: cron, emacs, scheduling, automation, daemon
---

# Cron Scheduling in Emacs

Cron provides reliable scheduling for Emacs tasks that must survive restarts and system reboots. This page covers configuration, common pitfalls, and patterns for integrating Emacs with cron.

## Overview

Cron offers advantages over Emacs timers for background tasks:

| Feature | Cron | Emacs Timer |
|---------|------|-------------|
| Survives restart | ✓ | ✗ (lost on exit) |
| Standard Unix tool | ✓ | Emacs-specific |
| Log management | ✓ (file redirection) | Manual |
| Visibility | `crontab -l` | Internal only |
| Environment control | Explicit | Inherits Emacs |

**When to use cron:** Long-running experiments, overnight tasks, weekly synthesis, system-level automation.

**When to use Emacs timers:** Session-aware notifications, interactive prompts, context-dependent triggers.

## Environment Configuration

Cron runs with a minimal environment. Always set explicit paths in your cron file.

### SHELL and PATH

```cron
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/opt/homebrew/bin
LOGDIR=/Users/davidwu/.emacs.d/var/tmp/cron
```

### Full Paths for Commands

```cron
# Always use full paths for executables
0 2 * * * /usr/local/bin/emacsclient -e '(gptel-auto-workflow-run)' >> $LOGDIR/workflow.log 2>&1
```

### Testing the Cron Environment

```bash
# See what cron actually sees
* * * * * env > /tmp/cron-env.txt 2>&1

# Compare with interactive shell
diff /tmp/cron-env.txt <(env)

# Test with minimal environment
env -i PATH=/usr/bin:/bin HOME=$HOME /bin/bash -c 'which emacsclient'
```

## Variable Expansion Gotchas

### The Problem

Cron variables set in the crontab are **not** visible to the shell executing your command:

```cron
# DON'T DO THIS - LOGDIR won't be expanded in the redirected command
LOGDIR=$HOME/.emacs.d/var/tmp/cron
0 2 * * * emacsclient -e '(func)' >> $LOGDIR/auto-workflow.log 2>&1
```

The `$LOGDIR` expands to an empty string because the shell receiving the command doesn't have that variable.

### The Solution

Use `$HOME` directly or absolute paths:

```cron
# CORRECT - use $HOME directly
0 2 * * * emacsclient -e '(gptel-auto-workflow-run)' >> $HOME/.emacs.d/var/tmp/cron/auto-workflow.log 2>&1
```

## Common Errors and Fixes

### args-out-of-range Error

**Error:** `(args-out-of-range 1 0 7)` in the Messages buffer

**Root Cause:** `substring` calls trying to extract characters from empty or short strings.

**Affected locations in `gptel-tools-agent.el`:**
- Line 114: `(substring commit-hash 0 7)` — git returns empty commit hash
- Line 142: `(substring (car o) 0 7)` — orphan hash empty/short
- Lines 204-205: Branch commits are "none" or empty
- Lines 3414-3416: Date parsing with malformed format

**Fix:** Add length guards:

```elisp
;; Before (crashes on short strings):
(substring commit-hash 0 7)

;; After (safe):
(if (>= (length commit-hash) 7)
    (substring commit-hash 0 7)
  commit-hash)
```

**Date parsing with nil checks:**

```elisp
;; Before:
(let* ((date-str (match-string 1 content))
       (last-tested (encode-time ...))
       (age (- now (float-time last-tested))))
  (when (> age four-weeks) ...))

;; After:
(let* ((date-str (match-string 1 content))
       (last-tested (when (>= (length date-str) 10)
                      (encode-time ...)))
       (age (when last-tested
              (- now (float-time last-tested)))))
  (when (and age (> age four-weeks)) ...))
```

### Command Not Found

**Error:** `/bin/bash: emacsclient: command not found`

**Fix:** Add PATH to cron file (see Environment Configuration above).

## Scheduled Jobs Setup

### Installation

```bash
# Preview what will be installed
./scripts/install-cron.sh --dry-run

# Install cron jobs
./scripts/install-cron.sh

# Verify installation
crontab -l
```

### Standard Schedule

| Time | Job | Purpose |
|------|-----|---------|
| Daily 2:00 AM | `auto-workflow-run` | Overnight experiments |
| Weekly Sunday 4:00 AM | `mementum-weekly-job` | Synthesis + decay |
| Weekly Sunday 5:00 AM | `instincts-weekly-job` | Evolution |

### Cron File Example

```cron
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/opt/homebrew/bin

# Auto-workflow - daily at 2 AM
0 2 * * * /usr/local/bin/emacsclient -e '(gptel-auto-workflow-run)' >> $HOME/.emacs.d/var/tmp/cron/auto-workflow.log 2>&1

# Weekly synthesis - Sunday at 4 AM
0 4 * * 0 /usr/local/bin/emacsclient -e '(gptel-benchmark-mementum-weekly-job)' >> $HOME/.emacs.d/var/tmp/cron/weekly-synthesis.log 2>&1

# Weekly instinct evolution - Sunday at 5 AM
0 5 * * 0 /usr/local/bin/emacsclient -e '(gptel-benchmark-instincts-weekly-job)' >> $HOME/.emacs.d/var/tmp/cron/weekly-evolution.log 2>&1
```

## Prerequisites

1. **Emacs daemon must be running:**
   ```bash
   # Start manually
   emacs --daemon

   # Or start in cron at reboot
   @reboot /usr/local/bin/emacs --daemon
   ```

2. **Create required directories:**
   ```bash
   mkdir -p ~/.emacs.d/var/tmp/cron
   mkdir -p ~/.emacs.d/var/tmp/experiments
   ```

## Monitoring and Debugging

### View Logs

```bash
# Tail all cron logs
tail -f ~/.emacs.d/var/tmp/cron/*.log

# Specific log
tail -f ~/.emacs.d/var/tmp/cron/auto-workflow.log

# System cron logs
journalctl -u cron --since "today" | grep -E "davidwu|CMD"
```

### Check Cron Status

```bash
# List installed crontab
crontab -l

# Edit crontab
crontab -e

# Remove all cron jobs
crontab -r
```

## Related

- [Emacs Daemon](./emacs-daemon.md) — Running Emacs as a background service
- [Emacsclient](./emacsclient.md) — Connecting to Emacs from the command line
- [Auto-Workflow](./auto-workflow.md) — The scheduled automation workflow
- [Cron.d Files](./cron-d-files.md) — System-wide cron configuration in `/etc/cron.d`
- [Environment Variables](./environment-variables.md) — Managing PATH and other vars