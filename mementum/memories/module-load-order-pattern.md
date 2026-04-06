# Module Load Order Pattern

**Date**: 2026-04-02
**Category**: pattern
**Related**: auto-workflow, requires, dependencies

## Pattern

Require modules before using their variables/functions.

## Problem

```elisp
;; ERROR: gptel--tool-preview-alist void
(gptel-agent--task ...)  ; Uses gptel--tool-preview-alist
```

## Root Cause

- Variable defined in `gptel.el`
- Function in `gptel-agent-tools.el` uses it
- If `gptel.el` not loaded, variable is void

## Solutions

### 1. Forward Declaration

```elisp
(defvar gptel--tool-preview-alist nil)  ; Forward declare
```

### 2. Require Dependencies

```elisp
(require 'gptel-request)
(require 'gptel-agent-tools)
```

### 3. Ensure Correct Load Order

```elisp
;; In run-auto-workflow-cron.sh:
(setq load-path (cons "." load-path))
(load-file "lisp/modules/gptel.el")
(load-file "lisp/modules/gptel-agent-tools.el")
```

## Common Dependencies

```
gptel → gptel-request → gptel-agent-tools → gptel-agent-tools
```

## Signal

- "Symbol's value as variable is void" → missing require/forward declaration
- Function works interactively but not programmatically → load order
- Works after manual require → missing dependency

## Best Practice

1. Use `require` for dependencies
2. Forward declare variables from other files
3. Document dependencies in comments
4. Test in clean Emacs instance