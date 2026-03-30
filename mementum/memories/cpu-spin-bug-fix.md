# CPU Spin Bug - accept-process-output Last Argument

**Date:** 2026-03-30
**Status:** ✅ FIXED
**Severity:** CRITICAL - Caused 100% CPU spin and daemon unresponsive

## Problem

Daemon became completely unresponsive, spinning at 100% CPU with no child processes. Required force kill to recover.

## Root Cause

Previous "fix" actually **introduced** the bug:

```elisp
;; WRONG - Blocks and causes CPU spin
(accept-process-output process 0.1 nil nil)

;; CORRECT - Non-blocking poll
(accept-process-output process 0.1 nil t)
```

**The last argument controls blocking behavior:**
- `t` = Don't block, just check if input is available
- `nil` = Block until input arrives or timeout

## What Happened

1. Changed from `t` to `nil` intending to "fix blocking"
2. Actually made it **block** instead of non-blocking
3. Combined with `sit-for 0.01`, created a tight loop
4. Daemon consumed 100% CPU, became unresponsive

## Evidence

- `ps aux` showed daemon at 99.1-100% CPU
- No child processes running
- emacsclient commands hung
- No response to any commands
- Required `pkill -9` to stop

## The Fix

Restore `t` as the last argument:

```elisp
;; Poll with short timeout to avoid blocking indefinitely
(while (and (not done)
            (< (float-time (time-subtract (current-time) start-time)) timeout-seconds))
  ;; Use 0.1s timeout in accept-process-output with non-blocking flag
  ;; The 't' as last arg prevents indefinite blocking
  (accept-process-output process 0.1 nil t)
  ;; Small delay to prevent busy-waiting
  (sit-for 0.01))
```

## Verification

**Before fix:**
- Daemon at 100% CPU
- Unresponsive to emacsclient
- Required force kill

**After fix:**
- Daemon at 0.0% CPU when idle
- Responds to emacsclient immediately
- Timeout function works correctly

## Critical Lesson

**accept-process-output arguments:**

```elisp
(accept-process-output PROCESS SECS MICROSECS READ-ANYTHING)
```

| Argument | Meaning | Effect |
|----------|---------|--------|
| PROCESS | Process to wait for | nil = any process |
| SECS | Timeout in seconds | 0.1 = 100ms |
| MICROSECS | Additional microseconds | nil = 0 |
| READ-ANYTHING | What to read | nil = process output only |
| **LAST ARG** | **Blocking behavior** | **t = non-blocking, nil = BLOCKING** |

**THE LAST ARGUMENT IS CRITICAL:**
- `t` = **Non-blocking** (safe, won't hang)
- `nil` = **Blocking** (dangerous, can hang daemon)

## Lambda Pattern

```
λ accept-process-output-last-arg. t = non-blocking | nil = BLOCKING
λ cpu-spin. accept-process-output(nil) + tight-loop = 100% CPU
λ daemon-blocking. Never use accept-process-output with nil as last arg in loops
```

**Symbol:** ❌ critical-bug → ✅ correct-fix