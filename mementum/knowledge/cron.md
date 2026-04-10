---
title: Cron Scheduling for Emacs Automation
status: active
category: knowledge
tags: [cron, emacs, automation, scheduling, devops, infrastructure]
---

# Cron Scheduling for Emacs Automation

This page documents the cron-based scheduling infrastructure for Emacs automation, including common pitfalls, fixes, and best practices for running Emacs functions on a schedule.

## Overview

Cron is the standard Unix scheduler used to trigger Emacs functions at specific times. This approach is preferred over Emacs timers for tasks that must survive system restarts and operate independently of user sessions.

| Feature | Cron | Emacs Timer |
|---------|------|-------------|
| Survives restart | ✓ | ✗ |
| Standard Unix tool | ✓ | Emacs-specific |
| Logs to files | ✓ | Manual handling |
| Visibility (`crontab -l`) | ✓ | Internal only |
| Session awareness | ✗ | ✓ |

## Basic Cron Configuration

### Required Environment Variables

Cron runs with a minimal environment. Always set explicit `PATH` and `SHELL`:

```cron
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin
LOGDIR=/Users/davidwu/.emacs.d/var/tmp/cron
```

### Common Cron File Locations

- User crontab: `crontab -e`
- System cron: `/etc/cron.d/` (Debian/Ubuntu)
- Launchd: `~/Library/LaunchAgents/` (macOS)

### Installation Script

Create `scripts/install-cron.sh` for easy deployment:

```bash
#!/bin/bash
set -e

CRON_DIR="$(cd "$(dirname "$0")/../cron.d" && pwd)"
CRON_USER="davidwu"
CRON_FILE="$CRON_DIR/auto-workflow"

install_cron() {
    local target="/etc/cron.d/auto-workflow"
    echo "Installing $CRON_FILE to $target..."
    sudo cp "$CRON_FILE" "$target"
    sudo chmod 644 "$target"
}

case "${1:-}" in
    --dry-run)
        echo "Would install: $CRON_FILE"
        cat "$CRON_FILE"
        ;;
    --install)
        install_cron
        ;;
    *)
        echo "Usage: $0 --dry-run|--install"
        exit 1
        ;;
esac
```

## Cron File Example

```cron
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin
LOGDIR=/Users/davidwu/.emacs.d/var/tmp/cron

# Ensure log directory exists
@replay mkdir -p $LOGDIR

# Daily at 2:00 AM - Auto workflow
0 2 * * * davidwu /usr/local/bin/emacsclient -e '(gptel-auto-workflow-run)' >> $LOGDIR/auto-workflow.log 2>&1

# Weekly Sunday at 4:00 AM - Mementum synthesis
0 4 * * 0 davidwu /usr/local/bin/emacsclient -e '(gptel-benchmark-mementum-weekly-job)' >> $LOGDIR/mementum-weekly.log 2>&1

# Weekly Sunday at 5:00 AM - Instincts evolution
0 5 * * 0 davidwu /usr/local/bin/emacsclient -e '(gptel-benchmark-instincts-weekly-job)' >> $LOGDIR/instincts-weekly.log 2>&1
```

## Scheduled Jobs Reference

| Schedule | Time | Function | Purpose |
|----------|------|----------|---------|
| Daily | 2:00 AM | `gptel-auto-workflow-run` | Overnight experiments |
| Weekly | Sunday 4:00 AM | `gptel-benchmark-mementum-weekly-job` | Synthesis + decay |
| Weekly | Sunday 5:00 AM | `gptel-benchmark-instincts-weekly-job` | Evolution |
| Daily | 4:00 AM | `my/cleanup-temp-files` | Cleanup temp files |

## Infrastructure Setup

### Required Directories

```bash
mkdir -p var/tmp/cron
mkdir -p var/tmp/experiments
```

### Log Monitoring

```bash
# Follow all cron logs
tail -f var/tmp/cron/*.log

# Check specific log
tail -f var/tmp/cron/auto-workflow.log
```

## Common Issues and Fixes

### Issue 1: PATH Not Found

**Symptom:**
```
/bin/bash: emacsclient: command not found
```

**Cause:** Cron has minimal PATH (`/usr/bin:/bin` only)

**Fix:** Set explicit PATH in cron file:

```cron
PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin
```

**Verification:**

```bash
# Test what cron sees
* * * * * env > /tmp/cron-env.txt 2>&1

# Compare with interactive shell
diff /tmp/cron-env.txt <(env)

# Test with minimal environment
env -i PATH=/usr/bin:/bin HOME=$HOME /bin/bash -c 'which emacsclient'
```

### Issue 2: Variable Expansion Bug

**Symptom:** Logs are empty, cron runs but output is lost

**Cause:** Cron variables set in crontab don't expand in the shell command:

```cron
# WRONG - LOGDIR not available in shell
LOGDIR=$HOME/.emacs.d/var/tmp/cron
0 2 * * * echo "test" >> $LOGDIR/test.log
```

**Fix:** Use `$HOME` directly or environment variable in the command:

```cron
# CORRECT - use $HOME directly
0 2 * * * echo "test" >> $HOME/.emacs.d/var/tmp/cron/test.log
```

**Detection:**

```bash
journalctl -u cron --since "today" | grep -E "davidwu|CMD"
```

### Issue 3: args-out-of-range Error

**Symptom:**
```
[auto-workflow] Cron error: (args-out-of-range 1 0 7)
```

**Cause:** Substring operations on empty or short strings in `gptel-tools-agent.el`

**Affected locations:**
- Line 114: `(substring commit-hash 0 7)` - empty git commit hash
- Line 142: `(substring (car o) 0 7)` - orphan hash empty/short
- Lines 204-205: Branch commits "none" or empty
- Lines 3414-3416: Malformed date format parsing

**Fix:** Add length guards before substring operations:

```elisp
;; Before (crashes on short strings):
(substring commit-hash 0 7)

;; After (safe):
(if (>= (length commit-hash) 7)
    (substring commit-hash 0 7)
  commit-hash)
```

For date parsing with nil checks:

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

**Verification:** After fix, workflow runs without errors:
```
[auto-workflow] Synced staging with main (origin/ -> 04948b5)
[auto-workflow] Found 3 orphan(s): 1 97974b8 97974b8
[auto-workflow] ⚠ Found 3 orphan commit(s) from previous run
```

## Decision Framework

When to use cron vs Emacs timers:

```
λ schedule(x).    cron(x) > emacs_timer(x)
                  | survives_restart(x) ∧ standard_unix(x)
                  | session_aware(x) → emacs_timer(x)
```

**Use Cron for:**
- Tasks that must run overnight
- Tasks that must survive system restart
- Integration with standard Unix tooling

**Use Emacs Timer for:**
- Session-aware notifications (while user is working)
- Interactive prompts
- Context-dependent triggers
- Quick testing during development

## Related

- [Emacs Daemon](./emacs-daemon.md) - Running Emacs as a background service
- [GPTel Auto Workflow](./gptel-auto-workflow.md) - Automated git workflow using LLMs
- [Elisp Error Handling](./elisp-error-handling.md) - Debugging techniques for Emacs Lisp
- [Environment Variables](./environment-variables.md) - PATH and shell configuration
- [Cron Expression Syntax](https://man7.org/linux/man-pages/man5/crontab.5.html) - Full cron syntax reference