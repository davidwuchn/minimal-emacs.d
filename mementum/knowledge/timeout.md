---
title: Timeout Handling in Emacs/GPTel Systems
status: active
category: knowledge
tags: [timeout, curl, process-management, gptel, elisp, debugging]
---

# Timeout Handling in Emacs/GPTel Systems

## Overview

Timeout handling is a critical aspect of robust system design, particularly when dealing with external processes, network requests, and long-running operations. This knowledge page synthesizes three key timeout-related discoveries: curl low-speed timeout mechanics, experiment timeout budgets, and a critical shell command blocking bug with its fix.

---

## 1. Curl Timeout Mechanisms

Curl provides multiple independent timeout mechanisms that behave differently. Understanding these distinctions is essential for reliable API calls.

### Timeout Types Comparison

| Option | Purpose | Behavior | Default |
|--------|---------|----------|---------|
| `--connect-timeout` | Connection phase only | Aborts if TCP connection not established within N seconds | 300s |
| `--max-time` | Total operation time | Aborts entire operation after N seconds | 0 (infinite) |
| `-y` / `--low-speed-time` | Low-speed detection | Aborts if average speed < threshold for N seconds | 0 (disabled) |
| `-Y` / `--low-speed-limit` | Bytes/sec threshold | Minimum bytes/second to avoid timeout | 0 |

### The Critical Insight

**Low-speed timeout (`-y/-Y`) operates independently of `--max-time`!** This is a common source of unexpected failures.

```bash
# This configuration can still fail with exit code 28:
curl -y 15 -Y 50 --max-time 600 https://api.example.com/long-task

# Why: If the LLM thinks for >15 seconds without outputting >=50 bytes/sec,
# curl aborts with exit code 28, regardless of the generous --max-time setting
```

### The GPTel Configuration Problem

In the GPTel system, the global curl arguments included low-speed detection:

```elisp
;; BEFORE (broken configuration)
(defvar my/gptel--install-fast-curl-timeouts
  '("-y" "15" "-Y" "50" "--max-time" "600"))

;; Problem: Backend-specific --max-time overrides global,
;; but -y/-Y from global remain active!
```

When the LLM enters "thinking" mode without streaming output for more than 15 seconds, curl aborts with exit code 28 even though the backend was configured with a 10-minute timeout.

### The Fix

```elisp
;; AFTER (fixed configuration)
(defvar my/gptel--install-fast-curl-timeouts
  '("--max-time" "600"))  ; Removed -y/-Y entirely

;; For long-running calls like subagents, use only max-time:
:gptel-backend (make-gptel-dashscope
                 :host "api.moonshot.cn"
                 :url "https://api.moonshot.cn/v1/chat/completions"
                 :curl-args '("--http1.1" "--max-time" "900" "--connect-timeout" "10"))
```

### Exit Code Reference

| Exit Code | Meaning |
|-----------|---------|
| 0 | Success |
| 2 | Malformed URL |
| 6 | Could not resolve host |
| 7 | Failed to connect |
| 28 | Operation timeout |
| 55 | Failed to send network request |

---

## 2. Shell Command Timeout Blocking Bug

A critical bug was discovered where the daemon became completely unresponsive due to improper `accept-process-output` usage.

### Symptoms

- Bash subprocess running for 32+ minutes
- Emacs daemon at 0% CPU but unresponsive to `emacsclient`
- No keyboard or timer interrupts processing
- Required force-kill of daemon to recover

### Root Cause

The original implementation used **blocking** `accept-process-output`:

```elisp
;; BROKEN CODE - DO NOT USE
(while (and (not done)
            (< (float-time (time-since start-time)) timeout-seconds))
  (accept-process-output process 0.1 nil t))  ; 't' = BLOCKING!
```

**Why this fails:**
- Last argument `t` means "block until output OR process exits"
- If subprocess hangs without producing output, blocks forever
- Timeout check in while loop is never reached
- Emacs main thread becomes completely unresponsive

### The Robust Fix

```elisp
(defun gptel-auto-workflow--shell-command-with-timeout (command timeout-seconds)
  "Execute COMMAND with TIMEOUT-SECONDS.
Returns: (list :stdout STRING :exit-code INT :status 'finished|'timeout|'error)"
  (let* ((buffer (generate-new-buffer " *shell-timeout*"))
         (process (start-process-shell-command "timeout-shell"
                                                buffer
                                                command))
         (done nil)
         (timer nil)
         (start-time (float-time)))
    
    ;; Safety net: timer fires even if main thread blocked
    (setq timer (run-with-timer timeout-seconds nil
                                (lambda ()
                                  (unless done
                                    (setq done 'timeout)))))
    
    ;; Non-blocking poll loop
    (while (and (not done)
                (process-live-p process))
      (accept-process-output process 0.1 nil nil)  ; 'nil' = NON-BLOCKING
      (sit-for 0.01)  ; Cooperative yield to allow timer/checkpoint
      (when (eq (car-safe (process-status process)) 'exit)
        (setq done 'finished)))
    
    ;; Cleanup sequence (order matters!)
    (when timer (cancel-timer timer))
    (when (and process (process-live-p process))
      (delete-process process))
    (when (buffer-live-p buffer)
      (kill-buffer buffer))
    
    ;; Return results based on done state
    (pcase done
      ('finished
       (list :stdout (with-current-buffer buffer (buffer-string))
             :exit-code (process-exit-status process)
             :status 'finished))
      ('timeout
       (list :stdout ""
             :exit-code -1
             :status 'timeout))
      (_
       (list :stdout ""
             :exit-code -1
             :status 'error)))))
```

### Key Changes Explained

| Change | Before | After | Purpose |
|--------|--------|-------|---------|
| Timer | None | `run-with-timer` | Forces timeout even if blocked |
| accept-process-output | `t` (blocking) | `nil` (non-blocking) | Returns immediately if no output |
| Cooperative yield | None | `(sit-for 0.01)` | Allows timer/checkpoint to fire |
| Cleanup order | Mixed | Timer → Process → Buffer | Prevents race conditions |
| State tracking | Boolean | Explicit symbols | Clear state transitions |

### Testing the Fix

```elisp
;; Test with hanging command - should timeout after 5 seconds
(gptel-auto-workflow--shell-command-with-timeout "sleep 60" 5)
;; Returns: (:stdout "" :exit-code -1 :status 'timeout)

;; Test with normal command - should complete
(gptel-auto-workflow--shell-command-with-timeout "echo hello" 5)
;; Returns: (:stdout "hello\n" :exit-code 0 :status 'finished)
```

---

## 3. Experiment Timeout Budget

Auto-workflow experiments have a configurable time budget. Understanding how this interacts with other timeouts is essential.

### Configuration

```elisp
(defcustom gptel-auto-experiment-time-budget 600
  "Time budget per experiment in seconds (default: 10 min).")
```

### Implementation Pattern

```elisp
(defun gptel-auto-workflow--run-with-timeout (timeout-seconds callback)
  "Run callback after TIMEOUT-SECONDS, cancelling if experiment completes first."
  (let* ((finished nil)
         (timer (run-with-timer timeout-seconds nil
                                (lambda ()
                                  (unless finished
                                    (setq finished t)
                                    (gptel-auto-workflow-delete-worktree)
                                    (funcall callback
                                             (list :target target
                                                   :id experiment-id
                                                   :error "timeout"))))))
    ;; ... experiment runs ...
    (when (and finished (timerp timer))
      (cancel-timer timer))))
```

### Timeout Interaction Matrix

| Component | Default | Configurable | Interaction |
|-----------|---------|--------------|-------------|
| Experiment budget | 600s | Yes | Overall experiment timeout |
| Backend curl | 300-900s | Per-backend | HTTP request timeout |
| Stage timeouts | None | No (proposed) | Per-stage budget |
| Shell command | 30s | Yes | Tool execution timeout |

### Proposed Stage-Level Timeouts

For more granular control, each experiment stage should have its own timeout:

```elisp
(defcustom gptel-auto-stage-timeouts
  '(("analyze" . 60)
    ("execute" . 300)
    ("grade" . 60)
    ("benchmark" . 60)
    ("decide" . 30))
  "Stage-name to timeout seconds association.")
```

---

## 4. Best Practices and Patterns

### Pattern: Timer-Based Safety Net

Always use a timer as a safety net for operations that might block:

```elisp
(let ((timer (run-with-timer timeout-seconds nil
                            (lambda () (setq timed-out t)))))
  (unwind-protect
      (progn
        ;; ... blocking operation ...
        )
    (cancel-timer timer)))
```

### Pattern: Non-Blocking Process Polling

Never use blocking `accept-process-output`:

```elisp
;; BAD - blocks indefinitely
(accept-process-output process 0.1 nil t)

;; GOOD - returns immediately if no output
(accept-process-output process 0.1 nil nil)
(sit-for 0.01)  ; Cooperative yield
```

### Pattern: Explicit State Tracking

Use symbols, not booleans, for state:

```elisp
;; BAD - ambiguous
(setq done t)  ;; What does t mean? Completed? Timed out? Error?

;; GOOD - explicit
(setq done 'finished)   ;; Process completed normally
(setq done 'timeout)    ;; Timer forced timeout
(setq done 'error)      ;; Error condition
```

### Pattern: Cleanup Order

Always cancel timer before killing process:

```elisp
;; CORRECT ORDER
(when timer (cancel-timer timer))
(when (and process (process-live-p process))
  (delete-process process))
(when (buffer-live-p buffer)
  (kill-buffer buffer))
```

### Pattern: Curl Timeout for LLM APIs

```elisp
;; Recommended for long-running LLM calls
:curl-args '("--http1.1"
             "--max-time" "900"      ; 15 minutes total
             "--connect-timeout" "10" ; 10 seconds connection
             "--retry" "3"            ; Retry on transient errors
             "--retry-delay" "2")
;; NOTE: Do NOT include -y/-Y for LLM API calls
```

### Pattern: Graceful Degradation

```elisp
(pcase result
  ((pred timeoutp)
   (warn "Operation timed out, falling back to default behavior")
   (use-default-strategy))
  ((pred errorp)
   (warn "Operation failed: %s" (cdr result))
   (signal 'operation-error (cdr result)))
  (_ result))
```

---

## 5. Debugging Timeout Issues

### Checking for Stuck Processes

```elisp
;; List all subprocesses
(list-processes)

;; Kill specific stuck process
(delete-process (get-process "timeout-shell"))
```

### Tracing Timeout Events

```elisp
(defmacro with-timeout-logging (name &rest body)
  "Log timeout NAME and timing for BODY."
  (declare (indent 1))
  `(let ((start-time (float-time)))
     (message "[TIMEOUT-DEBUG] Starting: %s" ,name)
     (unwind-protect
         (progn ,@body)
       (message "[TIMEOUT-DEBUG] Finished: %s (%.2fs)"
                ,name
                (- (float-time) start-time)))))
```

### Exit Code Analysis

```elisp
(defun gptel-auto-analyze-exit-code (code)
  "Explain curl exit CODE meaning."
  (pcase code
    (0 "Success")
    (2 "Malformed URL")
    (6 "Could not resolve host")
    (7 "Failed to connect")
    (28 "Operation timeout")
    (55 "Failed to send network request")
    (_ (format "Unknown error: %s" code))))
```

---

## Related

- [[Curl Configuration]] - Full curl argument reference
- [[GPTel Backends]] - Backend-specific timeout configurations
- [[Process Management]] - Emacs process handling
- [[Error Handling Patterns]] - Graceful degradation strategies
- [[Debugging Techniques]] - Troubleshooting stuck processes
- [[Transient Errors]] - Retry patterns for transient failures (e.g., 1013, "server is initializing")

---

## Lambda Patterns

```
λ curl-timeout. --max-time for total, -y/-Y only for fast transfers
λ shell-timeout. timer-based + non-blocking-poll > blocking-wait
λ process-cleanup. timer-cancel → process-kill → buffer-kill
λ state-tracking. explicit-symbols > boolean-flags
λ cooperative-yield. sit-for 0.01 enables timer interrupts
```

---

## Files Modified Reference

| File | Change |
|------|--------|
| `lisp/modules/gptel-ext-abort.el` | Removed `-y/-Y` from global curl args |
| `lisp/modules/gptel-ext-backends.el` | DashScope 600s → 900s max-time |
| `lisp/modules/gptel-ext-retry.el` | Added 1013 to transient error patterns |
| `lisp/modules/gptel-tools-agent.el` | Rewrote shell command timeout (lines 48-94) |