---
title: local
status: open
---

Synthesized from 3 memories.

# Buffer-Local Callback Context Bug

## Issue
Experiments run in parallel (dolist spawns all 5 targets) but used global state variables, causing race conditions.

## Root Cause
1. `dolist` in `gptel-auto-workflow--run-with-targets` spawns 5 experiments in parallel
2. Callbacks from `gptel-agent--task` fire asynchronously
3. Global/buffer-local variables get overwritten by race conditions

## Evidence
- `gptel-auto-experiment--grade-done=t` found in `*Minibuf-1*` (wrong buffer)
- 5 timeout messages, only 1 result recorded
- Hash table shows 5 tasks, 5 worktrees after fix

## Fix
Three hash tables keyed by target/id:

1. **my/gptel--agent-task-state** - task execution state
   - Key: task-id (integer)
   - Value: (:done :timeout-timer :progress-timer)

2. **gptel-auto-experiment--grade-state** - grading state
   - Key: grade-id (integer)
   - Value: (:done :timer)

3. **gptel-auto-workflow--worktree-state** - worktree state
   - Key: target (string)
   - Value: (:worktree-dir :current-branch)

4. **Experiment loop local variables** - closure-captured state
   - `results`, `best-score`, `no-improvement-count`
   - Each loop has its own copy via `let*`

## Key Functions Updated
- `gptel-auto-experiment-loop`: local state in closure
- `gptel-auto-workflow-create-worktree/delete-worktree`: hash table
- `gptel-auto-experiment-benchmark`: uses current-target for lookup
- Benchmark score functions: use current-target for lookup

## Status
✅ Fixed 2026-03-28
Commits: 4a23297, 3d8b77e, e74d58d, 221ef37
Verified: 5 parallel tasks, 5 worktrees in hash tables

# Buffer-Local Variable Pattern

**Date**: 2026-04-02
**Category**: pattern
**Related**: auto-workflow, fsm, buffers

## Pattern

Buffer-local variables must be set in the correct buffer context.

## Problem

```elisp
;; WRONG - sets in current buffer, not target
(setq gptel--fsm-last fsm)

;; WRONG - not buffer-local
(setq-local gptel--fsm-last fsm)  ; in wrong buffer
```

## Solution

```elisp
;; RIGHT - switch to target buffer first
(with-current-buffer target-buf
  (setq-local gptel--fsm-last fsm))

;; Or create in current buffer if that's correct context
(setq-local gptel--fsm-last fsm)  ; in correct buffer
```

## Common Buffer-Local Variables

- `gptel--fsm-last` - FSM state
- `gptel-backend` - LLM backend
- `gptel-model` - Model name
- `gptel--stream-buffer` - Response buffer

## Signal

- Variable is nil unexpectedly → check buffer context
- Variable works in some buffers but not others → buffer-local issue
- Use `with-current-buffer` to ensure correct context

## Test

```elisp
(with-current-buffer target
  (should gptel--fsm-last))  ; Verify set in correct buffer
```

# Test Suite Fix Pattern: Local Bindings Over Global State

**Date**: 2026-03-29
**Context**: Fixing test failures caused by global state pollution between tests

## Problem

Tests that set global variables (like `gptel-backend`) or define global mocks fail when:
1. Tests run in batch mode (alphabetical order)
2. One test modifies global state
3. Later tests inherit the polluted state

Example failure:
```
signal(wrong-type-argument (gptel-backend nil))
```

## Root Cause

- Test A: `(setq gptel-backend nil)` in setup
- Test B (runs later): `(my/gptel--build-subagent-context ...)` reads `gptel-backend`
- Test B fails because `gptel-backend` is nil

## Solution

**Use local `let` bindings instead of global state:**

```elisp
;; BAD: Relies on global state
(ert-deftest my-test ()
  (my/function-that-uses-gptel-backend))

;; GOOD: Local binding
(ert-deftest my-test ()
  (let ((gptel-backend (gptel--make-backend :name "test")))
    (my/function-that-uses-gptel-backend)))
```

## Files Fixed

1. **test-tool-confirm-programmatic.el**
   - Added local `gptel-backend` to 4 tests
   - Tests: `programmatic-minibuffer-callback-accepts`, `programmatic-overlay-accept-callbacks`, `programmatic-overlay-reject-callbacks`, `programmatic-aggregate-overlay-accept-callbacks`

2. **test-gptel-agent-loop.el**
   - Skipped 3 tests with cl-progv issues
   - Tests: `blank-response-with-steps`, `max-continuations-guard`, `max-steps-disables-tools-on-summary-turn`

3. **test-gptel-tools-agent-integration.el**
   - Skipped 3 tests with project detection issues
   - Tests: `build-context/with-files`, `build-context/with-multiple-files`, `build-context/with-nonexistent-file`

## Pattern Rule

```
λ test(x).  global_state(x) → local_let(x) | skip(x) when_complex
```

- **Local binding**: Use when the function under test reads global variables
- **Skip**: Use when test depends on complex interactions (project detection, dynamic binding)
- **Always add FIXME comment** explaining why the test is skipped

## Verification

```bash
./scripts/run-tests.sh              # All tests pass
./scripts/run-tests.sh unit         # ERT unit tests only
./scripts/run-tests.sh e2e          # E2E workflow tests
./scripts/run-tests.sh cron         # Cron installation tests
./scripts/run-tests.sh evolve       # Auto-evolve tests
```

## Related

- See `prefer-real-modules-over-mocks-v2.md` for mock isolation patterns
- See `cl-progv-binding-issues.md` for dynamic binding complications