---
title: Buffer-Local Variables and Local Bindings in Emacs
status: active
category: knowledge
tags: [emacs-lisp, buffers, variables, testing, concurrency, anti-patterns]
---

# Buffer-Local Variables and Local Bindings in Emacs

## Overview

Buffer-local variables and `let` bindings are essential for writing correct Emacs Lisp code, especially when dealing with asynchronous operations, parallel execution, or test suites. This page synthesizes common pitfalls and solutions learned from real bug fixes.

## Core Concepts

### What Are Buffer-Local Variables?

Buffer-local variables have a separate value for each buffer. Setting a variable with `setq-local` only affects the current buffer:

```elisp
;; This variable is buffer-local
(defvar-local gptel--fsm-last nil
  "Last FSM state in current buffer.")

;; Set in the current buffer only
(setq-local gptel--fsm-last 'running)
```

### What Are Local Bindings?

Local bindings created with `let` or `let*` only exist within that lexical scope:

```elisp
(let ((counter 0))
  ;; counter is 0 here
  (cl-incf counter)
  ;; counter is 1 here
  )
;; counter doesn't exist here
```

## The Critical Bug: Race Conditions with Global State

### Problem Description

When running parallel operations (e.g., `dolist` spawning multiple async tasks), global or buffer-local variables get overwritten by concurrent callbacks.

### Symptoms

| Symptom | Example |
|---------|---------|
| Variable found in wrong buffer | `gptel-auto-experiment--grade-done=t` in `*Minibuf-1*` |
| Multiple timeouts | 5 timeout messages from 5 parallel tasks |
| Missing results | Only 1 result recorded despite 5 tasks |
| Hash table inconsistency | Shows fewer entries than expected |

### Root Cause Analysis

```
┌─────────────────────────────────────────────────────────────────┐
│  dolist spawns 5 parallel tasks                                 │
│  ↓                                                              │
│  Task 1: writes to global-var                                   │
│  Task 2: writes to global-var  ← Race condition!                │
│  Task 3: writes to global-var                                   │
│  Task 4: writes to global-var                                   │
│  Task 5: writes to global-var                                   │
│  ↓                                                              │
│  Callbacks fire asynchronously                                  │
│  ↓                                                              │
│  Global state corrupted (last writer wins)                      │
└─────────────────────────────────────────────────────────────────┘
```

### The Fix: State Hash Tables

Replace global/buffer-local variables with hash tables keyed by unique identifiers:

```elisp
;; State hash tables - keyed by unique identifiers
(defvar my/gptel--agent-task-state (make-hash-table :test 'equal)
  "Task execution state. Key: task-id (integer), Value: (:done :timeout-timer :progress-timer).")

(defvar gptel-auto-experiment--grade-state (make-hash-table :test 'equal)
  "Grading state. Key: grade-id (integer), Value: (:done :timer).")

(defvar gptel-auto-workflow--worktree-state (make-hash-table :test 'equal)
  "Worktree state. Key: target (string), Value: (:worktree-dir :current-branch).")

;; Storing state
(puthash target 
         (list :worktree-dir worktree-dir
               :current-branch branch)
         gptel-auto-workflow--worktree-state)

;; Retrieving state
(gethash target gptel-auto-workflow--worktree-state)
```

### Local Variables in Closures

For loop iterations that spawn async callbacks, capture state in the closure:

```elisp
(defun gptel-auto-experiment-loop (targets)
  "Run experiments on TARGETS in parallel."
  (dolist (target targets)
    ;; Each iteration gets its OWN copies via let*
    (let* ((results (list))
           (best-score 0)
           (no-improvement-count 0)
           (current-target target))
      
      
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-jHwDdR.txt. Use Read tool if you need more]...