---
title: Cron Scheduling in Emacs Infrastructure
status: active
category: knowledge
tags: [cron, emacs, scheduling, automation, devops]
---

# Cron Scheduling in Emacs Infrastructure

This page documents the cron-based scheduling system used for autonomous Emacs operations, including setup, common pitfalls, and integration patterns.

## Overview

Cron is used to schedule automated Emacs tasks that must survive restarts and maintain standard Unix logging. This infrastructure supports autonomous workflows, weekly synthesis, and scheduled experiments.

## Installation

### Quick Install

```bash
./scripts/install-cron.sh --dry-run   # Preview configuration
./scripts/install-cron.sh              # Install to cron.d
```

### Manual Install

```bash
sudo cp cron.d/auto-workflow /etc/cron.d/
sudo chmod 644 /etc/cron.d/auto-workflow
```

### Directory Setup

Ensure required directories exist before cron jobs run:

```bash
mkdir -p var/tmp/cron
mkdir -p var/tmp/experiments
mkdir -p ~/.emacs.d/var/tmp/cron
```

## Cron Configuration

### Basic Structure

```cron
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin
LOGDIR=~/.emacs.d/var/tmp/cron

# Job definitions
0 2 * * * davidwu emacsclient -e '(gptel-auto-workflow-run)' >> $LOGDIR/auto-workflow.log 2>&1
```

### Scheduled Jobs

| Schedule | Job | Purpose | Log File |
|----------|-----|---------|----------|
| Daily 2:00 AM | `auto-workflow-run` | Overnight experiments | `auto-workflow.log` |
| Weekly Sun 4:00 AM | `mementum-weekly-job` | Synthesis + decay | `mementum-weekly.log` |
| Weekly Sun 5:00 AM | `instincts-weekly-job` | Evolution | `instincts-weekly.log` |

### Full Example: auto-workflow

```cron
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin
LOGDIR=/Users/davidwu/.emacs.d/var/tmp/cron

# Ensure log directory exists
@reboot mkdir -p $LOGDIR

# Daily workflow at 2 AM
0 2 * * * davidwu /usr/local/bin/emacsclient -e '(gptel-auto-workflow-run)' >> /Users/davidwu/.emacs.d/var/tmp/cron/auto-workflow.log 2>&1

# Weekly synthesis on Sunday at 4 AM
0 4 * * 0 davidwu /usr/local/bin/emacsclient -e '(gptel-benchmark-mementum-weekly-job)' >> /Users/davidwu/.emacs.d/var/tmp/cron/mementum-weekly.log 2>&1
```

## Prerequisites

### Emacs Daemon

Cron requires the Emacs daemon to be running:

```bash
# Start manually
emacs --daemon

# Or let cron start it
@reboot emacs --daemon
```

### Verify Daemon

```bash
# Check if daemon is running
pgrep -f "emacs --daemon"

# Connect test
emacsclient -e "(+ 1 1)"
```

## Common Issues and Solutions

### Issue 1: Command Not Found

**Error:**
```
/bin/bash: emacsclient: command not found
```

**Cause:** Cron runs with minimal environment, no user PATH.

**Solution:** Set explicit PATH in cron file:

```cron
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin
```

Also use full paths for commands when possible:

```cron
0 2 * * * davidwu /usr/local/bin/emacsclient -e '(func)' >> /path/to/log.log 2>&1
```

### Issue 2: Variable Not Expanded

**Problem:** Custom variables like `LOGDIR` don't expand in the command part.

**Cause:** Cron sets variables in its own environment, but the shell executing the command doesn't inherit them.

**Wrong:**
```cron
LOGDIR=$HOME/.emacs.d/var/tmp/cron
0 2 * * * emacsclient >> $LOGDIR/file.log  # $LOGDIR is empty!
```

**Correct:** Use `$HOME` directly or set full path:

```cron
0 2 * * * emacsclient >> $HOME/.emacs.d/var/tmp/cron/file.log 2>&1
```

### Issue 3: args-out-of-range Error

**Error:**
```
[auto-workflow] Cron error: (args-out-of-range 1 0 7)
```

**Cause:** `substring` calls in `gptel-tools-agent.el` assume strings are at least 7 characters.

**Problematic code:**
```elisp
(substring commit-hash 0 7)  ; crashes if empty or short
```

**Solution:** Add length guards:

```elisp
;; Safe substring for commit hashes
(if (>= (length commit-hash) 7)
    (substring commit-hash 0 7)
  commit-hash)

;; Safe date parsing
(let* ((date-str (match-string 1 content))
       (last-tested (when (>= (length date-str) 10)
                      (encode-time ...)))
       (age (when last-tested
              (- now (float-time last-tested)))))
  (when (and age (> age four-weeks)) ...))
```

**Files affected:** `lisp/modules/gptel-tools-agent.el` (lines 114, 142, 204-205, 3414-3416)

## Debugging Cron Jobs

### View Cron Logs

```bash
# System journal
journalctl -u cron --since "today"

# Follow log files
tail -f var/tmp/cron/*.log
tail -f ~/.emacs.d/var/tmp/cron/*.log
```

### Test Environment

Simulate cron's minimal environment:

```bash
env -i PATH=/usr/bin:/bin HOME=$HOME /bin/bash -c 'which emacsclient'
```

### Capture Environment

```bash
# Add to crontab temporarily
* * * * * env > /tmp/cron-env.txt 2>&1

# Compare with interactive shell
diff /tmp/cron-env.txt <(env)
```

## Patterns

### Pattern: Cron vs Emacs Timer

| Criteria | Cron | Emacs Timer |
|----------|------|-------------|
| Survives restart | ✓ | ✗ |
| Standard Unix tool | ✓ | ✗ |
| Easy log management | ✓ | Manual |
| Visibility (`crotab -l`) | ✓ | Internal only |
| Session-aware | ✗ | ✓ |
| Interactive prompts | ✗ | ✓ |

**Use Cron for:**
- Automated workflows that run overnight
- Scheduled synthesis and evolution
- Cleanup tasks independent of user session

**Use Emacs Timer for:**
- Notifications while user is working
- Interactive prompts
- Context-dependent triggers

### Pattern: Lambda for Scheduling Choice

```
λ schedule(x).    cron(x) > emacs_timer(x)
                  | survives_restart(x) ∧ standard_unix(x)
                  | session_aware(x) → emacs_timer(x)
```

## Verification Commands

```bash
# List installed crontabs
crontab -l
sudo cat /etc/cron.d/auto-workflow

# Check cron daemon status
sudo systemctl status cron
# or
sudo launchctl list | grep cron

# Manual test of job
emacsclient -e '(gptel-auto-workflow-run)'
```

## Related

- [Emacs Daemon](emacs-daemon) - Running Emacs as a background service
- [gptel-auto-workflow](gptel-auto-workflow) - Automated Git workflow orchestration
- [Emacs Timers](emacs-timers) - Alternative scheduling within Emacs
- [Environment Variables](environment-variables) - PATH and configuration
- [Error Handling](error-handling) - Debugging Elisp errors like args-out-of-range