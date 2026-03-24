# Tests Pass in Isolation, Fail Together

## Problem

Tests pass when run individually but fail when run as part of the full test suite.

## Example

```bash
# Passes
emacs -l tests/test-gptel-agent-loop.el -f ert-run-tests-batch-and-exit
# Result: 18/18 pass

# Fails when run with full suite
./scripts/run-tests.sh
# Result: agent-loop tests fail
```

## Cause

Global state pollution between tests. A previous test modifies global variables or loads modules that affect later tests.

## Diagnosis

When tests fail in full suite but pass in isolation:
1. Check for global variable mutations
2. Check for `defvar` without `defvar-local`
3. Check for advice that persists
4. Check for `with-eval-after-load` side effects

## Solution Pattern

```elisp
;; Use let-bound local copies
(let ((some-global-var initial-value))
  ...)

;; Reset state in teardown
(teardown
 (setq some-global-var nil))

;; Use unwind-protect for cleanup
(unwind-protect
    (run-test)
  (cleanup))
```

## Symbol

λ isolation - tests should be independent