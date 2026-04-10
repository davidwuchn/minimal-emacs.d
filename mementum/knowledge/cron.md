---
title: Cron Scheduling in Emacs Projects
status: active
category: knowledge
tags: [cron, emacs, scheduling, automation, devops]
---

# Cron Scheduling in Emacs Projects

This knowledge page covers cron setup, common pitfalls, and integration patterns for Emacs-based automation workflows.

## Overview

Cron is the standard Unix scheduler used to run automated tasks for the project. Unlike Emacs timers, cron survives system restarts and provides standardized logging. The project uses cron to run `emacsclient` commands that invoke Emacs Lisp functions.

## Common Issues and Fixes

### PATH Environment Variable

Cron runs with a minimal environment that does not include user-specific PATH settings.

**Problem:**
```
/bin/bash: emacsclient: command not found
```

**Root Cause:** Cron only has `/usr/bin:/bin` available by default. It does not load `.bashrc` or `.zshrc`.

**Solution:** Set explicit PATH in the cron file:

```cron
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin

# Job definition
0 2 * * * davidwu /usr/local/bin/emacsclient -e '(gptel-auto-workflow-run)' >> $HOME/.emacs.d/var/tmp/cron/auto-workflow.log 2>&1
```

**Verification:**
```bash
# Check what cron sees:
* * * * * env > /tmp/cron-env.txt 2>&1

# Test with minimal environment:
env -i PATH=/usr/bin:/bin HOME=$HOME /bin/bash -c 'which emacsclient'
```

### Variable Expansion in Crontab

Custom variables set in crontab do not expand in the command portion.

**Problem:** Logs were empty because `$LOGDIR` expanded to empty string.

**Root Cause:** Setting `LOGDIR=value` in crontab only sets it in cron's environment, not in the shell that executes the command.

**Broken:**
```cron
LOGDIR=$HOME/.emacs.d/var/tmp/cron
0 2 * * * davidwu emacsclient -e '(func)' >> $LOGDIR/auto-workflow.log 2>&1
```

**Fixed:**
```cron
0 2 * * * davidwu emacsclient -e '(func)' >> $HOME/.emacs.d/var/tmp/cron/auto-workflow.log 2>&1
```

## Emacs Integration

### Substring Out-of-Range Errors

When cron invokes Emacs functions that process git data, `substring` operations can fail if strings are empty or shorter than expected.

**Error:**
```
[auto-workflow] Cron error: (args-out-of-range 1 0 7)
```

**Affected locations in `gptel-tools-agent.el`:**

| Line | Code | Cause |
|------|------|-------|
| 114 | `(substring commit-hash 0 7)` | Empty git commit hash |
| 142 | `(substring (car o) 0 7)` | Orphan hash empty/short |
| 204-205 | `(substring staging-commit 0 7)` | Branch commits "none" or empty |
| 3414-3416 | Date parsing substring | Malformed date format |

**Solution - Length guard pattern:**

```elisp
;; Before (crashes on short strings):
(substring commit-hash 0 7)

;; After (safe):
(if (>= (length commit-hash) 7)
    (substring commit-hash 0 7)
  commit-hash)
```

**Solution - Date parsing with nil checks:**

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

## Infrastructure Setup

### Installation Script

The project includes `scripts/install-cron.sh` for easy cron deployment:

```bash
# Preview what will be installed
./scripts/install-cron.sh --dry-run

# Install cron jobs
./scripts/install-cron.sh
```

### Required Directories

Create these directories before cron jobs can write logs:

| Directory | Purpose |
|-----------|---------|
| `var/tmp/cron/` | Log output for all cron jobs |
| `var/tmp/experiments/` | Overnight experiment data |

```bash
mkdir -p var/tmp/cron var/tmp/experiments
```

### Scheduled Jobs

| Schedule | Job | Purpose |
|----------|-----|---------|
| Daily 2:00 AM | `auto-workflow-run` | Overnight experiments |
| Weekly Sunday 4:00 AM | `mementum-weekly-job` | Synthesis + decay |
| Weekly Sunday 5:00 AM | `instincts-weekly-job` | Evolution |

### Cron File Example

```cron
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin
HOME=/Users/davidwu

# Emacs daemon auto-start on reboot
@reboot /usr/local/bin/emacs --daemon >> /tmp/emacs-daemon.log 2>&1

# Daily auto-workflow at 2 AM
0 2 * * * /usr/local/bin/emacsclient -e '(gptel-auto-workflow-run)' >> $HOME/.emacs.d/var/tmp/cron/auto-workflow.log 2>&1

# Weekly synthesis on Sunday at 4 AM
0 4 * * 0 /usr/local/bin/emacsclient -e '(gptel-benchmark-mementum-weekly-job)' >> $HOME/.emacs.d/var/tmp/cron/mementum-weekly.log 2>&1
```

## Decision Pattern: Cron vs Emacs Timers

```
λ schedule(x).    cron(x) > emacs_timer(x)
                  | survives_restart(x) ∧ standard_unix(x)
                  | session_aware(x) → emacs_timer(x)
```

| Use Cron | Use Emacs Timer |
|----------|-----------------|
| Survives reboot | Session-aware notifications |
| Standard Unix tooling | Interactive prompts |
| Visible via `crontab -l` | Context-dependent triggers |
| Log rotation via external tools | While user is actively in Emacs |

## Monitoring

### View Logs

```bash
# Tail all cron logs
tail -f var/tmp/cron/*.log

# Check specific job
tail -f var/tmp/cron/auto-workflow.log

# System journal (systemd)
journalctl -u cron --since "today" | grep -E "davidwu|CMD"
```

### Common Log Patterns

**Success:**
```
[auto-workflow] Synced staging with main (origin/ -> 04948b5)
[auto-workflow] Found 3 orphan(s): 1 97974b8 97974b8
[auto-workflow] ⚠ Found 3 orphan commit(s) from previous run
```

**Error (pre-fix):**
```
[auto-workflow] Cron error: (args-out-of-range 1 0 7)
```

## Best Practices

1. **Always set PATH** in cron files - avoids "command not found" errors
2. **Use full paths** for commands when possible (e.g., `/usr/local/bin/emacsclient`)
3. **Use `$HOME` directly** instead of custom variables in crontab
4. **Add length guards** before substring operations in Emacs functions
5. **Test with minimal environment** before deploying:
   ```bash
   env -i PATH=/usr/bin:/bin HOME=$HOME /bin/bash -c 'your-command'
   ```
6. **Ensure Emacs daemon** is running before cron jobs execute (either via `@reboot` or systemd)
7. **Redirect both stdout and stderr** (`>> log 2>&1`) to capture all output

## Related

- [[emacs-daemon]] - Emacs daemon configuration and startup
- [[emacsclient]] - Client usage patterns and flags
- [[gptel-tools-agent]] - Automation functions invoked by cron
- [[logging]] - Log management and rotation
- [[systemd]] - Alternative to cron on Linux systems