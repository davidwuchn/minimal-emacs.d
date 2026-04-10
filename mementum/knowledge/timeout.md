---
title: Timeout Handling in gptel-auto
status: active
category: knowledge
tags: [timeout, curl, process-management, debugging, reliability]
---

# Timeout Handling in gptel-auto

This knowledge page covers timeout mechanisms across the gptel-auto system, including curl configuration, process timeout bugs, and experiment budget handling.

## Overview

Timeout handling is critical for reliability in long-running AI workflows. The system uses multiple timeout layers:

| Layer | Purpose | Configuration |
|-------|---------|---------------|
| Curl `--connect-timeout` | Connection phase only | 10s typical |
| Curl `--max-time` | Total request time | 300-900s |
| Curl `-y/-Y` | Low-speed detection | **Caution: causes false positives** |
| `run-with-timer` | Emacs-level timeouts | Per-experiment budget |
| `shell-command-timeout` | Subprocess timeouts | Per-command limit |

---

## Curl Timeout Configuration

### The Problem

Auto-workflow failing with curl exit code 28 (timeout) even when backend configured with `--max-time 600` or `--max-time 900`.

### Root Cause: Low-Speed Detection

Global `gptel-curl-extra-args` included `-y 15 -Y 50`:
- `-y 15`: 15 seconds of low-speed allowed before abort
- `-Y 50`: 50 bytes/sec threshold

When LLM thinks for >15s without streaming output, curl aborts with exit 28 **regardless of `--max-time` setting**. Low-speed detection is independent of max-time.

**Curl args are appended: `global → backend`.** Backend `--max-time` overrides, but `-y/-Y` from global still active.

### Curl Timeout Mechanisms

```bash
# Connection phase only
curl --connect-timeout 10 ...

# Total operation time (overrides -y/-Y for total time)
curl --max-time 600 ...

# Low-speed detection (INDEPENDENT of max-time!)
curl -y 15 -Y 50 ...
# -y: seconds of low-speed allowed before abort
# -Y: bytes/sec threshold (50 = very strict)
```

### Fix Applied

Removed `-y/-Y` from global args in `gptel-ext-abort.el`:

```elisp
;; BEFORE (problematic)
(setq my/gptel--install-fast-curl-timeouts
      '("--max-time" "300" "-y" "15" "-Y" "50"))

;; AFTER (fixed)
(setq my/gptel--install-fast-curl-timeouts
      '("--max-time" "300"))  ; No low-speed detection
```

### Backend Configuration Examples

```elisp
;; DashScope backend - 900s for long-running calls
:curl-args '("--http1.1" "--max-time" "900" "--connect-timeout" "10")

;; For quick experiments, reduce timeout
:curl-args '("--http1.1" "--max-time" "120" "--connect-timeout" "10")
```

---

## Process Timeout: Critical Bug Fix

### The Problem

The daemon became completely unresponsive to `emacsclient` connections. Investigation revealed:

1. **Stuck subprocess:** A bash process (PID 2953) was running for 32+ minutes
2. **Blocked main thread:** Emacs was waiting for `accept-process-output` to return
3. **No CPU usage:** Daemon at 0% CPU but completely unresponsive

### Root Cause Analysis

**Original buggy implementation:**

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

### The Perfect Fix

```elisp
(defun gptel-auto-workflow--shell-command-with-timeout (command timeout-seconds)
  "Run COMMAND with TIMEOUT-SECONDS limit.
Returns: (list :output ... :status ... :error nil)"
  (let* ((buffer (generate-new-buffer " *shell-timeout*"))
         (process nil)
         (timer nil)
         (done nil))
    
    ;; Start the subprocess
    (setq process (start-process-shell-command
                   "shell-timeout" buffer command))
    
    ;; Timer-based safety net - runs independently
    (setq timer (run-with-timer timeout-seconds nil
                                (lambda ()
                                  (unless done
                                    (setq done 'timeout)))))
    
    ;; Event loop with non-blocking poll
    (while (and (not done)
                (process-live-p process))
      ;; KEY FIX: Last arg nil = NON-BLOCKING
      (accept-process-output process 0.1 nil nil)
      (sit-for 0.01))  ; Cooperative yield
    
    ;; Proper cleanup sequence
    (when timer (cancel-timer timer))
    (when (and process (process-live-p process))
      (delete-process process))
    
    (let ((output (with-current-buffer buffer
                    (string-trim (buffer-string))))
            (status (if (eq done 'timeout) 'timeout (process-status process))))
      (kill-buffer buffer)
      (list :output output :status status :error (when (eq done 'timeout) "timeout")))))
```

### Key Changes Summary

| Change | Before | After |
|--------|--------|-------|
| Timeout mechanism | While loop check | Timer-based safety net |
| accept-process-output | Blocking (`t`) | Non-blocking (`nil`) |
| State tracking | Boolean flag | Explicit symbols |
| Cleanup order | Not specified | Timer → Process → Buffer |

### State Tracking Pattern

```elisp
;; Explicit state symbols prevent race conditions
(setq done 'finished)   ; Process completed normally
(setq done 'timeout)    ; Timer forced timeout
(setq done 'error)      ; Process error

;; Compare to boolean flags which can be ambiguous
(setq done t)           ; Ambiguous: success or timeout?
```

---

## Experiment Timeout Handling

### Problem

Experiment 2 took 900s (15 minutes), exceeding the 600s (10 minute) budget.

### Current Implementation

```elisp
(defcustom gptel-auto-experiment-time-budget 600
  "Time budget per experiment in seconds (default: 10 min).")

;; Timeout set via run-with-timer
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

1. **Blocking process:** gptel uses curl which may block
2. **Multiple stages:** analyze + execute + grade + benchmark + decide
3. **Timer not firing:** Emacs event loop blocked

### Potential Solutions

#### 1. Process Timeout via Curl

DashScope backend uses `--max-time 300` (5 min). This should abort individual requests.

```elisp
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

#### 3. Reduce Backend Timeout

For experiments, reduce curl timeout:

```elisp
:curl-args '("--http1.1" "--max-time" "120" "--connect-timeout" "10")
```

#### 4. Add Stage-Level Timeouts

Each stage should respect its own timeout:

```elisp
(defcustom gptel-auto-stage-timeouts
  '(("analyze" . 60)
    ("execute" . 300)
    ("grade" . 60)
    ("benchmark" . 60)
    ("decide" . 30))
  "Timeout per stage in seconds.")
```

---

## Error Patterns: Transient Errors

Added error patterns for Moonshot API cold starts:

```elisp
;; gptel-ext-retry.el
(add-to-list 'gptel-auto-transient-error-patterns
  '("1013" . "server initializing"))
```

---

## Best Practices and Patterns

### Lambda Patterns

```
λ shell-timeout. timer-based + non-blocking-poll > blocking-wait
λ process-cleanup. timer-cancel → process-kill → buffer-kill  
λ state-tracking. explicit-symbols > boolean-flags
```

### Timeout Layering Strategy

```
Layer 1: Curl --connect-timeout (10s)
  ↓ If connected
Layer 2: Curl --max-time (300-900s)
  ↓ If slow response
Layer 3: Curl -y/-Y (REMOVED - causes false positives)
  ↓ If total time exceeded
Layer 4: Emacs timer (600s experiment budget)
  ↓ If experiment runs too long
Layer 5: Shell command timeout (30s per command)
  ↓ If shell command hangs
Layer 6: Process cleanup (kill subprocess)
```

### Configuration Checklist

- [ ] Remove `-y/-Y` from global curl args
- [ ] Set appropriate `--max-time` per backend
- [ ] Use non-blocking `accept-process-output`
- [ ] Implement timer-based safety net
- [ ] Add stage-level timeouts for multi-stage workflows
- [ ] Track state with explicit symbols
- [ ] Clean up in correct order: timer → process → buffer

---

## Testing

### Test Curl Timeout

```bash
# Should timeout after 5 seconds
curl --max-time 5 https://httpbin.org/delay/10
echo "Exit code: $?"  # Should be 28
```

### Test Low-Speed Timeout

```bash
# Should abort after 3 seconds of low-speed
curl -y 3 -Y 1 https://httpbin.org/drip\?numbytes\&delay\&duration=10
echo "Exit code: $?"  # Should be 28
```

### Test Shell Command Timeout

```elisp
;; Should return timeout after 5 seconds, not hang
(gptel-auto-workflow--shell-command-with-timeout "sleep 60" 5)
;; Returns: (:output "" :status signal :error "timeout")
```

---

## Related

- [Curl Documentation](https://curl.se/docs/manpage.html)
- [Emacs Process Management](https://www.gnu.org/software/emacs/manual/html_node/elisp/Processes.html)
- [gptel-ext-abort.el](./gptel-ext-abort.el)
- [gptel-ext-retry.el](./gptel-ext-retry.el)
- [gptel-tools-agent.el](./gptel-tools-agent.el)
- [DashScope Backend Configuration](./gptel-ext-backends.el)

---

## Files Modified

- `lisp/modules/gptel-ext-abort.el`: Remove -y/-Y from global args
- `lisp/modules/gptel-ext-backends.el`: DashScope 600s → 900s
- `lisp/modules/gptel-ext-retry.el`: Add 1013 to transient patterns
- `lisp/modules/gptel-tools-agent.el`: Rewrite shell-command-with-timeout

## Lessons

1. **Curl has multiple timeout mechanisms** that operate independently
2. **Low-speed detection causes false positives** for thinking LLMs
3. **Never use blocking accept-process-output** in timeout loops
4. **Timer-based safety nets** must run independently of main loop
5. **Explicit state tracking** prevents race conditions
6. **Cleanup order matters**: cancel timer first, then kill process, then buffer