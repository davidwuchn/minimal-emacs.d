---
title: Buffer Management in Emacs - Best Practices and Pitfalls
status: active
category: knowledge
tags: [buffer, buffer-local, state-management, emacs-lisp, concurrency, hooks]
---

# Buffer Management in Emacs - Best Practices and Pitfalls

## Overview

Buffer management in Emacs involves more than just creating and killing buffers. This page covers critical patterns for working with buffer-local variables, managing state in asynchronous operations, loading directory-local variables in programmatic buffers, and understanding hook return value semantics.

## 1. Buffer-Local Variable Best Practices

### The Core Problem

Buffer-local variables must be set in the **correct buffer context**. Setting a buffer-local variable in the wrong buffer is a common source of bugs that are difficult to diagnose.

### The Wrong Way

```elisp
;; WRONG - sets in current buffer, not target
(with-current-buffer target-buf
  (setq gptel--fsm-last fsm))  ; Sets in current-lexical-buffer, not target-buf!

;; WRONG - not buffer-local at all
(setq gptel--fsm-last fsm)  ; Global variable, not buffer-local

;; WRONG - correct form but wrong buffer context
(setq-local gptel--fsm-last fsm)  ; In wrong buffer
```

### The Correct Way

```elisp
;; RIGHT - switch to target buffer first, THEN set
(with-current-buffer target-buf
  (setq-local gptel--fsm-last fsm))

;; Or ensure you're in the correct buffer before setting
(save-excursion
  (set-buffer target-buf)
  (setq-local gptel--fsm-last fsm))
```

### Diagnostic Pattern

When a buffer-local variable is unexpectedly `nil`:

1. Check buffer context with `current-buffer`
2. Verify the variable exists with `boundp` and `local-variable-if-set-p`
3. Print the variable's buffer binding

```elisp
(defun debug-buffer-local (variable buffer)
  "Debug a buffer-local VARIABLE in BUFFER."
  (with-current-buffer buffer
    (list :variable variable
          :value (if (boundp variable) (symbol-value variable) 'unbound)
          :boundp (boundp variable)
          :buffer-local-p (local-variable-if-set-p variable))))
```

### Common Buffer-Local Variables in gptel

| Variable | Purpose | Typical Context |
|----------|---------|-----------------|
| `gptel--fsm-last` | FSM state machine state | Agent buffer |
| `gptel-backend` | Active LLM backend | Session buffer |
| `gptel-model` | Current model name | Session buffer |
| `gptel--stream-buffer` | Response stream buffer | Communication buffer |
| `gptel--task-data` | Task metadata | Task-specific buffer |

## 2. State Management in Parallel Operations

### The Parallel Execution Problem

When running multiple operations in parallel (e.g., `dolist` spawning multiple experiments), buffer-local and global variables suffer from race conditions:

```elisp
;; PROBLEMATIC: Global state gets overwritten
(dolist (target targets)
  (gptel-auto-workflow--run-with-targets target)
  (setq gptel-auto-experiment--grade-done t))  ; Race condition!

;; Symptoms:
;; - Variable `t` found in wrong buffer (*Minibuf-1*)
;; - Only 1 result recorded despite 5 tasks
;; - Hash table shows correct count after fix
```

### Solution: Hash Tables for Task-State Mapping

Replace buffer-local/global state with hash tables keyed by task identifier:

```elisp
;; State hash tables
(defvar my/gptel--agent-task-state (make-hash-table :test 'equal))
(defvar gptel-auto-experiment--grade-state (make-hash-table :test 'equal))
(defvar gptel-auto-workflow--worktree-state (make-hash-table :test 'equal))

;; Accessor functions
(defun gptel-auto-workflow--get-worktree-state (target)
  "Get worktree state for TARGET."
  (gethash target gptel-auto-workflow--worktree-state))

(defun gptel-auto-workflow--set-worktree-state (target state)
  "Set worktree STATE for TARGET."
  (puthash target state gptel-auto-workflow--worktree-state))

(defun gptel-auto-workflow--clear-worktree-state (target)
  "Clear worktree state for TARGET."
  (remhash target gptel-auto-workflow--worktree-state))
```

### State Structure Examples

```elisp
;; Agent task state structure
(:done . nil)                    ; t when complete
(:timeout-timer . #<timer>)     ; Timeout timer object
(:progress-timer . #<timer>)    ; Progress timer object

;; Grade state structure
(:done . nil)                    ; t when grading complete
(:timer . #<timer>)             ; Timer for grade timeout

;; Worktree state structure
(:worktree-dir . "/path/to/worktree")
(:current-branch . "experiment-branch")
```

### Closure-Captured Loop Variables

For variables that should be local to each loop iteration, use `let*` to create closure-captured copies:

```elisp
(defun gptel-auto-experiment-loop (target benchmark-fn score-fn)
  ;; Each iteration gets its own binding
  (let* ((results '())
         (best-score -1)
         (no-improvement-count 0)
         (iteration 0))
    
    (while (< iteration max-iterations)
      (let ((score (funcall score-fn target)))
        (push score results)
        (when (> score best-score)
          (setq best-score score
                no-improvement-count 0))
        (cl-incf iteration)))
    
    ;; Return collected results
    (list :results (reverse results)
          :best-score best-score)))
```

## 3. dir-locals.el in Non-File Buffers

### The Problem

Setting `default-directory` alone does **not** auto-load `.dir-locals.el`. Emacs only auto-loads directory-local variables when visiting files.

```elisp
;; WRONG: .dir-locals.el NOT loaded
(with-current-buffer buf
  (setq default-directory "/path/to/project/")
  ;; Variables from .dir-locals.el still unset!
  )
```

### The Critical Detail: Trailing Slash

`default-directory` **must** have a trailing slash for `hack-dir-local-variables-non-file-buffer` to find `.dir-locals.el`:

```elisp
;; WRONG - no trailing slash
(file-name-directory "~/.emacs.d")  ; => "~/"

;; RIGHT - trailing slash preserved
(file-name-directory "~/.emacs.d/") ; => "~/.emacs.d/"
```

The `file-name-directory` function strips everything after the last slash, but only if there's a slash to begin with.

### Correct Pattern

```elisp
(defun my/setup-buffer-with-dir-locals (buf project-root)
  "Setup BUF with directory-local variables from PROJECT-ROOT."
  (let ((root (file-name-as-directory (expand-file-name project-root))))
    (with-current-buffer buf
      (setq default-directory root)  ; MUST have trailing slash!
      (hack-dir-local-variables-non-file-buffer)
      ;; Now buffer-local variables from .dir-locals.el are set
      )))

;; Usage
(my/setup-buffer-with-dir-locals 
  some-buffer 
  "~/projects/my-project")
```

### Safe Variables in defcustom

Use `:safe #'always` to mark directory-local variables as safe, preventing prompts that hang in daemon mode:

```elisp
(defcustom gptel-auto-workflow-timeout 300
  "Timeout for workflow operations."
  :type 'integer
  :safe #'always  ; Prevents dir-locals prompt in daemon
  :group 'gptel-auto-workflow)
```

### Quick Test for dir-locals Loading

```elisp
(defun test-dir-locals-load (dir)
  "Test if .dir-locals.el loads correctly from DIR."
  (let ((buf (get-buffer-create " *dir-locals-test*"))
        (root (file-name-as-directory (expand-file-name dir))))
    (with-current-buffer buf
      (setq default-directory root)
      (hack-dir-local-variables-non-file-buffer)
      (mapcar (lambda (var)
                (cons var (and (boundp var) (symbol-value var))))
              '(major-mode default-directory))))
```

## 4. Hook Return Value Semantics

### The kill-buffer-query-functions Gotcha

The `kill-buffer-query-functions` hook has **inverted semantics** from what you might expect:

| Return Value | Meaning |
|--------------|---------|
| `t` | **Allow** the operation |
| `nil` | **Block** the operation |

### The Wrong Implementation

```elisp
;; WRONG - logic is inverted!
(defun gptel-auto-workflow--suppress-kill-buffer-query ()
  (not gptel-auto-workflow--headless))

;; When headless is t:
;;   (not t) => nil
;;   nil in query-functions => BLOCK the kill
```

### The Correct Implementation

```elisp
;; RIGHT - returns t to allow killing
(defun gptel-auto-workflow--suppress-kill-buffer-query ()
  (or gptel-auto-workflow--headless t))

;; When headless is t:
;;   (or t t) => t => ALLOW killing
;; When headless is nil:
;;   (or nil t) => t => ALLOW killing (default: always allow)
```

### Hook Return Value Reference

| Hook | `nil` means | `t` means |
|------|-------------|-----------|
| `kill-buffer-query-functions` | Block kill | Allow kill |
| `kill-buffer-hook` | Continue | Continue (no effect) |
| `before-change-functions` | Continue | Continue (no effect) |
| `window-configuration-change-hook` | Continue | Continue (no effect) |

### Testing Hook Behavior

```elisp
(defun test-kill-buffer-query ()
  "Test kill buffer query suppression."
  (let ((gptel-auto-workflow--headless t)
        (query-result nil))
    (add-to-list 'kill-buffer-query-functions
                 (lambda () (setq query-result gptel-auto-workflow--headless)))
    (unwind-protect
        (progn
          (gptel-auto-workflow--suppress-kill-buffer-query)
          (should query-result))
      (setq kill-buffer-query-functions
            (delq (lambda (f) (eq (function-name f) 'gptel-auto-workflow--suppress-kill-buffer-query))
                  kill-buffer-query-functions)))))
```

## 5. Common Pitfalls Summary

| Pitfall | Symptom | Solution |
|---------|---------|----------|
| Wrong buffer context | Variable `nil` in target buffer | Use `with-current-buffer` before `setq-local` |
| Missing trailing slash | `.dir-locals.el` not loaded | Use `file-name-as-directory` |
| Global state in parallel | Race conditions, lost data | Use hash tables keyed by task ID |
| Inverted hook return | Operation blocked unexpectedly | Check semantics: `t` = allow |
| Closure not captured | Loop variable shared | Use `let*` for loop-local bindings |

## 6. Debugging Checklist

When debugging buffer-related issues:

```elisp
(defun my/debug-buffer-state (buf)
  "Comprehensive buffer state debugging."
  (with-current-buffer buf
    (list :buffer-name (buffer-name)
          :default-directory default-directory
          :major-mode major-mode
          :gptel-fsm (when (boundp 'gptel--fsm-last) gptel--fsm-last)
          :gptel-backend (when (boundp 'gptel-backend) gptel-backend)
          :gptel-model (when (boundp 'gptel-model) gptel-model)
          :local-variables (buffer-local-variables))))
```

## Related

- [[Emacs Concurrency Patterns]] - Async operations and process management
- [[Directory Local Variables]] - Project-wide settings
- [[State Machines (FSM)]] - FSM implementation patterns
- [[gptel-auto-workflow]] - Multi-target experiment workflow
- [[Hook Programming]] - Understanding hook semantics
- [[Hash Table Utilities]] - State storage patterns

## References

- Emacs Manual: Buffer-Local Variables
- Emacs Manual: Directory Local Variables
- Emacs Manual: Killing Buffers
- Source: `gptel-tools-agent.el:2695-2698`
- Fix Commits: 4a23297, 3d8b77e, e74d58d, 221ef37
```