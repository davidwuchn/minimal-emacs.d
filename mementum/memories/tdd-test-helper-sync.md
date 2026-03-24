# Test Helper Must Match Real Implementation

## Context

Running tests for curl timeout detection (`retry/curl-timeout/exit-code-28`) failed because test helper didn't match real implementation.

## Problem

- Real code in `gptel-ext-retry.el` matches `exit code 28`
- Test helper in `test-gptel-ext-retry.el` only matched `curl: (28)`
- Test failed: `(should (test--transient-error-p "exit code 28" nil))`

## Solution

Sync test helper regex with real implementation:

```elisp
;; Before (incomplete)
(string-match-p "curl: (28)\\|curl: (6)\\|curl: (7)" error-data)

;; After (complete)
(string-match-p "curl: (28)\\|curl: (6)\\|curl: (7)\\|exit code 28\\|exit code 6\\|exit code 7" error-data)
```

## Lesson

TDD reveals implementation gaps. When test fails:
1. Check if test expectation is correct
2. Check if test helper matches real code
3. Fix whichever is wrong

## Symbol

🔄 shift - test helper sync