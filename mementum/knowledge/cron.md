---
title: Cron Scheduling in Emacs Workflow
status: active
category: knowledge
tags: [cron, emacs, scheduling, automation, devops]
---

# Cron Scheduling in Emacs Workflow

This document covers the setup, integration, and troubleshooting of cron-based scheduling for Emacs automation workflows.

## Overview

Cron is used to schedule recurring tasks in the Emacs workflow system, particularly for the auto-workflow that runs autonomous experiments, weekly synthesis, and instinct evolution. Unlike Emacs timers, cron provides persistence across restarts and standard Unix integration.

## Cron File Structure

### Basic Format

```cron
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin
LOGDIR=$HOME/.emacs.d/var/tmp/cron

# Environment variables must use $HOME directly, not custom variables
# Correct:
0 2 * * * emacsclient -e '(gptel-auto-workflow-run)' >> $HOME/.emacs.d/var/tmp/cron/auto-workflow.log 2>&1

# Wrong - variable won't expand in shell:
LOGDIR=$HOME/.emacs.d/var/tmp/cron
0 2 * * * emacsclient ... >> $LOGDIR/auto-workflow.log 2>&1
```

### Scheduled Jobs

| Schedule | Job Name | Purpose | Function |
|----------|----------|---------|----------|
| Daily 2:00 AM | auto-workflow-run | Overnight experiments | `gptel-auto-workflow-run` |
| Weekly Sun 4:00 AM | mementum-weekly-job | Synthesis + decay | `gptel-benchmark-mementum-weekly-job` |
| Weekly Sun 5:00 AM | instincts-weekly-job | Evolution | `gptel-benchmark-instincts-weekly-job` |
| @reboot | emacs-daemon-start | Start Emacs daemon | `emacs --daemon` |

### Example cron.d File

```cron
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin

# Daily auto-workflow at 2 AM
0 2 * * * davidwu emacsclient -e '(gptel-auto-workflow-run)' >> $HOME/.emacs.d/var/tmp/cron/auto-workflow.log 2>&1

# Weekly synthesis on Sunday at 4 AM
0 4 * * 0 davidwu emacsclient -e '(gptel-benchmark-mementum-weekly-job)' >> $HOME/.emacs.d/var/tmp/cron/weekly.log 2>&1

# Weekly instinct evolution on Sunday at 5 AM
0 5 * * 0 davidwu emacsclient -e '(gptel-benchmark-instincts-weekly-job)' >> $HOME/.emacs.d/var/tmp/cron/weekly.log 2>&1
```

## Common Issues and Fixes

### Issue 1: PATH Not Found

**Symptom:**
```
/bin/bash: emacsclient: command not found
```

**Cause:** Cron runs with minimal environment, only `/usr/bin:/bin` by default.

**Solution:** Explicitly set PATH in the cron file:

```cron
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin
```

**Verification:**
```bash
# See what cron sees:
* * * * * env > /tmp/cron-env.txt 2>&1

# Test with minimal environment:
env -i PATH=/usr/bin:/bin HOME=$HOME /bin/bash -c 'which emacsclient'
```

### Issue 2: Variable Expansion

**Symptom:** Logs are empty or file is created in wrong location.

**Cause:** Custom variables like `LOGDIR` set in crontab don't expand in the shell that runs the command.

**Solution:** Use `$HOME` directly instead of custom variables:

```cron
# Wrong:
LOGDIR=$HOME/.emacs.d/var/tmp/cron
0 2 * * * emacsclient ... >> $LOGDIR/workflow.log 2>&1

# Correct:
0 2 * * * emacsclient ... >> $HOME/.emacs.d/var/tmp/cron/workflow.log 2>&1
```

### Issue 3: args-out-of-range Error

**Symptom:**
```
[auto-workflow] Cron error: (args-out-of-range 1 0 7)
```

**Cause:** `substring` operations on empty or short strings in `gptel-tools-agent.el`.

**Affected locations:**
- Line 114: `(substring commit-hash 0 7)` - empty git commit hash
- Line 142: `(substring (car o) 0 7)` - orphan hash empty/short
- Lines 204-205: Branch commits are "none" or empty
- Lines 3414-3416: Malformed date format

**Solution:** Add length guards before substring operations:

```elisp
;; Before (crashes on short strings):
(substring commit-hash 0 7)

;; After (safe):
(if (>= (length commit-hash) 7)
    (substring commit-hash 0 7)
  commit-hash)
```

For date parsing, also add nil checks:

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

**Files modified:** `lisp/modules/gptel-tools-agent.el`

## Infrastructure Setup

### Directory Structure

```bash
mkdir -p var/tmp/cron/
mkdir -p var/tmp/experiments/
```

### Installation Script

Use `scripts/install-cron.sh` for easy installation:

```bash
# Preview changes without applying
./scripts/install-cron.sh --dry-run

# Install cron jobs
./scripts/install-cron.sh
```

### Log Monitoring

```bash
# Watch all cron logs
tail -f var/tmp/cron/*.log

# Watch specific log
tail -f var/tmp/cron/auto-workflow.log

# Check for errors
grep -i error var/tmp/cron/*.log
```

## Emacs Integration Pattern

### Why Cron Over Emacs Timers?

| Feature | Cron | Emacs Timer |
|---------|------|-------------|
| Survives restart | ✅ | ❌ |
| Standard Unix tool | ✅ | ❌ |
| Easy log management | ✅ | ❌ |
| `crontab -l` visibility | ✅ | ❌ |
| Session-aware | ❌ | ✅ |
| Interactive prompts | ❌ | ✅ |

**Decision rule:**
- Use **cron** for: autonomous operations, scheduled experiments, cleanup
- Use **Emacs timer** for: session-aware notifications, context-dependent triggers

### Prerequisites

1. Emacs daemon must be running:
   ```bash
   emacs --daemon
   ```

2. Or start daemon in cron:
   ```cron
   @reboot emacs --daemon
   ```

### Lambda (Design Rule)

```
λ schedule(x).    cron(x) > emacs_timer(x)
                  | survives_restart(x) ∧ standard_unix(x)
                  | session_aware(x) → emacs_timer(x)
```

## Debugging Cron Jobs

### Check Cron Status

```bash
# List current crontab
crontab -l

# Edit crontab
crontab -e

# Check system cron logs
journalctl -u cron --since "today"

# Check specific user cron
grep -E "davidwu|CMD" /var/log/syslog
```

### Test Commands Manually

```bash
# Test Emacs function directly
emacsclient -e '(gptel-auto-workflow-run)'

# Test with cron environment
env -i PATH=/usr/bin:/bin HOME=$HOME /bin/bash -c 'emacsclient -e "(message \"test\")"'
```

## Best Practices

1. **Always set PATH** in cron files
2. **Use full paths** for commands when possible
3. **Use `$HOME` directly** instead of custom variables
4. **Add length guards** before string operations in called functions
5. **Log output** to files for debugging
6. **Test with minimal env** before deploying
7. **Monitor logs** regularly for errors

## Related

- [Emacs Daemon](./emacs-daemon.md)
- [Auto-Workflow](./auto-workflow.md)
- [gptel-tools-agent](./gptel-tools-agent.md)
- [Weekly Synthesis](./weekly-synthesis.md)
- [Instinct Evolution](./instinct-evolution.md)
- [Cron Troubleshooting](./cron-troubleshooting.md)
- [Emacs Timers](./emacs-timers.md)

---

*Last updated: 2026-03-30*
*Status: Active - regularly used for autonomous operations*