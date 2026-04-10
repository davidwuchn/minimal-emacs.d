---
title: Buffer Management in Emacs
status: active
category: knowledge
tags: [buffers, elisp, pattern, debugging, concurrency]
---

# Buffer Management in Emacs

Buffer-local variables are a powerful mechanism in Emacs for maintaining state specific to individual buffers. However, they introduce subtle complexities that can lead to hard-to-debug issues, especially in concurrent or async contexts. This page synthesizes key patterns, bugs, and solutions discovered through the gptel-auto-workflow development.

## Buffer-Local Variables: The Core Pattern

### The Fundamental Principle

Buffer-local variables must be set **in the correct buffer context**. This is the single most important rule for working with buffer-local state.

### Correct vs. Incorrect Patterns

```elisp
;; ❌ WRONG - sets in current buffer, not target buffer
(setq gptel--fsm-last fsm)

;; ❌ WRONG - buffer-local but set in wrong buffer
(with-current-buffer wrong-buffer
  (setq-local gptel--fsm-last fsm))

;; ✅ CORRECT - switch to target buffer first
(with-current-buffer target-buf
  (setq-local gptel--fsm-last fsm))

;; ✅ CORRECT - if current buffer IS the correct context
(setq-local gptel--fsm-last fsm)
```

### Common Buffer-Local Variables in gptel

| Variable | Purpose |
|----------|---------|
| `gptel--fsm-last` | FSM state tracking |
| `gptel-backend` | LLM backend configuration |
| `gptel-model` | Model name for API calls |
| `gptel--stream-buffer` | Response streaming buffer |
| `gptel-auto-workflow--headless` | Headless execution flag |

### Signal of Buffer-Local Issues

Watch for these symptoms:
- Variable is `nil` unexpectedly → check buffer context
- Variable works in some buffers but not others → buffer-local issue
- Race conditions in async code → likely global state problem

### Test Pattern

```elisp
;; Verify variable is set in correct buffer
(with-current-buffer target
  (should gptel--fsm-last)
  (should gptel-backend))
```

## The Buffer-Local Callback Context Bug

### The Problem

Parallel execution with `dolist` spawned multiple experiments simultaneously, but callbacks from `gptel-agent--task` fired asynchronously and overwrote global/buffer-local variables, causing race conditions.

### Symptoms Observed

- `gptel-auto-experiment--grade-done=t` found in `*Minibuf-1*` (wrong buffer)
- 5 timeout messages, only 1 result recorded
- Hash table inconsistency: 5 tasks but only partial results

### Root Cause Analysis

```elisp
;; This spawns all 5 experiments in parallel
(dolist (target targets)
  (gptel-auto-workflow--run-with-targets target))
```

The sequence of events:
1. `dolist` iterates and starts 5 async tasks
2. Callbacks fire in unpredictable order
3. Global variables get overwritten by whichever callback runs last
4. State from target A appears in target B's buffer

### The Fix: Hash Tables for State Management

Instead of buffer-local variables for async state, use hash tables keyed by target/id:

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

### Experiment Loop Local Variables

For closure-captured state in loops, use `let*` to create independent copies:

```elisp
(let* ((results nil)
       (best-score 0)
       (no-improvement-count 0))
  ;; Each iteration gets its own binding - no shared state
  (dolist (target targets)
    (lambda ()
      ;; This closure captures THIS iteration's bindings
      (run-experiment target))))
```

### Key Functions Updated

| Function | Change |
|----------|--------|
| `gptel-auto-experiment-loop` | Local state in closure |
| `gptel-auto-workflow-create-worktree` | Uses hash table |
| `gptel-auto-workflow-delete-worktree` | Uses hash table |
| `gptel-auto-experiment-benchmark` | Uses `current-target` for lookup |
| Benchmark score functions | Use `current-target` for lookup |

### Verification

After the fix:
```
Hash table entries: 5 tasks, 5 worktrees
All 5 parallel tasks completed successfully
No cross-contamination of state
```

## dir-locals.el in Non-File Buffers

### The Discovery

Setting `default-directory` alone does **NOT** auto-load `.dir-locals.el` for non-file buffers. You must call `hack-dir-local-variables-non-file-buffer` explicitly.

### Critical Requirement: Trailing Slash

The `default-directory` **MUST have a trailing slash** for `hack-dir-local-variables-non-file-buffer` to work:

```elisp
;; ❌ WRONG - no trailing slash
(file-name-directory "~/.emacs.d")  ; => "~/"
;; locate-dominating-file fails to find .dir-locals.el

;; ✅ CORRECT - with trailing slash
(file-name-directory "~/.emacs.d/") ; => "~/.emacs.d/"
;; locate-dominating-file finds .dir-locals.el
```

### The Fix

```elisp
(let ((root (file-name-as-directory (expand-file-name project-root))))
  (with-current-buffer buf
    (setq-local default-directory root)  ;; MUST have trailing slash!
    (hack-dir-local-variables-non-file-buffer)
    ...))
```

### Additional Tip: Safe Variables for Dir-Locals

Use `:safe #'always` in `defcustom` to mark variables as safe:

```elisp
(defcustom gptel-auto-workflow-projects nil
  "List of project configurations."
  :type '(repeat (cons string plist))
  :safe #'always)
```

Without this, Emacs prompts for confirmation, which hangs in daemon mode (no UI to display the prompt).

## Kill Buffer Query Functions: Inverted Logic Trap

### The Problem

The "Buffer X modified; kill anyway?" prompt appeared during auto-workflow execution, blocking headless operation.

### The Bug

```elisp
;; ❌ WRONG - inverted logic
(defun gptel-auto-workflow--suppress-kill-buffer-query ()
  (not gptel-auto-workflow--headless))
```

When `gptel-auto-workflow--headless` is `t`:
- `(not t)` = `nil`
- `kill-buffer-query-functions` interprets `nil` as "block the kill"

### The Fix

For `kill-buffer-query-functions`:
- Return `t` = allow killing
- Return `nil` = block killing

```elisp
;; ✅ CORRECT
(defun gptel-auto-workflow--suppress-kill-buffer-query ()
  (or gptel-auto-workflow--headless t))
```

### General Rule for Query Functions

When adding hooks to `*-query-functions`, understand the return value semantics:
- `nil` often means "block/prevent"
- `t` often means "allow/proceed"

Always test the actual behavior, not just the docstring intent.

### Location

`gptel-tools-agent.el:2695-2698`

## Common Pitfalls Summary

| Pitfall | Symptom | Solution |
|---------|---------|----------|
| Setting buffer-local in wrong buffer | Variable nil unexpectedly | Use `with-current-buffer` |
| Global state in async code | Race conditions | Use hash tables keyed by id |
| Missing trailing slash on `default-directory` | `.dir-locals.el` not loaded | Use `file-name-as-directory` |
| Inverted query function logic | Prompt blocks execution | Return `t` to allow, `nil` to block |
| Not calling `hack-dir-local-variables` | Dir-locals ignored in non-file buffers | Call explicitly |

## Related Topics

- [FSM Pattern] - State machine implementation using buffer-local variables
- [Async Patterns] - Handling concurrent operations in Emacs
- [Project Management] - Multi-project support with dir-locals
- [Headless Operation] - Running Emacs without a frame

---

**Status**: Active  
**Last Updated**: 2026-04-02  
**Pattern Origin**: gptel-auto-workflow development  
**Commits**: 4a23297, 3d8b77e, e74d58d, 221ef37