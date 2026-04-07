---
title: Timeout Handling in Emacs and Curl
status: active
category: knowledge
tags: [emacs, curl, timeout, subprocess, process-management, elisp, debugging]
---

# Timeout Handling in Emacs and Curl

## Overview

Timeout handling is critical for reliable automation systems. This page synthesizes three real incidents involving timeout mechanisms across curl HTTP requests and Emacs subprocess management. Understanding the distinction between different timeout types—and their interactions—is essential for building robust systems.

## Curl Timeout Mechanisms

Curl provides **three independent timeout mechanisms**. Misunderstanding their interactions leads to false positives and unexplained failures.

### The Three Timeout Types

| Flag | Purpose | Scope | Independent? |
|------|---------|-------|--------------|
| `--connect-timeout` | TCP connection phase only | Connection | Yes |
| `--max-time` | Total operation time | Entire request | Yes |
| `-y` / `-Y` | Low-speed detection | Entire request | **Yes** |

**Critical insight:** Low-speed detection (`-y`/`-Y`) operates completely independently of `--max-time`. Setting a generous `--max-time` does not disable or override low-speed detection.

### Low-Speed Detection Explained

```bash
# These are INDEPENDENT - both apply simultaneously
curl --max-time 600 -y 15 -Y 50 https://api.example.com/completion

# Explanation:
# --max-time 600 : Allow 10 minutes total
# -y 15         : Abort if below threshold for 15 consecutive seconds
# -Y 50         : Threshold is 50 bytes/second
```

**Exit code 28** means "operation timeout" but can be triggered by **either** `--max-time` expiration **or** low-speed detection—making debugging difficult without knowing which mechanism fired.

### The Problem: Global Args Appended to Backend Args

In gptel configurations, curl arguments are composed as:

```
gptel-curl-extra-args (global) + backend-specific args
```

```elisp
;; Global args (user config)
(defcustom gptel-curl-extra-args '("-y" "15" "-Y" "50"))

;; Backend args (per-provider)
:curl-args '("--http1.1" "--max-time" "900")
;;                            ^-- Backend max-time
```

The combined curl command becomes:
```bash
curl -y 15 -Y 50 --http1.1 --max-time 900 ...
#        ^-- Global (unwanted)    ^-- Backend (intended)
```

**Result:** Backend `--max-time 900` does not disable global `-y/-Y`. If the LLM "thinks" for 16 seconds without streaming output, curl aborts with exit 28.

### The Fix

Remove low-speed detection from global args for long-running API calls:

```elisp
;; BAD: Causes false positives for async APIs
(defcustom gptel-curl-extra-args '("-y" "15" "-Y" "50"))

;; GOOD: Let backend handle timeouts
(defcustom gptel-curl-extra-args '())
```

## Emacs Timer-Based Timeouts

### The Naive Implementation (Broken)

```elisp
(defun broken-timeout-handler ()
  "This implementation BLOCKS and fails."
  (let ((timeout-seconds 30)
        (done nil))
    (while (and (not done)
                (< (float-time (time-since start-time)) timeout-seconds))
      ;; BLOCKING CALL - problem source
      (accept-process-output process 0.1 nil t)  ; 't' = block indefinitely
      )))
```

**Why it fails:**
- `accept-process-output` with `t` as the last argument means "block until output or process exit"
- If the subprocess hangs without producing output, `accept-process-output` blocks forever
- The timeout check in the `while` loop is never reached
- Emacs becomes completely unresponsive

### The Robust Implementation (Correct)

```elisp
(defun gptel-auto-workflow--shell-command-with-timeout (command timeout-seconds)
  "Execute COMMAND with TIMEOUT-SECONDS timeout.
Returns (success . output) or (timeout . nil)."
  (let* ((buffer (generate-new-buffer " *timeout-cmd*"))
         (process nil)
         (timer nil)
         (done nil)
         (start-time (current-time)))
    
    (unwind-protect
        (progn
          ;; Start the process
   
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-NTc8Gn.txt. Use Read tool if you need more]...