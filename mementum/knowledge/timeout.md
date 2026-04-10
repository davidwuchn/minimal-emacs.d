---
title: Timeout Handling in gptel-auto
status: active
category: knowledge
tags: [timeout, curl, subprocess, process-management, debugging]
---

# Timeout Handling in gptel-auto

Timeout handling is critical for robust automation workflows. Poor timeout management can cause workflows to hang indefinitely, consume excessive resources, or make daemon instances completely unresponsive. This document covers the three main timeout scenarios in gptel-auto: curl network timeouts, experiment timeouts, and shell command subprocess timeouts.

## Curl Low-Speed Timeout Issue

### Problem

Auto-workflow failing with curl exit code 28 (timeout) even when backend configured with `--max-time 600` or `--max-time 900`.

### Root Cause

Global `gptel-curl-extra-args` included `-y 15 -Y 50`:

| Parameter | Value | Meaning |
|-----------|-------|---------|
| `-y` | 15 | 15 seconds of low-speed allowed before abort |
| `-Y` | 50 | 50 bytes/sec threshold |

When an LLM thinks for more than 15 seconds without streaming output, curl aborts with exit code 28 regardless of the `--max-time` setting. This is because **low-speed detection is independent of max-time**.

Curl arguments are appended: `global → backend`. Backend `--max-time` overrides global, but `-y/-Y` from global remain active.

### Fix

Remove `-y/-Y` from global curl args. The low-speed timeout causes false positives for subagents; backend-specific timeouts handle long-running calls better.

```elisp
;; Before (in gptel-ext-abort.el)
(setq my/gptel--install-fast-curl-timeouts
      '("--max-time" "900" "-y" "15" "-Y" "50"))

;; After - Remove low-speed detection
(setq my/gptel--install-fast-curl-timeouts
      '("--max-time" "900"))
```

### Curl Timeout Mechanisms

Curl provides three independent timeout mechanisms:

| Mechanism | Flag | Purpose |
|-----------|------|---------|
| Connection timeout | `--connect-timeout` | Connection phase only |
| Total operation timeout | `--max-time` | Total operation time |
| Low-speed detection | `-y/-Y` | Abort if below threshold for duration |

For long-running API calls, remove low-speed detection or set very generous thresholds (e.g., `-y 300 -Y 1`).

### Related Configuration

```elisp
;; DashScope backend timeout (gptel-ext-backends.el)
:curl-args '("--http1.1" "--max-time" "900" "--connect-timeout" "10")

;; For faster subagents, use shorter timeouts
:curl-args '("--http1.1" "--max-time" "120" "--connect-timeout" "10")
```

## Experiment Timeout Handling

### Problem

Experiment 2 took 900s (15 minutes), exceeding the 600s (10 minute) budget.

### Current Implementation

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

### Why Timeout May Fail

1. **Blocking process**: gptel uses curl which may block
2. **Multiple stages**: analyze + execute + grade + benchmark + decide
3. **Timer not firing**: Emacs event loop blocked

### Solutions

#### 1. Process Timeout via Curl

Set backend-specific curl timeouts for individual API calls:

```elisp
;; DashScope backend uses --max-time 300 (5 min)
;; This should abort individual requests
:curl-args '("--http1.1" "--max-time" "300" "--connect-timeout" "10")
```

#### 2. Kill Curl Process on Timeout

Store curl process PID and kill on timeout:

```elisp
(let ((curl-pid (process-id gptel--curl-process)))
  (run-with-timer timeout nil
                  (lambda ()
                    (when (process-live-p gptel--curl-process)
                      (delete-process gptel--curl-process)))))
```

#### 3. Stage-Level Timeouts

Each stage should respect its own timeout:

| Stage | Suggested Timeout | Purpose |
|-------|-------------------|---------|
| analyze | 60s | Initial analysis |
| execute | 300s | Code execution (longest) |
| grade | 60s | Grading output |
| benchmark | 60s | Running benchmarks |
| decide | 30s | Decision making |

```elisp
(defcustom gptel-auto-stage-timeouts
  '(("analyze" . 60)
    ("execute" . 300)
    ("grade" . 60)
    ("benchmark" . 60)
    ("decide" . 30))
  "Stage-specific timeouts in seconds.")
```

## Shell Command Timeout Blocking Bug

### Problem

The daemon became completely unresponsive to `emacsclient` connections. A bash process was running for 32+ minutes, and Emacs was waiting for `accept-process-output` to return. The daemon had 0% CPU but was completely unresponsive.

### Root Cause

The original implementation used `accept-process-output` with blocking flag (`t`):

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

### Perfect Fix

#### Key Changes

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

### Complete Implementation

```elisp
(defun gptel-auto-workflow--shell-command-with-timeout (command timeout-seconds)
  "Execute COMMAND with TIMEOUT-SECONDS timeout.
Returns (list :output STRING :status STATUS :error ERROR)."
  (let ((buffer (generate-new-buffer " *shell-command*"))
        (process nil)
        (timer nil)
        (done nil)
        (output ""))
    (unwind-protect
        (progn
          (setq process (start-process-shell-command
                         "timeout-process"
                         buffer
                         command))
          ;; Timer-based safety net
          (setq timer (run-with-timer timeout-seconds nil
                                      (lambda ()
                                        (unless done
                                          (setq done 'timeout)))))
          ;; Non-blocking poll loop
          (while (and (not done)
                      (process-live-p process))
            (accept-process-output process 0.1 nil nil)
            (sit-for 0.01))
          (setq output (with-current-buffer buffer
                         (string-trim (buffer-string))))
          (cond
           ((eq done 'timeout)
            (list :output output :status 'timeout :error "Command timed out"))
           ((eq done 'finished)
            (list :output output
                  :status (process-exit-status process)
                  :error nil))
           (t
            (list :output output
                  :status (process-exit-status process)
                  :error nil))))
      ;; Cleanup sequence
      (when timer (cancel-timer timer))
      (when (and process (process-live-p process))
        (delete-process process))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))
```

### Verification

**Before fix:**
- Bash subprocess: 32+ minutes runtime
- Daemon: Unresponsive, 0% CPU
- Required: Force kill daemon

**After fix:**
- Commands timeout reliably after 30s (configurable)
- Daemon remains responsive
- No stuck subprocesses

### Testing

```elisp
;; Test with hanging command - should return timeout after 5 seconds
(gptel-auto-workflow--shell-command-with-timeout "sleep 60" 5)
;; Returns: (:output "" :status timeout :error "Command timed out")

;; Test with normal command - should complete normally
(gptel-auto-workflow--shell-command-with-timeout "echo hello" 5)
;; Returns: (:output "hello" :status 0 :error nil)
```

## Patterns and Anti-Patterns

### Anti-Patterns

| Anti-Pattern | Problem | Fix |
|--------------|---------|-----|
| Blocking accept-process-output | Hangs indefinitely | Use non-blocking (last arg nil) |
| Timer without cleanup | Timer fires after function returns | Cancel timer in cleanup |
| No state tracking | Race conditions | Use explicit symbols ('finished, 'timeout) |
| Low-speed detection for LLM | False positives with thinking time | Remove -y/-Y or set generous values |
| Single global timeout | Can't distinguish stages | Stage-level timeouts |

### Patterns

```
λ timeout. timer-based + non-blocking-poll > blocking-wait
λ process-cleanup. timer-cancel → process-kill → buffer-kill  
λ state-tracking. explicit-symbols > boolean-flags
λ curl-timeout. max-time > low-speed-detection for LLM calls
λ stage-timeout. per-stage budgets > single global budget
```

## Related Topics

- [gptel-curl-extra-args](./gptel-curl-extra-args.md) - Global curl argument configuration
- [Process Management](./process-management.md) - Subprocess handling in Emacs
- [Error Handling](./error-handling.md) - Transient errors and retry logic
- [Backend Configuration](./backend-configuration.md) - Per-backend timeout settings
- [Debugging Guide](./debugging.md) - Investigating timeout-related failures

## Debugging Timeout Issues

### Identifying Timeout Problems

```bash
# Check for stuck processes
ps aux | grep emacs
ps aux | grep curl

# Check daemon responsiveness
emacsclient --eval "(message \"test\")"
```

### Common Exit Codes

| Exit Code | Meaning | Likely Cause |
|-----------|---------|--------------|
| 28 | curl timeout | Network or slow response |
| 124 | command timeout | Shell timeout (timeout command) |
| 143 | SIGTERM | Process killed by timeout |

### Diagnostic Code

```elisp
;; Check running processes
(list-processes)

;; Check process status
(with-current-buffer (get-buffer "*shell-command*")
  (process-list))

;; Manual timeout test
(gptel-auto-workflow--shell-command-with-timeout "sleep 30" 5)
;; Should complete in ~5 seconds, not 30
```

---

**Symbol:** λ timeout - robust timeout handling

**Last Updated:** 2026-03-30