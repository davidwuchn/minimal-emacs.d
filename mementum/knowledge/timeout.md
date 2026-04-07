---
title: Timeout Handling in Emacs - Complete Guide
status: active
category: knowledge
tags: [emacs, timeout, process, curl, debugging]
---

# Timeout Handling in Emacs - Complete Guide

Timeouts are critical for maintaining responsive Emacs daemons and preventing runaway processes. This guide covers timeout patterns for shell commands, HTTP requests (via curl), and multi-stage workflows.

## Overview: Timeout Mechanisms in Emacs

Emacs provides multiple timeout mechanisms, each with different use cases and failure modes:

| Mechanism | Scope | Blocking Risk | Use Case |
|-----------|-------|---------------|----------|
| `run-with-timer` | Timer-based | Low | Safety nets, long operations |
| `accept-process-output` | Process-based | High if misused | Reading process output |
| `sit-for` | Display-based | None | Cooperative yielding |
| curl `--max-time` | Network request | Low | HTTP request limits |
| curl `-y/-Y` | Low-speed detection | Independent | Detecting stalled connections |

## Pattern 1: Robust Shell Command Timeout (CRITICAL)

The most important timeout pattern: shell commands must never block the main thread.

### Anti-Pattern: Blocking `accept-process-output`

```elisp
;; ❌ DANGEROUS: This can hang indefinitely
(while (and (not done)
            (< (float-time (time-since start)) timeout-seconds))
  (accept-process-output process 0.1 nil t))  ; 't' blocks until output or exit
```

**Why it fails:**
- `accept-process-output` with `t` as the last argument means "block until output or process exit"
- If the subprocess hangs without producing output, Emacs blocks forever
- The timeout check is never reached
- Daemon becomes completely unresponsive

### Correct Pattern: Timer-Based Safety Net

```elisp
(defun gptel-auto-workflow--shell-command-with-timeout (command timeout-seconds)
  "Execute COMMAND with TIMEOUT-SECONDS limit.
Returns (success . output) or (timeout . nil) or (error . message)."
  (let* ((buffer (generate-new-buffer " *shell-timeout*"))
         (process nil)
         (done nil)
         (timer nil)
         (start (current-time))
         result)
    
    ;; Start the subprocess
    (with-current-buffer buffer
      (setq process
            (make-process
             :name "shell-timeout"
             :buffer buffer
             :command (list "bash" "-c" command)
             :sentinel (lambda (p msg)
                        (when (memq (process-status p) '(exit signal))
                          (setq done 'finished)))))
    
    ;; Timer-based safety net (runs independently)
    (setq timer
          (run-with-timer timeout-seconds nil
                          (lambda ()
                            (unless done
                              (setq done 'timeout)))))
    
    ;; Non-blocking poll loop
    (while (eq done nil)
      ;; Non-blocking: returns immediately if no output
      (accept-process-output process 0.1 nil nil)
      (sit-for 0.01)  ; Cooperative yield to allow timer to fire
      (when (>= (float-time (time-since start)) timeout-seconds)
        (setq done 'timeout)))
    
    ;; Cleanup sequence: timer first, then process, then buffer
    (when timer (cancel-timer timer))
    (when (and process (process-live-p process))
      (delete-process process))
    
    (unwind-protect
        (progn
          (setq result
                (cond
                 ((eq done 'timeout)
                  (cons 'timeout nil))
                 ((eq done 'finished)
                  (cons 'success (string-trim (buffer-string buffer))))
                 (t
                  (cons 'error "Unknown state")))))
      (when (buffer-live-p buffer)
        (kill-buffer buffer)))
    
    result))
```

### Cleanup Sequence (Critical Order)

```elisp
;; CORRECT ORDER:
(when timer (cancel-timer timer))           ; 1. Cancel timer first
(when (and process (process-live-p process)) ; 2. Then kill process
  (delete-process process))
(when (buffer-live
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-nUwJZe.txt. Use Read tool if you need more]...