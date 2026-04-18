---
title: Timeout Handling in Emacs and Curl
status: active
category: knowledge
tags: [timeout, curl, subprocess, emacs, process-management, debugging]
---

# Timeout Handling in Emacs and Curl

## Overview

Timeout handling is critical for maintaining responsive Emacs daemons and reliable API integrations. This knowledge page synthesizes three production incidents involving timeout mechanisms in curl, Emacs subprocess management, and experiment workflows. Understanding these patterns prevents daemon hangs, false timeouts, and unresponsive systems.

Timeouts appear deceptively simple but have subtle interactions. Curl has three independent timeout mechanisms. Emacs subprocess blocking can freeze the entire daemon. Timer-based timeouts require careful state management to avoid race conditions.

## Curl Timeout Mechanisms

Curl provides three distinct timeout mechanisms that operate independently. Misunderstanding these distinctions causes false timeouts in production.

### Timeout Types Comparison

| Mechanism | Flag | Scope | Behavior |
|-----------|------|-------|----------|
| Connection Timeout | `--connect-timeout <seconds>` | DNS + TCP + TLS handshake only | Aborts before request sent |
| Maximum Time | `--max-time <seconds>` | Total operation including retries | Hard cap on entire request |
| Low-Speed Detection | `-y <seconds>` + `-Y <bytes/sec>` | Throughput monitoring | Triggers on sustained slow transfer |

### Connection Timeout (`--connect-timeout`)

Controls only the connection establishment phase. The timer starts when curl begins DNS resolution and stops when TCP connection (including TLS handshake) completes.

```bash
# Abort if connection not established within 10 seconds
curl --connect-timeout 10 https://api.example.com
```

**Use case**: Prevent indefinite hangs on unreachable hosts or DNS failures. Set conservatively (5-15 seconds for most APIs).

### Maximum Time (`--max-time`)

Hard limit on total operation time. Includes connection, data transfer, retries, and any internal delays. When exceeded, curl aborts with exit code 28.

```bash
# Abort if entire operation exceeds 5 minutes
curl --max-time 300 https://api.example.com/v1/chat
```

**Use case**: Budget enforcement for interactive workflows. Backend timeouts in gptel configurations.

### Low-Speed Detection (`-y` and `-Y`)

Monitors average throughput. If average speed drops below threshold for specified duration, curl aborts. **This operates independently of `--max-time`.**

```bash
# Abort if average speed drops below 50 bytes/sec for 15 consecutive seconds
curl -y 15 -Y 50 https://api.example.com
```

**Critical behavior**: Exit code 28 (timeout) triggers even if `--max-time` is set to a much larger value. The mechanisms are independent.

### The False Timeout Problem

When global curl arguments include low-speed detection, long-thinking LLM APIs trigger false timeouts:

```elisp
;; gptel configuration with problematic global args
(setq gptel-curl-extra-args '("-y" "15" "-Y" "50"))
;; Plus backend-specific max-time...
(gptel-make-backend
  :name "my-backend"
  :host "https://api.example.com"
  :max-time 900)  ; 15 minutes for complex tasks
```

**What happens**:
1. Backend `--max-time 900` allows 15-minute operations
2. LLM takes 20 seconds to "think" before streaming begins
3. No output bytes arrive during thinking phase
4. Average throughput drops below 50 bytes/sec for 15 seconds
5. Curl aborts with exit code 28
6. Backend's generous `--max-time` never reached

**Resolution**: Remove low-speed detection for API calls with variable response times, or set generous thresholds:

```elisp
;; Corrected configuration
(setq gptel-curl-extra-args '("-y" "300" "-Y" "10"))
;; Allows 5 minutes of low/no throughput before abort
```

## Process Timeout Patterns in Emacs

Emacs subprocess management requires careful timeout handling. Naive implementations block the entire daemon.

### The Blocking Problem

Using `accept-process-output` with blocking flags can hang Emacs indefinitely:

```elisp
;; DANGEROUS: Can block forever
(while (and (not done)
            (< (float-time (time-since start)) timeout-secs))
  (accept-process-output process 0.1 nil t))  ; 't' = BLOCK
```

**Why this fails**:
- `accept-process-output` with `t` as the last argument blocks until output arrives OR process exits
- If subprocess hangs without output, the call never returns
- The while-loop timeout check never executes
- Daemon becomes unresponsive to all connections

### Robust Timeout Implementation

The following pattern ensures reliable timeout behavior:

```elisp
(defun gptel-auto-workflow--shell-command-with-timeout
    (command timeout-seconds &optional directory)
  "Execute COMMAND with TIMEOUT-SECONDS limit.
Returns (list exit-code stdout stderr) or :timeout symbol."
  (let* ((buffer (generate-new-buffer " *shell-command*"))
         (process nil)
         (done nil)
         (timer nil)
         (start (current-time))
         (output "")
         (error-output ""))

    (unwind-protect
        (progn
          ;; Start the subprocess
          (setq process
                (make-process
                 :name "timeout-cmd"
                 :buffer buffer
                 :command `("bash" "-c" ,command)
                 :sentinel (lambda (p s)
                            (setq done 'finished))
                 :filter (lambda (p s)
                          (setq output
                                (concat output s)))))

          ;; Set working directory if specified
          (when directory
            (with-current-buffer buffer
              (default-directory directory)))

          ;; Timer-based safety net (independent of blocking operations)
          (setq timer
                (run-with-timer timeout-seconds nil
                                (lambda ()
                                  (unless done
                                    (setq done 'timeout)))))

          ;; Non-blocking poll loop
          (while (not done)
            (accept-process-output process 0.1 nil nil)  ; nil = NON-BLOCKING
            (sit-for 0.01)  ; Cooperative yield to event loop
            (when (eq done 'timeout)
              (delete-process process)))

          ;; Collect stderr after process completes
          (setq error-output (with-current-buffer buffer
                              (buffer-string)))

          ;; Return structured result
          (cond
           ((eq done 'timeout)
            (list 124 output error-output))  ; 124 = timeout exit code
           ((eq done 'finished)
            (list (process-exit-status process) output error-output))
           (t
            (list -1 output error-output))))

      ;; Cleanup sequence (order matters!)
      (when timer (cancel-timer timer))
      (when (and process (process-live-p process))
        (delete-process process))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))))
```

**Key patterns demonstrated**:

1. **Timer as safety net**: Independent of blocking operations, forces timeout state
2. **Non-blocking poll**: `accept-process-output` with `nil` returns immediately
3. **Cooperative yield**: `sit-for` allows event loop to process timers
4. **Ordered cleanup**: Timer → Process → Buffer prevents race conditions
5. **Explicit state tracking**: Symbols (`'finished`, `'timeout`) over booleans

### State Machine for Timeout Handling

```
┌─────────────────────────────────────────────────────────────┐
│                    State Transitions                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   [idle] ──process-start──► [running]                       │
│              │                                                  │
│              ├────► [finished] (process exits normally)      │
│              │                                                  │
│              └────► [timeout] (timer fires before completion) │
│                                                             │
│   [finished] or [timeout] ──cleanup──► [done]               │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**State tracking principles**:
- Use distinct symbols, not boolean flags
- Guard state transitions with `unless` to prevent overwrites
- Make timer force timeout even if process is alive

## Experiment Timeout Architecture

Long-running experiments require multi-level timeout strategies.

### Experiment Stages and Budgets

| Stage | Typical Duration | Recommended Timeout | Rationale |
|-------|-----------------|---------------------|-----------|
| Analyze | 30-60s | 90s | JSON parsing + planning |
| Execute | 60-300s | 300s | Code execution time |
| Grade | 30-60s | 90s | Comparison logic |
| Benchmark | 30-120s | 120s | Performance measurement |
| Decide | 15-30s | 45s | Route selection |
| **Total budget** | 3-10 min | 10 min | Per-experiment limit |

### Stage-Level Timeout Implementation

```elisp
(defcustom gptel-auto-experiment-time-budget 600
  "Time budget per experiment in seconds (default: 10 min)."
  :type 'integer
  :group 'gptel-auto-experiment)

(defvar gptel-auto-experiment-stage-timeouts
  '((analyze . 90)
    (execute . 300)
    (grade . 90)
    (benchmark . 120)
    (decide . 45))
  "Timeout per stage in seconds.")

(defun gptel-auto-experiment-run-stage (stage callback context)
  "Run single STAGE with timeout from `gptel-auto-experiment-stage-timeouts'."
  (let* ((timeout (or (cdr (assq stage
                                 gptel-auto-experiment-stage-timeouts))
                      60))
         (stage-result nil)
         (finished nil))

    (run-with-timer timeout nil
                    (lambda ()
                      (unless finished
                        (setq finished 'timeout)
                        (funcall callback
                                 (list :stage stage
                                       :error "stage-timeout"
                                       :timeout timeout)))))

    (condition-case err
        (let ((result (funcall (intern (format "gptel-auto-experiment--stage-%s"
                                               stage))
                               context)))
          (unless finished
            (setq finished 'finished)
            (funcall callback
                     (list :stage stage
                           :result result))))
      (error
       (unless finished
         (setq finished 'finished)
         (funcall callback
                  (list :stage stage
                        :error (error-message-string err))))))))
```

### Curl Timeout for Experiments

For experiment workflows calling LLMs, reduce backend timeouts:

```elisp
(gptel-make-backend
 :name "experiment-backend"
 :host "https://dashscope.aliyuncs.com/compatible-mode/v1"
 :endpoint "/chat/completions"
 :key 'gptel-api-key
 :models '("qwen-plus"))
;; Override at call site for tighter budgets:
;; :curl-args '("--max-time" "120" "--connect-timeout" "10")
```

**Alternative**: Use per-request curl arguments:

```elisp
(gptel-request
  (lambda (response)
    ;; Process response
    )
  :system "You are a helpful assistant."
  :messages '((:role "user" :content "Hello"))
  :backend "experiment-backend"
  :curl-args '("--max-time" "120"))  ; Override backend default
```

## Debugging Timeout Issues

### Identifying Timeout Exit Codes

```bash
# Common curl exit codes
exit 28  # CURLE_OPERATION_TIMEDOUT - max time exceeded OR low-speed triggered
exit 22  # CURLE_HTTP_RETURNED_ERROR - non-2xx response (not timeout)
exit 7   # CURLE_COULDNT_CONNECT - connection refused/failed
exit 6   # CURLE_COULDNT_RESOLVE_HOST - DNS failure

# Shell timeout (GNU coreutils)
exit 124 # TIMEOUT - command timed out
exit 137 # SIGKILL (128 + 9) - killed by signal
```

### Diagnostic Commands

```bash
# Test connection with verbose output
curl -v --connect-timeout 5 --max-time 30 https://api.example.com

# Trace low-speed detection
curl -v -y 15 -Y 50 https://api.example.com 2>&1 | grep -i "speed\|time"

# Monitor process in another terminal
ps aux | grep curl
strace -p <pid> -e trace=process  # Watch process state changes
```

### Emacs Process Diagnostics

```elisp
;; List all active processes
(list-processes)

;; Check specific process status
(defun gptel-diagnose-process (process-name)
  "Diagnose a named process's state."
  (interactive "sProcess name: ")
  (let ((proc (get-process process-name)))
    (if proc
        (message "Process: %s\nStatus: %s\nPID: %s\nLive: %s"
                 process-name
                 (process-status proc)
                 (process-id proc)
                 (process-live-p proc))
      (message "Process '%s' not found" process-name))))

;; Kill stuck process by PID
(delete-process (get-process "timeout-cmd"))

;; Monitor buffer for output
(with-current-buffer " *shell-command*"
  (buffer-string))
```

## Actionable Patterns Summary

### Pattern 1: Remove Low-Speed Detection for LLMs

```elisp
;; DON'T: Causes false timeouts during LLM "thinking"
(setq gptel-curl-extra-args '("-y" "15" "-Y" "50"))

;; DO: Allow generous low-throughput periods
(setq gptel-curl-extra-args '("-y" "300" "-Y" "10"))
;; OR remove entirely for streaming APIs
(setq gptel-curl-extra-args nil)
```

### Pattern 2: Timer-Based Non-Blocking Poll

```elisp
;; SKELETON for robust subprocess timeout
(let ((done nil)
      (timer nil)
      (process nil))
  (setq timer (run-with-timer timeout nil (lambda () (setq done 'timeout))))
  (setq process (make-process ...))
  (while (not done)
    (accept-process-output process 0.1 nil nil)
    (sit-for 0.01))
  (cancel-timer timer)
  (when (process-live-p process) (delete-process process)))
```

### Pattern 3: Multi-Level Timeout Budget

```elisp
;; Stage-level timeouts prevent cascading failures
;; Total budget = sum of stage timeouts + overhead

(defvar experiment-budget
  '((:stage analyze   :timeout 90)
    (:stage execute   :timeout 300)
    (:stage grade     :timeout 90)
    (:stage benchmark :timeout 120)
    (:stage decide    :timeout 45)))
```

### Pattern 4: Explicit Cleanup Sequence

```elisp
;; Order matters! Timer first prevents race conditions
(progn
  (when timer (cancel-timer timer))           ; 1. Cancel safety net
  (when (and proc (process-live-p proc))      ; 2. Kill if alive
    (delete-process proc))
  (when (buffer-live-p buf)                   ; 3. Release memory
    (kill-buffer buf)))
```

### Pattern 5: Graceful Degradation

```elisp
;; When timeout occurs, signal clearly instead of returning garbage
(cond
 ((eq done 'timeout)
  (signal 'gptel-timeout (list timeout-seconds stage-name)))
 ((eq done 'finished)
  (process-exit-status process))
 (t
  (signal 'gptel-unknown-state (list done))))
```

## Lambda Patterns (λ)

These symbolic patterns capture the key lessons:

```
λ curl-timeout. low-speed (-y/-Y) independent of --max-time
λ shell-timeout. timer-safety-net + non-blocking-poll > blocking-wait
λ process-cleanup. timer-cancel → process-kill → buffer-kill
λ state-tracking. explicit-symbols > boolean-flags
λ stage-budgets. per-stage limits prevent cascade overflow
λ graceful-deg. timeout-signal > silent-failure
```

## Related

- [[curl]] - HTTP client tool and Emacs integration
- [[emacs-processes]] - Subprocess management internals
- [[gptel-configuration]] - LLM integration configuration
- [[debugging-daemon-hangs]] - Diagnosing unresponsive Emacs
- [[experiment-workflow]] - Multi-stage task handling
- [[error-handling]] - Robust error recovery patterns