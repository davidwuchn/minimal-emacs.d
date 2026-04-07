---
title: Cron-Based Scheduling for Auto-Workflow
status: active
category: knowledge
tags: [cron, scheduling, daemon, macos, linux]
related: [mementum/knowledge/emacs-daemon-patterns.md]
---

# Cron-Based Scheduling for Auto-Workflow

Patterns for scheduling auto-workflow, researcher, and mementum tasks via cron.

## Platform-Specific Schedules

### macOS (Interactive Use)

Schedule during daylight hours when user is typically active:

```
0 10,14,18 * * * auto-workflow  # 10AM, 2PM, 6PM (3 runs/day)
0 */4 * * * research            # Every 4 hours
0 4 * * 0 mementum              # Sunday 4AM
0 5 * * 0 instincts             # Sunday 5AM
```

### Linux/Pi5 (24/7 Headless)

Higher frequency for continuous operation:

```
0 23,3,7,11,15,19 * * * auto-workflow  # 6 runs/day
0 */4 * * * research
0 4 * * 0 mementum
0 5 * * 0 instincts
```

## Cron Environment Setup

**PATH Issues:**

Cron has minimal environment. Must set PATH explicitly:

```cron
SHELL=/bin/bash
PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$HOME/.emacs.d/bin
```

**Variable Expansion:**

Cron doesn't expand `$HOME` in some contexts. Use absolute paths or set in wrapper:

```bash
# Bad - may not expand
0 10 * * * $HOME/.emacs.d/scripts/run.sh

# Good - explicit path
0 10 * * * /Users/davidwu/.emacs.d/scripts/run.sh
```

## XDG_RUNTIME_DIR for Linux

Linux needs XDG_RUNTIME_DIR for some tools:

```cron
XDG_RUNTIME_DIR=/run/user/1000
```

Set dynamically in install script:

```bash
if [ "$machine" = "pi5" ] || [ "$machine" = "linux" ]; then
    echo "XDG_RUNTIME_DIR=/run/user/$(id -u)"
fi
```

## Common Errors and Fixes

### args-out-of-range

**Cause:** Script expects arguments but cron passes none.

**Fix:** Provide default in script:

```bash
ACTION="${1:-auto-workflow}"
```

### PATH Not Set

**Symptom:** `emacsclient: command not found`

**Fix:** Set PATH in crontab or use absolute path to emacsclient.

### Variable Not Expanded

**Symptom:** `$HOME` appears literally in error messages.

**Fix:** Expand in wrapper script or use `%HOMEPATH%` on Windows.

## Log Directory Setup

Ensure log directory exists before cron runs:

```cron
@reboot mkdir -p $HOME/.emacs.d/var/tmp/cron
```

## Installation Script

**Location:** `scripts/install-cron.sh`

### Usage

```bash
# Install crontab (auto-detect platform)
./scripts/install-cron.sh

# Preview without installing
./scripts/install-cron.sh --dry-run

# Render crontab to stdout
./scripts/install-cron.sh --render
```

### Machine Detection

Script auto-detects machine type:

| Machine | Detection | Schedule |
|---------|-----------|----------|
| macOS | `uname -s = "Darwin"` | 10AM, 2PM, 6PM |
| Pi5 | hostname contains `pi5\|raspberrypi\|onepi` | 6 runs/day |
| Linux | `uname -s = "Linux"` | Same as Pi5 |
| Single | Fallback | Every 4 hours |

### Section-Based Rendering

Cron template (`cron.d/auto-workflow`) has sections:

```
# -----------------------------------------------------------------
# PI5: Linux systemd (24/7 headless) - SECTION: pi5
# -----------------------------------------------------------------
#0 23,3,7,11,15,19 * * * ...

# -----------------------------------------------------------------
# MACOS: Daylight hours (interactive use) - SECTION: macos
# -----------------------------------------------------------------
#0 10,14,18 * * * ...
```

Script:
1. Finds section matching machine type
2. Uncomments lines starting with `#0 ` in that section
3. Other sections stay commented
4. Injects PATH and XDG_RUNTIME_DIR

### PATH Differences by Platform

```bash
# macOS (homebrew)
PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin

# Linux
PATH=/usr/local/bin:/usr/bin:/bin
```

### Log Directory

Script creates on install:

```bash
mkdir -p var/tmp/cron var/tmp/experiments
```

And via crontab on reboot:

```cron
@reboot mkdir -p $HOME/.emacs.d/var/tmp/cron
```

## Verification

After installing crontab:

```bash
./scripts/run-auto-workflow-cron.sh status
```

Check logs:

```bash
tail -f var/tmp/cron/auto-workflow.log
```

## Related

- `mementum/knowledge/emacs-daemon-patterns.md` - Daemon server name isolation
- `mementum/memories/cron-scheduling-pattern.md` - Original pattern
- `mementum/memories/cron-path-environment.md` - PATH issues
- `mementum/memories/cron-variable-expansion.md` - Variable expansion bug
- `mementum/memories/cron-args-out-of-range-fix.md` - Default arguments fix