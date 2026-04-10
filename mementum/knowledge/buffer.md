---
title: Buffer Management in Emacs
status: active
category: knowledge
tags: [buffers, emacs-lisp, concurrency, patterns, async]
---

# Buffer Management in Emacs

Buffer-local variables and proper buffer context management are critical for writing robust Emacs Lisp code, especially when dealing with asynchronous operations, parallel execution, or multi-buffer workflows. This page synthesizes common pitfalls and patterns for working with buffers in gptel and related projects.

## 1. Buffer-Local Variable Pattern

### The Core Problem

Buffer-local variables must be set in the **correct buffer context**. Setting them in the wrong buffer leads to unexpected `nil` values or state corruption.

### The Anti-Patterns

```elisp
;; WRONG - sets in current buffer, not target buffer
(setq gptel--fsm-last fsm)

;; WRONG - not buffer-local (global variable)
(setq-local gptel--fsm-last fsm)  ; when in wrong buffer

;; WRONG - variable not declared buffer-local
(setq gptel-backend (alist-get backend models))  ; clobbers global
```

### The Solution

```elisp
;; RIGHT - switch to target buffer first
(with-current-buffer target-buf
  (setq-local gptel--fsm-last fsm))

;; RIGHT - create in current buffer if that's the correct context
(setq-local gptel--fsm-last fsm)  ; when already in target buffer
```

### Common Buffer-Local Variables

| Variable | Purpose |
|----------|---------|
| `gptel--fsm-last` | FSM state |
| `gptel-backend` | LLM backend |
| `gptel-model` | Model name |
| `gptel--stream-buffer` | Response buffer |
| `default-directory` | Current directory |
| `gptel-auto-workflow--headless` | Headless mode flag |

### Detection Pattern

Use this to verify buffer-local variables are set correctly:

```elisp
;; Test that variable is set in correct buffer
(with-current-buffer target
  (should gptel--fsm-last))

;; Debug: check which buffer has the value
(dolist (buf (buffer-list))
  (when (buffer-local-value 'gptel--fsm-last buf)
    (message "Found in: %s" buf)))
```

## 2. Buffer Context in Async Callbacks

### The Problem

When using `dolist` or `mapc` to spawn parallel tasks, callbacks fire asynchronously and may execute in the **wrong buffer context**, causing race conditions.

```elisp
;; PROBLEM: All 5 iterations spawn immediately, but callbacks
;;          fire later in an unpredictable buffer context
(dolist (target targets)
  (gptel-agent--task ...))  ; callbacks overwrite global state!
```

### The Solution: Hash Tables for State Management

Instead of relying on buffer-local or global variables, use hash tables keyed by unique identifiers:

```elisp
;; Three hash tables for different state types

(defvar my/gptel--agent-task-state (make-hash-table :test 'equal))
(defvar gptel-auto-experiment--grade-state (make-hash-table :test 'equal))
(defvar gptel-auto-workflow--worktree-state (make-hash-table :test 'equal))
```

### State Hash Table Structure

| Hash Table | Key Type | Value Structure |
|------------|----------|-----------------|
| `my/gptel--agent-task-state` | task-id (integer) | `(:done :timeout-timer :progress-timer)` |
| `gptel-auto-experiment--grade-state` | grade-id (integer) | `(:done :timer)` |
| `gptel-auto-workflow--worktree-state` | target (string) | `(:worktree-dir :current-branch)` |

### Closure-Captured Local Variables

For loop-iteration state that shouldn't be shared:

```elisp
(dolist (target targets)
  (let* ((results nil)
         (best-score 0)
         (no-improvement-count 0))
    ;; Each iteration gets its own binding via closure
    (gptel-agent--task
     (lambda (response)
       ;; Uses captured `target`, `results`, etc.
       (cl-incf no-improvement-count)))))
```

### Lookup Pattern

Always use explicit lookup instead of relying on buffer context:

```elisp
;; WRONG - relies on buffer being correct
(benchmark-score gptel-auto-experiment--current-target)

;; RIGHT - explicit lookup
(benchmark-score (gethash target gptel-auto-workflow--worktree-state))
```

## 3. Directory Local Variables in Non-File Buffers

### The Problem

Setting `default-directory` alone does **NOT** auto-load `.dir-locals.el`. Emacs only auto-loads it when visiting files.

### The Critical Detail: Trailing Slash

`locate-dominating-file` requires a **trailing slash** on directories:

```elisp
;; WRONG - no trailing slash, locate-dominating-file fails
(setq default-directory (file-name-directory "~/.emacs.d"))
;; => "~/"

;; RIGHT - with trailing slash
(setq default-directory (file-name-as-directory "~/.emacs.d"))
;; => "~/.emacs.d/"
```

### Complete Pattern

```elisp
(defun gptel-auto-workflow--setup-dir-locals (buf project-root)
  "Load .dir-locals.el for PROJECT-ROOT into buffer BUF."
  (let ((root (file-name-as-directory (expand-file-name project-root))))
    (with-current-buffer buf
      (setq-local default-directory root)  ;; MUST have trailing slash!
      (hack-dir-local-variables-non-file-buffer))))
```

### Safe Variables for Dir-Locals

Use `:safe #'always` in `defcustom` to avoid prompts:

```elisp
(defcustom gptel-auto-workflow-projects nil
  "List of project configurations."
  :type '(repeat string)
  :safe #'always)  ;; Prevents prompts in daemon mode
```

Without `:safe #'always`, Emacs prompts for confirmation in daemon mode, which hangs because there's no UI to display the prompt.

## 4. Kill Buffer Query Functions

### The Inverted Logic Problem

`kill-buffer-query-functions` has **inverted semantics** compared to most hooks:

| Return Value | Meaning |
|--------------|---------|
| `t` | Allow the kill (proceed) |
| `nil` | Block the kill (prevent) |

### The Bug

```elisp
;; WRONG - inverted logic
(defun gptel-auto-workflow--suppress-kill-buffer-query ()
  (not gptel-auto-workflow--headless))

;; When headless = t:
;;   (not t) = nil
;;   nil means "block the kill" ← OPPOSITE of intended!
```

### The Fix

```elisp
;; CORRECT - return t to allow killing in headless mode
(defun gptel-auto-workflow--suppress-kill-buffer-query ()
  (or gptel-auto-workflow--headless t))
```

### Adding to the Hook

```elisp
(add-hook 'kill-buffer-query-functions
          #'gptel-auto-workflow--suppress-kill-buffer-query)
```

### Testing the Hook

```elisp
;; Verify the function returns correct value
(message "Query result: %s"
         (funcall #'gptel-auto-workflow--suppress-kill-buffer-query))
;; => t when headless, nil otherwise
```

## 5. Summary: Buffer Management Patterns

| Pattern | Use When | Key Function |
|---------|----------|--------------|
| `with-current-buffer` | Setting buffer-local vars | Context switching |
| Hash tables with IDs | Parallel async operations | State isolation |
| Closure-captured `let*` | Loop iteration state | Per-iteration binding |
| `file-name-as-directory` | Paths for dir-locals | Trailing slash |
| `hack-dir-local-variables-non-file-buffer` | Loading .dir-locals | Explicit loading |
| Return `t` in `*-query-functions` | Allowing actions | Hook semantics |

## Related

- [[auto-workflow]] - Workflow automation using these patterns
- [[fsm]] - Finite state machines using buffer-local state
- [[concurrency]] - Async task management
- [[dir-locals]] - Directory local variables
- [[gptel-agent]] - Agent execution with callback handling

---

**Status**: Active  
**Synthesized**: 2026-04-02  
**Sources**: Commits 4a23297, 3d8b77e, e74d58d, 221ef37