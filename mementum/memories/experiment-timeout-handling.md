# Experiment Timeout Handling

## Problem

Experiment 2 took 900s (15 minutes), exceeding the 600s (10 minute) budget.

## Current Implementation

```elisp
(defcustom gptel-auto-experiment-time-budget 600
  "Time budget per experiment in seconds (default: 10 min).")
```

Timeout set via `run-with-timer`:
```elisp
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

## Why Timeout May Fail

1. **Blocking process**: gptel uses curl which may block
2. **Multiple stages**: analyze + execute + grade + benchmark + decide
3. **Timer not firing**: Emacs event loop blocked

## Potential Solutions

### 1. Process Timeout via Curl

DashScope backend uses `--max-time 300` (5 min). This should abort individual requests.

### 2. Kill Curl Process on Timeout

Store curl process PID and kill on timeout:
```elisp
(let ((curl-pid (process-id gptel--curl-process)))
  (run-with-timer timeout nil
                  (lambda ()
                    (when (process-live-p gptel--curl-process)
                      (delete-process gptel--curl-process)))))
```

### 3. Reduce Backend Timeout

For experiments, reduce curl timeout:
```elisp
:curl-args '("--http1.1" "--max-time" "120" "--connect-timeout" "10")
```

### 4. Add Stage-Level Timeouts

Each stage should respect its own timeout:
- analyze: 60s
- execute: 300s
- grade: 60s
- benchmark: 60s
- decide: 30s

## Symbol

λ timeout - robust timeout handling