# Prefer Real Modules Over Mocks in Tests

**Date**: 2026-03-29  
**Category**: Testing  
**Status**: Active Pattern  
**Related**: cl-letf, test-isolation, emacs-lisp

## Problem

Test files defining global mock functions caused 70 unexpected failures when all tests ran together in batch mode. Mocks shadowed real functions from other modules.

**Example**:
```elisp
;; BAD: Global mock shadows real function
(defun gptel-make-fsm (&rest args)
  "Mock that doesn't match real struct")

;; BAD: Test file pretends to be the module
(provide 'gptel-agent-tools)
```

## Solution

### 1. Require Real Modules

```elisp
(require 'ert)
(require 'cl-lib)
(require 'gptel)              ; Load real module
(require 'gptel-agent-tools)  ; Load real implementation
```

### 2. Use cl-letf for Local Mocking

```elisp
(ert-deftest test-example ()
  "Test with temporarily mocked function."
  (cl-letf (((symbol-function 'expensive-function)
             (lambda (arg) "mocked result")))
    ;; Test code here uses the mock
    (should (string= (expensive-function "input") "mocked result"))))
```

### 3. Namespace Test Helpers

```elisp
;; GOOD: Namespaced helper won't shadow real function
(defun test-myfile--helper-fn ()
  "Helper only for this test file.")
```

### 4. Mock Multiple Functions

```elisp
(ert-deftest test-with-multiple-mocks ()
  "Test mocking multiple functions and variables."
  (cl-letf (((symbol-function 'function-one) (lambda () "one"))
            ((symbol-function 'function-two) (lambda () "two"))
            (global-variable "mocked value"))
    ;; Both mocks active here
    (should (string= (function-one) "one"))))
```

## Examples from This Session

### test-nucleus-presets.el

Fixed by removing global mock and using cl-letf:

```elisp
;; Before: Global mock that shadows real function
(defun gptel-agent-read-file (file &optional _no-cache _register)
  "Mock implementation...")

;; After: Local mock with cl-letf
(ert-deftest test-nucleus-read-agent-model-from-yaml ()
  (cl-letf (((symbol-function 'gptel-agent-read-file)
             (lambda (file &optional _no-cache _register)
               (cond
                ((string-match-p "code_agent.md" file)
                 (list 'agent :name "nucleus-gptel-agent" 
                       :model "qwen3.5-plus"))
                (t nil))))
            ((symbol-function 'file-readable-p)
             (lambda (file) (string-match-p "code_agent.md" file))))
    (let ((model (nucleus--read-agent-model "/path/to/code_agent.md")))
      (should (eq model 'qwen3.5-plus)))))
```

### test-gptel-tools-apply.el (and similar)

Fixed by removing `(provide 'gptel-agent-tools)`:

```elisp
;; Before: Test file claims to be the module
(provide 'gptel-agent-tools)

;; After: Remove the provide, let real module load
;; Just load dependencies:
(provide 'gptel)
(provide 'gptel-ext-core)
(provide 'gptel-ext-fsm-utils)
```

## Key Insights

1. **Batch mode loads all test files**: Unlike running tests individually, `ert-run-tests-batch` loads all test files together, causing mock conflicts.

2. **`cl-letf` is lexical**: The mock only exists within the `cl-letf` body, preventing interference with other tests.

3. **`provide` is permanent**: Once a module is provided, `(require 'module)` won't load the real file. Test files must not provide modules they mock.

4. **Struct definitions must match**: Mock structs must have the same slots as real structs, or construction will fail with keyword argument errors.

## Validation

Run tests in two ways to verify fixes:

```bash
# Batch mode (catches isolation issues)
./scripts/run-tests.sh

# Individual file (should always pass)
emacs --batch -Q -L . -L lisp -L tests -l ert \
  -l tests/test-specific.el \
  --eval "(ert-run-tests-batch-and-exit t)"
```

## Results

Applying this pattern reduced test failures from 70 to 17 (76% improvement).

---

**Symbol**: 🔁  
**Mementum Tag**: #testing #mocks #cl-letf #batch-mode
