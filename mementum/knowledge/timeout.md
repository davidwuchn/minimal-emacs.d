---
title: Timeout Handling in Emacs/GPTel
status: active
category: knowledge
tags: [timeout, curl, subprocess, process-management, robustness]
---

# Timeout Handling in Emacs/GPTel

## Overview

Timeouts are critical for maintaining responsive Emacs daemons, especially when dealing with external processes, LLM API calls, and long-running experiments. This guide covers the three major timeout scenarios encountered in the GPTel codebase, their failure modes, and robust solutions.

## 1. Curl Low-Speed Timeout

### The Problem

Curl commands fail with exit code 28 (timeout) even when `--max-time` is set generously to 600 or 900 seconds.

### Root Cause

The issue is **low-speed detection**, which operates independently of `--max-time`:

| Curl Flag | Purpose | Default |
|-----------|---------|---------|
| `--connect-timeout` | Connection phase only | seconds |
| `--max-time` | Total operation time | seconds |
| `-y` | Seconds of low-speed before abort | seconds |
| `-Y` | Bytes/second threshold | bytes/sec |

**Critical insight**: Low-speed detection (`-y/-Y`) runs independently of `--max-time`. When an LLM "thinks" for >15 seconds without streaming output, curl aborts with exit 28 regardless of the max-time setting.

### Curl Argument Ordering

Arguments are appended: `global args → backend args`. Backend `--max-time` overrides global, but `-y/-Y` from global remain active:

```bash
# What you think you're running:
curl --max-time 900 https://api.example.com/chat

# What actually runs (if global has -y/-Y):
curl -y 15 -Y 50 --max-time 900 https://api.example.com/chat
#                          ^-- This doesn't stop low-speed detection!
```

### The Fix

Remove low-speed detection from global curl arguments:

```elisp
;; BEFORE (in gptel-ext-abort.el)
(defvar my/gptel--install-fast-curl-timeouts
  '("-y" "15" "-Y" "50" "--max-time" "300"))

;; AFTER - Remove -y/-Y, keep only max-time
(defvar my/gptel--install-fast-curl-timeouts
  '("--max-time" "300"))
```

### For Long-Running API Calls

When calling LLMs that may think for extended periods:

1. **Remove low-speed detection entirely:**
   ```elisp
   (setq my/gptel--install-fast-curl-timeouts
         '("--max-time" "900"))
   ```

2. **Or set very generous thresholds:**
   ```elisp
   (setq my/gptel--install-fast-curl-timeouts
         '("-y" "300" "-Y" "1" "--max-time" "900"))
   ; 300 seconds of < 1 byte/sec before abort
   ```

## 2. Experiment Timeout Handling

### Problem Context

Auto-experiments have multiple stages (analyze, execute, grade, benchmark, decide) that can collectively exceed the time budget:

```elisp
(defcustom gptel-auto-experiment-time-budget 600
  "Time budget per experiment in seconds (default: 10 min).")
```

### Implementation Pattern

```elisp
(defun run-experiment-with-timeout (experiment-id target callback)
  "Run EXPERIMENT-ID on TARGET with TIMEOUT."
  (let ((finished nil)
        (start-time (float-time)))
    ;; Timer-based timeout
    (run-with-timer gptel-auto-experiment-time-budget nil
                    (lambda ()
                      (unless finished
                        (setq finished t)
                        (gptel-auto-workflow-delete-worktree)
                        (funcall callback
                                 (list :target target
                                       :id experiment-id
                                       :error "timeout")))))
    ;; ... run experiment stages ...
    ))
```

### Why Timeouts May Fail

| Failure Mode | Cause | Impact |
|--------------|-------|--------|
| Blocking process | gptel uses curl which may block | Timer never fires |
| Multiple stages | Each stage may take minutes | Cumulative delay |
| Event loop blocked | `accept-process-output` with blocking flag | Daemon unresponsive |

### Solution: Stage-Level Timeouts

Each stage should have its own timeout:

```elisp
(defvar gptel-experiment-stage-timeouts
  '((:ana
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-7KtKgW.txt. Use Read tool if you need more]...