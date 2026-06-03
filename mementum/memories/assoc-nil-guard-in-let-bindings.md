## assoc nil-guard pattern: move dependent computations inside `when` guard

When `assoc` (or `gethash`) returns nil in a `let*` binding, any subsequent bindings
using `(car entry)` will crash before the `(when entry ...)` guard is reached.

**Anti-pattern:**
```elisp
(let* ((entry (assoc key alist :test))
       (rest (cl-remove (car entry) ...)))  ;; crash if entry is nil
  (when entry ...))                           ;; guard too late
```

**Fix:** Move the dependent computation inside the `when entry` body:
```elisp
(let* ((entry (assoc key alist :test)))
  (when entry
    (let ((rest (cl-remove (car entry) ...)))
      ...)))
```

Found in `gptel-tools-agent-error.el` — `gptel-auto-workflow--demote-backend-in-fallback-chain`.