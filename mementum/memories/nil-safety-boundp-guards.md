## Nil-Safety Pattern: boundp Guards for Global Variables

**Problem**: Functions accessing global variables without checking if they're bound cause `void-variable` errors during early initialization or when modules load out of order.

**Pattern**: Add `boundp` guards before accessing global variables:

```elisp
;; Before (unsafe):
(defun foo ()
  (>= some-global-count threshold))

;; After (safe):
(defun foo ()
  (and (boundp 'some-global-count)
       (>= some-global-count threshold)))
```

**For counters that need initialization**:
```elisp
(unless (boundp 'some-counter)
  (setq some-counter 0))
(setq some-counter (1+ some-counter))
```

**For values with safe defaults**:
```elisp
(let ((value (if (boundp 'some-var) some-var default-value)))
  ...)
```

**Evidence**: Applied to gptel-tools-agent-error.el, fixed 3 functions:
- `gptel-auto-experiment--retry-delay-seconds`: boundp guards for retry delay vars
- `gptel-auto-experiment--note-api-pressure`: initializes api-error-count if unbound
- `gptel-auto-experiment-should-stop-p`: returns nil when counter unbound

**Impact**: Prevents void-variable errors during bootstrap, improves φ Vitality by adapting to initialization order variations.