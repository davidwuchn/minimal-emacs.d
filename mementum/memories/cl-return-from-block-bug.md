💡 cl-return-from-block-bug

## Problem

Emacs Lisp's `cl-return-from` requires a named `block`. `defun` does NOT create one - only `cl-defun` does.

## Silent Failure

When `cl-return-from` is used without a block, it causes a runtime error that silently fails. Callbacks are never called, experiments hang, workflows get stuck.

## Pattern to Avoid

```elisp
;; BAD - cl-return-from without block
(defun foo ()
  (when condition
    (cl-return-from foo nil)))  ; ERROR: no block!

;; GOOD - with cl-block wrapper
(defun foo ()
  (cl-block foo
    (when condition
      (cl-return-from foo nil))))

;; GOOD - use if-else instead
(defun foo ()
  (if condition
      nil
    (do-other-thing)))
```

## Fixed Functions

| File | Function |
|------|----------|
| gptel-tools-agent.el | gptel-auto-experiment-grade |
| gptel-tools-agent.el | my/gptel-agent--task-override |
| gptel-benchmark-instincts.el | gptel-benchmark-instincts-commit-batch |
| gptel-benchmark-memory.el | gptel-benchmark-memory-create |
| gptel-ext-context-cache.el | my/gptel--estimate-text-tokens |
| gptel-ext-context.el | my/gptel-auto-compact callback |

## Detection

```bash
grep -rn "cl-return-from\|cl-return" lisp/modules/*.el | grep -v "cl-defun"
```

Check if the function uses `defun` (not `cl-defun`) and has `cl-return-from`.