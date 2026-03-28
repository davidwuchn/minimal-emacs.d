# Advice Function Signature Mismatch

**Date:** 2026-03-28
**Source:** Fixing `gptel-workflow--tool-use-advice`

## Problem

Advice assumed wrong parameter structure:

```elisp
;; WRONG - assumed raw calls list
defun gptel-workflow--tool-use-advice (calls &rest _)
  (dolist (call calls)
    (alist-get 'name call)  ; Assumes alist
```

## Reality

`gptel--handle-tool-use` receives FSM object:

```elisp
(defun gptel--handle-tool-use (fsm)
  ;; FSM contains :tool-use plist with (:name ... :args ...)
```

## Fix

Advice must accept FSM and extract data:

```elisp
(defun gptel-workflow--tool-use-advice (fsm &rest _)
  (when-let* ((info (gptel-fsm-info fsm))
              (tool-use (plist-get info :tool-use)))
    (dolist (call tool-use)
      (let ((name (plist-get call :name))
            (args (plist-get call :args)))
        ...))))
```

## Lesson

Before advising functions:
1. Check actual function signature with `C-h f`
2. Look at function implementation
3. Verify data structures (plist vs alist vs cons)

## Related

- File: `lisp/modules/gptel-workflow-benchmark.el:148`
- gptel source: `gptel-request.el:1816`

**Symbol:** ❌ mistake | 💡 insight
