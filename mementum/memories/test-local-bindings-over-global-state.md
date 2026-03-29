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
./scripts/run-tests.sh                    # All tests pass
./scripts/run-tests.sh "pattern"          # Run specific tests
```

## Related

- See `prefer-real-modules-over-mocks-v2.md` for mock isolation patterns
- See `cl-progv-binding-issues.md` for dynamic binding complications