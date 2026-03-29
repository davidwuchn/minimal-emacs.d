# Dir-locals Safety Fix

**Date**: 2026-03-29

**Problem**: Emacs kept prompting about dir-locals safety even though variables were marked safe.

**Root Cause**: For complex types (lists, specific values), Emacs requires the EXACT values to be listed in `safe-local-variable-values`, not just `(var . t)`.

**Solution**: Explicitly mark exact values:

```elisp
(add-to-list 'safe-local-variable-values
             '(gptel-auto-workflow-targets
               "lisp/modules/gptel-tools-agent.el"
               "lisp/modules/gptel-auto-workflow-strategic.el"
               "lisp/modules/gptel-benchmark-core.el"))
(add-to-list 'safe-local-variable-values
             '(gptel-auto-experiment-max-per-target . 5))
;; ... etc
```

**Commit**: 26f356c
