---
title: Buffer Management Patterns in Emacs
status: active
category: knowledge
tags: [emacs, buffers, parallel-execution, dir-locals, gptel-auto-workflow]
---

# Buffer Management Patterns in Emacs

## Overview

This page documents critical patterns for managing buffers in Emacs, particularly when working with the gptel-auto-workflow system. Buffer management is fundamental to avoiding race conditions in parallel execution, correctly loading project settings, and preventing unwanted prompts during automated workflows.

## Buffer-Local Variables

### The Core Problem

Buffer-local variables in Emacs are buffer-specific, meaning their values are isolated to a particular buffer. When multiple operations run concurrently or switch between buffers, incorrect buffer context leads to nil values, wrong data, or race conditions.

### Correct Pattern: Set in Correct Buffer Context

```elisp
;; WRONG - sets in current buffer, not target
(setq gptel--fsm-last fsm)

;; WRONG - not buffer-local (global value)
(setq-local gptel--fsm-last fsm)  ; in wrong buffer

;; RIGHT - switch to target buffer first
(with-current-buffer target-buf
  (setq-local gptel--fsm-last fsm))

;; Or create in current buffer if that's correct context
(setq-local gptel--fsm-last fsm)  ; in correct buffer
```

### Common Buffer-Local Variables

| Variable | Purpose | Typical Context |
|----------|---------|-----------------|
| `gptel--fsm-last` | FSM state tracking | Agent buffers |
| `gptel-backend` | LLM backend configuration | gptel buffers |
| `gptel-model` | Model name | gptel buffers |
| `gptel--stream-buffer` | Response buffer | Stream handling |
| `default-directory` | Current directory | All buffers |

### Diagnostic Test

```elisp
;; Verify variable is set in correct buffer
(with-current-buffer target
  (should gptel--fsm-last))  ; Fails if set in wrong buffer

;; Check buffer-local binding
(local-variable-if-set-p 'gptel--fsm-last)
```

### Signal of Misuse

- Variable is nil unexpectedly → check buffer context
- Variable works in some buffers but not others → buffer-local issue
- Use `with-current-buffer` to ensure correct context

---

## Parallel Execution and State Management

### The Callback Context Bug

When running parallel experiments (e.g., via `dolist`), callbacks fire asynchronously. Using global or buffer-local variables causes race conditions where later operations overwrite earlier state.

### Root Cause Analysis

1. `dolist` in `gptel-auto-workflow--run-with-targets` spawns 5 experiments in parallel
2. Callbacks from `gptel-agent--task` fire asynchronously
3. Global/buffer-local variables get overwritten by race conditions

### Evidence of Race Condition

- `gptel-auto-experiment--grade-done=t` found in `*Minibuf-1*` (wrong buffer)
- 5 timeout messages, only 1 result recorded
- Hash table shows 5 tasks, 5 worktrees after fix

### Solution: Hash Tables for State Management

Use hash tables keyed by target/id to store state instead of buffer-local variables:

```elisp
;; 1. Agent task state - keyed by task-id (integer)
(defvar my/gptel--agent-task-state (make-hash-table :test 'equal))
;; Value: (:done :timeout-timer :progress-timer)

;; 2. Grading state - keyed by grade-id (integer)
(defvar gptel-auto-experiment--grade-state (make-hash-table :test 'equal))
;; Value: (:done :timer)

;; 3. Worktree state - keyed by target (string)
(defvar gptel-auto-workflow--worktree-state (make-hash-table :test 'equal))
;; Value: (:worktree-dir :current-branch)
```

### Loop-Local Variables via Closure

```elisp
;; Each loop iteration captures its own copy via let*
(let* ((results (list))
       (best-score 0)
       (no-improvement-count 0))
  ;; Use these in callback closure - each iteration has independent state
  (gptel-agent--task ...))
```

### Functions Using Hash Table Lookup

```elisp
;; Look up state by current target
(defun gptel-auto-workflow-get-worktree (target)
  (gethash target gptel-auto-workflow--worktree-state))

;; Update state atomically
(defun gptel-auto-workflow-set-worktree (target state)
  (puthash target state gptel-auto-workflow--worktree-state))
```

### Verification

After fix, parallel execution produces:
- 5 parallel tasks created
- 5 worktrees in hash tables
- No race conditions in callbacks

---

## Directory Local Variables in Non-File Buffers

### The Problem

Setting `default-directory` alone does **not** auto-load `.dir-locals.el`. Must call `hack-dir-local-variables-non-file-buffer` explicitly for non-file buffers.

### Critical Requirement: Trailing Slash

`default-directory` **MUST** have a trailing slash for `hack-dir-local-variables-non-file-buffer` to work!

```elisp
;; Without trailing slash - FAILS
(file-name-directory "~/.emacs.d")  ; => "~/"
;; locate-dominating-file fails to find .dir-locals.el

;; With trailing slash - WORKS
(file-name-directory "~/.emacs.d/") ; => "~/.emacs.d/"
;; locate-dominating-file finds .dir-locals.el
```

### The Fix

```elisp
;; Ensure trailing slash with file-name-as-directory
(let ((root (file-name-as-directory (expand-file-name project-root))))
  (with-current-buffer buf
    (setq-local default-directory root)  ;; MUST have trailing slash!
    (hack-dir-local-variables-non-file-buffer)
    ...))
```

### Safe Variables for Dir-Locals

Use `:safe #'always` in `defcustom` to mark variables as safe for dir-locals:

```elisp
(defcustom gptel-auto-workflow-project-root nil
  "Project root directory."
  :type 'string
  :safe #'always)  ;; Prevents prompt in daemon mode
```

Without `:safe #'always`, Emacs prompts for confirmation, which hangs in daemon mode (no UI to show prompt).

### Pattern Summary

```elisp
(defun gptel-auto-workload-init-buffer (buf project-root)
  "Initialize BUF with dir-locals from PROJECT-ROOT."
  (with-current-buffer buf
    (setq-local default-directory
                (file-name-as-directory (expand-file-name project-root)))
    (hack-dir-local-variables-non-file-buffer)))
```

---

## Kill Buffer Query Suppression

### The Problem

"Buffer X modified; kill anyway?" prompt appeared during auto-workflow execution, blocking headless operation.

### Inverted Logic in Query Functions

For `kill-buffer-query-functions`:
- Return `t` = allow killing
- Return `nil` = block killing

### Wrong Implementation

```elisp
;; WRONG - inverted logic
(defun gptel-auto-workflow--suppress-kill-buffer-query ()
  (not gptel-auto-workflow--headless))
```

When `gptel-auto-workflow--headless` is `t`:
- `(not t)` = `nil`
- `kill-buffer-query-functions` interprets `nil` as "block the kill"

### Correct Implementation

```elisp
;; RIGHT - allow kill when headless, otherwise allow too
(defun gptel-auto-workflow--suppress-kill-buffer-query ()
  (or gptel-auto-workflow--headless t))

;; Alternative: always allow
(defun gptel-auto-workflow--suppress-kill-buffer-query ()
  t)
```

### Hook Registration

```elisp
(add-hook 'kill-buffer-query-functions
          #'gptel-auto-workflow--suppress-kill-buffer-query)
```

### Lesson

When adding hooks to `*-query-functions`, understand the return value semantics:
- `nil` often means "block/prevent"
- `t` often means "allow/proceed"

Always test the actual behavior, not just the docstring intent.

---

## Common Patterns Summary

| Pattern | Problem | Solution |
|---------|---------|----------|
| Buffer-local context | Variable nil in wrong buffer | Use `with-current-buffer` |
| Parallel state | Race conditions | Hash tables keyed by target |
| Dir-locals non-file | Not auto-loaded | Explicit `hack-dir-local-variables-non-file-buffer` |
| Kill query suppression | Inverted logic | Return `t` to allow |

---

## Related

- [FSM Pattern](fsm) - State machine implementation using buffer-local variables
- [Auto-Workflow](auto-workflow) - Parallel experiment execution
- [Worktree Management](worktree) - Git worktree operations with state tracking
- [Emacs Hooks](hooks) - Query function patterns
- [Project Configuration](project) - Dir-locals and project-specific settings

---

## Status

✅ Knowledge page maintained - Updated 2026-04-02

## See Also

- `gptel-tools-agent.el:2695-2698` - Kill query suppression location
- Commits 4a23297, 3d8b77e, e74d58d, 221ef37 - Parallel execution fixes