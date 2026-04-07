---
title: Timeout Patterns for Emacs and Curl
status: active
category: knowledge
tags: [timeout, curl, process, blocking, timer]
related: [mementum/knowledge/cron.md]
---

# Timeout Patterns for Emacs and Curl

Patterns for implementing robust timeouts in Emacs subprocess handling and curl API calls.

## Emacs Process Timeout

### The Blocking Bug

**Problem:** `accept-process-output` with blocking flag can hang indefinitely:

```elisp
;; BAD - blocks forever if subprocess hangs
(accept-process-output process 0.1 nil t)  ; last arg 't' = BLOCK
```

If subprocess hangs without producing output, Emacs main thread blocks forever. Daemon becomes unresponsive.

### Timer-Based Solution

Use independent timer as safety net:

```elisp
(let (done timer)
  (setq timer (run-with-timeout timeout-seconds nil
                                (lambda ()
                                  (unless done
                                    (setq done 'timeout)))))
  (while (and (not done) (process-live-p process))
    (accept-process-output process 0.1 nil nil)  ; NON-BLOCKING
    (sit-for 0.01))  ; cooperative yield
  (cancel-timer timer)
  (when (process-live-p process)
    (delete-process process)))
```

**Key principles:**
1. Timer runs independently of blocking operations
2. Non-blocking `accept-process-output` (last arg nil)
3. Explicit state tracking (`'finished`, `'timeout`)
4. Clean up timer before process

## Curl Timeout Mechanisms

Curl has THREE independent timeout mechanisms:

### 1. connect-timeout

Connection phase only:

```bash
--connect-timeout 10  # 10 seconds to establish connection
```

### 2. max-time

Total operation time:

```bash
--max-time 300  # 5 minutes total including response
```

### 3. low-speed-timeout

Independent of max-time:

```bash
-y 15   # Abort if <15 seconds of low-speed
-Y 50   # Low-speed threshold: 50 bytes/sec
```

**The trap:** If LLM thinks for >15s without streaming, curl aborts with exit 28 regardless of `--max-time`.

### For Long-Running API Calls

Remove low-speed detection or set generous thresholds:

```elisp
;; For subagents with long thinking time
(setq gptel-curl-extra-args '("--max-time" "900" "--connect-timeout" "10"))
;; NO -y/-Y flags
```

## Experiment Timeout

Each experiment stage should have its own timeout:

```elisp
(defcustom gptel-auto-experiment-time-budget 600
  "Total time budget per experiment in seconds.")
```

**Stage timeouts:**
- Analyze: 60s
- Execute: 300s
- Grade: 60s
- Benchmark: 60s
- Decide: 30s

### Kill Curl on Timeout

Store curl process and kill on timeout:

```elisp
(let ((curl-process gptel--curl-process))
  (run-with-timer timeout nil
                  (lambda ()
                    (when (process-live-p curl-process)
                      (delete-process curl-process)))))
```

## Common Exit Codes

| Code | Meaning | Fix |
|------|---------|-----|
| 28 | Operation timeout | Increase `--max-time` or remove `-y/-Y` |
| 56 | Recv failure | Network issue, retry with backoff |
| 52 | Empty reply | Server error, retry |

## Related

- `mementum/memories/shell-command-timeout-blocking.md` - Blocking bug fix
- `mementum/memories/experiment-timeout-handling.md` - Experiment stages
- `mementum/memories/curl-low-speed-timeout-issue.md` - Curl low-speed trap