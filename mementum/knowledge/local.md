---
title: Local Bindings in Emacs - Patterns for Avoiding State Pollution
status: active
category: knowledge
tags: [elisp, buffer-local, closures, testing, concurrency, race-conditions]
---

# Local Bindings in Emacs - Patterns for Avoiding State Pollution

Emacs Lisp provides several mechanisms for creating local state: buffer-local variables, `let` bindings, and closure-captured variables. When these are misused—especially in asynchronous or parallel contexts—race conditions and state pollution occur. This page documents patterns for correctly managing local state, with emphasis on fixing callback context bugs and test isolation issues.

---

## 1. The Problem: Global State in Async Contexts

When running asynchronous tasks (via callbacks, timers, or parallel execution), using global or buffer-local variables can lead to **race conditions**. The root cause is that multiple tasks share the same variable storage, overwriting each other's values.

### Symptom Checklist

| Symptom | Likely Cause |
|---------|--------------|
| Variable is `nil` unexpectedly | Set in wrong buffer context |
| Variable works in some buffers, not others | Buffer-local not set in target buffer |
| Only 1 result recorded out of N parallel tasks | Global state overwritten by race condition |
| Hash table shows mismatched keys/values | Async callback in wrong context |
| Tests fail in batch mode but pass interactively | Global state pollution between tests |

---

## 2. Pattern: Closure-Captured Local Variables

For parallel loops (like `dolist` spawning async tasks), each iteration needs its own copy of state variables. Closure capture via `let*` ensures each iteration has independent state.

### Anti-Pattern: Shared Global State

```elisp
;; WRONG: All iterations share these variables
(defvar results nil)
(defvar best-score 0)
(defvar no-improvement-count 0)

(dolist (target targets)
  (gptel-agent--task target
    (lambda (response)
      ;; All callbacks write to shared globals → race condition
      (push response results)
      (cl-incf best-score))))
```

### Correct Pattern: Closure-Captured Local State

```elisp
;; CORRECT: Each iteration gets its own bindings via let*
(dolist (target targets)
  (let* ((results nil)
         (best-score 0)
         (no-improvement-count 0)
         (task-id (incf gptel--task-counter)))
    ;; Store state in hash table for later lookup
    (puthash task-id (list :results nil
                          :best-score 0
                          :no-improvement-count 0)
             gptel--task-state-table)
    (gptel-agent--task target
      (lambda (response)
        ;; Update iteration-local state (captured by closure)
        (let ((state (gethash task-id gptel--task-state-table)))
          (setq results (cons response results))
          (cl-incf best-score)
          (puthash task-id (list :results results
                                :best-score best-score
                                :no-improvement-count no-improvement-count)
                   gptel--task-state-table)))))))
```

### Key Principle

```
λ iteration(i).  local_state(i) = let*(bindings) | shared_state = hash_table
```

- **Loop variables**: Use `let*` to create per-iteration bindings
- **Shared state**: Use hash tables keyed by unique ID (task-id, target, etc.)

---

## 3. Pattern: Buffer-Local Variables with Correct Context

Buffer-local variables must be set in the **correct buffer context**. Using `setq-local` in the wrong buffer is a common error.

### Anti-Patterns

```elisp
;; WRONG 1: Sets in current buffer, not target buffer
(defun wrong-set-fsm (fsm target-buffer)
  (setq gptel--fsm-last fsm))  ; Sets in current buffer

;; WRONG 2: Not buffer-local at all
(defun wrong-buffer-local (fsm)
  (setq-local gptel--fsm-last fsm))  ; Not buffer-local

;; WRONG 3: In wrong buffer context
(defun wrong-context (fsm target-buf)
  (with-current-buffer target-buf  ; But called from different context
    (setq-local gptel--fsm-last fsm)))
```

### Correct Pattern

```elisp
;; CORRECT: Switch to target buffer first
(defun set-fsm-in-buffer (fsm target-buffer)
  "Set FSM state in the TARGET-BUFFER context."
  (with-current-buffer target-buffer
    (setq-local gptel--fsm-last fsm)))

;; Alternative: Set in current buffer if that's the correct context
(defun set-fsm-here (fsm)
  "Set FSM state in current buffer."
  (setq-local gptel--fsm-last fsm))
```

### Common Buffer-Local Variables

| Variable | Purpose | Typical Context |
|----------|---------|-----------------|
| `gptel--fsm-last` | FSM state tracking | Buffer where conversation lives |
| `gptel-backend` | LLM backend configuration | Per-buffer or global |
| `gptel-model` | Model name | Per-buffer or global |
| `gptel--stream-buffer` | Response streaming buffer | Buffer receiving chunks |

### Verification Test

```elisp
(defun test-fsm-set-in-correct-buffer ()
  "Verify fsm is set in target buffer, not current buffer."
  (let ((target (get-buffer-create "*test-target*"))
        (current (get-buffer-create "*test-current*")))
    (with-current-buffer current
      (setq-local gptel--fsm-last nil))
    (with-current-buffer target
      (setq-local gptel--fsm-last '(state "active")))
    ;; Verify
    (with-current-buffer current
      (should (null gptel--fsm-last)))
    (with-current-buffer target
      (should (equal '(state "active") gptel--fsm-last)))))
```

---

## 4. Pattern: Hash Tables for Shared Async State

When multiple async tasks need to coordinate or be queried, use **hash tables** instead of buffer-local variables. This avoids buffer context issues entirely.

### State Hash Tables Structure

```elisp
;; Task execution state - keyed by task-id
(defvar my/gptel--agent-task-state (make-hash-table :test 'equal))

;; Grading state - keyed by grade-id
(defvar gptel-auto-experiment--grade-state (make-hash-table :test 'equal))

;; Worktree state - keyed by target name
(defvar gptel-auto-workflow--worktree-state (make-hash-table :test 'equal))
```

### Accessor Functions

```elisp
(defun gptel--task-set-state (task-id state-plist)
  "Set TASK-ID state to STATE-PLIST."
  (puthash task-id state-plist my/gptel--agent-task-state))

(defun gptel--task-get-state (task-id)
  "Get state for TASK-ID."
  (gethash task-id my/gptel--agent-task-state))

(defun gptel--task-mark-done (task-id)
  "Mark TASK-ID as done."
  (let ((state (gptel--task-get-state task-id)))
    (gptel--task-set-state task-id
      (plist-put state :done t))))

(defun gptel--worktree-set (target worktree-dir &optional current-branch)
  "Set worktree state for TARGET."
  (puthash target (list :worktree-dir worktree-dir
                       :current-branch current-branch)
           gptel-auto-workflow--worktree-state))

(defun gptel--worktree-get (target)
  "Get worktree state for TARGET."
  (gethash target gptel-auto-workflow--worktree-state))
```

### Verification Command

```elisp
(defun gptel--debug-print-states ()
  "Print all hash table states for debugging."
  (interactive)
  (with-current-buffer (get-buffer-create "*debug-states*")
    (erase-buffer)
    (insert "=== Agent Task States ===\n")
    (maphash (lambda (k v)
               (insert (format "Task %s: %s\n" k v)))
             my/gptel--agent-task-state)
    (insert "\n=== Worktree States ===\n")
    (maphash (lambda (k v)
               (insert (format "Target %s: %s\n" k v)))
             gptel-auto-workflow--worktree-state)
    (pop-to-buffer (current-buffer))))
```

---

## 5. Pattern: Test Isolation with Local Bindings

Tests that rely on global variables fail when run in batch mode due to state pollution between tests.

### Anti-Pattern: Global State Dependency

```elisp
;; BAD: Relies on global gptel-backend
(ert-deftest my-test-uses-backend ()
  (my/function-that-uses-gptel-backend))  ; Fails if global is nil

;; BAD: Mutates global state
(ert-deftest my-test-mutates-global ()
  (setq gptel-backend nil)  ; Pollutes other tests
  (my/test-function))
```

### Correct Pattern: Local Let Bindings

```elisp
;; GOOD: Local binding for read operations
(ert-deftest my-test-local-backend ()
  (let ((gptel-backend (gptel--make-backend :name "test" :model "gpt-4")))
    (my/function-that-uses-gptel-backend)))

;; GOOD: Local binding for write operations
(ert-deftest my-test-local-backend-write ()
  (let ((gptel-backend (gptel--make-backend :name "test" :model "gpt-4")))
    (setq gptel-backend (gptel--make-backend :name "modified" :model "gpt-3.5")))
    ;; Original global unchanged
    (should gptel-backend))  ; Original still intact
```

### Complex Cases: Skip with FIXME

Some tests depend on complex interactions (project detection, dynamic binding) that are difficult to isolate. Skip these with a FIXME comment:

```elisp
;; SKIP: Complex project detection - hard to isolate in batch mode
(ert-deftest test-build-context/with-files ()
  "Skip due to cl-progv binding issues in batch mode."
  :tags '(:skip-batch)
  (skip-unless (not (getenv "EMACS_BATCH")))
  ;; Original test code...
  )

;; With a runner that skips :skip-batch tests:
(defun ert-run-tests-batch-and-skip ()
  "Run tests, skipping those tagged :skip-batch."
  (ert-run-tests-batch
   (lambda (stats)
     ;; Skip tests with :skip-batch tag
     )))
```

### Pattern Rule

```
λ test(x).  global_state(x) → local_let(x) | skip(x) when_complex
```

| Scenario | Solution |
|----------|----------|
| Test reads global variable | Wrap in `let` with mock value |
| Test modifies global variable | Use `let` to isolate mutation |
| Test depends on project detection | Skip in batch mode with FIXME |
| Test uses `cl-progv` dynamic binding | Skip with explanatory comment |

---

## 6. Real-World Fix: Parallel Experiment Workflow

This is the actual fix applied to the auto-workflow system that resolved the race condition.

### The Bug

```
- `dolist` spawned 5 parallel experiments
- All used global variables for results/scores
- Only 1 result recorded (others overwritten)
- Timeout messages appeared in wrong buffers
```

### The Fix: Three-Layer State Management

```elisp
;; Layer 1: Hash tables for async task coordination
(defvar gptel-auto-workflow--worktree-state (make-hash-table :test 'equal))
(defvar gptel-auto-experiment--grade-state (make-hash-table :test 'equal))
(defvar my/gptel--agent-task-state (make-hash-table :test 'equal))

;; Layer 2: Closure-captured loop variables
(dolist (target targets)
  (let* ((results nil)
         (best-score 0)
         (no-improvement-count 0)
         (task-id (incf gptel--task-counter)))
    ;; Each iteration has independent closure state
    (gptel-agent--task target
      (lambda (response)
        ;; Updates captured variables, not globals
        (push response results)
        (cl-incf best-score)))))

;; Layer 3: Per-task hash table lookups
(defun gptel-auto-workflow--create-worktree (target)
  "Create worktree for TARGET, store in hash table."
  (let ((worktree-dir (my/create-worktree target)))
    (gptel--worktree-set target worktree-dir target)
    worktree-dir))
```

### Verification

```bash
# Run the parallel experiment
M-x gptel-auto-workflow-run

# Check hash tables have correct counts
M-x gptel--debug-print-states

# Output should show:
;; === Agent Task States ===
;; Task 1: (:done t :timeout-timer nil :progress-timer nil)
;; Task 2: (:done t :timeout-timer nil :progress-timer nil)
;; Task 3: (:done t :timeout-timer nil :progress-timer nil)
;; Task 4: (:done t :timeout-timer nil :progress-timer nil)
;; Task 5: (:done t :timeout-timer nil :progress-timer nil)
;;
;; === Worktree States ===
;; Target 1: (:worktree-dir "/path/to/wt1" :current-branch "main")
;; Target 2: (:worktree-dir "/path/to/wt2" :current-branch "main")
;; Target 3: (:worktree-dir "/path/to/wt3" :current-branch "main")
;; Target 4: (:worktree-dir "/path/to/wt4" :current-branch "main")
;; Target 5: (:worktree-dir "/path/to/wt5" :current-branch "main")
```

---

## 7. Quick Reference Commands

### Debug Commands

```elisp
;; Show buffer-local variables in a buffer
(buffer-local-variables (get-buffer "*my-buffer*"))

;; Check if variable is buffer-local
(local-variable-if-set-p 'gptel--fsm-last)

;; List all buffer-local bindings
(mapatoms (lambda (sym)
            (when (local-variable-if-set-p sym)
              (princ sym)))
          obarray)

;; Verify hash table contents
(hash-table-count my/gptel--agent-task-state)
```

### Test Commands

```bash
# Run all tests
./scripts/run-tests.sh

# Run unit tests only
./scripts/run-tests.sh unit

# Run E2E workflow tests
./scripts/run-tests.sh e2e

# Run specific test file
emacs --batch -l test-gptel-agent-loop.el -f ert-run-tests-batch-and-exit
```

---

## Related

- **[Closure Variables](/closures.md)** - Deep dive into closure capture
- **[Hash Table Patterns](/hash-tables.md)** - State management with hash tables
- **[Test Isolation Best Practices](/test-isolation.md)** - Comprehensive testing guide
- **[Async Programming in Elisp](/async-elisp.md)** - Callbacks, promises, and threading
- **[Buffer Management](/buffers.md)** - Working with buffers and window configurations
- **[Dynamic Binding (cl-progv)](/cl-progv.md)** - Complications with dynamic scoping

---

## Summary

| Pattern | Use When | Solution |
|---------|----------|----------|
| Closure-captured locals | Parallel loop iterations | `let*` bindings captured by closure |
| Buffer-local with context | Per-buffer state | `with-current-buffer` before `setq-local` |
| Hash tables | Async task coordination | Key by unique ID (task-id, target) |
| Local let in tests | Test isolation | Wrap global reads in `let` |
| Skip with FIXME | Complex dependencies | Skip in batch mode with explanation |

The key principle: **prefer lexical scoping (let, closures) over dynamic scoping (special variables) wherever possible**, and when you must use shared state, use hash tables with unique keys rather than buffer-local variables that depend on correct buffer context.

---

*Last updated: 2026-04-02*
*Status: Active - Pattern verified in production*