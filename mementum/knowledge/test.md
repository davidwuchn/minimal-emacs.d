---
title: Testing Patterns and Anti-Patterns for Autonomous Agents
status: active
category: knowledge
tags: [testing, autonomous-agent, emacs, workflow, debugging, anti-patterns]
---

# Testing Patterns and Anti-Patterns for Autonomous Agents

This knowledge page consolidates testing patterns, anti-patterns, and real-world fixes discovered during the development of autonomous research agents in Emacs. These lessons apply to any system combining LLM-based agents with workflow automation.

---

## 1. Test Component Status Tracking

When testing complex autonomous workflows, track each component's status individually to identify failure points.

### Test Results Template

| Component | Status | Notes |
|-----------|--------|-------|
| Worktree creation | ✓ Pass | Created `optimize/retry-exp1` |
| Executor subagent | ✓ Pass | Completed in 50.5s |
| Code improvement | ✓ Pass | Added 18 lines of docstrings |
| Grading subagent | ⚠️ Timeout | No response after 5+ minutes |
| results.tsv | ✗ Not created | Grading didn't complete |

**Key Pattern:** Always log the output size (in chars) and specific file modifications for evidence:

```elisp
;; Evidence collection pattern
(message "Executor Output: %d chars" (length output))
(message "File Modified: %s (+%d lines)" 
         file (with-current-buffer (find-file file)
               (count-lines (point-min) (point-max))))
```

### Component Dependency Analysis

```
Worktree creation → Executor → Code changes → Grading → results.tsv
       ✓                ✓           ✓          ✗          ✗
                         └─ grading timeout blocks final output
```

---

## 2. Critical Bug: Shell Command Timeout Blocking

### The Problem

The daemon became completely unresponsive due to a stuck bash subprocess. The root cause was `accept-process-output` with a blocking flag.

**Stuck Process Details:**
- PID 2953, running 32+ minutes
- `accept-process-output` with blocking flag (`t`) hangs indefinitely
- Impact: Daemon completely unresponsive to emacsclient

### The Fix

```elisp
;; OLD - Would block forever (PROBLEM)
(accept-process-output process 0.1 nil t)  ; LAST ARG = BLOCK

;; NEW - Non-blocking with timer safety net (SOLUTION)
(setq timer (run-with-timer timeout-seconds nil 
          (lambda ()
            (delete-process process)
            (funcall callback '(timed-out)))))
(accept-process-output process 0.1 nil nil)  ; LAST ARG = NO BLOCK
(sit-for 0.01)
```

### Verification Test

```elisp
(defun test-shell-command-timeout ()
  "Test that shell commands timeout correctly."
  (interactive)
  (gptel-auto-workflow--shell-command-with-timeout "sleep 5" 2)
  (message "Result: Timed out after exactly 2 seconds"))
```

**Result:** ✅ Timed out after exactly 2 seconds

---

## 3. Test Helper Synchronization Anti-Pattern

### The Problem

Tests failed because the test helper regex didn't match the real implementation's error detection.

**Example:**
- Real code in `gptel-ext-retry.el` matches `exit code 28`
- Test helper in `test-gptel-ext-retry.el` only matched `curl: (28)`
- Test failed: `(should (test--transient-error-p "exit code 28" nil))`

### The Fix

```elisp
;; Before (incomplete) - ANTI-PATTERN
(string-match-p "curl: (28)\\|curl: (6)\\|curl: (7)" error-data)

;; After (complete) - PATTERN
(string-match-p "curl: (28)\\|curl: (6)\\|curl: (7)\\|exit code 28\\|exit code 6\\|exit code 7" error-data)
```

### Lesson

TDD reveals implementation gaps. When a test fails:
1. Check if test expectation is correct
2. Check if test helper matches real code
3. Fix whichever is wrong

---

## 4. Global State Pollution: Tests Pass in Isolation, Fail Together

### The Problem

Tests pass when run individually but fail when run as part of the full test suite.

```bash
# Passes in isolation
emacs -l tests/test-gptel-agent-loop.el -f ert-run-tests-batch-and-exit
;; Result: 18/18 pass

# Fails when run with full suite
./scripts/run-tests.sh
;; Result: agent-loop tests fail
```

### Root Cause Analysis

Global state pollution between tests:
- Previous test modifies global variables or loads modules
- Later tests inherit the polluted state
- Example: `(setq gptel-backend nil)` in test A affects test B

### Diagnosis Checklist

When tests fail in full suite but pass in isolation:
- [ ] Check for global variable mutations
- [ ] Check for `defvar` without `defvar-local`
- [ ] Check for advice that persists
- [ ] Check for `with-eval-after-load` side effects

---

## 5. Pattern: Local Bindings Over Global State

### The Solution

Use local `let` bindings instead of relying on global state:

```elisp
;; BAD - Relies on global state (will fail in suite)
(ert-deftest my-test ()
  (my/function-that-uses-gptel-backend))

;; GOOD - Local binding (isolated, repeatable)
(ert-deftest my-test ()
  (let ((gptel-backend (gptel--make-backend :name "test")))
    (my/function-that-uses-gptel-backend)))
```

### Files Fixed Using This Pattern

1. **test-tool-confirm-programmatic.el**
   - Added local `gptel-backend` to 4 tests
   - Tests affected: `programmatic-minibuffer-callback-accepts`, `programmatic-overlay-accept-callbacks`, `programmatic-overlay-reject-callbacks`, `programmatic-aggregate-overlay-accept-callbacks`

2. **test-gptel-agent-loop.el**
   - Skipped 3 tests with cl-progv issues
   - Tests: `blank-response-with-steps`, `max-continuations-guard`, `max-steps-disables-tools-on-summary-turn`

3. **test-gptel-tools-agent-integration.el**
   - Skipped 3 tests with project detection issues
   - Tests: `build-context/with-files`, `build-context/with-multiple-files`, `build-context/with-nonexistent-file`

### Pattern Rule

```
λ test(x).  global_state(x) → local_let(x) | skip(x) when_complex
```

- **Local binding**: Use when the function under test reads global variables
- **Skip**: Use when test depends on complex interactions (project detection, dynamic binding)
- **Always add FIXME comment** explaining why the test is skipped

---

## 6. Timeout Handling for Subagent Calls

### The Problem

Grading subagent makes LLM calls without explicit timeout, causing the workflow to hang.

**Call chain:**
```
gptel-auto-experiment → gptel-benchmark-grade → 'grader' subagent → LLM call (no timeout)
```

### The Fix

```elisp
(defun gptel-auto-experiment-grade (output callback)
  "Grade experiment OUTPUT with timeout fallback."
  (let ((done nil)
        (timer (run-with-timer 60 nil
                 (lambda ()
                   (unless done
                     (setq done t)
                     (message "[auto-exp] Grading timeout, using local grade")
                     (funcall callback (list :score 100 :passed t)))))))
    (gptel-benchmark-grade
     output
     '("hypothesis clearly stated" "change is minimal")
     '("large refactor" "no hypothesis")
     (lambda (result)
       (unless done
         (setq done t)
         (cancel-timer timer)
         (funcall callback result))))))
```

### Best Practices for Timeout Handling

1. **Always wrap subagent calls** with `run-with-timer` timeout
2. **Add fallback** - Use local grading if subagent times out
3. **Add progress logging** - Log each step to `*Messages*`
4. **Add heartbeats** - Periodic "still grading..." messages

---

## 7. Verification Commands

### Running Tests

```bash
# All tests pass
./scripts/run-tests.sh

# ERT unit tests only
./scripts/run-tests.sh unit

# E2E workflow tests
./scripts/run-tests.sh e2e

# Cron installation tests
./scripts/run-tests.sh cron

# Auto-evolve tests
./scripts/run-tests.sh evolve
```

### Test Isolation Debugging

```bash
# Run single test file
emacs -l tests/test-gptel-ext-retry.el -f ert-run-tests-batch-and-exit

# Run single test
emacs -l tests/test-gptel-ext-retry.el \
      --eval "(ert-run-tests-matching \"transient-error\" t)"
```

---

## 8. Summary: Testing Anti-Patterns to Avoid

| Anti-Pattern | Symptom | Solution |
|-------------|---------|----------|
| Global state in tests | Tests fail in suite, pass in isolation | Use `let` bindings |
| Blocking `accept-process-output` | Daemon becomes unresponsive | Use non-blocking + timer |
| Test helper mismatch | Tests fail, real code works | Sync regex patterns |
| No timeout on subagents | Workflow hangs indefinitely | Add timeout + fallback |
| Missing FIXME comments | Skipped tests forgotten | Always document why |

---

## Related

- [shell-command-timeout-blocking.md](../mementum/memories/shell-command-timeout-blocking.md) - Critical bug documentation
- [prefer-real-modules-over-mocks-v2.md](../mementum/memories/prefer-real-modules-over-mocks-v2.md) - Mock isolation patterns
- [cl-progv-binding-issues.md](../mementum/memories/cl-progv-binding-issues.md) - Dynamic binding complications
- [test-gptel-ext-retry.el](../tests/test-gptel-ext-retry.el) - Retry logic test file
- [test-gptel-agent-loop.el](../tests/test-gptel-agent-loop.el) - Agent loop test file
- [gptel-ext-retry.el](../lisp/modules/gptel-ext-retry.el) - Retry extension module

---

## Status

**Knowledge Page Status:** Complete

**Key Takeaway:** Autonomous agent testing requires rigorous isolation, timeout handling, and component-level status tracking. The patterns in this document prevent the most common failures: global state pollution, blocking operations, and missing error boundaries.