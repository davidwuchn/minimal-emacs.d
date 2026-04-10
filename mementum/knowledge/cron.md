---
title: Cron Scheduling for Emacs Workflows
status: active
category: knowledge
tags: [cron, emacs, scheduling, automation, bash]
---

# Cron Scheduling for Emacs Workflows

## Overview

Cron is the standard Unix tool for scheduling recurring tasks. When combined with Emacs in daemon mode, it enables robust, persistent automation that survives restarts and system reboots. This page synthesizes practical patterns and troubleshooting knowledge for cron-based Emacs workflows.

## Why Use Cron Over Emacs Timers

| Feature | Cron | Emacs Timer |
|---------|------|-------------|
| Survives restart | ✓ Yes | ✗ Lost on exit |
| Standard Unix tool | ✓ Yes | Emacs-specific |
| Visibility | `crontab -l` | Internal only |
| Log management | Easy file redirection | Manual |
| System startup | Native via @reboot | Requires init script |

**Use cron for:**
- Overnight batch processing
- Scheduled experiments
- Weekly synthesis tasks
- Cleanup jobs

**Keep in Emacs timers:**
- Session-aware notifications (user is active)
- Interactive prompts
- Context-dependent triggers

## Prerequisites

### 1. Emacs Daemon Running

Cron jobs should communicate with Emacs via `emacsclient`:

```bash
# Start daemon manually (once):
emacs --daemon

# Or in cron on reboot:
@reboot emacs --daemon
```

### 2. Directory Structure

Create required directories before cron jobs run:

```bash
mkdir -p ~/.emacs.d/var/tmp/cron
mkdir -p ~/.emacs.d/var/tmp/experiments
```

The `var/tmp` prefix keeps temporary data separate from persistent configuration.

### 3. Install Cron Jobs

Use an installation script for reproducibility:

```bash
./scripts/install-cron.sh --dry-run   # Preview what will be installed
./scripts/install-cron.sh             # Actually install
```

## Common Problems & Solutions

### Problem 1: Command Not Found (Missing PATH)

**Symptom:**
```
/bin/bash: emacsclient: command not found
```

**Root Cause:** Cron runs with a minimal environment—only `/usr/bin:/bin` by default. Your shell's `$PATH` from `.bashrc` or `.zshrc` is not loaded.

**Solution:** Explicitly set `PATH` at the top of your cron file:

```cron
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/opt/homebrew/bin
```

**Verification:**

```bash
# See what cron sees:
* * * * * env > /tmp/cron-env.txt 2>&1

# Compare with your interactive shell:
diff /tmp/cron-env.txt <(env)

# Test with minimal environment:
env -i PATH=/usr/bin:/bin HOME=$HOME /bin/bash -c 'which emacsclient'
```

### Problem 2: Variable Expansion in Redirection

**Symptom:** Cron jobs run but logs are empty at expected path.

**Root Cause:** In crontab, variable assignment (`VAR=value`) sets the variable in cron's environment, but the shell executing your command doesn't inherit it. The variable expands to an empty string.

```cron
# BROKEN: LOGDIR is empty in the shell running the command
LOGDIR=$HOME/.emacs.d/var/tmp/cron
0 2 * * * emacsclient -e '(gptel-auto-workflow-run)' >> $LOGDIR/auto-workflow.log 2>&1
```

**Solution:** Use `$HOME` directly in the command:

```cron
# CORRECT: $HOME is expanded by cron before shell execution
0 2 * * * emacsclient -e '(gptel-auto-workflow-run)' >> $HOME/.emacs.d/var/tmp/cron/auto-workflow.log 2>&1
```

**Detection:**

```bash
journalctl -u cron --since "today" | grep -E "davidwu|CMD"
```

### Problem 3: Args-Out-of-Range in Elisp Code

**Symptom:**
```
[auto-workflow] Cron error: (args-out-of-range 1 0 7)
```

**Root Cause:** Elisp `substring` calls assume strings are long enough, but external data (git output, file contents) may be empty or malformed.

**Solution:** Add length guards before substring operations:

```elisp
;; Before (crashes on short strings):
(substring commit-hash 0 7)

;; After (safe):
(if (>= (length commit-hash) 7)
    (substring commit-hash 0 7)
  commit-hash)
```

For date parsing with `encode-time`:

```elisp
;; Before:
(let* ((date-str (match-string 1 content))
       (last-tested (encode-t
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-rQbC12.txt. Use Read tool if you need more]...