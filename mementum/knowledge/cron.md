---
title: cron
status: open
---

Synthesized from 5 memories.

# Cron args-out-of-range Error Fix

**Date:** 2026-03-30
**Status:** ✅ Fixed

## Problem

Cron jobs were failing with error: `(args-out-of-range 1 0 7)`

This appeared in the Messages buffer as:
```
[auto-workflow] Cron error: (args-out-of-range 1 0 7)
```

## Root Cause

Multiple `substring` calls in `gptel-tools-agent.el` were trying to extract 7-character substrings from strings that could be empty or shorter than 7 characters:

1. **Line 114:** `(substring commit-hash 0 7)` - when git returns empty commit hash
2. **Line 142:** `(substring (car o) 0 7)` - when orphan hash is empty/short
3. **Lines 204-205:** `(substring staging-commit 0 7)` and `(substring main-commit 0 7)` - when branch commits are "none" or empty
4. **Lines 3414-3416:** Date parsing with `(substring date-str ...)` - when date format is malformed

## Solution

Added length guards before all substring operations:

```elisp
;; Before (would crash on short strings):
(substring commit-hash 0 7)

;; After (safe):
(if (>= (length commit-hash) 7)
    (substring commit-hash 0 7)
  commit-hash)
```

For date parsing, also added nil check for the computed age:
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

## Files Modified

- `lisp/modules/gptel-tools-agent.el`
  - Lines 114, 142, 204-205, 3414-3416

## Verification

After fix, `gptel-auto-workflow-cron-safe` runs without errors:
```
[auto-workflow] Synced staging with main (origin/ -> 04948b5)
[auto-workflow] Found 3 orphan(s): 1 97974b8 97974b8
[auto-workflow] ⚠ Found 3 orphan commit(s) from previous run
```

**Symbol:** ❌ mistake → ✅ win


💡 cron-infrastructure-autonomous

## Problem
Gap analysis showed autonomous operation infrastructure missing:
- No cron scheduling for overnight experiments
- Weekly synthesis not wired to cron
- var/tmp/experiments/ directory missing

## Solution
1. Created `scripts/install-cron.sh` for easy cron installation
2. Updated `cron.d/auto-workflow` with weekly synthesis job
3. Created required directories: var/tmp/cron/, var/tmp/experiments/

## Scheduled Jobs
| Daily 2:00 AM | auto-workflow-run | Overnight experiments |
| Weekly Sun 4:00 AM | mementum-weekly-job | Synthesis + decay |
| Weekly Sun 5:00 AM | instincts-weekly-job | Evolution |

## Install
```bash
./scripts/install-cron.sh --dry-run   # Preview
./scripts/install-cron.sh             # Install
```

## Logs
`tail -f var/tmp/cron/*.log`

# Cron PATH Environment Issue

**Date:** 2026-03-28
**Source:** Fixing workflow cron jobs

## Problem

Cron jobs fail with:
```
/bin/bash: emacsclient: command not found
```

## Root Cause

Cron runs with minimal environment:
- No `$PATH` from user shell
- No `.bashrc` or `.zshrc` loaded
- Only `/usr/bin:/bin` available

## Solution

Add explicit `PATH` to cron file:

```cron
SHELL=/bin/bash
PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin
```

## Verification

```bash
# Check what cron sees:
* * * * * env > /tmp/cron-env.txt 2>&1

# Compare with interactive shell:
diff /tmp/cron-env.txt <(env)
```

## Best Practices

1. **Always set PATH** in cron files
2. **Use full paths** for commands when possible
3. **Test with minimal env:**
   ```bash
   env -i PATH=/usr/bin:/bin HOME=$HOME /bin/bash -c 'which emacsclient'
   ```

## Related Files

- `cron.d/auto-workflow`
- `cron.d/auto-workflow-pi5`
- Fix: commit `0b3a4da`

**Symbol:** 💡 insight | ✅ win


# Cron-Based Scheduling for Emacs

**Date:** 2026-03-23
**Category:** pattern
**Tags:** cron, scheduling, emacs, daemon

## Pattern

Use cron for scheduled Emacs tasks instead of Emacs timers.

## Why

| Cron | Emacs Timer |
|------|-------------|
| ✓ Survives restart | ✗ Lost on exit |
| ✓ Standard Unix | Emacs-specific |
| ✓ Easy logs | Manual handling |
| ✓ `crontab -l` visibility | Inside Emacs |

## How

```cron
# cron.d/project
SHELL=/bin/bash
LOGDIR=~/.emacs.d/var/tmp/cron

@reboot mkdir -p $LOGDIR
0 2 * * * emacsclient -e '(my-scheduled-function)' >> $LOGDIR/project.log 2>&1
```

## Prerequisites

- Emacs daemon running: `emacs --daemon`
- Or start in cron: `@reboot emacs --daemon`

## Use Cases

| Task | Schedule | Function |
|------|----------|----------|
| Auto-workflow | Daily 2 AM | `gptel-auto-workflow-run` |
| Weekly evolution | Sunday 3 AM | `gptel-benchmark-instincts-weekly-job` |
| Cleanup | Daily 4 AM | `my/cleanup-temp-files` |

## Keep in Emacs Timer

- Session-aware notifications (while user is working)
- Interactive prompts
- Context-dependent triggers

## Lambda

```
λ schedule(x).    cron(x) > emacs_timer(x)
                  | survives_restart(x) ∧ standard_unix(x)
                  | session_aware(x) → emacs_timer(x)
```

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