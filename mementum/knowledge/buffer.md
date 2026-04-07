---
title: Buffer Management in Emacs
status: active
category: knowledge
tags: [buffers, buffer-local, async, workflow, emacs-lisp]
---

# Buffer Management in Emacs

## Overview

Buffers are fundamental to Emacs operation, serving as the primary container for text and state. This knowledge page covers critical patterns for managing buffer-local variables, handling async operations that reference buffers, and avoiding common pitfalls with buffer context.

**Key principle**: Always be aware of *which buffer your code is executing in* and *which buffer your variables belong to*.

## Buffer-Local Variables

### Setting Buffer-Local Variables Correctly

Buffer-local variables are tied to a specific buffer. Setting them requires being in the correct buffer context.

```elisp
;; WRONG - sets in current buffer, not target
(setq gptel--fsm-last fsm)

;; WRONG - not in the correct buffer context
(setq-local gptel--fsm-last fsm)  ; executed in wrong buffer

;; CORRECT - switch to target buffer first
(with-current-buffer target-buf
  (setq-local gptel--fsm-last fsm))

;; CORRECT - if current buffer is already the right context
(setq-local gptel--fsm-last fsm)
```

### Common Buffer-Local Variables in gptel

| Variable | Purpose |
|----------|---------|
| `gptel--fsm-last` | FSM state machine state |
| `gptel-backend` | LLM backend configuration |
| `gptel-model` | Active model name |
| `gptel--stream-buffer` | Response stream buffer |
| `gptel--task-state` | Task execution state |

### Diagnostic Pattern

When a buffer-local variable is nil unexpectedly:

```elisp
;; Check which buffer you're in
(current-buffer)

;; Check if variable exists and is buffer-local
(local-variable-if-set-p 'variable-name)
(buffer-local-value 'variable-name (get-buffer "*scratch*"))

;; Debug: Verify correct buffer context
(message "In buffer: %s, variable value: %S" 
         (buffer-name) some-var)
```

## Async Operations and Buffer Context

### The Race Condition Problem

When running async operations in parallel (e.g., `dolist` with callbacks), buffer-local variables can be overwritten by interleaved operations:

```elisp
;; PROBLEMATIC: Global state shared across parallel operations
(let ((target-buf (gptel-auto-workflow--get-buffer target)))
  (dolist (target targets)
    (gptel-agent--task 
     (lambda (result)
       ;; Callback fires asynchronously
       ;; target-buf may have changed by now!
       (process-result target-buf result)))))
```

### Solution: Hash Tables for Async State

Use hash tables keyed by unique identifiers to maintain per-operation state:

```elisp
;; Define state hash tables
(defvar gptel-auto-workflow--worktree-state (make-hash-table :test 'equal))
(defvar gptel-auto-workflow--grade-state (make-hash-table :test 'equal))
(defvar gptel-auto-workflow--task-state (make-hash-table :test 'equal))

;; Store state by target/id
(puthash target 
         (list :worktree-dir dir :current-branch branch)
         gptel-auto-workflow--worktree-state)

;; Retrieve state in callbacks
(let ((state (gethash current-target gptel-auto-workflow--worktree-state)))
  (plist-get state :worktree-dir))
```

### Closure-Captured Local Variables

For loop variables that need per-iteration copies, use `let*` to create closures with independent state:

```elisp
;; Each iteration gets its own binding
(dolist (target targets)
  (let* ((results nil)
         (best-score 0)
         (no-improvement-count 0)
         (worktree (gethash target gptel-auto-workflow--worktree-state)))
    
    ;; These variables are independent per iteration
    (gptel-agent--task
     (lambda (result)
       (push result results)
       (cl-incf no-improvement-count)
       (maybe-terminate))))))
```

### State Hash Table Reference

| Hash Table | Key Type | Value Structure |
|------------|----------|-----------------|
| `my/gptel--agent-task-state` | task-id (integer) | `(:done :timeout-timer :progress-timer)` |
| `gptel-a
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-2iiDW5.txt. Use Read tool if you need more]...