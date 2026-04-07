---
title: Timeout Handling in Emacs and Curl
status: active
category: knowledge
tags: [timeout, curl, process-management, subprocess, error-handling, elisp]
---

# Timeout Handling in Emacs and Curl

## Overview

Timeout handling is critical for robust systems. This page synthesizes three production incidents and their solutions to provide actionable patterns for timeout management in Emacs (using gptel) and curl-based network operations.

**Key Lesson:** Emacs has a single-threaded event loop. Blocking operations can freeze the entire daemon. Timeout mechanisms must be timer-based, not rely on polling loops.

---

## Curl Timeout Mechanisms

Curl provides **three independent timeout mechanisms** that can conflict if not understood:

| Mechanism | Flag | Scope | Behavior |
|-----------|------|-------|----------|
| Connection timeout | `--connect-timeout <seconds>` | DNS + TCP handshake only | Aborts if connection not established in time |
| Total timeout | `--max-time <seconds>` | Entire operation | Aborts if total request exceeds limit |
| Low-speed timeout | `-y <seconds>` + `-Y <bytes/sec>` | Transfer rate | Aborts if average speed drops below threshold |

### Critical Discovery: Low-Speed Detection is Independent

**The `-y/-Y` flags operate independently of `--max-time`.** When both are set:

```bash
# This does NOT work as expected:
curl --max-time 600 -y 15 -Y 50 https://api.example.com/completion

# If LLM thinks for 16 seconds without streaming output:
# → curl exits with code 28 (CURLE_OPERATION_TIMEDOUT)
# → --max-time 600 is NEVER reached
```

**Argument Order Matters:** Curl appends global args before backend args:

```
curl [global-args] [backend-args]
curl -y 15 -Y 50 --max-time 900  # -y/-Y still active!
```

### Pattern: Remove Low-Speed Detection for LLM APIs

For long-running API calls (LLM inference, code generation):

```elisp
;; BAD: Low-speed timeout causes false positives
(setq gptel-curl-extra-args '("-y" "15" "-Y" "50"))

;; GOOD: Backend timeout handles long-running calls
(setq gptel-curl-extra-args '("--max-time" "900"))
```

---

## Common Timeout Issues

### Issue 1: Curl Exit Code 28 Despite Long max-time

**Symptoms:**
- Exit code 28 (`CURLE_OPERATION_TIMEDOUT`)
- Backend configured with `--max-time 600` or higher
- LLM "thinking" for extended periods

**Root Cause:** Global `-y/-Y` flags still active after backend args appended.

**Fix:** Remove `-y/-Y` from global curl extra args:

```elisp
;; lisp/modules/gptel-ext-abort.el
(defun my/gptel--install-fast-curl-timeouts ()
  "Install timeout arguments for fast-failing curl requests."
  (setq gptel-curl-extra-args
        '("--connect-timeout" "10"  ; Connection timeout only
          "--max-time" "300")))     ; Per-request timeout
```

### Issue 2: Transient Errors Masquerading as Timeouts

Cold-start issues can appear as timeouts:

| Error Code | Message | API | Solution |
|------------|---------|-----|----------|
| 1013 | "server is initializing" | Moonshot | Add to transient errors, retry |
| 500 | Internal server error | Any | Retry with backoff |
| 502 | Bad gateway | Any | Retry with backoff |

```elisp
;; lisp/modules/gptel-ext-retry.el
(defvar gptel-ext-retry--transient-errors
  '("1013"                          ; Moonshot cold start
    "server is initializing"
    "500" "502" "503"               ; Server errors
    "rate limit" "too many requests"))
```

### Issue 3: Daemon Unresponsive Due to Blocking accept-process-output

**Severity:** CRITICAL

**Symptoms:**
- Daemon at 0% CPU but unresponsive to `emacsclient`
- Bash subprocess running for 30+ minutes
- No output produced, main thread blocked

**Root Cause:** `accept-process-output` with blocking flag (`t`) can hang indefinitely:

```elisp
;; BAD: Blocks forever if no output arrives
(while (and (not done)
            (< (float-time (time-since start)) timeout-seconds))
  (accept-process-output process 0.1 nil t))  ; LAST ARG
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-97CPCd.txt. Use Read tool if you need more]...