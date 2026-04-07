---
title: Timeout Handling in Emacs
status: active
category: knowledge
tags: [emacs, timeout, process, curl, gptel, debugging, performance]
---

# Timeout Handling in Emacs

## Overview

Timeout handling is critical for reliable automation workflows. These patterns address three distinct timeout scenarios: curl network timeouts, timer-based execution budgets, and shell subprocess blocking. Each requires different strategies because Emacs has multiple timeout mechanisms with different blocking characteristics.

## Curl Timeout Mechanisms

Curl provides three independent timeout mechanisms. Understanding their interaction is essential for debugging exit code 28 errors.

### Timeout Types

| Mechanism | Flag | Purpose | Blocking Behavior |
|-----------|------|---------|-------------------|
| Connection timeout | `--connect-timeout N` | DNS + TCP handshake | Aborts during connection phase only |
| Maximum time | `--max-time N` | Total operation duration | Hard cap on entire request |
| Low-speed detection | `-y N -Y B` | Detect stalled connections | Independent of `--max-time`! |

### The Low-Speed Trap

**Exit code 28** means "Operation timeout" but can occur even with generous `--max-time` settings if low-speed detection triggers first.

```bash
# These flags are INDEPENDENT - low-speed can fire before max-time
curl -y 15 -Y 50 --max-time 600 https://api.example.com
#           ↑    ↑         ↑
#    15 sec   50 B/s   10 min total
#           threshold
```

**How it works:** Curl tracks bytes/second. If average throughput drops below the threshold for the specified duration, curl aborts regardless of remaining `--max-time`.

### Why This Breaks LLM Calls

LLM APIs often "think" before streaming output. A 20-second thinking phase with no bytes sent triggers `-y 15 -Y 50` even though the total operation would complete within `--max-time 600`.

```elisp
;; PROBLEM: Global curl args appended to backend args
;; gptel-curl-extra-args: "-y 15 -Y 50"  ← Added to every request
;; Backend args: "--max-time 900"         ← Cannot override -y/-Y
;; Result: Timeout after 15 seconds of silence, not 900 seconds
```

### Correct Configuration

```elisp
;; REMOVE low-speed detection for long-running API calls
(setq gptel-curl-extra-args '())  ; Or specific non-timeout args

;; For backend-specific timeouts, use only --max-time
:curl-args '("--http1.1" "--max-time" "120" "--connect-timeout" "10")
```

## The Blocking Bug: accept-process-output with t

### Root Cause

When a shell command hangs without producing output, `accept-process-output` with `t` as the last argument blocks indefinitely:

```elisp
;; DANGEROUS: This can hang forever
(while (and (not done)
            (< (float-time (time-since start)) timeout-seconds))
  (accept-process-output process 0.1 nil t))  ; ← BLOCKING
;; If process hangs silently, we never reach the while condition check
```

**Why it fails:**
- `t` as final arg = "block until output or process exit"
- No output = block forever
- While loop never continues to check timeout condition
- Emacs daemon becomes completely unresponsive

### Demonstration

```elisp
;; This hangs Emacs indefinitely:
(gptel-auto-workflow--shell-command-with-timeout "sleep 60" 5)
;; Should timeout in 5 seconds but blocks forever
```

### The Perfect Fix Pattern

```elisp
(defun gptel-auto-workflow--shell-command-with-timeout
    (command timeout-seconds &optional buffer-name)
  "Execute COMMAND with TIMEOUT-SECONDS limit.
Returns (finished . output) or (timeout . \"timeout message\")."
  (let* ((buffer (or buffer-name (generate-new-buffer " *cmd-out*")))
         (done nil)
         (timer nil)
         (start (current-time))
         (process nil))

    ;; SAFETY NET: Timer fires regardless of blocking state
    (setq timer (run-with-timer timeout-seconds nil
                                (lambda ()
                                  (unless done
                                    (set
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-f0Yqyc.txt. Use Read tool if you need more]...