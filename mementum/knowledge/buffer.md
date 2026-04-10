---
title: Buffer Management in Emacs
status: active
category: knowledge
tags: [emacs, buffer, buffer-local, parallelism, race-condition, hooks]
---

# Buffer Management in Emacs

This knowledge page covers essential patterns and pitfalls when working with buffers in Emacs, particularly in the context of async operations, parallel execution, and workflow automation.

## 1. Buffer-Local Variables: The Core Pattern

Buffer-local variables in Emacs allow each buffer to have its own value for a variable. This is essential when managing state across multiple buffers (e.g., worktrees, experiments, agents).

### 1.1 The Correct Way to Set Buffer-Local Variables

```elisp
;; WRONG - sets in current buffer, not target
(setq gptel--fsm-last fsm)

;; WRONG - not buffer-local (global)
(setq-local gptel--fsm-last fsm)  ; in wrong buffer

;; RIGHT - switch to target buffer first
(with-current-buffer target-buf
  (setq-local gptel--fsm-last fsm))

;; Or create in current buffer if that's correct context
(setq-local gptel--fsm-last fsm)  ; in correct buffer
```

### 1.2 Common Buffer-Local Variables

| Variable | Purpose | Typical Context |
|----------|---------|-----------------|
| `gptel--fsm-last` | FSM state for agent | Per-buffer agent state |
| `gptel-backend` | LLM backend | Buffer-specific backend |
| `gptel-model` | Model name | Buffer-specific model |
| `gptel--stream-buffer` | Response buffer | Streaming response |
| `default-directory` | Current directory | Project context |

### 1.3 Signal of Buffer-Local Bugs

- Variable is `nil` unexpectedly → check buffer context
- Variable works in some buffers but not others → buffer-local issue
- Use `with-current-buffer` to ensure correct context

```elisp
;; Test pattern
(with-current-buffer target
  (should gptel--fsm-last))  ; Verify set in correct buffer
```

## 2. Parallel Execution and Race Conditions

When running parallel operations (e.g., multiple experiments in a workflow), buffer-local variables can cause race conditions if not properly isolated.

### 2.1 The Problem: Global State in Parallel Loops

```elisp
;; PROBLEMATIC: dolist spawns 5 experiments in parallel
(dolist (target targets)
  (gptel-agent--task target))  ; Callbacks fire asynchronously!
;; Callbacks overwrite global/buffer-local variables → race conditions
```

### 2.2 The Solution: Hash Tables with Target/ID Keys

Use hash tables to store state keyed by target or task ID:

```elisp
;; 1. Task execution state - keyed by task-id (integer)
(defvar my/gptel--agent-task-state (make-hash-table :test #'equal))
;; Value: (:done :timeout-timer :progress-timer)

;; 2. Grading state - keyed by grade-id (integer)
(defvar gptel-auto-experiment--grade-state (make-hash-table :test #'equal))
;; Value: (:done :timer)

;; 3. Worktree state - keyed by target (string)
(defvar gptel-auto-workflow--worktree-state (make-hash-table :test #'equal))
;; Value: (:worktree-dir :current-branch)

;; 4. Loop-local variables via closure capture
(let* ((results nil)
       (best-score 0)
       (no-improvement-count 0))
  ;; Each loop iteration has its own copy!
  (gptel-auto-experiment-run target))
```

### 2.3 Lookup Patterns

```elisp
;; Using current-target for hash table lookup
(defun gptel-auto-experiment-benchmark (target)
  (let* ((state (gethash target gptel-auto-workflow--worktree-state))
         (worktree-dir (plist-get state :worktree-dir)))
    ;; Use worktree-dir for benchmark
    ...))

;; Setting state
(puthash target
        (list :worktree-dir worktree-dir :current-branch branch)
        gptel-auto-workflow--worktree-state)
```

### 2.4 Evidence of the Bug

- Variable `gptel-auto-experiment--grade-done=t` found in `*Minibuf-1*` (wrong buffer)
- 5 timeout messages, only 1 result recorded
- Hash table shows 5 tasks, 5 worktrees after fix

## 3. Loading dir-locals.el in Non-File Buffers

Setting `default-directory` alone does **NOT** auto-load `.dir-locals.el`. You must call `hack-dir-local-variables-non-file-buffer` explicitly.

### 3.1 Critical: Trailing Slash Requirement

`default-directory` **MUST** have a trailing slash for `hack-dir-local-variables-non-file-buffer` to work!

```elisp
;; WITHOUT trailing slash - FAILS
(file-name-directory "~/.emacs.d")  ; → "~/"
(locate-dominating-file "~/" ".dir-locals.el")  ; → nil

;; WITH trailing slash - WORKS
(file-name-directory "~/.emacs.d/")  ; → "~/.emacs.d/"
(locate-dominating-file "~/.emacs.d/" ".dir-locals.el")  ; → path
```

### 3.2 The Fix: Ensure Trailing Slash

```elisp
(let ((root (file-name-as-directory (expand-file-name project-root))))
  (with-current-buffer buf
    (setq-local default-directory root)  ;; MUST have trailing slash!
    (hack-dir-local-variables-non-file-buffer)
    ...))
```

### 3.3 Safe Variables for dir-locals

Use `:safe #'always` in `defcustom` to mark variables as safe for dir-locals without prompting:

```elisp
(defcustom gptel-auto-workflow-project-root nil
  "Project root directory."
  :type 'string
  :safe #'always)  ;; Prevents prompt in daemon mode!
```

**Why this matters:** In daemon mode, prompts hang because there's no UI to show them.

## 4. Kill Buffer Query Functions: Inverted Logic Trap

When adding functions to `kill-buffer-query-functions`, the return value semantics are inverted from what you might expect.

### 4.1 The Problem

During auto-workflow execution in headless mode, the prompt "Buffer X modified; kill anyway?" appeared, blocking operation.

### 4.2 Root Cause: Inverted Logic

```elisp
;; WRONG - inverted logic
(defun gptel-auto-workflow--suppress-kill-buffer-query ()
  (not gptel-auto-workflow--headless))

;; When headless = t:
;;   (not t) = nil
;;   kill-buffer-query-functions interprets nil as "block the kill"
```

### 4.3 The Correct Logic

For `kill-buffer-query-functions`:
- Return `t` = allow killing (proceed)
- Return `nil` = block killing (prevent)

```elisp
;; CORRECT
(defun gptel-auto-workflow--suppress-kill-buffer-query ()
  (or gptel-auto-workflow--headless t))

;; When headless = t:
;;   (or t t) = t
;;   Allows killing without prompt
```

### 4.4 General Lesson

When adding hooks to `*-query-functions`, understand the return value semantics:
- `nil` often means "block/prevent"
- `t` often means "allow/proceed"

**Always test the actual behavior**, not just the docstring intent.

### 4.5 Adding to Hook

```elisp
(add-hook 'kill-buffer-query-functions
          #'gptel-auto-workflow--suppress-kill-buffer-query)
```

## 5. Actionable Patterns Summary

| Pattern | Code | When to Use |
|---------|------|-------------|
| Set buffer-local | `(with-current-buffer buf (setq-local var val))` | Need buffer-specific value |
| Ensure trailing slash | `(file-name-as-directory (expand-file-name dir))` | Setting default-directory |
| Parallel state storage | `(puthash key value hash-table)` | Multiple async tasks |
| Query function | `(or condition t)` | Suppressing prompts |
| Loop closure capture | `(let* (...) (closure-fn))` | Per-iteration state |

## 6. Key Functions Updated (Historical Reference)

- `gptel-auto-experiment-loop`: local state in closure
- `gptel-auto-workflow-create-worktree/delete-worktree`: hash table
- `gptel-auto-experiment-benchmark`: uses current-target for lookup
- Benchmark score functions: use current-target for lookup

### Commit History

- ✅ Fixed 2026-03-28
- Commits: `4a23297`, `3d8b77e`, `e74d58d`, `221ef37`
- Verified: 5 parallel tasks, 5 worktrees in hash tables

---

## Related

- [Emacs Hooks](https://www.gnu.org/software/emacs/manual/html_node/emacs/Hooks.html)
- [Buffer-Local Variables](https://www.gnu.org/software/emacs/manual/html_node/emacs/Buffer_002dLocal-Variables.html)
- [Directory Local Variables](https://www.gnu.org/software/emacs/manual/html_node/emacs/Directory-Variables.html)
- [gptel-auto-workflow](./gptel-auto-workflow.md)
- [Parallelism in Emacs](./parallelism.md)

---

**Last Updated**: 2026-04-02
**Status**: active
**Category**: knowledge
**Tags**: emacs, buffer, buffer-local, parallelism, race-condition, hooks, async