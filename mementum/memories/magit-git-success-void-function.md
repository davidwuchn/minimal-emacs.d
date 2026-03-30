💡 magit-git-success-void-function

## Problem
During experiment execution, gptel callback failed with:
```
gptel callback error: (void-function magit-git-success)
```

## Root Cause
gptel callbacks run in a different buffer context where `magit-git` may not be loaded. The `declare-function` at the top of the file only tells the compiler about the function signature but doesn't actually load it.

## Fix
Add `(require 'magit-git)` at the top of the file to ensure the function is always available in any callback context.

## Key Insight
`declare-function` is for compile-time checking, not runtime loading. When callbacks run in different buffer contexts, they need all required features to be explicitly loaded.

## Files
- lisp/modules/gptel-tools-agent.el:11 - Added require