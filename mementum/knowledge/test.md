---
title: Testing Patterns for Emacs Lisp
status: active
category: knowledge
tags: [testing, ert, e2e, automation, debugging]
---

# Testing Patterns for Emacs Lisp

## Overview

Testing Emacs Lisp code requires understanding both ERT (Emacs Lisp Regression Testing) and the unique challenges of testing code that interacts with the Emacs runtime environment. This page synthesizes patterns learned from debugging test failures, shell command timeouts, and autonomous agent workflows.

## The Golden Rule: Test Helpers Must Match Real Implementation

### The Problem

Test helpers that don't mirror actual implementation behavior cause false failures. When the real code and test helper use different patterns, tests pass or fail based on the test infrastructure rather than the actual code.

### Concrete Example

**Real implementation** (`gptel-ext-retry.el`):
```elisp
(defun test--transient-error-p (error-data context)
  "Detect transient errors that warrant retry."
  (or (string-match-p "exit code 28\\|exit code 6\\|exit code 7" error-data)
      (string-match-p "curl: (28)\\|curl: (6)\\|curl: (7)" error-data)
      (string-match-p "timeout\\|connection refused" error-data)))
```

**Test helper** (sync with real implementation):
```elisp
(defun test--transient-error-p (error-data context)
  "Test helper must match gptel-ext-retry.el implementation exactly."
  (or (string-match-p "exit code 28\\|exit code 6\\|exit code 7" error-data)
      (string-match-p "curl: (28)\\|curl: (6)\\|curl: (7)" error-data)))
```

### Verification Pattern

Always verify test helpers match real code:
```elisp
;; Verify both patterns match
(should (test--transient-error-p "exit code 28" nil))      ; Should match
(should (test--transient-error-p "curl: (28)" nil))        ; Should match
(should-not (test--transient-error-p "exit code 0" nil))   ; Should NOT match
```

### Pattern Symbol

```
🔄 shift - test helper sync
```

---

## Test Isolation: Pass in Isolation, Fail Together

### The Problem

Tests that pass individually but fail when run together indicate **global state pollution**. One test modifies global variables, loads modules, or sets advice that affects subsequent tests.

### Diagnosis Checklist

When tests fail in full suite but pass in isolation:

| Check | Command/Method |
|-------|----------------|
| Global variable mutations | Grep for `setq.*gptel` in test files |
| `defvar` without `defvar-local` | Search for `^\s*(defvar\s+[^(]` |
| Persistent advice | Search for `advice-add` without cleanup |
| Side effects in `with-eval-after-load` | Review module loading hooks |

### Example Failure

```
signal(wrong-type-argument (gptel-backend nil))
```

**Root cause chain:**
1. Test A: `(setq gptel-backend nil)` in setup
2. Test B (runs later alphabetically): `(my/gptel--build-subagent-context ...)` reads `gptel-backend`
3. Test B fails because `gptel-backend` is nil

### Pattern Symbol

```
λ isolation - tests should be independent
```

---

## Pattern: Local Bindings Over Global State

### The Core Pattern

Replace global state dependencies with local `let` bindings. This makes tests self-contained and order-independent.

### Before (Fragile)

```elisp
(ert-deftest my-test-with-backend ()
  "This test relies on global gptel-backend - FRAGILE."
  (my/function-that-uses-gptel-backend))  ; May fail if global is nil
```

### After (Robust)

```elisp
(ert-deftest my-test-with-backend ()
  "This test provides its own local binding - ROBUST."
  (let ((gptel-backend (gptel--make-backend :name "test"
                                             :token "test-token"
                                             :models '("test-model"))))
    (my/function-that-uses-gptel-backend)))
```

### When to Use Local Binding

| Situation | Solution |
|-----------|----------|
| Function reads a global variable | Provide local `let` binding |
| Need mock behavior | Use `cl-letf` or `advice-add` |
| State needed across 
...[Result too large, truncated. Full result saved to: /Users/davidwu/.emacs.d/tmp/gptel-subagent-result-dk4sqY.txt. Use Read tool if you need more]...