---
title: Buffer Handling in Emacs - Patterns and Pitfalls
status: active
category: knowledge
tags: [emacs, buffers, parallel-execution, race-conditions, dir-locals, hooks]
---

# Buffer Handling in Emacs - Patterns and Pitfalls

This page documents critical patterns and bugs related to buffer handling in Emacs, particularly in the context of the gptel-auto-workflow system. These lessons apply to any Emacs project dealing with buffer-local state, parallel execution, and non-file buffers.

## 1. Buffer-Local Variables: The Context Rule

Buffer-local variables must be set in the correct buffer context. This is a common source of bugs.

### The Problem

```elisp
;; WRONG - sets in current buffer, not target buffer
(setq gptel--fsm-last fsm)

;; WRONG - not buffer-local at all
(setq-local gptel--fsm-last fsm)  ; in wrong buffer context
```

### The Solution

```elisp
;; RIGHT - switch to target buffer first
(with-current-buffer target-buf
  (setq-local gptel--fsm-last fsm))

;; Or create in current buffer if that's correct context
(setq-local gptel--fsm-last fsm)  ; when already in correct buffer
```

### Common Buffer-Local Variables

| Variable | Purpose | Typical Context |
|----------|---------|-----------------|
| `gptel--fsm-last` | FSM state tracking | Agent buffers |
| `gptel-backend` | LLM backend configuration | Chat buffers |
| `gptel-model` | Model name | Chat buffers |
| `gptel--stream-buffer` | Response streaming buffer | Agent buffers |
| `default-directory` | Current directory for commands | All buffers |

### Diagnostic Pattern

When a buffer-local variable is unexpectedly nil:

1. Check which buffer you're in: `(current-buffer)`
2. Verify the variable is buffer-local: `(local-variable-if-set-p 'var-name)`
3. Test in correct context:

```elisp
(with-current-buffer target
  (should gptel--fsm-last))  ; Verify set in correct buffer
```

---

## 2. Parallel Execution: Avoiding Race Conditions

When running parallel tasks in Emacs (e.g., with `dolist`), global or buffer-local variables get overwritten by race conditions.

### The Bug Pattern

In `gptel-auto-workflow--run-with-targets`, `dolist` spawned 5 experiments in parallel:

```elisp
;; This spawns all 5 targets simultaneously
(dolist (target targets)
  (gptel-auto-experiment--run target))
```

Callbacks from `gptel-agent--task` fire asynchronously, and global/buffer-local variables get overwritten by race conditions.

### Evidence of the Bug

- `gptel-auto-experiment--grade-done=t` found in `*Minibuf-1*` (wrong buffer)
- 5 timeout messages, only 1 result recorded
- Hash table shows 5 tasks, but state was lost between callbacks

### The Fix: Hash Tables + Closure Variables

Use three hash tables keyed by target/id:

```elisp
;; 1. Task execution state
(defvar my/gptel--agent-task-state (make-hash-table :test 'equal))
;; Key: task-id (integer)
;; Value: (:done :timeout-timer :progress-timer)

;; 2. Grading state
(defvar gptel-auto-experiment--grade-state (make-hash-table :test 'equal))
;; Key: grade-id (integer)
;; Value: (:done :timer)

;; 3. Worktree state
(defvar gptel-auto-workflow--worktree-state (make-hash-table :test 'equal))
;; Key: target (string)
;; Value: (:worktree-dir :current-branch)
```

For loop-local variables, use `let*` to capture state in closures:

```elisp
(let* ((results nil)
       (best-score -1)
       (no-improvement-count 0))
  ;; Each loop iteration gets its own copy
  (dolist (target targets)
    (gptel-auto-experiment--run target)))
```

### Functions Updated

| Function | Change |
|----------|--------|
| `gptel-auto-experiment-loop` | Local state in closure |
| `gptel-auto-workflow-create-worktree` | Hash table lookup |
| `gptel-auto-workflow-delete-worktree` | Hash table removal |
| `gptel-auto-experiment-benchmark` | Uses `current-target` for lookup |
| Benchmark score functions | Use `current-target` for lookup |

### Verification

After the fix, parallel execution produces correct results:

```
Hash table: 5 tasks, 5 worktrees
Results: 5 complete (no timeout losses)
State: Correctly isolated per target
```

---

## 3. dir-locals.el in Non-File Buffers

Setting `default-directory` alone does NOT auto-load `.dir-locals.el`. You must call `hack-dir-local-variables-non-file-buffer` explicitly.

### Critical Requirement

`default-directory` MUST have a **trailing slash** for `hack-dir-local-variables-non-file-buffer` to work!

### The Problem

```elisp
;; Without trailing slash - FAILS
(setq default-directory (file-name-directory "~/.emacs.d"))
;; Result: "~/"
;; locate-dominating-file fails to find .dir-locals.el
```

```elisp
;; With trailing slash - WORKS
(setq default-directory (file-name-directory "~/.emacs.d/"))
;; Result: "~/"
;; locate-dominating-file finds .dir-locals.el
```

Actually, the issue is more subtle:

```elisp
;; WRONG: loses trailing slash
(file-name-directory "~/.emacs.d")  ; => "~/"

;; RIGHT: preserves trailing slash
(file-name-as-directory (expand-file-name "~/.emacs.d"))
;; => "/Users/user/.emacs.d/"
```

### The Fix

```elisp
(let ((root (file-name-as-directory (expand-file-name project-root))))
  (with-current-buffer buf
    (setq-local default-directory root)  ;; MUST have trailing slash!
    (hack-dir-local-variables-non-file-buffer)
    ...))
```

### Safe Variables for dir-locals

Use `:safe #'always` in `defcustom` to mark variables as safe for dir-locals without prompting:

```elisp
(defcustom gptel-auto-workflow-project-root nil
  "Project root directory."
  :type 'string
  :safe #'always)  ;; Prevents prompt in daemon mode
```

**Critical:** Without `:safe #'always`, Emacs prompts for confirmation in daemon mode, which hangs because there's no UI to display the prompt.

### Context

Multi-project auto-workflow assumed `.dir-locals.el` would load when changing directory. This was wrong—Emacs only auto-loads it when visiting files, not when manually setting `default-directory`.

---

## 4. Kill Buffer Query: Inverted Logic Trap

When adding functions to `kill-buffer-query-functions`, the return value semantics are inverted from what you might expect.

### The Problem

"Buffer X modified; kill anyway?" prompt appeared during auto-workflow execution, blocking headless operation.

### The Wrong Code

```elisp
;; WRONG - inverted logic
(defun gptel-auto-workflow--suppress-kill-buffer-query ()
  (not gptel-auto-workflow--headless))

;; When gptel-auto-workflow--headless is t:
;; (not t) = nil
;; kill-buffer-query-functions interprets nil as "block the kill"
```

### The Correct Logic

For `kill-buffer-query-functions`:

| Return Value | Meaning |
|--------------|---------|
| `nil` | Block the kill (prompt user) |
| `t` | Allow the kill (proceed) |

```elisp
;; RIGHT
(defun gptel-auto-workflow--suppress-kill-buffer-query ()
  (or gptel-auto-workflow--headless t))

;; When headless is t: (or t t) = t → allow kill
;; When headless is nil: (or nil t) = t → always allow
```

### Location

`gptel-tools-agent.el:2695-2698`

### Lesson

When adding hooks to `*-query-functions`, always verify the actual return value semantics:

- `nil` often means "block/prevent"
- `t` often means "allow/proceed"

**Always test the actual behavior**, not just the docstring intent. The semantic meaning may be inverted depending on the hook.

---

## 5. Summary: Key Patterns

| Pattern | Key Insight |
|---------|--------------|
| Buffer-local variables | Use `with-current-buffer` to set in correct context |
| Parallel state | Use hash tables keyed by target/id, not global variables |
| Loop closure state | Use `let*` to capture per-iteration state |
| dir-locals in non-file buffers | Explicit call + trailing slash on `default-directory` |
| Query suppression hooks | Return `t` to allow, `nil` to block |

---

## Related

- [[fsm]] - FSM state management (uses buffer-local `gptel--fsm-last`)
- [[auto-workflow]] - The workflow system this documentation describes
- [[parallel-execution]] - Parallel task handling patterns
- [[dir-locals]] - Directory local variables configuration
- [[hooks]] - Emacs hook best practices

---

## Status

✅ Documented 2026-04-02
Source commits: 4a23297, 3d8b77e, e74d58d, 221ef37