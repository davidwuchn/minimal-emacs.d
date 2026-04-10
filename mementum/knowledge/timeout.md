---
title: Timeout Handling in gptel-auto
status: active
category: knowledge
tags: [timeout, curl, emacs, subprocess, debugging, reliability]
---

# Timeout Handling in gptel-auto

Timeout management is critical for reliable automation. This knowledge page synthesizes three major timeout-related issues and their solutions: curl low-speed timeouts, experiment budget timeouts, and shell command blocking bugs.

## 1. Curl Low-Speed Timeout Issue

### Problem

Auto-workflow failing with curl exit code 28 (timeout) even when backend is configured with `--max-time 600` or `--max-time 900`.

### Root Cause

Global `gptel-curl-extra-args` included `-y 15 -Y 50`:
- `-y 15`: 15 seconds of low-speed allowed before abort
- `-Y 50`: 50 bytes/sec threshold

When the LLM thinks for >15 seconds without streaming output, curl aborts with exit code 28 **regardless of `--max-time` setting**. Low-speed detection is independent of max-time.

Curl args are appended in this order: `global → backend`. Backend `--max-time` overrides, but `-y/-Y` from global remain active.

### Curl Timeout Mechanisms

Curl has **three independent timeout mechanisms**:

| Option | Purpose | Scope |
|--------|---------|-------|
| `--connect-timeout <seconds>` | Connection phase only | TCP handshake |
| `--max-time <seconds>` | Total operation time | Entire request |
| `-y <seconds>` | Low-speed abort threshold | No data transfer |
| `-Y <bytes/sec>` | Low-speed bytes/second | Throughput check |

**Critical Insight**: `-y/-Y` operates independently of `--max-time`. Even with `--max-time 600`, curl will abort after 15 seconds of low-speed transfer.

### The Fix

Remove `-y/-Y` from global curl args:

```elisp
;; BEFORE (in gptel-ext-abort.el)
(setq my/gptel--install-fast-curl-timeouts
      '("--max-time" "900" "-y" "15" "-Y" "50"))

;; AFTER - remove low-speed detection
(setq my/gptel--install-fast-curl-timeouts
      '("--max-time" "900"))
```

### Files Changed

| File | Change |
|------|--------|
| `lisp/modules/gptel-ext-abort.el` | Remove -y/-Y from global args |
| `lisp/modules/gptel-ext-backends.el` | DashScope 600s → 900s |
| `lisp/modules/gptel-ext-retry.el` | Add 1013 to transient patterns |

### Lesson

For long-running API calls that may have Think time:
- Remove low-speed detection entirely
- Or set very generous thresholds: `-y 600 -Y 1`
- Use `--max-time` for overall timeout control

---

## 2. Experiment Timeout Handling

### Problem

Experiment 2 took 900s (15 minutes), exceeding the 600s (10 minute) budget.

### Current Implementation

```elisp
(defcustom gptel-auto-experiment-time-budget 600
  "Time budget per experiment in seconds (default: 10 min).")

;; Timeout via run-with-timer
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
2. **Multiple stages**: analyze → execute → grade → benchmark → decide
3. **Timer not firing**: Emacs event loop blocked by synchronous operations
4. **Race conditions**: Process completes just as timer fires

### Potential Solutions

#### Solution 1: Process Timeout via Curl

Configure backend to timeout individual requests:

```elisp
;; In backend definition
:curl-args '("--http1.1" "--max-time" "300" "--connect-timeout" "30")
```

| Parameter | Recommended Value | Purpose |
|-----------|-------------------|---------|
| `--max-time` | 300 (5 min) | Individual request timeout |
| `--connect-timeout` | 30 | Connection phase |

#### Solution 2: Kill Curl Process on Timeout

```elisp
(let ((curl-process gptel--curl-process))
  (run-with-timer timeout nil
                   (lambda ()
                     (when (and curl-process (process-live-p curl-process))
                       (delete-process curl-process)))))
```

#### Solution 3: Stage-Level Timeouts

Each stage should respect its own timeout:

```elisp
(defcustom gptel-auto-stage-timeouts
  '((analyze . 60)
    (execute . 300)
    (grade . 60)
    (benchmark . 60)
    (decide . 30))
  "Stage-specific timeout in seconds.")
```

| Stage | Timeout (s) | Rationale |
|-------|-------------|-----------|
| analyze | 60 | Quick prompt parsing |
| execute | 300 | Long-running commands |
| grade | 60 | Moderate LLM response |
| benchmark | 60 | Quick metrics |
| decide | 30 | Simple selection |

---

## 3. Shell Command Timeout Blocking Bug

### Problem

The daemon became completely unresponsive to `emacsclient` connections. Investigation revealed:

1. **Stuck subprocess**: A bash process (PID 2953) running for 32+ minutes
2. **Blocked main thread**: Emacs waiting for `accept-process-output` to return
3. **No CPU usage**: Daemon at 0% CPU but completely unresponsive
4. **Root cause**: `accept-process-output` with blocking flag (`t`) hangs indefinitely

### Root Cause Analysis

The original buggy implementation:

```elisp
(while (and (not done)
            (< (float-time ...) timeout-seconds))
  (accept-process-output process 0.1 nil t))  ; BUG: LAST ARG 't' = BLOCK
```

**Why it failed:**
- `accept-process-output` with `t` as last argument means "block until output or process exit"
- If subprocess hangs without producing output, `accept-process-output` blocks forever
- The timeout check in the while loop is never reached
- Emacs daemon becomes completely unresponsive

### The Perfect Fix

#### Key Changes:

1. **Timer-based safety net** (runs independently of blocking operations):
   ```elisp
   (setq timer (run-with-timer timeout-seconds nil
                               (lambda ()
                                 (unless done
                                   (setq done 'timeout)))))
   ```

2. **Non-blocking accept-process-output**:
   ```elisp
   (accept-process-output process 0.1 nil nil)  ; LAST ARG nil = NON-BLOCKING
   (sit-for 0.01)  ; Cooperative yield to allow timer to fire
   ```

3. **Proper cleanup sequence**:
   ```elisp
   (when timer (cancel-timer timer))
   (when (and process (process-live-p process))
     (delete-process process))
   (when (buffer-live-p buffer)
     (kill-buffer buffer))
   ```

4. **Explicit state tracking**:
   ```elisp
   (setq done 'finished)   ; process completed normally
   (setq done 'timeout)     ; timer forced timeout
   (setq done 'error)       ; error condition
   ```

### Complete Fixed Implementation

```elisp
(defun gptel-auto-workflow--shell-command-with-timeout (command timeout-seconds)
  "Execute COMMAND with TIMEOUT-SECONDS timeout.
Returns: (list :output string :status exit-code :timeout boolean)"
  (let* ((buffer (generate-new-buffer " *shell-timeout*"))
         (process nil)
         (timer nil)
         (done nil)
         (start-time (float-time)))
    
    ;; Start the process
    (setq process (start-process-shell-command
                   "timeout-cmd"
                   buffer
                   command))
    
    ;; Timer-based safety net
    (setq timer (run-with-timer timeout-seconds nil
                               (lambda ()
                                 (unless done
                                   (setq done 'timeout)))))
    
    ;; Non-blocking poll loop
    (while (not done)
      (cond
       ;; Check timeout condition
       ((eq done 'timeout)
        (message "Timeout reached after %d seconds" timeout-seconds))
       
       ;; Check if process exited
       ((not (process-live-p process))
        (setq done 'finished))
       
       ;; Normal case: poll for output
       (t
        (accept-process-output process 0.1 nil nil)
        (sit-for 0.01))))
    
    ;; Cleanup sequence (order matters!)
    (when timer (cancel-timer timer))
    (when (and process (process-live-p process))
      (delete-process process))
    
    (let ((output (with-current-buffer buffer
                    (string-trim (buffer-string))))
          (exit-code (if (eq done 'timeout)
                       -1
                       (process-exit-status process))))
      (kill-buffer buffer)
      (list :output output
            :status exit-code
            :timeout (eq done 'timeout)))))
```

### Verification

| Metric | Before Fix | After Fix |
|--------|------------|-----------|
| Bash subprocess | 32+ minutes | Terminated at timeout |
| Daemon | Unresponsive | Responsive |
| Required action | Force kill daemon | Automatic cleanup |

### Testing

```elisp
;; Test with hanging command - should timeout after 5 seconds
(gptel-auto-workflow--shell-command-with-timeout "sleep 60" 5)
;; Returns: (:output "" :status -1 :timeout t)

;; Test with normal command - should complete
(gptel-auto-workflow--shell-command-with-timeout "echo hello" 5)
;; Returns: (:output "hello\n" :status 0 :timeout nil)
```

---

## 4. Lambda Patterns

### Shell Timeout Pattern

```
λ shell-timeout. timer-based + non-blocking-poll > blocking-wait
```

**Components:**
1. Timer runs independently (not dependent on event loop)
2. `accept-process-output` with nil (non-blocking)
3. `sit-for` for cooperative yield

### Process Cleanup Pattern

```
λ process-cleanup. timer-cancel → process-kill → buffer-kill
```

**Order matters:**
1. Cancel timer first to prevent race conditions
2. Force-kill process if still alive
3. Clean up buffer last

### State Tracking Pattern

```
λ state-tracking. explicit-symbols > boolean-flags
```

**Why explicit symbols:**
- Boolean flags: `done` = t/nil (ambiguous)
- Explicit symbols: `done` = 'finished/'timeout/'error
- Clear state transitions prevent race conditions

---

## 5. Related Topics

- [[curl]] - HTTP client for LLM API calls
- [[subprocess]] - Emacs subprocess management
- [[emacs-daemon]] - Background Emacs process
- [[retry-strategy]] - Transient error handling
- [[gptel-configuration]] - Backend and global configuration

---

## 6. Quick Reference

### Curl Timeout Flags

```bash
# Connection timeout only
curl --connect-timeout 30 https://api.example.com

# Total operation timeout
curl --max-time 600 https://api.example.com

# Low-speed detection (independent of --max-time!)
curl -y 15 -Y 50 https://api.example.com
```

### Emacs Timeout Patterns

```elisp
;; Timer-based timeout
(run-with-timer seconds nil (lambda () ...))

;; Non-blocking process poll
(accept-process-output process 0.1 nil nil)
(sit-for 0.01)

;; Cleanup
(cancel-timer timer)
(delete-process process)
(kill-buffer buffer)
```

### Debugging Commands

```elisp
;; List all processes
(list-processes)

;; Check if process is live
(process-live-p process)

;; Get process ID
(process-id process)

;; Force kill subprocess
(delete-process process)
```

---

## 6. Actionable Checklist

When implementing timeouts:

- [ ] **Never use blocking `accept-process-output`** with last arg `t`
- [ ] **Always use timer-based safety net** for critical operations
- [ ] **Remove `-y/-Y` from curl** for long-running LLM calls
- [ ] **Use explicit state symbols** instead of boolean flags
- [ ] **Clean up in correct order**: timer → process → buffer
- [ ] **Test with hanging commands** to verify timeout works
- [ ] **Monitor daemon responsiveness** after timeout implementation