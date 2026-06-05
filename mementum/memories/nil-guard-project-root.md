## Nil guard pattern for project-root

When `gptel-auto-workflow--project-root` could return nil (edge case), guard with early return of safe default `(cons t nil)`.

Pattern:
```elisp
(let ((proj-root (gptel-auto-workflow--project-root)))
  (if (not proj-root)
      (cons t nil)  ;; safe: can't check, assume safe
    ;; ... use proj-root ...
    ))
```

Also hoist `proj-root` outside loops — it's the same every iteration.
