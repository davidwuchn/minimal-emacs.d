# Cron args-out-of-range Error Fix

**Date:** 2026-03-30
**Status:** ✅ Fixed

## Problem

Cron jobs were failing with error: `(args-out-of-range 1 0 7)`

This appeared in the Messages buffer as:
```
[auto-workflow] Cron error: (args-out-of-range 1 0 7)
```

## Root Cause

Multiple `substring` calls in `gptel-tools-agent.el` were trying to extract 7-character substrings from strings that could be empty or shorter than 7 characters:

1. **Line 114:** `(substring commit-hash 0 7)` - when git returns empty commit hash
2. **Line 142:** `(substring (car o) 0 7)` - when orphan hash is empty/short
3. **Lines 204-205:** `(substring staging-commit 0 7)` and `(substring main-commit 0 7)` - when branch commits are "none" or empty
4. **Lines 3414-3416:** Date parsing with `(substring date-str ...)` - when date format is malformed

## Solution

Added length guards before all substring operations:

```elisp
;; Before (would crash on short strings):
(substring commit-hash 0 7)

;; After (safe):
(if (>= (length commit-hash) 7)
    (substring commit-hash 0 7)
  commit-hash)
```

For date parsing, also added nil check for the computed age:
```elisp
;; Before:
(let* ((date-str (match-string 1 content))
       (last-tested (encode-time ...))
       (age (- now (float-time last-tested))))
  (when (> age four-weeks) ...))

;; After:
(let* ((date-str (match-string 1 content))
       (last-tested (when (>= (length date-str) 10)
                      (encode-time ...)))
       (age (when last-tested
              (- now (float-time last-tested)))))
  (when (and age (> age four-weeks)) ...))
```

## Files Modified

- `lisp/modules/gptel-tools-agent.el`
  - Lines 114, 142, 204-205, 3414-3416

## Verification

After fix, `gptel-auto-workflow-cron-safe` runs without errors:
```
[auto-workflow] Synced staging with main (origin/ -> 04948b5)
[auto-workflow] Found 3 orphan(s): 1 97974b8 97974b8
[auto-workflow] ⚠ Found 3 orphan commit(s) from previous run
```

**Symbol:** ❌ mistake → ✅ win
