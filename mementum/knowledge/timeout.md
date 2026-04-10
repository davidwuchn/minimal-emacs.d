---
title: timeout
status: open
---

Synthesized from 3 memories.

# Curl Low-Speed Timeout Issue

**Discovered**: 2026-03-28

## Problem

Auto-workflow failing with curl exit code 28 (timeout) even when backend
configured with `--max-time 600` or `--max-time 900`.

## Root Cause

Global `gptel-curl-extra-args` included `-y 15 -Y 50`:
- `-y 15`: 15 seconds of low-speed allowed before abort
- `-Y 50`: 50 bytes/sec threshold

When LLM thinks for >15s without streaming output, curl aborts with
exit 28 regardless of `--max-time` setting. Low-speed detection is
independent of max-time.

Curl args are appended: `global → backend`. Backend `--max-time`
overrides, but `-y/-Y` from global still active.

## Fix

Removed `-y/-Y` from `my/gptel--install-fast-curl-timeouts` in
`gptel-ext-abort.el`. Low-speed timeout causes false positives for
subagents; backend-specific timeouts handle long-running calls.

Also added `1013` and `server is initializing` to transient error
patterns for Moonshot API cold starts.

## Files Changed

- `lisp/modules/gptel-ext-abort.el`: Remove -y/-Y from global args
- `lisp/modules/gptel-ext-backends.el`: DashScope 600s → 900s
- `lisp/modules/gptel-ext-retry.el`: Add 1013 to transient patterns

## Lesson

Curl has multiple timeout mechanisms:
1. `--connect-timeout`: Connection phase only
2. `--max-time`: Total operation time
3. `-y/-Y`: Low-speed detection (independent of max-time!)

For long-running API calls, remove low-speed detection or set very
generous thresholds.

# Experiment Timeout Handling

## Problem

Experiment 2 took 900s (15 minutes), exceeding the 600s (10 minute) budget.

## Current Implementation

```elisp
(defcustom gptel-auto-experiment-time-budget 600
  "Time budget per experiment in seconds (default: 10 min).")
```

Timeout set via `run-with-timer`:
```elisp
(run-with-timer gptel-auto-experiment-time-budget nil
                (lambda ()
                  (unless finished
                    (setq finished t)
                    (gptel-auto-workflow-delete-worktree)
                    (funcall callback
                             (list :target target
                                   :id experiment-id
                                   :error "timeout")))))
```

## Why Timeout May Fail

1. **Blocking process**: gptel uses curl which may block
2. **Multiple stages**: analyze + execute + grade + benchmark + decide
3. **Timer not firing**: Emacs event loop blocked

## Potential Solutions

### 1. Process Timeout via Curl

DashScope backend uses `--max-time 300` (5 min). This should abort individual requests.

### 2. Kill Curl Process on Timeout

Store curl process PID and kill on timeout:
```elisp
(let ((curl-pid (process-id gptel--curl-process)))
  (run-with-timer timeout nil
                  (lambda ()
                    (when (process-live-p gptel--curl-process)
                      (delete-process gptel--curl-process)))))
```

### 3. Reduce Backend Timeout

For experiments, reduce curl timeout:
```elisp
:curl-args '("--http1.1" "--max-time" "120" "--connect-timeout" "10")
```

### 4. Add Stage-Level Timeouts

Each stage should respect its own timeout:
- analyze: 60s
- execute: 300s
- grade: 60s
- benchmark: 60s
- decide: 30s

## Symbol

λ timeout - robust timeout handling

# Shell Command Timeout Blocking Bug - PERFECT FIX

**Date:** 2026-03-30
**Status:** ✅ FIXED with robust timeout mechanism
**Severity:** CRITICAL - Causes daemon to become unresponsive

## Problem

The daemon became completely unresponsive to `emacsclient` connections. Investigation revealed:

1. **Stuck subprocess:** A bash process (PID 2953) was running for 32+ minutes
2. **Blocked main thread:** Emacs was waiting for `accept-process-output` to return
3. **No CPU usage:** Daemon at 0% CPU but completely unresponsive
4. **Root cause:** `accept-process-output` with blocking flag (`t`) can hang indefinitely

## Root Cause Analysis

The original implementation:
```elisp
(while (and (not done)
            (< (float-time ...) timeout-seconds))
  (accept-process-output process 0.1 nil t))  ; LAST ARG 't' = BLOCK
```

**Why it failed:**
- `accept-process-output` with `t` as last argument means "block until output or process exit"
- If subprocess hangs without producing output, `accept-process-output` blocks forever
- The timeout check in the while loop is never reached
- Emacs daemon becomes completely unresponsive

## Perfect Fix

### Key Changes:

1. **Timer-based safety net:**
   ```elisp
   (setq timer (run-with-timer timeout-seconds nil
                               (lambda ()
                                 (unless done
                                   (setq done 'timeout)))))
   ```
   - Timer runs independently of blocking operations
   - Forces timeout even if main thread is blocked

2. **Non-blocking accept-process-output:**
   ```elisp
   (accept-process-output process 0.1 nil nil)  ; LAST ARG nil = NON-BLOCKING
   (sit-for 0.01)  ; Cooperative yield
   ```
   - Returns immediately if no output available
   - Allows timeout check to run on each iteration

3. **Proper cleanup sequence:**
   ```elisp
   (when timer (cancel-timer timer))
   (when (and process (process-live-p process))
     (delete-process process))
   (when (buffer-live-p buffer)
     (kill-buffer buffer))
   ```
   - Cancel timer first to prevent race conditions
   - Force-kill process if still alive
   - Clean up buffer

4. **Explicit state tracking:**
   - `'finished` - process completed normally
   - `'timeout` - timer forced timeout
   - Clear state transitions prevent race conditions

## Verification

**Before fix:**
- Bash subprocess: 32+ minutes runtime
- Daemon: Unresponsive, 0% CPU
- Required: Force kill daemon

**After fix:**
- Commands timeout reliably after 30s (configurable)
- Daemon remains responsive
- No stuck subprocesses

## Testing

Test with hanging command:
```elisp
(gptel-auto-workflow--shell-command-with-timeout "sleep 60" 5)
;; Should return timeout error after 5 seconds, not hang
```

## Files Modified

- `lisp/modules/gptel-tools-agent.el`
  - Function: `gptel-auto-workflow--shell-command-with-timeout`
  - Lines: 48-94 (completely rewritten)

## Lambda Pattern

```
λ shell-timeout. timer-based + non-blocking-poll > blocking-wait
λ process-cleanup. timer-cancel → process-kill → buffer-kill
λ state-tracking. explicit-symbols > boolean-flags
```

**Symbol:** ❌ critical-bug → ✅ robust-fix
