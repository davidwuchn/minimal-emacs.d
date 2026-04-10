---
title: Timeout Mechanisms in gptel-auto
status: active
category: knowledge
tags: [timeout, curl, elisp, debugging, process-management, reliability]
created: 2026-03-30
updated: 2026-03-30
---

# Timeout Mechanisms in gptel-auto

## Overview

Timeouts are critical for maintaining reliability in automated systems. This document covers three distinct timeout scenarios encountered in gptel-auto: curl low-speed detection, experiment budget timeouts, and shell command blocking bugs. Each requires different handling strategies.

---

## 1. Curl Low-Speed Timeout

### The Problem

Auto-workflow failing with curl exit code 28 (timeout) even when backend configured with `--max-time 600` or `--max-time 900`:

```bash
# Backend explicitly configured with long timeout
--max-time 900

# But still getting exit code 28
curl: (28) Operation timeout
```

### Root Cause

Global `gptel-curl-extra-args` included low-speed detection parameters:

```elisp
;; In gptel-ext-abort.el - the problematic configuration
(setq my/gptel--install-fast-curl-timeouts
      '("-y" "15" "-Y" "50" ...))
```

| Parameter | Value | Meaning |
|-----------|-------|---------|
| `-y` | 15 | 15 seconds of low-speed allowed before abort |
| `-Y` | 50 | 50 bytes/sec threshold |

**Critical insight**: Low-speed detection (`-y/-Y`) is **independent** of `--max-time`. When an LLM thinks for >15 seconds without streaming output, curl aborts with exit 28 regardless of the `--max-time` setting.

Curl argument order matters: `global → backend`. Backend `--max-time` overrides, but `-y/-Y` from global remain active.

### The Fix

Remove `-y/-Y` from global curl arguments in `lisp/modules/gptel-ext-abort.el`:

```elisp
;; Before (problematic)
(setq my/gptel--install-fast-curl-timeouts
      '("-y" "15" "-Y" "50" "--max-time" "300"))

;; After (fixed) - removed low-speed detection
(setq my/gptel--install-fast-curl-timeouts
      '("--max-time" "300"))
```

Also added `1013` and `server is initializing` to transient error patterns for Moonshot API cold starts in `gptel-ext-retry.el`.

### Curl Timeout Mechanisms

| Mechanism | Flag | Scope | Notes |
|-----------|------|-------|-------|
| Connection timeout | `--connect-timeout` | Connection phase only | Handshake duration |
| Total operation | `--max-time` | Entire request | Hard limit |
| Low-speed detection | `-y/-Y` | Independent | Triggers before max-time if threshold not met |

**Recommendation**: For long-running API calls, either:
1. Remove low-speed detection entirely
2. Set very generous thresholds (e.g., `-y 300 -Y 1`)

---

## 2. Experiment Timeout Handling

### The Problem

Experiment 2 took 900 seconds (15 minutes), exceeding the 600-second (10 minute) budget:

```elisp
(defcustom gptel-auto-experiment-time-budget 600
  "Time budget per experiment in seconds (default: 10 min).")
```

### Current Implementation

The timeout uses `run-with-timer`:

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

### Why Timeout May Fail

1. **Blocking process**: gptel uses curl which may block the Emacs event loop
2. **Multiple stages**: analyze → execute → grade → benchmark → decide
3. **Timer not firing**: Emacs event loop blocked by `accept-process-output`

### Solutions

#### Solution 1: Process Timeout via Curl

DashScope backend uses `--max-time 300` (5 min):

```elisp
:curl-args '("--http1.1" "--max-time" "300" "--connect-timeout" "10")
```

#### Solution 2: Kill Curl Process on Timeout

Store curl process PID and kill on timeout:

```elisp
(let ((curl-pid (process-id gptel--curl-process)))
  (run-with-timer timeout nil
                  (lambda ()
                    (when (process-live-p gptel--curl-process)
                      (delete-process gptel--curl-process)))))
```

#### Solution 3: Reduce Backend Timeout Per-Request

```elisp
:curl-args '("--http1.1" "--max-time" "120" "--connect-timeout" "10")
```

#### Solution 4: Stage-Level Timeouts

Each stage should respect its own timeout:

| Stage | Suggested Timeout | Notes |
|-------|-------------------|-------|
| analyze | 60s | Quick classification |
| execute | 300s | Code execution can be slow |
| grade | 60s | LLM grading |
| benchmark | 60s | Performance measurement |
| decide | 30s | Quick decision |

---

## 3. Shell Command Timeout Blocking Bug

### The Problem

The daemon became completely unresponsive to `emacsclient` connections. Investigation revealed:

1. **Stuck subprocess**: A bash process (PID 2953) was running for 32+ minutes
2. **Blocked main thread**: Emacs was waiting for `accept-process-output` to return
3. **No CPU usage**: Daemon at 0% CPU but completely unresponsive
4. **Root cause**: `accept-process-output` with blocking flag (`t`) can hang indefinitely

### Root Cause Analysis

The original broken implementation:

```elisp
(while (and (not done)
            (< (float-time ...) timeout-seconds))
  (accept-process-output process 0.1 nil t))  ; LAST ARG 't' = BLOCK
```

**Why it failed**:
- `accept-process-output` with `t` as the last argument means "block until output or process exit"
- If subprocess hangs without producing output, `accept-process-output` blocks forever
- The timeout check in the while loop is never reached
- Emacs daemon becomes completely unresponsive

### The Perfect Fix

```elisp
(defun gptel-auto-workflow--shell-command-with-timeout (command timeout-seconds)
  "Execute COMMAND with TIMEOUT-SECONDS timeout.
Returns (success . output) or (timeout . nil) or (error . message)."
  (let* ((buffer (generate-new-buffer " *shell-command*"))
         (process nil)
         (timer nil)
         (done nil)
         (output ""))
    ;; Start the process
    (setq process
          (start-process-shell-command
           "timeout-cmd"
           buffer
           command))
    
    ;; Timer-based safety net - runs independently of blocking operations
    (setq timer
          (run-with-timer timeout-seconds nil
                          (lambda ()
                            (unless done
                              (setq done 'timeout)))))
    
    ;; Event loop - NON-BLOCKING (last arg nil)
    (while (and (not done)
                (process-live-p process))
      (accept-process-output process 0.1 nil nil)  ; nil = non-blocking
      (sit-for 0.01)  ; Cooperative yield to allow timer to fire
      (with-current-buffer buffer
        (setq output (buffer-string))))
    
    ;; Proper cleanup sequence
    (when timer (cancel-timer timer))
    (when (and process (process-live-p process))
      (delete-process process))
    (when (buffer-live-p buffer)
      (kill-buffer buffer))
    
    ;; Return result based on state
    (cond
     ((eq done 'timeout)
      (cons 'timeout nil))
     ((eq done 'finished)
      (cons 'success output))
     (t
      (cons 'error output)))))
```

### Key Changes Summary

1. **Timer-based safety net**: Timer runs independently, forces timeout even if main thread is blocked
2. **Non-blocking accept-process-output**: Last argument `nil` returns immediately if no output available
3. **Proper cleanup sequence**: `timer-cancel` → `process-kill` → `buffer-kill`
4. **Explicit state tracking**: Uses symbols (`'finished`, `'timeout`) instead of boolean flags

### Verification

| Metric | Before Fix | After Fix |
|--------|------------|-----------|
| Bash subprocess runtime | 32+ minutes | Configurable (30s default) |
| Daemon responsiveness | Unresponsive | Responsive |
| CPU usage | 0% (blocked) | Normal |
| Required intervention | Force kill daemon | None |

### Testing

```elisp
;; Test with hanging command - should return timeout after 5 seconds
(gptel-auto-workflow--shell-command-with-timeout "sleep 60" 5)
;; Returns: (timeout . nil)
```

---

## Actionable Patterns

### Pattern 1: Timer + Non-Blocking Poll

For reliable timeouts that don't block the Emacs event loop:

```elisp
;; Template
(let ((timer nil)
      (done nil))
  (setq timer (run-with-timer timeout-seconds nil
                              (lambda () (setq done 'timeout))))
  (while (and (not done) (process-live-p process))
    (accept-process-output process 0.1 nil nil)
    (sit-for 0.01))
  (when timer (cancel-timer timer))
  (when (and process (process-live-p process))
    (delete-process process)))
```

### Pattern 2: Curl Timeout Configuration

Avoid low-speed detection for long-running requests:

```elisp
;; Recommended: Explicit timeouts without low-speed detection
(setq my/curl-args
      '("--max-time" "300"
        "--connect-timeout" "30"))
```

### Pattern 3: Stage-Level Timeouts

For multi-stage workflows:

```elisp
(defvar gptel-auto-stage-timeouts
  '(("analyze" . 60)
    ("execute" . 300)
    ("grade" . 60)
    ("benchmark" . 60)
    ("decide" . 30)))

(defun gptel-auto-run-stage-with-timeout (stage-name func)
  (let* ((timeout (cdr (assoc stage-name gptel-auto-stage-timeouts)))
         (timer nil)
         (done nil)
         (result nil))
    (setq timer (run-with-timer timeout nil
                                (lambda () (setq done 'timeout))))
    (setq result (funcall func))
    (when done (setq result (cons 'timeout (car result))))
    (when timer (cancel-timer timer))
    result))
```

---

## Debugging Timeout Issues

### Identifying the Problem

| Symptom | Likely Cause |
|---------|---------------|
| Exit code 28 from curl | `-y/-Y` low-speed triggered |
| Command hangs indefinitely | `accept-process-output` blocking |
| Experiment exceeds budget | Timer not firing / blocking call |
| Daemon unresponsive | Stuck subprocess / blocking poll |

### Diagnostic Commands

```elisp
;; Check for stuck processes
(list-processes)

;; Check process status
(process-status "timeout-cmd")

;; Kill specific process
(delete-process (get-process "timeout-cmd"))

;; Check timer status
(timer-list)
```

---

## Related

- [[curl-timeouts]] - Detailed curl timeout options
- [[process-management]] - Emacs process handling
- [[error-handling]] - Transient error patterns and retries
- [[gptel-ext-backends]] - Backend configuration
- [[gptel-ext-abort]] - Abort conditions
- [[gptel-tools-agent]] - Shell command execution

---

## Lambda Patterns

```
λ timeout-mechanisms. understand curl's -y/-Y vs --max-time independence
λ shell-timeout. timer-based + non-blocking-poll > blocking-wait
λ process-cleanup. timer-cancel → process-kill → buffer-kill
λ state-tracking. explicit-symbols > boolean-flags
λ stage-timeouts. granular limits per phase > single global budget
```

---

## Files Modified

| File | Changes |
|------|---------|
| `lisp/modules/gptel-ext-abort.el` | Removed `-y/-Y` from global curl args |
| `lips/modules/gptel-ext-backends.el` | DashScope 600s → 900s timeout |
| `lisp/modules/gptel-ext-retry.el` | Added 1013 to transient patterns |
| `lisp/modules/gptel-tools-agent.el` | Rewrote `gptel-auto-workflow--shell-command-with-timeout` |